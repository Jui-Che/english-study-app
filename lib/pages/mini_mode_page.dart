import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../models.dart';
import '../platform/window_mode.dart';
import '../widgets/copy.dart';
import 'word_detail_page.dart' show highlight;

/// 迷你模式：視窗縮小、沒有標題列並固定在最上層（Windows），用字卡複習「我的收藏」。
/// 上方列可以按住拖曳視窗。鍵盤：← → 換字、空白鍵顯示解釋。
class MiniModePage extends StatefulWidget {
  const MiniModePage({super.key});

  @override
  State<MiniModePage> createState() => _MiniModePageState();
}

class _MiniModePageState extends State<MiniModePage> {
  static const _autoInterval = Duration(seconds: 5);

  List<Word>? _words;
  int _index = 0;
  bool _revealed = false;
  bool _shuffled = false;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    setCompactWindow(true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _words ??= _loadFavorites();
  }

  @override
  void dispose() {
    _auto?.cancel();
    setCompactWindow(false);
    super.dispose();
  }

  /// 新收藏的在前面。
  List<Word> _loadFavorites() {
    final scope = AppScope.of(context);
    final words = scope.store.favorites.reversed.map(scope.repo.find).whereType<Word>().toList();
    return _shuffled ? (words..shuffle()) : words;
  }

  void _move(int delta) {
    final words = _words!;
    if (words.isEmpty) return;
    setState(() {
      _index = (_index + delta) % words.length;
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
      _words = _loadFavorites();
      _index = 0;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final words = _words!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(
              label: words.isEmpty ? '我的收藏' : '我的收藏  ${_index + 1} / ${words.length}',
            ),
            Expanded(
              child: words.isEmpty
                  ? const Center(
                      child: Text('還沒有收藏的單字\n先在一般視窗點 ☆ 收藏', textAlign: TextAlign.center),
                    )
                  : _buildCard(context, words[_index]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, Word word) {
    final t = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.space): _toggleReveal,
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _toggleReveal,
                    onLongPress: () => copyToClipboard(context, word.word),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(word.word,
                              style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          if (word.phonetic.isNotEmpty)
                            Text(word.phonetic, style: TextStyle(color: t.colorScheme.outline)),
                          const SizedBox(height: 12),
                          if (_revealed)
                            Text(word.posAndMeaning, style: t.textTheme.titleLarge)
                          else
                            Text('點一下或按空白鍵看解釋', style: TextStyle(color: t.colorScheme.outline)),
                          if (word.example.isNotEmpty) ...[
                            const SizedBox(height: 12),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(tooltip: '上一個（←）', icon: const Icon(Icons.chevron_left), onPressed: () => _move(-1)),
                  IconButton(
                    tooltip: _auto == null ? '自動播放' : '停止自動播放',
                    icon: Icon(_auto == null ? Icons.play_arrow : Icons.pause),
                    onPressed: _toggleAuto,
                  ),
                  IconButton(
                    tooltip: _shuffled ? '依收藏順序' : '隨機順序',
                    icon: Icon(Icons.shuffle, color: _shuffled ? t.colorScheme.primary : null),
                    onPressed: _toggleShuffle,
                  ),
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

/// 取代 Windows 標題列的上方列：按住空白處可拖曳視窗，右邊只有「離開迷你模式」與「關閉程式」。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const iconStyle = ButtonStyle(visualDensity: VisualDensity.compact);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => startWindowDrag(),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.outline)),
            ),
            IconButton(
              style: iconStyle,
              iconSize: 18,
              tooltip: '離開迷你模式',
              icon: const Icon(Icons.open_in_full),
              onPressed: () => Navigator.of(context).pop(),
            ),
            IconButton(
              style: iconStyle,
              iconSize: 18,
              tooltip: '關閉程式',
              icon: const Icon(Icons.close),
              onPressed: closeWindow,
            ),
          ],
        ),
      ),
    );
  }
}
