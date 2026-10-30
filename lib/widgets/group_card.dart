import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models.dart';
import '../pages/group_page.dart';

/// 一組單字的卡片：名稱、前幾個字、最佳成績；玩過的會打勾。
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group, this.allowMiniMode = false});

  final WordGroup group;

  /// 傳給 [GroupPage.allowMiniMode]。
  final bool allowMiniMode;

  @override
  Widget build(BuildContext context) {
    final best = AppScope.of(context).store.bestScore(group.id);
    final preview = group.words.take(4).map((w) => w.word).join('、');
    return Card(
      child: ListTile(
        title: Text(group.name),
        subtitle: Text(
          '$preview${group.words.length > 4 ? '…' : ''}\n'
          '${group.words.length} 個'
          '${best == null ? '' : '　·　最佳 ${(best.accuracy * 100).round()}%，${formatSeconds(best.seconds)}'}',
        ),
        isThreeLine: true,
        trailing: best == null
            ? const Icon(Icons.chevron_right)
            : const Icon(Icons.check_circle, color: Colors.green),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GroupPage(group: group, allowMiniMode: allowMiniMode)),
        ),
      ),
    );
  }
}

String formatSeconds(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
