#ifndef BBK_GAMEPADS_WINDOWS_PLUGIN_C_API_H_
#define BBK_GAMEPADS_WINDOWS_PLUGIN_C_API_H_
#include <flutter_plugin_registrar.h>
#ifdef FLUTTER_PLUGIN_IMPL
#define BBK_GAMEPAD_EXPORT __declspec(dllexport)
#else
#define BBK_GAMEPAD_EXPORT __declspec(dllimport)
#endif
#ifdef __cplusplus
extern "C" {
#endif
BBK_GAMEPAD_EXPORT void GamepadsWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
#ifdef __cplusplus
}
#endif
#endif
