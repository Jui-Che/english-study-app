import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 迷你模式（縮小並固定在所有視窗最上層）只有 Windows 桌面版支援，
/// 實作在 windows/runner/flutter_window.cpp。
bool get supportsMiniMode => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

const _channel = MethodChannel('vocab_app/window');

/// 進入迷你模式：縮小（[size] 為邏輯像素，沒給用預設）、拿掉標題列並置頂。
Future<void> enterCompactWindow({Size? size}) async {
  if (!supportsMiniMode) return;
  await _channel.invokeMethod<void>('setCompact', {
    'compact': true,
    if (size != null) 'width': size.width,
    if (size != null) 'height': size.height,
  });
}

/// 離開迷你模式，恢復原本的視窗；回傳迷你視窗離開前的大小（使用者可能調整過）。
Future<Size?> leaveCompactWindow() async {
  if (!supportsMiniMode) return null;
  final size = await _channel.invokeMapMethod<String, double>('setCompact', {'compact': false});
  return size == null ? null : Size(size['width']!, size['height']!);
}

/// 迷你模式沒有標題列，按住自己畫的上方列時呼叫，讓 Windows 開始拖曳視窗。
Future<void> startWindowDrag() async {
  if (supportsMiniMode) await _channel.invokeMethod<void>('startDrag');
}

/// 迷你模式沒有可見的邊框，按住邊緣時呼叫，讓 Windows 開始調整大小。
Future<void> startWindowResize(ResizeEdge edge) async {
  if (supportsMiniMode) await _channel.invokeMethod<void>('startResize', edge.hitTest);
}

/// 關閉整個程式。
Future<void> closeWindow() async {
  if (supportsMiniMode) await _channel.invokeMethod<void>('close');
}

/// 視窗的邊與角，對應 Win32 的 HT* 代碼。
enum ResizeEdge {
  left(10),
  right(11),
  top(12),
  topLeft(13),
  topRight(14),
  bottom(15),
  bottomLeft(16),
  bottomRight(17);

  const ResizeEdge(this.hitTest);

  final int hitTest;
}
