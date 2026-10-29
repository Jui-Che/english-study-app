import 'package:flutter/widgets.dart';

import 'data/user_store.dart';
import 'data/word_repository.dart';

/// 讓所有頁面都能取得單字資料與使用者資料：`AppScope.of(context).store`。
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.repo,
    required this.store,
    required super.child,
  });

  final WordRepository repo;
  final UserStore store;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      repo != oldWidget.repo || store != oldWidget.store;
}
