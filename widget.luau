--!strict
local Tuxedo = require("./tuxedo_sysfs.luau")

function update()
  noctalia.setUpdateInterval(3000)

  local state = noctalia.state.get("tuxedo_keyboard") or {}
  local driverActive = (state.driverActive ~= false)

  barWidget.setGlyph("keyboard")

  if not driverActive then
    barWidget.setText("")
    barWidget.setTooltip("TUXEDO Keyboard Driver not detected")
    return
  end

  local brightness = state.brightness or 100
  local mode = state.activeLightingMode or "theme"
  local model = state.model or "TUXEDO Keyboard"

  local showPct = noctalia.getConfig("show_percentage")
  if showPct and brightness > 0 and mode ~= "off" then
    barWidget.setText(string.format("%d%%", brightness))
  else
    barWidget.setText("")
  end

  local statusMode = mode == "theme" and ("Theme (" .. (state.themeRole or "primary") .. ")")
    or mode == "spectrum" and "Rainbow Cycle"
    or mode == "breathe" and "Breathe"
    or mode == "off" and "Off"
    or (state.currentColorHex or mode)

  barWidget.setTooltip(string.format(
    "%s\nBrightness: %d%%\nEffect: %s\n(Click: panel | Right-click: sync theme | Scroll: brightness)",
    model, brightness, statusMode
  ))
end

function onClick()
  noctalia.togglePanel("detluck/tuxedo-keyboard:panel")
end

function onRightClick()
  noctalia.runAsync({"noctalia", "msg", "plugin", "detluck/tuxedo-keyboard:monitor", "all", "sync_theme"})
  noctalia.notify("Keyboard Lighting", "Synced backlight with active theme color")
end

function onScroll(axis: string, steps: number)
  local state = noctalia.state.get("tuxedo_keyboard") or {}
  local zones = state.zones or Tuxedo.discoverZones()
  if #zones == 0 then return end

  local currentBr = state.brightness or 100
  local delta = -steps * 10
  local newBr = math.clamp(currentBr + delta, 0, 100)

  state.brightness = newBr
  noctalia.state.set("tuxedo_keyboard", state)

  for _, z in ipairs(zones) do
    Tuxedo.setBrightness(newBr, z.path, z.maxBrightness)
  end

  noctalia.runAsync({"noctalia", "msg", "plugin", "detluck/tuxedo-keyboard:panel", "all", "refresh"})
end
