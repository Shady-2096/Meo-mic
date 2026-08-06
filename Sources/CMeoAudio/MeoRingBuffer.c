#include "MeoRingBuffer.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct MeoRingBuffer {
    float *samples;
    uint32_t capacity;
    uint32_t target_fill;
    _Atomic uint64_t write_index;
    _Atomic uint64_t read_index;
    _Atomic uint64_t underruns;
    _Atomic uint64_t overruns;
    _Atomic double ratio;
    double fractional_read;
    bool primed;
};

static uint32_t available_for(uint64_t write_index, uint64_t read_index) {
    uint64_t difference = write_index - read_index;
    return difference > UINT32_MAX ? UINT32_MAX : (uint32_t)difference;
}

MeoRingBuffer *meo_ring_create(uint32_t capacity, uint32_t target_fill) {
    if (capacity < 4 || target_fill >= capacity) {
        return NULL;
    }

    MeoRingBuffer *ring = calloc(1, sizeof(MeoRingBuffer));
    if (!ring) {
        return NULL;
    }

    ring->samples = calloc(capacity, sizeof(float));
    if (!ring->samples) {
        free(ring);
        return NULL;
    }

    ring->capacity = capacity;
    ring->target_fill = target_fill;
    atomic_init(&ring->write_index, 0);
    atomic_init(&ring->read_index, 0);
    atomic_init(&ring->underruns, 0);
    atomic_init(&ring->overruns, 0);
    atomic_init(&ring->ratio, 1.0);
    return ring;
}

void meo_ring_destroy(MeoRingBuffer *ring) {
    if (!ring) {
        return;
    }
    free(ring->samples);
    free(ring);
}

void meo_ring_clear(MeoRingBuffer *ring) {
    if (!ring) {
        return;
    }
    uint64_t write_index = atomic_load_explicit(&ring->write_index, memory_order_acquire);
    atomic_store_explicit(&ring->read_index, write_index, memory_order_release);
    ring->fractional_read = 0.0;
    ring->primed = false;
    atomic_store_explicit(&ring->ratio, 1.0, memory_order_relaxed);
}

uint32_t meo_ring_write_pcm16le(
    MeoRingBuffer *ring,
    const uint8_t *bytes,
    uint32_t byte_count,
    float gain
) {
    if (!ring || !bytes || byte_count < 2) {
        return 0;
    }

    uint32_t frame_count = byte_count / 2;
    uint64_t write_index = atomic_load_explicit(&ring->write_index, memory_order_relaxed);
    uint64_t read_index = atomic_load_explicit(&ring->read_index, memory_order_acquire);
    uint32_t free_space = ring->capacity - available_for(write_index, read_index);

    if (frame_count > free_space) {
        uint32_t dropped = frame_count - free_space;
        atomic_fetch_add_explicit(&ring->overruns, dropped, memory_order_relaxed);
        bytes += (size_t)dropped * 2;
        frame_count = free_space;
    }

    for (uint32_t index = 0; index < frame_count; index++) {
        uint16_t raw = (uint16_t)bytes[index * 2] |
                       ((uint16_t)bytes[index * 2 + 1] << 8);
        int16_t sample = (int16_t)raw;
        float value = ((float)sample / 32768.0f) * gain;
        ring->samples[write_index % ring->capacity] = fmaxf(-1.0f, fminf(1.0f, value));
        write_index++;
    }

    atomic_store_explicit(&ring->write_index, write_index, memory_order_release);
    return frame_count;
}

uint32_t meo_ring_render(MeoRingBuffer *ring, float *output, uint32_t frames) {
    if (!ring || !output || frames == 0) {
        return 0;
    }

    memset(output, 0, (size_t)frames * sizeof(float));

    uint64_t read_index = atomic_load_explicit(&ring->read_index, memory_order_relaxed);
    uint64_t write_index = atomic_load_explicit(&ring->write_index, memory_order_acquire);
    uint32_t available = available_for(write_index, read_index);

    if (!ring->primed) {
        if (available < ring->target_fill) {
            return 0;
        }
        ring->primed = true;
    }

    // A proportional controller bounded to +/- 1500 ppm. At the expected
    // tens-of-ppm clock error it converges gently; larger temporary corrections
    // recover from network jitter without a discontinuous sample drop.
    double fill_error = ((double)available - (double)ring->target_fill) /
                        (double)ring->target_fill;
    double desired_ratio = 1.0 + fmax(-0.0015, fmin(0.0015, fill_error * 0.00075));
    double previous_ratio = atomic_load_explicit(&ring->ratio, memory_order_relaxed);
    double ratio = previous_ratio + (desired_ratio - previous_ratio) * 0.002;
    atomic_store_explicit(&ring->ratio, ratio, memory_order_relaxed);

    uint32_t produced = 0;
    double cursor = ring->fractional_read;

    for (; produced < frames; produced++) {
        uint32_t whole = (uint32_t)cursor;
        if (whole + 1 >= available) {
            break;
        }

        double fraction = cursor - (double)whole;
        float first = ring->samples[(read_index + whole) % ring->capacity];
        float second = ring->samples[(read_index + whole + 1) % ring->capacity];
        output[produced] = first + (second - first) * (float)fraction;
        cursor += ratio;
    }

    uint64_t consumed = (uint64_t)cursor;
    ring->fractional_read = cursor - (double)consumed;
    atomic_store_explicit(&ring->read_index, read_index + consumed, memory_order_release);

    if (produced < frames) {
        atomic_fetch_add_explicit(&ring->underruns, 1, memory_order_relaxed);
        ring->primed = false;
        ring->fractional_read = 0.0;
    }

    return produced;
}

uint32_t meo_ring_available(const MeoRingBuffer *ring) {
    if (!ring) {
        return 0;
    }
    uint64_t write_index = atomic_load_explicit(&ring->write_index, memory_order_acquire);
    uint64_t read_index = atomic_load_explicit(&ring->read_index, memory_order_acquire);
    return available_for(write_index, read_index);
}

uint32_t meo_ring_target_fill(const MeoRingBuffer *ring) {
    return ring ? ring->target_fill : 0;
}

double meo_ring_current_ratio(const MeoRingBuffer *ring) {
    return ring ? atomic_load_explicit(&ring->ratio, memory_order_relaxed) : 1.0;
}

uint64_t meo_ring_underruns(const MeoRingBuffer *ring) {
    return ring ? atomic_load_explicit(&ring->underruns, memory_order_relaxed) : 0;
}

uint64_t meo_ring_overruns(const MeoRingBuffer *ring) {
    return ring ? atomic_load_explicit(&ring->overruns, memory_order_relaxed) : 0;
}
