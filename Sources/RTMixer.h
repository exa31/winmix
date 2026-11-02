#ifndef RTMIXER_H
#define RTMIXER_H

#include <stdbool.h>
#include <stdint.h>
#include <CoreAudio/CoreAudioTypes.h>

#define RT_MAX_SLOTS 64

typedef struct RTContext RTContext;

/* Lifecycle */
RTContext *rt_context_create(void);
void       rt_context_destroy(RTContext *ctx);

/* Control thread -> audio thread (atomic) */
void  rt_set_gain(RTContext *ctx, int slot, float gain);
void  rt_set_mute(RTContext *ctx, int slot, bool mute);
void  rt_set_master_gain(RTContext *ctx, float gain);
void  rt_set_master_mute(RTContext *ctx, bool mute);
void  rt_set_preamp_gain(RTContext *ctx, float gain);
float rt_get_preamp_gain(RTContext *ctx);

/* Audio thread -> control thread (atomic) */
float    rt_get_peak_l(RTContext *ctx, int slot);
float    rt_get_peak_r(RTContext *ctx, int slot);
uint64_t rt_get_cycles(RTContext *ctx);

/* Routing: written by control thread ONLY while IOProc is stopped */
void rt_set_routing(RTContext *ctx, int slot, int bufferIndex, int channelOffset, int channels);
void rt_set_out_buffer(RTContext *ctx, int slot, int outBufferIndex);
void rt_set_tap_count(RTContext *ctx, int count);
void rt_reset_slot(RTContext *ctx, int slot);

/* The real-time IO callback body */
void rt_mix_process(RTContext *ctx,
                    const AudioBufferList *inInputData,
                    AudioBufferList *outOutputData);

#endif /* RTMIXER_H */

