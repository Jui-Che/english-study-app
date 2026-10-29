import 'package:flutter/material.dart';

import '../logic/grouping.dart';
import '../models.dart';
import '../widgets/word_tile.dart';
import 'matching_game_page.dart';

/// 一組單字：先瀏覽，再開始配對。
class GroupPage extends StatelessWidget {
  const GroupPage({super.key, required this.group});

  final WordGroup group;

  @override
  Widget build(BuildContext context) {
    final rounds = splitRounds(group.words).length;
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
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
