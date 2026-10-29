#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Size of the compact window and its gap from the screen corner, in logical
// pixels.
constexpr int kCompactWidth = 320;
constexpr int kCompactHeight = 420;
constexpr int kCompactMargin = 16;

// DWMWA_WINDOW_CORNER_PREFERENCE and its values, spelled out so the runner
// also builds with Windows SDKs older than Windows 11. Ignored on Windows 10.
constexpr DWORD kDwmWindowCornerPreference = 33;
constexpr DWORD kCornerDefault = 0;
constexpr DWORD kCornerRound = 2;

void SetCornerPreference(HWND hwnd, DWORD preference) {
  DwmSetWindowAttribute(hwnd, kDwmWindowCornerPreference, &preference,
                        sizeof(preference));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "vocab_app/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setCompact") {
          const auto* compact = std::get_if<bool>(call.arguments());
          if (!compact) {
            result->Error("bad_args", "Expected a bool.");
            return;
          }
          SetCompact(*compact);
          result->Success();
        } else if (call.method_name() == "startDrag") {
          // The compact window has no title bar, so let Dart start a native
          // window move from its own top bar.
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else if (call.method_name() == "close") {
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetCompact(bool compact) {
  HWND hwnd = GetHandle();
  if (!hwnd || compact == compact_) {
    return;
  }
  compact_ = compact;
  if (!compact) {
    SetWindowLongPtr(hwnd, GWL_STYLE, saved_style_);
    SetCornerPreference(hwnd, kCornerDefault);
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED);
    SetWindowPlacement(hwnd, &saved_placement_);
    return;
  }

  saved_placement_.length = sizeof(WINDOWPLACEMENT);
  GetWindowPlacement(hwnd, &saved_placement_);
  if (IsZoomed(hwnd) || IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }

  // No title bar or borders: the Dart side draws its own small top bar with
  // only "leave compact mode" and "close" buttons.
  saved_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
  SetWindowLongPtr(hwnd, GWL_STYLE,
                   (saved_style_ & ~WS_OVERLAPPEDWINDOW) | WS_POPUP);
  SetCornerPreference(hwnd, kCornerRound);

  // Bottom-right corner of the monitor the window is on, like the Clock app's
  // compact overlay.
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  MONITORINFO info{sizeof(MONITORINFO)};
  GetMonitorInfo(monitor, &info);
  const int width = static_cast<int>(kCompactWidth * scale);
  const int height = static_cast<int>(kCompactHeight * scale);
  const int margin = static_cast<int>(kCompactMargin * scale);
  SetWindowPos(hwnd, HWND_TOPMOST, info.rcWork.right - width - margin,
               info.rcWork.bottom - height - margin, width, height,
               SWP_SHOWWINDOW | SWP_FRAMECHANGED);
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
