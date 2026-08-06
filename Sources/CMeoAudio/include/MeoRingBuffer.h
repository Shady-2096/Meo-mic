#ifndef MEO_RING_BUFFER_H
#define MEO_RING_BUFFER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct MeoRingBuffer MeoRingBuffer;

MeoRingBuffer *meo_ring_create(uint32_t capacity, uint32_t target_fill);
void meo_ring_destroy(MeoRingBuffer *ring);
void meo_ring_clear(MeoRingBuffer *ring);

// Converts signed 16-bit little-endian PCM to float while writing.
uint32_t meo_ring_write_pcm16le(
    MeoRingBuffer *ring,
    const uint8_t *bytes,
    uint32_t byte_count,
    float gain
);

// Pulls float audio using linear interpolation. The read ratio is adjusted
// continuously around 1.0 to keep the jitter buffer near target fill.
uint32_t meo_ring_render(MeoRingBuffer *ring, float *output, uint32_t frames);

uint32_t meo_ring_available(const MeoRingBuffer *ring);
uint32_t meo_ring_target_fill(const MeoRingBuffer *ring);
double meo_ring_current_ratio(const MeoRingBuffer *ring);
uint64_t meo_ring_underruns(const MeoRingBuffer *ring);
uint64_t meo_ring_overruns(const MeoRingBuffer *ring);

#endif
