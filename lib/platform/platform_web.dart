import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 使用者資料（一段 JSON 文字）存在瀏覽器的 localStorage，只存在這台裝置的這個瀏覽器。
class UserDataStorage {
  static const _key = 'vocab_app.user_data';

  Future<String?> read() async => web.window.localStorage.getItem(_key);

  Future<void> write(String data) async => web.window.localStorage.setItem(_key, data);
}

/// 用瀏覽器內建的 DecompressionStream 解壓縮，比在 Dart 裡解快很多。
Future<Uint8List> gunzip(Uint8List bytes) async {
  final ds = web.DecompressionStream('gzip');
  final stream = web.Blob([bytes.toJS].toJS)
      .stream()
      .pipeThrough(web.ReadableWritablePair(readable: ds.readable, writable: ds.writable));
  final buffer = await web.Response(stream).arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
