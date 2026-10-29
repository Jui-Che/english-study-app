import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models.dart';
import '../pages/word_detail_page.dart';
import 'copy.dart';

/// 單字清單的一列：英文、詞性＋中文，右側收藏星號，點一下看詳細，長按複製。
class WordTile extends StatelessWidget {
  const WordTile({super.key, required this.word});

  final Word word;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(word.word, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${word.pos} ${word.meaning}'),
      trailing: FavoriteButton(word: word.word),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WordDetailPage(word: word)),
      ),
      onLongPress: () => copyToClipboard(context, word.word),
    );
  }
}

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final fav = store.isFavorite(word);
        return IconButton(
          tooltip: fav ? '取消收藏' : '加入收藏',
          icon: Icon(fav ? Icons.star : Icons.star_outline,
              color: fav ? Colors.amber.shade700 : null),
          onPressed: () => store.toggleFavorite(word),
        );
      },
    );
  }
}
