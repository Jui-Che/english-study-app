import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../widgets/word_tile.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    final results = repo.search(_query);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: SearchBar(
                    hintText: '輸入英文或中文，例如 travel、went、早餐',
                    leading: const Icon(Icons.search),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                IconButton(
                  tooltip: '關於與資料來源',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => _showAbout(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty
                ? Center(
                    child: Text(
                      '輸入英文或中文開始查詢\n字庫共 ${_formatCount(repo.size)} 個字',
                      textAlign: TextAlign.center,
                    ),
                  )
                : results.isEmpty
                    ? const Center(child: Text('找不到這個字'))
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (_, i) => WordTile(word: results[i]),
                      ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) => showAboutDialog(
        context: context,
        applicationName: '單字學習',
        applicationVersion: '0.2',
        children: const [
          Text(
            '字典資料：ECDICT（MIT 授權）\n'
            '繁體轉換：OpenCC（Apache 2.0）\n'
            '例句：Tatoeba（CC-BY 2.0 FR），經由 manythings.org 整理',
          ),
        ],
      );
}

String _formatCount(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+$)'),
      (_) => ',',
    );
