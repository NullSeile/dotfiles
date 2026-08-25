--!nonstrict

local providerState = noctalia.state.get("lyrics_provider_state") or {}
local track = noctalia.state.get("track")

local PROVIDER_NAMES = {
  lrclib = "LRCLIB",
  netease = "NetEase",
  qqmusic = "QQ Music",
  kugou = "Kugou",
  musixmatch = "Musixmatch",
}

local PROVIDER_GLYPHS = {
  lrclib = "globe",
  netease = "cloud",
  qqmusic = "music-2",
  kugou = "disc",
  musixmatch = "microphone",
}

local function trackKey(value)
  if type(value) ~= "table" then return "" end
  local durationSeconds = math.floor((tonumber(value.duration) or 0) / 1000000)
  return (value.playerInstance or "") .. "|" .. (value.trackId or "") .. "|"
    .. (value.title or "") .. "|" .. (value.artist or "") .. "|" .. (value.album or "")
    .. "|" .. tostring(durationSeconds)
end

local function stateForTrack()
  if type(providerState) ~= "table" or providerState.track_key ~= trackKey(track) then return {} end
  return providerState
end

local function providerName(source)
  return PROVIDER_NAMES[tostring(source or "")] or tostring(source or "")
end

local function badge(text, color, fillAlpha)
  return ui.row({
    fill = color .. "/" .. tostring(fillAlpha),
    border = color .. "/0.22",
    borderWidth = 1,
    radius = 999,
    paddingH = 8,
    paddingV = 2,
    align = "center",
  }, {
    ui.label({ text = text, fontSize = 10, fontWeight = "medium", color = color }),
  })
end

local function selectProvider(source)
  local state = stateForTrack()
  if tostring(state.selected_source or "") == source or not track then return end
  -- Optimistic local update so the highlight moves immediately.
  providerState = {
    track_key = trackKey(track),
    providers = state.providers or {},
    selected_source = source,
    preferred_source = source,
    has_preference = true,
    loading = state.loading == true,
  }
  noctalia.state.set("lyrics_provider_request", {
    request_id = tostring(os.clock()) .. "-" .. source,
    action = "select",
    source = source,
    track_key = trackKey(track),
  })
  render()
end

local function clearPreference()
  local state = stateForTrack()
  if state.has_preference ~= true or not track then return end
  noctalia.state.set("lyrics_provider_request", {
    request_id = tostring(os.clock()) .. "-clear",
    action = "clear_preference",
    track_key = trackKey(track),
  })
end

local function providerRow(provider)
  local source = tostring(provider.source or "")
  local state = stateForTrack()
  local selected = source ~= "" and source == tostring(state.selected_source or "")
  local saved = source ~= "" and source == tostring(state.preferred_source or "") and state.has_preference == true
  local synced = provider.synced == true
  local enhanced = provider.enhanced == true
  local lineCount = tonumber(provider.line_count) or 0

  local badges = {}
  if synced then
    badges[#badges + 1] = badge(noctalia.tr("panel.synced"), "primary", "0.16")
  else
    badges[#badges + 1] = badge(noctalia.tr("panel.unsynced"), "on_surface_variant", "0.12")
  end
  if enhanced then
    badges[#badges + 1] = badge(noctalia.tr("panel.enhanced"), "tertiary", "0.18")
  end
  if saved then
    badges[#badges + 1] = badge(noctalia.tr("panel.saved"), "secondary", "0.16")
  end

  local badgeRow = {
    ui.label({
      text = tostring(lineCount) .. " " .. noctalia.tr("panel.lines"),
      fontSize = 11,
      color = "on_surface_variant",
    }),
  }
  for _, item in ipairs(badges) do badgeRow[#badgeRow + 1] = item end

  return ui.row({
    key = "provider-" .. source .. (selected and "-selected" or ""),
    gap = 12,
    align = "center",
    paddingH = 12,
    paddingV = 11,
    radius = 12,
    fill = selected and "primary/0.14" or "surface_container/0.45",
    border = selected and "primary/0.38" or "outline/0.18",
    borderWidth = 1,
    onClick = function()
      selectProvider(source)
    end,
  }, {
    ui.box({
      width = 36,
      height = 36,
      radius = 10,
      fill = selected and "primary/0.22" or "surface_variant/0.18",
      align = "center",
      justify = "center",
    }, {
      ui.glyph({
        name = PROVIDER_GLYPHS[source] or "file-music",
        size = 18,
        color = selected and "primary" or "on_surface_variant",
      }),
    }),
    ui.column({ flexGrow = 1, gap = 4, align = "stretch" }, {
      ui.label({
        text = providerName(source),
        fontSize = 14,
        fontWeight = selected and "semibold" or "medium",
        color = selected and "primary" or "on_surface",
        maxLines = 1,
      }),
      ui.row({ gap = 6, align = "center", wrap = true }, badgeRow),
    }),
    ui.glyph({
      name = selected and "check" or "chevron-right",
      size = selected and 18 or 16,
      color = selected and "primary" or "on_surface_variant",
    }),
  })
end

local function emptyState(glyph, text, subtext)
  local children = {
    ui.box({
      width = 52,
      height = 52,
      radius = 26,
      fill = "surface_variant/0.16",
      align = "center",
      justify = "center",
    }, {
      ui.glyph({ name = glyph, size = 24, color = "on_surface_variant" }),
    }),
    ui.label({ text = text, fontSize = 14, fontWeight = "medium", color = "on_surface", textAlign = "center" }),
  }
  if subtext ~= "" then
    children[#children + 1] = ui.label({
      text = subtext,
      fontSize = 11,
      color = "on_surface_variant",
      textAlign = "center",
      maxLines = 2,
    })
  end
  return ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 10, padding = 16 }, children)
end

local function trackSubtitle()
  if not track then return "" end
  local artist = tostring(track.artist or "")
  local title = tostring(track.title or "")
  if artist ~= "" and title ~= "" then return artist .. " — " .. title end
  if title ~= "" then return title end
  return artist
end

function render()
  local state = stateForTrack()
  local providers = type(state.providers) == "table" and state.providers or {}
  local loading = state.loading == true
  local hasPreference = state.has_preference == true
  local body = {}

  if not track then
    body[#body + 1] = emptyState("music-off", noctalia.tr("panel.no_track"), "")
  elseif #providers == 0 then
    body[#body + 1] = emptyState(
      loading and "loader-2" or "search-x",
      loading and noctalia.tr("panel.loading") or noctalia.tr("panel.no_providers"),
      loading and noctalia.tr("panel.loading_hint") or ""
    )
  else
    local rows = {}
    for _, provider in ipairs(providers) do rows[#rows + 1] = providerRow(provider) end
    if loading then
      rows[#rows + 1] = ui.row({ gap = 8, align = "center", paddingH = 4, paddingV = 2 }, {
        ui.glyph({ name = "loader", size = 14, color = "primary" }),
        ui.label({ text = noctalia.tr("panel.loading_more"), fontSize = 11, color = "on_surface_variant" }),
      })
    end
    body[#body + 1] = ui.scroll({ flexGrow = 1, gap = 8, padding = 2, align = "stretch" }, rows)
    if hasPreference then
      body[#body + 1] = ui.button({
        text = noctalia.tr("panel.clear_preference"),
        glyph = "restore",
        variant = "outline",
        onClick = clearPreference,
      })
    elseif #providers > 1 then
      body[#body + 1] = ui.label({
        text = noctalia.tr("panel.source_count", { count = #providers }),
        fontSize = 10,
        color = "on_surface_variant",
        textAlign = "center",
      })
    end
  end

  local headerActions = {}
  if hasPreference then
    headerActions[#headerActions + 1] = ui.button({
      glyph = "restore",
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("panel.clear_preference"),
      onClick = clearPreference,
    })
  end
  headerActions[#headerActions + 1] = ui.button({
    glyph = "close",
    variant = "ghost",
    controlSize = "sm",
    tooltip = noctalia.tr("panel.close"),
    onClick = "onCloseClicked",
  })

  panel.render(ui.column({ flexGrow = 1, gap = 0, align = "stretch" }, {
    ui.column({ gap = 10, paddingH = 16, paddingV = 14, align = "stretch" }, {
      ui.row({ align = "center", gap = 10 }, {
        ui.column({ flexGrow = 1, gap = 3 }, {
          ui.label({ text = noctalia.tr("panel.title"), fontSize = 15, fontWeight = "bold" }),
          ui.label({
            text = trackSubtitle(),
            color = "on_surface_variant",
            fontSize = 11,
            maxLines = 1,
          }),
        }),
        ui.row({ gap = 4, align = "center" }, headerActions),
      }),
      ui.separator(),
    }),
    ui.column({ flexGrow = 1, gap = 8, paddingH = 14, paddingBottom = 14, align = "stretch" }, body),
  }))
end

noctalia.state.watch("lyrics_provider_state", function(value)
  providerState = type(value) == "table" and value or {}
  render()
end)

noctalia.state.watch("track", function(value)
  track = value
  render()
end)

function onOpen(_context)
  noctalia.state.set("lyrics_selector_open", true)
  providerState = noctalia.state.get("lyrics_provider_state") or {}
  track = noctalia.state.get("track")
  render()
end

function onClose()
  noctalia.state.set("lyrics_selector_open", false)
end

function onCloseClicked()
  panel.close()
end

render()
