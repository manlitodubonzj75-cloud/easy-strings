#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <type_traits>

namespace violin {

/**
 * Lock-free Single-Producer / Single-Consumer ring buffer.
 *
 * Requirements:
 *   - exactly ONE producer thread
 *   - exactly ONE consumer thread
 *   - Capacity is fixed at compile time
 *
 * No dynamic allocation.
 * No mutex.
 * No condition variable.
 *
 * Memory model:
 *   producer publishes write_index_ with release
 *   consumer reads write_index_ with acquire
 *
 *   consumer publishes read_index_ with release
 *   producer reads read_index_ with acquire
 */
template <typename T, std::size_t Capacity>
class SpscRingBuffer final {
    static_assert(Capacity >= 2, "Capacity must be >= 2");
    static_assert(std::is_trivially_copyable_v<T>,
                  "SPSC buffer requires trivially copyable T");

public:
    SpscRingBuffer() noexcept = default;

    SpscRingBuffer(const SpscRingBuffer&) = delete;
    SpscRingBuffer& operator=(const SpscRingBuffer&) = delete;

    /**
     * Push one item.
     *
     * Returns false when the buffer is full.
     * This function NEVER blocks.
     */
    bool push(const T& value) noexcept {
        const std::size_t write =
            write_index_.load(std::memory_order_relaxed);

        const std::size_t next = increment(write);

        const std::size_t read =
            read_index_.load(std::memory_order_acquire);

        if (next == read) {
            return false; // full
        }

        buffer_[write] = value;

        write_index_.store(next, std::memory_order_release);
        return true;
    }

    /**
     * Push a contiguous range.
     *
     * Returns number of actually written samples.
     * Never blocks.
     */
    std::size_t push(const T* src, std::size_t count) noexcept {
        if (src == nullptr || count == 0) {
            return 0;
        }

        std::size_t pushed = 0;

        while (pushed < count) {
            const std::size_t write =
                write_index_.load(std::memory_order_relaxed);

            const std::size_t next = increment(write);

            const std::size_t read =
                read_index_.load(std::memory_order_acquire);

            if (next == read) {
                break; // full
            }

            buffer_[write] = src[pushed];

            write_index_.store(next, std::memory_order_release);

            ++pushed;
        }

        return pushed;
    }

    /**
     * Pull one item.
     *
     * Returns false when the buffer is empty.
     * This function NEVER blocks.
     */
    bool pull(T& value) noexcept {
        const std::size_t read =
            read_index_.load(std::memory_order_relaxed);

        const std::size_t write =
            write_index_.load(std::memory_order_acquire);

        if (read == write) {
            return false; // empty
        }

        value = buffer_[read];

        read_index_.store(
            increment(read),
            std::memory_order_release);

        return true;
    }

    /**
     * Pull up to count samples into dst.
     *
     * Returns actual number of samples copied.
     */
    std::size_t pull(T* dst, std::size_t count) noexcept {
        if (dst == nullptr || count == 0) {
            return 0;
        }

        std::size_t pulled = 0;

        while (pulled < count) {
            const std::size_t read =
                read_index_.load(std::memory_order_relaxed);

            const std::size_t write =
                write_index_.load(std::memory_order_acquire);

            if (read == write) {
                break; // empty
            }

            dst[pulled] = buffer_[read];

            read_index_.store(
                increment(read),
                std::memory_order_release);

            ++pulled;
        }

        return pulled;
    }

    bool empty() const noexcept {
        return available() == 0;
    }

    std::size_t available() const noexcept {
        const std::size_t write =
            write_index_.load(std::memory_order_acquire);

        const std::size_t read =
            read_index_.load(std::memory_order_acquire);

        if (write >= read) {
            return write - read;
        }

        return Capacity - read + write;
    }

    constexpr std::size_t capacity() const noexcept {
        return Capacity - 1;
    }

    void reset() noexcept {
        // Must be called only when producer/consumer are stopped.
        read_index_.store(0, std::memory_order_relaxed);
        write_index_.store(0, std::memory_order_relaxed);
    }

private:
    static constexpr std::size_t increment(std::size_t index) noexcept {
        ++index;
        if (index == Capacity) {
            index = 0;
        }
        return index;
    }

private:
    // One extra slot is intentionally used to distinguish full/empty.
    std::array<T, Capacity> buffer_{};

    // Separate cache lines are preferable in production to avoid
    // false sharing between producer and consumer.
    alignas(64) std::atomic<std::size_t> write_index_{0};

    alignas(64) std::atomic<std::size_t> read_index_{0};
};

} // namespace violin