#include "audio_processor.h"
#include "bowed_synth.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstring>
#include <limits>
#include <thread>
#include <vector>

namespace violin {

struct NoteEvent {
    float freq_hz{0.0f};
    float duration_sec{0.0f};
    bool is_legato{false};
};

#if defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>

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

class AppleAudioPlayer {
public:
    static AppleAudioPlayer& instance() {
        static AppleAudioPlayer s_instance;
        return s_instance;
    }

    AppleAudioPlayer() {
        AudioStreamBasicDescription format{};
        format.mSampleRate = 44100.0f;
        format.mFormatID = kAudioFormatLinearPCM;
        format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        format.mBytesPerPacket = sizeof(float);
        format.mFramesPerPacket = 1;
        format.mBytesPerFrame = sizeof(float);
        format.mChannelsPerFrame = 1;
        format.mBitsPerChannel = 32;

        OSStatus st = AudioQueueNewOutput(
            &format,
            audioOutputCallback,
            this,
            nullptr,
            nullptr,
            0,
            &queue_);

        if (st == noErr && queue_) {
            const UInt32 bufSize = kBufferSampleCount * sizeof(float);
            for (int i = 0; i < kNumBuffers; ++i) {
                st = AudioQueueAllocateBuffer(queue_, bufSize, &buffers_[i]);
                if (st == noErr && buffers_[i]) {
                    std::memset(buffers_[i]->mAudioData, 0, bufSize);
                    buffers_[i]->mAudioDataByteSize = bufSize;
                    AudioQueueEnqueueBuffer(queue_, buffers_[i], 0, nullptr);
                }
            }
            AudioQueueStart(queue_, nullptr);
        }
    }

    ~AppleAudioPlayer() {
        if (queue_) {
            AudioQueueStop(queue_, true);
            AudioQueueDispose(queue_, true);
            queue_ = nullptr;
        }
    }

    bool isPlaying() const noexcept {
        return is_playing_.load(std::memory_order_relaxed);
    }

    void stop() {
        pending_stop_.store(true, std::memory_order_release);
        NoteEvent discard;
        while (note_queue_.pull(discard)) {}
        is_playing_.store(false, std::memory_order_release);
    }

    void play(float freq_hz, float duration_sec, bool is_legato = false) {
        if (freq_hz <= 0.0f || duration_sec <= 0.0f) {
            stop();
            return;
        }

        const NoteEvent ev{freq_hz, duration_sec, is_legato};
        // DRAIN any previous notes so the new note plays IMMEDIATELY without queue delay/backlog!
        NoteEvent discard;
        while (note_queue_.pull(discard)) {}
        note_queue_.push(ev);
        pending_stop_.store(false, std::memory_order_release);
        is_playing_.store(true, std::memory_order_release);

        if (queue_) {
            AudioQueueStart(queue_, nullptr);
        }
    }

    void fillBuffer(AudioQueueBufferRef buffer) {
        float* out = static_cast<float*>(buffer->mAudioData);
        const UInt32 count = buffer->mAudioDataBytesCapacity / sizeof(float);

        if (pending_stop_.load(std::memory_order_acquire)) {
            synth_.noteOff();
            is_playing_.store(false, std::memory_order_release);
            std::memset(out, 0, buffer->mAudioDataBytesCapacity);
            buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
            if (queue_) AudioQueueEnqueueBuffer(queue_, buffer, 0, nullptr);
            return;
        }

        if (!is_playing_.load(std::memory_order_acquire)) {
            std::memset(out, 0, buffer->mAudioDataBytesCapacity);
            buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
            if (queue_) AudioQueueEnqueueBuffer(queue_, buffer, 0, nullptr);
            return;
        }

        UInt32 generated = 0;
        while (generated < count) {
            NoteEvent next_note;
            if (note_queue_.pull(next_note)) {
                // Instantly transition to the newly requested note!
                const bool use_vibrato = (next_note.duration_sec >= 0.16f);
                synth_.noteOn(next_note.freq_hz, next_note.duration_sec, use_vibrato, next_note.is_legato);
                is_playing_.store(true, std::memory_order_release);
            } else if (!synth_.isActive()) {
                is_playing_.store(false, std::memory_order_release);
                std::memset(out + generated, 0, (count - generated) * sizeof(float));
                break;
            }

            while (generated < count && synth_.isActive()) {
                out[generated++] = synth_.tick();
                if (!note_queue_.empty()) {
                    break; // Switch to the newly requested note without waiting!
                }
            }
        }

        buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
        if (queue_) AudioQueueEnqueueBuffer(queue_, buffer, 0, nullptr);
    }

private:
    static void audioOutputCallback(void* userData, AudioQueueRef, AudioQueueBufferRef buffer) {
        auto* player = static_cast<AppleAudioPlayer*>(userData);
        if (player) {
            player->fillBuffer(buffer);
        }
    }

    AudioQueueRef queue_{nullptr};
    static constexpr int kNumBuffers = 3;
    static constexpr UInt32 kBufferSampleCount = 1024;
    AudioQueueBufferRef buffers_[kNumBuffers]{};
    SpscRingBuffer<NoteEvent, 128> note_queue_;
    std::atomic<bool> is_playing_{false};
    std::atomic<bool> pending_stop_{false};
    BowedViolinModel synth_{44100.0f};
};

bool isAudioTonePlaying() noexcept {
    return AppleAudioPlayer::instance().isPlaying();
}

void playAudioTone(float freq_hz, float duration_sec, bool is_legato) noexcept {
    AppleAudioPlayer::instance().play(freq_hz, duration_sec, is_legato);
}

void stopAudioTone() noexcept {
    AppleAudioPlayer::instance().stop();
}

#elif defined(__ANDROID__)
#include <aaudio/AAudio.h>

struct AndroidAudioCapture {
    AAudioStream* stream{nullptr};
    ViolinTracker* tracker{nullptr};
    std::atomic<bool> is_recording{false};
    bool is_float_format{true};
    std::vector<float> conversion_buffer;

    AndroidAudioCapture() : conversion_buffer(4096, 0.0f) {}
};

static aaudio_data_callback_result_t androidAudioInputCallback(
    AAudioStream* /*stream*/,
    void* userData,
    void* audioData,
    int32_t numFrames)
{
    auto* capture = static_cast<AndroidAudioCapture*>(userData);
    if (!capture || !capture->is_recording.load(std::memory_order_acquire)) {
        return AAUDIO_CALLBACK_RESULT_CONTINUE;
    }

    if (numFrames <= 0 || !capture->tracker || !audioData) {
        return AAUDIO_CALLBACK_RESULT_CONTINUE;
    }

    if (capture->is_float_format) {
        const float* samples = static_cast<const float*>(audioData);
        capture->tracker->pushSamples(samples, static_cast<std::size_t>(numFrames));
    } else {
        const int16_t* pcm16 = static_cast<const int16_t*>(audioData);
        const int32_t frames_to_copy = std::min(numFrames, static_cast<int32_t>(capture->conversion_buffer.size()));
        constexpr float kNorm = 1.0f / 32768.0f;
        for (int32_t i = 0; i < frames_to_copy; ++i) {
            capture->conversion_buffer[i] = static_cast<float>(pcm16[i]) * kNorm;
        }
        capture->tracker->pushSamples(capture->conversion_buffer.data(), static_cast<std::size_t>(frames_to_copy));
    }

    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

class AndroidAudioPlayer {
public:
    static AndroidAudioPlayer& instance() {
        static AndroidAudioPlayer s_instance;
        return s_instance;
    }

    AndroidAudioPlayer() {
        initStream();
    }

    ~AndroidAudioPlayer() {
        closeStream();
    }

    bool isPlaying() const noexcept {
        return is_playing_.load(std::memory_order_relaxed);
    }

    void stop() {
        pending_stop_.store(true, std::memory_order_release);
        NoteEvent discard;
        while (note_queue_.pull(discard)) {}
        is_playing_.store(false, std::memory_order_release);
    }

    void play(float freq_hz, float duration_sec, bool is_legato = false) {
        if (freq_hz <= 0.0f || duration_sec <= 0.0f) {
            stop();
            return;
        }
        if (!stream_) {
            initStream();
        }

        const NoteEvent ev{freq_hz, duration_sec, is_legato};
        // DRAIN any previous notes so the new note plays IMMEDIATELY without queue delay/backlog!
        NoteEvent discard;
        while (note_queue_.pull(discard)) {}
        note_queue_.push(ev);
        pending_stop_.store(false, std::memory_order_release);
        is_playing_.store(true, std::memory_order_release);

        if (stream_) {
            aaudio_stream_state_t state = AAudioStream_getState(stream_);
            if (state == AAUDIO_STREAM_STATE_PAUSED || state == AAUDIO_STREAM_STATE_STOPPED) {
                AAudioStream_requestStart(stream_);
            }
        }
    }

    void fillBuffer(float* out, int32_t numFrames) {
        if (pending_stop_.load(std::memory_order_acquire)) {
            synth_.noteOff();
            is_playing_.store(false, std::memory_order_release);
            std::memset(out, 0, numFrames * sizeof(float));
            return;
        }

        if (!is_playing_.load(std::memory_order_acquire)) {
            std::memset(out, 0, numFrames * sizeof(float));
            return;
        }

        int32_t generated = 0;
        while (generated < numFrames) {
            NoteEvent next_note;
            if (note_queue_.pull(next_note)) {
                // Instantly switch to the new note!
                const bool use_vibrato = (next_note.duration_sec >= 0.16f);
                synth_.noteOn(next_note.freq_hz, next_note.duration_sec, use_vibrato, next_note.is_legato);
                is_playing_.store(true, std::memory_order_release);
            } else if (!synth_.isActive()) {
                is_playing_.store(false, std::memory_order_release);
                std::memset(out + generated, 0, (numFrames - generated) * sizeof(float));
                break;
            }

            while (generated < numFrames && synth_.isActive()) {
                out[generated++] = synth_.tick();
                if (!note_queue_.empty()) {
                    break; // Switch to the newly requested note without waiting!
                }
            }
        }
    }

    void fillBufferI16(int16_t* out, int32_t numFrames) {
        if (float_buf_.size() < static_cast<std::size_t>(numFrames)) {
            float_buf_.resize(numFrames);
        }
        fillBuffer(float_buf_.data(), numFrames);
        for (int32_t i = 0; i < numFrames; ++i) {
            float s = std::clamp(float_buf_[i], -1.0f, 1.0f);
            out[i] = static_cast<int16_t>(s * 32767.0f);
        }
    }

    bool isFloatFormat() const { return is_float_format_; }

private:
    void initStream() {
        AAudioStreamBuilder* builder = nullptr;
        aaudio_result_t result = AAudio_createStreamBuilder(&builder);
        if (result != AAUDIO_OK || !builder) {
            return;
        }

        AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_OUTPUT);
        AAudioStreamBuilder_setSampleRate(builder, 44100);
        AAudioStreamBuilder_setChannelCount(builder, 1);
        AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
        AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
        AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
        AAudioStreamBuilder_setDataCallback(builder, androidAudioOutputCallback, this);

        result = AAudioStreamBuilder_openStream(builder, &stream_);
        if (result != AAUDIO_OK || !stream_) {
            AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_I16);
            result = AAudioStreamBuilder_openStream(builder, &stream_);
        }
        AAudioStreamBuilder_delete(builder);

        if (result == AAUDIO_OK && stream_) {
            aaudio_format_t fmt = AAudioStream_getFormat(stream_);
            is_float_format_ = (fmt == AAUDIO_FORMAT_PCM_FLOAT);
            AAudioStream_requestStart(stream_);
        }
    }

    void closeStream() {
        if (stream_) {
            AAudioStream_requestStop(stream_);
            AAudioStream_close(stream_);
            stream_ = nullptr;
        }
    }

    static aaudio_data_callback_result_t androidAudioOutputCallback(
        AAudioStream* /*stream*/,
        void* userData,
        void* audioData,
        int32_t numFrames)
    {
        auto* player = static_cast<AndroidAudioPlayer*>(userData);
        if (player) {
            if (player->isFloatFormat()) {
                player->fillBuffer(static_cast<float*>(audioData), numFrames);
            } else {
                player->fillBufferI16(static_cast<int16_t*>(audioData), numFrames);
            }
        }
        return AAUDIO_CALLBACK_RESULT_CONTINUE;
    }

    AAudioStream* stream_{nullptr};
    SpscRingBuffer<NoteEvent, 128> note_queue_;
    std::atomic<bool> is_playing_{false};
    std::atomic<bool> pending_stop_{false};
    BowedViolinModel synth_{44100.0f};
    bool is_float_format_{true};
    std::vector<float> float_buf_;
};

bool isAudioTonePlaying() noexcept {
    return AndroidAudioPlayer::instance().isPlaying();
}

void playAudioTone(float freq_hz, float duration_sec, bool is_legato) noexcept {
    AndroidAudioPlayer::instance().play(freq_hz, duration_sec, is_legato);
}

void stopAudioTone() noexcept {
    AndroidAudioPlayer::instance().stop();
}

#else

void playAudioTone(float /*freq_hz*/, float /*duration_sec*/, bool /*is_legato*/) noexcept {}
bool isAudioTonePlaying() noexcept { return false; }
void stopAudioTone() noexcept {}

#endif

namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr float kTwoPi = 2.0f * kPi;

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
            for (std::size_t j = 0; j < len / 2; ++j) {
                const Complex u = data[i + j];
                const Complex v = data[i + j + len / 2] * w;
                data[i + j] = u + v;
                data[i + j + len / 2] = u - v;
                w *= wlen;
            }
        }
    }
}

inline float magnitudeSquared(const Complex& c) noexcept
{
    return c.real() * c.real() + c.imag() * c.imag();
}

inline float hzToBin(float hz, std::size_t sample_rate) noexcept
{
    return hz * static_cast<float>(kFFTSize) / static_cast<float>(sample_rate);
}

} // namespace

ViolinTracker::ViolinTracker(std::size_t sample_rate)
    : sample_rate_(sample_rate)
{
}

ViolinTracker::~ViolinTracker()
{
    stop();
}

void ViolinTracker::start()
{
    if (running_.exchange(true, std::memory_order_acq_rel)) {
        return;
    }

    worker_thread_ = std::thread(&ViolinTracker::workerLoop, this);
}

void ViolinTracker::stop()
{
    stopMic();

    if (!running_.exchange(false, std::memory_order_acq_rel)) {
        return;
    }

    if (worker_thread_.joinable()) {
        worker_thread_.join();
    }
}

bool ViolinTracker::isRunning() const noexcept
{
    return running_.load(std::memory_order_relaxed);
}

bool ViolinTracker::startMic()
{
    if (mic_active_.load(std::memory_order_relaxed)) {
        return true;
    }

#if defined(__APPLE__)
    auto* capture = new AppleAudioCapture();
    capture->tracker = this;
    capture->is_recording.store(true, std::memory_order_release);

    AudioStreamBasicDescription format{};
    format.mSampleRate = static_cast<Float64>(sample_rate_);
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = sizeof(float);
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(float);
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 32;

    OSStatus st = AudioQueueNewInput(
        &format,
        appleAudioQueueCallback,
        capture,
        nullptr,
        nullptr,
        0,
        &capture->queue);

    if (st != noErr || !capture->queue) {
        delete capture;
        return false;
    }

    const UInt32 bufSize = AppleAudioCapture::kBufferSampleCount * sizeof(float);
    for (int i = 0; i < AppleAudioCapture::kNumBuffers; ++i) {
        st = AudioQueueAllocateBuffer(capture->queue, bufSize, &capture->buffers[i]);
        if (st == noErr && capture->buffers[i]) {
            AudioQueueEnqueueBuffer(capture->queue, capture->buffers[i], 0, nullptr);
        }
    }

    st = AudioQueueStart(capture->queue, nullptr);
    if (st != noErr) {
        AudioQueueDispose(capture->queue, true);
        delete capture;
        return false;
    }

    platform_mic_handle_ = capture;
    mic_active_.store(true, std::memory_order_release);
    return true;

#elif defined(__ANDROID__)
    auto* capture = new AndroidAudioCapture();
    capture->tracker = this;
    capture->is_recording.store(true, std::memory_order_release);

    AAudioStreamBuilder* builder = nullptr;
    aaudio_result_t result = AAudio_createStreamBuilder(&builder);
    if (result != AAUDIO_OK || !builder) {
        delete capture;
        return false;
    }

    AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_INPUT);
    AAudioStreamBuilder_setSampleRate(builder, static_cast<int32_t>(sample_rate_));
    AAudioStreamBuilder_setChannelCount(builder, 1);
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
    AAudioStreamBuilder_setDataCallback(builder, androidAudioInputCallback, capture);

    result = AAudioStreamBuilder_openStream(builder, &capture->stream);
    if (result != AAUDIO_OK || !capture->stream) {
        AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_I16);
        result = AAudioStreamBuilder_openStream(builder, &capture->stream);
    }
    AAudioStreamBuilder_delete(builder);

    if (result != AAUDIO_OK || !capture->stream) {
        delete capture;
        return false;
    }

    aaudio_format_t fmt = AAudioStream_getFormat(capture->stream);
    capture->is_float_format = (fmt == AAUDIO_FORMAT_PCM_FLOAT);

    result = AAudioStream_requestStart(capture->stream);
    if (result != AAUDIO_OK) {
        AAudioStream_close(capture->stream);
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

void ViolinTracker::stopMic()
{
    if (!mic_active_.exchange(false, std::memory_order_acq_rel)) {
        return;
    }

#if defined(__APPLE__)
    if (platform_mic_handle_) {
        auto* capture = static_cast<AppleAudioCapture*>(platform_mic_handle_);
        capture->is_recording.store(false, std::memory_order_release);
        if (capture->queue) {
            AudioQueueStop(capture->queue, true);
            AudioQueueDispose(capture->queue, true);
        }
        delete capture;
        platform_mic_handle_ = nullptr;
    }
#elif defined(__ANDROID__)
    if (platform_mic_handle_) {
        auto* capture = static_cast<AndroidAudioCapture*>(platform_mic_handle_);
        capture->is_recording.store(false, std::memory_order_release);
        if (capture->stream) {
            AAudioStream_requestStop(capture->stream);
            AAudioStream_close(capture->stream);
        }
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
    float& confidence,
    const std::array<Complex, kFFTSize>& spectrum) const noexcept
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

    struct MpmPeak {
        float lag;
        float nsdf;
        float pitch;
    };
    std::vector<MpmPeak> peaks;
    float max_peak_nsdf = 0.0f;

    // Find all local maxima over low threshold to avoid dropping weak fundamentals
    for (std::size_t lag = min_lag + 1; lag + 1 <= max_lag; ++lag) {
        const float prev = nsdf[lag - 1];
        const float current = nsdf[lag];
        const float next = nsdf[lag + 1];

        if (current < 0.22f) {
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
        if (current > max_peak_nsdf) {
            max_peak_nsdf = current;
        }
    }

    if (peaks.empty() || max_peak_nsdf < 0.35f) {
        return 0.0f;
    }

    // Standard McLeod Pitch Method (MPM):
    // Pick the first peak exceeding (0.72 * max_peak_nsdf).
    constexpr float kCutoffCoeff = 0.72f;
    const float cutoff = max_peak_nsdf * kCutoffCoeff;

    MpmPeak chosen = peaks.front();
    for (const auto& p : peaks) {
        if (p.nsdf >= cutoff) {
            chosen = p;
            break;
        }
    }

    // Helper lambda to measure spectral power around a target frequency
    auto getSpectralPower = [&](float freq_hz) -> float {
        if (freq_hz <= 0.0f || freq_hz >= sample_rate_ * 0.5f) return 0.0f;
        const float center = hzToBin(freq_hz, sample_rate_);
        const int center_bin = static_cast<int>(std::lround(center));
        float peak_power = 0.0f;
        for (int offset = -2; offset <= 2; ++offset) {
            const int b = center_bin + offset;
            if (b >= 1 && b < static_cast<int>(kFFTSize / 2)) {
                peak_power = std::max(peak_power, magnitudeSquared(spectrum[static_cast<std::size_t>(b)]));
            }
        }
        return peak_power;
    };

    const float chosen_power = getSpectralPower(chosen.pitch);

    // Violin Octave-Up and Overtone Elimination:
    // Only apply when the candidate pitch might be an overtone of the lowest open strings (G3 ~196Hz, D4 ~293Hz).
    // For higher pitches, do NOT erroneously force downward into violin body resonances (280Hz / 470Hz).
    for (int harmonic_ratio = 2; harmonic_ratio <= 3; ++harmonic_ratio) {
        const float target_sub_lag = chosen.lag * static_cast<float>(harmonic_ratio);
        const float sub_freq = sample_rate_ / target_sub_lag;
        if (sub_freq < kMinPitchHz || sub_freq > 330.0f) {
            continue;
        }

        // Search for a candidate peak in the vicinity of target_sub_lag
        for (const auto& p : peaks) {
            const float ratio = p.lag / chosen.lag;
            const float diff = std::fabs(ratio - static_cast<float>(harmonic_ratio));
            if (diff <= 0.10f) { // Within 10% of exact subharmonic ratio
                const float sub_power = getSpectralPower(p.pitch);
                const float odd3_power = (harmonic_ratio == 2) ? getSpectralPower(p.pitch * 3.0f) : 0.0f;

                // Subharmonic is the true fundamental ONLY if there is actual acoustic/spectral energy
                // at the odd harmonic frequencies (f_sub or 3*f_sub).
                const bool has_odd_energy = (chosen_power > 0.0f) &&
                    ((sub_power >= 0.08f * chosen_power) || (odd3_power >= 0.08f * chosen_power));

                if (p.nsdf >= 0.60f * chosen.nsdf && has_odd_energy) {
                    chosen = p;
                    break;
                }
            }
        }
    }

    confidence = std::clamp(chosen.nsdf, 0.0f, 1.0f);
    return chosen.pitch;
}

float ViolinTracker::calculateSpectralFlatness(
    const std::array<Complex, kFFTSize>& spectrum) const noexcept
{
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
    const std::array<Complex, kFFTSize>& spectrum,
    float fundamental_hz) const noexcept
{
    if (fundamental_hz <= 0.0f) {
        return -100.0f;
    }

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

    // 1. Remove DC offset (clean microphone bias)
    std::array<float, kFrameSize> clean_frame{};
    float sum = 0.0f;
    for (float s : frame) {
        sum += s;
    }
    const float dc_offset = sum / static_cast<float>(kFrameSize);
    for (std::size_t i = 0; i < kFrameSize; ++i) {
        clean_frame[i] = frame[i] - dc_offset;
    }

    // 2. Calculate frame RMS energy on clean signal
    double sum_sq = 0.0;
    for (float s : clean_frame) {
        sum_sq += static_cast<double>(s) * static_cast<double>(s);
    }
    const float rms = static_cast<float>(std::sqrt(sum_sq / static_cast<double>(kFrameSize)));
    result.rms_energy = static_cast<std::uint8_t>(std::clamp(rms * 1000.0f, 0.0f, 255.0f));

    // Zero out immediately on silence or ambient noise floor (< 1.2 mV)
    if (rms < 0.0012f) {
        last_stable_pitch_ = 0.0f;
        min_rms_transition_ = 0.0f;
        result.frequency_hz = 0.0f;
        result.confidence = 0.0f;
        result.is_scratching = 0;
        return result;
    }

    // 3. Compute single FFT for spectral analysis and harmonic validation
    std::array<float, kFrameSize> windowed{};
    applyHannWindow(clean_frame, windowed);

    std::array<Complex, kFFTSize> spectrum{};
    for (std::size_t i = 0; i < kFFTSize; ++i) {
        spectrum[i] = Complex(windowed[i], 0.0f);
    }
    fft(spectrum);

    // 4. Calculate MPM with spectral subharmonic validation
    float confidence = 0.0f;
    const float pitch = calculateMPM(clean_frame, confidence, spectrum);

    // If pitch cannot be reliably determined: return zeroed result
    if (pitch <= 0.0f || confidence < 0.35f) {
        last_stable_pitch_ = 0.0f;
        min_rms_transition_ = 0.0f;
        result.frequency_hz = 0.0f;
        result.confidence = 0.0f;
        result.is_scratching = 0;
        return result;
    }

    result.frequency_hz = pitch;
    result.confidence = confidence;

    // 5. Legato (Slur) Transition Detection:
    // Continuous tone without bow reversal/silence dip
    const int current_midi = static_cast<int>(std::lround(69.0 + 12.0 * std::log2(static_cast<double>(pitch) / 440.0)));

    if (last_stable_pitch_ > 0.0f) {
        const int prev_midi = static_cast<int>(std::lround(69.0 + 12.0 * std::log2(static_cast<double>(last_stable_pitch_) / 440.0)));

        if (current_midi != prev_midi) {
            // Note pitch shifted! Check if energy was continuous
            if (min_rms_transition_ > 0.004f && rms > 0.004f) {
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

    const float spectral_flatness = calculateSpectralFlatness(spectrum);
    const float hnr_db = calculateHarmonicsToNoise(spectrum, pitch);

    const bool high_noise_floor = spectral_flatness > 0.45f;
    const bool weak_harmonic_structure = hnr_db < 3.0f;

    // True scratch only when acoustic energy is loud (rms > 0.025f)
    // with degraded harmonic periodicity (confidence < 0.55f)
    result.is_scratching = (rms > 0.025f && confidence < 0.55f && high_noise_floor && weak_harmonic_structure) ? 1 : 0;

    return result;
}

} // namespace violin
