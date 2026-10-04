--!strict
-- Tuxedo / Clevo Keyboard Backlight Hardware Layer via Linux sysfs
local Tuxedo = {}

local LEDS_DIR = "/sys/class/leds"

local function readSysfs(path: string): string?
  if type(noctalia.readFile) == "function" then
    local ok, content = pcall(noctalia.readFile, path)
    if ok and content and #content > 0 then
      return content
    end
  end
  return nil
end

local function writeSysfs(path: string, content: string): boolean
  if type(noctalia.writeFile) == "function" then
    local ok, res = pcall(noctalia.writeFile, path, content)
    if ok and res == true then
      return true
    end
  end
  if type(noctalia.runAsync) == "function" then
    noctalia.runAsync({"sh", "-c", string.format("echo '%s' > '%s'", content:gsub("'", ""):gsub("\n", ""), path)})
    return true
  end
  return false
end

export type KeyboardZone = {
  id: string,
  name: string,
  path: string,
  isMulticolor: boolean,
  maxBrightness: number,
}

function Tuxedo.getLaptopModel(): string
  local prod = readSysfs("/sys/class/dmi/id/product_name")
  if prod then
    prod = prod:gsub("[\r\n]+", ""):match("^%s*(.-)%s*$")
    if prod and #prod > 0 and prod ~= "None" then
      return prod
    end
  end
  local board = readSysfs("/sys/class/dmi/id/board_name")
  if board then
    board = board:gsub("[\r\n]+", ""):match("^%s*(.-)%s*$")
    if board and #board > 0 and board ~= "None" then
      return board
    end
  end
  return "TUXEDO / Clevo Laptop"
end

function Tuxedo.discoverZones(): { KeyboardZone }
  local zones: { KeyboardZone } = {}

  -- Standard candidate paths in sysfs
  local candidates = {
    { path = LEDS_DIR .. "/rgb:kbd_backlight", name = "Full Keyboard" },
    { path = LEDS_DIR .. "/rgb:kbd_backlight_1", name = "Zone 1 (Left)" },
    { path = LEDS_DIR .. "/rgb:kbd_backlight_2", name = "Zone 2 (Center)" },
    { path = LEDS_DIR .. "/rgb:kbd_backlight_3", name = "Zone 3 (Right)" },
    { path = LEDS_DIR .. "/rgb:kbd_backlight:left", name = "Left Zone" },
    { path = LEDS_DIR .. "/rgb:kbd_backlight:center", name = "Center Zone" },
    { path = LEDS_DIR .. "/rgb:kbd_backlight:right", name = "Right Zone" },
    { path = LEDS_DIR .. "/white:kbd_backlight", name = "White Backlight" },
  }

  for i, cand in ipairs(candidates) do
    local maxBrStr = readSysfs(cand.path .. "/max_brightness")
    if maxBrStr then
      local maxBr = tonumber(maxBrStr:match("(%d+)")) or 255
      local multiIndex = readSysfs(cand.path .. "/multi_index")
      local isMc = (multiIndex ~= nil and multiIndex:find("red") ~= nil)
      table.insert(zones, {
        id = "zone_" .. i,
        name = cand.name,
        path = cand.path,
        isMulticolor = isMc,
        maxBrightness = maxBr,
      })
    end
  end

  -- If multiple zones found, rename first full keyboard to Zone 1 if needed
  if #zones == 3 and zones[1].name == "Full Keyboard" then
    zones[1].name = "Zone 1 (Left)"
    zones[2].name = "Zone 2 (Center)"
    zones[3].name = "Zone 3 (Right)"
  end

  return zones
end

function Tuxedo.readBrightness(zonePath: string): number
  local str = readSysfs(zonePath .. "/brightness")
  local maxStr = readSysfs(zonePath .. "/max_brightness")
  local val = tonumber(str and str:match("(%d+)")) or 0
  local maxVal = tonumber(maxStr and maxStr:match("(%d+)")) or 255
  if maxVal <= 0 then return 0 end
  return math.clamp(math.floor((val / maxVal) * 100 + 0.5), 0, 100)
end

function Tuxedo.setBrightness(pct: number, zonePath: string, maxBrightness: number?)
  local maxVal = maxBrightness or 255
  local target = math.clamp(math.floor((pct / 100) * maxVal + 0.5), 0, maxVal)
  writeSysfs(zonePath .. "/brightness", tostring(target) .. "\n")
end

function Tuxedo.readColorHex(zonePath: string): string
  local str = readSysfs(zonePath .. "/multi_intensity")
  if str then
    local r, g, b = str:match("(%d+)%s+(%d+)%s+(%d+)")
    if r and g and b then
      local rn = tonumber(r) or 0
      local gn = tonumber(g) or 0
      local bn = tonumber(b) or 0
      return string.format("#%02X%02X%02X", rn, gn, bn)
    end
  end
  return "#FFFFFF"
end

function Tuxedo.setColorRgb(r: number, g: number, b: number, zonePath: string)
  local rn = math.clamp(math.floor(r), 0, 255)
  local gn = math.clamp(math.floor(g), 0, 255)
  local bn = math.clamp(math.floor(b), 0, 255)
  writeSysfs(zonePath .. "/multi_intensity", string.format("%d %d %d\n", rn, gn, bn))
end

function Tuxedo.setColorHex(hex: string, zonePath: string)
  local clean = hex:gsub("#", "")
  if #clean == 3 then
    clean = clean:sub(1,1):rep(2) .. clean:sub(2,2):rep(2) .. clean:sub(3,3):rep(2)
  end
  if #clean ~= 6 then return end
  local r = tonumber(clean:sub(1, 2), 16) or 255
  local g = tonumber(clean:sub(3, 4), 16) or 255
  local b = tonumber(clean:sub(5, 6), 16) or 255
  Tuxedo.setColorRgb(r, g, b, zonePath)
end

function Tuxedo.hsvToRgb(h: number, s: number, v: number): (number, number, number)
  local c = v * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = v - c
  local r1, g1, b1 = 0, 0, 0
  if h < 60 then
    r1, g1, b1 = c, x, 0
  elseif h < 120 then
    r1, g1, b1 = x, c, 0
  elseif h < 180 then
    r1, g1, b1 = 0, c, x
  elseif h < 240 then
    r1, g1, b1 = 0, x, c
  elseif h < 300 then
    r1, g1, b1 = x, 0, c
  else
    r1, g1, b1 = c, 0, x
  end
  return math.floor((r1 + m) * 255), math.floor((g1 + m) * 255), math.floor((b1 + m) * 255)
end

function Tuxedo.getThemeColor(role: string?): (string, boolean)
  local targetRole = role or "primary"
  if type(noctalia.getColor) == "function" then
    local hex = noctalia.getColor(targetRole)
    if hex and type(hex) == "string" and #hex >= 4 then
      return hex:upper(), true
    end
  end
  -- Fallback to Tuxedo Blue
  return "#0080FF", false
end

return Tuxedo
