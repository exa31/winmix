#include "RTMixer.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>

struct RTContext {
  /* control -> audio */
  _Atomic float gain[RT_MAX_SLOTS];
  _Atomic bool mute[RT_MAX_SLOTS];
  _Atomic float masterGain;
  _Atomic bool masterMute;
  _Atomic float preampGain;
  /* audio -> control */
  _Atomic float peakL[RT_MAX_SLOTS];
  _Atomic float peakR[RT_MAX_SLOTS];
  _Atomic uint64_t cycleCount;
  _Atomic uint32_t lastFrameCount;
  /* routing (control thread writes while IOProc stopped) */
  int32_t tapCount;
  int32_t bufferIndex[RT_MAX_SLOTS];
  int32_t outBufferIndex[RT_MAX_SLOTS];
  int32_t channelOffset[RT_MAX_SLOTS];
  int32_t channels[RT_MAX_SLOTS];
};

/* Studio soft-saturation limiter:
 * - Linear & 100% bit-accurate for samples |x| <= 0.80 (zero coloration / zero distortion).
 * - Smooth hyperbolic tangent compression (tanh) for peaks > 0.80.
 * - Prevents harsh digital clipping/crackling even when audio is boosted to 200%. */
static inline float rt_saturate(float x) {
  const float threshold = 0.80f;
  if (x > threshold) {
    float excess = x - threshold;
    return threshold + (1.0f - threshold) * tanhf(excess / (1.0f - threshold));
  } else if (x < -threshold) {
    float excess = -x - threshold;
    return -threshold - (1.0f - threshold) * tanhf(excess / (1.0f - threshold));
  }
  return x;
}

static void rt_init(RTContext *ctx) {
  for (int i = 0; i < RT_MAX_SLOTS; i++) {
    atomic_store_explicit(&ctx->gain[i], 1.0f, memory_order_relaxed);
    atomic_store_explicit(&ctx->mute[i], false, memory_order_relaxed);
    atomic_store_explicit(&ctx->peakL[i], 0.0f, memory_order_relaxed);
    atomic_store_explicit(&ctx->peakR[i], 0.0f, memory_order_relaxed);
    ctx->bufferIndex[i] = -1;
    ctx->outBufferIndex[i] = 0;
    ctx->channelOffset[i] = 0;
    ctx->channels[i] = 0;
  }
  ctx->tapCount = 0;
  atomic_store_explicit(&ctx->masterGain, 1.0f, memory_order_relaxed);
  atomic_store_explicit(&ctx->masterMute, false, memory_order_relaxed);
  atomic_store_explicit(&ctx->preampGain, 1.0f, memory_order_relaxed);
  atomic_store_explicit(&ctx->cycleCount, 0, memory_order_relaxed);
  atomic_store_explicit(&ctx->lastFrameCount, 0, memory_order_relaxed);
}

RTContext *rt_context_create(void) {
  RTContext *ctx = (RTContext *)calloc(1, sizeof(RTContext));
  if (ctx)
    rt_init(ctx);
  return ctx;
}

void rt_context_destroy(RTContext *ctx) { free(ctx); }

static inline int rt_slot_ok(int slot) {
  return slot >= 0 && slot < RT_MAX_SLOTS;
}

void rt_set_gain(RTContext *ctx, int slot, float gain) {
  if (ctx && rt_slot_ok(slot)) {
    atomic_store_explicit(&ctx->gain[slot], gain, memory_order_relaxed);
  }
}

void rt_set_mute(RTContext *ctx, int slot, bool mute) {
  if (ctx && rt_slot_ok(slot)) {
    atomic_store_explicit(&ctx->mute[slot], mute, memory_order_relaxed);
  }
}

void rt_set_master_gain(RTContext *ctx, float gain) {
  if (ctx) {
    atomic_store_explicit(&ctx->masterGain, gain, memory_order_relaxed);
  }
}

void rt_set_master_mute(RTContext *ctx, bool mute) {
  if (ctx) {
    atomic_store_explicit(&ctx->masterMute, mute, memory_order_relaxed);
  }
}

void rt_set_preamp_gain(RTContext *ctx, float gain) {
  if (ctx) {
    atomic_store_explicit(&ctx->preampGain, gain, memory_order_relaxed);
  }
}

float rt_get_preamp_gain(RTContext *ctx) {
  return ctx ? atomic_load_explicit(&ctx->preampGain, memory_order_relaxed) : 1.0f;
}

float rt_get_peak_l(RTContext *ctx, int slot) {
  return (ctx && rt_slot_ok(slot))
             ? atomic_load_explicit(&ctx->peakL[slot], memory_order_relaxed)
             : 0.0f;
}

float rt_get_peak_r(RTContext *ctx, int slot) {
  return (ctx && rt_slot_ok(slot))
             ? atomic_load_explicit(&ctx->peakR[slot], memory_order_relaxed)
             : 0.0f;
}

uint64_t rt_get_cycles(RTContext *ctx) {
  return ctx ? atomic_load_explicit(&ctx->cycleCount, memory_order_relaxed) : 0;
}

void rt_set_routing(RTContext *ctx, int slot, int bufferIndex,
                    int channelOffset, int channels) {
  if (!ctx || !rt_slot_ok(slot))
    return;
  ctx->bufferIndex[slot] = bufferIndex;
  ctx->channelOffset[slot] = channelOffset;
  ctx->channels[slot] = channels;
}

void rt_set_out_buffer(RTContext *ctx, int slot, int outBufferIndex) {
  if (!ctx || !rt_slot_ok(slot))
    return;
  ctx->outBufferIndex[slot] = outBufferIndex;
}

void rt_set_tap_count(RTContext *ctx, int count) {
  if (!ctx)
    return;
  if (count < 0)
    count = 0;
  if (count > RT_MAX_SLOTS)
    count = RT_MAX_SLOTS;
  ctx->tapCount = count;
}

void rt_reset_slot(RTContext *ctx, int slot) {
  if (!ctx || !rt_slot_ok(slot))
    return;
  atomic_store_explicit(&ctx->gain[slot], 1.0f, memory_order_relaxed);
  atomic_store_explicit(&ctx->mute[slot], false, memory_order_relaxed);
  atomic_store_explicit(&ctx->peakL[slot], 0.0f, memory_order_relaxed);
  atomic_store_explicit(&ctx->peakR[slot], 0.0f, memory_order_relaxed);
  ctx->bufferIndex[slot] = -1;
  ctx->outBufferIndex[slot] = 0;
  ctx->channelOffset[slot] = 0;
  ctx->channels[slot] = 0;
}

void rt_mix_process(RTContext *ctx, const AudioBufferList *in,
                    AudioBufferList *out) {
  if (ctx == NULL || out == NULL || out->mNumberBuffers == 0)
    return;

  float mg = atomic_load_explicit(&ctx->masterGain, memory_order_relaxed);
  if (atomic_load_explicit(&ctx->masterMute, memory_order_relaxed)) {
    mg = 0.0f;
  }

  uint32_t nbuf = (in != NULL) ? in->mNumberBuffers : 0;
  int32_t taps = ctx->tapCount;
  if (taps > RT_MAX_SLOTS)
    taps = RT_MAX_SLOTS;

  uint32_t lastFrames = 0;

  for (int32_t t = 0; t < taps; t++) {
    int32_t bi = ctx->bufferIndex[t];
    if (bi < 0 || (uint32_t)bi >= nbuf)
      continue;

    int32_t obi = ctx->outBufferIndex[t];
    if (obi < 0 || (uint32_t)obi >= out->mNumberBuffers) {
      obi = 0; // fallback to master output buffer
    }

    AudioBuffer ob = out->mBuffers[obi];
    float *o = (float *)ob.mData;
    if (o == NULL)
      continue;
    uint32_t outCh = ob.mNumberChannels;
    if (outCh == 0)
      continue;
    uint32_t outFrames = ob.mDataByteSize / (uint32_t)(sizeof(float) * outCh);
    if (outFrames == 0)
      continue;
    if (outFrames > lastFrames)
      lastFrames = outFrames;

    AudioBuffer ib = in->mBuffers[bi];
    const float *s = (const float *)ib.mData;
    uint32_t stride = ib.mNumberChannels;
    int32_t off = ctx->channelOffset[t];
    int32_t ch = ctx->channels[t];
    if (ch <= 0 || stride == 0 || (uint32_t)(off + ch) > stride || s == NULL) {
      atomic_store_explicit(&ctx->peakL[t], 0.0f, memory_order_relaxed);
      atomic_store_explicit(&ctx->peakR[t], 0.0f, memory_order_relaxed);
      continue;
    }

    uint32_t inFrames = ib.mDataByteSize / (uint32_t)(sizeof(float) * stride);
    uint32_t n = inFrames < outFrames ? inFrames : outFrames;

    float g = atomic_load_explicit(&ctx->gain[t], memory_order_relaxed);
    if (atomic_load_explicit(&ctx->mute[t], memory_order_relaxed)) {
      g = 0.0f;
    }
    float effPreamp = atomic_load_explicit(&ctx->preampGain, memory_order_relaxed);
    float eff = g * mg * effPreamp;

    float peakL = 0.0f, peakR = 0.0f;

    if (ch >= 2) {
      for (uint32_t f = 0; f < n; f++) {
        const float *frame = s + (size_t)f * stride + off;
        float l = frame[0], r = frame[1];
        float al = fabsf(l), ar = fabsf(r);
        if (al > peakL)
          peakL = al;
        if (ar > peakR)
          peakR = ar;
        if (outCh >= 2) {
          o[(size_t)f * outCh + 0] += l * eff;
          o[(size_t)f * outCh + 1] += r * eff;
        } else {
          o[(size_t)f * outCh] += 0.5f * (l + r) * eff;
        }
      }
    } else {
      for (uint32_t f = 0; f < n; f++) {
        float m = s[(size_t)f * stride + off];
        float am = fabsf(m);
        if (am > peakL)
          peakL = am;
        o[(size_t)f * outCh + 0] += m * eff;
        if (outCh >= 2)
          o[(size_t)f * outCh + 1] += m * eff;
      }
      peakR = peakL;
    }

    atomic_store_explicit(&ctx->peakL[t], peakL * effPreamp, memory_order_relaxed);
    atomic_store_explicit(&ctx->peakR[t], peakR * effPreamp, memory_order_relaxed);
  }

  /* Studio soft-saturation limiter applied across ALL output sub-device buffers */
  for (uint32_t b = 0; b < out->mNumberBuffers; b++) {
    AudioBuffer ob = out->mBuffers[b];
    float *o = (float *)ob.mData;
    if (o == NULL || ob.mNumberChannels == 0)
      continue;
    uint32_t total = ob.mDataByteSize / (uint32_t)sizeof(float);
    for (uint32_t i = 0; i < total; i++) {
      o[i] = rt_saturate(o[i]);
    }
  }

  atomic_fetch_add_explicit(&ctx->cycleCount, 1, memory_order_relaxed);
  atomic_store_explicit(&ctx->lastFrameCount, lastFrames, memory_order_relaxed);
}
