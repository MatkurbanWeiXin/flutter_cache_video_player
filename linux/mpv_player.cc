#include "mpv_player.h"

#include <algorithm>
#include <chrono>
#include <clocale>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <thread>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX  // prevent windows.h from defining min/max macros.
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <io.h>
#include <windows.h>
#define mpv_unlink _unlink
#else
#include <unistd.h>
#define mpv_unlink unlink
#endif

namespace flutter_cache_video_player {

namespace {

// Observed property IDs used by the main player.
constexpr uint64_t kPropTimePos = 1;
constexpr uint64_t kPropDuration = 2;
constexpr uint64_t kPropPause = 3;
constexpr uint64_t kPropSeeking = 4;
constexpr uint64_t kPropCache = 5;
constexpr uint64_t kPropEof = 6;
constexpr uint64_t kPropVideoWidth = 7;
constexpr uint64_t kPropVideoHeight = 8;
// Raw source dimensions — available earlier than dwidth/dheight under SW
// rendering on some platforms (notably Windows).
constexpr uint64_t kPropSrcWidth = 9;
constexpr uint64_t kPropSrcHeight = 10;

std::string TempFilePath(const char* suffix) {
#if defined(_WIN32)
  char tmp[MAX_PATH] = {0};
  GetTempPathA(MAX_PATH, tmp);
  char name[MAX_PATH] = {0};
  GetTempFileNameA(tmp, "fcv", 0, name);
  std::string p(name);
  // GetTempFileName creates the file with a .tmp extension; replace.
  auto pos = p.find_last_of('.');
  if (pos != std::string::npos) p = p.substr(0, pos);
  p += suffix;
  return p;
#else
  char buf[] = "/tmp/fcv-XXXXXX";
  int fd = mkstemp(buf);
  if (fd >= 0) {
    close(fd);
    mpv_unlink(buf);
  }
  std::string p(buf);
  p += suffix;
  return p;
#endif
}

bool ReadAllBytes(const std::string& path, std::vector<uint8_t>* out) {
  std::ifstream in(path, std::ios::binary);
  if (!in.is_open()) return false;
  in.seekg(0, std::ios::end);
  std::streamsize n = in.tellg();
  if (n <= 0) return false;
  in.seekg(0, std::ios::beg);
  out->resize(static_cast<size_t>(n));
  in.read(reinterpret_cast<char*>(out->data()), n);
  return static_cast<std::streamsize>(in.gcount()) == n;
}

// Compute average Rec.601 luma over a RGB/BGR(A) buffer, sampling on a 64x64
// grid for speed. `bytes_per_pixel` should be 3 or 4; for 4, the alpha byte is
// ignored. `rgb_order` = true for RGB(A), false for BGR(A).
double AverageBrightness(const uint8_t* data,
                         uint32_t width,
                         uint32_t height,
                         uint32_t stride_bytes,
                         int bytes_per_pixel,
                         bool rgb_order) {
  if (!data || width == 0 || height == 0) return 0.0;
  constexpr uint32_t kGrid = 64;
  const uint32_t sx = std::max(1u, width / kGrid);
  const uint32_t sy = std::max(1u, height / kGrid);
  double total = 0.0;
  uint64_t count = 0;
  for (uint32_t y = 0; y < height; y += sy) {
    const uint8_t* row = data + static_cast<size_t>(y) * stride_bytes;
    for (uint32_t x = 0; x < width; x += sx) {
      const uint8_t* px = row + x * bytes_per_pixel;
      uint8_t c0 = px[0], c1 = px[1], c2 = px[2];
      double r = (rgb_order ? c0 : c2) / 255.0;
      double g = c1 / 255.0;
      double b = (rgb_order ? c2 : c0) / 255.0;
      total += 0.299 * r + 0.587 * g + 0.114 * b;
      count++;
    }
  }
  return count > 0 ? total / static_cast<double>(count) : 0.0;
}

int SetOptionString(mpv_handle* h, const char* name, const char* value) {
  return mpv_set_option_string(h, name, value);
}


}  // namespace

// ════════════════════════════════════════════════════════════════════════════
// MpvPlayer
// ════════════════════════════════════════════════════════════════════════════

MpvPlayer::MpvPlayer() = default;

MpvPlayer::~MpvPlayer() { Dispose(); }

void MpvPlayer::OnMpvWakeup(void* ctx) {
  auto* self = static_cast<MpvPlayer*>(ctx);
  if (self && self->wakeup_handler_) self->wakeup_handler_();
}

void MpvPlayer::OnMpvRenderUpdate(void* ctx) {
  auto* self = static_cast<MpvPlayer*>(ctx);
  if (!self) return;
  self->render_pending_.store(true, std::memory_order_release);
  if (self->update_handler_) self->update_handler_();
}

bool MpvPlayer::Initialize(std::string* error) {
  // libmpv refuses to start under non-C LC_NUMERIC and will otherwise
  // misparse option strings (probesize, analyzeduration, …) leading to
  // heap corruption. Enforce here too in case the host app changed the
  // locale after plugin registration.
  std::setlocale(LC_NUMERIC, "C");
  mpv_ = mpv_create();
  if (!mpv_) {
    if (error) *error = "mpv_create failed";
    return false;
  }
  // Avoid reading user config or creating the usual mpv GUI surface.
  SetOptionString(mpv_, "config", "no");
  SetOptionString(mpv_, "terminal", "no");
  SetOptionString(mpv_, "msg-level", "all=warn");
  SetOptionString(mpv_, "audio-display", "no");
  SetOptionString(mpv_, "keep-open", "yes");
  // IMPORTANT: we render through MPV_RENDER_API_TYPE_SW (CPU-side RGBA).
  // Hardware-decoded frames live in GPU memory and libmpv's SW render path
  // cannot reliably read them back on Windows/Linux, which manifests as audio
  // playing but the texture never receiving a frame. Force software decoding
  // for the playback pipeline. (Snapshots & cover extraction use independent
  // mpv_handles and are unaffected.)
  SetOptionString(mpv_, "hwdec", "no");
  SetOptionString(mpv_, "vo", "libmpv");
  SetOptionString(mpv_, "idle", "yes");
  // Force libavformat to seek and probe aggressively so that MP4/MOV files
  // whose `moov` atom sits at the tail (i.e. not faststart-optimized) report
  // the correct duration instead of an early guess based on bitrate.
  // Without these the demuxer will happily stop after the first few MB, and
  // the reported duration for a 27-second tail-moov clip comes out as ~8 s.
  // `force-seekable=yes` ensures mpv will attempt byte-range seeks through
  // our HTTP cache proxy, which supports Range requests.
  SetOptionString(mpv_, "force-seekable", "yes");
  SetOptionString(mpv_, "demuxer-lavf-probesize", "50000000");       // 50 MB
  SetOptionString(mpv_, "demuxer-lavf-analyzeduration", "10000000"); // 10 s

  if (mpv_initialize(mpv_) < 0) {
    if (error) *error = "mpv_initialize failed";
    mpv_destroy(mpv_);
    mpv_ = nullptr;
    return false;
  }

  // SW render context.
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE,
       const_cast<char*>(MPV_RENDER_API_TYPE_SW)},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  if (mpv_render_context_create(&render_ctx_, mpv_, params) < 0) {
    if (error) *error = "mpv_render_context_create failed";
    mpv_destroy(mpv_);
    mpv_ = nullptr;
    return false;
  }

  mpv_set_wakeup_callback(mpv_, &MpvPlayer::OnMpvWakeup, this);
  mpv_render_context_set_update_callback(
      render_ctx_, &MpvPlayer::OnMpvRenderUpdate, this);

  mpv_observe_property(mpv_, kPropTimePos, "time-pos", MPV_FORMAT_DOUBLE);
  mpv_observe_property(mpv_, kPropDuration, "duration", MPV_FORMAT_DOUBLE);
  mpv_observe_property(mpv_, kPropPause, "pause", MPV_FORMAT_FLAG);
  mpv_observe_property(mpv_, kPropSeeking, "seeking", MPV_FORMAT_FLAG);
  mpv_observe_property(mpv_, kPropCache, "paused-for-cache", MPV_FORMAT_FLAG);
  mpv_observe_property(mpv_, kPropEof, "eof-reached", MPV_FORMAT_FLAG);
  mpv_observe_property(mpv_, kPropVideoWidth, "dwidth", MPV_FORMAT_INT64);
  mpv_observe_property(mpv_, kPropVideoHeight, "dheight", MPV_FORMAT_INT64);
  mpv_observe_property(mpv_, kPropSrcWidth, "width", MPV_FORMAT_INT64);
  mpv_observe_property(mpv_, kPropSrcHeight, "height", MPV_FORMAT_INT64);
  return true;
}

void MpvPlayer::Open(const std::string& url) {
  if (!mpv_) return;
  const char* cmd[] = {"loadfile", url.c_str(), "replace", nullptr};
  mpv_command_async(mpv_, 0, cmd);
}

void MpvPlayer::Play() {
  if (!mpv_) return;
  int flag = 0;
  mpv_set_property(mpv_, "pause", MPV_FORMAT_FLAG, &flag);
}

void MpvPlayer::Pause() {
  if (!mpv_) return;
  int flag = 1;
  mpv_set_property(mpv_, "pause", MPV_FORMAT_FLAG, &flag);
}

void MpvPlayer::Seek(int64_t ms) {
  if (!mpv_) return;
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%.3f", ms / 1000.0);
  const char* cmd[] = {"seek", buf, "absolute+exact", nullptr};
  mpv_command_async(mpv_, 0, cmd);
}

void MpvPlayer::SetVolume(double volume) {
  if (!mpv_) return;
  double v = std::max(0.0, std::min(1.0, volume)) * 100.0;
  mpv_set_property(mpv_, "volume", MPV_FORMAT_DOUBLE, &v);
}

void MpvPlayer::SetSpeed(double speed) {
  if (!mpv_) return;
  double s = std::max(0.1, std::min(4.0, speed));
  mpv_set_property(mpv_, "speed", MPV_FORMAT_DOUBLE, &s);
}

void MpvPlayer::Dispose() {
  if (render_ctx_) {
    mpv_render_context_free(render_ctx_);
    render_ctx_ = nullptr;
  }
  if (mpv_) {
    mpv_set_wakeup_callback(mpv_, nullptr, nullptr);
    mpv_terminate_destroy(mpv_);
    mpv_ = nullptr;
  }
}

void MpvPlayer::DrainEvents() {
  if (!mpv_) return;
  for (;;) {
    mpv_event* ev = mpv_wait_event(mpv_, 0);
    if (!ev || ev->event_id == MPV_EVENT_NONE) break;
    HandleMpvEvent(ev);
  }
}

void MpvPlayer::HandleMpvEvent(mpv_event* ev) {
  switch (ev->event_id) {
    case MPV_EVENT_END_FILE: {
      auto* info = static_cast<mpv_event_end_file*>(ev->data);
      if (info && info->reason == MPV_END_FILE_REASON_EOF) {
        if (on_completed_) on_completed_();
      } else if (info && info->reason == MPV_END_FILE_REASON_ERROR) {
        if (on_error_) on_error_(mpv_error_string(info->error));
      }
      break;
    }
    case MPV_EVENT_LOG_MESSAGE:
      break;
    case MPV_EVENT_VIDEO_RECONFIG: {
      // Kick a render after any video reconfig (size change, new stream, etc.)
      // so Windows SW rendering can break out of the
      // dwidth-is-0-until-first-render chicken-and-egg.
      render_pending_.store(true, std::memory_order_release);
      if (update_handler_) update_handler_();
      break;
    }
    case MPV_EVENT_FILE_LOADED:
    case MPV_EVENT_START_FILE:
    case MPV_EVENT_PLAYBACK_RESTART: {
      // Property-change observation for `pause` only fires on *changes*.
      // When a new file starts and pause was already false (our default), no
      // event is delivered — the Dart side would be stuck in "loading"
      // forever because playingSignal never flips. Re-query the property on
      // these lifecycle events and re-emit so the UI state machine advances.
      if (mpv_ && on_playing_) {
        int paused = 0;
        if (mpv_get_property(mpv_, "pause", MPV_FORMAT_FLAG, &paused) >= 0) {
          on_playing_(paused == 0);
        }
      }
      if (mpv_ && on_buffering_) {
        // Also clear any stale "buffering" flag once playback starts.
        int cache_paused = 0;
        if (mpv_get_property(mpv_, "paused-for-cache", MPV_FORMAT_FLAG,
                             &cache_paused) >= 0) {
          on_buffering_(cache_paused != 0);
        }
      }
      // And make sure at least one render has been kicked.
      render_pending_.store(true, std::memory_order_release);
      if (update_handler_) update_handler_();
      break;
    }
    case MPV_EVENT_PROPERTY_CHANGE: {
      auto* prop = static_cast<mpv_event_property*>(ev->data);
      switch (ev->reply_userdata) {
        case kPropTimePos:
          if (prop->format == MPV_FORMAT_DOUBLE && prop->data) {
            double v = *static_cast<double*>(prop->data);
            // mpv occasionally reports NaN/Inf for time-pos during seeks or
            // before the first frame is decoded. Casting a non-finite double
            // to int64_t is UB and historically gave astronomical values that
            // the UI then displayed as the "duration".
            if (std::isfinite(v) && v >= 0.0) {
              if (on_position_) on_position_(static_cast<int64_t>(v * 1000));
            }
          }
          break;
        case kPropDuration:
          if (prop->format == MPV_FORMAT_DOUBLE && prop->data) {
            double v = *static_cast<double*>(prop->data);
            if (std::isfinite(v) && v >= 0.0) {
              if (on_duration_) on_duration_(static_cast<int64_t>(v * 1000));
            }
          }
          break;
        case kPropPause:
          if (prop->format == MPV_FORMAT_FLAG && prop->data) {
            int v = *static_cast<int*>(prop->data);
            if (on_playing_) on_playing_(v == 0);
          }
          break;
        case kPropCache:
          if (prop->format == MPV_FORMAT_FLAG && prop->data) {
            int v = *static_cast<int*>(prop->data);
            if (on_buffering_) on_buffering_(v != 0);
          }
          break;
        case kPropSeeking:
          if (prop->format == MPV_FORMAT_FLAG && prop->data) {
            int v = *static_cast<int*>(prop->data);
            if (on_buffering_) on_buffering_(v != 0);
          }
          break;
        case kPropVideoWidth:
          if (prop->format == MPV_FORMAT_INT64 && prop->data) {
            video_w_.store(*static_cast<int64_t*>(prop->data));
            if (on_video_size_) {
              on_video_size_(video_w_.load(), video_h_.load());
            }
          }
          break;
        case kPropVideoHeight:
          if (prop->format == MPV_FORMAT_INT64 && prop->data) {
            video_h_.store(*static_cast<int64_t*>(prop->data));
            if (on_video_size_) {
              on_video_size_(video_w_.load(), video_h_.load());
            }
          }
          break;
        case kPropSrcWidth:
          if (prop->format == MPV_FORMAT_INT64 && prop->data) {
            src_w_.store(*static_cast<int64_t*>(prop->data));
            // Emit a videoSize event using the best dimensions we have so that
            // the Flutter side can render the texture immediately even before
            // dwidth/dheight settle (see kPropSrcWidth comment).
            if (on_video_size_) {
              int64_t w = video_w_.load();
              int64_t h = video_h_.load();
              if (w <= 0) w = src_w_.load();
              if (h <= 0) h = src_h_.load();
              if (w > 0 && h > 0) on_video_size_(w, h);
            }
            // Nudge the render loop: with a now-known size, we can perform
            // the first SW render even if dwidth/dheight haven't fired yet.
            render_pending_.store(true, std::memory_order_release);
            if (update_handler_) update_handler_();
          }
          break;
        case kPropSrcHeight:
          if (prop->format == MPV_FORMAT_INT64 && prop->data) {
            src_h_.store(*static_cast<int64_t*>(prop->data));
            if (on_video_size_) {
              int64_t w = video_w_.load();
              int64_t h = video_h_.load();
              if (w <= 0) w = src_w_.load();
              if (h <= 0) h = src_h_.load();
              if (w > 0 && h > 0) on_video_size_(w, h);
            }
            render_pending_.store(true, std::memory_order_release);
            if (update_handler_) update_handler_();
          }
          break;
        case kPropEof:
          break;
      }
      break;
    }
    case MPV_EVENT_SHUTDOWN:
      break;
    default:
      break;
  }
}

bool MpvPlayer::Render() {
  if (!render_ctx_) return false;
  if (!render_pending_.exchange(false, std::memory_order_acq_rel)) return false;

  // Prefer display dimensions (aspect-corrected), but fall back to raw source
  // dimensions if the VO hasn't populated dwidth/dheight yet. This is crucial
  // on Windows with SW rendering where dwidth/dheight only settle after the
  // first successful render.
  int64_t w = video_w_.load();
  int64_t h = video_h_.load();
  if (w <= 0 || h <= 0) {
    w = src_w_.load();
    h = src_h_.load();
  }
  if (w <= 0 || h <= 0) {
    // Still no video info — we'll get another update when the demuxer finishes
    // reading the stream header.
    return false;
  }

  // Cap SW rendering at 1080p. SW render cost scales with resolution and a
  // 4K frame is a 33 MB RGBA memcpy on every single frame — that's enough to
  // swamp CPU/memory bandwidth and cause visible stutter. The texture is
  // still displayed at its full natural aspect ratio via the Flutter side's
  // AspectRatio widget, so users don't notice the resolution cap.
  constexpr int64_t kMaxDim = 1920;
  if (w > kMaxDim || h > kMaxDim) {
    double scale = std::min(static_cast<double>(kMaxDim) / static_cast<double>(w),
                            static_cast<double>(kMaxDim) / static_cast<double>(h));
    w = static_cast<int64_t>(w * scale);
    h = static_cast<int64_t>(h * scale);
    if (w <= 0) w = 1;
    if (h <= 0) h = 1;
  }
  return PerformRender(static_cast<uint32_t>(w), static_cast<uint32_t>(h));
}

bool MpvPlayer::PerformRender(uint32_t w, uint32_t h) {
  std::lock_guard<std::mutex> lock(sw_mutex_);
  size_t needed = static_cast<size_t>(w) * h * 4;
  if (sw_buffer_.size() < needed) sw_buffer_.resize(needed);

  int size[2] = {static_cast<int>(w), static_cast<int>(h)};
  // libmpv supports `rgb0` on every build (rgba is not universally available).
  // The 4th byte is left unspecified — we zero-fill it to 0xFF below so the
  // Flutter Windows compositor (which multiplies against the alpha channel)
  // doesn't render the frame as fully transparent. Without this, Windows
  // shows audio-only playback with a seemingly-stuck "loading" overlay even
  // though frames are being produced.
  const char* sw_format = "rgb0";
  int stride = static_cast<int>(w) * 4;
  void* ptr = sw_buffer_.data();
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_SW_SIZE, size},
      {MPV_RENDER_PARAM_SW_FORMAT, const_cast<char*>(sw_format)},
      {MPV_RENDER_PARAM_SW_STRIDE, &stride},
      {MPV_RENDER_PARAM_SW_POINTER, ptr},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  int rc = mpv_render_context_render(render_ctx_, params);
  if (rc < 0) {
    if (on_error_) {
      on_error_(std::string("mpv_render_context_render failed: ") +
                mpv_error_string(rc));
    }
    return false;
  }

  // Force opaque alpha. rgb0's 4th byte is unspecified/zero, and Flutter's
  // texture compositors (Windows and some embedders) blend against it.
  // Use 32-bit OR to write all four bytes per step — 4x faster than a
  // byte-wise loop and measurably cheaper at 1080p @ 30+fps.
  {
    uint32_t* p = reinterpret_cast<uint32_t*>(sw_buffer_.data());
    const size_t pixels = static_cast<size_t>(w) * h;
    constexpr uint32_t kAlphaMask = 0xFF000000u;  // little-endian: A is MSB
    for (size_t i = 0; i < pixels; ++i) p[i] |= kAlphaMask;
  }

  sw_w_.store(w, std::memory_order_release);
  sw_h_.store(h, std::memory_order_release);
  if (on_frame_) on_frame_(sw_buffer_.data(), w, h);
  return true;
}

const uint8_t* MpvPlayer::sw_buffer() { return sw_buffer_.data(); }

bool MpvPlayer::TakeSnapshot(std::vector<uint8_t>* out, std::string* error) {
  if (!mpv_) {
    if (error) *error = "player not initialized";
    return false;
  }
  std::string path = TempFilePath(".png");
  const char* cmd[] = {"screenshot-to-file", path.c_str(), "video", nullptr};
  int rc = mpv_command(mpv_, cmd);
  if (rc < 0) {
    if (error) *error = mpv_error_string(rc);
    return false;
  }
  bool ok = ReadAllBytes(path, out);
  mpv_unlink(path.c_str());
  if (!ok && error) *error = "failed to read snapshot file";
  return ok;
}

// ────────────────────────────────────────────────────────────────────────────
// Cover extraction (static, uses a short-lived mpv_handle).
// ────────────────────────────────────────────────────────────────────────────

std::vector<CoverFrame> MpvPlayer::ExtractCovers(const std::string& url,
                                                 int count,
                                                 int candidates,
                                                 double min_brightness,
                                                 const std::string& output_dir,
                                                 std::string* error) {
  std::vector<CoverFrame> result;
  if (count <= 0) return result;
  if (candidates < count) candidates = count * 3;

  std::setlocale(LC_NUMERIC, "C");
  mpv_handle* h = mpv_create();
  if (!h) {
    if (error) *error = "mpv_create failed";
    return result;
  }
  struct Guard {
    mpv_handle* h;
    ~Guard() { if (h) mpv_terminate_destroy(h); }
  } guard{h};

  SetOptionString(h, "config", "no");
  SetOptionString(h, "terminal", "no");
  SetOptionString(h, "msg-level", "all=error");
  SetOptionString(h, "audio", "no");
  SetOptionString(h, "vo", "null");
  SetOptionString(h, "hwdec", "no");
  SetOptionString(h, "pause", "yes");
  SetOptionString(h, "keep-open", "yes");

  if (mpv_initialize(h) < 0) {
    if (error) *error = "mpv_initialize failed";
    return result;
  }

  // Load the file, wait for it to actually be loaded.
  const char* load[] = {"loadfile", url.c_str(), "replace", nullptr};
  if (mpv_command(h, load) < 0) {
    if (error) *error = "loadfile failed";
    return result;
  }

  // Pump events until we see MPV_EVENT_FILE_LOADED (with timeout).
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(15);
  bool loaded = false;
  while (std::chrono::steady_clock::now() < deadline) {
    mpv_event* ev = mpv_wait_event(h, 0.2);
    if (!ev) continue;
    if (ev->event_id == MPV_EVENT_FILE_LOADED) { loaded = true; break; }
    if (ev->event_id == MPV_EVENT_END_FILE) break;
  }
  if (!loaded) {
    if (error) *error = "timeout waiting for file load";
    return result;
  }

  double duration = 0.0;
  if (mpv_get_property(h, "duration", MPV_FORMAT_DOUBLE, &duration) < 0 ||
      duration <= 0.0) {
    if (error) *error = "could not read duration";
    return result;
  }

  // Build sample times — skip first/last 5%, sample `n` positions evenly.
  int n = std::max(candidates, count);
  const double lower = duration * 0.05;
  const double upper = duration * 0.95;
  const double span = std::max(upper - lower, 0.1);

  // Ensure output directory exists — best effort (caller should also ensure).
  // Here we rely on the caller to pre-create; if not, screenshot-to-file fails.

  auto hash_url = std::to_string(
      std::hash<std::string>{}(url));

  for (int i = 0; i < n && static_cast<int>(result.size()) < count; ++i) {
    double t = lower + span * (i + 0.5) / n;
    // Seek to `t`.
    char tbuf[64];
    std::snprintf(tbuf, sizeof(tbuf), "%.3f", t);
    const char* seek[] = {"seek", tbuf, "absolute+exact", nullptr};
    if (mpv_command(h, seek) < 0) continue;

    // Drain events briefly to let the seek settle.
    const auto step_deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < step_deadline) {
      mpv_event* ev = mpv_wait_event(h, 0.05);
      if (!ev) break;
      if (ev->event_id == MPV_EVENT_PLAYBACK_RESTART) break;
      if (ev->event_id == MPV_EVENT_NONE) break;
    }

    // screenshot-raw: returns MPV_FORMAT_NODE_MAP with keys w/h/stride/format/data.
    mpv_node result_node;
    std::memset(&result_node, 0, sizeof(result_node));
    const char* shot[] = {"screenshot-raw", "video", nullptr};
    int rc = mpv_command_ret(h, shot, &result_node);
    if (rc < 0) continue;

    // Parse the node: { w, h, stride, format, data }
    uint32_t rw = 0, rh = 0, rstride = 0;
    const char* fmt = nullptr;
    const uint8_t* rdata = nullptr;
    size_t rdata_size = 0;
    if (result_node.format == MPV_FORMAT_NODE_MAP) {
      mpv_node_list* m = result_node.u.list;
      for (int k = 0; k < m->num; ++k) {
        const char* key = m->keys[k];
        mpv_node& v = m->values[k];
        if (std::strcmp(key, "w") == 0 && v.format == MPV_FORMAT_INT64) {
          rw = static_cast<uint32_t>(v.u.int64);
        } else if (std::strcmp(key, "h") == 0 &&
                   v.format == MPV_FORMAT_INT64) {
          rh = static_cast<uint32_t>(v.u.int64);
        } else if (std::strcmp(key, "stride") == 0 &&
                   v.format == MPV_FORMAT_INT64) {
          rstride = static_cast<uint32_t>(v.u.int64);
        } else if (std::strcmp(key, "format") == 0 &&
                   v.format == MPV_FORMAT_STRING) {
          fmt = v.u.string;
        } else if (std::strcmp(key, "data") == 0 &&
                   v.format == MPV_FORMAT_BYTE_ARRAY) {
          rdata = reinterpret_cast<const uint8_t*>(v.u.ba->data);
          rdata_size = v.u.ba->size;
        }
      }
    }

    double brightness = 0.0;
    if (rw > 0 && rh > 0 && rdata && rdata_size >= static_cast<size_t>(rh) *
                                                         rstride) {
      // mpv screenshot-raw returns BGR0 by default on little-endian (format
      // string "bgr0"). Treat unknown formats as BGR0 too since that is the
      // documented default.
      bool rgb_order = (fmt && (std::strcmp(fmt, "rgb0") == 0 ||
                                std::strcmp(fmt, "rgba") == 0));
      brightness = AverageBrightness(rdata, rw, rh, rstride, 4, rgb_order);
    }

    mpv_free_node_contents(&result_node);

    if (brightness < min_brightness) continue;

    // Write the PNG via mpv's screenshot-to-file for simplicity.
    int64_t t_ms = static_cast<int64_t>(t * 1000);
    std::ostringstream name;
    name << output_dir;
    if (!output_dir.empty() && output_dir.back() != '/' &&
        output_dir.back() != '\\') {
      name << '/';
    }
    name << "cover-" << hash_url << "-" << t_ms << ".png";
    std::string out_path = name.str();
    const char* save[] = {"screenshot-to-file", out_path.c_str(), "video",
                          nullptr};
    if (mpv_command(h, save) < 0) continue;

    CoverFrame cf;
    cf.path = out_path;
    cf.position_ms = t_ms;
    cf.brightness = brightness;
    result.push_back(std::move(cf));
  }

  std::sort(result.begin(), result.end(),
            [](const CoverFrame& a, const CoverFrame& b) {
              return a.brightness > b.brightness;
            });
  if (static_cast<int>(result.size()) > count) result.resize(count);
  return result;
}

int64_t MpvPlayer::GetDurationMs(const std::string& url,
                                 int timeout_ms,
                                 std::string* error) {
  if (url.empty()) {
    if (error) *error = "empty url";
    return 0;
  }

  std::setlocale(LC_NUMERIC, "C");
  mpv_handle* h = mpv_create();
  if (!h) {
    if (error) *error = "mpv_create failed";
    return 0;
  }
  struct Guard {
    mpv_handle* h;
    ~Guard() { if (h) mpv_terminate_destroy(h); }
  } guard{h};

  SetOptionString(h, "config", "no");
  SetOptionString(h, "terminal", "no");
  SetOptionString(h, "msg-level", "all=error");
  SetOptionString(h, "audio", "no");
  SetOptionString(h, "vid", "no");
  SetOptionString(h, "vo", "null");
  SetOptionString(h, "ao", "null");
  SetOptionString(h, "hwdec", "no");
  SetOptionString(h, "pause", "yes");
  SetOptionString(h, "keep-open", "yes");
  // Mirror the main player's demuxer probe knobs so tail-moov MP4s report
  // the correct total duration instead of a truncated estimate.
  SetOptionString(h, "force-seekable", "yes");
  SetOptionString(h, "demuxer-lavf-probesize", "50000000");
  SetOptionString(h, "demuxer-lavf-analyzeduration", "10000000");

  if (mpv_initialize(h) < 0) {
    if (error) *error = "mpv_initialize failed";
    return 0;
  }

  const char* load[] = {"loadfile", url.c_str(), "replace", nullptr};
  if (mpv_command(h, load) < 0) {
    if (error) *error = "loadfile failed";
    return 0;
  }

  const int wait_ms = timeout_ms > 0 ? timeout_ms : 15000;
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::milliseconds(wait_ms);
  bool loaded = false;
  while (std::chrono::steady_clock::now() < deadline) {
    mpv_event* ev = mpv_wait_event(h, 0.2);
    if (!ev) continue;
    if (ev->event_id == MPV_EVENT_FILE_LOADED) { loaded = true; break; }
    if (ev->event_id == MPV_EVENT_END_FILE) break;
  }
  if (!loaded) {
    if (error) *error = "timeout waiting for file load";
    return 0;
  }

  double duration = 0.0;
  if (mpv_get_property(h, "duration", MPV_FORMAT_DOUBLE, &duration) < 0) {
    if (error) *error = "could not read duration";
    return 0;
  }
  if (!std::isfinite(duration) || duration <= 0.0) {
    if (error) *error = "non-finite duration";
    return 0;
  }
  return static_cast<int64_t>(duration * 1000.0);
}

}  // namespace flutter_cache_video_player
