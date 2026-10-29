import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_app/data/user_store.dart';
import 'package:vocab_app/logic/grouping.dart';
import 'package:vocab_app/models.dart';
import 'package:vocab_app/pages/favorites_page.dart' show toFixReport;

import 'helpers.dart';

void main() {
  final repo = loadTestRepo();

  test('每個主題組剛好 20 個字', () {
    expect(repo.groups.length, 5);
    for (final g in repo.groups) {
      expect(g.words.length, groupSize, reason: g.name);
    }
  });

  test('字庫載入 ECDICT，主題字保留手寫例句並補上字典資料', () {
    expect(repo.size, greaterThan(30000));
    final breakfast = repo.find('breakfast')!;
    expect(breakfast.example, 'I usually eat breakfast at seven.');
    expect(breakfast.definitions, isNotEmpty);
    expect(repo.groups.first.words.first.definitions, isNotEmpty);
  });

  test('字典內容已轉成台灣繁體', () {
    expect(repo.find('computer')!.meaning, contains('電腦'));
    expect(repo.find('software')!.meaning, contains('軟體'));
    expect(repo.find('genre')!.meaning, contains('類型'));
  });

  test('20 字切成 4 回合、每回合 5 對', () {
    final rounds = splitRounds(List.generate(20, (i) => i));
    expect(rounds.map((r) => r.length), [5, 5, 5, 5]);
  });

  test('最後只剩 1 個字時併入前一回合', () {
    final rounds = splitRounds(List.generate(11, (i) => i));
    expect(rounds.map((r) => r.length), [5, 6]);
  });

  test('搜尋：完全相符最前面，其次常用字', () {
    expect(repo.search('apple').first.word, 'apple');
    final bre = repo.search('bre').map((w) => w.word).toList();
    expect(bre.every((w) => w.toLowerCase().contains('bre')), isTrue);
    expect(bre, containsAll(['bread', 'breakfast']));
    expect(bre.length, lessThanOrEqualTo(50));
  });

  test('搜尋：輸入變化形找得到原形', () {
    expect(repo.search('went').map((w) => w.word), contains('go'));
    expect(repo.search('children').map((w) => w.word), contains('child'));
  });

  test('片語：依常用度每 20 個一組，可從單字找到相關片語', () {
    expect(repo.phraseGroups.length, greaterThan(20));
    expect(repo.phraseGroups.first.words.length, groupSize);
    expect(repo.phraseGroups.first.words.map((w) => w.word), contains('have to'));
    expect(repo.phraseGroups.expand((g) => g.words).every((w) => w.isPhrase), isTrue);
    expect(repo.relatedPhrases(repo.find('give')!).map((w) => w.word), contains('give up'));
    expect(repo.find('take care of')!.example, isNotEmpty);
    expect(repo.search('give u').first.word, 'give up');
  });

  test('corrections.json 的修正會覆蓋字典解釋', () {
    final w = repo.find('get along with')!;
    expect(w.meaning, '相處；進展');
    expect(w.definitions.first, contains('相處'));
    expect(w.example, isNotEmpty); // 沒修正的欄位沿用字典
    expect(repo.correctedKinds('get along with'), {FixKind.meaning});
    expect(repo.correctedKinds('give up'), isEmpty);
    expect(FixKind.resolvedBy({'example': 'x', 'exampleZh': 'y'}), {FixKind.example});
  });

  test('考試單字：牛津 3000、TOEFL、IELTS、GRE，常用的排前面', () {
    expect(repo.examTracks.map((t) => t.name), ['牛津 3000', 'TOEFL', 'IELTS', 'GRE']);
    for (final track in repo.examTracks) {
      expect(track.wordCount, greaterThan(2000), reason: track.name);
      expect(track.groups.first.words.length, groupSize);
      final words = track.groups.expand((g) => g.words).toList();
      expect(words.every((w) => !w.isPhrase), isTrue);
      expect(words.first.rank, lessThanOrEqualTo(words.last.rank));
    }
    final toefl = repo.examTracks.firstWhere((t) => t.id == 'toefl');
    expect(toefl.groups.expand((g) => g.words).every((w) => w.tags.contains('toefl')), isTrue);
  });

  test('待調整清單：解釋與例句分開記錄，全部修正才算完成', () async {
    final store = UserStore.memory();
    await store.markToFix('give up', '少了「認輸」', {FixKind.meaning});
    await store.markToFix('get along with', '', {FixKind.meaning});
    await store.markToFix('genre', '', {FixKind.example});
    expect(store.toFix, ['give up', 'get along with', 'genre']);
    expect(store.toFixNote('give up'), '少了「認輸」');

    var report = toFixReport(repo, store);
    expect(report, startsWith('待調整清單（2 筆）'));
    expect(report, contains('give up｜需要：中文解釋｜目前：'));
    expect(report, contains('備註：少了「認輸」'));
    expect(report, contains('genre｜需要：補例句｜目前：n. 類型；流派｜目前例句：（無）'));
    expect(report, isNot(contains('get along with'))); // 解釋已修正，不列出

    // get along with 只修了解釋，若還要補例句就不算完成
    await store.markToFix('get along with', '', {FixKind.meaning, FixKind.example});
    report = toFixReport(repo, store);
    expect(report, contains('get along with｜需要：中文解釋、補例句'));

    await store.markToFix('give up', '', {}); // 沒勾任何項目 = 移除
    expect(store.needsFix('give up'), isFalse);
  });

  test('搜尋：中文反查', () {
    expect(repo.search('早餐').first.word, 'breakfast');
    expect(repo.search('蘋果').map((w) => w.word), contains('apple'));
    expect(repo.search('zzzq'), isEmpty);
    expect(repo.search('  '), isEmpty);
  });
}
