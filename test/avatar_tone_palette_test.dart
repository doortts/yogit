import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/git.dart';
import 'package:yogit/github_api.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/timeline_palette.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit, graphRow;

/// 팔레트의 연한 두 색이 밝은 아바타에 묻히면 노드의 브랜치 링이 사라진다. 팔레트를
/// 고치는 대신 **무작위 배정 후보에서 그 색을 뺀다** — 사용자가 고른 팔레트와 핀
/// 배정은 그대로 두고, 어느 브랜치가 어느 색을 받느냐만 바꾼다.
void main() {
  // A plain test that reaches for a photo needs the painting binding, and the
  // one the test framework installs is also what answers every image request
  // with a failure.
  TestWidgetsFlutterBinding.ensureInitialized();

  // The palette's own rail colours, by index.
  const green = Color(0xFF18E022);
  const sky = Color(0xFFC2DDF4);
  const midBlue = Color(0xFF68A7EA);
  const lavender = Color(0xFFDACFFA);
  const pink = Color(0xFFFF2D95);
  const cyan = Color(0xFF00E5FF);
  const yellow = Color(0xFFFFF01F);
  const orange = Color(0xFFFF6E27);
  const laneColors = [
    green,
    sky,
    midBlue,
    lavender,
    pink,
    cyan,
    yellow,
    orange,
  ];

  // The avatars the threshold was measured against: a blue doodle on white,
  // which is where the symptom was actually seen, and a mid-grey photo.
  const blueDoodle = Color(0xFFC7D9EC);
  const midtone = Color(0xFF8A8F96);

  group('perceptual distance', () {
    test('separates the lanes that melt from the lanes that read', () {
      // The two pale entries sit on top of the doodle; cyan is the nearest
      // colour anybody confirmed as readable, and it has to survive.
      expect(oklabDistance(sky, blueDoodle), closeTo(0.013, 0.001));
      expect(oklabDistance(lavender, blueDoodle), closeTo(0.045, 0.001));
      expect(oklabDistance(cyan, blueDoodle), closeTo(0.127, 0.001));
      expect(oklabDistance(pink, midtone), closeTo(0.252, 0.001));

      expect(oklabDistance(sky, blueDoodle), lessThan(paletteToneCollision));
      expect(
        oklabDistance(lavender, blueDoodle),
        lessThan(paletteToneCollision),
      );
      expect(
        oklabDistance(cyan, blueDoodle),
        greaterThanOrEqualTo(paletteToneCollision),
        reason: '선명한 시안은 실제로 잘 보인다',
      );
      expect(
        oklabDistance(pink, midtone),
        greaterThanOrEqualTo(paletteToneCollision),
        reason: '명도 대비 1.06이어도 색상 차이가 링을 살린다',
      );
    });

    test('is symmetric and zero on the same colour', () {
      expect(oklabDistance(sky, sky), closeTo(0, 1e-9));
      expect(
        oklabDistance(sky, blueDoodle),
        closeTo(oklabDistance(blueDoodle, sky), 1e-9),
      );
    });
  });

  group('candidate filter', () {
    test('drops the pale lanes a bright avatar would swallow', () {
      final kept = paletteIndexesAvoiding(
        const [1, 2, 3, 4, 5, 6, 7],
        laneColors,
        blueDoodle,
      );

      expect(kept, isNot(contains(1)), reason: '하늘색이 낙서에 묻힌다');
      expect(kept, isNot(contains(3)), reason: '라벤더도 마찬가지다');
      expect(kept, containsAll(const [2, 4, 5, 6, 7]));
    });

    test('leaves the candidates alone when nothing collides', () {
      const candidates = [1, 2, 3, 4, 5, 6, 7];
      expect(
        paletteIndexesAvoiding(candidates, laneColors, const Color(0xFF2E3138)),
        candidates,
        reason: '어두운 사진 위에서는 여덟 색 모두 읽힌다',
      );
    });

    test('a palette that collides throughout still offers three', () {
      // Every entry within the threshold of the tone: seven greys a hair apart
      // from #808080, the furthest three being the last three.
      const greys = [
        Color(0xFF808080),
        Color(0xFF7E8080),
        Color(0xFF828282),
        Color(0xFF858585),
        Color(0xFF888888),
        Color(0xFF8B8B8B),
        Color(0xFF8F8F8F),
        Color(0xFF949494),
      ];

      final kept = paletteIndexesAvoiding(
        const [1, 2, 3, 4, 5, 6, 7],
        greys,
        const Color(0xFF808080),
      );

      expect(kept, const [5, 6, 7], reason: '후보가 비면 배정이 무너진다');
    });

    test('never returns more candidates than it was given', () {
      final kept = paletteIndexesAvoiding(
        const [2, 5],
        laneColors,
        const Color(0xFF808080),
      );

      expect(kept, hasLength(lessThanOrEqualTo(2)));
      expect(kept, everyElement(isIn(const [2, 5])));
    });
  });

  group('branch assignment', () {
    /// A line born at id [id], with every line alive beside it.
    GraphRow born(int id, List<int> alive) {
      final branches = {for (final lane in alive) lane: lane};
      return graphRow(
        commit: commit('$id', 'line $id'),
        lane: 0,
        activeLanes: alive,
        nextLanes: alive,
        branch: id,
        activeLaneBranches: branches,
        nextLaneBranches: branches,
      );
    }

    /// Twelve lines on top of the base one: more branches than the palette has
    /// colours, so every candidate in the random pool is drawn at least once.
    final rows = [
      for (var id = 0; id <= 12; id++)
        born(id, [for (var alive = 0; alive <= id; alive++) alive]),
    ];

    /// What the timeline hands over: the palette itself, which is where the
    /// rail colours the tone is compared against are read from.
    const palette = AppSettings.defaultRefPalette;

    test('a bright avatar loses the two lanes that melt into it', () {
      final unfiltered = assignBranchPaletteIndexes(rows, 7);
      expect(
        unfiltered.values,
        anyOf(contains(1), contains(3)),
        reason: '조정이 없으면 연한 색이 실제로 배정된다',
      );

      final indexes = assignBranchPaletteIndexes(
        rows,
        7,
        refPalette: palette,
        avoidTone: blueDoodle,
      );

      expect(indexes.values, isNot(contains(1)));
      expect(indexes.values, isNot(contains(3)));
      expect(indexes[0], 0, reason: '기준 브랜치는 그대로다');
    });

    test('a pinned lane keeps its colour even where it collides', () {
      // Palette 1 — the sky the doodle swallows — pinned to branch 4.
      const assignments = [1, 5, 0, 0, 0, 0, 0, 0];

      final indexes = assignBranchPaletteIndexes(
        rows,
        7,
        refPaletteAssignments: assignments,
        refPalette: palette,
        avoidTone: blueDoodle,
      );

      expect(indexes[4], 1, reason: '사용자가 못 박은 색이 자동 조정보다 세다');
      expect(
        [
          for (final entry in indexes.entries)
            if (entry.key != 4) entry.value,
        ],
        isNot(contains(1)),
        reason: '핀은 자기 브랜치만 지킨다',
      );
    });

    test('the base branch owns palette 0 whatever the avatar is', () {
      // Even an avatar that is exactly palette 0 — the second tone here is the
      // green itself, distance zero — does not move the base branch off it.
      for (final tone in const [blueDoodle, green]) {
        expect(
          assignBranchPaletteIndexes(
            rows,
            7,
            refPalette: palette,
            avoidTone: tone,
          )[0],
          0,
          reason: '$tone',
        );
      }
    });

    test('no tone means no change at all', () {
      final today = assignBranchPaletteIndexes(rows, 7);

      expect(
        assignBranchPaletteIndexes(rows, 7, refPalette: palette),
        today,
        reason: '아바타가 없으면 오늘과 같아야 한다',
      );
      expect(assignBranchPaletteIndexes(rows, 7, avoidTone: null), today);
    });

    test('the same repository and tone assign the same colours', () {
      final first = assignBranchPaletteIndexes(
        rows,
        7,
        refPalette: palette,
        avoidTone: blueDoodle,
      );

      for (var again = 0; again < 3; again++) {
        expect(
          assignBranchPaletteIndexes(
            rows,
            7,
            refPalette: palette,
            avoidTone: blueDoodle,
          ),
          first,
          reason: '다시 그릴 때마다 색이 바뀌면 안 된다',
        );
      }
      expect(
        assignBranchPaletteIndexes(
          rows,
          8,
          refPalette: palette,
          avoidTone: blueDoodle,
        ),
        isNot(first),
        reason: '저장소가 다르면 배정도 다르다',
      );
    });

    test('a palette nobody can read colours out of uses the default', () {
      // One entry with a hex nothing will parse — enough for
      // refPaletteColorsAt to throw the whole palette away, the same
      // all-or-nothing call the settings screen and the rails already make.
      final broken = [...palette]
        ..[4] = (base: '#B51D68', text: 'not a colour');

      expect(
        assignBranchPaletteIndexes(
          rows,
          7,
          refPalette: broken,
          avoidTone: blueDoodle,
        ),
        assignBranchPaletteIndexes(
          rows,
          7,
          refPalette: palette,
          avoidTone: blueDoodle,
        ),
        reason: '읽을 수 없는 팔레트는 기본 팔레트로 되돌아간다',
      );
    });
  });

  group('the tone on disk', () {
    late Directory home;
    late AvatarStore store;

    setUp(() {
      home = Directory.systemTemp.createTempSync('yogit_tone_');
      store = AvatarStore(File('${home.path}/avatars.json'));
    });

    tearDown(() => home.deleteSync(recursive: true));

    test('a learned tone is there on the next run', () async {
      await store.save('github.com', const {
        'ada@example.com': RemoteAvatar(
          login: 'ada',
          url: 'https://avatars.example/ada',
          tone: blueDoodle,
        ),
      });

      final known = await store.load('github.com');

      expect(known['ada@example.com']?.tone, blueDoodle);
      expect(
        store.file.readAsStringSync(),
        contains('#C7D9EC'),
        reason: '사람이 열어 봐도 읽히는 형식이다',
      );
    });

    test('an avatar written before the field existed still loads', () async {
      store.file.writeAsStringSync(
        '{"github.com":{"ada@example.com":'
        '{"login":"ada","url":"https://avatars.example/ada"}}}',
      );

      final known = await store.load('github.com');

      expect(known['ada@example.com']?.login, 'ada');
      expect(known['ada@example.com']?.tone, isNull, reason: '없으면 다시 계산한다');
    });

    test('a tone nobody could parse is no tone', () async {
      store.file.writeAsStringSync(
        '{"github.com":{"ada@example.com":{"login":"ada",'
        '"url":"https://avatars.example/ada","tone":"not a colour"}}}',
      );

      final known = await store.load('github.com');

      expect(known['ada@example.com']?.login, 'ada', reason: '얼굴은 남는다');
      expect(known['ada@example.com']?.tone, isNull);
    });

    test('a face with no tone yet is written without one', () async {
      await store.save('github.com', const {
        'ada@example.com': RemoteAvatar(
          login: 'ada',
          url: 'https://avatars.example/ada',
        ),
      });

      expect(store.file.readAsStringSync(), isNot(contains('tone')));
    });
  });

  group('the tone read off a photo', () {
    Future<ui.Image> imageOf(List<int> rgba) {
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        Uint8List.fromList(rgba),
        2,
        2,
        ui.PixelFormat.rgba8888,
        decoded.complete,
      );
      return decoded.future;
    }

    test('is the mean of the pixels that are actually there', () async {
      final image = await imageOf(const [
        255, 0, 0, 255, // red
        0, 0, 255, 255, // blue
        0, 255, 0, 255, // green
        255, 255, 255, 0, // a transparent corner, which is not the photo
      ]);

      expect(
        await AvatarService.debugToneOf(image),
        const Color(0xFF555555),
        reason: '투명한 자리는 사진이 아니라 그 뒤에 있는 것이다',
      );
    });

    test('is nothing at all when the photo is all corner', () async {
      final image = await imageOf(List.filled(16, 0));

      expect(await AvatarService.debugToneOf(image), isNull);
    });

    test('is the colour a half-transparent pixel was drawn in', () async {
      // `decodeImageFromPixels` stores these bytes the way the engine stores a
      // decoded PNG: premultiplied. So #A3A3A3 drawn at 78% alpha sits in the
      // buffer as #808080, and reading it back premultiplied would call the
      // whole face #808080 — a shade darker than anything on the photo.
      final image = await imageOf(
        List.filled(4, const [
          128,
          128,
          128,
          200,
        ]).expand((pixel) => pixel).toList(),
      );

      expect(
        await AvatarService.debugToneOf(image),
        const Color(0xFFA3A3A3),
        reason: '반투명 픽셀은 곱해서 어두워진 값이 아니라 그려진 색이다',
      );
    });

    test('is nothing at all when the pixels will not come back', () async {
      final image = await imageOf(List.filled(16, 255));
      // A disposed texture is the cheapest thing the engine refuses to read
      // back; a photo whose bytes never reached the GPU is the same failure.
      image.dispose();

      expect(
        await AvatarService.debugToneOf(image),
        isNull,
        reason: '픽셀을 못 읽으면 톤이 없는 것이고 영원히 기다리는 것이 아니다',
      );
    });
  });

  group('the graph reads the tone', () {
    // Ada wrote every commit the fake repository answers with; Zoe wrote none
    // of them, which is the only way a tone goes unasked for.
    const me = GitIdentity(name: 'Ada Author', email: 'ada@example.com');
    const zoe = GitIdentity(name: 'Zoe Other', email: 'zoe@example.com');

    late Directory home;
    late AvatarStore store;

    setUp(() {
      home = Directory.systemTemp.createTempSync('yogit_tone_wired_');
      store = AvatarStore(File('${home.path}/avatars.json'));
      addTearDown(() {
        AvatarService.branchAssignments = const {};
        home.deleteSync(recursive: true);
      });
    });

    /// [answer] stands in for the server. It goes unasked wherever the face is
    /// already on disk, and the photo behind the face is never its business —
    /// that one belongs to the image cache.
    AvatarService serviceOn(
      AvatarStore? store, {
      Future<HttpResponse> Function(Uri uri)? answer,
    }) => AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      store: store,
      api: GitHubApi(
        apiBaseUrl: 'https://api.github.com',
        token: 'token-1',
        send: (uri, {required method, required headers, body}) async =>
            await answer?.call(uri) ?? (status: 500, body: 'offline'),
      ),
    );

    /// Git answers whatever the identity is, and nothing else.
    CommandRunner speaking(GitIdentity identity) =>
        (executable, arguments, {workingDirectory, environment}) async {
          final key = arguments.last;
          return ProcessResult(0, 0, switch (key) {
            'user.name' => identity.name,
            'user.email' => identity.email,
            _ => '',
          }, '');
        };

    /// Ten lines off one root, so the random pool is drawn from often enough
    /// that the pale entries actually turn up in an unadjusted assignment.
    List<GitCommit> branchy() => [
      for (var tip = 0; tip < 10; tip++)
        commit('tip$tip', 'line $tip', parents: const ['root']),
      commit('root', 'root'),
    ];

    Future<void> pumpTimeline(
      WidgetTester tester,
      AvatarService service, {
      GitIdentity identity = me,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(
            repository: FakeGitRepository(
              (skip, _) async => skip == 0 ? branchy() : const [],
              runner: speaking(identity),
            ),
            avatarService: service,
            controller: WindowFrameController(
              channel: const MethodChannel('test/yogit-window'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an unadjusted graph really does hand out a pale lane', (
      tester,
    ) async {
      // The other half of the contract below: without a tone the assignment is
      // free to pick a colour the avatar swallows, and here it does.
      await pumpTimeline(tester, serviceOn(null));

      expect(
        AvatarService.branchAssignments.values.map(
          (color) => oklabDistance(color, blueDoodle),
        ),
        anyElement(lessThan(paletteToneCollision)),
      );
    });

    testWidgets('a stored tone is in force on the first graph', (tester) async {
      final service = serviceOn(store);
      // The disk is real, and a widget test's clock is not: both the write and
      // the read back have to happen outside it.
      await tester.runAsync(
        () => store.save('github.com', const {
          'ada@example.com': RemoteAvatar(
            login: 'ada',
            url: 'https://avatars.example/ada.png',
            tone: blueDoodle,
          ),
        }),
      );
      await tester.runAsync(service.restore);

      await pumpTimeline(tester, service);

      expect(AvatarService.branchAssignments, isNotEmpty);
      for (final entry in AvatarService.branchAssignments.entries) {
        expect(
          oklabDistance(entry.value, blueDoodle),
          greaterThanOrEqualTo(paletteToneCollision),
          reason: '브랜치 ${entry.key}의 링이 아바타에 묻힌다',
        );
      }
    });

    testWidgets('a photo that will not decode leaves the graph alone', (
      tester,
    ) async {
      // The face is known, the photo is not: every image request a test makes
      // fails, which is the same thing a 404 avatar is.
      final service = serviceOn(store);
      await tester.runAsync(
        () => store.save('github.com', const {
          'ada@example.com': RemoteAvatar(
            login: 'ada',
            url: 'https://avatars.example/gone.png',
          ),
        }),
      );
      await tester.runAsync(service.restore);

      await pumpTimeline(tester, service);

      expect(
        AvatarService.branchAssignments.values.map(
          (color) => oklabDistance(color, blueDoodle),
        ),
        anyElement(lessThan(paletteToneCollision)),
        reason: '톤이 없으면 오늘과 같다',
      );
    });

    test(
      'a photo that will not decode is a missing tone, not an error',
      () async {
        await store.save('github.com', const {
          'ada@example.com': RemoteAvatar(
            login: 'ada',
            url: 'https://avatars.example/gone.png',
          ),
        });
        final service = serviceOn(store);

        expect(
          await service.toneFor('tip3', identity: me),
          isNull,
          reason: '예외가 아니라 답이 없는 것이다',
        );
        await service.debugWritten;
        expect(
          (await store.load('github.com'))['ada@example.com']?.tone,
          isNull,
          reason: '못 읽은 사진을 톤으로 적어 두지 않는다',
        );
      },
    );

    test('the face is found through the sha of one of their commits', () async {
      final asked = <Uri>[];
      final service = serviceOn(
        store,
        answer: (uri) async {
          asked.add(uri);
          return (
            status: 200,
            body:
                '{"author":{"login":"ada",'
                '"avatar_url":"https://avatars.example/ada"}}',
          );
        },
      );

      await service.toneFor('tip3', identity: me);

      expect(asked.single.path, '/repos/team/yogit/commits/tip3');
      expect(asked.single.query, isEmpty, reason: '주소가 URL에 실려 나가지 않는다');
      expect(service.cachedFor(author: me)?.author?.login, 'ada');

      // Going through resolve is what buys this: the face is filed under the
      // person, so the next commit of theirs is answered without asking.
      await service.toneFor('tip4', identity: me);

      expect(asked, hasLength(1), reason: '이미 아는 얼굴을 다시 묻지 않는다');
    });

    // GitHub UI에서 squash 머지한 커밋은 커미터가 `GitHub <noreply@github.com>`이다.
    // 저자는 아는 얼굴이고 커미터는 처음 보는 사람이니 행 하나가 조회 경로를 탄다 —
    // 평범한 스크롤이다. API 응답에는 tone이 없으므로, 여기서 덮어쓰면 복원해 둔 톤이
    // 메모리에서 지워지고 그 뒤 `_persist()`가 지워진 상태를 파일에 적는다.
    const robot = GitIdentity(name: 'GitHub', email: 'noreply@github.com');

    /// 저자는 ada, 커미터는 [committerLogin]. ada의 사진은 [adaPhoto].
    AvatarService serviceAnswering({
      String adaPhoto = 'https://avatars.example/ada.png',
      String committerLogin = 'github',
    }) => serviceOn(
      store,
      answer: (uri) async => (
        status: 200,
        body:
            '{"author":{"login":"ada","avatar_url":"$adaPhoto"},'
            '"committer":{"login":"$committerLogin",'
            '"avatar_url":"https://avatars.example/$committerLogin.png"}}',
      ),
    );

    Future<void> storeAda() => store.save('github.com', const {
      'ada@example.com': RemoteAvatar(
        login: 'ada',
        url: 'https://avatars.example/ada.png',
        tone: blueDoodle,
      ),
    });

    test('an ordinary row does not wipe the tone off a known face', () async {
      await storeAda();
      final service = serviceAnswering();

      await service.resolve('tip3', author: me, committer: robot);

      expect(
        service.cachedFor(author: me)?.author?.tone,
        blueDoodle,
        reason: '남의 얼굴을 배우면서 아는 톤을 지우면 안 된다',
      );
      await service.debugWritten;
      expect(
        (await store.load('github.com'))['ada@example.com']?.tone,
        blueDoodle,
        reason: '평범한 스크롤에 디스크의 톤이 지워지면 안 된다',
      );
    });

    test('a tone read off another photo is not this photo\'s tone', () async {
      await storeAda();
      final service = serviceAnswering(
        adaPhoto: 'https://avatars.example/ada-new.png',
      );

      await service.resolve('tip3', author: me, committer: robot);

      expect(
        service.cachedFor(author: me)?.author?.tone,
        isNull,
        reason: '사진이 바뀌면 톤은 다시 읽어야 한다',
      );
    });

    testWidgets('a graph with none of their commits reads no tone', (
      tester,
    ) async {
      // Zoe's face and her tone are both on disk, and not one row of this
      // history is hers: no photo of hers is drawn, so no ring of hers is at
      // risk and there is nothing for the assignment to steer around.
      final service = serviceOn(store);
      await tester.runAsync(
        () => store.save('github.com', const {
          'zoe@example.com': RemoteAvatar(
            login: 'zoe',
            url: 'https://avatars.example/zoe.png',
            tone: blueDoodle,
          ),
        }),
      );
      await tester.runAsync(service.restore);

      await pumpTimeline(tester, service, identity: zoe);

      expect(
        AvatarService.branchAssignments.values.map(
          (color) => oklabDistance(color, blueDoodle),
        ),
        anyElement(lessThan(paletteToneCollision)),
        reason: '본인이 쓴 커밋이 화면에 없으면 조정할 이유도 없다',
      );
    });

    test('an identity git has never been told is not asked about', () async {
      expect(
        await serviceOn(store).toneFor(
          'tip3',
          identity: const GitIdentity(name: '', email: ''),
        ),
        isNull,
      );
    });

    test('a lookup that fails is a missing tone, not an error', () async {
      // No store, so the face has to be asked for — and the server is down.
      expect(await serviceOn(null).toneFor('tip3', identity: me), isNull);
    });
  });
}
