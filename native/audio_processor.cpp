#include "audio_processor.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <limits>
#include <thread>

namespace violin {

namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr float kTwoPi = 2.0f * kPi;

constexpr float kMinPitchHz = 70.0f;
constexpr float kMaxPitchHz = 1200.0f;

constexpr float kMPMThreshold = 0.70f;

constexpr float kScratchFlatnessThreshold = 0.30f;
constexpr float kScratchHnrThresholdDb = 6.0f;

constexpr std::size_t kFFTSize = kFrameSize;

using Complex = std::complex<float>;

static void applyHannWindow(
    const std::array<float, kFrameSize>& input,
    std::array<float, kFrameSize>& output) noexcept
{
    for (std::size_t i = 0; i < kFrameSize; ++i) {
        const float phase =
            kTwoPi * static_cast<float>(i) /
            static_cast<float>(kFrameSize - 1);

        const float window =
            0.5f * (1.0f - std::cos(phase));

        output[i] = input[i] * window;
    }
}

/**
 * In-place radix-2 Cooley-Tukey FFT.
 *
 * No allocations.
 */
static void fft(
    std::array<Complex, kFFTSize>& data) noexcept
{
    // Bit reversal.
    for (std::size_t i = 1, j = 0;
         i < kFFTSize;
         ++i) {

        std::size_t bit = kFFTSize >> 1;

        for (; j & bit; bit >>= 1) {
            j ^= bit;
        }

        j ^= bit;

        if (i < j) {
            std::swap(data[i], data[j]);
        }
    }

    // Butterfly stages.
    for (std::size_t len = 2;
         len <= kFFTSize;
         len <<= 1) {

        const float angle =
            -kTwoPi / static_cast<float>(len);

        const Complex wlen(
            std::cos(angle),
            std::sin(angle));

        for (std::size_t i = 0;
             i < kFFTSize;
             i += len) {

            Complex w(1.0f, 0.0f);

            const std::size_t half = len >> 1;

            for (std::size_t j = 0;
                 j < half;
                 ++j) {

                const Complex u = data[i + j];
                const Complex v =
                    data[i + j + half] * w;

                data[i + j] = u + v;
                data[i + j + half] = u - v;

                w *= wlen;
            }
        }
    }
}

static float magnitudeSquared(
    const Complex& value) noexcept
{
    return value.real() * value.real() +
           value.imag() * value.imag();
}

static float hzToBin(
    float hz,
    float sample_rate) noexcept
{
    return hz *
           static_cast<float>(kFFTSize) /
           sample_rate;
}

static float binToHz(
    float bin,
    float sample_rate) noexcept
{
    return bin *
           sample_rate /
           static_cast<float>(kFFTSize);
}

} // anonymous namespace

ViolinTracker::ViolinTracker(float sample_rate)
    : sample_rate_(sample_rate)
{
}

ViolinTracker::~ViolinTracker()
{
    stop();
}

bool ViolinTracker::start() noexcept
{
    bool expected = false;

    if (!running_.compare_exchange_strong(
            expected,
            true,
            std::memory_order_acq_rel)) {
        return false;
    }

    worker_thread_ = std::thread(
        &ViolinTracker::workerLoop,
        this);

    return true;
}

void ViolinTracker::stop() noexcept
{
    bool expected = true;

    if (!running_.compare_exchange_strong(
            expected,
            false,
            std::memory_order_acq_rel)) {
        return;
    }

    if (worker_thread_.joinable()) {
        worker_thread_.join();
    }
}

std::size_t ViolinTracker::pushSamples(
    const float* samples,
    std::size_t count) noexcept
{
    return input_buffer_.push(samples, count);
}

void ViolinTracker::setCallback(
    PitchCallback callback) noexcept
{
    callback_.store(
        callback,
        std::memory_order_release);
}

void ViolinTracker::workerLoop() noexcept
{
    std::array<float, kFrameSize> frame{};

    while (running_.load(std::memory_order_acquire)) {

        const std::size_t available =
            input_buffer_.available();

        if (available < kFrameSize) {
            // No blocking primitive is used. This keeps the hot path
            // free of mutexes/condition variables.
            //
            // Production version may use an RT-friendly wakeup strategy
            // outside the microphone callback, or tune scheduler priority.
            std::this_thread::yield();
            continue;
        }

        const std::size_t pulled =
            input_buffer_.pull(
                frame.data(),
                kFrameSize);

        if (pulled != kFrameSize) {
            continue;
        }

        const PitchResult result =
            processFrame(frame);

        PitchCallback callback =
            callback_.load(std::memory_order_acquire);

        if (callback != nullptr) {
            /**
             * IMPORTANT REALTIME BOUNDARY:
             *
             * All DSP and memory work has already completed above.
             *
             * With Dart NativeCallable.listener, the trampoline is designed
             * for arbitrary native threads and sends the callback event to
             * the Dart isolate. The callback is therefore void and the
             * PitchResult itself is copied as the argument.
             */
            callback(result);
        }
    }
}

/**
 * McLeod Pitch Method / Normalized Square Difference foundation.
 *
 * The classical MPM implementation additionally performs:
 *   - NSDF calculation
 *   - peak identification
 *   - threshold crossing
 *   - strongest peak selection
 *   - parabolic interpolation
 *
 * This implementation contains that basic structure.
 */
float ViolinTracker::calculateMPM(
    const std::array<float, kFrameSize>& frame,
    float& confidence) const noexcept
{
    confidence = 0.0f;

    float best_pitch = 0.0f;
    float best_nsdf = -1.0f;

    const std::size_t min_lag =
        static_cast<std::size_t>(
            std::floor(
                sample_rate_ / kMaxPitchHz));

    const std::size_t max_lag =
        std::min<std::size_t>(
            kFrameSize / 2,
            static_cast<std::size_t>(
                std::ceil(
                    sample_rate_ / kMinPitchHz)));

    if (min_lag < 2 || max_lag >= kFrameSize) {
        return 0.0f;
    }

    // Normalized Square Difference Function.
    std::array<float, kFrameSize / 2 + 1> nsdf{};

    for (std::size_t lag = min_lag;
         lag <= max_lag;
         ++lag) {

        double numerator = 0.0;
        double denominator = 0.0;

        const std::size_t length =
            kFrameSize - lag;

        for (std::size_t i = 0;
             i < length;
             ++i) {

            const float a = frame[i];
            const float b = frame[i + lag];

            numerator +=
                static_cast<double>(a) *
                static_cast<double>(b);

            denominator +=
                static_cast<double>(a) * a +
                static_cast<double>(b) * b;
        }

        if (denominator > 1.0e-12) {
            nsdf[lag] =
                static_cast<float>(
                    2.0 * numerator /
                    denominator);
        }
    }

    // Find local maxima over the MPM threshold.
    for (std::size_t lag = min_lag + 1;
         lag + 1 <= max_lag;
         ++lag) {

        const float prev = nsdf[lag - 1];
        const float current = nsdf[lag];
        const float next = nsdf[lag + 1];

        if (current < kMPMThreshold) {
            continue;
        }

        if (current < prev || current < next) {
            continue;
        }

        // Parabolic interpolation around the NSDF peak.
        const float denominator =
            prev - 2.0f * current + next;

        float shift = 0.0f;

        if (std::fabs(denominator) > 1.0e-8f) {
            shift =
                0.5f * (prev - next) /
                denominator;
        }

        const float refined_lag =
            static_cast<float>(lag) + shift;

        if (refined_lag <= 0.0f) {
            continue;
        }

        const float candidate_pitch =
            sample_rate_ / refined_lag;

        if (candidate_pitch < kMinPitchHz ||
            candidate_pitch > kMaxPitchHz) {
            continue;
        }

        if (current > best_nsdf) {
            best_nsdf = current;
            best_pitch = candidate_pitch;
        }
    }

    if (best_pitch <= 0.0f) {
        return 0.0f;
    }

    confidence =
        std::clamp(best_nsdf, 0.0f, 1.0f);

    return best_pitch;
}

float ViolinTracker::calculateSpectralFlatness(
    const std::array<float, kFrameSize>& frame) const noexcept
{
    std::array<float, kFrameSize> windowed{};

    applyHannWindow(frame, windowed);

    std::array<Complex, kFFTSize> spectrum{};

    for (std::size_t i = 0;
         i < kFFTSize;
         ++i) {
        spectrum[i] =
            Complex(windowed[i], 0.0f);
    }

    fft(spectrum);

    double log_sum = 0.0;
    double arithmetic_sum = 0.0;

    // Only positive frequencies.
    constexpr std::size_t bins =
        kFFTSize / 2;

    constexpr float epsilon = 1.0e-12f;

    for (std::size_t i = 1;
         i < bins;
         ++i) {

        const float power =
            magnitudeSquared(spectrum[i]);

        arithmetic_sum +=
            static_cast<double>(power);

        log_sum +=
            std::log(
                static_cast<double>(
                    std::max(power, epsilon)));
    }

    if (arithmetic_sum <= 0.0) {
        return 1.0f;
    }

    const double arithmetic_mean =
        arithmetic_sum /
        static_cast<double>(bins - 1);

    const double geometric_mean =
        std::exp(
            log_sum /
            static_cast<double>(bins - 1));

    return static_cast<float>(
        geometric_mean /
        std::max(arithmetic_mean, 1.0e-12));
}

float ViolinTracker::calculateHarmonicsToNoise(
    const std::array<float, kFrameSize>& frame,
    float fundamental_hz) const noexcept
{
    if (fundamental_hz <= 0.0f) {
        return -100.0f;
    }

    std::array<float, kFrameSize> windowed{};

    applyHannWindow(frame, windowed);

    std::array<Complex, kFFTSize> spectrum{};

    for (std::size_t i = 0;
         i < kFFTSize;
         ++i) {
        spectrum[i] =
            Complex(windowed[i], 0.0f);
    }

    fft(spectrum);

    constexpr std::size_t half =
        kFFTSize / 2;

    double total_power = 0.0;
    double harmonic_power = 0.0;

    for (std::size_t i = 1; i < half; ++i) {
        const float power =
            magnitudeSquared(spectrum[i]);

        total_power +=
            static_cast<double>(power);
    }

    if (total_power <= 1.0e-12) {
        return -100.0f;
    }

    /**
     * Harmonic energy model:
     *
     * fundamental, 2f0, 3f0 ... up to Nyquist.
     *
     * Around each expected harmonic we take a small local peak window.
     * This is deliberately conservative for an MVP.
     */
    for (int harmonic = 1; ; ++harmonic) {

        const float harmonic_hz =
            fundamental_hz *
            static_cast<float>(harmonic);

        if (harmonic_hz >=
            sample_rate_ * 0.5f) {
            break;
        }

        const float center =
            hzToBin(
                harmonic_hz,
                sample_rate_);

        const int center_bin =
            static_cast<int>(
                std::lround(center));

        const int radius = 2;

        float local_peak = 0.0f;

        for (int offset = -radius;
             offset <= radius;
             ++offset) {

            const int bin =
                center_bin + offset;

            if (bin <= 0 ||
                bin >= static_cast<int>(half)) {
                continue;
            }

            local_peak =
                std::max(
                    local_peak,
                    magnitudeSquared(
                        spectrum[
                            static_cast<std::size_t>(bin)]));
        }

        harmonic_power +=
            static_cast<double>(local_peak);
    }

    harmonic_power =
        std::min(
            harmonic_power,
            total_power);

    const double noise_power =
        std::max(
            total_power - harmonic_power,
            1.0e-12);

    return static_cast<float>(
        10.0 *
        std::log10(
            harmonic_power /
            noise_power));
}

float ViolinTracker::calculateDynamicTolerance(
    float base_cents,
    float local_variance,
    float stretch) const noexcept
{
    return std::max(
        0.0f,
        base_cents +
        local_variance * stretch);
}

float ViolinTracker::estimateLocalPitchVariance()
    const noexcept
{
    if (pitch_history_size_ < 2) {
        return 0.0f;
    }

    /**
     * Variance is computed in cents relative to the current
     * local mean pitch.
     *
     * This makes vibrato tolerance approximately scale invariant.
     */
    double mean_log2 = 0.0;

    for (std::size_t i = 0;
         i < pitch_history_size_;
         ++i) {

        const float hz =
            pitch_history_[i];

        if (hz <= 0.0f) {
            continue;
        }

        mean_log2 +=
            std::log2(
                static_cast<double>(hz));
    }

    mean_log2 /=
        static_cast<double>(pitch_history_size_);

    double variance = 0.0;

    for (std::size_t i = 0;
         i < pitch_history_size_;
         ++i) {

        const float hz =
            pitch_history_[i];

        if (hz <= 0.0f) {
            continue;
        }

        const double cents =
            1200.0 *
            (std::log2(
                static_cast<double>(hz)) -
             mean_log2);

        variance += cents * cents;
    }

    variance /=
        static_cast<double>(pitch_history_size_);

    return static_cast<float>(variance);
}

void ViolinTracker::updatePitchHistory(
    float pitch_hz) noexcept
{
    if (pitch_hz <= 0.0f) {
        return;
    }

    pitch_history_[pitch_history_write_] =
        pitch_hz;

    pitch_history_write_ =
        (pitch_history_write_ + 1) %
        pitch_history_.size();

    pitch_history_size_ =
        std::min(
            pitch_history_size_ + 1,
            pitch_history_.size());
}

PitchResult ViolinTracker::processFrame(
    const std::array<float, kFrameSize>& frame) noexcept
{
    PitchResult result{};

    result.frequency_hz = 0.0f;
    result.confidence = 0.0f;
    result.is_scratching = 0;

    float confidence = 0.0f;

    const float pitch =
        calculateMPM(
            frame,
            confidence);

    result.frequency_hz = pitch;
    result.confidence = confidence;

    if (pitch <= 0.0f ||
        confidence < 0.50f) {
        result.is_scratching = 1;
        return result;
    }

    updatePitchHistory(pitch);

    const float spectral_flatness =
        calculateSpectralFlatness(frame);

    const float hnr_db =
        calculateHarmonicsToNoise(
            frame,
            pitch);

    /**
     * Basic scratching detector.
     *
     * Typical violin bow noise tends to increase broadband energy,
     * therefore spectral flatness rises and harmonic concentration falls.
     *
     * These thresholds MUST be calibrated against your actual microphone,
     * room, bow technique and violin.
     */
    const bool high_noise_floor =
        spectral_flatness >
        kScratchFlatnessThreshold;

    const bool weak_harmonic_structure =
        hnr_db <
        kScratchHnrThresholdDb;

    result.is_scratching =
        (high_noise_floor ||
         weak_harmonic_structure)
            ? 1
            : 0;

    /**
     * Vibrato compensation.
     *
     * tolerance = base + local_variance * stretch
     *
     * Example starting values:
     *   base = 20 cents
     *   stretch = 0.04
     *
     * The actual note-target matching happens downstream.
     *
     * OLTW INTEGRATION POINT #1
     * ----------------------------------------
     * At this point the raw estimated pitch should be converted into a
     * normalized pitch trajectory / note sequence representation.
     *
     * OLTW should then align:
     *
     *     observed pitch trajectory
     *             vs.
     *     reference note trajectory
     *
     * without introducing a blocking operation in the audio worker.
     *
     * Recommended architecture:
     *
     *     realtime DSP worker
     *          |
     *          +--> immutable PitchResult stream
     *                         |
     *                         v
     *               non-realtime temporal layer
     *                         |
     *                         +--> OLTW
     *                         +--> note alignment
     *                         +--> scoring
     *
     * Do NOT put a dynamic-programming OLTW matrix into this 4096-sample
     * realtime frame loop.
     */
    const float local_variance =
        estimateLocalPitchVariance();

    const float tolerance_cents =
        calculateDynamicTolerance(
            20.0f,
            local_variance,
            0.04f);

    (void)tolerance_cents;

    /**
     * OLTW INTEGRATION POINT #2
     * ----------------------------------------
     * The eventual note-target tracker should consume:
     *
     *   pitch_hz
     *   confidence
     *   spectral_flatness
     *   hnr_db
     *   dynamic_tolerance_cents
     *
     * and expose an immutable event/feature structure to the Dart layer.
     *
     * That layer can then render note highlighting independently from
     * the realtime DSP timing budget.
     */

    return result;
}

} // namespace violin