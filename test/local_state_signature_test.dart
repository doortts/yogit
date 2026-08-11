import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/local_state_signature.dart';

/// The fingerprint `loadLocalStateSignature` builds: HEAD's commit, HEAD's
/// symbolic name, then one `refname sha` line per local branch.
String signature(String headCommit, String headRef, Map<String, String> tips) =>
    [
      headCommit,
      headRef,
      for (final entry in tips.entries) 'refs/heads/${entry.key} ${entry.value}',
    ].join('\n');

void main() {
  _movedBranchDetail();
  _movedBranchLine();
  group('parse', () {
    test('reads HEAD and every branch tip while sitting on a branch', () {
      final state = parseLocalState(
        signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'bbb'}),
      );

      expect(state.headCommit, 'aaa');
      expect(state.headRef, 'refs/heads/main');
      expect(state.detached, isFalse);
      expect(state.currentBranch, 'main');
      expect(state.branchTips, {'main': 'aaa', 'work': 'bbb'});
    });

    test('a detached HEAD has no current branch', () {
      final state = parseLocalState(
        signature('aaa', 'HEAD', {'main': 'bbb'}),
      );

      expect(state.detached, isTrue);
      expect(state.currentBranch, isNull);
      expect(state.branchTips, {'main': 'bbb'});
    });

    test('a repository with no local branch parses to an empty tip map', () {
      final state = parseLocalState(signature('aaa', 'HEAD', const {}));

      expect(state.headCommit, 'aaa');
      expect(state.branchTips, isEmpty);
    });

    test('a slash in a branch name stays part of the name', () {
      final state = parseLocalState(
        signature('aaa', 'refs/heads/codex/outline-parity', {
          'codex/outline-parity': 'aaa',
          'demo/conflict/sample': 'ccc',
        }),
      );

      expect(state.currentBranch, 'codex/outline-parity');
      expect(state.branchTips, {
        'codex/outline-parity': 'aaa',
        'demo/conflict/sample': 'ccc',
      });
    });

    test('a fingerprint git could not fill in does not throw', () {
      expect(parseLocalState('').branchTips, isEmpty);
      expect(parseLocalState('').headCommit, '');
    });
  });

  group('diff', () {
    LocalStateChange change(String before, String after) =>
        diffLocalState(parseLocalState(before), parseLocalState(after));

    test('an identical fingerprint reports nothing at all', () {
      final result = change(
        signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
        signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
      );

      expect(result.isEmpty, isTrue);
      expect(result.isPureDeletion, isFalse);
    });

    test('branches that vanished are a pure deletion', () {
      final result = change(
        signature('aaa', 'refs/heads/main', {
          'main': 'aaa',
          'work': 'bbb',
          'spike': 'ccc',
        }),
        signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
      );

      expect(result.removed, ['spike', 'work']);
      expect(result.added, isEmpty);
      expect(result.moved, isEmpty);
      expect(result.headCommitMoved, isFalse);
      expect(result.headRefChanged, isFalse);
      expect(result.isPureDeletion, isTrue);
    });

    test('a branch that appeared is not a deletion', () {
      final result = change(
        signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
        signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'bbb'}),
      );

      expect(result.added, ['work']);
      expect(result.removed, isEmpty);
      expect(result.isPureDeletion, isFalse);
    });

    test('a tip that moved names where it was and where it went', () {
      final result = change(
        signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'bbb'}),
        signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'ddd'}),
      );

      expect(result.moved, [(branch: 'work', before: 'bbb', after: 'ddd')]);
      expect(result.isPureDeletion, isFalse);
    });

    test('a checkout onto another branch moves HEAD without touching a tip', () {
      final result = change(
        signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'bbb'}),
        signature('bbb', 'refs/heads/work', {'main': 'aaa', 'work': 'bbb'}),
      );

      expect(result.headRefChanged, isTrue);
      expect(result.headCommitMoved, isTrue);
      expect(result.moved, isEmpty);
      expect(result.isPureDeletion, isFalse);
    });

    test('a deletion that also moved HEAD is not a pure deletion', () {
      final result = change(
        signature('bbb', 'refs/heads/work', {'main': 'aaa', 'work': 'bbb'}),
        signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
      );

      expect(result.removed, ['work']);
      expect(result.headRefChanged, isTrue);
      expect(result.isPureDeletion, isFalse);
    });

    test('losing the branch HEAD still names is never a pure deletion', () {
      // Git will not let this happen from a checkout, but a worktree edit or a
      // hand-written HEAD can leave the ref pointing at nothing.
      final result = change(
        signature('bbb', 'refs/heads/work', {'main': 'aaa', 'work': 'bbb'}),
        signature('bbb', 'refs/heads/work', {'main': 'aaa'}),
      );

      expect(result.removed, ['work']);
      expect(result.headRefChanged, isFalse);
      expect(result.headCommitMoved, isFalse);
      expect(result.isPureDeletion, isFalse);
    });

    test('a deletion beside a moved tip still deserves the question', () {
      final result = change(
        signature('aaa', 'refs/heads/main', {
          'main': 'aaa',
          'work': 'bbb',
          'spike': 'ccc',
        }),
        signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'ddd'}),
      );

      expect(result.removed, ['spike']);
      expect(result.moved, [(branch: 'work', before: 'bbb', after: 'ddd')]);
      expect(result.isPureDeletion, isFalse);
    });
  });

  group('summary', () {
    String? summarize(String before, String after) => localStateChangeSummary(
      diffLocalState(parseLocalState(before), parseLocalState(after)),
    );

    test('nothing changed says nothing', () {
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
          signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
        ),
        isNull,
      );
    });

    test('a handful of deleted branches are named', () {
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', {
            'main': 'aaa',
            'work': 'bbb',
            'spike': 'ccc',
          }),
          signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
        ),
        'spike, work 브랜치 삭제됨',
      );
    });

    test('too many deleted branches to name become a count', () {
      final before = {
        'main': 'aaa',
        for (var i = 0; i < 15; i++) 'gone-$i': 'b$i',
      };
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', before),
          signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
        ),
        '브랜치 15개 삭제됨',
      );
    });

    test('an added branch is named the same way', () {
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
          signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'bbb'}),
        ),
        'work 브랜치 추가됨',
      );
    });

    test('many added branches degrade to a count too', () {
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
          signature('aaa', 'refs/heads/main', {
            'main': 'aaa',
            for (var i = 0; i < 6; i++) 'new-$i': 'b$i',
          }),
        ),
        '브랜치 6개 추가됨',
      );
    });

    test('a moved tip reads as an update', () {
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'bbb'}),
          signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'ddd'}),
        ),
        'work 브랜치 갱신됨',
      );
    });

    test('a checkout names the branch the way the app already does', () {
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', {'main': 'aaa', 'work': 'bbb'}),
          signature('bbb', 'refs/heads/work', {'main': 'aaa', 'work': 'bbb'}),
        ),
        'work 체크아웃',
      );
    });

    test('a detached HEAD says so instead of naming a branch', () {
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
          signature('bbb', 'HEAD', {'main': 'aaa'}),
        ),
        'HEAD 분리됨',
      );
    });

    test('a commit on the checked-out branch reads as one update, not two', () {
      // The tip line already says the branch moved, so repeating it for HEAD
      // would say the same thing twice.
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', {'main': 'aaa'}),
          signature('bbb', 'refs/heads/main', {'main': 'bbb'}),
        ),
        'main 브랜치 갱신됨',
      );
    });

    test('HEAD moving with no tip behind it is still worth saying', () {
      expect(
        summarize(
          signature('aaa', 'HEAD', {'main': 'ccc'}),
          signature('bbb', 'HEAD', {'main': 'ccc'}),
        ),
        'HEAD 이동됨',
      );
    });

    test('every kind of change at once stays on one line', () {
      expect(
        summarize(
          signature('aaa', 'refs/heads/main', {
            'main': 'aaa',
            'work': 'bbb',
            'spike': 'ccc',
          }),
          signature('ddd', 'refs/heads/work', {
            'work': 'ddd',
            'main': 'aaa',
            'fresh': 'eee',
          }),
        ),
        'work 체크아웃, work 브랜치 갱신됨, fresh 브랜치 추가됨, spike 브랜치 삭제됨',
      );
    });
  });
}

/// docs/local-change-summary-mockup.html — 요약 한 줄 뒤에 무슨 작업이었고 어떤
/// 커밋이 오갔는지를 붙이려면, git이 남긴 문장에서 그 둘을 읽어낼 수 있어야 한다.
void _movedBranchDetail() {
  group('branchOperationFromReflog', () {
    test('git이 쓰는 문장에서 작업 이름만 꺼낸다', () {
      // 전부 이 저장소의 reflog에 실제로 남아 있는 모양이다.
      for (final entry in {
        'commit: fix: let the app say a thing once, not twice': 'commit',
        'commit (amend): fix: one alert width': 'amend',
        'commit (merge): Merge branch main': 'merge',
        'pull: Fast-forward': 'pull',
        'pull --rebase (pick): fix: one alert width': 'pull',
        "merge feature/pr-monitoring: Merge made by the 'ort' strategy.":
            'merge',
        'rebase (finish): returning to refs/heads/main': 'rebase',
        'rebase (pick): fix: match the alert to the approved mockup': 'rebase',
        'reset: moving to 954e6e8': 'reset',
        'checkout: moving from a to b': 'checkout',
      }.entries) {
        expect(branchOperationFromReflog(entry.key), entry.value);
      }
    });

    test('읽을 것이 없으면 아무 이름도 지어내지 않는다', () {
      expect(branchOperationFromReflog(''), isNull);
      expect(branchOperationFromReflog('   '), isNull);
    });
  });

  group('parseMovedCommits', () {
    test('나간 쪽과 들어온 쪽을 갈라 읽는다', () {
      // `git log --left-right --oneline old...new`: 왼쪽이 옛 tip이라 <가 나간 것.
      const output =
          '< 32ee935 fix: let the app say a thing once, not twice\n'
          '> 89a61cb feat: let a remote branch stand as the base\n'
          '> 06fdbd1 test: pin the origin/HEAD drop against real git output\n';

      final commits = parseMovedCommits(output);

      expect(commits, hasLength(3));
      expect(commits.first.incoming, isFalse);
      expect(commits.first.shortSha, '32ee935');
      expect(commits.first.subject, 'fix: let the app say a thing once, not twice');
      expect(commits.last.incoming, isTrue);
      expect(commits.last.shortSha, '06fdbd1');
    });

    test('알아볼 수 없는 줄은 버린다', () {
      expect(parseMovedCommits('\n rubbish \n< abc\n'), isEmpty);
    });
  });

  group('parseMovedCounts', () {
    test('나간 개수와 들어온 개수를 읽는다', () {
      expect(parseMovedCounts('3\t0\n'), (outgoing: 3, incoming: 0));
      expect(parseMovedCounts('2\t5'), (outgoing: 2, incoming: 5));
    });

    test('git이 답하지 못한 것은 없는 것으로 둔다', () {
      expect(parseMovedCounts(''), isNull);
      expect(parseMovedCounts('nonsense'), isNull);
    });
  });
}

/// 시안의 머리줄 문구를 그대로 못박는다.
void _movedBranchLine() {
  group('movedBranchLine', () {
    test('받아온 커밋은 들어온 것으로 말한다', () {
      expect(
        movedBranchLine('main', operation: 'pull', outgoing: 0, incoming: 3),
        'main · pull · 커밋 3개 들어옴',
      );
    });

    test('평범한 커밋은 작업 이름을 되풀이하지 않는다', () {
      expect(
        movedBranchLine('main', operation: 'commit', outgoing: 0, incoming: 1),
        'main · 커밋 1개 들어옴',
      );
    });

    test('되감긴 것은 물러난 것으로 말한다', () {
      expect(
        movedBranchLine('main', operation: 'reset', outgoing: 2, incoming: 0),
        'main · reset · 커밋 2개 물러남',
      );
    });

    test('다시 쓰인 것은 양쪽을 다 말한다', () {
      expect(
        movedBranchLine('main', operation: 'rebase', outgoing: 3, incoming: 3),
        'main · rebase · 커밋 3개 나가고 3개 들어옴',
      );
    });

    test('셀 수 없으면 sha 두 개로 물러난다', () {
      expect(
        movedBranchLine(
          'main',
          operation: null,
          outgoing: null,
          incoming: null,
          before: '3948f07',
          after: '89a61cb',
        ),
        'main 갱신됨 · 3948f07 → 89a61cb',
      );
    });
  });
}
