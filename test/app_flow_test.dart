import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_app/app_scope.dart';
import 'package:vocab_app/data/user_store.dart';
import 'package:vocab_app/main.dart';
import 'package:vocab_app/models.dart';
import 'package:vocab_app/pages/matching_game_page.dart';
import 'package:vocab_app/pages/mini_mode_page.dart';

import 'helpers.dart';

void main() {
  final repo = loadTestRepo();

  testWidgets('查詢 → 收藏 → 收藏頁看得到', (tester) async {
    final store = UserStore.memory();
    await tester.pumpWidget(VocabApp(repo: repo, store: store));
    await tester.enterText(find.byType(TextField), 'umbrella');
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'umbrella'), findsOneWidget);

    await tester.tap(find.byTooltip('加入收藏').first);
    await tester.pump();
    expect(store.isFavorite('umbrella'), isTrue);

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('收藏（1）'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'umbrella'), findsOneWidget);
  });

  testWidgets('複製單字、加入待調整，收藏頁的待調整清單可整份複製', (tester) async {
    final clipboard = FakeClipboard(tester);
    final store = UserStore.memory();
    await tester.pumpWidget(VocabApp(repo: repo, store: store));
    await tester.enterText(find.byType(TextField), 'give up');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'give up'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('複製單字'));
    await tester.pump();
    expect(clipboard.text, 'give up');

    await tester.tap(find.byTooltip('回報問題（解釋、例句）'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '少了「認輸」');
    await tester.tap(find.text('加入待調整'));
    await tester.pumpAndSettle();
    expect(store.toFixNote('give up'), '少了「認輸」');
    expect(find.textContaining('已加入待調整'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待調整（1）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('備註：少了「認輸」'), findsOneWidget);

    await tester.tap(find.text('複製清單'));
    await tester.pump();
    expect(clipboard.text, startsWith('待調整清單（1 筆）'));
    expect(clipboard.text, contains('give up｜需要：中文解釋｜目前：'));
  });

  testWidgets('沒有例句的字可以直接回報需要例句', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = UserStore.memory();
    await tester.pumpWidget(VocabApp(repo: repo, store: store));
    await tester.enterText(find.byType(TextField), 'genre');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'genre'));
    await tester.pumpAndSettle();
    expect(find.text('這個字還沒有例句'), findsOneWidget);

    await tester.tap(find.text('回報需要例句'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入待調整'));
    await tester.pumpAndSettle();
    expect(store.toFixKinds('genre'), {FixKind.example});
    expect(find.text('已回報需要例句'), findsOneWidget);
    expect(find.textContaining('已加入待調整（補例句）'), findsOneWidget);
  });

  testWidgets('學習頁 → TOEFL → 接著練第 1 組', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final toefl = repo.examTracks.firstWhere((t) => t.id == 'toefl');

    await tester.pumpWidget(VocabApp(repo: repo, store: UserStore.memory()));
    await tester.tap(find.text('學習'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TOEFL'));
    await tester.pumpAndSettle();
    expect(find.text('已完成 0 / ${toefl.groups.length} 組'), findsOneWidget);
    expect(find.text('TOEFL 第 1 組'), findsOneWidget);

    await tester.tap(find.text('繼續：TOEFL 第 1 組'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, toefl.groups.first.words.first.word), findsOneWidget);
    expect(find.textContaining('開始配對'), findsOneWidget);
  });

  testWidgets('迷你模式：只複習收藏、上方列只有離開與關閉、鍵盤換字', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final windowCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('vocab_app/window'),
      (call) async {
        windowCalls.add('${call.method}(${call.arguments ?? ''})');
        return null;
      },
    );
    final store = UserStore.memory();
    await store.toggleFavorite('umbrella');
    await store.toggleFavorite('breakfast');

    await tester.pumpWidget(VocabApp(repo: repo, store: store));
    await tester.tap(find.byTooltip('迷你模式（縮小並固定在最上層）'));
    await tester.pumpAndSettle();
    expect(windowCalls, ['setCompact(true)']);
    expect(find.text('我的收藏  1 / 2'), findsOneWidget);
    expect(find.text('breakfast'), findsOneWidget); // 新收藏的在前面
    expect(find.text('點一下或按空白鍵看解釋'), findsOneWidget);
    // 不再有查詢與來源選單
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.byTooltip('查單字'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('n. 早餐'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('umbrella'), findsOneWidget);
    expect(find.text('我的收藏  2 / 2'), findsOneWidget);
    expect(find.text('n. 雨傘'), findsNothing); // 換字後解釋重新蓋起來

    // 按住上方列拖曳 → 交給 Windows 移動視窗
    await tester.drag(find.text('我的收藏  2 / 2'), const Offset(-50, -50));
    await tester.pump();
    expect(windowCalls, contains('startDrag()'));

    await tester.tap(find.byTooltip('關閉程式'));
    await tester.pump();
    expect(windowCalls.last, 'close()');

    await tester.tap(find.byTooltip('離開迷你模式'));
    await tester.pumpAndSettle();
    expect(windowCalls.last, 'setCompact(false)');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('迷你模式：考試單字組可以用迷你模式複習，主題單字組沒有這個按鈕', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final windowCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('vocab_app/window'),
      (call) async {
        windowCalls.add('${call.method}(${call.arguments ?? ''})');
        return null;
      },
    );
    final toefl = repo.examTracks.firstWhere((t) => t.id == 'toefl');
    final first = toefl.groups.first;

    await tester.pumpWidget(VocabApp(repo: repo, store: UserStore.memory()));
    await tester.tap(find.text('學習'));
    await tester.pumpAndSettle();

    // 主題單字組：沒有迷你模式按鈕
    await tester.tap(find.text(repo.groups.first.name));
    await tester.pumpAndSettle();
    expect(find.byTooltip('用迷你模式複習這組'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // TOEFL 第 1 組：有，按下去複習這組的 20 個字
    await tester.tap(find.text('TOEFL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(first.name));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('用迷你模式複習這組'));
    await tester.pumpAndSettle();
    expect(windowCalls, ['setCompact(true)']);
    expect(find.text('${first.name}  1 / ${first.words.length}'), findsOneWidget);
    expect(find.text(first.words.first.word), findsOneWidget);

    await tester.tap(find.byTooltip('離開迷你模式'));
    await tester.pumpAndSettle();
    expect(windowCalls.last, 'setCompact(false)');
    expect(find.text(first.name), findsOneWidget); // 回到這組的頁面
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('迷你模式：沒有收藏時提示先收藏', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('vocab_app/window'),
      (call) async => null,
    );
    await tester.pumpWidget(AppScope(
      repo: repo,
      store: UserStore.memory(),
      child: const MaterialApp(home: MiniModePage()),
    ));
    expect(find.textContaining('還沒有收藏的單字'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('網頁版與非 Windows 不顯示迷你模式按鈕', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(VocabApp(repo: repo, store: UserStore.memory()));
    expect(find.byTooltip('迷你模式（縮小並固定在最上層）'), findsNothing);
  });

  testWidgets('配對：兩個字中文解釋相同時，配哪一張都算對', (tester) async {
    const group = WordGroup(id: 'dup', name: 'dup', words: [
      Word(word: 'quit', meaning: '放棄'),
      Word(word: 'abandon', meaning: '放棄'),
    ]);
    await tester.pumpWidget(AppScope(
      repo: repo,
      store: UserStore.memory(),
      child: const MaterialApp(home: MatchingGamePage(group: group)),
    ));
    await tester.tap(find.text('quit'));
    await tester.tap(find.text('放棄').at(0));
    await tester.pump();
    await tester.tap(find.text('abandon'));
    await tester.tap(find.text('放棄').at(1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('完成！'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('查 went 找到 go，詳細頁有解釋、詞形變化、例句', (tester) async {
    // 視窗拉高，讓詳細頁整頁都建出來
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(VocabApp(repo: repo, store: UserStore.memory()));
    await tester.enterText(find.byType(TextField), 'went');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'go'));
    await tester.pumpAndSettle();

    expect(find.text('完整解釋'), findsOneWidget);
    expect(find.text('詞形變化'), findsOneWidget);
    expect(find.text('相關片語'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'go out'), findsOneWidget);
    expect(find.textContaining('went', findRichText: true), findsWidgets);
    expect(find.text('這個字還沒有例句'), findsNothing);
  });

  testWidgets('學習頁展開常用片語，進入第 1 組', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(VocabApp(repo: repo, store: UserStore.memory()));
    await tester.tap(find.text('學習'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${repo.phraseGroups.length} 組'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('常用片語 第 1 組'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'have to'), findsOneWidget);
    expect(find.textContaining('開始配對'), findsOneWidget);
  });

  testWidgets('玩完一整組 20 字配對（含一次配錯）', (tester) async {
    final store = UserStore.memory();
    final group = repo.groups.first;
    await tester.pumpWidget(VocabApp(repo: repo, store: store));

    await tester.tap(find.text('學習'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(group.name));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('開始配對'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 4 回合'), findsOneWidget);

    var madeMistake = false;
    final done = <String>{};
    for (var round = 0; round < 4; round++) {
      final onScreen = group.words
          .where((w) => !done.contains(w.word) && find.text(w.word).evaluate().isNotEmpty)
          .toList();
      expect(onScreen.length, 5);

      if (!madeMistake) {
        await tester.tap(find.text(onScreen[0].word));
        await tester.tap(find.text(onScreen[1].meaning));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('錯誤 1 次'), findsOneWidget);
        madeMistake = true;
      }
      for (final w in onScreen) {
        await tester.tap(find.text(w.word));
        await tester.tap(find.text(w.meaning));
        await tester.pump();
        done.add(w.word);
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    expect(find.text('完成！'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget); // 20 對 / (20 + 1 次錯)
    expect(find.text('這些字要再加強'), findsOneWidget);
    expect(store.bestScore(group.id)?.accuracy, closeTo(20 / 21, 1e-9));

    await tester.tap(find.text('全部加入收藏'));
    await tester.pump();
    expect(store.favorites.length, 2);
  });
}
