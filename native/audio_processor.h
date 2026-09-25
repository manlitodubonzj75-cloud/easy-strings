#pragma once

#include "ring_buffer.h"

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <thread>

namespace violin {

constexpr std::size_t kSampleRate = 44100;
// Frame size of 2048 gives ~46.4ms analysis window, hop size of 512 gives ~11.6ms update rate (~86Hz)
constexpr std::size_t kFrameSize  = 2048;
constexpr std::size_t kHopSize    = 512;

/**
 * Fixed-size ABI structure.
 *
 * Layout:
 *   float frequency_hz   0..3
 *   float confidence     4..7
 *   uint8 is_scratching  8
 *   uint8 reserved[3]    9..11
 *
 * Total expected size: 12 bytes.
 */
struct PitchResult {
    float frequency_hz;
    float confidence;
    std::uint8_t is_scratching;
    std::uint8_t reserved[3];
};

static_assert(sizeof(PitchResult) == 12,
              "PitchResult ABI layout must stay 12 bytes");

/**
 * Callback is intentionally void for Dart NativeCallable.listener.
 */
using PitchCallback = void (*)(PitchResult result);

class ViolinTracker final {
public:
    explicit ViolinTracker(float sample_rate = 44100.0f);
    ~ViolinTracker();

    ViolinTracker(const ViolinTracker&) = delete;
    ViolinTracker& operator=(const ViolinTracker&) = delete;

    bool start() noexcept;
    void stop() noexcept;

    /**
     * Start/stop native platform microphone capture directly into the ring buffer.
     */
    bool startMic() noexcept;
    void stopMic() noexcept;
    bool isMicActive() const noexcept;

    /**
     * Realtime-safe audio producer entry point.
     * Exactly one producer thread may call this method.
     */
    std::size_t pushSamples(
        const float* samples,
        std::size_t count) noexcept;

    void setCallback(PitchCallback callback) noexcept;

    float calculateMPM(
        const std::array<float, kFrameSize>& frame,
        float& confidence) const noexcept;

    float calculateSpectralFlatness(
        const std::array<float, kFrameSize>& frame) const noexcept;

    float calculateHarmonicsToNoise(
        const std::array<float, kFrameSize>& frame,
        float fundamental_hz) const noexcept;

    float calculateDynamicTolerance(
        float base_cents,
        float local_variance,
        float stretch) const noexcept;

private:
    void workerLoop() noexcept;

    PitchResult processFrame(
        const std::array<float, kFrameSize>& frame) noexcept;

    float estimateLocalPitchVariance() const noexcept;

    void updatePitchHistory(float pitch_hz) noexcept;

private:
    float sample_rate_;

    SpscRingBuffer<float, 32768> input_buffer_;

    std::atomic<bool> running_{false};
    std::atomic<bool> mic_active_{false};

    std::thread worker_thread_;

    std::atomic<PitchCallback> callback_{nullptr};

    // Last accepted pitch values for local vibrato variance.
    std::array<float, 32> pitch_history_{};
    std::size_t pitch_history_size_{0};
    std::size_t pitch_history_write_{0};

    // Pointer to platform-specific mic state (e.g. AudioQueue on Apple)
    void* platform_mic_handle_{nullptr};
};

} // namespace violin
