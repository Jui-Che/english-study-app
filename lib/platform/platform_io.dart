import 'dart:io';
import 'dart:typed_data';

/// 使用者資料（一段 JSON 文字）的存放位置。
/// Windows 上是 %APPDATA%\vocab_app\user_data.json。
class UserDataStorage {
  final _file = File('${_dataDir()}${Platform.pathSeparator}user_data.json');

  static String _dataDir() {
    final env = Platform.environment;
    final base = Platform.isWindows
        ? env['APPDATA']
        : Platform.isMacOS
            ? '${env['HOME']}/Library/Application Support'
            : null;
    return '${base ?? Directory.systemTemp.path}${Platform.pathSeparator}vocab_app';
  }

  Future<String?> read() async => await _file.exists() ? _file.readAsString() : null;

  Future<void> write(String data) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(data);
  }
}

Future<Uint8List> gunzip(Uint8List bytes) async => Uint8List.fromList(gzip.decode(bytes));
