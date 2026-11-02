/*
 * rt_test.c - Unit tests for the real-time audio mixing core (RTMixer.c).
 *
 * Verifies:
 *   1. Numeric correctness: per-app gain, channel summing, individual mute,
 * master mute, routing, soft overdrive clamping, and pre-gain VU metering.
 *   2. Real-time safety: 500,000 IO cycles with ZERO heap allocations
 * (malloc_zone_statistics).
 */
#include "../Sources/RTMixer.h"
#include <malloc/malloc.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int g_failures = 0;
#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      printf("  [FAIL] %s\n", msg);                                            \
      g_failures++;                                                            \
    } else {                                                                   \
      printf("  [PASS] %s\n", msg);                                            \
    }                                                                          \
  } while (0)

static int approx(float a, float b) { return fabsf(a - b) < 1e-5f; }

typedef struct {
  UInt32 mNumberBuffers;
  AudioBuffer mBuffers[8];
} ABL8;

int main(void) {
  printf("==================================================\n");
  printf(" RUNNING C REAL-TIME CORE AUDIO UNIT TESTS\n");
  printf("==================================================\n");

  RTContext *ctx = rt_context_create();
  if (!ctx) {
    printf("  [FAIL] rt_context_create returned NULL\n");
    return 1;
  }
  // Unity preamp for baseline math unit tests
  rt_set_preamp_gain(ctx, 1.0f);

  const uint32_t frames = 512;
  static float tap0[1024], tap1[1024], outbuf[1024];
  for (uint32_t f = 0; f < frames; f++) {
    tap0[f * 2 + 0] = 0.8f;
    tap0[f * 2 + 1] = -0.8f;
    tap1[f * 2 + 0] = 0.4f;
    tap1[f * 2 + 1] = 0.2f;
  }

  ABL8 in;
  memset(&in, 0, sizeof(in));
  ABL8 out;
  memset(&out, 0, sizeof(out));
  in.mNumberBuffers = 2;
  in.mBuffers[0].mNumberChannels = 2;
  in.mBuffers[0].mDataByteSize = frames * 2 * sizeof(float);
  in.mBuffers[0].mData = tap0;
  in.mBuffers[1].mNumberChannels = 2;
  in.mBuffers[1].mDataByteSize = frames * 2 * sizeof(float);
  in.mBuffers[1].mData = tap1;
  out.mNumberBuffers = 1;
  out.mBuffers[0].mNumberChannels = 2;
  out.mBuffers[0].mDataByteSize = frames * 2 * sizeof(float);
  out.mBuffers[0].mData = outbuf;

  rt_set_tap_count(ctx, 2);
  rt_set_routing(ctx, 0, 0, 0, 2);
  rt_set_routing(ctx, 1, 1, 0, 2);

  /* Test 1: Gains 0.5 and 1.0, summed correctly */
  rt_set_gain(ctx, 0, 0.5f);
  rt_set_gain(ctx, 1, 1.0f);
  memset(outbuf, 0, sizeof(outbuf));
  rt_mix_process(ctx, (AudioBufferList *)&in, (AudioBufferList *)&out);
  CHECK(approx(outbuf[0], 0.8f), "Mix Left: 0.5 * 0.8 + 1.0 * 0.4 = 0.8");
  CHECK(approx(outbuf[1], -0.2f), "Mix Right: 0.5 * -0.8 + 1.0 * 0.2 = -0.2");
  CHECK(approx(rt_get_peak_l(ctx, 0), 0.8f),
        "Tap0 peakL is accurate pre-gain meter (0.8)");
  CHECK(approx(rt_get_peak_r(ctx, 1), 0.2f),
        "Tap1 peakR is accurate pre-gain meter (0.2)");

  /* Test 2: Mute tap1 -> only tap0 in output, tap1 VU meter still responsive */
  rt_set_mute(ctx, 1, true);
  memset(outbuf, 0, sizeof(outbuf));
  rt_mix_process(ctx, (AudioBufferList *)&in, (AudioBufferList *)&out);
  CHECK(approx(outbuf[0], 0.4f), "Muting tap1 leaves Left = 0.5 * 0.8 = 0.4");
  CHECK(approx(rt_get_peak_l(ctx, 1), 0.4f),
        "Muted tap1 still measures source peak for meter (0.4)");
  rt_set_mute(ctx, 1, false);

  /* Test 3: Changing one app gain leaves other app completely untouched */
  rt_set_gain(ctx, 0, 0.0f);
  rt_set_gain(ctx, 1, 1.0f);
  memset(outbuf, 0, sizeof(outbuf));
  rt_mix_process(ctx, (AudioBufferList *)&in, (AudioBufferList *)&out);
  CHECK(approx(outbuf[0], 0.4f) && approx(outbuf[1], 0.2f),
        "Tap0 volume to 0 leaves Tap1 untouched (0.4, 0.2)");
  rt_set_gain(ctx, 0, 0.5f);

  /* Test 4: Master mute silences all outputs */
  rt_set_master_mute(ctx, true);
  memset(outbuf, 0, sizeof(outbuf));
  rt_mix_process(ctx, (AudioBufferList *)&in, (AudioBufferList *)&out);
  CHECK(approx(outbuf[0], 0.0f) && approx(outbuf[1], 0.0f),
        "Master mute silences all output channels");
  CHECK(approx(rt_get_peak_l(ctx, 0), 0.8f),
        "Master mute still preserves per-app VU meters");
  rt_set_master_mute(ctx, false);

  /* Test 5: Overdrive / 200% volume boost soft-saturates cleanly within [-1.0, 1.0] */
  rt_set_gain(ctx, 0, 2.0f);
  rt_set_gain(ctx, 1, 0.0f);
  memset(outbuf, 0, sizeof(outbuf));
  rt_mix_process(ctx, (AudioBufferList *)&in, (AudioBufferList *)&out);
  // 0.8 * 2.0 = 1.6; with threshold 0.8, excess 0.8: 0.8 + 0.2 * tanh(4.0) = ~0.999f
  CHECK(outbuf[0] >= 0.99f && outbuf[0] <= 1.0f, "200% boost cleanly saturates Left near +1.0f without harsh clipping");
  CHECK(outbuf[1] <= -0.99f && outbuf[1] >= -1.0f, "200% boost cleanly saturates Right near -1.0f without harsh clipping");

  /* Test 5b: Extreme overdrive (4.0x) asymptotically hits +/-1.0f without overflow */
  rt_set_gain(ctx, 0, 4.0f);
  memset(outbuf, 0, sizeof(outbuf));
  rt_mix_process(ctx, (AudioBufferList *)&in, (AudioBufferList *)&out);
  CHECK(approx(outbuf[0], 1.0f), "Extreme overdrive asymptotes to +1.0f");
  CHECK(approx(outbuf[1], -1.0f), "Extreme overdrive asymptotes to -1.0f");
  rt_set_gain(ctx, 0, 0.5f);
  rt_set_gain(ctx, 1, 1.0f);

  /* Test 6: Interleaved buffer routing */
  static float packed[2048];
  for (uint32_t f = 0; f < frames; f++) {
    packed[f * 4 + 0] = 0.8f;
    packed[f * 4 + 1] = -0.8f;
    packed[f * 4 + 2] = 0.4f;
    packed[f * 4 + 3] = 0.2f;
  }
  ABL8 in2;
  memset(&in2, 0, sizeof(in2));
  in2.mNumberBuffers = 1;
  in2.mBuffers[0].mNumberChannels = 4;
  in2.mBuffers[0].mDataByteSize = frames * 4 * sizeof(float);
  in2.mBuffers[0].mData = packed;
  rt_set_routing(ctx, 0, 0, 0, 2);
  rt_set_routing(ctx, 1, 0, 2, 2);
  memset(outbuf, 0, sizeof(outbuf));
  rt_mix_process(ctx, (AudioBufferList *)&in2, (AudioBufferList *)&out);
  CHECK(approx(outbuf[0], 0.8f) && approx(outbuf[1], -0.2f),
        "Interleaved single-buffer multi-tap routing succeeds");

  /* Test 7: NULL tap data handling (fail-safe test) */
  in.mBuffers[1].mData = NULL;
  rt_set_routing(ctx, 0, 0, 0, 2);
  rt_set_routing(ctx, 1, 1, 0, 2);
  memset(outbuf, 0, sizeof(outbuf));
  rt_mix_process(ctx, (AudioBufferList *)&in, (AudioBufferList *)&out);
  CHECK(approx(outbuf[0], 0.4f),
        "NULL input buffer handled safely without crash or noise");
  CHECK(approx(rt_get_peak_l(ctx, 1), 0.0f),
        "NULL input buffer meters to 0.0f");
  in.mBuffers[1].mData = tap1;

  /* Test 7b: Preamp gain calibration (Apple -6 dB downmix attenuation recovery) */
  rt_set_preamp_gain(ctx, 2.0f);
  rt_set_gain(ctx, 0, 0.5f);
  rt_set_gain(ctx, 1, 0.0f);
  memset(outbuf, 0, sizeof(outbuf));
  rt_mix_process(ctx, (AudioBufferList *)&in, (AudioBufferList *)&out);
  // 0.8 * 0.5 * 2.0 = 0.8
  CHECK(approx(outbuf[0], 0.8f), "Preamp 2.0x restores -6 dB attenuation (0.8 * 0.5 * 2.0 = 0.8)");
  CHECK(approx(rt_get_peak_l(ctx, 0), 1.6f), "Preamp 2.0x scales peak meter accurately (0.8 * 2.0 = 1.6)");
  rt_set_preamp_gain(ctx, 1.0f);

  /* Test 8: Real-time safety (ZERO heap allocations over 500,000 audio IO
   * cycles) */
  printf("\nTesting Real-Time Safety over 500,000 IO cycles...\n");
  malloc_statistics_t before, after;
  rt_mix_process(ctx, (AudioBufferList *)&in,
                 (AudioBufferList *)&out); // warm up
  malloc_zone_statistics(malloc_default_zone(), &before);
  for (int i = 0; i < 500000; i++) {
    rt_mix_process(ctx, (AudioBufferList *)&in, (AudioBufferList *)&out);
  }
  malloc_zone_statistics(malloc_default_zone(), &after);
  long deltaBlocks = (long)after.blocks_in_use - (long)before.blocks_in_use;
  printf("  Heap blocks in use delta: %ld\n", deltaBlocks);
  CHECK(deltaBlocks == 0,
        "rt_mix_process performs ZERO heap allocations during 500k cycles");
  CHECK(rt_get_cycles(ctx) >= 500000, "Cycle counter progressed smoothly");

  rt_context_destroy(ctx);

  printf("\nRESULT: %s (%d failure(s))\n",
         g_failures == 0 ? "ALL C TESTS PASSED" : "FAILED", g_failures);
  return g_failures == 0 ? 0 : 1;
}
