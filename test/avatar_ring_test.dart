import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/git.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// Contract for the branch-coloured avatar (승인된 3안).
///
/// A commit's disc is its branch line, all the way through: a ring at the
/// rail's own weight, the same colour dimmed inside it, and the initials in
/// that colour too. One branch reads as one thing down the column — and a
/// photo, which used to hide the branch entirely, now sits inside the ring.
void main() {
  const ada = GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com');

  BoxDecoration discOf(WidgetTester tester, {int at = 0}) =>
      tester
              .widget<Container>(
                find
                    .descendant(
                      of: find.byType(IdentityAvatar),
                      matching: find.byType(Container),
                    )
                    .at(at),
              )
              .decoration!
          as BoxDecoration;

  testWidgets('a photo keeps the branch ring around it', (tester) async {
    final branch = AvatarService.branchColor(3);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: IdentityAvatar(
            identity: ada,
            discColor: branch,
            remoteAvatar: const RemoteAvatar(
              login: 'ada',
              url: 'https://example.com/ada.png',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final disc = discOf(tester);
    expect((disc.border! as Border).top.color, branch);
    expect(
      (disc.border! as Border).top.width,
      CommitGraphPainter.railWidth,
      reason: '링은 레일과 같은 두께다',
    );
    // The photo is fetched and clipped inside the ring. Whether it arrives is
    // the network's business — a failed one still falls back to the initials,
    // so this asserts the ring, not the absence of a face.
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the ring leaves room for two glyphs inside it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: IdentityAvatar(
            identity: ada,
            size: CommitGraphPainter.avatarDiameter,
            discColor: AvatarService.branchColor(1),
          ),
        ),
      ),
    );
    await tester.pump();

    // Two capitals must fit the ringed interior, not the whole disc. The test
    // font draws every glyph as wide as it is tall, which is the widest any
    // face gets, so passing here passes with a real one.
    final glyphs = tester.getSize(find.text('AL'));
    expect(
      glyphs.width,
      lessThanOrEqualTo(
        CommitGraphPainter.avatarDiameter - CommitGraphPainter.railWidth * 2,
      ),
      reason: '이니셜이 링을 넘어 그려지면 안 된다',
    );
  });

  testWidgets('a photo that never arrives still shows who committed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: IdentityAvatar(
            identity: ada,
            discColor: AvatarService.branchColor(3),
            remoteAvatar: const RemoteAvatar(
              login: 'ada',
              url: 'https://example.com/gone.png',
            ),
          ),
        ),
      ),
    );
    // Widget tests answer every request with a failure, which is the same
    // thing a 404 avatar is: the disc falls back to the initials rather than
    // going blank, and the ring stays either way.
    await tester.pumpAndSettle();

    expect(find.text('AL'), findsOneWidget);
    expect((discOf(tester).border! as Border).top.color, isNotNull);
  });

  testWidgets('a row draws the disc in its own branch colour', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: WindowFrameController(
            channel: const MethodChannel('test/yogit-window'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    final branch = AvatarService.branchColor(painter.row.branch);

    final disc = discOf(tester);
    expect((disc.border! as Border).top.color, branch);
    expect(disc.color!.a, lessThan(1.0));
    expect(tester.widget<Text>(find.text('AA').first).style?.color, branch);
  });

  testWidgets('a stacked author and committer share one branch ring', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit(
                '1',
                'first commit',
                committer: const GitIdentity(
                  name: 'Cam Committer',
                  email: 'cam@example.com',
                ),
              ),
            ],
          ),
          controller: WindowFrameController(
            channel: const MethodChannel('test/yogit-window'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    final branch = AvatarService.branchColor(painter.row.branch);
    // Both discs of the stack wear the same ring, so the pair reads as one
    // commit on one branch rather than two unrelated marks.
    expect(find.byType(IdentityAvatar), findsNWidgets(2));
    for (final at in const [0, 1]) {
      expect((discOf(tester, at: at).border! as Border).top.color, branch);
    }
  });
}
