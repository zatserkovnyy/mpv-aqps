# Adaptive Quality Profile Selector & Advanced OSD (AQPS) for mpv

Intelligent **mpv** script that automatically analyzes video bitrate, resolution, codec, bit depth, HDR type, frame rate and content type, then applies the most suitable quality profile. It also provides a detailed custom OSD with real-time information.

## What the script does

On every file load the script:

1. Detects resolution category (`2160p` / `1080p` / `720p` / `480p`).
2. Measures or estimates video bitrate (via `ffprobe` or file size calculation).
3. Normalizes bitrate taking into account:
   - Codec efficiency (H.264, HEVC, AV1, VP9…)
   - Bit depth (8/10/12/16-bit)
   - HDR (HDR10, HDR10+, Dolby Vision, HLG…)
   - Frame rate (corrects high-FPS content)
   - Cartoon content (applies higher multiplier)
4. Selects and applies one of the quality profiles listed below.
5. Detects special sources (YouTube, DVD, custom `hdtv` files) and applies dedicated profiles.
6. Shows a rich custom OSD (toggled with `Home` key) containing:
   - File name / title
   - Current time, progress, remaining time and estimated end time
   - Video resolution, FPS, bit depth, codec, pixel format and bitrate
   - Audio track details (language, title, codec, channels, bitrate)
   - Subtitle track details
   - Active tone-mapping, 3D LUT, debanding settings and loaded shaders
   - Selected quality profile with detailed bitrate calculation breakdown
  
### Core Logic

<details>
<br>
AQPS is a smart video-quality/profile selector for mpv.

Its main purpose is to analyze the currently playing video, normalize its effective bitrate according to codec efficiency and video characteristics, select an appropriate quality profile, and display the complete calculation in the mpv OSD.

The script does not simply compare the source bitrate against fixed thresholds. Instead, it converts different video formats into a common **effective bitrate scale** before selecting a profile.

---

## 1. Overview

The script performs four main tasks:

1. **Analyzes the currently loaded video**
   - Resolution
   - Codec
   - Bit depth
   - Frame rate
   - Video bitrate
   - Audio tracks
   - HDR format
   - Special file types

2. **Normalizes the video bitrate**
   - Codec efficiency
   - HDR
   - Bit depth
   - Frame rate
   - Cartoon/animation content

3. **Selects an appropriate quality profile**
   - `2160p-HQ`
   - `2160p-MQ`
   - `2160p-LQ`
   - `1080p-HQ`
   - `1080p-MQ`
   - `1080p-LQ`
   - `720p-HQ`
   - `720p-MQ`
   - `720p-LQ`
   - `480p`

4. **Displays detailed playback information**
   - Video parameters
   - Raw bitrate
   - Normalized bitrate
   - Selected profile
   - Audio information
   - Subtitle information
   - HDR
   - Tone mapping
   - 3D LUT
   - Debanding
   - Shaders
   - Playback progress and ETA

---

# 2. Quality Thresholds

The script defines separate bitrate thresholds for each resolution.

| Resolution | HQ | MQ | LQ |
|------------|----:|----:|----:|
| 2160p | ≥ 24 Mbps | ≥ 12 Mbps | < 12 Mbps |
| 1080p | ≥ 12 Mbps | ≥ 6 Mbps | < 6 Mbps |
| 720p | ≥ 4 Mbps | ≥ 2.5 Mbps | < 2.5 Mbps |
| 480p | — | — | 480p |

These thresholds are applied to the **normalized bitrate**, not necessarily to the raw source bitrate.

This distinction is important because two files with the same raw bitrate can have very different visual quality depending on their codec and other characteristics.

---

# 3. Codec Normalization

The script uses codec-specific coefficients to convert the source bitrate into a common reference scale.

The coefficients are resolution-dependent.

For example, at 2160p:

| Codec | Factor |
|-------|-------:|
| H.264 / AVC1 | 2.50 |
| HEVC / H.265 | 1.00 |
| VP8 | 3.15 |
| VP9 | 1.20 |
| AV1 | 0.65 |

The basic normalization formula is:

```text
equivalent_bitrate = source_bitrate / codec_factor
```

For example:

```text
24 Mbps H.264
24 / 2.50 = 9.6 Mbps equivalent
```

while:

```text
24 Mbps HEVC
24 / 1.00 = 24 Mbps equivalent
```

Therefore, the script treats the same raw bitrate differently depending on codec efficiency.

The codec tables are different for 2160p, 1080p, 720p and 480p.

---

# 4. HDR Normalization

HDR video receives an additional normalization factor.

The script defines three HDR factors:

```text
HQ = 1.03
MQ = 1.05
LQ = 1.08
```

The factor is selected according to the resolution and normalized bitrate.

Conceptually:

```text
HDR-normalized bitrate =
    codec-normalized bitrate / HDR factor
```

For example, if a source falls into the HDR HQ range:

```text
HDR factor = 1.03
```

The normalized bitrate is divided by `1.03`.

This provides a small bitrate penalty for HDR material during quality classification.

---

# 5. Bit Depth Normalization

The script also accounts for color bit depth.

The multipliers are:

| Bit depth | Multiplier |
|-----------|-----------:|
| 8-bit | 1.00 |
| 10-bit | 1.08 |
| 12-bit | 1.15 |
| 16-bit | 1.20 |

The bit-depth multiplier is applied after codec and HDR normalization.

Conceptually:

```text
normalized_bitrate =
    bitrate
    / codec_factor
    / hdr_factor
    × bit_depth_multiplier
```

Therefore, a 10-bit source receives a small positive adjustment compared with an otherwise identical 8-bit source.

---

# 6. Cartoon / Animation Detection

The script has a special mechanism for animation.

It searches the filename for predefined keywords, including:

```text
futurama
simpsons
morty
phineas
south.park
gravity.falls
spongebob
```

If one of these strings is found in the filename, the video is classified as cartoon content.

Different multipliers are then applied depending on resolution:

| Resolution | Cartoon multiplier |
|------------|-------------------:|
| 480p | ×1.50 |
| 720p | ×1.60 |
| 1080p | ×1.70 |
| 2160p | ×1.90 |

For example, a 1080p cartoon with a calculated bitrate of:

```text
4 Mbps
```

is treated as:

```text
4 × 1.70 = 6.8 Mbps
```

for quality classification.

This allows animation to be evaluated differently from live-action material.

---

# 7. Audio Bitrate Estimation

The script first tries to obtain the actual audio bitrate from mpv.

If a valid bitrate is available, it is used directly.

If the actual bitrate is unavailable, the script estimates it from:

- Codec
- Codec profile (for accurate DTS-HD Master Audio detection)
- Channel count
- Sample rate
- Track information
- Atmos indication

The script contains bitrate estimates for codecs including:

- TrueHD
- DTS-HD
- FLAC
- ALAC
- PCM
- DTS
- E-AC-3
- AC-3
- MP3
- Vorbis
- AAC
- Opus

If no suitable information is available, the fallback value is:

```text
192 kbps
```

The script also detects `Atmos` in the audio track title and adds an Atmos bitrate bonus:

```text
0.512 Mbps
```

Audio bitrate calculations are cached by track ID.

---

# 8. Video Bitrate Detection

The script has two primary methods for obtaining the video bitrate.

## 8.1. FFprobe

For local files, the script uses `ffprobe` to obtain:

- Video bitrate
- Frame rate
- `BPS` stream tag

The returned data is parsed and converted to Mbps.

For example:

```text
12000000 bits/s
```

becomes:

```text
12 Mbps
```

The FFprobe result is cached for 60 seconds.

---

## 8.2. Bitrate Fallback Calculation

If FFprobe cannot provide the video bitrate, the script estimates it from:

- Total file size
- Duration
- Estimated audio bitrate

The approximate total bitrate calculation is:

```text
total_bitrate =
    file_size × 8 / duration / 1,000,000
```

The estimated video bitrate is then calculated approximately as:

```text
video_bitrate =
    total_bitrate - audio_bitrate
```

The result is marked as an estimated value rather than an FFprobe value.

The OSD uses a `~` prefix when the bitrate is estimated.

---

# 9. Network Stream / YouTube Handling

The script explicitly checks for `youtube.com` and `youtu.be` URLs. For these YouTube streams, it uses a separate profile-selection path and does not attempt to use FFprobe.

Regular HTTP/HTTPS network streams (such as direct links, Plex, or Jellyfin) are now treated as standard files, allowing the script to accurately estimate their bitrate instead of blindly applying YouTube profiles.

```text
>1080p  → YouTube UHD
1080p   → YouTube HD
<1080p  → YouTube SD
```

No normal bitrate normalization is performed for this branch.

---

# 10. DVD Handling

DVD files are treated as a special case.

The script recognizes:

```text
.vob
.ifo
```

and assigns:

```text
DVD
```

as the profile.

For DVD files, normal bitrate/FPS detection is disabled.


---

# 11. HDTV Handling

If the filename contains:

```text
hdtv
```

the script assigns the:

```text
hdtv
```

profile.

Bitrate and FPS information can still be collected for OSD/debugging purposes, but HDR processing is disabled for this special case.

---

# 12. Resolution Classification

The script maps the actual video resolution into four categories based on the frame's total pixel area.

### 2160p
If the frame area > 2.5 MP (e.g., > 2,500,000 pixels). This includes 1440p, 4K and higher.

### 1080p
If the frame area > 1.3 MP (e.g., > 1,300,000 pixels). This intelligently catches cropped ultra-wide formats like 1920x800 and 1440x1080.

### 720p
If the frame area > 0.64 MP (e.g., > 640,000 pixels). This reliably catches 1280x536 and 960x720, while explicitly excluding PAL/DVD 1024x576.

### 480p
Everything below the 720p classification (DVD, 540p, 480p).

The resolution category determines which:

- Codec coefficients
- HDR factors
- Cartoon multipliers
- Quality thresholds

will be used.

---

# 13. Frame Rate Normalization

The script uses approximately:

```text
23.976 FPS
```

as its reference frame rate.

For videos with substantially higher FPS, it calculates:

```text
fps_adjust_coeff =
    actual_fps / 23.976
```

If the coefficient is greater than `1`, the bitrate is adjusted:

```text
adjusted_bitrate =
    bitrate / fps_adjust_coeff
```

For example:

```text
47.952 FPS
```

produces:

```text
47.952 / 23.976 = 2.0
```

Therefore:

```text
20 Mbps / 2 = 10 Mbps
```

for quality classification.

This prevents high-frame-rate video from receiving an artificially high quality classification simply because it contains more frames per second.

---

# 14. 50 FPS Special Case

The script contains a specific correction for:

- 576p @ 50 FPS
- 1080p @ 50 FPS

These sources are treated as effectively 25 FPS for the bitrate coefficient calculation.

Conceptually:

```text
50 FPS → 25 FPS
```

The original FPS is still retained separately for display.

This allows the OSD to show the actual source frame rate while the normalization algorithm uses the adjusted value.

---

# 15. Complete Normalized Bitrate Formula

The core normalization process can be represented as:

```text
normalized_bitrate =
    source_bitrate
    × cartoon_multiplier
    × fps_multiplier
    × bit_depth_multiplier
    / codec_factor
    / hdr_factor
```

where:

```text
fps_multiplier = 1 / fps_adjust_coeff
```

when FPS normalization is active.

For ordinary 23.976/24 FPS, SDR, 8-bit, non-cartoon material, most factors become `1.0`.

The calculation therefore simplifies to approximately:

```text
normalized_bitrate =
    source_bitrate / codec_factor
```

---

# 16. Quality Profile Selection

After normalization, the script compares the resulting bitrate against the resolution-specific thresholds.

## 2160p

```text
normalized >= 24 Mbps → 2160p-HQ
normalized >= 12 Mbps → 2160p-MQ
otherwise             → 2160p-LQ
```

## 1080p

```text
normalized >= 12 Mbps → 1080p-HQ
normalized >= 6 Mbps  → 1080p-MQ
otherwise             → 1080p-LQ
```

## 720p

```text
normalized >= 4 Mbps   → 720p-HQ
normalized >= 2.5 Mbps → 720p-MQ
otherwise              → 720p-LQ
```

## 480p

```text
480p
```

The selected profile is cached using the file path and resolution.

---

# 17. HDR Detection

HDR detection is based on mpv's:

```text
video-out-params
```

The script examines parameters such as:

- Gamma
- Primaries
- Color matrix
- Dolby Vision information
- HDR10+ information
- SL-HDR information
- Technicolor information

The detection logic is approximately:

```text
HLG gamma
    ↓
HLG / HLG10

PQ or BT.2020
    ↓
    Dolby Vision?
        ↓ yes
        Dolby Vision

    HDR10+?
        ↓ yes
        HDR10+

    SL-HDR?
        ↓ yes
        SL-HDR

    Technicolor HDR?
        ↓ yes
        Technicolor HDR

    otherwise
        HDR10
```

When HDR is detected, the script activates:

```text
hdr
```

When HDR is no longer detected, it switches back to:

```text
default
```

HDR changes are handled dynamically through mpv property observers.

---

# 18. Runtime State

The script keeps its runtime information inside a central `state` table.

It contains information such as:

- Current file path
- Filename
- FPS
- Raw bitrate
- Normalized bitrate
- Bitrate source
- HDR status
- HDR type
- Cartoon status
- Cartoon multiplier
- FPS correction coefficient
- Selected profile
- Audio information
- OSD state

This provides a central representation of the current video state.

---

# 19. Caching

The script uses several caches:

```text
ffprobe_cache
audio_bitrate_cache
quality_profile_cache
```

### FFprobe cache

Stores video bitrate and FPS information.

Entries remain valid for:

```text
60 seconds
```

### Audio bitrate cache

Stores the calculated bitrate for individual audio tracks.

### Quality profile cache

Stores the selected profile based on:

```text
file path + resolution
```

Caching prevents repeated calculations during playback.

---

# 20. Audio OSD

The OSD displays information about the currently selected audio track:

- Language
- Title
- Codec
- Channel layout
- Bitrate
- Track number
- Total number of audio tracks

Common channel counts are converted into familiar notation:

```text
1 channel → 1.0
2 channels → 2.0
6 channels → 5.1
8 channels → 7.1
```

For example:

```text
Audio: [ENG] Main | DTS-HD Master Audio 7.1 @ 4608 kbps [1/3]
```

The exact information depends on the metadata provided by mpv.

---

# 21. Audio Codec Identification

The script performs additional codec identification instead of simply displaying the raw codec name.

For DTS, it examines multiple properties, including:

- Codec
- Codec profile
- Codec description
- Track title
- Decoder name
- Output format

It can distinguish between:

```text
DTS Digital Surround
DTS-HD
DTS-HD High Resolution
DTS-HD Master Audio
```

It also recognizes common formats such as:

```text
Dolby Digital
Dolby Digital Plus
Dolby TrueHD
AAC
MP3
FLAC
Opus
Vorbis
PCM
```

If `Atmos` is detected in the track title, it is added to the displayed codec name.

---

# 22. Subtitle Information

The selected subtitle track is also displayed.

The script distinguishes between several subtitle types.

### ASS / SSA

Depending on subtitle override mode:

```text
Styled (ASS)
```

or:

```text
Text (ASS)
```

### PGS / HDMV / DVD subtitles

```text
Bitmap (PGS)
```

### SRT / SubRip / Text / WebVTT

```text
Text (SRT)
```

The OSD also displays:

- Language
- Subtitle title
- Track number
- Total number of subtitle tracks

---

# 23. Tone Mapping

The script checks mpv's:

```text
tone-mapping
```

property.

If HDR is inactive, or tone mapping is set to:

```text
auto
```

the OSD displays:

```text
Tone-Mapping: inactive
```

Otherwise, the active tone-mapping algorithm is displayed.

`mobius` is displayed as:

```text
Möbius
```

while other algorithm names are formatted for readability.

---

# 24. 3D LUT Detection

The script checks mpv's:

```text
target-lut
```

property.

If an active `.cube` LUT exists, the script extracts its filename and removes the `.cube` extension.

For example:

```text
some_lut.cube
```

becomes:

```text
3D LUT: some_lut
```

If no LUT is active:

```text
3D LUT: inactive
```

---

# 25. Debanding Detection

The script checks whether mpv debanding is enabled.

When active, the OSD displays:

- Iterations
- Threshold
- Range
- Grain

Otherwise:

```text
Debanding: inactive
```

This provides direct visibility into the current debanding configuration.

---

# 26. Shader Detection

The script reads mpv's:

```text
glsl-shaders
```

list.

For each shader, it attempts to generate a human-readable name instead of displaying the full filesystem path.

Special formatting is provided for shaders such as:

- FSRCNNX
- adaptive-sharpen
- CAS

If no shaders are active:

```text
Shaders: inactive
```

---

# 27. Static OSD Information

Static OSD information contains parameters that normally do not change every frame.

It includes:

```text
Video:
resolution
FPS
bit depth
codec
pixel format / hwdec
```

It also displays the selected profile and the normalization calculation.

Conceptually, the profile information can look like:

```text
Profile: 1080p-HQ
[13.2 Mbps codec /0.55, bit depth x1.08, hdr /1.03]
```

The exact values depend on the source video.

The purpose is to make the profile-selection process transparent and debuggable.

---

# 28. Normalization Breakdown in the OSD

One of the most useful parts of the OSD is that it can show how the normalized bitrate was calculated.

Starting with:

```text
raw video bitrate
```

the script applies:

```text
cartoon multiplier
FPS multiplier
bit-depth multiplier
codec divisor
HDR divisor
```

The resulting value is the normalized bitrate used for profile selection.

Conceptually:

```text
raw bitrate
    ↓
cartoon adjustment
    ↓
FPS adjustment
    ↓
codec normalization
    ↓
HDR normalization
    ↓
bit-depth adjustment
    ↓
normalized bitrate
    ↓
quality profile
```

This makes it possible to understand why a particular profile was selected instead of treating the profile as a black box.

---

# 29. Dynamic OSD Information

Dynamic OSD information is regenerated when track or audio properties change.

This includes:

- Selected audio track
- Selected subtitle track
- Audio bitrate
- Audio codec
- Subtitle information

Static video information does not need to be rebuilt every time the user changes the audio or subtitle track.

---

# 30. OSD Layout

When visible, the OSD contains information in approximately this order:

1. Video name
2. Playback time and progress
3. Video information
4. Audio information
5. Subtitle information
6. Tone mapping
7. 3D LUT
8. Quality profile
9. Debanding
10. Shaders

The playback line can contain:

```text
current clock time
current playback position
percentage
total duration
remaining duration
estimated end time
```

For example:

```text
10:32 | 01:15:23 [52%] 02:24:10 (-01:08:47) | 11:41
```

The OSD is rendered using mpv's ASS OSD interface.

---

# 31. OSD Refresh

The custom OSD is toggled using:

```text
HOMEPAGE
```

When enabled, the script creates a timer that updates the OSD once per second:

```text
1 second
    ↓
display_osd()
```

When the OSD is hidden, the timer is destroyed and the ASS OSD is cleared.

This means playback time and ETA are refreshed once per second.

---

# 32. mpv Property Observers

The script observes several mpv properties so that information updates automatically.

### Audio

```text
audio-codec-name
audio-out-format
audio-bitrate
aid
```

### Subtitles

```text
sid
```

### Video

```text
video-out-params
video-bitrate
target-lut
```

### Playback

```text
duration
seeking
```

When a relevant property changes, the appropriate part of the OSD is regenerated.

---

# 33. Event-Driven HDR Handling

HDR detection is integrated into mpv's property observer system.

When:

```text
video-out-params
```

changes, the script checks the HDR state again.

If the HDR state changed, it:

1. Updates the HDR state.
2. Applies or removes the HDR profile.
3. Regenerates static OSD information.
4. Refreshes the visible OSD.

This allows HDR changes to be handled dynamically during playback.

---

# 34. File Lifecycle

The script primarily operates through two events:

```text
start-file
file-loaded
```

## `start-file`

The script resets:

- Timers
- Runtime state
- Bitrate caches
- Profile state
- Cartoon state
- FPS correction state

It also clears:

```text
deband
glsl-shaders
```

and removes the current OSD.

This prevents settings from the previous file from leaking into the next one.

---

## `file-loaded`

After mpv has loaded the file, the script:

1. Obtains the video path.
2. Resets video-specific state.
3. Determines the appropriate quality profile.
4. Applies the profile.
5. Generates static OSD information.
6. Generates dynamic OSD information.
7. Refreshes the OSD if it is currently visible.

This is effectively the main initialization stage for every new video.

---

# 35. Track Changes

When the available tracks change, the audio bitrate cache is cleared.

This ensures that newly available or modified audio tracks do not accidentally reuse stale bitrate estimates.

---

# 36. Keyboard Controls

## `HOMEPAGE`

Toggles the AQPS information OSD.

```text
HOMEPAGE
    ↓
OSD visible?
    ├── Yes → Hide
    └── No  → Show
```

## `MENU`

If the AQPS OSD is visible, it is hidden first.

The action is then forwarded to mpv's standard statistics display:

```text
stats/display-stats-toggle
```

This prevents the custom AQPS OSD and mpv's standard statistics overlay from being displayed simultaneously.

---

# 37. Complete Processing Pipeline

The normal-video processing pipeline can be summarized as:

```text
File loaded
     │
     ▼
Get video path
     │
     ▼
Detect special file type
     │
     ├── YouTube ───────► YouTube UHD / HD / SD
     │
     ├── DVD ───────────► DVD
     │
     ├── hdtv ─────► hdtv
     │
     └── Normal video
              │
              ▼
       Determine resolution
              │
              ▼
       Detect codec + bit depth
              │
              ▼
       Obtain video bitrate
         │              │
         │              └── FFprobe
         │
         └── Fallback calculation
              │
              ▼
       Detect cartoon content
              │
              ▼
       Apply cartoon multiplier
              │
              ▼
       Apply FPS correction
              │
              ▼
       Normalize codec efficiency
              │
              ▼
       Normalize HDR
              │
              ▼
       Apply bit-depth multiplier
              │
              ▼
       Calculate normalized bitrate
              │
              ▼
       Compare against thresholds
              │
              ▼
       Select quality profile
              │
              ▼
       Apply mpv profile
              │
              ▼
       Generate OSD
```

---

# 38. Example: 1080p HEVC HDR 10-bit

Consider a source with:

```text
1920×1080
HEVC
10-bit
23.976 FPS
HDR10
15 Mbps
```

The script first classifies it as:

```text
1080p
```

Assuming the 1080p HEVC coefficient is:

```text
0.55
```

the codec-normalized bitrate becomes:

```text
15 / 0.55
≈ 27.27 Mbps
```

The result is above the 1080p HQ threshold:

```text
12 Mbps
```

so the HDR HQ factor is applied:

```text
27.27 / 1.03
≈ 26.48 Mbps
```

The 10-bit multiplier is then applied:

```text
26.48 × 1.08
≈ 28.60 Mbps
```

The resulting profile is:

```text
1080p-HQ
```

This example demonstrates why the script does not classify video solely by its raw bitrate.

---

# 39. Example: 1080p H.264

Consider:

```text
1920×1080
H.264
8-bit
23.976 FPS
SDR
15 Mbps
```

Assuming the 1080p H.264 coefficient is:

```text
1.00
```

the normalized bitrate is:

```text
15 / 1.00 = 15 Mbps
```

No HDR adjustment is required.

No bit-depth adjustment is required because the source is 8-bit.

The final normalized bitrate is therefore:

```text
15 Mbps
```

Since:

```text
15 Mbps >= 12 Mbps
```

the selected profile is:

```text
1080p-HQ
```

---

# 40. Example: 2160p AV1

Consider:

```text
3840×2160
AV1
20 Mbps
```

Assuming the 2160p AV1 coefficient is:

```text
0.65
```

the normalized bitrate becomes:

```text
20 / 0.65
≈ 30.77 Mbps
```

The 2160p HQ threshold is:

```text
24 Mbps
```

Therefore:

```text
30.77 Mbps >= 24 Mbps
```

and the selected profile is:

```text
2160p-HQ
```

This illustrates the purpose of codec normalization: a relatively low raw bitrate can still represent high-quality video when the codec is sufficiently efficient.

---

# 41. What the Script Is Actually Measuring

AQPS is not directly measuring visual quality.

Instead, it attempts to estimate:

> **How much bitrate the source would approximately correspond to if different codecs, frame rates, bit depths, HDR characteristics and content types were converted to a common reference scale.**

The reference scale is implicitly based around:

- Codec efficiency
- 23.976/24 FPS
- 8-bit
- SDR
- Non-cartoon content

Other video characteristics are then normalized against this reference.

The resulting value is used as the **effective / equivalent bitrate** for profile selection.

---

# 42. Profile Selection vs. Playback Configuration

The script does not contain the complete rendering configuration for profiles such as:

```text
2160p-HQ
2160p-MQ
2160p-LQ
1080p-HQ
1080p-MQ
1080p-LQ
720p-HQ
720p-MQ
720p-LQ
```

Instead, it calls mpv's:

```lua
mp.commandv("apply-profile", profile)
```

The actual mpv settings are therefore expected to be defined separately in the mpv configuration.

AQPS acts primarily as the **decision engine**:

```text
Analyze
    ↓
Normalize
    ↓
Classify
    ↓
Apply profile
```

rather than as the place where all rendering parameters are defined.

---

# 43. Separation of Responsibilities

The architecture can be divided into several logical layers.

### Detection layer

Determines:

- File type
- Codec
- Resolution
- FPS
- Bit depth
- HDR
- Audio
- Subtitles

### Measurement layer

Obtains:

- Video bitrate
- Audio bitrate
- File size
- Duration

### Normalization layer

Adjusts the bitrate according to:

- Codec efficiency
- HDR
- Bit depth
- FPS
- Cartoon content

### Classification layer

Maps the normalized bitrate to:

```text
HQ / MQ / LQ
```

### Profile layer

Calls:

```text
apply-profile
```

### Presentation layer

Displays the calculated information through the OSD.

This separation allows the thresholds and normalization logic to be modified independently from the OSD and mpv profile configuration.

---

# 44. Reset Behavior

When a new file starts, the script resets the previous video's state.

This includes:

```text
HDR state
Cartoon state
FPS correction
Video bitrate
Selected profile
Caches
Timers
```

It also clears previously active debanding and shaders.

This prevents parameters from the previous video from affecting the new one.

---

# 45. High-Level Algorithm

In simplified pseudocode:

```text
ON FILE LOADED:

    reset state

    identify file type

    IF YouTube:
        choose UHD / HD / SD profile
        disable normal HDR handling
        apply profile
        stop

    IF DVD:
        apply DVD profile
        send dvd-detected message
        stop

    IF HDTV:
        collect bitrate information
        apply hdtv
        stop

    detect:
        resolution
        codec
        bit depth
        FPS
        HDR

    obtain video bitrate

    IF bitrate is unavailable:
        estimate bitrate from file size and duration

    detect cartoon filename

    IF cartoon:
        apply animation multiplier

    IF FPS requires correction:
        normalize to 23.976 FPS

    normalize codec efficiency

    IF HDR:
        apply HDR normalization

    apply bit-depth multiplier

    calculate normalized bitrate

    classify normalized bitrate:

        2160p:
            >=24 → HQ
            >=12 → MQ
            else → LQ

        1080p:
            >=12 → HQ
            >=6  → MQ
            else → LQ

        720p:
            >=4   → HQ
            >=2.5 → MQ
            else → LQ

        480p:
            480p

    apply selected mpv profile

    generate static OSD
    generate dynamic OSD
```

---

## Summary

AQPS can be summarized as a **video-analysis and quality-profile decision engine for mpv**.

Its core workflow is:

```text
Source video
     ↓
Detect technical parameters
     ↓
Obtain / estimate bitrate
     ↓
Normalize bitrate
     ├── Codec
     ├── HDR
     ├── Bit depth
     ├── FPS
     └── Cartoon content
     ↓
Calculate effective bitrate
     ↓
Compare against resolution-specific thresholds
     ↓
Select HQ / MQ / LQ profile
     ↓
Apply mpv profile
     ↓
Display the complete calculation in OSD
```

The main idea is that **raw bitrate is not treated as a universal measure of quality**. AQPS attempts to compensate for the major factors that influence how efficiently bitrate is converted into perceived image quality, producing a more consistent basis for automatic profile selection.
</details>

### Automatically applied profiles

The script looks for these exact profile names in your `mpv.conf`:

```
[hdr]
[hdtv]
[dvd]
[YouTube UHD]
[YouTube HD]
[YouTube SD]
[2160p-HQ]
[2160p-MQ]
[2160p-LQ]
[1080p-HQ]
[1080p-MQ]
[1080p-LQ]
[720p-HQ]
[720p-MQ]
[720p-LQ]
[480p]
```

You must define these profiles yourself in `mpv.conf` with the settings you prefer (shaders, deband, scaling, tone-mapping, etc.). The script only decides *which* profile to apply.

### Special cases

| Source              | Applied profile     |
|---------------------|---------------------|
| YouTube ≥ 4K        | `YouTube UHD`       |
| YouTube 1080p       | `YouTube HD`        |
| YouTube < 1080p     | `YouTube SD`        |
| DVD / VOB / IFO     | `dvd`               |
| Filename contains `hdtv` | `hdtv` |
| HDR content         | additionally applies `hdr` |

## Requirements

- **ffprobe** must be installed on your system.
  - **Windows:** Place `ffprobe.exe` in the same folder as `mpv.exe` **or** add it to your system `PATH`.
  - **macOS / Linux:** Install via your package manager (e.g., `brew install ffmpeg` or `sudo apt install ffmpeg`). The script automatically detects `ffprobe` in standard locations (such as `/opt/homebrew/bin`, `/usr/local/bin`, or `/usr/bin`) even if your system `PATH` is not fully passed to the mpv GUI application.
- Profiles listed above must exist in your `mpv.conf` (you define the actual settings inside them).

## Installation

1. Copy `aqps.lua` into your mpv scripts directory:
   - Linux / macOS → `~/.config/mpv/scripts/`
   - Windows → `%APPDATA%\mpv\scripts\`
2. Make sure `ffprobe` is accessible.
3. Define the required profiles in `mpv.conf`.
4. Restart mpv.

## Hotkeys

| Key        | Action                          |
|------------|---------------------------------|
| `Home`     | Toggle detailed custom OSD      |
| `Menu`     | Hide custom OSD + show stats    |

## How the quality decision works

1. Raw bitrate is obtained from `ffprobe` (preferred) or calculated from file size.
2. Bitrate is normalized using multiple factors:
   - Codec equivalence tables (different for each resolution)
   - Bit-depth multiplier
   - HDR penalty/bonus
   - Cartoon multiplier (higher for animated content)
   - Frame-rate correction (e.g. 50/60 fps → treated closer to 24 fps)
3. The normalized bitrate is compared against thresholds:

| Resolution | HQ threshold | MQ threshold |
|------------|--------------|--------------|
| 2160p      | ≥ 24 Mbps    | ≥ 12 Mbps    |
| 1080p      | ≥ 12 Mbps    | ≥ 6 Mbps     |
| 720p       | ≥ 4 Mbps     | ≥ 2.5 Mbps   |
| ≤ 480p     | always `480p`| –            |

4. The matching profile (`…-HQ` / `…-MQ` / `…-LQ`) is applied.

## What you can (and should) customize

All important values are defined as constants at the top of the script and can be freely changed:

- Bitrate thresholds (`BITRATE_2160_HQ`, `BITRATE_1080_HQ`, …)
- Codec equivalence factors (`CODEC_EQUIV_FACTOR_2160`, `…_1080`, etc.)
- HDR multipliers (`HDR_FACTOR_HQ / MQ / LQ`)
- Bit-depth multipliers
- Cartoon multipliers and list of cartoon show names
- Base audio bitrate estimates
- OSD behaviour and key bindings

Because the script only *selects* profiles, you have full control over the actual image processing by editing the corresponding sections in `mpv.conf`.

## Sample OSD

<img width="2676" height="966" alt="osd-1" src="https://github.com/user-attachments/assets/429d2575-9f4c-4f7b-be31-9e72d328a4fa" />

---

<img width="2676" height="966" alt="osd-2" src="https://github.com/user-attachments/assets/3711b279-9538-406c-9d97-af9f89ffbabe" />

## Sample mpv.conf (e.g., for my 1080p PJ)

<details>
<br>

```ini
profile=high-quality

[hdr]
tone-mapping=mobius
hdr-compute-peak=yes
tone-mapping-param=0.01

[hdtv]
glsl-shaders-clr
glsl-shaders="~~/shaders/SSimSuperRes.glsl"
glsl-shaders-append="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=1
deband-threshold=22
deband-range=12
deband-grain=2

[dvd]
glsl-shaders-clr
glsl-shaders="~~/shaders/FSRCNNX_x2_16-0-4-1.glsl"
glsl-shaders-append="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=2
deband-threshold=22
deband-range=14
deband-grain=4

[YouTube UHD]
glsl-shaders-clr
glsl-shaders="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/SSimDownscaler.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
linear-downscaling=no
deband=yes
deband-iterations=1
deband-threshold=18
deband-range=10
deband-grain=2

[YouTube HD]
glsl-shaders-clr
glsl-shaders="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=1
deband-threshold=20
deband-range=12
deband-grain=3

[YouTube SD]
glsl-shaders-clr
glsl-shaders="~~/shaders/FSRCNNX_x2_16-0-4-1.glsl"
glsl-shaders-append="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=2
deband-threshold=22
deband-range=14
deband-grain=4

[2160p-HQ]
glsl-shaders-clr
glsl-shaders="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/SSimDownscaler.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
linear-downscaling=no

[2160p-MQ]
glsl-shaders-clr
glsl-shaders="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/SSimDownscaler.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
linear-downscaling=no
deband=yes
deband-iterations=1
deband-threshold=18
deband-range=10
deband-grain=2

[2160p-LQ]
glsl-shaders-clr
glsl-shaders="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/SSimDownscaler.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
linear-downscaling=no
deband=yes
deband-iterations=2
deband-threshold=20
deband-range=12
deband-grain=3

[1080p-HQ]
glsl-shaders-clr
glsl-shaders="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"

[1080p-MQ]
glsl-shaders-clr
glsl-shaders="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=1
deband-threshold=20
deband-range=12
deband-grain=2

[1080p-LQ]
glsl-shaders-clr
glsl-shaders="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=2
deband-threshold=24
deband-range=14
deband-grain=3

[720p-HQ]
glsl-shaders-clr
glsl-shaders="~~/shaders/FSRCNNX_x2_16-0-4-1.glsl"
glsl-shaders-append="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=1
deband-threshold=20
deband-range=12
deband-grain=2

[720p-MQ]
glsl-shaders-clr
glsl-shaders="~~/shaders/FSRCNNX_x2_16-0-4-1.glsl"
glsl-shaders-append="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=1
deband-threshold=22
deband-range=14
deband-grain=3

[720p-LQ]
glsl-shaders-clr
glsl-shaders="~~/shaders/FSRCNNX_x2_16-0-4-1.glsl"
glsl-shaders-append="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=2
deband-threshold=26
deband-range=16
deband-grain=4

[480p]
glsl-shaders-clr
glsl-shaders="~~/shaders/FSRCNNX_x2_16-0-4-1.glsl"
glsl-shaders-append="~~/shaders/SSimSuperRes.glsl"
glsl-shaders-append="~~/shaders/KrigBilateral.glsl"
glsl-shaders-append="~~/shaders/adaptive-sharpen.glsl"
deband=yes
deband-iterations=2
deband-threshold=26
deband-range=16
deband-grain=4
```

</details>

## FFprobe download

[GyanD/codexffmpeg Releases](https://github.com/GyanD/codexffmpeg/releases)

## Notes

Please note: this script is designed to be fully cross-platform (Windows, macOS, Linux). However, since I primarily develop on Windows and currently cannot test directly on macOS or Linux environments, please feel free to open an issue or provide feedback if you encounter any platform-specific bugs!

- All threshold values, bitrates, multipliers, and factors (such as codec efficiencies, HDR bonuses, and custom cartoon detection titles) are defined right at the top of the script under the `CONSTANTS` section. You can easily tweak any number in the code to perfectly match your specific display, projector, or hardware capabilities.
- The script is heavily optimized for **1080p projectors**, but the 2160p profiles and logic are fully functional for 4K displays.
- For best results keep `ffprobe` up to date.
- External audio tracks and network streams are handled gracefully (bitrate estimation falls back when necessary).
- If you encounter any bugs, errors, or have ideas on how to improve the script, please let me know! You can open an **Issue** here on GitHub or submit a **Pull Request**. I will gladly find the time to review your feedback and fix any problems.

---

Drop the script in, define your preferred profiles in `mpv.conf`, and mpv will automatically choose the best settings for every video.

---

## Support

If you find this script useful, you can support my work with a voluntary donation. If you'd like to fuel my coding with a warm cup of coffee, any support is greatly appreciated! ❤️

[![DonationAlerts](https://img.shields.io/badge/Support-DonationAlerts-orange?style=for-the-badge&logo=coffee)](https://www.donationalerts.com/r/zatserkovnyy)
