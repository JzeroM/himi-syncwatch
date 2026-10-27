#include "include/himi_mpv_windows/himi_mpv_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "himi_mpv_windows_plugin.h"

void HimiMpvWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  himi_mpv_windows::HimiMpvWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
