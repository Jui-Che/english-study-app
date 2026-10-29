import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_app/data/word_repository.dart';

/// 直接從 assets 讀檔建立字庫（測試環境不經過 rootBundle）。
WordRepository loadTestRepo() => WordRepository(
      groups: parseGroups(File('assets/words.json').readAsStringSync()),
      dictionary: parseDictionary(
        utf8.decode(gzip.decode(File('assets/dictionary.tsv.gz').readAsBytesSync())),
      ),
      corrections: jsonDecode(File('assets/corrections.json').readAsStringSync())
          as Map<String, dynamic>,
    );

/// 測試環境沒有真的剪貼簿，用這個接住 Clipboard.setData 的內容。
class FakeClipboard {
  FakeClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        text = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  }

  String? text;
}
