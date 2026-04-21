#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

namespace flutter_cache_video_player {
	namespace test {

		// Basic sanity test. The full plugin requires TextureRegistrar and
		// BinaryMessenger which are unavailable in a unit-test context.
		// Integration tests live in example/integration_test/.
		TEST(FlutterCacheVideoPlayerPlugin, Placeholder) { EXPECT_TRUE(true); }

	}  // namespace test
}  // namespace flutter_cache_video_player
