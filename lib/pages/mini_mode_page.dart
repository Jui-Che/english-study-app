import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../models.dart';
import '../platform/window_mode.dart';
import '../widgets/copy.dart';
import '../widgets/word_tile.dart';
import 'word_detail_page.dart' show highlight;

/// 迷你模式：視窗縮小並固定在最上層（Windows），像字卡一樣邊工作邊複習，也能快速查字。
/// 鍵盤：← → 換字、空白鍵顯示解釋。
class MiniModePage extends StatefulWidget {
  const MiniModePage({super.key});

  @override
  State<MiniModePage> createState() => _MiniModePageState();
}

class _MiniModePageState extends State<MiniModePage> {
  static const _autoInterval = Duration(seconds: 5);

  late List<(String, List<Word>)> _sources;
  int _source = 0;
  List<Word> _words = const [];
  int _index = 0;
  bool _revealed = false;
  bool _shuffled = false;
  Timer? _auto;

  bool _searching = false;
  String _query = '';

  /// 從搜尋點進來的字，換下一個字時就回到清單。
  Word? _lookup;

  @override
  void initState() {
    super.initState();
    setCompactWindow(true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    final repo = scope.repo;
    final favorites =
        scope.store.favorites.reversed.map(repo.find).whereType<Word>().toList();
    _sources = [
      ('我的收藏', favorites),
      ('主題單字', [for (final g in repo.groups) ...g.words]),
      ('常用片語', [for (final g in repo.phraseGroups) ...g.words]),
      for (final track in repo.examTracks) (track.name, [for (final g in track.groups) ...g.words]),
    ];
    // 收藏是空的就從主題單字開始
    if (_words.isEmpty) _selectSource(favorites.isEmpty ? 1 : 0);
  }

  @override
  void dispose() {
    _auto?.cancel();
    setCompactWindow(false);
    super.dispose();
  }

  void _selectSource(int i) {
    _source = i;
    _words = [..._sources[i].$2];
    if (_shuffled) _words.shuffle();
    _index = 0;
    _revealed = false;
    _lookup = null;
  }

  Word? get _current => _lookup ?? (_words.isEmpty ? null : _words[_index]);

  void _move(int delta) {
    if (_words.isEmpty) return;
    setState(() {
      if (_lookup != null) {
        _lookup = null;
      } else {
        _index = (_index + delta) % _words.length;
      }
      _revealed = false;
    });
  }

  void _toggleReveal() => setState(() => _revealed = !_revealed);

  void _toggleAuto() {
    setState(() {
      if (_auto != null) {
        _auto!.cancel();
        _auto = null;
      } else {
        // 每隔幾秒：先顯示解釋，下一次換下一個字
        _auto = Timer.periodic(_autoInterval, (_) => _revealed ? _move(1) : _toggleReveal());
      }
    });
  }

  void _toggleShuffle() {
    setState(() {
      _shuffled = !_shuffled;
      _selectSource(_source);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 12,
        automaticallyImplyLeading: false,
        title: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _source,
            items: [
              for (final (i, (label, words)) in _sources.indexed)
                DropdownMenuItem(value: i, child: Text('$label（${words.length}）')),
            ],
            onChanged: (i) => setState(() => _selectSource(i!)),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _searching ? '回到字卡' : '查單字',
            icon: Icon(_searching ? Icons.style : Icons.search),
            onPressed: () => setState(() => _searching = !_searching),
          ),
          IconButton(
            tooltip: '離開迷你模式',
            icon: const Icon(Icons.open_in_full),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: _searching ? _buildSearch(context) : _buildCard(context),
    );
  }

  Widget _buildSearch(BuildContext context) {
    final results = AppScope.of(context).repo.search(_query);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '輸入英文或中文',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, i) {
              final w = results[i];
              return ListTile(
                dense: true,
                title: Text(w.word, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(w.posAndMeaning, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => setState(() {
                  _lookup = w;
                  _revealed = true;
                  _searching = false;
                }),
                onLongPress: () => copyToClipboard(context, w.word),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context) {
    final word = _current;
    final t = Theme.of(context);
    if (word == null) {
      return const Center(child: Text('這個清單還沒有單字'));
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.space): _toggleReveal,
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _toggleReveal,
                    onLongPress: () => copyToClipboard(context, word.word),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_lookup != null)
                            Text('查詢結果', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.primary)),
                          Text(word.word,
                              style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          if (word.phonetic.isNotEmpty)
                            Text(word.phonetic, style: TextStyle(color: t.colorScheme.outline)),
                          const SizedBox(height: 16),
                          if (_revealed)
                            Text(word.posAndMeaning, style: t.textTheme.titleLarge)
                          else
                            Text('點一下或按空白鍵看解釋', style: TextStyle(color: t.colorScheme.outline)),
                          if (word.example.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text.rich(
                              highlight(word.example, [word.word, ...word.forms.values], t.colorScheme.primary),
                              style: t.textTheme.bodyLarge,
                            ),
                            if (_revealed)
                              Text(word.exampleZh, style: TextStyle(color: t.colorScheme.outline)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(tooltip: '上一個（←）', icon: const Icon(Icons.chevron_left), onPressed: () => _move(-1)),
                  IconButton(
                    tooltip: _auto == null ? '自動播放' : '停止自動播放',
                    icon: Icon(_auto == null ? Icons.play_arrow : Icons.pause),
                    onPressed: _toggleAuto,
                  ),
                  IconButton(
                    tooltip: _shuffled ? '依原本順序' : '隨機順序',
                    icon: Icon(Icons.shuffle, color: _shuffled ? t.colorScheme.primary : null),
                    onPressed: _toggleShuffle,
                  ),
                  Expanded(
                    child: Text('${_index + 1} / ${_words.length}', textAlign: TextAlign.center),
                  ),
                  FavoriteButton(word: word.word),
                  IconButton(tooltip: '下一個（→）', icon: const Icon(Icons.chevron_right), onPressed: () => _move(1)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
