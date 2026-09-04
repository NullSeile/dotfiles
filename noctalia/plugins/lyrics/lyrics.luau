--!strict
-- Synchronized lyrics bar widget with karaoke highlighting.
-- Long lines keep the singing character centered in the widget.

-- One line of lyrics, published by the service, plus render-side flags.
export type LyricLine = {
  time: number, -- ms from song start; -1 marks unsynced/plain-text lyrics
  duration: number, -- ms; 0 when unknown
  text: string,
  chars: { number }?, -- per-character activation times in ms (enhanced lyrics)
  cue: boolean?, -- set on synthetic intro/interlude cue lines
  duration_inferred: boolean?, -- set when the fetcher estimated duration
}

type TrackState = {
  title: string,
  artist: string,
  album: string?,
  status: string,
  position: number, -- µs
  duration: number, -- µs
  playerInstance: string,
  trackId: string?,
  mediaUrl: string?,
}

type LineInfo = {
  key: string,
  index: number, -- 0 during the intro cue
  line: LyricLine,
  progress: number, -- 0..1 through the current line/cue
  synced: boolean,
  position: number?, -- ms into the song when synced
  cue: boolean?,
}

type RowOpts = {
  key: string?,
  follow: boolean?, -- keep the singing playhead centered in the viewport
  position: number?,
  useGradient: boolean?,
  solid: boolean?, -- skip karaoke coloring entirely
  dim: boolean?, -- fixed inactive color
  cascade: boolean?,
  wave: boolean?,
  typewriter: boolean?,
  blink: boolean?,
  opacity: number?,
  cue: boolean?,
  fontScale: number?,
}

noctalia.setUpdateInterval(33)

-- ── Settings (widget scope; see [[widget.setting]] in plugin.toml) ──────────

local function stateString(value: any, fallback: string): string
  return if type(value) == "string" then value else fallback
end

local function cfgString(key: string, fallback: string): string
  return stateString(noctalia.getConfig(key), fallback)
end

local function cfgNumber(key: string, fallback: number): number
  local value = noctalia.getConfig(key)
  return if type(value) == "number" then value else fallback
end

local function cfgBool(key: string, fallback: boolean): boolean
  local value = noctalia.getConfig(key)
  return if type(value) == "boolean" then value else fallback
end

local maxChars = cfgNumber("max_chars", 15)
local charWidth = cfgNumber("char_width", 9)
local gradientOn = cfgBool("gradient", true)
local animation = cfgString("animation", "fade")
local cueText = cfgString("cue_text", "•••••")
if cueText == "" then cueText = "•••••" end
local cueFontMode = cfgString("cue_font_mode", "follow")
local cueFontFamily = cfgString("cue_font_family", "sans-serif")
if cueFontFamily == "" then cueFontFamily = "sans-serif" end
local karaokeEnabled = cfgBool("karaoke_enabled", true)
local karaokeRequireTiming = cfgBool("karaoke_require_timing", true)
local fontFamily = cfgString("font_family", "")
local fontSize = cfgNumber("font_size", 0)
local fontWeight = cfgString("font_weight", "normal")
local fontStyle = cfgString("font_style", "normal")

local hideWhenPaused = cfgBool("hide_when_paused", false)
local hideWhenNoLyrics = cfgBool("hide_when_no_lyrics", false)
local lyricsOffsetMs = cfgNumber("lyrics_offset_ms", 0)
local activeColor = cfgString("active_color", "on_surface")
local inactiveColor = cfgString("inactive_color", "on_surface_variant")

-- ── Playback state mirrored from the service ────────────────────────────────

local track: TrackState? = nil
local lyrics: { LyricLine }? = nil
local playing = false
local playerInstance = ""
local sourceUsed = ""

local baselinePosition = 0 -- µs at baselineClock
local baselineClock = os.clock()
local lastClock = 0
local displayKey = ""
local displayedLine: LyricLine? = nil
local outgoingLine: LyricLine? = nil
local transitionElapsed = 0
local smoothProgress = 0

local FADE_OUT_MS = 130
local FADE_IN_MS = 260
local BLEND_MS = 350
local INTERLUDE_GAP_MS = 7000
local INTRO_MIN_MS = 6000
local INTERLUDE_MIN_MS = 5000

local function shellQuote(value: string): string
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function clamp(value: number, low: number, high: number): number
  return math.min(high, math.max(low, value))
end

local function easeOutCubic(t: number): number
  local u = 1 - clamp(t, 0, 1)
  return 1 - u * u * u
end

-- Split into grapheme-ish chunks (UTF-8 code points).
local function toChars(text: string): { string }
  local chars: { string } = {}
  local i = 1
  while i <= #text do
    local byte = text:byte(i) or 0
    local length = 1
    if byte >= 0xF0 then length = 4
    elseif byte >= 0xE0 then length = 3
    elseif byte >= 0xC0 then length = 2 end
    chars[#chars + 1] = text:sub(i, i + length - 1)
    i = i + length
  end
  return chars
end

-- Approximate width of a character in cells, relative to a CJK-width unit.
local function charUnits(char: string): number
  if char == " " or char == "\t" then return 0.35 end
  local byte = char:byte(1) or 0
  if byte < 0x80 then
    if char:match("[%.,:;!'|ilI%-%(%)]") then return 0.38 end
    if char:match("[MW@#%%&]") then return 0.85 end
    return 0.58
  end
  return 1
end

-- Playback position in ms. The service publishes raw µs snapshots; we
-- interpolate locally from the instant this widget received them so karaoke
-- stays smooth between polls without running ahead of the player.
local function getRawProgressMs(): number
  local elapsed = if playing then (os.clock() - baselineClock) * 1000 else 0
  return baselinePosition / 1000 + elapsed
end

local function getProgressMs(): number
  return getRawProgressMs() + lyricsOffsetMs
end

local function hasLyrics(): boolean
  local list = lyrics
  return list ~= nil and #list > 0 and track ~= nil
end

local function getLineInfo(): LineInfo?
  local list = lyrics
  local currentTrack = track
  if list == nil or #list == 0 or currentTrack == nil then return nil end

  local position = getProgressMs()
  if list[1].time < 0 then
    return { key = "plain", index = 1, line = list[1], progress = 0, synced = false }
  end

  local firstTime = list[1].time
  if firstTime >= INTRO_MIN_MS and position < firstTime then
    return {
      key = "intro",
      index = 0,
      line = { time = 0, duration = 0, text = cueText, cue = true },
      progress = clamp(position / firstTime, 0, 1),
      synced = true,
      position = position,
      cue = true,
    }
  end

  local index = 1
  for i = #list, 1, -1 do
    if list[i].time <= position then
      index = i
      break
    end
  end

  -- Storage-to-view: the same record carries the render flags (cue stays nil).
  local line = list[index]
  local startTime = line.time
  local durationMs: number? = if currentTrack.duration > 0 then currentTrack.duration / 1000 else nil
  local nextLine: LyricLine? = list[index + 1]
  local nextTime: number = if nextLine ~= nil then nextLine.time
    elseif durationMs ~= nil then durationMs
    else startTime + 4000
  local lineEnd = nextTime

  if line.duration ~= nil and line.duration > 0 and line.duration_inferred ~= true then
    lineEnd = math.min(nextTime, startTime + line.duration)
  elseif nextTime - startTime >= INTERLUDE_GAP_MS then
    -- LRC only marks line starts. Do not stretch a lyric across a long instrumental gap.
    local charTimes = line.chars
    local firstCharTime: number? = if charTimes ~= nil then charTimes[1] else nil
    local lastCharTime: number? = if charTimes ~= nil then charTimes[#charTimes] else nil
    local hasWordTiming = charTimes ~= nil and #charTimes >= 2
      and firstCharTime ~= nil and lastCharTime ~= nil and lastCharTime > firstCharTime
    if hasWordTiming and lastCharTime ~= nil and lastCharTime >= startTime and lastCharTime < nextTime then
      lineEnd = math.min(nextTime, lastCharTime + 600)
    else
      local estimatedDuration = clamp(#toChars(line.text) * 320, 3200, 6000)
      lineEnd = math.min(nextTime, startTime + estimatedDuration)
    end
  end

  -- Only show an interlude between two real lyric lines. The final lyric stays
  -- visible through the outro instead of turning the whole song ending into dots.
  -- if nextLine ~= nil and nextTime - lineEnd >= INTERLUDE_MIN_MS and position >= lineEnd then
  if nextTime - lineEnd >= INTERLUDE_MIN_MS and position >= lineEnd then
    return {
      key = "interlude-" .. tostring(index),
      index = index,
      line = { time = 0, duration = 0, text = cueText, cue = true },
      progress = clamp((position - lineEnd) / (nextTime - lineEnd), 0, 1),
      synced = true,
      position = position,
      cue = true,
    }
  end

  local progress = if lineEnd > startTime
    then clamp((position - startTime) / (lineEnd - startTime), 0, 1)
    else 1

  return {
    key = "line-" .. tostring(index),
    index = index,
    line = line,
    progress = progress,
    synced = true,
    position = position,
  }
end

local function trackKey(value: TrackState?): string
  if value == nil then return "" end
  local durationSeconds = math.floor(value.duration / 1000000)
  return value.playerInstance .. "|" .. (value.trackId or "") .. "|"
    .. value.title .. "|" .. value.artist .. "|" .. (value.album or "")
    .. "|" .. tostring(durationSeconds)
end

local function hasWordTiming(line: LyricLine?): boolean
  if line == nil then return false end
  local chars = line.chars
  if chars == nil or #chars < 2 then return false end
  local first = chars[1]
  for index = 2, #chars do
    if chars[index] ~= first then return true end
  end
  return false
end

local function getTrackLabel(): string
  local currentTrack = track
  if currentTrack == nil then return "--" end
  if currentTrack.artist ~= "" then
    return currentTrack.artist .. " - " .. currentTrack.title
  end
  return currentTrack.title
end

-- Distance in cells from the start of the line to the singing playhead.
-- Word-timed sources (Musixmatch richsync) repeat the same ms for every
-- character in a word. Spread those plateaus toward the next distinct time
-- (or line end) so karaoke moves smoothly, like non-enhanced progress.
local function expandCharTimes(times: { number }, lineEnd: number?): { number }
  local count = #times
  if count < 2 then return times end
  local expanded: { number } = {}
  local index = 1
  while index <= count do
    local runEnd = index
    while runEnd <= count and times[runEnd] == times[index] do
      runEnd += 1
    end
    local runStartTime = times[index]
    local runStopTime = if runEnd <= count then times[runEnd]
      elseif lineEnd ~= nil and lineEnd > runStartTime then lineEnd
      else runStartTime
    local runLength = runEnd - index
    if runLength > 1 and runStopTime > runStartTime then
      for offset = 0, runLength - 1 do
        expanded[index + offset] = runStartTime + math.floor(offset * (runStopTime - runStartTime) / runLength)
      end
    else
      for offset = 0, runLength - 1 do
        expanded[index + offset] = runStartTime
      end
    end
    index = runEnd
  end
  return expanded
end

local function playheadUnits(chars: { string }, times: { number }?, position: number?, progress: number): number
  local count = #chars
  if count == 0 then return 0 end
  local starts: { number } = {}
  local total = 0
  for index = 1, count do
    starts[index] = total
    total = total + charUnits(chars[index])
  end

  if times ~= nil and position ~= nil and #times >= count then
    local index = 1
    for i = 1, count do
      if times[i] <= position then
        index = i
      else
        break
      end
    end
    local here = starts[index] + charUnits(chars[index]) * 0.5
    if index < count and times[index + 1] > times[index] then
      local t = clamp((position - times[index]) / (times[index + 1] - times[index]), 0, 1)
      local there = starts[index + 1] + charUnits(chars[index + 1]) * 0.5
      return here + (there - here) * t
    end
    return here
  end

  return total * clamp(progress, 0, 1)
end

-- Slice a maxChars-wide window centered on playhead. lead/trail are 0..1 of
-- the edge characters that sit outside the viewport (used for opacity).
local function viewportRange(chars: { string }, playhead: number): (number, number, number, number, boolean)
  local count = #chars
  if count == 0 then return 1, 1, 0, 1, false end
  local starts: { number } = {}
  local total = 0
  for index = 1, count do
    starts[index] = total
    total = total + charUnits(chars[index])
  end
  if total <= maxChars then
    return 1, count, 0, 1, false
  end

  local startUnits = clamp(playhead - maxChars * 0.5, 0, total - maxChars)
  local endUnits = startUnits + maxChars
  local first = 1
  local lead = 0
  for index = 1, count do
    local width = charUnits(chars[index])
    if starts[index] + width > startUnits + 0.0001 then
      first = index
      lead = clamp((startUnits - starts[index]) / width, 0, 1)
      break
    end
  end

  local last = count
  local trail = 1
  for index = first, count do
    local width = charUnits(chars[index])
    if starts[index] + width >= endUnits - 0.0001 then
      last = index
      trail = clamp((endUnits - starts[index]) / width, 0, 1)
      break
    end
  end
  return first, last, lead, trail, true
end

local function karaokeColor(charTime: number?, charProgress: number, position: number?, useGradient: boolean): string
  if not playing then return inactiveColor end
  if charTime ~= nil and position ~= nil then
    if not useGradient then
      return if position >= charTime then activeColor else inactiveColor
    end
    if position >= charTime then return activeColor end
    local distance = charTime - position
    if distance >= BLEND_MS then return inactiveColor end
    local alpha = 1 - distance / BLEND_MS
    if alpha <= 0.5 then return inactiveColor end
    return activeColor .. "/" .. string.format("%.2f", math.max(0.72, alpha))
  end

  if not useGradient then
    return if smoothProgress >= charProgress then activeColor else inactiveColor
  end
  local distance = charProgress - smoothProgress
  if distance <= 0 then return activeColor end
  if distance >= 0.16 then return inactiveColor end
  local alpha = 1 - distance / 0.16
  if alpha <= 0.5 then return inactiveColor end
  return activeColor .. "/" .. string.format("%.2f", math.max(0.72, alpha))
end

local function labelBaseline(): string
  if fontStyle == "fixed" then return "textFixedHeight" end
  if fontStyle == "ink_centered" then return "inkCentered" end
  return "text"
end

local function buildLineRow(line: LyricLine | string, opts: RowOpts?): UiNode
  local options: RowOpts = if opts ~= nil then opts else {}
  local record: LyricLine?
  local text: string
  if type(line) == "table" then
    record = line
    text = line.text
  else
    record = nil
    text = line
  end
  local times: { number }? = if record ~= nil then record.chars else nil
  if times ~= nil and #times > 0 and record ~= nil then
    local lineEnd: number? = nil
    if record.duration > 0 then
      lineEnd = record.time + record.duration
    elseif options.position ~= nil then
      -- Fall back to current playback only as a soft bound for the last run.
      lineEnd = nil
    end
    times = expandCharTimes(times, lineEnd)
  end
  local isCue: boolean = if record ~= nil and record.cue == true then true else options.cue == true
  local chars: { string } = toChars(text)
  if #chars == 0 then chars = { " " } end

  local playhead = if options.follow == true
    then playheadUnits(chars, times, options.position, smoothProgress)
    else 0
  local first, last, lead, trail, windowed = viewportRange(chars, playhead)
  local labels: { UiNode } = {}

  for sourceIndex = first, last do
    local active = if playing then activeColor else inactiveColor
    local color = if options.dim == true
      then inactiveColor
      else active

    if options.solid ~= true and options.dim ~= true then
      local progress = if #chars > 1 then (sourceIndex - 1) / (#chars - 1) else 0
      local charTime: number? = if times ~= nil then times[sourceIndex] else nil
      color = karaokeColor(charTime, progress, options.position, options.useGradient == true)
    end

    local alpha = 1
    if windowed then
      if sourceIndex == first and lead > 0 then alpha = alpha * (1 - lead) end
      if sourceIndex == last and trail < 1 then alpha = alpha * trail end
    end
    if options.cascade == true then
      local charProgress = (sourceIndex - first) / math.max(1, last - first)
      local cascadeProgress = clamp((transitionElapsed - FADE_OUT_MS) / 420, 0, 1)
      alpha = alpha * clamp((cascadeProgress - charProgress * 0.45) * 2.4, 0.08, 1)
    end
    if options.wave == true then
      local waveProgress = clamp((transitionElapsed - FADE_OUT_MS) / 650, 0, 1)
      local wave = 0.55 + 0.45 * math.sin(waveProgress * math.pi * 2 - sourceIndex * 0.78)
      alpha = alpha * (wave * (1 - waveProgress) + waveProgress)
    end
    if options.typewriter == true then
      local reveal = clamp((transitionElapsed - FADE_OUT_MS) / 520, 0, 1)
      local threshold = (sourceIndex - first) / math.max(1, last - first + 1)
      alpha = alpha * (if reveal >= threshold then 1 else 0.08)
    end
    if options.blink == true and transitionElapsed < FADE_OUT_MS + 540 then
      local blink = math.floor(math.max(0, transitionElapsed - FADE_OUT_MS) / 90) % 2
      alpha = alpha * (if blink == 0 then 0.35 else 1)
    end

    local fontScale = options.fontScale or 1
    labels[#labels + 1] = ui.label({
      key = "char-" .. tostring(sourceIndex),
      text = chars[sourceIndex],
      color = color,
      opacity = alpha,
      maxLines = 1,
      fontFamily = if isCue and cueFontMode == "custom" then cueFontFamily
        elseif fontFamily ~= "" then fontFamily
        else nil,
      fontSize = if fontSize > 0 or fontScale < 1
          then math.max(6, (if fontSize > 0 then fontSize else 13) * fontScale)
        else nil,
      fontWeight = fontWeight,
      baseline = labelBaseline(),
    })
  end

  return ui.row({
    key = options.key or "line",
    gap = 0,
    align = "center",
    minWidth = maxChars * charWidth,
    opacity = options.opacity or 1,
  }, labels)
end

-- Crossfade: outgoing line while fading out, incoming line fading in.
local function currentTransitionLine(info: LineInfo?): (LyricLine?, number)
  if animation == "none" or transitionElapsed >= FADE_OUT_MS then
    local opacity: number = if animation == "none"
      then 1
      else easeOutCubic((transitionElapsed - FADE_OUT_MS) / FADE_IN_MS)
    if animation == "pulse" and transitionElapsed < FADE_OUT_MS + 600 then
      opacity = opacity * (0.76 + 0.24 * math.sin(math.max(0, transitionElapsed - FADE_OUT_MS) / 75))
    end
    return (if info ~= nil then info.line else nil), opacity
  end
  return outgoingLine, 1 - easeOutCubic(transitionElapsed / FADE_OUT_MS)
end

local SOURCE_NAMES: { [string]: string } = {
  lrclib = "LRCLIB", netease = "NetEase", qqmusic = "QQ Music", kugou = "Kugou",
  musixmatch = "Musixmatch", cache = "Cache", external = "External",
}

-- Runtime validation at the trust boundary: state published by the service is
-- untyped until these normalize it.
local function asLyricLines(value: any): { LyricLine }?
  if type(value) ~= "table" then return nil end
  local lines: { LyricLine } = {}
  for _, item in ipairs(value :: { any }) do
    if type(item) == "table" then
      local record = item :: { [string]: any }
      local text = record.text
      if type(text) == "string" and text ~= "" then
        lines[#lines + 1] = {
          time = if type(record.time) == "number" then record.time else -1,
          duration = if type(record.duration) == "number" then record.duration else 0,
          text = text,
          chars = if type(record.chars) == "table" then record.chars else {},
        }
      end
    end
  end
  if #lines == 0 then return nil end
  return lines
end

local function asTrack(value: any): TrackState?
  if type(value) ~= "table" then return nil end
  local record = value :: { [string]: any }
  if type(record.title) ~= "string" or type(record.position) ~= "number" then return nil end
  return {
    title = record.title :: string,
    artist = stateString(record.artist, ""),
    album = stateString(record.album, ""),
    status = stateString(record.status, ""),
    position = record.position :: number,
    duration = if type(record.duration) == "number" then record.duration else 0,
    playerInstance = stateString(record.playerInstance, ""),
    trackId = stateString(record.trackId, ""),
    mediaUrl = stateString(record.mediaUrl, ""),
  }
end

local function render()
  if (hideWhenPaused and not playing) or (hideWhenNoLyrics and not hasLyrics()) then
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)

  local useGradient = gradientOn
  local position = getProgressMs()
  local line: UiNode = nil

  local info = getLineInfo()
  if info ~= nil then
    local shownLine, opacity = currentTransitionLine(info)
    if shownLine ~= nil then
      local timedKaraoke = hasWordTiming(shownLine)
      local karaokeActive = karaokeEnabled and shownLine == info.line and info.synced
        and (not karaokeRequireTiming or timedKaraoke)
      line = buildLineRow(shownLine, {
        key = "current-" .. tostring(info.index),
        follow = shownLine == info.line and info.synced,
        position = position,
        useGradient = karaokeActive and useGradient,
        solid = not karaokeActive,
        cascade = karaokeActive and animation == "cascade",
        wave = karaokeActive and animation == "wave",
        typewriter = shownLine == info.line and animation == "typewriter",
        blink = shownLine == info.line and animation == "blink",
        opacity = opacity,
        cue = shownLine == info.line and info.cue == true,
      })
    end
  end

  barWidget.render(ui.row({ gap = 6, align = "center", opacity = if playing then 1 else 0.58 }, {line}))

  local tooltip = getTrackLabel()
  if sourceUsed ~= "" then
    tooltip = tooltip .. "\n" .. noctalia.tr("source_label") .. ": " .. (SOURCE_NAMES[sourceUsed] or sourceUsed)
  end
  if track ~= nil then
    tooltip = tooltip .. "\n" .. noctalia.tr("select_lyrics")
  end
  barWidget.setTooltip(tooltip)
end

function onClick()
  if track == nil then return end
  noctalia.togglePanel("nullptr/lyrics:selector")
end

function onRightClick()
  if playerInstance == "" then return end
  noctalia.runAsync("playerctl --player " .. shellQuote(playerInstance) .. " play-pause", function(result)
    if result.exitCode == 0 then
      local wasPlaying = playing
      if wasPlaying then baselinePosition = getRawProgressMs() * 1000 end
      playing = not wasPlaying
      noctalia.state.set("playing", playing)
      baselineClock = os.clock()
      render()
    end
  end)
end

function onScroll(axis: string, steps: number)
  if axis ~= "vertical" or playerInstance == "" then return end
  if steps == 0 then return end
  local action = if steps < 0 then "next" else "previous"
  noctalia.runAsync("playerctl --player " .. shellQuote(playerInstance) .. " " .. action, function() end)
end

function update()
  local now = os.clock()
  local delta = if lastClock > 0 then now - lastClock else 0
  lastClock = now

  track = asTrack(noctalia.state.get("track"))
  lyrics = asLyricLines(noctalia.state.get("lyrics"))
  playing = noctalia.state.get("playing") == true
  playerInstance = stateString(noctalia.state.get("player_instance"), "")
  sourceUsed = stateString(noctalia.state.get("lyrics_source_used"), "")

  local info = getLineInfo()
  local nextKey = if info ~= nil then info.key else "fallback"
  if nextKey ~= displayKey then
    outgoingLine = displayedLine
    displayKey = nextKey
    transitionElapsed = if animation == "none" then FADE_OUT_MS + FADE_IN_MS else 0
    smoothProgress = if info ~= nil then info.progress else 0
  else
    local target = if info ~= nil then info.progress else 0
    smoothProgress = smoothProgress + (target - smoothProgress) * math.min(1, delta * 8)
  end
  displayedLine = if info ~= nil then info.line else nil

  if playing then
    transitionElapsed = transitionElapsed + delta * 1000
  end

  render()
end

-- Interpolate from this widget's clock at receipt. The service's spawn-time
-- stamp is earlier than the D-Bus sample (playerctl still has to start and
-- query), so using it made the next line appear early. Spotify-lyrics avoids
-- that by displaying the last polled position as-is; we keep interpolation
-- for karaoke, but never start it before the snapshot arrives here.
noctalia.state.watch("position", function(value: any)
  baselinePosition = if type(value) == "number" then value else 0
  baselineClock = os.clock()
end)

noctalia.state.watch("lyrics", function(value: any)
  lyrics = asLyricLines(value)
  displayKey = ""
  displayedLine = nil
  outgoingLine = nil
end)

noctalia.state.watch("playing", function(value: any)
  -- Preserve the interpolated position when pausing between service polls.
  local nowPlaying = value == true
  if playing and not nowPlaying then
    baselinePosition = getRawProgressMs() * 1000
  end
  playing = nowPlaying
  baselineClock = os.clock()
end)
