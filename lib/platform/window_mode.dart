import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 迷你模式（縮小並固定在所有視窗最上層）只有 Windows 桌面版支援，
/// 實作在 windows/runner/flutter_window.cpp。
bool get supportsMiniMode => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

const _channel = MethodChannel('vocab_app/window');

Future<void> setCompactWindow(bool compact) async {
  if (supportsMiniMode) await _channel.invokeMethod<void>('setCompact', compact);
}
