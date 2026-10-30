import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models.dart';
import '../widgets/group_card.dart';
import 'group_page.dart';

/// 一種考試的所有單字組，常用字在前；右下角可直接接著練下一組沒玩過的。
class ExamPage extends StatelessWidget {
  const ExamPage({super.key, required this.track});

  final ExamTrack track;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final groups = track.groups;
        final done = groups.where((g) => store.bestScore(g.id) != null).length;
        final next = groups.where((g) => store.bestScore(g.id) == null).firstOrNull;
        final t = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: Text(track.name)),
          body: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: groups.length + 1,
            itemBuilder: (context, i) {
              if (i > 0) return GroupCard(group: groups[i - 1], allowMiniMode: true);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.description, style: t.bodyLarge),
                    const SizedBox(height: 4),
                    Text('共 ${track.wordCount} 字，依常用程度排序，越前面越常用', style: t.bodyMedium),
                    const SizedBox(height: 12),
                    Text('已完成 $done / ${groups.length} 組', style: t.titleMedium),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: groups.isEmpty ? 0 : done / groups.length,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              );
            },
          ),
          floatingActionButton: next == null
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.play_arrow),
                  label: Text('繼續：${next.name}'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => GroupPage(group: next, allowMiniMode: true)),
                  ),
                ),
        );
      },
    );
  }
}
