-- =======================================================
-- Script: aqps.lua
-- Description: Adaptive Quality Profile Selector & Advanced OSD (AQPS) for mpv
-- Author: Boris Zatserkovnyy
-- Version: 1.0.0
-- GitHub: https://github.com/zatserkovnyy/mpv-aqps
-- =======================================================

local mp = require("mp")
local utils = require("mp.utils")

-- ======================================
-- CONSTANTS
-- ======================================

local BITRATE_2160_HQ = 24
local BITRATE_2160_MQ = 12

local BITRATE_1080_HQ = 12
local BITRATE_1080_MQ = 6

local BITRATE_720_HQ = 4
local BITRATE_720_MQ = 2.5

local CODEC_EQUIV_FACTOR_2160 = {
    h264 = 2.50,
    avc1 = 2.50,
    hevc = 1.00,
    h265 = 1.00,
    hev1 = 1.00,
    vp8 = 2.80,
    vp9 = 1.20,
    av1 = 0.65
}

local CODEC_EQUIV_FACTOR_1080 = {
    h264 = 1.00,
    avc1 = 1.00,
    hevc = 0.55,
    h265 = 0.55,
    hev1 = 0.55,
    vp8 = 0.80,
    vp9 = 0.60,
    av1 = 0.42
}

local CODEC_EQUIV_FACTOR_720 = {
    h264 = 1.00,
    avc1 = 1.00,
    hevc = 0.65,
    h265 = 0.65,
    hev1 = 0.65,
    vp8 = 0.85,
    vp9 = 0.70,
    av1 = 0.48
}

local CODEC_EQUIV_FACTOR_480 = {
    h264 = 1.00,
    avc1 = 1.00,
    hevc = 0.70,
    h265 = 0.70,
    hev1 = 0.70,
    vp8 = 0.90,
    vp9 = 0.75,
    av1 = 0.50
}

local HDR_FACTOR_HQ = 1.03
local HDR_FACTOR_MQ = 1.05
local HDR_FACTOR_LQ = 1.08

local BIT_DEPTH_MULTIPLIER = {
    [8] = 1.00,
    [10] = 1.08,
    [12] = 1.15,
    [16] = 1.20
}

local CARTOON_MULTIPLIER = {
    ["480p"] = 1.50,
    ["720p"] = 1.60,
    ["1080p"] = 1.70,
    ["2160p"] = 1.90
}

local CARTOON_SHOWS = {"futurama", "simpsons", "morty", "phineas", "south"}

local DEFAULT_AUDIO_BITRATE = 0.192
local ATMOS_BONUS = 0.512
local BASE_AUDIO_BITRATES = {
    truehd = 4.870 / 8,
    ["dts-hd"] = 5.770 / 8,
    flac = 1.200 / 2,
    alac = 1.200 / 2,
    pcm = 1.536 / 2,
    dts = {
        stereo = 0.768,
        multichannel = 1.509
    },
    eac3 = 0.640,
    ac3 = 0.448,
    mp3 = 0.192,
    vorbis = 0.192,
    aac = 0.192,
    opus = 0.128
}

-- ======================================
-- FFPROBE DETECTION
-- ======================================

local ffprobe_path = "ffprobe"
mp.msg.info("Using ffprobe: " .. ffprobe_path)

-- ======================================
-- STATE TABLE
-- ======================================

local default_state = {
    video_path = nil,
    video_name = "",
    video_fps_actual = nil,
    raw_video_bitrate = nil,
    orig_video_bitrate = nil,
    video_bitrate = nil,
    avg_video_bitrate = nil,
    video_bitrate_source = nil,
    hdr_enabled = true,
    hdr_active = false,
    hdr_type = "",
    is_cartoon = false,
    cartoon_multiplier = 1.0,
    display_profile = nil,
    profile_applied = false,
    fps_adjust_coeff = nil,
    audio_codec_name = "",
    audio_output_format = "",
    audio_bitrate_kbps = nil,
    osd_visible = false,
    osd_timer = nil,
    osd_video_line_prefix = "",
    osd_video_line_suffix = "",
    osd_audio_line = "",
    osd_subs_line = "",
    osd_profile_line = "",
    osd_deband_line = "",
    osd_shader_line = "",
    osd_fps_display = "",
    osd_hdr_text = ""
}

local state = {}
for k, v in pairs(default_state) do
    state[k] = v
end

-- ======================================
-- CACHE
-- ======================================

local ffprobe_cache = {}
local audio_bitrate_cache = {}
local quality_profile_cache = {}

-- ======================================
-- AUDIO BITRATE CALCULATION
-- ======================================

local function calculate_audio_bitrate(track)
    if not track then
        return DEFAULT_AUDIO_BITRATE
    end

    local br = tonumber(track.bit_rate)

    if br and br > 0 then
        return br / 1e6
    end

    local codec = (track.codec or ""):lower()
    local channels = tonumber(track["audio-channels"]) or tonumber(track["demux-channels"]) or 2
    local sr = tonumber(track["sample-rate"]) or 48000
    local freq_factor = sr / 48000
    local abr = nil

    if codec:find("truehd") or codec:find("mlp") then
        abr = BASE_AUDIO_BITRATES.truehd * channels
    elseif codec:find("dts%-hd") or codec:find("dtshd") then
        abr = BASE_AUDIO_BITRATES["dts-hd"] * channels
    elseif codec:find("flac") then
        abr = BASE_AUDIO_BITRATES.flac * channels
    elseif codec:find("alac") then
        abr = BASE_AUDIO_BITRATES.alac * channels
    elseif codec:find("pcm") then
        abr = BASE_AUDIO_BITRATES.pcm * channels
    elseif codec:find("dts") then
        abr = (channels <= 2) and BASE_AUDIO_BITRATES.dts.stereo or BASE_AUDIO_BITRATES.dts.multichannel
    elseif codec:find("eac3") then
        abr = BASE_AUDIO_BITRATES.eac3
    elseif codec:find("ac3") then
        abr = BASE_AUDIO_BITRATES.ac3
    elseif codec:find("mp3") then
        abr = BASE_AUDIO_BITRATES.mp3
    elseif codec:find("vorbis") then
        abr = BASE_AUDIO_BITRATES.vorbis
    elseif codec:find("aac") then
        abr = BASE_AUDIO_BITRATES.aac
    elseif codec:find("opus") then
        abr = BASE_AUDIO_BITRATES.opus
    end

    if not abr then
        abr = DEFAULT_AUDIO_BITRATE
    end

    local total = abr * freq_factor

    if track.title and track.title:lower():find("atmos") then
        total = total + ATMOS_BONUS
    end

    return total
end

-- ======================================
-- HELPERS
-- ======================================

-- Bitrate formatting

local function fmt_bitrate(val)
    return string.format("%.1f", math.floor((val or 0) * 10 + 0.5) / 10)
end

-- Video name
local function get_video_name()
    local path = state.video_path or ""
    local is_youtube = path:match("^https?://.*youtube%.com") or path:match("^https?://youtu%.be")

    if is_youtube then
        local title = mp.get_property("media-title")

        if title and title ~= "" then
            return title
        end
    end

    return ((path or "Unknown"):match("[^/\\]+$") or "Unknown"):gsub("%.[^%.]+$", "")
end

-- Audio bitrate
local function get_cached_audio_bitrate(track)
    if not track.id then
        return calculate_audio_bitrate(track)
    end

    local cached = audio_bitrate_cache[track.id]

    if cached then
        return cached
    end

    local result = calculate_audio_bitrate(track)
    audio_bitrate_cache[track.id] = result

    return result
end

-- ======================================
-- VIDEO INFO RETRIEVAL
-- ======================================

local function get_video_bitrate_and_fps(path)
    local c = ffprobe_cache[path]

    if c and os.time() - (c.last_checked or 0) < 60 then
        return c.v_bitrate, c.v_fps
    end

    local size = mp.get_property_number("file-size") or 0

    if path:match("^https?://") or size == 0 then
        ffprobe_cache[path] = {
            v_bitrate = nil,
            v_fps = nil,
            last_checked = os.time()
        }
        return nil, nil
    end

    local res, err = utils.subprocess({
        args = {ffprobe_path, "-v", "error", "-select_streams", "v:0", "-show_entries",
                "stream=bit_rate,r_frame_rate:stream_tags=BPS", "-of", "json", path},
        cancellable = false
    })

    local ok, json = pcall(utils.parse_json, res and res.stdout or "")
    local s = (ok and json and json.streams and json.streams[1]) or nil

    if not s then
        mp.msg.error("FFprobe JSON error for " .. path)
        ffprobe_cache[path] = {
            v_bitrate = nil,
            v_fps = nil,
            last_checked = os.time()
        }
        return nil, nil
    end

    local br = tonumber(s.bit_rate or (s.tags and s.tags.BPS))
    local fps

    if s.r_frame_rate then
        local n, d = s.r_frame_rate:match("(%d+)/(%d+)")
        n, d = tonumber(n), tonumber(d)

        if n and d and d ~= 0 then
            fps = n / d
        end
    end

    ffprobe_cache[path] = {
        v_bitrate = br and math.max(br / 1e6, 0) or nil,
        v_fps = fps,
        last_checked = os.time()
    }

    return ffprobe_cache[path].v_bitrate, ffprobe_cache[path].v_fps
end

-- ======================================
-- HDR DETECTION
-- ======================================

local function update_hdr_profile()
    if not state.hdr_enabled then
        state.hdr_type = ""
        state.osd_hdr_text = ""
        return false
    end

    local v_out = mp.get_property_native("video-out-params")
    if not v_out then
        return false
    end

    local gamma = (v_out.gamma or ""):lower()
    local prim = (v_out.primaries or ""):lower()
    local cm = (v_out.colormatrix or ""):lower()
    local dv = mp.get_property_native("video-out-params/dolby-vision") or ""
    local h10p = mp.get_property_native("video-out-params/hdr10-plus") or ""
    local hdr_type = ""

    if gamma == "hlg" then
        hdr_type = cm:find("hlg10") and "HLG10" or "HLG"
    elseif gamma == "pq" or prim == "bt.2020" then
        if dv ~= "" or cm:find("dv") or cm:find("dolby") then
            hdr_type = "Dolby Vision"
        elseif h10p ~= "" or cm:find("hdr10%+") then
            hdr_type = "HDR10+"
        elseif cm:find("sl%-hdr") then
            hdr_type = "SL-HDR"
        elseif cm:find("technicolor") then
            hdr_type = "Technicolor HDR"
        else
            hdr_type = "HDR10"
        end
    end

    if hdr_type ~= state.hdr_type then
        state.hdr_type = hdr_type
        if hdr_type ~= "" then
            state.osd_hdr_text = " " .. hdr_type
            state.hdr_active = true
            mp.commandv("apply-profile", "hdr")
            mp.msg.info("HDR detected: " .. hdr_type .. ", applying profile")
        else
            state.osd_hdr_text = " SDR"
            state.hdr_active = false
            mp.commandv("apply-profile", "default")
            mp.msg.info("No HDR detected, resetting profile")
        end
        return true
    end

    return false
end

-- ======================================
-- VIDEO QUALITY NORMALIZATION
-- ======================================

local function get_video_track()
    local tracks = mp.get_property_native("track-list") or {}

    for _, t in ipairs(tracks) do
        if t.type == "video" and t.selected then
            return t
        end
    end

    return nil
end

local function get_video_codec_and_depth()
    local codec = (mp.get_property("video-codec") or ""):lower()
    local vp = mp.get_property_native("video-params") or {}
    local vo = mp.get_property_native("video-out-params") or {}
    local vt = get_video_track() or {}
    local depth = tonumber(vp["bit-depth"]) or tonumber(vo["bit-depth"]) or tonumber(vt["bit-depth"])

    if not depth then
        local profile = (vt["codec-profile"] or vt["profile"] or ""):lower()

        if profile:find("10") then
            depth = 10
        elseif profile:find("12") then
            depth = 12
        end
    end

    if not depth then
        local pf = (vo.pixelformat or vp.pixelformat or ""):lower()

        if pf:match("p010") or pf:match("10le") or pf:match("10be") then
            depth = 10
        elseif pf:match("p012") or pf:match("12le") or pf:match("12be") then
            depth = 12
        elseif pf:match("p016") or pf:match("16le") or pf:match("16be") then
            depth = 16
        else
            depth = 8
        end
    end

    return codec, depth or 8
end

-- Resolution category classification
local function classify_resolution(width, height)
    width = width or 0
    height = height or 0

    if width > 1920 or height > 1080 then
        return "2160p"
    end

    if width == 1920 or height == 1080 then
        return "1080p"
    end

    if width >= 960 or height >= 540 then
        return "720p"
    end

    return "480p"
end

-- Codec efficiency factor
local function get_codec_equiv_factor(codec, width, height)
    codec = (codec or ""):lower()
    local category = classify_resolution(width, height)
    local factors_map = {
        ["2160p"] = CODEC_EQUIV_FACTOR_2160,
        ["1080p"] = CODEC_EQUIV_FACTOR_1080,
        ["720p"] = CODEC_EQUIV_FACTOR_720,
        ["480p"] = CODEC_EQUIV_FACTOR_480
    }
    local factors = factors_map[category] or CODEC_EQUIV_FACTOR_480

    for k, v in pairs(factors) do
        if codec:find(k) then
            return v
        end
    end

    return 1.0
end

-- HDR multiplier
local function get_hdr_normalization_factor(equiv_bitrate)
    if not state.hdr_active then
        return 1.0
    end

    local width = mp.get_property_number("width") or 0
    local height = mp.get_property_number("height") or 0
    local category = classify_resolution(width, height)

    if category == "2160p" then
        if equiv_bitrate >= BITRATE_2160_HQ then
            return HDR_FACTOR_HQ
        elseif equiv_bitrate >= BITRATE_2160_MQ then
            return HDR_FACTOR_MQ
        else
            return HDR_FACTOR_LQ
        end
    elseif category == "1080p" then
        if equiv_bitrate >= BITRATE_1080_HQ then
            return HDR_FACTOR_HQ
        elseif equiv_bitrate >= BITRATE_1080_MQ then
            return HDR_FACTOR_MQ
        else
            return HDR_FACTOR_LQ
        end
    elseif category == "720p" then
        if equiv_bitrate >= BITRATE_720_HQ then
            return HDR_FACTOR_HQ
        elseif equiv_bitrate >= BITRATE_720_MQ then
            return HDR_FACTOR_MQ
        else
            return HDR_FACTOR_LQ
        end
    else
        return HDR_FACTOR_LQ
    end
end

-- Bits multiplier
local function get_normalized_video_bitrate(avg_bitrate, width, height)
    if not avg_bitrate then
        return nil
    end

    width = width or 0
    height = height or 0

    local codec, bit_depth = get_video_codec_and_depth()
    local depth_bonus = BIT_DEPTH_MULTIPLIER[bit_depth] or 1.0

    local codec_equiv = get_codec_equiv_factor(codec, width, height)
    local equiv_bitrate = avg_bitrate / codec_equiv

    local hdr_factor = state.hdr_active and get_hdr_normalization_factor(equiv_bitrate) or 1.0

    local adjusted_bitrate = (equiv_bitrate / hdr_factor) * depth_bonus
    return adjusted_bitrate
end

-- Cartoon multiplier
local function get_cartoon_multiplier_by_resolution(width, height)
    local category = classify_resolution(width, height)
    return CARTOON_MULTIPLIER[category] or 1.8
end

-- ======================================
-- FILE TYPE DETECTION
-- ======================================

local function get_special_file_type(path)
    if path:match("^https?://") then
        return "youtube"
    end

    local filename = path:match("[^/\\]+$") or ""
    local fname_lc = filename:lower()

    if fname_lc:find("hdtv") then
        return "hdtv"
    elseif fname_lc:find("%.vob$") or fname_lc:find("%.ifo$") then
        return "dvd"
    end

    return nil
end

local function is_cartoon_content(filename)
    local lc_filename = filename:lower()

    for _, show in ipairs(CARTOON_SHOWS) do
        if lc_filename:find(show) then
            return true
        end
    end

    return false
end

-- ======================================
-- BITRATE AND PROFILE SELECTION
-- ======================================

local function estimate_input_video_bitrate(path)
    local ftype = get_special_file_type(state.video_path or "")
    local duration = mp.get_property_number("duration") or 0
    local size = mp.get_property_number("file-size") or 0
    local tracks = mp.get_property_native("track-list") or {}
    local audio_sum = 0

    for _, t in ipairs(tracks) do
        if t.type == "audio" and not t.external then
            audio_sum = audio_sum + get_cached_audio_bitrate(t)
        end
    end

    local v_bitrate, v_fps = get_video_bitrate_and_fps(path)
    local source

    -- 50 FPS fix
    local height = mp.get_property_number("height", 0)

    if v_fps and math.abs(v_fps - 50) < 0.01 and (height == 576 or height == 1080) then
        mp.msg.info("50 fps resolution detected, treating as 25 FPS for coeff")
        state.video_fps_actual = v_fps
        v_fps = 25
    end

    if ftype == "dvd" then
        v_bitrate, v_fps, source = nil, nil, "n/a"
    else
        if not v_bitrate or v_bitrate <= 0 then
            if duration > 0 and size > 0 then
                local total = size * 8 / duration / 1e6
                v_bitrate = math.max(math.min(math.max(total - audio_sum, total * 0.8, 0), 1000), 0.1)
            end

            source = "calc"
        else
            source = "ffprobe"
        end
    end

    if v_bitrate then
        state.raw_video_bitrate = v_bitrate
    else
        state.raw_video_bitrate = nil
    end

    -- Cartoons
    local filename = state.video_path or ""
    state.is_cartoon = is_cartoon_content(filename)

    if state.is_cartoon then
        local height = mp.get_property_number("height") or 0
        local width = mp.get_property_number("width") or 0
        state.cartoon_multiplier = get_cartoon_multiplier_by_resolution(width, height)
    end

    if v_bitrate and state.is_cartoon then
        v_bitrate = v_bitrate * state.cartoon_multiplier
    end

    -- FPS correction
    if state.cartoon_multiplier == 1.0 and v_fps and v_bitrate and not ftype then
        local fps_diff = math.abs(v_fps - 23.976) > 0.01 and math.abs(v_fps - 24.0) > 0.01

        if fps_diff then
            if v_fps and v_fps > 0 then
                local fps_adjust_coeff = v_fps / 23.976

                if fps_adjust_coeff > 1.0001 then
                    state.fps_adjust_coeff = fps_adjust_coeff
                    state.orig_video_bitrate = v_bitrate
                    v_bitrate = v_bitrate / fps_adjust_coeff
                end
            else
                mp.msg.warn("FPS is zero or nil, skipping FPS adjustment")
            end
        end
    end

    return v_bitrate, v_fps or 0, source, state.cartoon_multiplier
end

-- Profile selection
local function determine_quality_profile(avg_bitrate, height)
    if not avg_bitrate then
        return "Default"
    end

    local width = mp.get_property_number("width") or 0
    local path = state.video_path or ""
    local cache_key = path .. "_" .. tostring(width) .. "x" .. tostring(height)

    if quality_profile_cache[cache_key] then
        return quality_profile_cache[cache_key]
    end

    local q_bitrate = get_normalized_video_bitrate(avg_bitrate, width, height)
    q_bitrate = tonumber(fmt_bitrate(q_bitrate))
    local category = classify_resolution(width, height)
    local profile

    if category == "2160p" then
        profile = q_bitrate >= BITRATE_2160_HQ and "2160p-HQ" or q_bitrate >= BITRATE_2160_MQ and "2160p-MQ" or
                      "2160p-LQ"
    elseif category == "1080p" then
        profile = q_bitrate >= BITRATE_1080_HQ and "1080p-HQ" or q_bitrate >= BITRATE_1080_MQ and "1080p-MQ" or
                      "1080p-LQ"
    elseif category == "720p" then
        profile = q_bitrate >= BITRATE_720_HQ and "720p-HQ" or q_bitrate >= BITRATE_720_MQ and "720p-MQ" or "720p-LQ"
    else
        profile = "480p"
    end

    quality_profile_cache[cache_key] = profile

    return profile
end

-- ======================================
-- SMART PROFILE APPLICATION
-- ======================================

local function apply_video_quality_profile()
    if state.profile_applied then
        return
    end

    local path = state.video_path
    if not path then
        return
    end

    local ftype = get_special_file_type(state.video_path or "")

    local function apply_special(name, profile, extra)
        state.hdr_enabled = false
        state.display_profile = name
        state.profile_applied = true

        if profile then
            mp.commandv("apply-profile", profile)
        end

        if extra then
            extra()
        end

        mp.msg.info("Applying special profile: " .. name)
    end

    if ftype == "youtube" then
        local width = mp.get_property_number("width") or 0
        local height = mp.get_property_number("height") or 0
        local youtube_profile

        if height > 1080 then
            youtube_profile = "YouTube UHD"
        elseif height == 1080 then
            youtube_profile = "YouTube HD"
        else
            youtube_profile = "YouTube SD"
        end

        apply_special(youtube_profile, youtube_profile)
        return
    elseif ftype == "dvd" then
        apply_special("DVD", "dvd", function()
        end)
        return
    elseif ftype == "hdtv" then
        local avg, fps, source, coeff = estimate_input_video_bitrate(path)
        state.hdr_enabled = false
        state.avg_video_bitrate = avg
        state.video_bitrate_source = source
        state.video_fps_actual = fps
        state.cartoon_multiplier = coeff
        apply_special("hdtv", "hdtv")
        return
    end

    local height = mp.get_property_number("height") or 0
    if height == 0 then
        return
    end

    local avg, fps, source, coeff = estimate_input_video_bitrate(path)
    state.avg_video_bitrate = avg
    state.video_bitrate_source = source
    state.video_fps_actual = fps
    state.cartoon_multiplier = coeff

    local profile = determine_quality_profile(avg, height)
    state.display_profile = profile
    state.profile_applied = true

    if profile ~= "" and profile ~= "Default" then
        local avg_bitrate = state.avg_video_bitrate
        local video_bitrate_source = state.video_bitrate_source or "n/a"
        local prefix = (video_bitrate_source == "calc") and "~" or ""
        local avg_text = avg_bitrate and fmt_bitrate(avg_bitrate) or "n/a"
        local bitrate_display = avg_text
        local osd_hdr_text = " " .. (state.hdr_type ~= "" and state.hdr_type or "SDR")

        if state.is_cartoon and (state.cartoon_multiplier or 1.0) > 1.0 then
            local orig_text = fmt_bitrate(avg_bitrate / state.cartoon_multiplier)
            local applied_text = fmt_bitrate(avg_bitrate)
            bitrate_display = string.format("%s (%s*c)", orig_text, applied_text)
        elseif state.fps_adjust_coeff and state.fps_adjust_coeff > 1.0 then
            local orig_text = fmt_bitrate(state.orig_video_bitrate)
            bitrate_display = string.format("%s (%s*f)", orig_text, avg_text)
        end

        local x = state.raw_video_bitrate or 0
        local x_text = fmt_bitrate(x)
        local dw, dh = mp.get_property_number("width", 0), mp.get_property_number("height", 0)
        local codec, bit_depth = get_video_codec_and_depth()
        local depth_mult = BIT_DEPTH_MULTIPLIER[bit_depth] or 1.00
        local codec_div = get_codec_equiv_factor(codec, dw, dh) or 1.0
        local equiv = avg_bitrate / codec_div
        local hdr_div = state.hdr_active and get_hdr_normalization_factor(equiv) or 1.0
        local cartoon_mult = state.cartoon_multiplier or 1.0
        local fps_mult = 1.0
        if state.fps_adjust_coeff and state.fps_adjust_coeff > 1.0001 then
            fps_mult = 1 / state.fps_adjust_coeff
        end
        local y = x * cartoon_mult * fps_mult * depth_mult / codec_div / hdr_div
        local y_text = fmt_bitrate(y)
        local coeff_parts = {}
        if cartoon_mult ~= 1.0 then
            table.insert(coeff_parts, string.format("cartoon x%.2f", cartoon_mult))
        end
        if codec_div ~= 1.0 then
            table.insert(coeff_parts, string.format("codec /%.2f", codec_div))
        end
        if depth_mult ~= 1.0 then
            table.insert(coeff_parts, string.format("bit depth x%.2f", depth_mult))
        end
        if fps_mult ~= 1.0 then
            table.insert(coeff_parts, string.format("frame rate x%.2f", fps_mult))
        end
        if hdr_div ~= 1.0 then
            table.insert(coeff_parts, string.format("hdr /%.2f", hdr_div))
        end

        local full_profile_str
        if #coeff_parts > 0 then
            local coeff_str = table.concat(coeff_parts, ", ")
            full_profile_str = string.format("%s%s [%s%s Mbps @ %s] → [%s%s Mbps @ %s]", profile, osd_hdr_text,
                prefix, x_text, video_bitrate_source, prefix, y_text, coeff_str)
        else
            full_profile_str = string.format("%s%s [%s%s Mbps @ %s]", profile, osd_hdr_text, prefix, x_text,
                video_bitrate_source)
        end

        mp.msg.info("Applying quality profile: " .. full_profile_str)
        mp.commandv("apply-profile", profile)
    else
        mp.msg.info("No profile to apply, skipping")
    end
end

-- ======================================
-- OSD FORMATTING HELPERS
-- ======================================

local function format_time_hms(seconds, show_hours, show_seconds)
    if not seconds or seconds < 0 then
        return "00:00"
    end

    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)

    if show_seconds then
        return (show_hours or h > 0) and string.format("%02d:%02d:%02d", h, m, s) or string.format("%02d:%02d", m, s)
    else
        return string.format("%02d:%02d", (show_hours or h > 0) and h or m, (show_hours or h > 0) and m or s)
    end
end

local function format_eta_time(seconds_remaining)
    if not seconds_remaining or seconds_remaining < 0 then
        return "00:00"
    end

    local t = os.date("*t", os.time() + math.floor(seconds_remaining))
    return string.format("%02d:%02d", t.hour, t.min)
end

-- Get friendly codec name for audio track
local function get_readable_audio_codec_name(track)
    if not track or not track.codec then
        return "Unknown"
    end

    local filename = (state.video_path or ""):match("[^/\\]+$") or ""
    local c_lower = (track.codec or ""):lower()
    local c_profile = (track["codec-profile"] or ""):lower()
    local desc = (mp.get_property_native("current-tracks/audio/codec-desc") or ""):lower()
    local track_title = (track.title or ""):lower()
    local decoder_name = (state.audio_codec_name or ""):lower()
    local ao_format = (state.audio_output_format or ""):lower()

    local names = {
        ac3 = "Dolby Digital",
        eac3 = "Dolby Digital Plus",
        truehd = "Dolby TrueHD",
        dts = "DTS Digital Surround",
        aac = "AAC",
        mp3 = "MP3",
        flac = "FLAC",
        opus = "Opus",
        vorbis = "Vorbis"
    }

    local res = ""

    if c_lower:find("dts") or c_lower:find("dca") or ao_format:find("dts") or decoder_name:find("dts") then
        local info = table.concat({c_lower, desc, track_title, decoder_name, ao_format, c_profile}, " "):lower()

        if info:find("master audio") or info:find("hdma") or info:find("dts%-ma") or info:find("dtshd%-ma") or
            c_profile:find("ma") then
            res = "DTS-HD Master Audio"
        elseif info:find("high resolution") or info:find("dts%-hr") or info:find("dtshd%-hr") or c_profile:find("hr") then
            res = "DTS-HD High Resolution"
        elseif info:find("hd") or info:find("dtshd") then
            res = "DTS-HD"
        else
            res = "DTS Digital Surround"
        end
    elseif c_lower:find("pcm") or ao_format:find("pcm") then
        res = "PCM"
    else
        res = names[c_lower] or c_lower:upper()
    end

    if filename:lower():find("atmos") and not res:find("Atmos") then
        res = res .. " Atmos"
    end

    return res:gsub("%+", " Plus")
end

-- Get subtitle type description
local function get_readable_subtitle_type(track)
    if not track or not track.codec then
        return "Unknown"
    end

    local c = track.codec:lower()

    if c == "ass" or c == "ssa" then
        return mp.get_property("sub-ass-override", "no") == "no" and "Styled (ASS)" or "Text (ASS)"
    elseif c:find("pgs") or c:find("dvd") or c:find("hdmv") then
        return "Bitmap (PGS)"
    elseif c:find("srt") or c:find("subrip") or c:find("text") or c:find("webvtt") then
        return "Text (SRT)"
    else
        return c:upper()
    end
end

-- Get selected audio and subtitle tracks with indices
local function get_selected_tracks(tracks)
    local sel_audio, sel_sub
    local sel_audio_idx, sel_sub_idx = 0, 0
    local audio_cnt, sub_cnt = 0, 0

    for _, t in ipairs(tracks) do
        if t.type == "audio" and not t.external then
            audio_cnt = audio_cnt + 1
            if t.selected then
                sel_audio, sel_audio_idx = t, audio_cnt
            end
        elseif t.type == "sub" then
            sub_cnt = sub_cnt + 1
            if t.selected then
                sel_sub, sel_sub_idx = t, sub_cnt
            end
        end
    end

    return sel_audio, sel_audio_idx, sel_sub, sel_sub_idx, audio_cnt, sub_cnt
end

local function determine_video_fps()
    local fps = state.video_fps_actual

    if fps and fps > 0 then
        return fps
    end

    local v = mp.get_property_native("video-params") or {}
    fps = tonumber(v.fps) or nil

    if not fps and v.r_frame_rate then
        local n, d = v.r_frame_rate:match("(%d+)/(%d+)")
        n, d = tonumber(n), tonumber(d)
        if n and d and d ~= 0 then
            fps = n / d
        end
    end

    if not fps then
        local est = mp.get_property_number("estimated-vf-fps", 0)
        if est and est > 0 then
            fps = est
        end
    end

    return fps
end

-- Tone-Mapping
local function get_active_tonemapping_name()
    local tm = mp.get_property("tone-mapping")
    if not state.hdr_active or not tm or tm == "" or tm == "auto" then
        return "inactive"
    end

    if tm:lower() == "mobius" then
        return "Möbius"
    end

    return tm:sub(1, 1):upper() .. tm:sub(2)
end

-- 3dlut
local function get_active_lut_name()
    local lut = mp.get_property("target-lut")
    if lut and lut ~= "" and lut ~= "no" then
        return (lut:match("([^/\\]+)$") or lut):gsub("%.cube$", "")
    end
    return nil
end

-- ======================================
-- OSD STATIC
-- ======================================

local function generate_static_osd_info()
    local v_in = mp.get_property_native("video-params") or {}
    local v_codec = (mp.get_property("video-codec") or "unknown"):upper()
    local dw, dh = mp.get_property_number("width", 0), mp.get_property_number("height", 0)
    local avg_bitrate = state.avg_video_bitrate
    local video_bitrate_source = state.video_bitrate_source or "n/a"
    local filename = (state.video_path or ""):lower()
    local is_hdtv = filename:find("hdtv")
    local profile = state.display_profile or "Loading..."
    local prefix = (video_bitrate_source == "calc") and "~" or ""
    local avg_text = avg_bitrate and fmt_bitrate(avg_bitrate) or "n/a"
    local bitrate_display = avg_text

    state.video_name = get_video_name()
    state.osd_hdr_text = " " .. (state.hdr_type ~= "" and state.hdr_type or "SDR")

    local fps_val = determine_video_fps()
    if fps_val and fps_val > 0 then
        if math.abs(fps_val - 23.976) < 0.001 then
            state.osd_fps_display = "@23.976"
        else
            local fps_rounded = math.floor(fps_val + 0.5)
            if math.abs(fps_val - fps_rounded) < 0.001 then
                state.osd_fps_display = "@" .. fps_rounded
            else
                state.osd_fps_display = string.format("@%.2f", math.floor(fps_val * 100) / 100)
            end
        end
    else
        state.osd_fps_display = ""
    end

    if state.is_cartoon and (state.cartoon_multiplier or 1.0) > 1.0 then
        local orig_text = fmt_bitrate(avg_bitrate / state.cartoon_multiplier)
        local applied_text = fmt_bitrate(avg_bitrate)
        bitrate_display = string.format("%s (%s*c)", orig_text, applied_text)
    elseif state.fps_adjust_coeff and state.fps_adjust_coeff > 1.0 and not state.is_cartoon and not is_hdtv then
        local orig_text = fmt_bitrate(state.orig_video_bitrate)
        bitrate_display = string.format("%s (%s*f)", orig_text, avg_text)
    end

    if profile:find("^DVD") or profile:find("YouTube") then
        state.osd_profile_line = "Profile: " .. profile
    elseif avg_bitrate then
        if profile == "hdtv" then
            state.osd_profile_line = string.format("Profile: %s [%s%s Mbps @ %s]", string.upper(profile), prefix,
                bitrate_display, video_bitrate_source)
        else
            local prefix = (state.video_bitrate_source == "calc") and "~" or ""
            local x = state.raw_video_bitrate or 0
            local x_text = fmt_bitrate(x)
            local source = state.video_bitrate_source
            local codec, bit_depth = get_video_codec_and_depth()
            local depth_mult = BIT_DEPTH_MULTIPLIER[bit_depth] or 1.00
            local codec_div = get_codec_equiv_factor(codec, dw, dh) or 1.0
            local equiv = avg_bitrate / codec_div
            local hdr_div = state.hdr_active and get_hdr_normalization_factor(equiv) or 1.0
            local cartoon_mult = state.cartoon_multiplier or 1.0
            local fps_mult = 1.0
            if state.fps_adjust_coeff and state.fps_adjust_coeff > 1.0001 then
                fps_mult = 1 / state.fps_adjust_coeff
            end
            local y = x * cartoon_mult * fps_mult * depth_mult / codec_div / hdr_div
            local y_text = fmt_bitrate(y)
            local coeff_parts = {}
            if cartoon_mult ~= 1.0 then
                table.insert(coeff_parts, string.format("cartoon x%.2f", cartoon_mult))
            end
            if codec_div ~= 1.0 then
                table.insert(coeff_parts, string.format("codec /%.2f", codec_div))
            end
            if depth_mult ~= 1.0 then
                table.insert(coeff_parts, string.format("bit depth x%.2f", depth_mult))
            end
            if fps_mult ~= 1.0 then
                table.insert(coeff_parts, string.format("frame rate x%.2f", fps_mult))
            end
            if hdr_div ~= 1.0 then
                table.insert(coeff_parts, string.format("hdr /%.2f", hdr_div))
            end

            if #coeff_parts > 0 then
                local coeff_str = table.concat(coeff_parts, ", ")
                state.osd_profile_line = string.format("Profile: %s%s [%s%s Mbps @ %s] → [%s%s Mbps @ %s]", profile,
                    state.osd_hdr_text, prefix, x_text, source, prefix, y_text, coeff_str)
            else
                state.osd_profile_line = string.format("Profile: %s%s [%s%s Mbps @ %s]", profile, state.osd_hdr_text,
                    prefix, x_text, source)
            end
        end
    else
        state.osd_profile_line = string.format("Profile: %s%s [n/a]", profile, state.osd_hdr_text)
    end

    local tm_name = get_active_tonemapping_name()
    state.osd_tonemapping_line = "Tone-Mapping: " .. tm_name

    local lut = get_active_lut_name()
    if lut then
        state.osd_lut_line = "3D LUT: " .. lut
    else
        state.osd_lut_line = "3D LUT: inactive"
    end

    local deband = mp.get_property_native("deband")
    if deband and deband ~= "no" then
        state.osd_deband_line = string.format("Debanding: iterations=%s, threshold=%s, range=%s, grain=%s",
            mp.get_property_number("deband-iterations") or "-", mp.get_property_number("deband-threshold") or "-",
            mp.get_property_number("deband-range") or "-", mp.get_property_number("deband-grain") or "-")
    else
        state.osd_deband_line = "Debanding: inactive"
    end

    local shaders = mp.get_property_native("glsl-shaders") or {}
    local shader_lines = {}
    if #shaders > 0 then
        for i, s in ipairs(shaders) do
            local name = (s:match("([^/\\]+)$") or s):gsub("%.%w+$", "")
            local disp = name
            local fsrc, fsrc_params = name:match("^(FSRCNNX)_(.+)")
            if fsrc then
                disp = string.format("%s [%s]", fsrc, fsrc_params:gsub("_", " "))
            end
            local a = name:match("adaptive%-sharpen%-([0-9%.]+)")
            if a then
                disp = string.format("Adaptive Sharpen [%s]", a)
            end
            local c = name:match("CAS%-([0-9%.]+)")
            if c then
                disp = string.format("Contrast Adaptive Sharpening [%s]", c)
            end
            table.insert(shader_lines, string.format("　%d. %s", i, disp))
        end
        state.osd_shader_line = "Shaders:\\N" .. table.concat(shader_lines, "\\N")
    else
        state.osd_shader_line = "Shaders: inactive"
    end

    local _, bit_depth = get_video_codec_and_depth()
    local bit_depth_text = bit_depth .. "-bit"
    local pf_display
    if v_in.pixelformat and not v_in.pixelformat:match("cuda|dxva2|d3d11|nvdec") then
        pf_display = v_in.pixelformat
    else
        pf_display = mp.get_property("hwdec") or "sw"
    end

    state.osd_video_line_prefix = string.format("Video: %dx%d%s / %s / %s (%s) [", dw, dh, state.osd_fps_display,
        bit_depth_text, v_codec, pf_display)
    state.osd_video_line_suffix = " Mbps]"
end

-- ======================================
-- OSD DYNAMIC
-- ======================================

local function generate_dynamic_osd_info()
    local tracks = mp.get_property_native("track-list") or {}
    local sel_audio, sel_audio_idx, sel_sub, sel_sub_idx, audio_cnt, sub_cnt = get_selected_tracks(tracks)

    state.osd_audio_line = "Audio: none"
    if sel_audio then
        local ch = tonumber(sel_audio["audio-channels"]) or tonumber(sel_audio["demux-channels"]) or 0
        local chan_text = ch == 8 and "7.1" or ch == 6 and "5.1" or ch == 2 and "2.0" or ch == 1 and "1.0" or
                              tostring(ch) .. "ch"

        local abps_kbps_text = (state.audio_bitrate_kbps and state.audio_bitrate_kbps > 0) and
                                   string.format("%d kbps", math.floor(state.audio_bitrate_kbps)) or "n/a"

        state.osd_audio_line = string.format("Audio: [%s]%s | (%s %s @ %s) [%d/%d]", (sel_audio.lang or "und"):upper(),
            sel_audio.title and (" " .. sel_audio.title) or "", get_readable_audio_codec_name(sel_audio), chan_text,
            abps_kbps_text, sel_audio_idx, audio_cnt)
    end

    state.osd_subs_line = "Subs: none"
    if sel_sub then
        state.osd_subs_line = string.format("Subs: [%s]%s | %s [%d/%d]", (sel_sub.lang or "und"):upper(),
            sel_sub.title and (" " .. sel_sub.title) or "", get_readable_subtitle_type(sel_sub), sel_sub_idx, sub_cnt)
    end
end

-- ======================================
-- OSD DISPLAY
-- ======================================

local function display_osd()
    if not state.osd_visible then
        mp.set_osd_ass(0, 0, "")
        return
    end

    local v_bitrate_text = state.video_bitrate and string.format("%.1f", math.floor(state.video_bitrate * 10) / 10) or
                               "n/a"
    local duration = mp.get_property_number("duration", 0)
    local time_pos = mp.get_property_number("time-pos", 0)
    local rem_real = mp.get_property_number("playtime-remaining", 0)
    local progress = duration > 0 and math.floor((time_pos / duration) * 100) or 0
    local curr_time = os.date("%H:%M")
    local exit_time = format_eta_time(rem_real)

    local time_line = string.format("%s | %s [%d%%] %s (-%s) | %s", curr_time, format_time_hms(time_pos, true, true),
        progress, format_time_hms(duration, true, true), format_time_hms(duration - time_pos, true, true), exit_time)

    local video_line = state.osd_video_line_prefix .. v_bitrate_text .. state.osd_video_line_suffix

    local info_lines = {"{\\r}", "{\\r}", "{\\r}"}

    -- Name info
    table.insert(info_lines, state.video_name)
    table.insert(info_lines, "{\\r}")

    -- Time info
    table.insert(info_lines, time_line)
    table.insert(info_lines, "{\\r}")

    -- Video / Audio / Subs info
    table.insert(info_lines, video_line)
    table.insert(info_lines, state.osd_audio_line)
    table.insert(info_lines, state.osd_subs_line)
    table.insert(info_lines, "{\\r}")

    -- Tone-Mapping / 3D LUT info
    table.insert(info_lines, state.osd_tonemapping_line)
    table.insert(info_lines, state.osd_lut_line)
    table.insert(info_lines, "{\\r}")

    -- Profile / Debanding / Shaders info
    table.insert(info_lines, state.osd_profile_line)
    table.insert(info_lines, state.osd_deband_line)
    table.insert(info_lines, state.osd_shader_line)

    local osd_text = table.concat(info_lines, "\\N")
    mp.set_osd_ass(0, 0, osd_text)
end

-- ======================================
-- OSD TOGGLE FUNCTIONS
-- ======================================

local function show_osd()
    state.osd_visible = true
    if state.osd_timer then
        state.osd_timer:kill()
    end
    state.osd_timer = mp.add_periodic_timer(1, display_osd)
    display_osd()
end

local function hide_osd()
    state.osd_visible = false
    if state.osd_timer then
        state.osd_timer:kill()
        state.osd_timer = nil
    end
    mp.set_osd_ass(0, 0, "")
end

-- ======================================
-- RESET AND REFRESH FUNCTIONS
-- ======================================

local function reset_state()
    if state.osd_timer then
        state.osd_timer:kill()
        state.osd_timer = nil
    end

    for k, v in pairs(default_state) do
        state[k] = v
    end

    audio_bitrate_cache = {}
    ffprobe_cache = {}

    mp.set_property("deband", "no")
    mp.set_property_native("glsl-shaders", {})
    mp.set_osd_ass(0, 0, "")
end

-- ======================================
-- PROPERTY OBSERVERS
-- ======================================

-- Audio
mp.observe_property("audio-codec-name", "string", function(_, val)
    state.audio_codec_name = (val or ""):lower()
end)

mp.observe_property("audio-out-format", "string", function(_, val)
    state.audio_output_format = (val or ""):lower()
end)

mp.observe_property("audio-bitrate", "number", function(_, val)
    if type(val) == "number" and val > 0 then
        state.audio_bitrate_kbps = val / 1000
        generate_dynamic_osd_info()
    end
    if state.osd_visible then
        display_osd()
    end
end)

mp.observe_property("aid", "string", function()
    generate_dynamic_osd_info()
    if state.osd_visible then
        display_osd()
    end
end)

-- Subtitles
mp.observe_property("sid", "string", function()
    generate_dynamic_osd_info()
    if state.osd_visible then
        display_osd()
    end
end)

-- Video
mp.observe_property("video-out-params", "native", function()
    if update_hdr_profile() then
        generate_static_osd_info()
        if state.osd_visible then
            display_osd()
        end
    end
end)

mp.observe_property("video-bitrate", "number", function(_, val)
    if type(val) == "number" and val > 0 then
        state.video_bitrate = val / 1e6
    end
    if state.osd_visible then
        display_osd()
    end
end)

-- 3dlut
mp.observe_property("target-lut", "string", function()
    generate_static_osd_info()
    if state.osd_visible then
        display_osd()
    end
end)

-- Timing / Playback
mp.observe_property("duration", "number", function()
    if state.osd_visible then
        display_osd()
    end
end)

mp.observe_property("seeking", "bool", function(_, val)
    if not val and state.osd_visible then
        display_osd()
    end
end)

-- ======================================
-- EVENT HANDLERS
-- ======================================

mp.register_event("start-file", function()
    reset_state()
    state.cartoon_multiplier = 1.0
    state.is_cartoon = false
    state.profile_applied = false
    state.fps_adjust_coeff = nil
    state.orig_video_bitrate = nil
    state.avg_video_bitrate = nil
    state.raw_video_bitrate = nil
    quality_profile_cache = {}
end)

mp.register_event("file-loaded", function()
    state.video_path = mp.get_property("path") or ""
    state.profile_applied = false
    state.display_profile = nil
    state.avg_video_bitrate = nil
    state.video_bitrate_source = nil
    state.video_fps_actual = nil
    state.cartoon_multiplier = 1.0
    state.hdr_active = false
    state.hdr_type = ""
    state.osd_hdr_text = ""

    apply_video_quality_profile()
    generate_static_osd_info()
    generate_dynamic_osd_info()

    if state.osd_visible then
        display_osd()
    end
end)

mp.register_event("tracks-changed", function()
    audio_bitrate_cache = {}
end)

-- ======================================
-- KEY BINDINGS
-- ======================================

mp.add_key_binding("HOMEPAGE", "toggle-osd", function()
    if state.osd_visible then
        hide_osd()
    else
        show_osd()
    end
end)

mp.add_forced_key_binding("MENU", "hide-osd-on-menu", function()
    if state.osd_visible then
        hide_osd()
    end
    mp.command("script-binding stats/display-stats-toggle")
end, {
    repeatable = false
})
