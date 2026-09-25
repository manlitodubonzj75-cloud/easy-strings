#include "audio_processor.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <vector>

#if defined(_WIN32)
#define VIOLIN_EXPORT __declspec(dllexport)
#else
#define VIOLIN_EXPORT __attribute__((visibility("default")))
#endif

using violin::PitchCallback;
using violin::PitchResult;
using violin::ViolinTracker;

extern "C" {

/**
 * Opaque native handle.
 * Dart stores this as Pointer<Void>.
 */
VIOLIN_EXPORT
void* violin_processor_create(float sample_rate)
{
    if (sample_rate <= 0.0f) {
        sample_rate = 44100.0f;
    }

    try {
        return static_cast<void*>(
            new ViolinTracker(sample_rate));
    } catch (...) {
        return nullptr;
    }
}

VIOLIN_EXPORT
int32_t violin_processor_start(void* handle)
{
    if (handle == nullptr) {
        return 0;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    return processor->start() ? 1 : 0;
}

VIOLIN_EXPORT
void violin_processor_stop(void* handle)
{
    if (handle == nullptr) {
        return;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    processor->stop();
}

/**
 * Platform mic capture start/stop.
 */
VIOLIN_EXPORT
int32_t violin_processor_start_mic(void* handle)
{
    if (handle == nullptr) {
        return 0;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    return processor->startMic() ? 1 : 0;
}

VIOLIN_EXPORT
void violin_processor_stop_mic(void* handle)
{
    if (handle == nullptr) {
        return;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    processor->stopMic();
}

VIOLIN_EXPORT
int32_t violin_processor_is_mic_active(void* handle)
{
    if (handle == nullptr) {
        return 0;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    return processor->isMicActive() ? 1 : 0;
}

/**
 * Push synthetic tone (fundamental + 2nd and 3rd harmonics) for testing.
 */
VIOLIN_EXPORT
void violin_processor_push_synth_note(
    void* handle,
    float frequency_hz,
    float duration_sec)
{
    if (handle == nullptr || frequency_hz <= 0.0f || duration_sec <= 0.0f) {
        return;
    }

    auto* processor = static_cast<ViolinTracker*>(handle);
    constexpr float kSampleRate = 44100.0f;
    const std::size_t total_samples = static_cast<std::size_t>(duration_sec * kSampleRate);

    constexpr std::size_t kChunkSize = 512;
    std::vector<float> chunk(kChunkSize);

    constexpr float kTwoPi = 6.28318530717958647692f;
    float phase = 0.0f;
    const float phase_step = kTwoPi * frequency_hz / kSampleRate;

    std::size_t emitted = 0;
    while (emitted < total_samples) {
        const std::size_t count = std::min(kChunkSize, total_samples - emitted);
        for (std::size_t i = 0; i < count; ++i) {
            // Rich violin-like harmonic structure: fundamental + 2nd harmonic (often strong on violin)
            float s = 0.70f * std::sin(phase) +
                      0.35f * std::sin(2.0f * phase) +
                      0.15f * std::sin(3.0f * phase);
            chunk[i] = s;
            phase += phase_step;
            if (phase >= kTwoPi) {
                phase -= kTwoPi;
            }
        }
        processor->pushSamples(chunk.data(), count);
        emitted += count;
    }
}

/**
 * Destroy must only happen after stop.
 */
VIOLIN_EXPORT
void violin_processor_destroy(void* handle)
{
    if (handle == nullptr) {
        return;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    delete processor;
}

/**
 * Realtime-safe producer API.
 * The supplied memory remains owned by the caller.
 * Samples are copied into the native SPSC ring.
 */
VIOLIN_EXPORT
std::size_t violin_processor_push_samples(
    void* handle,
    const float* samples,
    std::size_t count)
{
    if (handle == nullptr ||
        samples == nullptr ||
        count == 0) {
        return 0;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    return processor->pushSamples(
        samples,
        count);
}

/**
 * Register / unregister callback.
 */
VIOLIN_EXPORT
void violin_processor_set_callback(
    void* handle,
    PitchCallback callback)
{
    if (handle == nullptr) {
        return;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    processor->setCallback(callback);
}

VIOLIN_EXPORT
std::size_t violin_processor_buffered_samples(
    void* handle)
{
    (void)handle;
    return 0;
}

} // extern "C"
