// 把原始資料轉成 App 內建字庫 assets/dictionary.tsv.gz。
//
// 用法（在 vocab_app 資料夾下）：
//   dart run tool/build_dictionary.dart <原始資料資料夾>
//
// 原始資料資料夾需包含：
//   ecdict.csv                       https://github.com/skywind3000/ECDICT (MIT)
//   STCharacters.txt STPhrases.txt   https://github.com/BYVoid/OpenCC (Apache 2.0)
//   TWPhrases.txt TWVariants.txt
//   cmn-eng/cmn.txt                  https://www.manythings.org/anki/ (Tatoeba, CC-BY 2.0 FR)
//
// 輸出每行一個字，欄位以 Tab 分隔（順序見 columns）。多行解釋以字面上的 \n 分隔。
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const columns = [
  'word', 'phonetic', 'pos', 'meaning', 'definitions', 'rank',
  'collins', 'oxford', 'tags', 'exchange', 'example', 'exampleZh',
  'usage', // 片語在 Tatoeba 例句中出現的句數，單字為 0
];

/// 片語至少要在這麼多句 Tatoeba 例句中出現才收錄（考試、牛津、柯林斯片語不受限）。
const minPhraseUsage = 3;

/// 片語中的代稱：one's 可對應 my / his …，sb / sth 可對應任一個字。
const _possessives = {"my", "your", "his", "her", "its", "our", "their", "one's"};
const _reflexives = {
  'myself', 'yourself', 'himself', 'herself', 'itself', 'ourselves', 'yourselves', 'themselves', 'oneself',
};
const _wildcards = {'sb', 'sth'};

// 以下用來排除「只是普通字詞組合」的片語，例如 want to、he is、tell me、the world。
const _functionWords = {
  'a', 'an', 'the', 'to', 'for', 'in', 'on', 'at', 'of', 'this', 'that', 'there', 'all', 'it',
  'be', 'is', 'am', 'are', 'was', 'were', 'been', 'do', 'does', 'did', 'have', 'has', 'had',
  'i', 'you', 'he', 'she', 'we', 'they', 'me', 'him', 'her', 'us', 'them',
};
const _subjectPronouns = {'i', 'you', 'he', 'she', 'we', 'they'};
const _objectPronouns = {'me', 'you', 'him', 'her', 'it', 'us', 'them'};
const _verbToAllowed = {'have to', 'has to', 'used to', 'ought to', 'need to'};
const _articleAllowed = {'lot', 'little', 'few', 'bit', 'same', 'while', 'couple'};
const _auxiliaries = {
  'to', 'not', 'would', 'will', 'can', 'could', 'should', 'must', 'may', 'might', 'shall',
  "don't", "doesn't", "didn't",
};
/// 兩個字合起來也是單字、但意思不同的片語，例如 every day（每天）≠ everyday（日常的）。
const _keepDespiteCompound = {'every day', 'some time', 'any one', 'every one', 'may be'};

/// 從 Tatoeba 統計補進來的片語，要通過這些規則才收。
bool usefulPhrase(
  String key,
  Map<String, String> e,
  Map<String, Map<String, String>> words,
  Map<String, Set<String>> lemmasOf,
) {
  final t = key.split(' ');
  if (t.every(_functionWords.contains)) return false;
  // looking for、came to 是 look for、come to 的變化形，留原形就好
  final inflected = (lemmasOf[t[0]] ?? const {}).any((l) => l != t[0]);
  if (inflected && !_verbToAllowed.contains(key)) return false;
  if (t.length == 2) {
    if (_subjectPronouns.contains(t[0]) || _objectPronouns.contains(t[1])) return false;
    // 動詞 + to（want to、try to）只是不定詞，不算片語
    final isVerb = parseExchange(words[t[0]]?['exchange'] ?? '').containsKey('p');
    if (t[1] == 'to' && isVerb && !_verbToAllowed.contains(key)) return false;
    if ({'a', 'an', 'the'}.contains(t[0]) && !_articleAllowed.contains(t[1])) return false;
    // to go、would be、don't know 這類助動詞開頭，或 by this 這類代名詞結尾的
    if (_auxiliaries.contains(t[0]) || {'this', 'that', 'it'}.contains(t[1])) return false;
    // here by（hereby）、on going（ongoing）、know how（know-how）其實是單字拆開寫
    if (!_keepDespiteCompound.contains(key) &&
        (words.containsKey(t.join()) || words.containsKey(t.join('-')))) {
      return false;
    }
  }
  // 只有網路釋義、歌名、網路流行語的不收
  final lines = e['translation']!.split(r'\n');
  if (lines.every((l) => l.startsWith('[网络]'))) return false;
  if (lines.first.contains('歌曲') || lines.first.contains('网络热词')) return false;
  return true;
}

/// OpenCC 的台灣用語表偏向資訊術語，這些在一般字典裡會轉錯
/// （例如 genre「類型」→「型別」、menu「菜單」→「選單」），所以不轉。
const itOnlyPhrases = {
  '類型', '文件', '對象', '局部', '全局', '實例', '映射', '擴展', '權限', '項目',
  '循環', '刷新', '菜單', '拋出', '溢出', '鏡像', '調度', '死機', '審覈', '剪切',
  '綁定', '網卡',
};

/// 排名在這之內的常用字都收；冷門字則需有考試標籤、牛津 3000 或柯林斯星級。
const maxRank = 30000;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('用法：dart run tool/build_dictionary.dart <原始資料資料夾>');
    exit(64);
  }
  final raw = args.first;
  final sw = Stopwatch()..start();

  final s2t = Converter({
    ...loadOpencc('$raw/STCharacters.txt'),
    ...loadOpencc('$raw/STPhrases.txt'),
  });
  final twPhrases = Converter(
    loadOpencc('$raw/TWPhrases.txt')..removeWhere((k, _) => itOnlyPhrases.contains(k)),
  );
  final twVariants = Converter(loadOpencc('$raw/TWVariants.txt'));
  String toTw(String s) => twVariants.convert(twPhrases.convert(s2t.convert(s)));

  final curated = curatedWords('assets/words.json');

  // 1. 篩選 ECDICT
  final entries = <String, Map<String, String>>{};
  // 還沒確定要收的片語，之後依 Tatoeba 出現次數決定
  final phraseCandidates = <String, Map<String, String>>{};
  final header = <String>[];
  var total = 0;
  for (final row in csvRows(File('$raw/ecdict.csv').readAsStringSync())) {
    if (header.isEmpty) {
      header.addAll(row);
      continue;
    }
    total++;
    if (row.length < header.length) continue;
    final e = {for (var i = 0; i < header.length; i++) header[i]: row[i].trim()};
    final word = e['word']!;
    final key = word.toLowerCase();
    if (!keep(e, curated.contains(key))) {
      if (_phraseRe.hasMatch(word) && e['translation']!.isNotEmpty) phraseCandidates[key] = e;
      continue;
    }
    final prev = entries[key];
    // 同一個字有大小寫兩種時（Apple / apple），優先保留小寫
    if (prev != null && (prev['word'] == key || word != key)) continue;
    entries[key] = e;
  }
  stdout.writeln('ECDICT $total 筆 → 保留 ${entries.length} 筆（${sw.elapsed.inSeconds}s）');

  // 2. 由詞形變化建立「變化形 → 原形」對照，用來幫例句找單字
  final lemmasOf = <String, Set<String>>{};
  for (final MapEntry(:key, :value) in entries.entries) {
    lemmasOf.putIfAbsent(key, () => {}).add(key);
    for (final form in parseExchange(value['exchange']!).values) {
      lemmasOf.putIfAbsent(form.toLowerCase(), () => {}).add(key);
    }
  }

  // 3. 準備片語比對：每個字可對應它的變化形（take care of ↔ took care of）
  Set<String>? alternatives(String token) {
    if (token == "one's") return _possessives;
    if (token == 'oneself') return _reflexives;
    if (_wildcards.contains(token)) return null; // 任一個字
    return {token, ...parseExchange(entries[token]?['exchange'] ?? '').values.map((f) => f.toLowerCase())};
  }

  final phrasesByFirst = <String, List<(String, List<Set<String>?>)>>{};
  for (final key in [
    ...entries.keys.where(_phraseRe.hasMatch),
    ...phraseCandidates.keys,
  ]) {
    final pattern = key.split(' ').map(alternatives).toList();
    final first = pattern.first;
    // 開頭或結尾是 sb / sth 的（go to sth）會跟任何句子都對得上，不統計
    if (first == null || pattern.last == null) continue;
    for (final f in first) {
      phrasesByFirst.putIfAbsent(f, () => []).add((key, pattern));
    }
  }

  // 4. 掃過 Tatoeba：幫每個字、每個片語挑一句最短、最簡單的例句，並統計片語出現次數
  final best = <String, (int, String, String)>{};
  final usage = <String, int>{};
  final seenSentences = <String>{};
  final tokenRe = RegExp(r"[a-z]+(?:'[a-z]+)?");
  void offer(String key, int score, String en, String zh) {
    final cur = best[key];
    if (cur == null || score < cur.$1) best[key] = (score, en, zh);
  }

  for (final line in File('$raw/cmn-eng/cmn.txt').readAsLinesSync()) {
    final parts = line.split('\t');
    if (parts.length < 2) continue;
    final en = parts[0].trim(), zh = parts[1].trim();
    final tokens = tokenRe.allMatches(en.toLowerCase()).map((m) => m[0]!).toList();
    final firstTime = seenSentences.add(en); // 同一句英文有多個中文翻譯時只算一次
    // 句子越短分數越低越好；太短（3 個字）稍微扣分
    final goodExample = tokens.length >= 3 && tokens.length <= 12;
    final baseScore = tokens.length + (tokens.length < 4 ? 3 : 0);

    final matched = <String>{};
    for (var i = 0; i < tokens.length; i++) {
      for (final (key, pattern) in phrasesByFirst[tokens[i]] ?? const <(String, List<Set<String>?>)>[]) {
        if (i + pattern.length > tokens.length) continue;
        var ok = true;
        for (var j = 1; j < pattern.length && ok; j++) {
          ok = pattern[j] == null || pattern[j]!.contains(tokens[i + j]);
        }
        if (ok) matched.add(key);
      }
    }
    for (final key in matched) {
      if (firstTime) usage[key] = (usage[key] ?? 0) + 1;
      if (goodExample) offer(key, baseScore, en, zh);
    }

    if (!goodExample) continue;
    for (final t in tokens.toSet()) {
      for (final lemma in lemmasOf[t] ?? const <String>{}) {
        // 用原形出現比變化形好
        offer(lemma, baseScore + (t == lemma ? 0 : 2), en, zh);
      }
    }
  }

  final picked = [
    for (final MapEntry(:key, :value) in phraseCandidates.entries)
      if ((usage[key] ?? 0) >= minPhraseUsage && usefulPhrase(key, value, entries, lemmasOf)) key,
  ];
  // 「lot of」幾乎都出現在「a lot of」裡，只留較長的那個
  final allPhrases = [...entries.keys.where(_phraseRe.hasMatch), ...picked];
  bool coveredByLonger(String p) => allPhrases.any((q) =>
      q.length > p.length &&
      ' $q '.contains(' $p ') &&
      (usage[q] ?? 0) >= 0.8 * (usage[p] ?? 0));
  var added = 0;
  for (final key in picked) {
    if (!coveredByLonger(key)) {
      entries[key] = phraseCandidates[key]!;
      added++;
    }
  }
  final phraseCount = entries.keys.where(_phraseRe.hasMatch).length;
  stdout.writeln('片語：依 Tatoeba 新增 $added 個，共 $phraseCount 個片語');
  stdout.writeln('例句：${best.length} 個字或片語找到例句（${sw.elapsed.inSeconds}s）');

  // 5. 輸出
  final out = StringBuffer();
  final rows = entries.values.toList()
    ..sort((a, b) => rankOf(a).compareTo(rankOf(b)));
  for (final e in rows) {
    final key = e['word']!.toLowerCase();
    final lines = toTw(e['translation']!)
        .split(r'\n')
        .map((l) => balanceBrackets(l.trim().replaceFirst(RegExp(r'^a\. '), 'adj. ')))
        .where((l) => l.isNotEmpty)
        .toList();
    final (pos, meaning) = shortMeaning(lines);
    final ex = best[key];
    final fields = [
      e['word']!,
      formatPhonetic(e['phonetic']!),
      pos,
      meaning,
      lines.join(r'\n'),
      '${rankOf(e)}',
      e['collins']!.isEmpty ? '0' : e['collins']!,
      e['oxford'] == '1' ? '1' : '0',
      e['tag']!,
      e['exchange']!,
      ex?.$2 ?? '',
      ex == null ? '' : toTw(ex.$3),
      _phraseRe.hasMatch(key) ? '${usage[key] ?? 0}' : '0',
    ];
    out.writeln(fields.map((f) => f.replaceAll(RegExp(r'[\t\r\n]'), ' ')).join('\t'));
  }
  final bytes = gzip.encode(utf8.encode(out.toString()));
  File('assets/dictionary.tsv.gz').writeAsBytesSync(bytes);
  stdout.writeln('寫入 assets/dictionary.tsv.gz：${rows.length} 筆，'
      '${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB（${sw.elapsed.inSeconds}s）');
}

final _wordRe = RegExp(r"^[A-Za-z][A-Za-z' -]*$");

/// 2–5 個小寫英文字組成的片語（排除專有名詞）。
final _phraseRe = RegExp(r"^[a-z][a-z']*( [a-z][a-z']*){1,4}$");

bool keep(Map<String, String> e, bool isCurated) {
  final word = e['word']!;
  if (isCurated) return true;
  if (e['translation']!.isEmpty || word.length > 30 || !_wordRe.hasMatch(word)) return false;
  final important = e['tag']!.isNotEmpty ||
      e['oxford'] == '1' ||
      (int.tryParse(e['collins']!) ?? 0) > 0;
  if (word.contains(' ')) return important; // 片語只收重要的
  return important || rankOf(e) <= maxRank;
}

/// BNC 與當代語料庫詞頻排名取較好的那個；沒有排名的排最後。
int rankOf(Map<String, String> e) {
  final ranks = [e['frq'], e['bnc']]
      .map((v) => int.tryParse(v ?? '') ?? 0)
      .where((v) => v > 0);
  return ranks.isEmpty ? 999999 : ranks.reduce(min);
}

final _posRe = RegExp(r'^((?:[a-z]+\.\s*)+)');

/// 從翻譯取出詞性與一個簡短中文解釋（配對遊戲用），例如 ("n.", "蘋果；傢伙")。
(String, String) shortMeaning(List<String> lines) {
  // [網路]、[醫] 這類行放到最後才考慮
  final main = lines.where((l) => !l.startsWith('[')).toList();
  final first = (main.isEmpty ? lines : main).first;
  final m = _posRe.firstMatch(first);
  final pos = m == null ? '' : m[1]!.trim().split(RegExp(r'\s+')).first;
  final body = first.substring(m?.end ?? 0).replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '');
  final senses = splitSenses(body);
  if (senses.isEmpty) return (pos, body.trim());
  final two = senses.take(2).join('；');
  return (pos, two.length <= 10 ? two : senses.first);
}

const _openers = '([（【<〈', _closers = ')]）】>〉';

/// 修正 ECDICT 原文的括號錯誤：半形、〔〕統一成全形（），並刪掉沒有配對的括號，
/// 例如「威利(人名）」→「威利（人名）」、「伊頓（姓氏））」→「伊頓（姓氏）」。
String balanceBrackets(String s) {
  final text = s.replaceAll('(', '（').replaceAll(')', '）').replaceAll('〔', '（').replaceAll('〕', '）');
  const pairs = {'）': '（', ']': '[', '】': '【'};
  final chars = text.split('');
  final open = <int>[];
  final drop = <int>{};
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    if (pairs.containsValue(c)) {
      open.add(i);
    } else if (pairs.containsKey(c)) {
      if (open.isNotEmpty && chars[open.last] == pairs[c]) {
        open.removeLast();
      } else {
        drop.add(i);
      }
    }
  }
  drop.addAll(open);
  return [for (var i = 0; i < chars.length; i++) if (!drop.contains(i)) chars[i]].join();
}

/// 依逗號、分號拆成多個意思，但括號裡的不拆：
/// 「使參與[陷入，牽扯到]; 嬋媛」→ ["使參與[陷入，牽扯到]", "嬋媛"]。
List<String> splitSenses(String text) {
  final senses = <String>[];
  final current = StringBuffer();
  var depth = 0;
  for (final ch in text.split('')) {
    if (_openers.contains(ch)) depth++;
    if (_closers.contains(ch) && depth > 0) depth--;
    if (depth == 0 && ',，;；'.contains(ch)) {
      senses.add(current.toString().trim());
      current.clear();
    } else {
      current.write(ch);
    }
  }
  senses.add(current.toString().trim());
  return senses.where((s) => s.isNotEmpty).toList();
}

/// ECDICT 的音標用 ' 表示主重音、, 表示次重音，轉成 IPA 符號並加上斜線。
String formatPhonetic(String p) =>
    p.isEmpty ? '' : '/${p.replaceAll("'", 'ˈ').replaceAll(',', 'ˌ')}/';

Map<String, String> parseExchange(String s) => {
      for (final part in s.split('/'))
        if (part.length > 2 && part[1] == ':' && 'pdi3srt'.contains(part[0]))
          part[0]: part.substring(2),
    };

Set<String> curatedWords(String path) {
  final data = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final g in data['groups'] as List)
      for (final w in g['words'] as List) (w['word'] as String).toLowerCase(),
  };
}

Map<String, String> loadOpencc(String path) {
  final m = <String, String>{};
  for (final line in File(path).readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final tab = line.indexOf('\t');
    if (tab <= 0) continue;
    m[line.substring(0, tab)] = line.substring(tab + 1).split(' ').first;
  }
  return m;
}

/// OpenCC 的「最長詞優先」轉換。
class Converter {
  Converter(this.map) : maxLen = map.keys.fold(1, (a, k) => max(a, k.length));

  final Map<String, String> map;
  final int maxLen;

  String convert(String s) {
    final out = StringBuffer();
    var i = 0;
    outer:
    while (i < s.length) {
      for (var len = min(maxLen, s.length - i); len > 0; len--) {
        final hit = map[s.substring(i, i + len)];
        if (hit != null) {
          out.write(hit);
          i += len;
          continue outer;
        }
      }
      out.writeCharCode(s.codeUnitAt(i));
      i++;
    }
    return out.toString();
  }
}

/// 支援引號、逗號、"" 跳脫的 CSV 解析。
Iterable<List<String>> csvRows(String s) sync* {
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (inQuotes) {
      if (c == 0x22) {
        if (i + 1 < s.length && s.codeUnitAt(i + 1) == 0x22) {
          field.writeCharCode(0x22);
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.writeCharCode(c);
      }
    } else if (c == 0x22) {
      inQuotes = true;
    } else if (c == 0x2C) {
      row.add(field.toString());
      field.clear();
    } else if (c == 0x0A) {
      row.add(field.toString());
      field.clear();
      yield row;
      row = [];
    } else if (c != 0x0D) {
      field.writeCharCode(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    yield row;
  }
}
