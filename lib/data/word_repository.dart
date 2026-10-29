import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logic/grouping.dart';
import '../models.dart';
import '../platform/platform.dart';

/// 單字資料來源（後者覆蓋前者）：
/// - assets/dictionary.tsv.gz：ECDICT 轉成繁體的字庫（由 tool/build_dictionary.dart 產生）
/// - assets/words.json：手動整理的主題單字組（例句、解釋優先採用這裡的）
/// - assets/corrections.json：使用者回報「待調整」後修正的解釋
class WordRepository {
  WordRepository._(this.groups, this.phraseGroups, this.examTracks, this._byWord,
      this._sortedKeys, this._lemmas, this._phrasesByWord, this._corrected);

  /// 手動整理的主題單字組。
  final List<WordGroup> groups;

  /// 常用片語，依日常例句出現次數排序、每 20 個一組。
  final List<WordGroup> phraseGroups;

  /// 依考試標籤分類的單字，常用的排前面、每 20 個一組。
  final List<ExamTrack> examTracks;

  final Map<String, Word> _byWord;

  /// 套用過 corrections.json 的字 → 修正了哪些項目。
  final Map<String, Set<FixKind>> _corrected;

  /// 依字母排序的所有 key，用來做前綴搜尋。
  final List<String> _sortedKeys;

  /// 變化形 → 原形，例如 went → {go}。
  final Map<String, Set<String>> _lemmas;

  /// 單字 → 含有這個字的片語，例如 give → [give up, give in …]。
  final Map<String, List<Word>> _phrasesByWord;

  static const maxResults = 50;

  /// 片語至少在這麼多句日常例句中出現，才放進學習用的片語組。
  static const minPhraseUsageForStudy = 3;

  /// 考試分類：id、名稱、說明、判斷條件。
  /// ECDICT 的考試標籤也涵蓋 can、want 這類基礎字，所以排除基礎程度（zk 國中、gk 高中）的字，
  /// 留下真正需要準備的；基礎字由「牛津 3000」負責。
  static final _exams = <(String, String, String, bool Function(Word))>[
    ('oxford', '牛津 3000', '最核心的 3000 個常用字，適合打基礎', (w) => w.oxford),
    ('toefl', 'TOEFL', '托福：北美留學（已排除國中程度基礎字）',
        (w) => w.tags.contains('toefl') && !w.tags.contains('zk')),
    ('ielts', 'IELTS', '雅思：英國、澳洲留學與移民（已排除國中程度基礎字）',
        (w) => w.tags.contains('ielts') && !w.tags.contains('zk')),
    ('gre', 'GRE', '美國研究所入學考，難度最高（已排除高中以下程度的字）',
        (w) => w.tags.contains('gre') && !w.tags.contains('zk') && !w.tags.contains('gk')),
  ];

  factory WordRepository({
    required List<WordGroup> groups,
    List<Word> dictionary = const [],
    Map<String, dynamic> corrections = const {},
  }) {
    final byWord = {for (final w in dictionary) w.key: w};
    for (final g in groups) {
      for (final w in g.words) {
        final dict = byWord[w.key];
        byWord[w.key] = dict == null ? w : w.mergedWith(dict);
      }
    }
    final corrected = <String, Set<FixKind>>{};
    for (final MapEntry(:key, :value) in corrections.entries) {
      final w = byWord[key.toLowerCase()];
      if (w == null || value is! Map<String, dynamic>) continue; // 例如 "_說明"
      byWord[w.key] = w.withCorrection(value);
      corrected[w.key] = FixKind.resolvedBy(value);
    }
    final mergedGroups = [
      for (final g in groups)
        WordGroup(id: g.id, name: g.name, words: [for (final w in g.words) byWord[w.key]!]),
    ];
    final lemmas = <String, Set<String>>{};
    for (final w in byWord.values) {
      for (final form in w.forms.values) {
        final f = form.toLowerCase();
        if (f != w.key) lemmas.putIfAbsent(f, () => {}).add(w.key);
      }
    }

    final phrases = byWord.values.where((w) => w.isPhrase).toList()
      ..sort((a, b) => b.usage - a.usage);
    final phrasesByWord = <String, List<Word>>{};
    for (final p in phrases) {
      for (final token in p.key.split(' ').toSet()) {
        if (byWord.containsKey(token)) phrasesByWord.putIfAbsent(token, () => []).add(p);
      }
    }
    final studyPhrases = phrases.where((p) => p.usage >= minPhraseUsageForStudy).toList();
    final phraseGroups = [
      for (final (i, words) in chunk(studyPhrases, groupSize).indexed)
        WordGroup(id: 'phrase-${i + 1}', name: '常用片語 第 ${i + 1} 組', words: words),
    ];
    final singleWords = _byRank(byWord.values.where((w) => !w.isPhrase));
    final examTracks = [
      for (final (id, name, description, test) in _exams)
        ExamTrack(id: id, name: name, description: description, groups: [
          for (final (i, words) in chunk(singleWords.where(test).toList(), groupSize).indexed)
            WordGroup(id: '$id-${i + 1}', name: '$name 第 ${i + 1} 組', words: words),
        ]),
    ];
    return WordRepository._(mergedGroups, phraseGroups, examTracks, byWord,
        byWord.keys.toList()..sort(), lemmas, phrasesByWord, corrected);
  }

  static Future<WordRepository> load() async {
    final groups = parseGroups(await rootBundle.loadString('assets/words.json'));
    final corrections =
        jsonDecode(await rootBundle.loadString('assets/corrections.json')) as Map<String, dynamic>;
    final bytes = await rootBundle.load('assets/dictionary.tsv.gz');
    final text = utf8.decode(await gunzip(bytes.buffer.asUint8List()));
    // 桌面版在背景執行；網頁版沒有背景執行緒，會直接在畫面執行緒跑（約一兩秒）
    final dictionary = await compute(parseDictionary, text);
    return WordRepository(groups: groups, dictionary: dictionary, corrections: corrections);
  }

  int get size => _byWord.length;

  Word? find(String word) => _byWord[word.toLowerCase()];

  /// 這個字在 corrections.json 裡修正過哪些項目。
  Set<FixKind> correctedKinds(String word) => _corrected[word.toLowerCase()] ?? const {};

  /// 回報的項目是否都已修正。
  bool isResolved(String word, Set<FixKind> kinds) =>
      kinds.isNotEmpty && correctedKinds(word).containsAll(kinds);

  /// 含有這個字的片語，最常用的在前面。
  List<Word> relatedPhrases(Word word, {int limit = 12}) => word.isPhrase
      ? const []
      : (_phrasesByWord[word.key] ?? const []).take(limit).toList();

  /// 英文：完全相符 → 變化形的原形（went → go）→ 開頭相符 → 包含，後兩者依常用度排序。
  /// 中文：簡短解釋相符優先，再找完整解釋，依常用度排序。
  List<Word> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    if (_cjk.hasMatch(q)) return _searchChinese(q);

    final seen = <String>{};
    final out = <Word>[];
    void addAll(Iterable<Word> words) {
      for (final w in words) {
        if (out.length >= maxResults) return;
        if (seen.add(w.key)) out.add(w);
      }
    }

    addAll([?_byWord[q]]);
    addAll((_lemmas[q] ?? const {}).map((k) => _byWord[k]!));
    addAll(_byRank(_prefixMatches(q)));
    if (q.length >= 3) {
      addAll(_byRank(_byWord.values.where((w) => w.key.contains(q))));
    }
    return out;
  }

  Iterable<Word> _prefixMatches(String q) sync* {
    // 二分搜尋找到第一個 >= q 的位置，往後讀到不再以 q 開頭為止
    var lo = 0, hi = _sortedKeys.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sortedKeys[mid].compareTo(q) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < _sortedKeys.length && _sortedKeys[i].startsWith(q); i++) {
      yield _byWord[_sortedKeys[i]]!;
    }
  }

  List<Word> _searchChinese(String q) {
    final hits = <(int, Word)>[];
    for (final w in _byWord.values) {
      if (w.meaning == q) {
        hits.add((0, w));
      } else if (w.meaning.contains(q)) {
        hits.add((1, w));
      } else if (w.definitionsRaw.contains(q)) {
        hits.add((2, w));
      }
    }
    hits.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.rank - b.$2.rank);
    return [for (final (_, w) in hits.take(maxResults)) w];
  }

  /// 依常用度排序：單字看詞頻排名，片語（沒有排名）看例句出現次數。
  static List<Word> _byRank(Iterable<Word> words) => words.toList()
    ..sort((a, b) => a.rank != b.rank ? a.rank - b.rank : b.usage - a.usage);

  static final _cjk = RegExp(r'[㐀-鿿]');
}

List<WordGroup> parseGroups(String raw) {
  final data = jsonDecode(raw) as Map<String, dynamic>;
  return [
    for (final g in data['groups'] as List)
      WordGroup(
        id: g['id'] as String,
        name: g['name'] as String,
        words: [
          for (final w in g['words'] as List) Word.fromJson(w as Map<String, dynamic>),
        ],
      ),
  ];
}

/// 解析解壓縮後的字庫（每行一個字）。
List<Word> parseDictionary(String tsv) => [
      for (final line in const LineSplitter().convert(tsv))
        if (line.isNotEmpty) Word.fromTsv(line),
    ];
