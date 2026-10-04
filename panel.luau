--!strict
local Tuxedo = require("./tuxedo_sysfs.luau")

local function tr(key: string, defaultText: string): string
  if type(noctalia.tr) == "function" then
    local res = noctalia.tr(key)
    if res and res ~= "" and res ~= key then
      return res
    end
  end
  return defaultText
end

local THEME_ROLES = {
  "primary",
  "on_primary",
  "secondary",
  "on_secondary",
  "tertiary",
  "on_tertiary",
  "surface",
  "on_surface",
  "surface_variant",
  "on_surface_variant",
  "hover",
  "on_hover",
  "outline",
  "shadow",
  "error",
  "on_error",
}

local QUICK_SWATCHES = {
  "#FFFFFF", -- White
  "#0080FF", -- Tuxedo Blue
  "#00FF00", -- Razer Green
  "#FF0055", -- Neon Pink
  "#FF5500", -- Amber / Orange
  "#00E5FF", -- Cyan
  "#BD93F9", -- Lavender
  "#FF3333", -- Red
}

local lastRenderedSignature = ""

function onOpen()
  lastRenderedSignature = ""
  update()
end

function onIpc(event: string, payload: string)
  if event == "refresh" then
    lastRenderedSignature = ""
    update()
  end
end

function update()
  local state = noctalia.state.get("tuxedo_keyboard") or {}
  local zones = state.zones or Tuxedo.discoverZones()
  local driverActive = (state.driverActive ~= false and #zones > 0)
  local brightness = state.brightness or 100
  local activeMode = state.activeLightingMode or "theme"
  local currentRole = state.themeRole or "primary"
  local activeColor = state.currentColorHex or "#0080FF"
  local isMenuOpen = (state.roleMenuOpen == true)
  local selectedZone = state.selectedZone or "all"

  -- Build state signature to skip redundant renders
  local themeHex = Tuxedo.getThemeColor(currentRole)
  local sig = string.format("%s:%s:%d:%s:%s:%s:%s:%s:%s",
    tostring(driverActive), tostring(#zones), brightness, activeMode,
    currentRole, tostring(isMenuOpen), selectedZone, activeColor, themeHex)

  if sig == lastRenderedSignature and lastRenderedSignature ~= "" then
    return
  end
  lastRenderedSignature = sig

  -- Case 1: Driver not detected
  if not driverActive then
    panel.render(ui.column({ gap = 12, padding = 16, align = "center" }, {
      ui.glyph({ name = "alert-triangle", size = 32, color = "error" }),
      ui.label({ text = tr("ui.driver_not_found", "TUXEDO Keyboard Driver Not Detected"), fontWeight = "bold", fontSize = 14 }),
      ui.label({
        text = tr("ui.driver_not_found_hint", "Make sure tuxedo-drivers is installed and the tuxedo_keyboard kernel module is loaded:\nmodprobe tuxedo_keyboard"),
        textAlign = "center",
        color = "on_surface_variant",
        fontSize = 12,
      }),
      ui.button({
        text = tr("ui.refresh", "Refresh"),
        variant = "primary",
        onClick = function()
          noctalia.runAsync({"noctalia", "msg", "plugin", "detluck/tuxedo-keyboard:monitor", "all", "refresh"})
        end
      }),
    }))
    return
  end

  -- Case 2: Connected keyboard controls
  local children = {}

  -- Title row
  table.insert(children, ui.row({ align = "center", justify = "space_between", paddingV = 4 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "keyboard", size = 20, color = "primary" }),
      ui.label({ text = tr("ui.panel_title", "Keyboard Backlight Control"), fontWeight = "bold", fontSize = 15 }),
    }),
    ui.button({
      glyph = "refresh",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("ui.refresh", "Refresh"),
      onClick = function()
        noctalia.runAsync({"noctalia", "msg", "plugin", "detluck/tuxedo-keyboard:monitor", "all", "refresh"})
      end
    })
  }))

  table.insert(children, ui.separator({ spacing = 8 }))

  -- Device Card
  local cardChildren = {}

  -- Device Header & Model Info
  local modelName = state.model or Tuxedo.getLaptopModel()
  table.insert(cardChildren, ui.row({ align = "center", justify = "space_between", paddingV = 4 }, {
    ui.row({ gap = 10, align = "center" }, {
      ui.glyph({ name = "keyboard", size = 28, color = "primary" }),
      ui.column({ gap = 2 }, {
        ui.label({ text = modelName, fontWeight = "bold", fontSize = 13 }),
        ui.label({
          text = (#zones > 1) and string.format(tr("ui.multi_zone", "%d RGB Zones Detected"), #zones) or tr("ui.single_zone", "Single-Zone RGB Backlight"),
          fontSize = 11,
          color = "on_surface_variant"
        }),
      }),
    }),
    ui.label({
      text = (activeMode == "off" or brightness == 0) and tr("ui.off", "Off") or (brightness .. "%"),
      color = (activeMode == "off" or brightness == 0) and "on_surface_variant" or "primary",
      fontSize = 12,
      fontWeight = "bold",
    })
  }))

  table.insert(cardChildren, ui.separator({ spacing = 6 }))

  -- Helper to apply color to active target zone(s)
  local function applyColorToTargets(hex)
    for _, z in ipairs(zones) do
      if selectedZone == "all" or selectedZone == z.id then
        Tuxedo.setColorHex(hex, z.path)
      end
    end
  end

  -- Zone Tabs (when multi-zone is detected)
  if #zones > 1 then
    local zoneTabs = {}
    table.insert(zoneTabs, ui.button({
      text = tr("ui.all_zones", "All Zones"),
      variant = (selectedZone == "all") and "primary" or "outline",
      controlSize = "sm",
      onClick = function()
        state.selectedZone = "all"
        noctalia.state.set("tuxedo_keyboard", state)
        lastRenderedSignature = ""
        update()
      end
    }))
    for _, z in ipairs(zones) do
      table.insert(zoneTabs, ui.button({
        text = z.name,
        variant = (selectedZone == z.id) and "primary" or "outline",
        controlSize = "sm",
        onClick = function()
          state.selectedZone = z.id
          noctalia.state.set("tuxedo_keyboard", state)
          lastRenderedSignature = ""
          update()
        end
      }))
    end
    table.insert(cardChildren, ui.row({ gap = 6, paddingV = 4 }, zoneTabs))
  end

  -- Brightness Slider
  table.insert(cardChildren, ui.row({ align = "center", justify = "space_between", paddingV = 2 }, {
    ui.label({ text = tr("ui.brightness", "LED Brightness"), fontSize = 12, fontWeight = "bold" }),
    ui.label({ text = brightness .. "%", fontSize = 12, color = "on_surface_variant" }),
  }))
  table.insert(cardChildren, ui.slider({
    min = 0, max = 100, step = 5, value = brightness, controlSize = "sm",
    onChange = function(val)
      local num = tonumber(val) or 100
      state.brightness = num
      noctalia.state.set("tuxedo_keyboard", state)
      lastRenderedSignature = ""
      update()
      for _, z in ipairs(zones) do
        Tuxedo.setBrightness(num, z.path, z.maxBrightness)
      end
    end
  }))

  -- Lighting Effect Header & Status
  table.insert(cardChildren, ui.row({ align = "center", justify = "space_between", paddingV = 2 }, {
    ui.label({ text = tr("ui.lighting_effect", "Lighting Effect"), fontSize = 12, fontWeight = "bold" }),
    ui.label({
      text = activeMode == "theme" and (tr("ui.theme_sync", "Theme Sync") .. " (" .. currentRole .. ")")
        or activeMode == "white" and tr("ui.white", "White")
        or activeMode == "blue" and tr("ui.tuxedo_blue", "Tuxedo Blue")
        or activeMode == "green" and tr("ui.razer_green", "Razer Green")
        or activeMode == "spectrum" and tr("ui.spectrum", "Rainbow Cycle")
        or activeMode == "breathe" and tr("ui.breathe", "Breathe")
        or activeMode == "custom" and activeColor
        or tr("ui.off", "Off"),
      fontSize = 11,
      color = "primary",
      fontWeight = "bold"
    }),
  }))

  -- Row 1: Presets & Theme Sync
  table.insert(cardChildren, ui.row({ gap = 6, justify = "space_between", paddingV = 2 }, {
    ui.button({
      text = tr("ui.theme_sync", "Theme Sync"),
      variant = (activeMode == "theme") and "primary" or "outline",
      selected = (activeMode == "theme"),
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        state.activeLightingMode = "theme"
        noctalia.state.set("tuxedo_keyboard", state)
        lastRenderedSignature = ""
        update()
        local colHex, found = Tuxedo.getThemeColor(currentRole)
        applyColorToTargets(colHex)
        state.currentColorHex = colHex
        if found then
          noctalia.notify("Keyboard Lighting", tr("ui.theme_synced", "Theme role set to: ") .. currentRole .. " (" .. colHex .. ")")
        end
      end
    }),
    ui.button({
      text = tr("ui.white", "White"),
      variant = (activeMode == "white") and "primary" or "outline",
      selected = (activeMode == "white"),
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        state.activeLightingMode = "white"
        state.currentColorHex = "#FFFFFF"
        noctalia.state.set("tuxedo_keyboard", state)
        lastRenderedSignature = ""
        update()
        applyColorToTargets("#FFFFFF")
      end
    }),
    ui.button({
      text = tr("ui.tuxedo_blue", "Tuxedo Blue"),
      variant = (activeMode == "blue") and "primary" or "outline",
      selected = (activeMode == "blue"),
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        state.activeLightingMode = "blue"
        state.currentColorHex = "#0080FF"
        noctalia.state.set("tuxedo_keyboard", state)
        lastRenderedSignature = ""
        update()
        applyColorToTargets("#0080FF")
      end
    }),
    ui.button({
      text = tr("ui.razer_green", "Razer Green"),
      variant = (activeMode == "green") and "primary" or "outline",
      selected = (activeMode == "green"),
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        state.activeLightingMode = "green"
        state.currentColorHex = "#00FF00"
        noctalia.state.set("tuxedo_keyboard", state)
        lastRenderedSignature = ""
        update()
        applyColorToTargets("#00FF00")
      end
    }),
  }))

  -- Row 2: Animations & Off
  table.insert(cardChildren, ui.row({ gap = 6, justify = "space_between", paddingV = 2 }, {
    ui.button({
      text = tr("ui.spectrum", "Rainbow Cycle"),
      variant = (activeMode == "spectrum") and "primary" or "outline",
      selected = (activeMode == "spectrum"),
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        state.activeLightingMode = "spectrum"
        noctalia.state.set("tuxedo_keyboard", state)
        lastRenderedSignature = ""
        update()
      end
    }),
    ui.button({
      text = tr("ui.breathe", "Breathe"),
      variant = (activeMode == "breathe") and "primary" or "outline",
      selected = (activeMode == "breathe"),
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        state.activeLightingMode = "breathe"
        noctalia.state.set("tuxedo_keyboard", state)
        lastRenderedSignature = ""
        update()
      end
    }),
    ui.button({
      text = tr("ui.off", "Off"),
      variant = (activeMode == "off") and "primary" or "ghost",
      selected = (activeMode == "off"),
      controlSize = "sm",
      onClick = function()
        state.activeLightingMode = "off"
        noctalia.state.set("tuxedo_keyboard", state)
        lastRenderedSignature = ""
        update()
        for _, z in ipairs(zones) do
          Tuxedo.setBrightness(0, z.path, z.maxBrightness)
        end
      end
    }),
  }))

  -- Palette Role Selector (when Theme Sync is active)
  if activeMode == "theme" then
    local currentHex = Tuxedo.getThemeColor(currentRole)

    table.insert(cardChildren, ui.row({ align = "center", justify = "space_between", paddingV = 2 }, {
      ui.label({ text = tr("ui.theme_role", "Palette Role"), fontSize = 12, fontWeight = "bold" }),
      ui.row({
        align = "center",
        justify = "space_between",
        gap = 8,
        paddingH = 10,
        paddingV = 5,
        fill = "surface_variant/0.5",
        radius = 6,
        border = isMenuOpen and "primary" or "outline",
        borderWidth = 1,
        onClick = function()
          state.roleMenuOpen = not isMenuOpen
          noctalia.state.set("tuxedo_keyboard", state)
          lastRenderedSignature = ""
          update()
        end
      }, {
        ui.row({ align = "center", gap = 8 }, {
          ui.box({
            width = 14,
            height = 14,
            radius = 7,
            fill = currentHex,
            border = "outline",
            borderWidth = 1,
          }),
          ui.label({ text = currentRole, fontSize = 12, fontWeight = "bold" }),
        }),
        ui.glyph({
          name = isMenuOpen and "chevron-up" or "chevron-down",
          size = 14,
          color = isMenuOpen and "primary" or "on_surface_variant",
        }),
      })
    }))

    -- Dropdown menu showing color preview chips for each role
    if isMenuOpen then
      local menuItems = {}
      for _, rName in ipairs(THEME_ROLES) do
        local rHex = Tuxedo.getThemeColor(rName)
        local isSelected = (currentRole == rName)
        table.insert(menuItems, ui.row({
          key = "menu-item-" .. rName,
          align = "center",
          justify = "space_between",
          paddingH = 8,
          paddingV = 6,
          radius = 6,
          fill = isSelected and "primary/0.2" or "transparent",
          onClick = function()
            state.themeRole = rName
            state.roleMenuOpen = false
            state.activeLightingMode = "theme"
            noctalia.state.set("tuxedo_keyboard", state)
            lastRenderedSignature = ""
            update()

            local roleHex = Tuxedo.getThemeColor(rName)
            applyColorToTargets(roleHex)
            state.currentColorHex = roleHex
            noctalia.notify("Keyboard Lighting", tr("ui.theme_synced", "Theme role set to: ") .. rName .. " (" .. roleHex .. ")")
          end
        }, {
          ui.row({ align = "center", gap = 8 }, {
            ui.box({
              width = 14,
              height = 14,
              radius = 7,
              fill = rHex,
              border = isSelected and "primary" or "outline",
              borderWidth = 1,
            }),
            ui.label({
              text = rName,
              fontSize = 12,
              fontWeight = isSelected and "bold" or "normal",
              color = isSelected and "primary" or "on_surface",
            }),
          }),
          ui.row({ align = "center", gap = 6 }, {
            ui.label({
              text = rHex,
              fontSize = 11,
              color = isSelected and "primary" or "on_surface_variant",
            }),
            ui.label({
              text = isSelected and "✓" or "",
              fontSize = 12,
              fontWeight = "bold",
              color = "primary",
            }),
          })
        }))
      end

      table.insert(cardChildren, ui.column({
        gap = 2,
        padding = 6,
        radius = 8,
        fill = "surface_variant/0.3",
        border = "outline",
        borderWidth = 1,
      }, menuItems))
    end
  end

  -- Function to apply a custom hex color code
  local function applyCustomHex(rawHex)
    if not rawHex or rawHex == "" then return end
    local clean = rawHex:gsub("#", "")
    if #clean == 3 then
      clean = clean:sub(1,1):rep(2) .. clean:sub(2,2):rep(2) .. clean:sub(3,3):rep(2)
    end
    if #clean ~= 6 then
      noctalia.notifyError("Keyboard Color", "Invalid color hex. Example: #FF0055")
      return
    end
    local formatted = "#" .. clean:upper()
    state.activeLightingMode = "custom"
    state.currentColorHex = formatted
    state.customColorInput = formatted
    noctalia.state.set("tuxedo_keyboard", state)
    lastRenderedSignature = ""
    update()
    applyColorToTargets(formatted)
    noctalia.notify("Keyboard Color", "Backlight set to " .. formatted)
  end

  -- Custom Hex & Color Picker Row
  table.insert(cardChildren, ui.row({ gap = 6, align = "center", paddingV = 4 }, {
    ui.input({
      value = state.customColorInput or activeColor or "#",
      placeholder = tr("ui.custom_color_placeholder", "Hex color (e.g. #FF0055)"),
      controlSize = "sm",
      flexGrow = 1,
      onChange = function(val)
        state.customColorInput = val
        noctalia.state.set("tuxedo_keyboard", state)
      end,
      onSubmit = function(val)
        applyCustomHex(val)
      end
    }),
    ui.button({
      glyph = "palette",
      tooltip = tr("ui.picker", "Color Picker"),
      variant = "outline",
      controlSize = "sm",
      onClick = function()
        if type(noctalia.openColorPicker) == "function" then
          local currentHex = activeColor
          if not currentHex or #currentHex ~= 7 or currentHex:sub(1,1) ~= "#" then
            currentHex = "#0080FF"
          end
          noctalia.openColorPicker(currentHex, function(selectedHex)
            if selectedHex and selectedHex ~= "" then
              applyCustomHex(selectedHex)
            end
          end)
        end
      end
    }),
    ui.button({
      text = tr("ui.set", "Set"),
      variant = "outline",
      controlSize = "sm",
      onClick = function()
        applyCustomHex(state.customColorInput)
      end
    })
  }))

  -- Quick Palette Swatches Row
  local swatchButtons = {}
  for _, col in ipairs(QUICK_SWATCHES) do
    table.insert(swatchButtons, ui.box({
      key = "quick-swatch-" .. col,
      width = 24,
      height = 24,
      radius = 12,
      fill = col,
      border = (activeColor == col) and "primary" or "outline",
      borderWidth = (activeColor == col) and 2 or 1,
      onClick = function()
        applyCustomHex(col)
      end
    }))
  end
  table.insert(cardChildren, ui.row({ justify = "space_between", align = "center", paddingV = 4 }, swatchButtons))

  table.insert(children, ui.column({
    gap = 8, padding = 12, fill = "surface_variant/0.4", radius = 10
  }, cardChildren))

  panel.render(ui.column({ gap = 8, padding = 14, width = 430, height = 550 }, children))
end
