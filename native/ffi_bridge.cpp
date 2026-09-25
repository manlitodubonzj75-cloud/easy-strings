#include "audio_processor.h"

#include <cstddef>
#include <cstdint>
#include <new>

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
 *
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
 *
 * The supplied memory remains owned by the caller.
 * Samples are copied into the native SPSC ring.
 *
 * Exactly one native thread may call this function.
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
 *
 * The callback is stored atomically.
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

/**
 * Convenience ABI helper.
 */
VIOLIN_EXPORT
std::size_t violin_processor_buffered_samples(
    void* handle)
{
    // The private ring buffer is intentionally not exposed directly.
    // Kept as a placeholder for future diagnostics API.
    (void)handle;
    return 0;
}

} // extern "C"