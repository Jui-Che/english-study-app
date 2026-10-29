import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'data/user_store.dart';
import 'data/word_repository.dart';
import 'pages/home_shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先顯示載入畫面，等它畫出來再開始載入字庫（網頁版載入時畫面無法更新）
  runApp(const _LoadingApp());
  await WidgetsBinding.instance.endOfFrame;
  final repo = await WordRepository.load();
  final store = await UserStore.open();
  runApp(VocabApp(repo: repo, store: store, startInMiniMode: args.contains('--mini')));
}

ThemeData _theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: b),
      fontFamilyFallback: const ['Microsoft JhengHei', 'PingFang TC', 'Noto Sans TC'],
    );

class VocabApp extends StatelessWidget {
  const VocabApp({
    super.key,
    required this.repo,
    required this.store,
    this.startInMiniMode = false,
  });

  final WordRepository repo;
  final UserStore store;
  final bool startInMiniMode;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repo: repo,
      store: store,
      child: MaterialApp(
        title: '單字學習',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: HomeShell(startInMiniMode: startInMiniMode),
      ),
    );
  }
}

class _LoadingApp extends StatelessWidget {
  const _LoadingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('載入字庫中…'),
            ],
          ),
        ),
      ),
    );
  }
}
