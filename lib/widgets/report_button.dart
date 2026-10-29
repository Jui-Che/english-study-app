import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models.dart';

/// 單字頁右上角的 🚩：回報中文解釋有誤或需要補例句，加入「待調整」，可附上備註。
class ReportButton extends StatelessWidget {
  const ReportButton({super.key, required this.word});

  final Word word;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final flagged = store.needsFix(word.word);
        return IconButton(
          tooltip: flagged ? '編輯待調整' : '回報問題（解釋、例句）',
          icon: Icon(flagged ? Icons.flag : Icons.outlined_flag,
              color: flagged ? Theme.of(context).colorScheme.error : null),
          onPressed: () => showReportDialog(context, word),
        );
      },
    );
  }
}

/// 開啟回報視窗；[preset] 是預先勾選的項目（例如從「沒有例句」那裡點進來）。
Future<void> showReportDialog(BuildContext context, Word word, {Set<FixKind>? preset}) async {
  final store = AppScope.of(context).store;
  final flagged = store.needsFix(word.word);
  final result = await showDialog<(Set<FixKind>, String)>(
    context: context,
    builder: (_) => _ReportDialog(
      word: word,
      kinds: flagged
          ? {...store.toFixKinds(word.word), ...?preset}
          : preset ?? {FixKind.meaning},
      note: store.toFixNote(word.word) ?? '',
      flagged: flagged,
    ),
  );
  if (result case (final kinds, final note)) {
    await store.markToFix(word.word, note, kinds);
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.word,
    required this.kinds,
    required this.note,
    required this.flagged,
  });

  final Word word;
  final Set<FixKind> kinds;
  final String note;
  final bool flagged;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late final _note = TextEditingController(text: widget.note);
  late final Set<FixKind> _kinds = {...widget.kinds};

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('回報問題，加入待調整'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.word.word, style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('目前：${widget.word.posAndMeaning}'),
            const SizedBox(height: 16),
            Text('需要處理', style: t.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final kind in FixKind.values)
                  FilterChip(
                    label: Text(kind.label),
                    selected: _kinds.contains(kind),
                    onSelected: (on) => setState(() => on ? _kinds.add(kind) : _kinds.remove(kind)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '備註（選填）',
                hintText: '例如：應該是「相處」、想要職場情境的例句',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.flagged)
          TextButton(
            onPressed: () => Navigator.pop(context, (<FixKind>{}, '')),
            child: const Text('移出待調整'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _kinds.isEmpty ? null : () => Navigator.pop(context, (_kinds, _note.text)),
          child: Text(widget.flagged ? '更新' : '加入待調整'),
        ),
      ],
    );
  }
}
