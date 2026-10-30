import 'package:flutter/material.dart';

import '../logic/grouping.dart';
import '../models.dart';
import '../platform/window_mode.dart';
import '../widgets/word_tile.dart';
import 'matching_game_page.dart';
import 'mini_mode_page.dart';

/// 一組單字：先瀏覽，再開始配對。
class GroupPage extends StatelessWidget {
  const GroupPage({super.key, required this.group, this.allowMiniMode = false});

  final WordGroup group;

  /// 右上角是否顯示「用迷你模式複習這組」（目前只有考試單字組，且只有 Windows 版）。
  final bool allowMiniMode;

  @override
  Widget build(BuildContext context) {
    final rounds = splitRounds(group.words).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          if (allowMiniMode && supportsMiniMode)
            IconButton(
              tooltip: '用迷你模式複習這組',
              icon: const Icon(Icons.picture_in_picture_alt),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MiniModePage(group: group)),
              ),
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: group.words.length,
        itemBuilder: (_, i) => WordTile(word: group.words[i]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.extension),
        label: Text('開始配對（$rounds 回合）'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MatchingGamePage(group: group)),
        ),
      ),
    );
  }
}
