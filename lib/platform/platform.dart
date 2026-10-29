// 桌面版與網頁版不同的地方集中在這裡，編譯時自動選對的實作：
// - platform_io.dart：Windows / macOS（存成檔案、用 dart:io 解壓縮）
// - platform_web.dart：瀏覽器（存在 localStorage、用瀏覽器內建解壓縮）
export 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart';
