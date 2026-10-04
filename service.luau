--!strict
local Tuxedo = require("./tuxedo_sysfs.luau")

local spectrumHue = 0
local breathePhase = 0
local lastThemeHex = ""
local lastAppliedHexMap: { [string]: string } = {}
local lastHardwareBrightness: number = -1

function update()
  local state = noctalia.state.get("tuxedo_keyboard") or {}
  local zones = Tuxedo.discoverZones()

  if #zones == 0 then
    state.driverActive = false
    state.model = Tuxedo.getLaptopModel()
    state.zones = {}
    noctalia.state.set("tuxedo_keyboard", state)
    noctalia.setUpdateInterval(5000)
    return
  end

  state.driverActive = true
  state.model = state.model or Tuxedo.getLaptopModel()

  -- Read hardware brightness from primary zone
  local currentHwBrightness = Tuxedo.readBrightness(zones[1].path)
  if lastHardwareBrightness ~= currentHwBrightness and lastHardwareBrightness ~= -1 then
    -- Hardware brightness changed via Fn keys
    state.brightness = currentHwBrightness
    lastHardwareBrightness = currentHwBrightness
    noctalia.runAsync({"noctalia", "msg", "plugin", "detluck/tuxedo-keyboard:panel", "all", "refresh"})
  else
    lastHardwareBrightness = currentHwBrightness
    state.brightness = state.brightness or currentHwBrightness
  end

  -- Default settings
  if not state.activeLightingMode then
    state.activeLightingMode = "theme"
  end
  if not state.themeRole then
    state.themeRole = "primary"
  end
  if not state.selectedZone then
    state.selectedZone = "all"
  end

  local mode = state.activeLightingMode

  -- Animation 1: Rainbow / Spectrum Cycle
  if mode == "spectrum" then
    noctalia.setUpdateInterval(60)
    spectrumHue = (spectrumHue + 3) % 360
    for idx, z in ipairs(zones) do
      -- If multiple zones, offset hue for wave animation
      local offset = (#zones > 1) and ((idx - 1) * 60) or 0
      local h = (spectrumHue + offset) % 360
      local r, g, b = Tuxedo.hsvToRgb(h, 1.0, 1.0)
      Tuxedo.setColorRgb(r, g, b, z.path)
    end
    state.currentColorHex = string.format("#%02X%02X%02X", Tuxedo.hsvToRgb(spectrumHue, 1.0, 1.0))
    noctalia.state.set("tuxedo_keyboard", state)
    return
  end

  -- Animation 2: Breathe / Pulse
  if mode == "breathe" then
    noctalia.setUpdateInterval(50)
    breathePhase = (breathePhase + 0.08) % (2 * math.pi)
    local factor = 0.15 + 0.85 * (0.5 * (1 + math.sin(breathePhase)))
    local baseHex = state.currentColorHex or "#0080FF"
    local clean = baseHex:gsub("#", "")
    local br = tonumber(clean:sub(1, 2), 16) or 0
    local bg = tonumber(clean:sub(3, 4), 16) or 128
    local bb = tonumber(clean:sub(5, 6), 16) or 255
    local r = math.floor(br * factor)
    local g = math.floor(bg * factor)
    local b = math.floor(bb * factor)
    for _, z in ipairs(zones) do
      Tuxedo.setColorRgb(r, g, b, z.path)
    end
    noctalia.state.set("tuxedo_keyboard", state)
    return
  end

  -- Non-animated modes run at 1-second interval
  noctalia.setUpdateInterval(1000)

  -- Mode: Theme Sync
  if mode == "theme" then
    local role = state.themeRole or "primary"
    local themeHex = Tuxedo.getThemeColor(role)
    if themeHex ~= lastThemeHex then
      lastThemeHex = themeHex
      state.currentColorHex = themeHex
      for _, z in ipairs(zones) do
        Tuxedo.setColorHex(themeHex, z.path)
      end
      noctalia.log(string.format("Synced TUXEDO Keyboard to theme (%s): %s", role, themeHex))
      noctalia.state.set("tuxedo_keyboard", state)
      noctalia.runAsync({"noctalia", "msg", "plugin", "detluck/tuxedo-keyboard:panel", "all", "refresh"})
    end
    return
  end

  -- Mode: Off
  if mode == "off" then
    lastThemeHex = ""
    noctalia.state.set("tuxedo_keyboard", state)
    return
  end

  -- Static color modes (white, blue, green, custom)
  if state.currentColorHex and state.currentColorHex ~= lastAppliedHexMap["static"] then
    for _, z in ipairs(zones) do
      Tuxedo.setColorHex(state.currentColorHex, z.path)
    end
    lastAppliedHexMap["static"] = state.currentColorHex
  end

  noctalia.state.set("tuxedo_keyboard", state)
end

function onIpc(event: string, payload: string)
  local state = noctalia.state.get("tuxedo_keyboard") or {}
  local zones = Tuxedo.discoverZones()

  if event == "sync_theme" then
    state.activeLightingMode = "theme"
    lastThemeHex = "" -- force sync
    noctalia.state.set("tuxedo_keyboard", state)
    update()
  elseif event == "set_brightness" then
    local num = tonumber(payload)
    if num then
      state.brightness = math.clamp(num, 0, 100)
      for _, z in ipairs(zones) do
        Tuxedo.setBrightness(state.brightness, z.path, z.maxBrightness)
      end
      noctalia.state.set("tuxedo_keyboard", state)
    end
  elseif event == "set_color" then
    state.activeLightingMode = "custom"
    state.currentColorHex = payload:upper()
    for _, z in ipairs(zones) do
      Tuxedo.setColorHex(payload, z.path)
    end
    noctalia.state.set("tuxedo_keyboard", state)
  elseif event == "refresh" then
    update()
  end
end
