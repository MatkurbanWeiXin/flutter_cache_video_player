// Shared libmpv-backed player used by both Linux and Windows plugins.
//
// Design:
// * No internal threads. The platform plugin owns the event loop integration
//   and is expected to call `DrainEvents()` / `Render()` when mpv signals via
//   the user-supplied wakeup / update callbacks.
// * Rendering uses MPV_RENDER_API_TYPE_SW so that decoded frames end up as
//   RGBA byte buffers that Flutter's PixelBufferTexture / FlPixelBufferTexture
//   can consume directly, without any GL/D3D context sharing.
// * Snapshots and covers are produced by invoking mpv's built-in
//   `screenshot-to-file` command (PNG via libpng bundled in libmpv), so no
//   extra image-encoding dependency is needed.
//
// Nothing in this file depends on Flutter — only libmpv and the C++ standard
// library.

#ifndef FLUTTER_CACHE_VIDEO_PLAYER_NATIVE_MPV_PLAYER_H_
#define FLUTTER_CACHE_VIDEO_PLAYER_NATIVE_MPV_PLAYER_H_

#include <mpv/client.h>
#include <mpv/render.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace flutter_cache_video_player {

struct CoverFrame {
  std::string path;     // absolute path of a PNG written to disk
  int64_t position_ms;  // requested sample position in milliseconds
  double brightness;    // average luma 0..1 (Rec.601)
};

class MpvPlayer {
 public:
  using PositionCb = std::function<void(int64_t ms)>;
  using DurationCb = std::function<void(int64_t ms)>;
  using PlayingCb = std::function<void(bool playing)>;
  using BufferingCb = std::function<void(bool buffering)>;
  using CompletedCb = std::function<void()>;
  using ErrorCb = std::function<void(const std::string& msg)>;
  using FrameCb =
      std::function<void(const uint8_t* rgba, uint32_t width, uint32_t height)>;
  using VideoSizeCb = std::function<void(int64_t width, int64_t height)>;

  // Trampolines — invoked on an arbitrary libmpv thread. Consumers typically
  // use these to post a task onto the platform main loop that will end up
  // calling DrainEvents() / Render().
  using WakeupHandler = std::function<void()>;
  using UpdateHandler = std::function<void()>;

  MpvPlayer();
  ~MpvPlayer();

  MpvPlayer(const MpvPlayer&) = delete;
  MpvPlayer& operator=(const MpvPlayer&) = delete;

  bool Initialize(std::string* error = nullptr);

  // Playback controls.
  void Open(const std::string& url);
  void Play();
  void Pause();
  void Seek(int64_t ms);
  void SetVolume(double volume);
  void SetSpeed(double speed);
  void Dispose();

  // Platform-thread driven integration points.
  void DrainEvents();
  bool Render();

  bool TakeSnapshot(std::vector<uint8_t>* out, std::string* error = nullptr);

  static std::vector<CoverFrame> ExtractCovers(const std::string& url,
                                               int count,
                                               int candidates,
                                               double min_brightness,
                                               const std::string& output_dir,
                                               std::string* error = nullptr);

  void SetOnPosition(PositionCb cb) { on_position_ = std::move(cb); }
  void SetOnDuration(DurationCb cb) { on_duration_ = std::move(cb); }
  void SetOnPlaying(PlayingCb cb) { on_playing_ = std::move(cb); }
  void SetOnBuffering(BufferingCb cb) { on_buffering_ = std::move(cb); }
  void SetOnCompleted(CompletedCb cb) { on_completed_ = std::move(cb); }
  void SetOnError(ErrorCb cb) { on_error_ = std::move(cb); }
  void SetOnFrame(FrameCb cb) { on_frame_ = std::move(cb); }
  void SetOnVideoSize(VideoSizeCb cb) { on_video_size_ = std::move(cb); }
  void SetWakeupHandler(WakeupHandler cb) { wakeup_handler_ = std::move(cb); }
  void SetUpdateHandler(UpdateHandler cb) { update_handler_ = std::move(cb); }

  const uint8_t* sw_buffer();
  uint32_t sw_width() const { return sw_w_.load(); }
  uint32_t sw_height() const { return sw_h_.load(); }
  std::mutex& sw_mutex() { return sw_mutex_; }

 private:
  static void OnMpvWakeup(void* ctx);
  static void OnMpvRenderUpdate(void* ctx);
  void HandleMpvEvent(mpv_event* ev);
  bool PerformRender(uint32_t w, uint32_t h);

  mpv_handle* mpv_ = nullptr;
  mpv_render_context* render_ctx_ = nullptr;

  std::vector<uint8_t> sw_buffer_;
  std::atomic<uint32_t> sw_w_{0};
  std::atomic<uint32_t> sw_h_{0};
  std::mutex sw_mutex_;

  std::atomic<int64_t> video_w_{0};
  std::atomic<int64_t> video_h_{0};
  // Raw source dimensions (`width`/`height`). These populate from the
  // demuxer as soon as the stream header is read — much earlier than
  // `dwidth`/`dheight` (which on Windows libmpv SW rendering only fill in
  // *after* the first mpv_render_context_render call). Used as a fallback so
  // that we can kick off rendering and break the chicken-and-egg deadlock.
  std::atomic<int64_t> src_w_{0};
  std::atomic<int64_t> src_h_{0};

  std::atomic<bool> render_pending_{false};

  PositionCb on_position_;
  DurationCb on_duration_;
  PlayingCb on_playing_;
  BufferingCb on_buffering_;
  CompletedCb on_completed_;
  ErrorCb on_error_;
  FrameCb on_frame_;
  VideoSizeCb on_video_size_;
  WakeupHandler wakeup_handler_;
  UpdateHandler update_handler_;
};

}  // namespace flutter_cache_video_player

#endif  // FLUTTER_CACHE_VIDEO_PLAYER_NATIVE_MPV_PLAYER_H_
