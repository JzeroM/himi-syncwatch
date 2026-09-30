#include "include/himi_windows_rtm/himi_windows_rtm_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "himi_windows_rtm_plugin.h"

void HimiWindowsRtmPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  himi_windows_rtm::HimiWindowsRtmPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
