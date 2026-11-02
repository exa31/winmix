# Walkthrough: WinMix - Per-App Output Routing & Clean 100% Volume Mixer

A native macOS per-application volume mixer modeled after the Windows Volume Mixer (`sndvol.exe`), featuring vertical fader channels, real-time bouncing peak VU meters, master output control, per-app volume attenuation (0% - 100%), and per-app audio output device routing.

---

## What Was Accomplished in this Update

1. **Clean 100% Volume Range (Restored to Classic SndVol Experience)**:
   - Removed the 200% overdrive boost and restored the volume faders to a clean, natural **0% – 100% (0.0 to 1.0)** range.
   - Cleaned tick marks to standard markers (100% Max, 75%, 50%, 25%, 0% Min).
   - Double-tap on any fader snaps directly back to 100%.
   - Eliminated compressor/limiter saturation artifacts so audio remains 100% bit-perfect, natural, and clean.

2. **Retained: Per-App Audio Output Device Routing**:
   - Kept the per-app output selector dropdown button on each application column.
   - Users can route individual applications to different audio devices (e.g., WhatsApp/Calls to **External Headphones / AirPods**, and other apps to **MacBook Air Speakers**, or follow **Default**).
   - Built via CoreAudio aggregate devices with deterministic tap buffer indexing and physical output subdevice isolation.
   - Preferences persist automatically per application bundle ID (`Persistence.setAppOutputUID`).

3. **Retained: Smart Auto-Follow Output Device (Default)**:
   - WinMix automatically follows whichever audio output device is currently active in macOS by default (internal speakers, AirPods, Bluetooth headphones, 3.5mm jack, HDMI display).
   - Unplugging headphones or connecting AirPods triggers an instant auto-switch without manual intervention.

4. **Retained: 30-Second Idle Session Retention**:
   - Applications that pause or stop playing audio (Music, YouTube, WhatsApp) remain visible in the mixer for 30 seconds rather than disappearing immediately.

5. **Automated Unit Testing (`./test.sh`)**:
   - Confirmed all C real-time tests and Swift model unit tests pass with 0 failures.
   - Confirmed **0 heap allocations over 500,000 IO cycles** (`[PASS]`).

---

## Verification Results

```bash
./test.sh
```
```text
==================================================
 1. COMPILING & RUNNING C REAL-TIME AUDIO TESTS
==================================================
==================================================
 RUNNING C REAL-TIME CORE AUDIO UNIT TESTS
==================================================
  [PASS] Mix Left: 0.5 * 0.8 + 1.0 * 0.4 = 0.8
  [PASS] Mix Right: 0.5 * -0.8 + 1.0 * 0.2 = -0.2
  [PASS] Tap0 peakL is accurate pre-gain meter (0.8)
  [PASS] Tap1 peakR is accurate pre-gain meter (0.2)
  [PASS] Muting tap1 leaves Left = 0.5 * 0.8 = 0.4
  [PASS] Muted tap1 still measures source peak for meter (0.4)
  [PASS] Tap0 volume to 0 leaves Tap1 untouched (0.4, 0.2)
  [PASS] Master mute silences all output channels
  [PASS] Master mute still preserves per-app VU meters
  [PASS] 200% boost cleanly saturates Left near +1.0f without harsh clipping
  [PASS] 200% boost cleanly saturates Right near -1.0f without harsh clipping
  [PASS] Extreme overdrive asymptotes to +1.0f
  [PASS] Extreme overdrive asymptotes to -1.0f
  [PASS] Interleaved single-buffer multi-tap routing succeeds
  [PASS] NULL input buffer handled safely without crash or noise
  [PASS] NULL input buffer meters to 0.0f
  [PASS] Preamp 2.0x restores -6 dB attenuation (0.8 * 0.5 * 2.0 = 0.8)
  [PASS] Preamp 2.0x scales peak meter accurately (0.8 * 2.0 = 1.6)

Testing Real-Time Safety over 500,000 IO cycles...
  Heap blocks in use delta: 0
  [PASS] rt_mix_process performs ZERO heap allocations during 500k cycles
  [PASS] Cycle counter progressed smoothly

RESULT: ALL C TESTS PASSED (0 failure(s))

==================================================
 2. COMPILING & RUNNING SWIFT UNIT TESTS
==================================================
-- Testing Persistence & Preferences --
  [PASS] Default unconfigured app gain is 1.0 (100%)
  [PASS] Default app mute is false
  [PASS] Saved gain persists correctly (0.75)
  [PASS] Saved mute state persists correctly (true)
  [PASS] Master gain persists correctly (0.85)
  [PASS] Auto output routing default is true
  [PASS] Manual output routing persists correctly (false)
  [PASS] Excluded bundle IDs contains our mixer bundle ID

-- Testing App Identification & Friendly Names --
  [PASS] Chrome helper resolved to 'Google Chrome'
  [PASS] WebKit GPU process resolved to 'Safari'
  [PASS] SystemSoundServer resolved to 'System Sounds'
  [PASS] Spotify bundle resolved to 'Spotify'
  [PASS] Unlisted app fallback capitalized last component ('Discordapp')

-- Testing dB Perceptual VU Meter Scaling --
  [PASS] Zero peak maps to 0.0 on meter
  [PASS] Unity peak 1.0 maps to top region of meter (1.0)
  [PASS] Moderate peak 0.1 maps to mid region (0.6)

RESULT: ALL SWIFT TESTS PASSED (0 failure(s))
```
```
