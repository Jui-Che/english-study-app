import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/user_store.dart';
import '../models.dart';
import '../platform/window_mode.dart';
import '../widgets/copy.dart';
import 'word_detail_page.dart' show highlight;

/// 迷你模式：視窗縮小、沒有標題列並固定在最上層（Windows），用字卡複習「我的收藏」或一組考試單字。
/// 上方列可以按住拖曳視窗。鍵盤：← → 換字、空白鍵顯示解釋。
class MiniModePage extends StatefulWidget {
  const MiniModePage({super.key, this.group});

  /// 要複習的單字組；沒給就是「我的收藏」。
  final WordGroup? group;

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

  late UserStore _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = AppScope.of(context).store;
    if (_words == null) {
      _words = _loadWords();
      enterCompactWindow(size: _store.miniWindowSize);
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    // 記住使用者調整過的大小，下次進迷你模式沿用
    final store = _store;
    leaveCompactWindow().then((size) {
      if (size != null) store.setMiniWindowSize(size);
    });
    super.dispose();
  }

  String get _title => widget.group?.name ?? '我的收藏';

  /// 單字組照原本順序；收藏則是新收藏的在前面。
  List<Word> _loadWords() {
    final scope = AppScope.of(context);
    final words = widget.group != null
        ? [...widget.group!.words]
        : scope.store.favorites.reversed
              .map(scope.repo.find)
              .whereType<Word>()
              .toList();
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
        _auto = Timer.periodic(
          _autoInterval,
          (_) => _revealed ? _move(1) : _toggleReveal(),
        );
      }
    });
  }

  void _toggleShuffle() {
    setState(() {
      _shuffled = !_shuffled;
      _words = _loadWords();
      _index = 0;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final words = _words!;
    return Scaffold(
      body: _ResizeFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(
              label: words.isEmpty
                  ? _title
                  : '$_title  ${_index + 1} / ${words.length}',
            ),
            Expanded(
              child: words.isEmpty
                  ? const Center(
                      child: Text(
                        '還沒有收藏的單字\n先在一般視窗點 ☆ 收藏',
                        textAlign: TextAlign.center,
                      ),
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
                          Text(
                            word.word,
                            style: t.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (word.phonetic.isNotEmpty)
                            Text(
                              word.phonetic,
                              style: TextStyle(color: t.colorScheme.outline),
                            ),
                          const SizedBox(height: 12),
                          if (_revealed)
                            Text(
                              word.posAndMeaning,
                              style: t.textTheme.titleLarge,
                            )
                          else
                            Text(
                              '點一下或按空白鍵看解釋',
                              style: TextStyle(color: t.colorScheme.outline),
                            ),
                          if (word.example.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text.rich(
                              highlight(word.example, [
                                word.word,
                                ...word.forms.values,
                              ], t.colorScheme.primary),
                              style: t.textTheme.bodyLarge,
                            ),
                            if (_revealed)
                              Text(
                                word.exampleZh,
                                style: TextStyle(color: t.colorScheme.outline),
                              ),
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
                  IconButton(
                    tooltip: '上一個（←）',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _move(-1),
                  ),
                  IconButton(
                    tooltip: _auto == null ? '自動播放' : '停止自動播放',
                    icon: Icon(_auto == null ? Icons.play_arrow : Icons.pause),
                    onPressed: _toggleAuto,
                  ),
                  IconButton(
                    tooltip: _shuffled ? '依收藏順序' : '隨機順序',
                    icon: Icon(
                      Icons.shuffle,
                      color: _shuffled ? t.colorScheme.primary : null,
                    ),
                    onPressed: _toggleShuffle,
                  ),
                  IconButton(
                    tooltip: '下一個（→）',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _move(1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 迷你視窗沒有可見的邊框：在四邊與四角放看不見的細條，滑鼠移過去顯示調整大小的游標，
/// 按住拖曳就交給 Windows 調整視窗大小。
class _ResizeFrame extends StatelessWidget {
  const _ResizeFrame({required this.child});

  final Widget child;

  static const _edge = 6.0, _corner = 12.0;

  @override
  Widget build(BuildContext context) {
    Widget handle(ResizeEdge edge, MouseCursor cursor) => MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => startWindowResize(edge),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: child),
        // 四邊
        Positioned(
          left: _corner,
          right: _corner,
          top: 0,
          height: _edge,
          child: handle(ResizeEdge.top, SystemMouseCursors.resizeUpDown),
        ),
        Positioned(
          left: _corner,
          right: _corner,
          bottom: 0,
          height: _edge,
          child: handle(ResizeEdge.bottom, SystemMouseCursors.resizeUpDown),
        ),
        Positioned(
          top: _corner,
          bottom: _corner,
          left: 0,
          width: _edge,
          child: handle(ResizeEdge.left, SystemMouseCursors.resizeLeftRight),
        ),
        Positioned(
          top: _corner,
          bottom: _corner,
          right: 0,
          width: _edge,
          child: handle(ResizeEdge.right, SystemMouseCursors.resizeLeftRight),
        ),
        // 四角
        Positioned(
          left: 0,
          top: 0,
          width: _corner,
          height: _corner,
          child: handle(
            ResizeEdge.topLeft,
            SystemMouseCursors.resizeUpLeftDownRight,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          width: _corner,
          height: _corner,
          child: handle(
            ResizeEdge.bottomRight,
            SystemMouseCursors.resizeUpLeftDownRight,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          width: _corner,
          height: _corner,
          child: handle(
            ResizeEdge.topRight,
            SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          width: _corner,
          height: _corner,
          child: handle(
            ResizeEdge.bottomLeft,
            SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
      ],
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
              child: Text(
                label,
                style: t.textTheme.labelLarge?.copyWith(
                  color: t.colorScheme.outline,
                ),
              ),
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
