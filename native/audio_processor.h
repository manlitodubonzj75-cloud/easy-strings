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
 *   uint8 is_legato      9  (1 if transition from previous note was continuous on one bow stroke)
 *   uint8 rms_energy     10 (0..255 scaled RMS loudness)
 *   uint8 reserved       11
 *
 * Total expected size: 12 bytes.
 */
struct PitchResult {
    float frequency_hz;
    float confidence;
    std::uint8_t is_scratching;
    std::uint8_t is_legato;
    std::uint8_t rms_energy;
    std::uint8_t reserved;
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

    std::size_t pushSamples(
        const float* samples,
        std::size_t count) noexcept;

    void setCallback(
        PitchCallback callback) noexcept;

private:
    void workerLoop() noexcept;

    PitchResult processFrame(
        const std::array<float, kFrameSize>& frame) noexcept;

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
        float stretch = 1.0f) const noexcept;

    float estimateLocalPitchVariance() const noexcept;
    void updatePitchHistory(float pitch_hz) noexcept;

private:
    float sample_rate_;
    std::atomic<bool> running_{false};
    std::atomic<bool> mic_active_{false};
    void* platform_mic_handle_{nullptr};
    std::thread worker_thread_;

    SpscRingBuffer<float, 65536> input_buffer_;
    std::atomic<PitchCallback> callback_{nullptr};

    std::array<float, 16> pitch_history_{};
    std::size_t pitch_history_write_{0};
    std::size_t pitch_history_size_{0};

    // Legato (slur) transition tracker state
    float last_stable_pitch_{0.0f};
    float min_rms_transition_{1.0f};

    static constexpr float kMinPitchHz = 160.0f; // Violin G3 ~196 Hz (margin for flat tuning)
    static constexpr float kMaxPitchHz = 2200.0f; // High positions on E5 string

    static constexpr float kScratchFlatnessThreshold = 0.35f;
    static constexpr float kScratchHnrThresholdDb = 6.0f;
};


void playAudioTone(float freq_hz, float duration_sec) noexcept;
} // namespace violin
