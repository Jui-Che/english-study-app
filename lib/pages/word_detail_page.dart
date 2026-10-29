import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models.dart';
import '../widgets/copy.dart';
import '../widgets/report_button.dart';
import '../widgets/word_tile.dart';

class WordDetailPage extends StatelessWidget {
  const WordDetailPage({super.key, required this.word});

  final Word word;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppScope.of(context);
    final forms = word.forms;
    final phrases = scope.repo.relatedPhrases(word);
    final corrected = scope.repo.correctedKinds(word.word);
    final badges = [
      if (corrected.contains(FixKind.meaning)) '✓ 解釋已修正',
      if (corrected.contains(FixKind.example)) '✓ 例句已補充',
      if (word.oxford) '牛津 3000',
      if (word.collins > 0) '柯林斯 ${'★' * word.collins}',
      for (final tag in word.tags)
        if (_examTags.containsKey(tag)) _examTags[tag]!,
    ];
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text(title, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(
          tooltip: '複製單字',
          icon: const Icon(Icons.copy),
          onPressed: () => copyToClipboard(context, word.word),
        ),
        ReportButton(word: word),
        FavoriteButton(word: word.word),
      ]),
      // 整頁文字都可以用滑鼠或長按選取、複製
      body: SelectionArea(
        child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(word.word, style: t.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(word.phonetic, style: t.textTheme.titleMedium?.copyWith(color: t.colorScheme.outline)),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in badges)
                  Chip(label: Text(b), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text.rich(TextSpan(children: [
            if (word.pos.isNotEmpty)
              TextSpan(text: '${word.pos}  ', style: TextStyle(color: t.colorScheme.primary)),
            TextSpan(text: word.meaning),
          ]), style: t.textTheme.headlineSmall),
          ListenableBuilder(
            listenable: scope.store,
            builder: (context, _) {
              if (!scope.store.needsFix(word.word)) return const SizedBox.shrink();
              final note = scope.store.toFixNote(word.word)!;
              final kinds = scope.store.toFixKinds(word.word).map((k) => k.label).join('、');
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '🚩 已加入待調整（$kinds）${note.isEmpty ? '' : '：$note'}',
                  style: TextStyle(color: t.colorScheme.error),
                ),
              );
            },
          ),
          section('例句'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: word.example.isEmpty
                  ? Text('這個字還沒有例句', style: TextStyle(color: t.colorScheme.outline))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          highlight(word.example, [word.word, ...forms.values], t.colorScheme.primary),
                          style: t.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(word.exampleZh,
                            style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.outline)),
                      ],
                    ),
            ),
          ),
          ListenableBuilder(
            listenable: scope.store,
            builder: (context, _) {
              final requested = scope.store.toFixKinds(word.word).contains(FixKind.example);
              return Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: Icon(requested ? Icons.flag : Icons.outlined_flag),
                  label: Text(requested
                      ? '已回報需要例句'
                      : word.example.isEmpty
                          ? '回報需要例句'
                          : '想要其他例句'),
                  onPressed: () => showReportDialog(context, word, preset: {FixKind.example}),
                ),
              );
            },
          ),
          if (phrases.isNotEmpty) ...[
            section('相關片語'),
            Card(
              child: Column(
                children: [for (final p in phrases) WordTile(word: p)],
              ),
            ),
          ],
          if (word.definitions.isNotEmpty) ...[
            section('完整解釋'),
            for (final d in word.definitions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(d, style: t.textTheme.bodyLarge),
              ),
          ],
          if (forms.isNotEmpty) ...[
            section('詞形變化'),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                for (final MapEntry(:key, :value) in forms.entries)
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '${Word.formLabels[key]}  ', style: TextStyle(color: t.colorScheme.outline)),
                    TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ])),
              ],
            ),
          ],
        ],
        ),
      ),
    );
  }
}

const _examTags = {'toefl': 'TOEFL', 'ielts': 'IELTS', 'gre': 'GRE'};

/// 把例句中出現的單字或其變化形（went、delayed…）加粗上色。
TextSpan highlight(String sentence, List<String> forms, Color color) {
  final alternatives = forms.where((f) => f.isNotEmpty).map(RegExp.escape).toList()
    ..sort((a, b) => b.length - a.length);
  final pattern = RegExp('\\b(${alternatives.join('|')})\\b', caseSensitive: false);
  final spans = <TextSpan>[];
  var last = 0;
  for (final m in pattern.allMatches(sentence)) {
    spans.add(TextSpan(text: sentence.substring(last, m.start)));
    spans.add(TextSpan(
      text: m.group(0),
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    ));
    last = m.end;
  }
  spans.add(TextSpan(text: sentence.substring(last)));
  return TextSpan(children: spans);
}
