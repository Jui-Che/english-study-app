import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 迷你模式（縮小並固定在所有視窗最上層）只有 Windows 桌面版支援，
/// 實作在 windows/runner/flutter_window.cpp。
bool get supportsMiniMode => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

const _channel = MethodChannel('vocab_app/window');

/// 縮小並置頂（沒有標題列），或恢復原本的視窗。
Future<void> setCompactWindow(bool compact) async {
  if (supportsMiniMode) await _channel.invokeMethod<void>('setCompact', compact);
}

/// 迷你模式沒有標題列，按住自己畫的上方列時呼叫，讓 Windows 開始拖曳視窗。
Future<void> startWindowDrag() async {
  if (supportsMiniMode) await _channel.invokeMethod<void>('startDrag');
}

/// 關閉整個程式。
Future<void> closeWindow() async {
  if (supportsMiniMode) await _channel.invokeMethod<void>('close');
}
