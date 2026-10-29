import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 複製到剪貼簿，並在畫面下方提示。
Future<void> copyToClipboard(BuildContext context, String text, {String? message}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message ?? '已複製：$text'),
      duration: const Duration(seconds: 2),
    ));
}
