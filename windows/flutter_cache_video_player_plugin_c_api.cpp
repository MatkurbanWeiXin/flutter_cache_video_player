#include "include/flutter_cache_video_player/flutter_cache_video_player_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_cache_video_player_plugin.h"

void FlutterCacheVideoPlayerPluginCApiRegisterWithRegistrar(
	FlutterDesktopPluginRegistrarRef registrar) {
	flutter_cache_video_player::FlutterCacheVideoPlayerPlugin::RegisterWithRegistrar(
		flutter::PluginRegistrarManager::GetInstance()
		->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
