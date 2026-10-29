/// 一個單字（含中文解釋與簡單例句）。
class Word {
  const Word({
    required this.word,
    this.phonetic = '',
    this.pos = '',
    required this.meaning,
    this.example = '',
    this.exampleZh = '',
    this.definitionsRaw = '',
    this.rank = unranked,
    this.collins = 0,
    this.oxford = false,
    this.tagsRaw = '',
    this.exchange = '',
    this.usage = 0,
  });

  /// 沒有詞頻排名的字。
  static const unranked = 999999;

  final String word;
  final String phonetic;

  /// 詞性，例如 n.、v.、adj.
  final String pos;

  /// 簡短中文解釋（清單與配對遊戲用）。
  final String meaning;
  final String example;
  final String exampleZh;

  /// 完整中文解釋，多行以字面上的 `\n` 分隔。
  final String definitionsRaw;

  /// 詞頻排名，越小越常用。
  final int rank;

  /// 柯林斯星級 0–5。
  final int collins;

  /// 是否為牛津 3000 核心字。
  final bool oxford;

  /// ECDICT 考試標籤，例如 "gk cet4 toefl"。
  final String tagsRaw;

  /// ECDICT 詞形變化，例如 "p:went/d:gone/i:going/3:goes"。
  final String exchange;

  /// 片語在日常例句（Tatoeba）中出現的句數，越大越常用；單字為 0。
  final int usage;

  String get key => word.toLowerCase();

  /// 「n. 蘋果」；沒有詞性時只有解釋。
  String get posAndMeaning => pos.isEmpty ? meaning : '$pos $meaning';

  bool get isPhrase => word.contains(' ');

  List<String> get definitions =>
      definitionsRaw.isEmpty ? const [] : definitionsRaw.split(r'\n');

  List<String> get tags =>
      tagsRaw.isEmpty ? const [] : tagsRaw.split(' ');

  /// 詞形變化：代號 → 單字，代號見 [formLabels]。
  Map<String, String> get forms => {
        for (final part in exchange.split('/'))
          if (part.length > 2 && part[1] == ':' && formLabels.containsKey(part[0]))
            part[0]: part.substring(2),
      };

  static const formLabels = {
    'p': '過去式',
    'd': '過去分詞',
    'i': '現在分詞',
    '3': '第三人稱單數',
    's': '複數',
    'r': '比較級',
    't': '最高級',
  };

  factory Word.fromJson(Map<String, dynamic> json) => Word(
        word: json['word'] as String,
        phonetic: json['phonetic'] as String? ?? '',
        pos: json['pos'] as String? ?? '',
        meaning: json['meaning'] as String,
        example: json['example'] as String? ?? '',
        exampleZh: json['exampleZh'] as String? ?? '',
      );

  /// 解析 tool/build_dictionary.dart 產生的一行 TSV。
  factory Word.fromTsv(String line) {
    final f = line.split('\t');
    return Word(
      word: f[0],
      phonetic: f[1],
      pos: f[2],
      meaning: f[3],
      definitionsRaw: f[4],
      rank: int.parse(f[5]),
      collins: int.parse(f[6]),
      oxford: f[7] == '1',
      tagsRaw: f[8],
      exchange: f[9],
      example: f[10],
      exampleZh: f[11],
      usage: int.parse(f[12]),
    );
  }

  /// 手動整理的字（this）優先，字典補上完整解釋、詞頻、標籤、詞形變化。
  Word mergedWith(Word dict) => Word(
        word: word,
        phonetic: phonetic.isNotEmpty ? phonetic : dict.phonetic,
        pos: pos.isNotEmpty ? pos : dict.pos,
        meaning: meaning,
        example: example.isNotEmpty ? example : dict.example,
        exampleZh: example.isNotEmpty ? exampleZh : dict.exampleZh,
        definitionsRaw: dict.definitionsRaw,
        rank: dict.rank,
        collins: dict.collins,
        oxford: dict.oxford,
        tagsRaw: dict.tagsRaw,
        exchange: dict.exchange,
        usage: dict.usage,
      );

  /// 套用 assets/corrections.json 的一筆修正；沒填的欄位沿用原本的。
  Word withCorrection(Map<String, dynamic> c) => Word(
        word: word,
        phonetic: phonetic,
        pos: c['pos'] as String? ?? pos,
        meaning: c['meaning'] as String? ?? meaning,
        example: c['example'] as String? ?? example,
        exampleZh: c['exampleZh'] as String? ?? exampleZh,
        definitionsRaw: (c['definitions'] as List?)?.cast<String>().join(r'\n') ?? definitionsRaw,
        rank: rank,
        collins: collins,
        oxford: oxford,
        tagsRaw: tagsRaw,
        exchange: exchange,
        usage: usage,
      );
}

/// 「待調整」要處理的項目。
enum FixKind {
  meaning('中文解釋'),
  example('補例句');

  const FixKind(this.label);

  final String label;

  /// corrections.json 的一筆修正處理了哪些項目。
  static Set<FixKind> resolvedBy(Map<String, dynamic> correction) => {
        if (correction.keys.any({'meaning', 'definitions', 'pos'}.contains)) meaning,
        if (correction.containsKey('example')) example,
      };
}

/// 一種考試（TOEFL、IELTS…）的單字，切成每 20 字一組。
class ExamTrack {
  const ExamTrack({
    required this.id,
    required this.name,
    required this.description,
    required this.groups,
  });

  final String id;
  final String name;
  final String description;
  final List<WordGroup> groups;

  int get wordCount => groups.fold(0, (n, g) => n + g.words.length);
}

/// 一組要一起學的單字（通常 20 個）。
class WordGroup {
  const WordGroup({required this.id, required this.name, required this.words});

  final String id;
  final String name;
  final List<Word> words;
}

/// 某一組配對練習的最佳成績。
class BestScore {
  const BestScore({required this.accuracy, required this.seconds});

  /// 0–1 之間的正確率。
  final double accuracy;
  final int seconds;

  bool isBetterThan(BestScore? other) {
    if (other == null) return true;
    if (accuracy != other.accuracy) return accuracy > other.accuracy;
    return seconds < other.seconds;
  }

  Map<String, dynamic> toJson() => {'accuracy': accuracy, 'seconds': seconds};

  factory BestScore.fromJson(Map<String, dynamic> json) => BestScore(
        accuracy: (json['accuracy'] as num).toDouble(),
        seconds: json['seconds'] as int,
      );
}
