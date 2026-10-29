import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../data/word_repository.dart';
import '../models.dart';
import '../widgets/copy.dart';
import '../widgets/word_tile.dart';
import 'word_detail_page.dart';

/// 「收藏」分頁：收藏的單字，以及回報為解釋有誤的「待調整」清單。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _showToFix = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: scope.store,
        builder: (context, _) {
          final store = scope.store;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.star_outline),
                      label: Text('收藏（${store.favorites.length}）'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.outlined_flag),
                      label: Text('待調整（${store.toFix.length}）'),
                    ),
                  ],
                  selected: {_showToFix},
                  onSelectionChanged: (s) => setState(() => _showToFix = s.first),
                ),
              ),
              // 清單由這裡算好傳進去，收藏或待調整變動時才會跟著更新
              Expanded(
                child: _showToFix
                    ? _ToFixList(keys: store.toFix.reversed.toList())
                    : _FavoriteList(
                        // 新收藏的排在最上面
                        words: store.favorites.reversed
                            .map(scope.repo.find)
                            .whereType<Word>()
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FavoriteList extends StatelessWidget {
  const _FavoriteList({required this.words});

  final List<Word> words;

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) {
      return const Center(
        child: Text('還沒有收藏的單字\n在查詢頁或配對結果點 ☆ 就能加入', textAlign: TextAlign.center),
      );
    }
    return ListView.builder(
      itemCount: words.length,
      itemBuilder: (_, i) => WordTile(word: words[i]),
    );
  }
}

class _ToFixList extends StatefulWidget {
  const _ToFixList({required this.keys});

  /// 新回報的排在最上面。
  final List<String> keys;

  @override
  State<_ToFixList> createState() => _ToFixListState();
}

class _ToFixListState extends State<_ToFixList> {
  /// null 表示全部。
  FixKind? _filter;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    if (widget.keys.isEmpty) {
      return const Center(
        child: Text('還沒有待調整的字\n在單字頁點右上角 🚩 就能加入', textAlign: TextAlign.center),
      );
    }
    bool resolved(String key) => scope.repo.isResolved(key, store.toFixKinds(key));
    final fixed = widget.keys.where(resolved).toList();
    final keys = _filter == null
        ? widget.keys
        : widget.keys.where((k) => store.toFixKinds(k).contains(_filter)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final kind in [null, ...FixKind.values])
                ChoiceChip(
                  label: Text(kind?.label ?? '全部'),
                  selected: _filter == kind,
                  onSelected: (_) => setState(() => _filter = kind),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text('${widget.keys.length} 筆，${fixed.length} 筆已修正'),
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('複製清單'),
                onPressed: () => copyToClipboard(
                  context,
                  toFixReport(scope.repo, store),
                  message: '已複製待調整清單（${widget.keys.length - fixed.length} 筆），可以貼給 Claude 處理',
                ),
              ),
              if (fixed.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.done_all),
                  label: const Text('清除已修正'),
                  onPressed: () => store.removeToFix(fixed),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: keys.length,
            itemBuilder: (context, i) {
              final key = keys[i];
              final word = scope.repo.find(key);
              final note = store.toFixNote(key) ?? '';
              return ListTile(
                title: Text(key, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  '需要：${store.toFixKinds(key).map((k) => k.label).join('、')}',
                  if (word != null) '目前：${word.pos} ${word.meaning}',
                  if (note.isNotEmpty) '備註：$note',
                ].join('\n')),
                isThreeLine: true,
                trailing: resolved(key)
                    ? const Chip(label: Text('已修正'), visualDensity: VisualDensity.compact)
                    : IconButton(
                        tooltip: '移出待調整',
                        icon: const Icon(Icons.close),
                        onPressed: () => store.removeToFix([key]),
                      ),
                onTap: word == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => WordDetailPage(word: word)),
                        ),
                onLongPress: () => copyToClipboard(context, key),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 待調整清單的文字版，貼給 Claude 修正用。只列出還沒修正的。
String toFixReport(WordRepository repo, UserStore store) {
  final lines = <String>[];
  for (final key in store.toFix) {
    final kinds = store.toFixKinds(key);
    if (repo.isResolved(key, kinds)) continue;
    final word = repo.find(key);
    final note = store.toFixNote(key) ?? '';
    lines.add([
      key,
      '需要：${kinds.map((k) => k.label).join('、')}',
      if (word != null) '目前：${word.pos} ${word.meaning}',
      if (word != null && kinds.contains(FixKind.example))
        '目前例句：${word.example.isEmpty ? '（無）' : word.example}',
      if (note.isNotEmpty) '備註：$note',
    ].join('｜'));
  }
  return '待調整清單（${lines.length} 筆）\n${lines.join('\n')}';
}
