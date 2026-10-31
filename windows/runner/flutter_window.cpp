#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <algorithm>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Default and minimum size of the compact window and its gap from the screen
// corner, in logical pixels.
constexpr double kCompactWidth = 320;
constexpr double kCompactHeight = 420;
constexpr double kCompactMinWidth = 240;
constexpr double kCompactMinHeight = 260;
constexpr double kCompactMargin = 16;

// DWMWA_WINDOW_CORNER_PREFERENCE and its values, spelled out so the runner
// also builds with Windows SDKs older than Windows 11. Ignored on Windows 10.
constexpr DWORD kDwmWindowCornerPreference = 33;
constexpr DWORD kCornerDefault = 0;
constexpr DWORD kCornerRound = 2;

void SetCornerPreference(HWND hwnd, DWORD preference) {
  DwmSetWindowAttribute(hwnd, kDwmWindowCornerPreference, &preference,
                        sizeof(preference));
}

// Physical pixels per logical pixel on the monitor showing |hwnd|.
double ScaleFor(HWND hwnd) {
  return FlutterDesktopGetDpiForMonitor(
             MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)) /
         96.0;
}

// Reads a double from a method call's map arguments, or |fallback|.
double GetDouble(const flutter::EncodableMap& args, const char* key,
                 double fallback) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  const auto* value = std::get_if<double>(&it->second);
  return value ? *value : fallback;
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
        const std::string& method = call.method_name();
        if (method == "setCompact") {
          // Arguments: {compact: bool, width?: double, height?: double}.
          // Leaving compact mode returns the compact window's last logical
          // size so Dart can remember it.
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          const bool* compact = nullptr;
          if (args) {
            auto it = args->find(flutter::EncodableValue("compact"));
            if (it != args->end()) {
              compact = std::get_if<bool>(&it->second);
            }
          }
          if (!compact) {
            result->Error("bad_args", "Expected {compact: bool}.");
            return;
          }
          if (*compact) {
            EnterCompact(GetDouble(*args, "width", kCompactWidth),
                         GetDouble(*args, "height", kCompactHeight));
            result->Success();
          } else {
            const auto size = LeaveCompact();
            if (!size) {
              result->Success();
              return;
            }
            result->Success(flutter::EncodableValue(flutter::EncodableMap{
                {flutter::EncodableValue("width"),
                 flutter::EncodableValue(size->first)},
                {flutter::EncodableValue("height"),
                 flutter::EncodableValue(size->second)},
            }));
          }
        } else if (method == "startDrag" || method == "startResize") {
          // The compact window has no title bar or visible border, so Dart
          // starts native moves and resizes from its own widgets. startResize
          // takes the HT* hit-test code of the edge being dragged.
          WPARAM hit = HTCAPTION;
          if (method == "startResize") {
            const auto* edge = std::get_if<int32_t>(call.arguments());
            if (!edge || *edge < HTLEFT || *edge > HTBOTTOMRIGHT) {
              result->Error("bad_args", "Expected an HT* edge code.");
              return;
            }
            hit = static_cast<WPARAM>(*edge);
          }
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, hit, 0);
          result->Success();
        } else if (method == "close") {
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

void FlutterWindow::EnterCompact(double width, double height) {
  HWND hwnd = GetHandle();
  if (!hwnd || compact_) {
    return;
  }
  saved_placement_.length = sizeof(WINDOWPLACEMENT);
  GetWindowPlacement(hwnd, &saved_placement_);
  if (IsZoomed(hwnd) || IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }

  // No title bar: the Dart side draws its own small top bar with only "leave
  // compact mode" and "close" buttons. WS_THICKFRAME keeps the window
  // resizable; WM_NCCALCSIZE below hides the frame it would draw.
  compact_ = true;
  saved_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
  SetWindowLongPtr(hwnd, GWL_STYLE,
                   (saved_style_ & ~WS_OVERLAPPEDWINDOW) | WS_POPUP |
                       WS_THICKFRAME);
  SetCornerPreference(hwnd, kCornerRound);

  // Bottom-right corner of the monitor the window is on, like the Clock app's
  // compact overlay.
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  MONITORINFO info{sizeof(MONITORINFO)};
  GetMonitorInfo(monitor, &info);
  const int margin = static_cast<int>(kCompactMargin * scale);
  const int min_width = static_cast<int>(kCompactMinWidth * scale);
  const int min_height = static_cast<int>(kCompactMinHeight * scale);
  const int max_width = std::max(
      min_width, static_cast<int>(info.rcWork.right - info.rcWork.left - 2 * margin));
  const int max_height = std::max(
      min_height, static_cast<int>(info.rcWork.bottom - info.rcWork.top - 2 * margin));
  const int w = std::clamp(static_cast<int>(width * scale), min_width, max_width);
  const int h = std::clamp(static_cast<int>(height * scale), min_height, max_height);
  SetWindowPos(hwnd, HWND_TOPMOST, info.rcWork.right - w - margin,
               info.rcWork.bottom - h - margin, w, h,
               SWP_SHOWWINDOW | SWP_FRAMECHANGED);
}

std::optional<std::pair<double, double>> FlutterWindow::LeaveCompact() {
  HWND hwnd = GetHandle();
  if (!hwnd || !compact_) {
    return std::nullopt;
  }
  RECT rect;
  GetWindowRect(hwnd, &rect);
  const double scale = ScaleFor(hwnd);
  const std::pair<double, double> size{(rect.right - rect.left) / scale,
                                       (rect.bottom - rect.top) / scale};

  compact_ = false;
  SetWindowLongPtr(hwnd, GWL_STYLE, saved_style_);
  SetCornerPreference(hwnd, kCornerDefault);
  SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED);
  SetWindowPlacement(hwnd, &saved_placement_);
  return size;
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
  if (compact_) {
    switch (message) {
      case WM_NCCALCSIZE:
        // Use the whole window as client area, hiding the resize frame.
        if (wparam) {
          return 0;
        }
        break;
      case WM_GETMINMAXINFO: {
        const double scale = ScaleFor(hwnd);
        auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
        info->ptMinTrackSize.x = static_cast<LONG>(kCompactMinWidth * scale);
        info->ptMinTrackSize.y = static_cast<LONG>(kCompactMinHeight * scale);
        return 0;
      }
    }
  }

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
