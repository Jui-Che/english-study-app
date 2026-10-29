import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../logic/grouping.dart';
import '../models.dart';
import '../widgets/group_card.dart';
import 'exam_page.dart';

/// 學習頁：主題單字、考試單字、常用片語，加上把收藏自動每 20 字分成的組。
class StudyPage extends StatelessWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: scope.store,
        builder: (context, _) {
          final favWords =
              scope.store.favorites.map(scope.repo.find).whereType<Word>().toList();
          final favGroups = [
            for (final (i, words) in chunk(favWords, groupSize).indexed)
              WordGroup(id: 'fav-${i + 1}', name: '我的收藏 第 ${i + 1} 組', words: words),
          ];
          final t = Theme.of(context).textTheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('主題單字', style: t.titleLarge),
              const SizedBox(height: 8),
              for (final g in scope.repo.groups) GroupCard(group: g),
              const SizedBox(height: 24),
              Text('考試單字', style: t.titleLarge),
              const SizedBox(height: 8),
              for (final track in scope.repo.examTracks) _ExamCard(track: track),
              const SizedBox(height: 24),
              Text('常用片語', style: t.titleLarge),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  title: Text('${scope.repo.phraseGroups.length} 組'),
                  subtitle: const Text('依日常使用頻率排序，越前面越常用'),
                  shape: const Border(),
                  children: [
                    for (final g in scope.repo.phraseGroups)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: GroupCard(group: g),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('我的收藏', style: t.titleLarge),
              const SizedBox(height: 8),
              if (favGroups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('收藏 2 個以上的單字，就會自動出現在這裡。'),
                )
              else
                for (final g in favGroups)
                  if (g.words.length >= 2) GroupCard(group: g),
            ],
          );
        },
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.track});

  final ExamTrack track;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final done = track.groups.where((g) => store.bestScore(g.id) != null).length;
    return Card(
      child: ListTile(
        title: Text(track.name),
        subtitle: Text(
          '${track.description}\n'
          '${track.wordCount} 字 · ${track.groups.length} 組 · 已完成 $done 組',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExamPage(track: track)),
        ),
      ),
    );
  }
}
