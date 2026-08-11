import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// 앱이 스스로 저장소를 바꾸면 그 사실을 아는 곳이 둘이 된다: 그 일을 시킨 코드와,
/// 저장소가 밖에서 바뀌었는지 지켜보는 감시자. 둘 다 말하면 사용자는 같은 문장을
/// 두 번 읽는다.
class _WatchedRepository extends FakeGitRepository {
  _WatchedRepository(super.loader, {required super.refs});

  /// 브랜치가 사라지기 전과 후의 지문. 삭제가 이 값을 바꾼다.
  var signature =
      'main-tip\nrefs/heads/main\nrefs/heads/main main-tip\nrefs/heads/gone gone-tip';

  /// 재적재를 붙잡아 둘 손잡이 — 앱이 저장소를 만지는 중에 감시자가 깨어나는
  /// 순간을 시험이 직접 만든다.
  Completer<void>? hold;

  @override
  Future<String?> loadLocalStateSignature() async => signature;

  @override
  Future<void> deleteLocalBranch(String branch) async {
    signature = 'main-tip\nrefs/heads/main\nrefs/heads/main main-tip';
  }

  @override
  Future<void> checkoutLocalBranch(String branch) async {
    signature =
        'gone-tip\nrefs/heads/$branch\n'
        'refs/heads/main main-tip\nrefs/heads/gone gone-tip';
  }

  @override
  Future<List<GitCommit>> loadHistory({
    int limit = 200,
    int skip = 0,
    Set<String> hiddenTips = const {},
  }) async {
    await hold?.future;
    return super.loadHistory(limit: limit, skip: skip, hiddenTips: hiddenTips);
  }
}

void main() {
  testWidgets('a branch the app deleted is announced once', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = _WatchedRepository(
      (_, _) async => [
        commit('main-tip', 'tip', parents: ['root']),
        commit('root', 'root'),
      ],
      refs: const RepoRefs(
        local: ['main', 'gone'],
        current: 'main',
        tips: {'main': 'main-tip', 'gone': 'gone-tip'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: WindowFrameController(
            channel: const MethodChannel('test/yogit-window'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 삭제를 시작하고, 재적재가 끝나기 전에 감시자를 깨운다. 실제로도 ref 파일이
    // 지워지는 순간 파일 감시자가 깨어나므로 이 사이가 열려 있다.
    final hold = Completer<void>();
    repository.hold = hold;
    await tester.tap(find.byKey(const Key('sidebar-row-gone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-branch-confirm')));
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    hold.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('gone 브랜치 삭제됨'), findsOneWidget);

    // 스낵바는 한 번에 하나만 서고 나머지는 줄을 선다. 첫 것이 물러난 뒤에도 같은
    // 문장이 또 서면, 삭제를 시킨 쪽과 감시자가 같은 말을 나눠 한 것이다.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('gone 브랜치 삭제됨'),
      findsNothing,
      reason: '같은 말을 두 번 하지 않는다',
    );
  });

  testWidgets('a checkout the app ran is announced once', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = _WatchedRepository(
      (_, _) async => [
        commit('main-tip', 'tip', parents: ['root']),
        commit('root', 'root'),
      ],
      refs: const RepoRefs(
        local: ['main', 'gone'],
        current: 'main',
        tips: {'main': 'main-tip', 'gone': 'gone-tip'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: WindowFrameController(
            channel: const MethodChannel('test/yogit-window'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hold = Completer<void>();
    repository.hold = hold;
    await tester.tap(find.byKey(const Key('sidebar-row-gone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar-action-checkout')));
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    hold.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('gone 체크아웃'), findsOneWidget);
    // 체크아웃은 HEAD를 옮기므로 감시자에게는 밖에서 벌어진 일처럼 보인다. 앱이
    // 시킨 일을 두고 "새로 읽어올까요?"를 묻는 것은 같은 말을 두 번 하는 것보다
    // 더 성가시다.
    expect(find.text('저장소가 바뀌었습니다'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('저장소가 바뀌었습니다'), findsNothing);
    expect(
      find.textContaining('gone 체크아웃'),
      findsNothing,
      reason: '체크아웃도 시킨 쪽과 감시자가 나눠 말하면 안 된다',
    );
  });
}
