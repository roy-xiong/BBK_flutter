#include "include/gamepads_windows/gamepads_windows_plugin_c_api.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <Xinput.h>
#include <array>
#include <cmath>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

/// 主线程轮询系统XInput，平台消息只从窗口线程发送；没有后台读线程或退出等待。
/// 系统DLL动态加载，缺少接口时返回空手柄列表，不要求额外GameInput运行库。
class BbkGamepads final : public flutter::Plugin {
 public:
  explicit BbkGamepads(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar), channel_(std::make_unique<flutter::MethodChannel<Value>>(
          registrar->messenger(), "xyz.luan/gamepads", &flutter::StandardMethodCodec::GetInstance())) {
    module_ = LoadLibraryExW(L"xinput1_4.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module_) module_ = LoadLibraryExW(L"xinput9_1_0.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (module_) get_state_ = reinterpret_cast<GetState>(GetProcAddress(module_, "XInputGetState"));
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "listGamepads") {
        Poll();
        flutter::EncodableList list;
        for (DWORD i = 0; i < XUSER_MAX_COUNT; ++i) {
          if (connected_[i]) list.emplace_back(Map{{Value("id"), Value(Id(i))}, {Value("name"), Value(Name(i))}});
        }
        result->Success(Value(list));
      } else if (call.method_name() == "hasRumble" || call.method_name() == "rumble" || call.method_name() == "stopRumble") {
        result->Success(Value(false));
      } else { result->NotImplemented(); }
    });
    if (registrar_->GetView()) window_ = registrar_->GetView()->GetNativeWindow();
    if (window_ && get_state_) {
      delegate_ = registrar_->RegisterTopLevelWindowProcDelegate(
          [this](HWND, UINT message, WPARAM wparam, LPARAM) -> std::optional<LRESULT> {
            if (message == WM_TIMER && wparam == timer_) { Poll(); return 0; }
            return std::nullopt;
          });
      timer_ = SetTimer(window_, reinterpret_cast<UINT_PTR>(this), 16, nullptr);
    }
  }
  ~BbkGamepads() override {
    if (window_ && timer_) KillTimer(window_, timer_);
    if (delegate_ >= 0) registrar_->UnregisterTopLevelWindowProcDelegate(delegate_);
    channel_->SetMethodCallHandler(nullptr);
    if (module_) FreeLibrary(module_);
  }

 private:
  using GetState = DWORD(WINAPI*)(DWORD, XINPUT_STATE*);
  static std::string Id(DWORD i) { return "xinput:" + std::to_string(i); }
  static std::string Name(DWORD i) { return "XInput Gamepad " + std::to_string(i + 1); }
  static double Axis(SHORT value) { return value < 0 ? value / 32768.0 : value / 32767.0; }

  void Emit(DWORD i, const char* key, double value, bool analog) {
    channel_->InvokeMethod("onGamepadEvent", std::make_unique<Value>(Map{
      {Value("gamepadId"), Value(Id(i))}, {Value("time"), Value(static_cast<int64_t>(GetTickCount64()))},
      {Value("type"), Value(analog ? "analog" : "button")}, {Value("key"), Value(key)}, {Value("value"), Value(value)}}));
  }
  void Connection(DWORD i, bool connected) {
    channel_->InvokeMethod("onGamepadConnectionEvent", std::make_unique<Value>(Map{
      {Value("gamepadId"), Value(Id(i))}, {Value("name"), Value(Name(i))},
      {Value("type"), Value(connected ? "connected" : "disconnected")}}));
  }
  void Analog(DWORD i, const char* key, double before, double after) {
    if (std::abs(before - after) > .002 || (before != 0 && after == 0)) Emit(i, key, after, true);
  }

  /// 四个槽位固定上限；读取失败只清除该槽，所有输出结构在调用前初始化为零。
  void Poll() {
    if (!get_state_) return;
    struct Button { WORD flag; const char* key; };
    static constexpr Button buttons[] = {
      {XINPUT_GAMEPAD_A, "a"}, {XINPUT_GAMEPAD_B, "b"}, {XINPUT_GAMEPAD_X, "x"}, {XINPUT_GAMEPAD_Y, "y"},
      {XINPUT_GAMEPAD_DPAD_UP, "dpadUp"}, {XINPUT_GAMEPAD_DPAD_DOWN, "dpadDown"},
      {XINPUT_GAMEPAD_DPAD_LEFT, "dpadLeft"}, {XINPUT_GAMEPAD_DPAD_RIGHT, "dpadRight"},
      {XINPUT_GAMEPAD_LEFT_SHOULDER, "leftShoulder"}, {XINPUT_GAMEPAD_RIGHT_SHOULDER, "rightShoulder"},
      {XINPUT_GAMEPAD_BACK, "view"}, {XINPUT_GAMEPAD_START, "menu"}};
    for (DWORD i = 0; i < XUSER_MAX_COUNT; ++i) {
      XINPUT_STATE current{};
      const bool available = get_state_(i, &current) == ERROR_SUCCESS;
      if (available != connected_[i]) { connected_[i] = available; previous_[i] = {}; Connection(i, available); }
      if (!available) continue;
      const auto& old = previous_[i].Gamepad;
      const auto& now = current.Gamepad;
      for (const auto& button : buttons) {
        if ((old.wButtons & button.flag) != (now.wButtons & button.flag)) Emit(i, button.key, (now.wButtons & button.flag) ? 1.0 : 0.0, false);
      }
      Analog(i, "leftThumbstickX", Axis(old.sThumbLX), Axis(now.sThumbLX));
      Analog(i, "leftThumbstickY", Axis(old.sThumbLY), Axis(now.sThumbLY));
      Analog(i, "leftTrigger", old.bLeftTrigger / 255.0, now.bLeftTrigger / 255.0);
      Analog(i, "rightTrigger", old.bRightTrigger / 255.0, now.bRightTrigger / 255.0);
      previous_[i] = current;
    }
  }
  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  HMODULE module_ = nullptr;
  GetState get_state_ = nullptr;
  HWND window_ = nullptr;
  UINT_PTR timer_ = 0;
  int delegate_ = -1;
  std::array<bool, XUSER_MAX_COUNT> connected_{};
  std::array<XINPUT_STATE, XUSER_MAX_COUNT> previous_{};
};
}

void GamepadsWindowsPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows = flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows->AddPlugin(std::make_unique<BbkGamepads>(windows));
}
