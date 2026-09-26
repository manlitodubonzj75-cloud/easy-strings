#include "audio_processor.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <complex>
#include <limits>
#include <thread>

#if defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>

namespace violin {

struct AppleAudioCapture {
    AudioQueueRef queue{nullptr};
    static constexpr int kNumBuffers = 3;
    static constexpr UInt32 kBufferSampleCount = 512;
    AudioQueueBufferRef buffers[kNumBuffers]{};
    ViolinTracker* tracker{nullptr};
    std::atomic<bool> is_recording{false};
};

static void appleAudioQueueCallback(
    void* userData,
    AudioQueueRef queue,
    AudioQueueBufferRef buffer,
    const AudioTimeStamp* /*startTime*/,
    UInt32 /*numPackets*/,
    const AudioStreamPacketDescription* /*packetDesc*/)
{
    auto* capture = static_cast<AppleAudioCapture*>(userData);
    if (!capture || !capture->is_recording.load(std::memory_order_acquire)) {
        return;
    }

    const float* samples = static_cast<const float*>(buffer->mAudioData);
    const std::size_t count = buffer->mAudioDataByteSize / sizeof(float);
    if (count > 0 && capture->tracker) {
        capture->tracker->pushSamples(samples, count);
    }

    AudioQueueEnqueueBuffer(queue, buffer, 0, nullptr);
}

} // namespace violin
#endif

namespace violin {

namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr float kTwoPi = 2.0f * kPi;

// Violin range: G3 (~196 Hz) to E7 (~2637 Hz).
// Setting min to 160.0f filters out AC hum (50/60/100/120 Hz) and room rumbles.
constexpr float kMinPitchHz = 160.0f;
constexpr float kMaxPitchHz = 2200.0f;

constexpr float kMPMThreshold = 0.70f;

constexpr float kScratchFlatnessThreshold = 0.28f;
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
 * No dynamic allocations.
 */
static void fft(
    std::array<Complex, kFFTSize>& data) noexcept
{
    for (std::size_t i = 1, j = 0; i < kFFTSize; ++i) {
        std::size_t bit = kFFTSize >> 1;
        for (; j & bit; bit >>= 1) {
            j ^= bit;
        }
        j ^= bit;

        if (i < j) {
            std::swap(data[i], data[j]);
        }
    }

    for (std::size_t len = 2; len <= kFFTSize; len <<= 1) {
        const float angle = -kTwoPi / static_cast<float>(len);
        const Complex wlen(std::cos(angle), std::sin(angle));

        for (std::size_t i = 0; i < kFFTSize; i += len) {
            Complex w(1.0f, 0.0f);
            const std::size_t half = len >> 1;

            for (std::size_t j = 0; j < half; ++j) {
                const Complex u = data[i + j];
                const Complex v = data[i + j + half] * w;

                data[i + j] = u + v;
                data[i + j + half] = u - v;

                w *= wlen;
            }
        }
    }
}

static float magnitudeSquared(const Complex& value) noexcept
{
    return value.real() * value.real() + value.imag() * value.imag();
}

static float hzToBin(float hz, float sample_rate) noexcept
{
    return hz * static_cast<float>(kFFTSize) / sample_rate;
}

} // anonymous namespace

ViolinTracker::ViolinTracker(float sample_rate)
    : sample_rate_(sample_rate)
{
}

ViolinTracker::~ViolinTracker()
{
    stopMic();
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

bool ViolinTracker::startMic() noexcept
{
    if (mic_active_.load(std::memory_order_acquire)) {
        return true;
    }
#if defined(__APPLE__)
    auto* capture = new (std::nothrow) AppleAudioCapture();
    if (!capture) {
        return false;
    }
    capture->tracker = this;

    AudioStreamBasicDescription format{};
    format.mSampleRate = sample_rate_;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = sizeof(float);
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(float);
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 32;

    OSStatus status = AudioQueueNewInput(
        &format,
        appleAudioQueueCallback,
        capture,
        nullptr,
        nullptr,
        0,
        &capture->queue);

    if (status != noErr) {
        delete capture;
        return false;
    }

    capture->is_recording.store(true, std::memory_order_release);
    const UInt32 bufferByteSize = AppleAudioCapture::kBufferSampleCount * sizeof(float);
    for (int i = 0; i < AppleAudioCapture::kNumBuffers; ++i) {
        status = AudioQueueAllocateBuffer(capture->queue, bufferByteSize, &capture->buffers[i]);
        if (status == noErr) {
            AudioQueueEnqueueBuffer(capture->queue, capture->buffers[i], 0, nullptr);
        }
    }

    status = AudioQueueStart(capture->queue, nullptr);
    if (status != noErr) {
        AudioQueueDispose(capture->queue, true);
        delete capture;
        return false;
    }

    platform_mic_handle_ = capture;
    mic_active_.store(true, std::memory_order_release);
    return true;
#else
    return false;
#endif
}

void ViolinTracker::stopMic() noexcept
{
    if (!mic_active_.exchange(false, std::memory_order_acq_rel)) {
        return;
    }
#if defined(__APPLE__)
    if (platform_mic_handle_) {
        auto* capture = static_cast<AppleAudioCapture*>(platform_mic_handle_);
        capture->is_recording.store(false, std::memory_order_release);
        AudioQueueStop(capture->queue, true);
        AudioQueueDispose(capture->queue, true);
        delete capture;
        platform_mic_handle_ = nullptr;
    }
#endif
}

bool ViolinTracker::isMicActive() const noexcept
{
    return mic_active_.load(std::memory_order_relaxed);
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
    std::size_t buffered = 0;

    std::array<float, kHopSize> hop_buffer{};

    while (running_.load(std::memory_order_acquire)) {
        const std::size_t available = input_buffer_.available();

        if (buffered < kFrameSize) {
            // Initial fill
            if (available == 0) {
                std::this_thread::sleep_for(std::chrono::microseconds(500));
                continue;
            }
            const std::size_t needed = kFrameSize - buffered;
            const std::size_t to_pull = std::min(needed, available);
            const std::size_t pulled = input_buffer_.pull(frame.data() + buffered, to_pull);
            buffered += pulled;

            if (buffered < kFrameSize) {
                continue;
            }
        } else {
            // Window is already full. Advance by kHopSize
            if (available < kHopSize) {
                std::this_thread::sleep_for(std::chrono::microseconds(500));
                continue;
            }

            const std::size_t pulled = input_buffer_.pull(hop_buffer.data(), kHopSize);
            if (pulled < kHopSize) {
                continue;
            }

            // Shift left by kHopSize
            std::copy(frame.begin() + kHopSize, frame.end(), frame.begin());
            // Append new hop samples at the tail
            std::copy(hop_buffer.begin(), hop_buffer.end(), frame.end() - kHopSize);
        }

        const PitchResult result = processFrame(frame);

        PitchCallback callback = callback_.load(std::memory_order_acquire);
        if (callback != nullptr) {
            callback(result);
        }
    }
}

float ViolinTracker::calculateMPM(
    const std::array<float, kFrameSize>& frame,
    float& confidence) const noexcept
{
    confidence = 0.0f;

    const std::size_t min_lag =
        static_cast<std::size_t>(
            std::floor(sample_rate_ / kMaxPitchHz));

    const std::size_t max_lag =
        std::min<std::size_t>(
            kFrameSize / 2,
            static_cast<std::size_t>(
                std::ceil(sample_rate_ / kMinPitchHz)));

    if (min_lag < 2 || max_lag >= kFrameSize) {
        return 0.0f;
    }

    // Normalized Square Difference Function (NSDF)
    std::array<float, kFrameSize / 2 + 1> nsdf{};

    for (std::size_t lag = min_lag; lag <= max_lag; ++lag) {
        double numerator = 0.0;
        double denominator = 0.0;

        const std::size_t length = kFrameSize - lag;

        for (std::size_t i = 0; i < length; ++i) {
            const float a = frame[i];
            const float b = frame[i + lag];

            numerator += static_cast<double>(a) * static_cast<double>(b);
            denominator += static_cast<double>(a) * a + static_cast<double>(b) * b;
        }

        if (denominator > 1.0e-12) {
            nsdf[lag] = static_cast<float>(2.0 * numerator / denominator);
        }
    }

    struct CandidatePeak {
        float lag;
        float nsdf;
        float pitch;
    };
    std::vector<CandidatePeak> peaks;
    peaks.reserve(16);
    float max_nsdf = -1.0f;

    // Find local maxima over threshold
    for (std::size_t lag = min_lag + 1; lag + 1 <= max_lag; ++lag) {
        const float prev = nsdf[lag - 1];
        const float current = nsdf[lag];
        const float next = nsdf[lag + 1];

        if (current < kMPMThreshold) {
            continue;
        }

        if (current < prev || current < next) {
            continue;
        }

        // Parabolic interpolation around NSDF peak
        const float denominator = prev - 2.0f * current + next;
        float shift = 0.0f;

        if (std::fabs(denominator) > 1.0e-8f) {
            shift = 0.5f * (prev - next) / denominator;
        }

        const float refined_lag = static_cast<float>(lag) + shift;
        if (refined_lag <= 0.0f) {
            continue;
        }

        const float candidate_pitch = sample_rate_ / refined_lag;
        if (candidate_pitch < kMinPitchHz || candidate_pitch > kMaxPitchHz) {
            continue;
        }

        peaks.push_back({refined_lag, current, candidate_pitch});
        if (current > max_nsdf) {
            max_nsdf = current;
        }
    }

    if (peaks.empty() || max_nsdf <= 0.0f) {
        return 0.0f;
    }

    // McLeod Pitch Method Key Maximum:
    // Pick the FIRST peak that reaches 0.85 of maximum NSDF to prevent octave jumping
    // on open strings (which often have strong 2nd harmonics).
    const float cutoff = 0.85f * max_nsdf;
    for (const auto& p : peaks) {
        if (p.nsdf >= cutoff) {
            confidence = std::clamp(p.nsdf, 0.0f, 1.0f);
            return p.pitch;
        }
    }

    confidence = std::clamp(max_nsdf, 0.0f, 1.0f);
    return peaks.front().pitch;
}

float ViolinTracker::calculateSpectralFlatness(
    const std::array<float, kFrameSize>& frame) const noexcept
{
    std::array<float, kFrameSize> windowed{};
    applyHannWindow(frame, windowed);

    std::array<Complex, kFFTSize> spectrum{};
    for (std::size_t i = 0; i < kFFTSize; ++i) {
        spectrum[i] = Complex(windowed[i], 0.0f);
    }

    fft(spectrum);

    double log_sum = 0.0;
    double arithmetic_sum = 0.0;

    constexpr std::size_t bins = kFFTSize / 2;
    constexpr float epsilon = 1.0e-12f;

    for (std::size_t i = 1; i < bins; ++i) {
        const float power = magnitudeSquared(spectrum[i]);
        arithmetic_sum += static_cast<double>(power);
        log_sum += std::log(static_cast<double>(std::max(power, epsilon)));
    }

    if (arithmetic_sum <= 0.0) {
        return 1.0f;
    }

    const double arithmetic_mean = arithmetic_sum / static_cast<double>(bins - 1);
    const double geometric_mean = std::exp(log_sum / static_cast<double>(bins - 1));

    return static_cast<float>(geometric_mean / std::max(arithmetic_mean, 1.0e-12));
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
    for (std::size_t i = 0; i < kFFTSize; ++i) {
        spectrum[i] = Complex(windowed[i], 0.0f);
    }

    fft(spectrum);

    constexpr std::size_t half = kFFTSize / 2;
    double total_power = 0.0;
    double harmonic_power = 0.0;

    for (std::size_t i = 1; i < half; ++i) {
        const float power = magnitudeSquared(spectrum[i]);
        total_power += static_cast<double>(power);
    }

    if (total_power <= 1.0e-12) {
        return -100.0f;
    }

    for (int harmonic = 1; ; ++harmonic) {
        const float harmonic_hz = fundamental_hz * static_cast<float>(harmonic);
        if (harmonic_hz >= sample_rate_ * 0.5f) {
            break;
        }

        const float center = hzToBin(harmonic_hz, sample_rate_);
        const int center_bin = static_cast<int>(std::lround(center));
        const int radius = 2;

        float local_peak = 0.0f;
        for (int offset = -radius; offset <= radius; ++offset) {
            const int bin = center_bin + offset;
            if (bin <= 0 || bin >= static_cast<int>(half)) {
                continue;
            }
            local_peak = std::max(
                local_peak,
                magnitudeSquared(spectrum[static_cast<std::size_t>(bin)]));
        }

        harmonic_power += static_cast<double>(local_peak);
    }

    harmonic_power = std::min(harmonic_power, total_power);
    const double noise_power = std::max(total_power - harmonic_power, 1.0e-12);

    return static_cast<float>(10.0 * std::log10(harmonic_power / noise_power));
}

float ViolinTracker::calculateDynamicTolerance(
    float base_cents,
    float local_variance,
    float stretch) const noexcept
{
    return std::max(0.0f, base_cents + local_variance * stretch);
}

float ViolinTracker::estimateLocalPitchVariance() const noexcept
{
    if (pitch_history_size_ < 2) {
        return 0.0f;
    }

    double mean_log2 = 0.0;
    for (std::size_t i = 0; i < pitch_history_size_; ++i) {
        const float hz = pitch_history_[i];
        if (hz <= 0.0f) continue;
        mean_log2 += std::log2(static_cast<double>(hz));
    }
    mean_log2 /= static_cast<double>(pitch_history_size_);

    double variance = 0.0;
    for (std::size_t i = 0; i < pitch_history_size_; ++i) {
        const float hz = pitch_history_[i];
        if (hz <= 0.0f) continue;

        const double cents = 1200.0 * (std::log2(static_cast<double>(hz)) - mean_log2);
        variance += cents * cents;
    }
    variance /= static_cast<double>(pitch_history_size_);

    return static_cast<float>(variance);
}

void ViolinTracker::updatePitchHistory(float pitch_hz) noexcept
{
    if (pitch_hz <= 0.0f) {
        return;
    }

    pitch_history_[pitch_history_write_] = pitch_hz;
    pitch_history_write_ = (pitch_history_write_ + 1) % pitch_history_.size();
    pitch_history_size_ = std::min(pitch_history_size_ + 1, pitch_history_.size());
}

PitchResult ViolinTracker::processFrame(
    const std::array<float, kFrameSize>& frame) noexcept
{
    PitchResult result{};
    result.frequency_hz = 0.0f;
    result.confidence = 0.0f;
    result.is_scratching = 0;
    result.is_legato = 0;
    result.rms_energy = 0;
    result.reserved = 0;

    // 1. Calculate frame RMS energy
    double sum_sq = 0.0;
    for (float s : frame) {
        sum_sq += static_cast<double>(s) * static_cast<double>(s);
    }
    const float rms = static_cast<float>(std::sqrt(sum_sq / static_cast<double>(frame.size())));
    result.rms_energy = static_cast<std::uint8_t>(std::clamp(rms * 1000.0f, 0.0f, 255.0f));

    float confidence = 0.0f;
    const float pitch = calculateMPM(frame, confidence);

    result.frequency_hz = pitch;
    result.confidence = confidence;

    if (pitch <= 0.0f || confidence < 0.60f || rms < 0.009f) {
        last_stable_pitch_ = 0.0f;
        min_rms_transition_ = 0.0f;
        result.is_scratching = (rms > 0.015f) ? 1 : 0;
        return result;
    }

    // 2. Legato (Slur) Transition Detection:
    // Continuous tone without bow reversal/silence dip
    const int current_midi = static_cast<int>(std::lround(69.0 + 12.0 * std::log2(static_cast<double>(pitch) / 440.0)));

    if (last_stable_pitch_ > 0.0f) {
        const int prev_midi = static_cast<int>(std::lround(69.0 + 12.0 * std::log2(static_cast<double>(last_stable_pitch_) / 440.0)));

        if (current_midi != prev_midi) {
            // Note pitch shifted! Check if energy was continuous
            if (min_rms_transition_ > 0.005f && rms > 0.005f) {
                // Legato transition: continuous bow stroke across distinct pitches
                result.is_legato = 1;
            } else {
                // Detache: silence dip or bow change before new note
                result.is_legato = 0;
            }
            min_rms_transition_ = rms;
            last_stable_pitch_ = pitch;
        } else {
            // Sustaining current pitch
            min_rms_transition_ = std::min(min_rms_transition_, rms);
            last_stable_pitch_ = pitch;
            result.is_legato = 0;
        }
    } else {
        // Initial onset from silence
        last_stable_pitch_ = pitch;
        min_rms_transition_ = rms;
        result.is_legato = 0;
    }

    updatePitchHistory(pitch);

    const float spectral_flatness = calculateSpectralFlatness(frame);
    const float hnr_db = calculateHarmonicsToNoise(frame, pitch);

    const bool high_noise_floor = spectral_flatness > kScratchFlatnessThreshold;
    const bool weak_harmonic_structure = hnr_db < kScratchHnrThresholdDb;

    result.is_scratching = (high_noise_floor || weak_harmonic_structure) ? 1 : 0;

    return result;
}

} // namespace violin
