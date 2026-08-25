--!strict
-- Lyrics — headless service.
-- Polls MPRIS players via playerctl, resolves lyrics through fetch_lyrics.py
-- (LRCLIB, NetEase, QQ Music, Kugou, Musixmatch), and publishes playback state.

export type LyricLine = {
  time: number, -- ms from song start; -1 marks unsynced/plain-text lyrics
  duration: number, -- ms; 0 when unknown
  text: string,
  translation: string?,
  romanization: string?,
  chars: { number }?, -- per-character activation times in ms (enhanced lyrics)
}

type ServiceConfig = {
  poll_interval_ms: number,
  providers: { string },
  allow_plain_text: boolean,
  enhanced: boolean,
  translation_language: string,
}

type PlayerRow = {
  instance: string,
  name: string,
  status: string,
  title: string,
  artist: string,
  album: string,
  position: number, -- µs
  duration: number, -- µs
  artUrl: string,
  trackId: string,
  mediaUrl: string,
}

type TrackRecord = {
  title: string,
  artist: string,
  album: string,
  status: string,
  position: number, -- µs
  duration: number, -- µs
  playerInstance: string,
  trackId: string,
  mediaUrl: string,
}

type ProviderMeta = {
  source: string,
  synced: boolean,
  enhanced: boolean,
  line_count: number,
}

local updateIntervalMs = 100
noctalia.setUpdateInterval(updateIntervalMs)

local pluginDir = noctalia.pluginDir() or "/tmp"
local cacheDir = pluginDir .. "/.cache"
noctalia.mkdirAll(cacheDir)

local preferencesPath = cacheDir .. "/provider_preferences.json"
local maxPreferenceEntries = 500

local pendingRequests: { string } = noctalia.listDir(cacheDir) or {}
for _, name in ipairs(pendingRequests) do
  if name:match("^fetch_request_.*%.json$") then noctalia.removeFile(cacheDir .. "/" .. name) end
end

local config: ServiceConfig = {
  poll_interval_ms = 500,
  providers = {},
  allow_plain_text = true,
  enhanced = false,
  translation_language = "",
}

local resultsCache: { [string]: { [string]: { LyricLine } } } = {}
local providerPreferences: { [string]: string } = {}
local selectedSourceCache: { [string]: string } = {}
local lastTrackKey = ""
local currentTrack: TrackRecord? = nil
local currentPlayerInstance = ""
local fetchGeneration = 0
local pollInFlight = false
local pollElapsedMs = config.poll_interval_ms
local providerFetchLoading = false

local function shellQuote(value: string): string
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function normalizePatterns(value: any): { string }
  if type(value) ~= "table" then return {} end
  local patterns: { string } = {}
  for _, raw in ipairs(value :: { any }) do
    local pattern = (tostring(raw):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if pattern ~= "" then patterns[#patterns + 1] = pattern end
  end
  table.sort(patterns)
  return patterns
end

local function normalizeProviders(value: any): { string }
  if type(value) ~= "table" then return {} end
  local providers: { string } = {}
  local seen: { [string]: boolean } = {}
  for _, raw in ipairs(value :: { any }) do
    local name = (tostring(raw):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if name ~= "" and not seen[name] then
      providers[#providers + 1] = name
      seen[name] = true
    end
  end
  return providers
end

local playerAllowlist = normalizePatterns(noctalia.getConfig("player_allowlist"))
local playerBlocklist = normalizePatterns(noctalia.getConfig("player_blocklist"))

local function patternMatches(value: string, pattern: string): boolean
  local escaped = (pattern:gsub("([%%%^%$%(%)%.%[%]%+%-%?])", "%%%1"):gsub("%*", ".*"))
  local luaPattern = "^" .. escaped .. "$"
  return value:lower():match(luaPattern) ~= nil
end

local function matchesAny(player: PlayerRow, patterns: { string }): boolean
  for _, pattern in ipairs(patterns) do
    if patternMatches(player.name, pattern) or patternMatches(player.instance, pattern) then return true end
  end
  return false
end

local function playerAllowed(player: PlayerRow): boolean
  if #playerAllowlist > 0 and not matchesAny(player, playerAllowlist) then return false end
  return not matchesAny(player, playerBlocklist)
end

local function selectPlayer(players: { PlayerRow }): PlayerRow?
  local best: PlayerRow? = nil
  local bestRank = -1
  for _, player in ipairs(players) do
    if playerAllowed(player) then
      local rank = if player.status == "playing" then 2 elseif player.status == "paused" then 1 else 0
      if rank > bestRank or (rank == bestRank and player.instance == currentPlayerInstance) then
        best = player
        bestRank = rank
      end
    end
  end
  return best
end

type KeyableTrack = {
  playerInstance: string?, trackId: string?, title: string?,
  artist: string?, album: string?, duration: number?,
}

local function trackKey(track: KeyableTrack): string
  local durationSeconds = math.floor((track.duration or 0) / 1000000)
  return (track.playerInstance or "") .. "|" .. (track.trackId or "") .. "|"
    .. (track.title or "") .. "|" .. (track.artist or "") .. "|" .. (track.album or "")
    .. "|" .. tostring(durationSeconds)
end

local function contentKey(track: KeyableTrack): string
  local durationSeconds = math.floor((track.duration or 0) / 1000000)
  return (track.title or "") .. "|" .. (track.artist or "") .. "|" .. (track.album or "")
    .. "|" .. tostring(durationSeconds)
end

local function evictResultsCache()
  local keys: { string } = {}
  for key, _ in pairs(resultsCache) do keys[#keys + 1] = key end
  if #keys > 30 then
    table.sort(keys)
    for index = 1, #keys - 30 do resultsCache[keys[index]] = nil end
  end
end

local function loadProviderPreferences()
  local raw, _err = noctalia.readFile(preferencesPath)
  if raw == nil or raw == "" then
    providerPreferences = {}
    return
  end
  local decoded = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then
    providerPreferences = {}
    return
  end
  local nextPreferences: { [string]: string } = {}
  for key, value in pairs(decoded :: { [string]: any }) do
    if type(key) == "string" and type(value) == "string" and value ~= "" then
      nextPreferences[key] = value
    end
  end
  providerPreferences = nextPreferences
end

local function saveProviderPreferences()
  local keys: { string } = {}
  for key, _ in pairs(providerPreferences) do keys[#keys + 1] = key end
  if #keys > maxPreferenceEntries then
    table.sort(keys)
    for index = 1, #keys - maxPreferenceEntries do
      providerPreferences[keys[index]] = nil
    end
  end
  local encoded = noctalia.json.encode(providerPreferences)
  if encoded ~= nil then noctalia.writeFile(preferencesPath, encoded) end
end

local function rememberProvider(track: KeyableTrack, source: string)
  if source == "" or source == "cache" or source == "external" then return end
  local key = contentKey(track)
  if key == "|||0" then return end
  providerPreferences[key] = source
  saveProviderPreferences()
end

local function forgetProvider(track: KeyableTrack)
  local key = contentKey(track)
  if providerPreferences[key] == nil then return false end
  providerPreferences[key] = nil
  saveProviderPreferences()
  return true
end

local function savedPreference(track: KeyableTrack): string?
  local saved = providerPreferences[contentKey(track)]
  if saved == nil or saved == "" then return nil end
  return saved
end

local function clearPlayerState()
  fetchGeneration = fetchGeneration + 1
  currentPlayerInstance = ""
  currentTrack = nil
  lastTrackKey = ""
  providerFetchLoading = false
  noctalia.state.set("player_instance", nil)
  noctalia.state.set("player_name", nil)
  noctalia.state.set("track", nil)
  noctalia.state.set("lyrics", nil)
  noctalia.state.set("lyrics_source_used", nil)
  noctalia.state.set("lyrics_provider_state", nil)
  noctalia.state.set("playing", false)
end

local function loadConfig()
  config.poll_interval_ms = math.max(100, tonumber(tostring(noctalia.getConfig("poll_interval_ms"))) or 500)
  config.providers = normalizeProviders(noctalia.getConfig("providers"))
  config.allow_plain_text = noctalia.getConfig("allow_plain_text") ~= false
  config.enhanced = noctalia.getConfig("enhanced") == true
  local language = tostring(noctalia.getConfig("translation_language") or "")
  config.translation_language = if language == "none" then "" else language
end

local function asCharTimes(value: any): { number }
  local times: { number } = {}
  if type(value) ~= "table" then return times end
  for _, raw in ipairs(value :: { any }) do
    if type(raw) == "number" then times[#times + 1] = raw :: number end
  end
  return times
end

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
          translation = if type(record.translation) == "string" then record.translation else "",
          romanization = if type(record.romanization) == "string" then record.romanization else "",
          chars = asCharTimes(record.chars),
        }
      end
    end
  end
  if #lines == 0 then return nil end
  return lines
end

local function lineIsEnhanced(line: LyricLine): boolean
  local chars = line.chars
  if chars == nil or #chars < 2 then return false end
  local first = chars[1]
  for index = 2, #chars do
    if chars[index] ~= first then return true end
  end
  return false
end

local function linesAreEnhanced(lines: { LyricLine }): boolean
  for _, line in ipairs(lines) do
    if lineIsEnhanced(line) then return true end
  end
  return false
end

-- Prefer enhanced (word/char-timed) results. A saved preference only wins
-- among that preferred pool, so a non-enhanced favorite does not beat an
-- enhanced alternative for the same track.
local function preferredProvider(track: KeyableTrack, available: { string }): string?
  if #available == 0 then return nil end
  local bucket = resultsCache[trackKey(track)]
  local pool = available
  if bucket ~= nil then
    local enhanced: { string } = {}
    for _, source in ipairs(available) do
      local lines = bucket[source]
      if lines ~= nil and linesAreEnhanced(lines) then
        enhanced[#enhanced + 1] = source
      end
    end
    if #enhanced > 0 then pool = enhanced end
  end

  local saved = providerPreferences[contentKey(track)]
  if saved ~= nil and saved ~= "" then
    for _, source in ipairs(pool) do
      if source == saved then return saved end
    end
  end
  for _, configured in ipairs(config.providers) do
    for _, source in ipairs(pool) do
      if configured == source then return source end
    end
  end
  return pool[1]
end

local function providerMetaFor(source: string, lines: { LyricLine }): ProviderMeta
  local synced = lines[1].time >= 0
  return {
    source = source,
    synced = synced,
    enhanced = synced and linesAreEnhanced(lines),
    line_count = #lines,
  }
end

local function providerListFor(trackKeyValue: string): { ProviderMeta }
  local bucket = resultsCache[trackKeyValue]
  if bucket == nil then return {} end
  local providers: { ProviderMeta } = {}
  for _, configured in ipairs(config.providers) do
    local lines = bucket[configured]
    if lines ~= nil then providers[#providers + 1] = providerMetaFor(configured, lines) end
  end
  for source, lines in pairs(bucket) do
    local seen = false
    for _, configured in ipairs(config.providers) do
      if configured == source then seen = true break end
    end
    if not seen then providers[#providers + 1] = providerMetaFor(source, lines) end
  end
  return providers
end

local function availableSources(trackKeyValue: string): { string }
  local bucket = resultsCache[trackKeyValue]
  if bucket == nil then return {} end
  local sources: { string } = {}
  local seen: { [string]: boolean } = {}
  for _, configured in ipairs(config.providers) do
    if bucket[configured] ~= nil and not seen[configured] then
      sources[#sources + 1] = configured
      seen[configured] = true
    end
  end
  for source, _ in pairs(bucket) do
    if not seen[source] then
      sources[#sources + 1] = source
      seen[source] = true
    end
  end
  return sources
end

local function publishProviderState(track: TrackRecord?, loading: boolean)
  if track == nil then
    noctalia.state.set("lyrics_provider_state", nil)
    return
  end
  local tk = trackKey(track)
  local preference = savedPreference(track)
  noctalia.state.set("lyrics_provider_state", {
    track_key = tk,
    providers = providerListFor(tk),
    selected_source = selectedSourceCache[tk] or "",
    preferred_source = preference or "",
    has_preference = preference ~= nil,
    loading = loading,
  })
end

local function applyProvider(track: TrackRecord, source: string, remember: boolean)
  local tk = trackKey(track)
  local bucket = resultsCache[tk]
  if bucket == nil then return false end
  local lines = bucket[source]
  if lines == nil then return false end
  selectedSourceCache[tk] = source
  noctalia.state.set("lyrics", lines)
  noctalia.state.set("lyrics_source_used", source)
  if remember then rememberProvider(track, source) end
  publishProviderState(track, false)
  return true
end

local function applyBestProvider(track: TrackRecord)
  local tk = trackKey(track)
  local sources = availableSources(tk)
  if #sources == 0 then return end
  local chosen = preferredProvider(track, sources)
  if chosen ~= nil then applyProvider(track, chosen, false) end
end

local function tableHasEntries(value: { [string]: { LyricLine } }): boolean
  for _, _ in pairs(value) do return true end
  return false
end

local function applyText(text: string?, sourceUsed: string?): boolean
  local lines: { LyricLine } = {}
  local seenLyric = false
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local mins, secs = line:match("%[(%d+):(%d+%.?%d*)%]")
    local body = (line:gsub("%[%d+:%d+%.?%d*%]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if mins ~= nil and secs ~= nil and body ~= "" then
      lines[#lines + 1] = {
        time = math.floor((tonumber(mins) or 0) * 60000 + (tonumber(secs) or 0) * 1000),
        duration = 0, text = body, translation = "", romanization = "", chars = {},
      }
      seenLyric = true
    elseif body ~= "" and (seenLyric or body:find(":", 1, true) == nil) then
      lines[#lines + 1] = { time = -1, duration = 0, text = body, translation = "", romanization = "", chars = {} }
      seenLyric = true
    end
  end
  if #lines == 0 then return false end
  noctalia.state.set("lyrics", lines)
  if sourceUsed ~= nil and sourceUsed ~= "" then noctalia.state.set("lyrics_source_used", sourceUsed) end
  publishProviderState(currentTrack, false)
  return true
end

local function fetchLyrics(track: TrackRecord)
  local tk = trackKey(track)
  local cached = resultsCache[tk]
  if cached ~= nil then
    applyBestProvider(track)
    return
  end

  fetchGeneration = fetchGeneration + 1
  local generation = fetchGeneration
  providerFetchLoading = true
  publishProviderState(track, true)

  local requestPath = cacheDir .. "/fetch_request_" .. tostring(generation) .. ".json"
  local encoded = noctalia.json.encode({
    track = {
      title = track.title,
      artist = track.artist,
      album = track.album,
      duration = math.floor(track.duration / 1000000),
    },
    options = {
      providers = config.providers,
      allow_plain_text = config.allow_plain_text,
      enhanced = config.enhanced,
      lang = config.translation_language,
      fetch_all = true,
    },
  })
  if encoded == nil or not noctalia.writeFile(requestPath, encoded) then
    providerFetchLoading = false
    publishProviderState(track, false)
    return
  end

  local command = "python3 " .. shellQuote(pluginDir .. "/fetch_lyrics.py") .. " " .. shellQuote(requestPath)
  local started = noctalia.runAsync(command, function(result)
    noctalia.removeFile(requestPath)
    providerFetchLoading = false
    if generation ~= fetchGeneration or tk ~= lastTrackKey then return end

    local errorText: string? = nil
    local bucket: { [string]: { LyricLine } } = {}
    if result.exitCode == 0 then
      local decoded = noctalia.json.decode(result.stdout)
      if type(decoded) == "table" then
        local response = decoded :: { [string]: any }
        if response.type == "all" and type(response.results) == "table" then
          for _, item in ipairs(response.results :: { any }) do
            if type(item) == "table" then
              local record = item :: { [string]: any }
              local source = if type(record.source) == "string" then record.source else ""
              local lines = asLyricLines(record.lines)
              if source ~= "" and lines ~= nil then bucket[source] = lines end
            end
          end
        elseif response.type == "lyrics" then
          local source = if type(response.source) == "string" then response.source else ""
          local lines = asLyricLines(response.lines)
          if source ~= "" and lines ~= nil then bucket[source] = lines end
        end
        if type(response.error) == "string" and (response.error :: string) ~= "" then
          errorText = response.error :: string
        end
      end
    end

    for line in tostring(result.stderr or ""):gmatch("[^\n]+") do
      local trimmed = (line:gsub("^%s+", ""):gsub("%s+$", ""))
      if trimmed ~= "" then noctalia.log(trimmed) end
    end

    if tableHasEntries(bucket) then
      resultsCache[tk] = bucket
      evictResultsCache()
      applyBestProvider(track)
      local selected = selectedSourceCache[tk] or ""
      noctalia.log('lyrics: loaded ' .. tostring(#availableSources(tk)) .. ' providers for "' .. track.title .. '"'
        .. (if selected ~= "" then ', using ' .. selected else ""))
    else
      noctalia.state.set("lyrics", nil)
      noctalia.state.set("lyrics_source_used", nil)
      publishProviderState(track, false)
      noctalia.log('lyrics: fetch failed for "' .. track.title .. '": ' .. (errorText or "unknown error"))
    end
  end, 45000)
  if not started then
    noctalia.removeFile(requestPath)
    providerFetchLoading = false
    publishProviderState(track, false)
  end
end

local function applyPlayer(selected: PlayerRow)
  currentPlayerInstance = selected.instance
  noctalia.state.set("player_instance", selected.instance)
  noctalia.state.set("player_name", selected.name)

  local playing = selected.status == "playing"
  if selected.title == "" and selected.artist == "" then
    fetchGeneration = fetchGeneration + 1
    currentTrack = nil
    lastTrackKey = ""
    providerFetchLoading = false
    noctalia.state.set("track", nil)
    noctalia.state.set("lyrics", nil)
    noctalia.state.set("lyrics_source_used", nil)
    noctalia.state.set("lyrics_provider_state", nil)
    noctalia.state.set("playing", playing)
    return
  end

  local track: TrackRecord = {
    title = selected.title,
    artist = selected.artist,
    album = selected.album,
    status = selected.status,
    position = selected.position,
    duration = selected.duration,
    playerInstance = selected.instance,
    trackId = selected.trackId,
    mediaUrl = selected.mediaUrl,
  }
  currentTrack = track
  noctalia.state.set("position", track.position)

  local tk = trackKey(track)
  if tk == lastTrackKey then
    noctalia.state.set("track", track)
    noctalia.state.set("playing", playing)
    return
  end

  lastTrackKey = tk
  noctalia.state.set("track", track)
  noctalia.state.set("playing", playing)
  noctalia.state.set("lyrics", nil)
  noctalia.state.set("lyrics_source_used", nil)
  fetchLyrics(track)
end

local function poll()
  if pollInFlight then return end
  pollInFlight = true
  local cmd = [[playerctl --all-players metadata --format "$(printf '{{playerInstance}}\037{{playerName}}\037{{lc(status)}}\037{{title}}\037{{artist}}\037{{album}}\037{{position}}\037{{mpris:length}}\037{{mpris:artUrl}}\037{{mpris:trackid}}\037{{xesam:url}}\036')" 2>/dev/null]]

  local started = noctalia.runAsync(cmd, function(result)
    pollInFlight = false
    if result.exitCode ~= 0 or result.stdout == "" then
      clearPlayerState()
      return
    end

    local players: { PlayerRow } = {}
    local fieldSeparator = string.char(31)
    local recordSeparator = string.char(30)
    for record in (result.stdout .. recordSeparator):gmatch("(.-)" .. recordSeparator) do
      if record ~= "" then
        local parts: { [number]: string? } = {}
        for field in (record .. fieldSeparator):gmatch("(.-)" .. fieldSeparator) do
          parts[#parts + 1] = (field:gsub("^%s+", ""):gsub("%s+$", ""))
        end
        local player: PlayerRow = {
          instance = parts[1] or "",
          name = parts[2] or "",
          status = parts[3] or "stopped",
          title = parts[4] or "",
          artist = parts[5] or "",
          album = parts[6] or "",
          position = tonumber(parts[7]) or 0,
          duration = tonumber(parts[8]) or 0,
          artUrl = parts[9] or "",
          trackId = parts[10] or "",
          mediaUrl = parts[11] or "",
        }
        if player.instance ~= "" or player.name ~= "" then players[#players + 1] = player end
      end
    end

    local selected = selectPlayer(players)
    if selected == nil then
      clearPlayerState()
      return
    end
    applyPlayer(selected)
  end)
  if not started then pollInFlight = false end
end

function update()
  pollElapsedMs = pollElapsedMs + updateIntervalMs
  if pollElapsedMs >= config.poll_interval_ms then
    pollElapsedMs = 0
    poll()
  end
end

function onIpc(event: string, payload: string?)
  if event == "push-lrc" then
    applyText(payload, "external")
  elseif event == "clear" then
    fetchGeneration = fetchGeneration + 1
    noctalia.state.set("lyrics", nil)
    noctalia.state.set("lyrics_source_used", nil)
    publishProviderState(currentTrack, false)
  end
end

local function fetchOptionsSignature(): string
  return table.concat({
    table.concat(config.providers, "\n"),
    tostring(config.allow_plain_text),
    tostring(config.enhanced),
    config.translation_language,
  }, "\0")
end

function onConfigChanged()
  local previousOptions = fetchOptionsSignature()
  loadConfig()
  local optionsChanged = previousOptions ~= fetchOptionsSignature()
  local nextAllowlist = normalizePatterns(noctalia.getConfig("player_allowlist"))
  local nextBlocklist = normalizePatterns(noctalia.getConfig("player_blocklist"))
  local playersChanged = table.concat(nextAllowlist, "\n") ~= table.concat(playerAllowlist, "\n")
    or table.concat(nextBlocklist, "\n") ~= table.concat(playerBlocklist, "\n")
  playerAllowlist = nextAllowlist
  playerBlocklist = nextBlocklist

  if playersChanged then
    currentPlayerInstance = ""
    fetchGeneration = fetchGeneration + 1
    pollInFlight = false
    poll()
  elseif optionsChanged and currentTrack ~= nil then
    resultsCache = {}
    selectedSourceCache = {}
    fetchGeneration = fetchGeneration + 1
    lastTrackKey = ""
    noctalia.state.set("lyrics", nil)
    fetchLyrics(currentTrack)
  end
end

noctalia.state.watch("lyrics_provider_request", function(request)
  if type(request) ~= "table" or currentTrack == nil then return end
  local record = request :: { [string]: any }
  local action = tostring(record.action or "select")
  if tostring(record.track_key or "") ~= trackKey(currentTrack) then return end

  if action == "clear_preference" then
    if forgetProvider(currentTrack) then
      noctalia.log('lyrics: cleared saved preference for "' .. currentTrack.title .. '"')
    end
    applyBestProvider(currentTrack)
    return
  end

  local source = tostring(record.source or "")
  if source == "" then return end
  if source == selectedSourceCache[trackKey(currentTrack)] then
    -- Still persist if the user re-confirms the same source as a preference.
    rememberProvider(currentTrack, source)
    publishProviderState(currentTrack, false)
    return
  end
  if applyProvider(currentTrack, source, true) then
    noctalia.log('lyrics: switched to ' .. source .. ' for "' .. currentTrack.title .. '"')
  end
end)

loadConfig()
loadProviderPreferences()
poll()
