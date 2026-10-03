#include "audio_processor.h"
#include "bowed_synth.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

#if defined(_WIN32)
    #define VIOLIN_EXPORT __declspec(dllexport)
#else
    #define VIOLIN_EXPORT __attribute__((visibility("default")))
#endif

extern "C" {

using PitchCallback = violin::PitchCallback;
using ViolinTracker = violin::ViolinTracker;

/**
 * Lifecycle: allocation is explicit and isolated.
 */
VIOLIN_EXPORT
void* violin_processor_create(float sample_rate)
{
    const std::size_t sr = (sample_rate >= 8000.0f && sample_rate <= 192000.0f)
        ? static_cast<std::size_t>(sample_rate)
        : 44100;
    return new ViolinTracker(sr);
}

/**
 * Worker thread execution control.
 */
VIOLIN_EXPORT
int violin_processor_start(void* handle)
{
    if (handle == nullptr) {
        return 0;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    processor->start();
    return 1;
}

/**
 * Graceful termination. Blocks until worker thread joins.
 */
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
 * Return current state of worker.
 */
VIOLIN_EXPORT
int violin_processor_is_running(void* handle)
{
    if (handle == nullptr) {
        return 0;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    return processor->isRunning() ? 1 : 0;
}

/**
 * Platform hardware microphone control.
 */
VIOLIN_EXPORT
int violin_processor_start_mic(void* handle)
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
int violin_processor_is_mic_active(void* handle)
{
    if (handle == nullptr) {
        return 0;
    }

    auto* processor =
        static_cast<ViolinTracker*>(handle);

    return processor->isMicActive() ? 1 : 0;
}

/**
 * Play authentic physical-modelled bowed tone through platform speaker.
 */
VIOLIN_EXPORT
void violin_play_tone(float frequency_hz, float duration_sec)
{
    violin::playAudioTone(frequency_hz, duration_sec, false);
}

VIOLIN_EXPORT
void violin_play_tone_legato(float frequency_hz, float duration_sec, int is_legato)
{
    violin::playAudioTone(frequency_hz, duration_sec, is_legato != 0);
}

VIOLIN_EXPORT
void violin_stop_tone()
{
    violin::stopAudioTone();
}

VIOLIN_EXPORT
int violin_is_tone_playing()
{
    return violin::isAudioTonePlaying() ? 1 : 0;
}

VIOLIN_EXPORT
void violin_processor_push_synth_note(
    void* handle,
    float frequency_hz,
    float duration_sec)
{
    if (frequency_hz <= 0.0f || duration_sec <= 0.0f) {
        return;
    }

    if (handle == nullptr) {
        return;
    }

    auto* processor = static_cast<ViolinTracker*>(handle);
    constexpr float kSampleRate = 44100.0f;
    const std::size_t total_samples = static_cast<std::size_t>(duration_sec * kSampleRate);

    constexpr std::size_t kChunkSize = 512;
    std::vector<float> chunk(kChunkSize);

    violin::BowedViolinModel synth(kSampleRate);
    synth.noteOn(frequency_hz, duration_sec);

    std::size_t emitted = 0;
    while (emitted < total_samples) {
        const std::size_t count = std::min(kChunkSize, total_samples - emitted);
        for (std::size_t i = 0; i < count; ++i) {
            chunk[i] = synth.tick();
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
