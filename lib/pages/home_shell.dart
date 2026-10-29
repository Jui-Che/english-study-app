import 'package:flutter/material.dart';

import '../platform/window_mode.dart';
import 'favorites_page.dart';
import 'mini_mode_page.dart';
import 'search_page.dart';
import 'study_page.dart';

/// 主畫面：查詢 / 收藏 / 學習 三個分頁。
/// 寬螢幕（桌面）用左側導覽列，窄螢幕（手機）用底部導覽列。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.startInMiniMode = false});

  /// 用 `vocab_app.exe --mini` 啟動時，直接進入迷你模式。
  final bool startInMiniMode;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.search, label: '查詢'),
    (icon: Icons.star_outline, label: '收藏'),
    (icon: Icons.school_outlined, label: '學習'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.startInMiniMode && supportsMiniMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openMiniMode());
    }
  }

  void _openMiniMode() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MiniModePage()),
      );

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _index,
      children: const [SearchPage(), FavoritesPage(), StudyPage()],
    );
    final wide = MediaQuery.sizeOf(context).width >= 700;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
              ],
              trailing: supportsMiniMode
                  ? Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: IconButton(
                            tooltip: '迷你模式（縮小並固定在最上層）',
                            icon: const Icon(Icons.picture_in_picture_alt),
                            onPressed: _openMiniMode,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}
