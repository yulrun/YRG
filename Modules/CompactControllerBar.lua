local _, YRG = ...

-- CompactControllerBar: TriggerBar integrated as a YRG module (One-Bar mode only).
-- Displays only when Gamepad/Controller UI is active, using clean Blizzard Settings UI
-- controls with deferred menu-safe layout updates to prevent controller binding taint.

local CFG = {
    BUTTON_SIZE = 32,
    ROUND_BUTTON_SIZE = 30,
    GROUP_GAP = 12,
    LABEL_SPACE = 24,
    PRESSED_NUDGE_Y = -2,
    PLATE_INSETS = { left = 9, top = 9, right = 9, bottom = 9 },
    PADDING_RANGE = { 0, 16 },
    SCALE_RANGE = { 0.5, 1.5 },
    STEP = 0.05,
    STEPS_PER_UNIT = 20,

    -- Blizzard class/pet/stance overlay buttons (LT+LB / RT+RB)
    CLASS_BUTTON_X = 138,
    CLASS_BUTTON_Y = -50,
    CLASS_BUTTON_SIZE = 38,
    CLASS_PROMPT_Y = -80,
    CLASS_PROMPT_WIDTH = 72,
    CLASS_PROMPT_HEIGHT = 24,
    CLASS_BUTTON_SIDES = { DRUID = "Left", PALADIN = "Left", WARRIOR = "Right", HUNTER = "Both", WARLOCK = "Both" },
    CLASS_FRAMES = { "LeftClassAction", "RightClassAction", "LeftInputPrompt", "RightInputPrompt" },
    PROMPT_SCALE = 0.50,

    GUIDE_ICON = 18,
    GUIDE_GAP = 2,
    TOOLS_WIDTH = 104,
    SCREEN_MARGIN = 4,
    FIRST_RUN_MARGIN = 24,
    CENTRE_SNAP = 8,

    DEFAULT_ACCENT = { 1, 0.82, 0 },
    INACTIVE_COLOR = { 0.65, 0.65, 0.65 },
    GLYPH_SIZE = 18,
    GLYPH_CORNER_X = -19,
    GLYPH_CORNER_Y = 19,
    GLYPH_BELOW_DEFAULT = 7,
    GLYPH_BELOW_RANGE = { 0, 24 },
    LABEL_INSET_X = 6,
    LABEL_INSET_Y = 2,
    PAGE_SPACING = 5,
    AVAILABLE_PAGE_COLOR = { 0.9, 0.9, 0.9 },
    EMPTY_PAGE_COLOR = { 0.5, 0.5, 0.5 },
    EMPTY_PAGE_STATE = 3,
    MIN_BAR_ALPHA = 0.05,
    GUIDE_UNLIT_ALPHA = 0.4,
    FLASH_COUNT = 3,
    FLASH_PEAK = 0.5,
    FLASH_SECONDS = 0.25,
    PADDED_W = 76,
    PADDED_H = 75,
    PADDED_TC = { 0.015, 0.96, 0.015, 0.94 },

    SIDES = { "Left", "Right" },
    BUTTONS_PER_GROUP = 4,
    ROW_POS_XYBA = { 1, 2, 3, 4 }, -- Left, Up, Right, Down / X, Y, B, A
    ROW_POS_XYAB = { 1, 2, 4, 3 }, -- Left, Up, Down, Right / X, Y, A, B

    SECTIONS = {
        { anchorKey = "TopCenteredAnchor" },
        { anchorKey = "LeftCenteredAnchor" },
        { anchorKey = "RightCenteredAnchor" },
        { anchorKey = "BottomCenteredAnchor" },
    },
    TRIGGER_NAMES = {
        Generic = { "LT", "RT" },
        Letters = { "LT", "RT" },
        Shapes  = { "L2", "R2" },
        Reverse = { "ZL", "ZR" },
    },
    TRIGGER_KEYS = {
        GAMEPAD_TRIGGER_LEFT or "PADLTRIGGER",
        GAMEPAD_TRIGGER_RIGHT or "PADRTRIGGER",
    },
    SECTION_TRIGGERS = { {}, { 1 }, { 2 }, { 1, 2 } },

    OVERRIDE_BARS = {
        { key = "possessBar",           wrap = true,  title = "PET" },
        { key = "stanceBar",            wrap = true,  title = "STANCE" },
        { key = "friendlyTargetingBar", wrap = false, label = "FRIENDLY TARGET" },
        { key = "hostileTargetingBar",  wrap = false, label = "ENEMY TARGET" },
        { key = "shortcutsBar",         wrap = false, label = "SHORTCUTS" },
    },
    REQUIRED_FUNCS = {
        "GamepadMainActionBarFrame.SetupNonbindableActions",
        "GamepadMainActionBarFrame.PageUnit.SetActiveActionBar",
        "GamepadMainActionBarFrame.PageUnit.GetActiveBar",
        "GamepadMainActionBarFrame.PageUnit.RefreshCompactLayout",
        "GamepadActionBarStyleUtil.ApplyCollapsedActionBarStyle",
        "GamepadActionBarStyleUtil.ApplyExpandedActionBarStyle",
        "SecureHandlerWrapScript",
        "SecureHandlerSetFrameRef",
    },
    OPTIONAL_FUNCS = {
        glyphs = {
            "InputIconTextureSetUtility.GetActiveInputIconButtonTextures",
            "InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture",
            "InputDeviceIconSetManager.RegisterActiveInputDeviceIconSetUpdatedCallback",
        },
        triggerNames = {
            "InputDeviceIconSetManager.GetActiveInputDeviceIconSet",
            "InputDeviceIconSetManager.RegisterActiveInputDeviceIconSetUpdatedCallback",
        },
        settingWatch = { "CVarCallbackRegistry.RegisterCallback" },
        activeBarCallback = { "GamepadMainActionBarFrame.PageUnit.RegisterActiveActionBarUpdatedCallback" },
        pageIndicator = {
            "GamepadMainActionBarFrame.PageUnit.GetCurrentPage",
            "GamepadMainActionBarFrame.PageUnit.RefreshPageTracker",
            "GamepadMainActionBarFrame.PageUnit.RefreshPageTrackerSpecialPageSlotVisibility",
        },
        releaseFix = { "GamepadMainActionBarFrame.PressActionButton" },
        pressFlash = { "GamepadMainActionBarFrame.PressActionButton" },
    },
    BLOCKERS = {
        { "GamepadUseCompactActionBar", "GAMEPAD_TOGGLE_COMPACT_ACTION_BAR", "Compact Action Bar" },
        { "GamepadShowActionBarScaling", "GAMEPAD_ACTION_BAR_SCALING_TOGGLE", "Action Bar Scaling" },
    },
    MENU_FRAMES = { "SettingsPanel", "GameMenuFrame", "EditModeManagerFrame", "GamepadActionBarEditFrame" },
    MUTED_PAGE_ART = {
        "LeftIcon", "RightIcon", "CenteredIcons",
        "LeftShoulderBackground", "RightShoulderBackground",
        "LeftShoulderIcon", "RightShoulderIcon",
        "LeftShoulderHighlight", "RightShoulderHighlight",
    },
    MUTED_BAR_ART = { "BackgroundFocus", "BackgroundWatermark", "IdentifierIcon" },
    LABEL_SIZE_OPTIONS = {
        { value = 0.85, label = "Small (85%)" },
        { value = 1.0,  label = "Normal (100%)" },
        { value = 1.25, label = "Large (125%)" },
    },
    GLYPH_SIZE_OPTIONS = {
        { value = 0,    label = "Off" },
        { value = 0.75, label = "Small (75%)" },
        { value = 1.0,  label = "Normal (100%)" },
        { value = 1.3,  label = "Large (130%)" },
    },
    GLYPH_POS_OPTIONS = {
        { value = "BELOW",  label = "Centered Below Button (Default)" },
        { value = "CORNER", label = "Top-Left Corner" },
    },
    ARRANGEMENT_OPTIONS = {
        { value = "XYBA", label = "XYBA (Default)" },
        { value = "XYAB", label = "XYAB" },
    },
    CLASS_LAYOUT_OPTIONS = {
        { value = "INLINE", label = "Inline Left & Right of Bar (Default)" },
        { value = "BELOW",  label = "Below Bar (TriggerBar Default)" },
    },
}

CFG.PLAIN_GLYPH_SIZE = CFG.GLYPH_SIZE * 20 / 29
CFG.GUIDE_WIDTH = 2 * CFG.GUIDE_ICON + CFG.GUIDE_GAP
CFG.GUIDE_HEIGHT = CFG.GUIDE_ICON + 4

local CompactBar = {
    name = "CompactControllerBar",
    description = "Controller-only single-bar compact gamepad action bar (from TriggerBar) with customizable spacing, arrangement, inline square stance/pet buttons, and centered selection wheel.",
    defaultEnabled = true,
    defaults = {
        enabled = true,
        scale = 1.0,
        x = 0,
        y = -16,
        lockCenterX = true,
        buttonPadding = 5,
        arrangement = "XYBA",           -- "XYBA" or "XYAB"
        classButtonLayout = "INLINE",   -- "INLINE" or "BELOW"
        squareClassButtons = true,
        centerFlyoutWheel = true,
        showBarBackground = true,
        guide = true,
        glyphScale = 1.0,
        glyphPosition = "BELOW",        -- "BELOW" or "CORNER"
        glyphBelowOffset = 7,
        labelScale = 1.0,
        flash = true,
    },
}

-- All runtime state consolidated in one table to stay well within Lua 5.1's 200-local cap.
local S = {
    enabled = false,
    initialized = false,
    hooksInstalled = false,
    built = false,
    applied = false,
    disabled = false,
    stopped = false,
    lastError = nil,
    conflictTriggerBar = false,
    missing = {},
    features = {},
    root = nil,
    pageUnit = nil,
    anchors = {},
    bars = {},
    flatBars = {},
    flatBarInfo = {},
    sectionOfAnchor = {},

    header = nil,
    holder = nil,
    guideHolder = nil,
    toolsHolder = nil,
    slots = {},
    slotOffsets = {},
    barButtons = {},
    wrappedBars = {},
    postClicks = {},
    anchorPoints = {},
    buttonPoints = {},
    buttonSizes = {},
    barButtonHooked = {},
    reanchorBarGuard = false,
    barDriftPending = false,

    -- Extra Class/Pet/Stance buttons & flyout wheel state
    classSlots = {},      -- "Left"/"Right" -> SecureFrameTemplate slot
    classPromptSlots = {},-- "Left"/"Right" -> SecureFrameTemplate prompt slot
    classPlates = {},     -- "Left"/"Right" -> HUD square well/border plate
    classOrigPoints = {}, -- frame -> { points... }
    classOrigSizes = {},  -- frame -> { w, h }
    classOrigScales = {}, -- frame -> scale
    classMaskSaved = {},  -- iconTex -> { masks... }
    classTexCoordSaved = {},
    classIconPoints = {}, -- iconTex -> { points... }
    classAlphaSaved = {}, -- region -> origAlpha
    classRegionSide = {}, -- region -> "Left"/"Right"
    classIgnParentAlpha = {},
    classHooked = {},
    reanchorGuard = false,
    hookedFlyouts = {},
    origFlyoutPoints = {},
    flyoutConfirmPending = {},
    centeringFlyoutGuard = false,
    hookedClassClick = {},

    -- Mover overlay state
    mover = nil,
    moverLockBtn = nil,
    moverAxisBtn = nil,
    settingsCtx = nil,
    classOutlines = nil,
    moving = false,
    dragging = false,

    -- Styling & overlay art
    art = nil,
    tray = nil,
    sectionArt = {},
    wells = {},          -- { tex = texture, side = "Left"|"Right", index = 1..4 }
    divider = nil,
    glyphs = {},
    glyphFrames = {},
    glyphSlots = {},
    mutedAlpha = {},
    pointerOff = {},
    pageIndicator = nil,
    pageTracker = nil,
    pageTexts = {},
    pageEntries = {},
    specialPageShown = nil,
    guide = nil,
    guideEntries = {},
    guideLit = nil,
    iconMarkup = {},
    flashes = {},
    flashTextures = {},
    flashLeft = {},
    flashScales = {},
    nextFlash = 1,
    fader = nil,
    flashesBusy = false,
    pressedIndex = nil,
    styled = false,
    styleShown = false,
    fitted = {},
    failedPieces = {},
    fontBaseSizes = {},

    -- Queues & timers
    pendingOrder = {},
    pendingWork = {},
    handBackPending = false,
    pendingSettingRefresh = false,
    settingsHooked = false,
    menuTicker = nil,
    noticeTimer = nil,
    statusText = nil,
    lastStatusMsg = nil,
}

local function GetDB()
    return YRG:GetModuleDB("CompactControllerBar")
end

local function IsStandaloneTriggerBarLoaded()
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded("TriggerBar") and true or false
    elseif type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded("TriggerBar") and true or false
    end
    return false
end

local function IsGamepadUIOn()
    if C_InputInterfaceStyle and Enum and Enum.InputDeviceInterfaceType then
        return C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad
    end
    if InputUtil and type(InputUtil.IsGamepadUIEnabled) == "function" then
        return InputUtil.IsGamepadUIEnabled() and true or false
    end
    return false
end

local function IsCVarOn(name)
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        local v = C_CVar.GetCVar(name)
        return v ~= nil and v ~= "0"
    elseif type(GetCVar) == "function" then
        local v = GetCVar(name)
        return v ~= nil and v ~= "0"
    end
    return false
end

local function IsProtectedSafe(f)
    if not f then return true end
    if type(f.IsForbidden) == "function" and f:IsForbidden() then return true end
    if type(f.IsProtected) == "function" then
        local ok, prot = pcall(f.IsProtected, f)
        if ok and prot then return true end
    end
    return false
end

local function ResolvePath(path)
    local value = _G
    for key in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

local function Snap(val, range)
    local num = tonumber(val) or range[1]
    return math.max(range[1], math.min(range[2], math.floor(num * CFG.STEPS_PER_UNIT + 0.5) / CFG.STEPS_PER_UNIT))
end

local function GetPadding(db)
    local p = math.floor((tonumber(db and db.buttonPadding) or 5) + 0.5)
    return math.max(CFG.PADDING_RANGE[1], math.min(CFG.PADDING_RANGE[2], p))
end

local function GetSlotPitch(db)
    return CFG.BUTTON_SIZE + GetPadding(db)
end

local function GetSectionWidth(db)
    local pitch = GetSlotPitch(db)
    return 2 * (CFG.GROUP_GAP / 2 + 3.5 * pitch + CFG.BUTTON_SIZE / 2)
end

local function GetRowPositions(db)
    return (db and db.arrangement == "XYAB") and CFG.ROW_POS_XYAB or CFG.ROW_POS_XYBA
end

local function SlotOffsetAtPosition(side, position, pitch)
    if side == "Left" then
        return -CFG.GROUP_GAP / 2 - (4.5 - position) * pitch
    end
    return CFG.GROUP_GAP / 2 + (position - 0.5) * pitch
end

local function SlotOffsetX(side, index, db)
    local pos = GetRowPositions(db)[index]
    return SlotOffsetAtPosition(side, pos, GetSlotPitch(db))
end

local function EachBarButton(bar, fn)
    for _, side in ipairs(CFG.SIDES) do
        local group = bar[side]
        if type(group) == "table" then
            for i = 1, CFG.BUTTONS_PER_GROUP do
                local btn = group["ActionButton" .. i]
                if btn then
                    fn(btn, side, i)
                end
            end
        end
    end
end

local function HasClassButton(side)
    local cls = UnitClassBase and select(1, UnitClassBase("player"))
        or (UnitClass and select(2, UnitClass("player")))
    local sides = cls and CFG.CLASS_BUTTON_SIDES[cls]
    if sides == side or sides == "Both" then
        return true
    end
    local btn = S.pageUnit and S.pageUnit[side .. "ClassAction"]
    return type(btn) == "table" and btn.IsShown ~= nil and btn:IsShown()
end

local function GetClassButtonSize(db)
    return (not db or db.squareClassButtons ~= false) and CFG.BUTTON_SIZE or CFG.CLASS_BUTTON_SIZE
end

local function GetClassSlotOffsetFromBarEdge(db)
    local pad = GetPadding(db)
    local cSize = GetClassButtonSize(db)
    local outerGap = math.max(4, pad + 2)
    return CFG.PLATE_INSETS.left + CFG.PLATE_INSETS.right + outerGap + cSize / 2
end

local function HotbarSize(db)
    return GetSectionWidth(db), CFG.LABEL_SPACE + CFG.BUTTON_SIZE
end

local function IsAnyMenuOpen()
    for _, name in ipairs(CFG.MENU_FRAMES) do
        local frame = _G[name]
        if type(frame) == "table" and frame.IsShown and frame:IsShown() then
            return true
        end
    end
    return false
end

local function IsYRGSettingsCategoryOpen()
    if not SettingsPanel or not SettingsPanel.IsShown or not SettingsPanel:IsShown() then
        return false
    end
    if type(SettingsPanel.GetCurrentCategory) ~= "function" then
        return false
    end
    local ok, cat = pcall(SettingsPanel.GetCurrentCategory, SettingsPanel)
    if not ok or not cat then
        return false
    end
    if cat == CompactBar.settingsCategory or cat == YRG.settingsCategory then
        return true
    end
    if type(cat.GetParentCategory) == "function" then
        local okP, pCat = pcall(cat.GetParentCategory, cat)
        if okP and pCat == YRG.settingsCategory then
            return true
        end
    end
    return false
end

local function IsMenuOpen()
    for _, name in ipairs(CFG.MENU_FRAMES) do
        if name ~= "SettingsPanel" then
            local frame = _G[name]
            if type(frame) == "table" and frame.IsShown and frame:IsShown() then
                return true
            end
        end
    end
    if SettingsPanel and type(SettingsPanel.IsShown) == "function" and SettingsPanel:IsShown() then
        if not (S.built and S.applied and IsYRGSettingsCategoryOpen()) then
            return true
        end
    end
    return false
end

local function GetBlockers()
    local names = {}
    for _, setting in ipairs(CFG.BLOCKERS) do
        if IsCVarOn(setting[1]) then
            local text = _G[setting[2]]
            names[#names + 1] = (type(text) == "string" and text ~= "") and text or setting[3]
        end
    end
    return names
end

local function IsBlocked()
    for _, setting in ipairs(CFG.BLOCKERS) do
        if IsCVarOn(setting[1]) then
            return true
        end
    end
    return false
end

local function ShouldBeActiveNow()
    local db = GetDB()
    return S.enabled
        and db and db.enabled
        and not S.disabled
        and not S.stopped
        and not S.conflictTriggerBar
        and IsGamepadUIOn()
        and not IsBlocked()
        and S.root ~= nil
        and S.pageUnit ~= nil
end

local function GetSectionLabel(index)
    local iconSet = S.features.triggerNames
        and InputDeviceIconSetManager
        and InputDeviceIconSetManager.GetActiveInputDeviceIconSet
        and InputDeviceIconSetManager:GetActiveInputDeviceIconSet()
    local names = CFG.TRIGGER_NAMES[iconSet] or CFG.TRIGGER_NAMES.Generic
    if index == 1 then
        return "NO TRIGGER"
    elseif index == 2 then
        return names[1]
    elseif index == 3 then
        return names[2]
    end
    return names[1] .. " + " .. names[2]
end

local function GetAccentColor(db)
    return CFG.DEFAULT_ACCENT
end

local function GetClassPromptScale(db)
    return CFG.PROMPT_SCALE
end

local function IsCenterXLocked(db)
    return db == nil or db.lockCenterX ~= false
end

local function GetGlyphBelowOffset(db)
    local v = math.floor((tonumber(db and db.glyphBelowOffset) or CFG.GLYPH_BELOW_DEFAULT) + 0.5)
    return math.max(CFG.GLYPH_BELOW_RANGE[1], math.min(CFG.GLYPH_BELOW_RANGE[2], v))
end

local function GetPromptOffsetY(db, cSize, pScale)
    local gScale = tonumber(db and db.glyphScale)
    if gScale == nil then gScale = 1 end
    local glyphPos = (db and db.glyphPosition == "CORNER") and "CORNER" or "BELOW"
    local belowOff = GetGlyphBelowOffset(db)
    if glyphPos == "BELOW" then
        if gScale > 0 then
            -- Match the exact vertical center of the main button icons below the bar
            return -(CFG.BUTTON_SIZE / 2 + belowOff + (CFG.GLYPH_SIZE * gScale) / 2)
        end
        return -(CFG.BUTTON_SIZE / 2 + belowOff + 8 * pScale)
    end
    return -(cSize / 2 + CFG.PLATE_INSETS.bottom + 4 + 8 * pScale)
end

local function UnitSize()
    if not S.pageUnit or not S.pageUnit:GetParent() or not UIParent then return 1 end
    local pScale = math.max(YRG.SafeNumber(S.pageUnit:GetParent():GetEffectiveScale(), 1), 0.01)
    local uScale = math.max(YRG.SafeNumber(UIParent:GetEffectiveScale(), 1), 0.01)
    return pScale / uScale
end

-- Computes total outer bounds (left, right, top, bottom) relative to holder TOP center.
local function ComputeBounds(db)
    local w, h = HotbarSize(db)
    local insets = CFG.PLATE_INSETS
    local left = -w / 2 - insets.left
    local right = w / 2 + insets.right
    local top = math.max(0, insets.top + CFG.LABEL_INSET_Y + 14 - CFG.LABEL_SPACE)
    local bottom = -(h + insets.bottom)

    if db.guide ~= false then
        top = math.max(top, insets.top + CFG.LABEL_INSET_Y + CFG.GUIDE_HEIGHT - CFG.LABEL_SPACE)
    end

    local gScale = tonumber(db.glyphScale)
    if gScale == nil then gScale = 1 end
    if gScale > 0 and (db.glyphPosition or "BELOW") == "BELOW" then
        bottom = math.min(bottom, -(h + GetGlyphBelowOffset(db) + CFG.GLYPH_SIZE * gScale))
    end

    local hasLeft = HasClassButton("Left")
    local hasRight = HasClassButton("Right")
    if hasLeft or hasRight then
        local pScale = GetClassPromptScale(db)
        if (db.classButtonLayout or "INLINE") == "INLINE" then
            local cSize = GetClassButtonSize(db)
            local off = GetClassSlotOffsetFromBarEdge(db)
            local promptOffY = GetPromptOffsetY(db, cSize, pScale)
            local pHalfW = (CFG.CLASS_PROMPT_WIDTH * pScale) / 2
            local sqPadL = (db.squareClassButtons ~= false) and insets.left or 0
            local sqPadR = (db.squareClassButtons ~= false) and insets.right or 0
            if hasLeft then
                local cx = -w / 2 - off
                left = math.min(left, cx - math.max(cSize / 2 + sqPadL, pHalfW))
            end
            if hasRight then
                local cx = w / 2 + off
                right = math.max(right, cx + math.max(cSize / 2 + sqPadR, pHalfW))
            end
            local classBottom = -(h - CFG.BUTTON_SIZE / 2 - promptOffY + (CFG.CLASS_PROMPT_HEIGHT * pScale) / 2 + 4)
            bottom = math.min(bottom, classBottom)
        else
            local btnY = -(h - CFG.BUTTON_SIZE / 2) + CFG.CLASS_BUTTON_Y
            local classBottom = btnY - CFG.CLASS_BUTTON_SIZE / 2 - CFG.CLASS_PROMPT_HEIGHT * pScale - 18
            bottom = math.min(bottom, classBottom)
            if hasLeft then
                left = math.min(left, -CFG.CLASS_BUTTON_X - (CFG.CLASS_PROMPT_WIDTH * pScale) / 2)
            end
            if hasRight then
                right = math.max(right, CFG.CLASS_BUTTON_X + (CFG.CLASS_PROMPT_WIDTH * pScale) / 2)
            end
        end
    end

    return left, right, top, bottom
end

local function FitScaleForMargin(db, margin)
    local left, right, top, bottom = ComputeBounds(db)
    local unit = UnitSize()
    local uW = YRG.SafeNumber(UIParent and UIParent:GetWidth(), 1280)
    local uH = YRG.SafeNumber(UIParent and UIParent:GetHeight(), 800)
    local spanX = math.max((right - left) * unit, 1)
    local spanY = math.max((top - bottom) * unit, 1)
    local fit = math.min((uW - 2 * margin) / spanX, (uH - 2 * margin) / spanY)
    local steps = math.floor(fit * CFG.STEPS_PER_UNIT + 0.001)
    return math.max(CFG.SCALE_RANGE[1], math.min(CFG.SCALE_RANGE[2], steps / CFG.STEPS_PER_UNIT))
end

local function GetScale(db)
    local saved = Snap(db and db.scale or 1, CFG.SCALE_RANGE)
    return math.min(saved, FitScaleForMargin(db, CFG.SCREEN_MARGIN))
end

-- Forward declarations
local SyncLayout, PlaceSections, ApplyStyle, FitStyle, RefreshEmphasis, SetStyleShown, HandBack, HandBackWhenPossible, SetMoverActive, UpdateMoverBox

local function IsForbiddenSafe(f)
    if type(f) ~= "table" then return true end
    if type(f.IsForbidden) == "function" then
        local ok, forb = pcall(f.IsForbidden, f)
        if not ok or forb then return true end
    end
    return false
end

local function RunCore(fn)
    if S.stopped then return false end
    local errMsg
    local ok = xpcall(fn, function(msg)
        errMsg = tostring(msg)
        local handler = geterrorhandler and geterrorhandler()
        if type(handler) == "function" then
            pcall(handler, msg)
        end
        return msg
    end)
    if ok then
        S.lastError = nil
        return true
    end
    S.lastError = errMsg or "unknown layout error"
    S.stopped = true
    S.pendingOrder, S.pendingWork = {}, {}
    print("|cffff5555YRG CompactControllerBar Layout Error:|r " .. S.lastError)
    HandBackWhenPossible()
    SetStyleShown(false)
    return false
end

local function RunOutOfCombat(key, fn)
    if not InCombatLockdown() then
        return RunCore(fn)
    end
    if S.stopped then return false end
    if not S.pendingWork[key] then
        table.insert(S.pendingOrder, key)
    end
    S.pendingWork[key] = fn
    return false
end

local function SafeTry(piece, fn)
    if S.failedPieces[piece] then return false end
    if xpcall(fn, geterrorhandler()) then return true end
    S.failedPieces[piece] = true
    return false
end

--------------------------------------------------------------------------------
-- Selection Wheel (FlyoutRadial) Centering
--------------------------------------------------------------------------------
local function SafeFrameLabel(frame)
    if IsForbiddenSafe(frame) then return "" end
    local ok, nm = pcall(function()
        return (type(frame.GetName) == "function" and frame:GetName())
            or (type(frame.GetDebugName) == "function" and frame:GetDebugName())
            or ""
    end)
    return (ok and type(nm) == "string") and nm or ""
end

local function HasDeniedFlyoutToken(low)
    if type(low) ~= "string" or low == "" then return false end
    for _, deny in ipairs({
        "icon", "mask", "shadow", "ring", "border", "background", "backdrop",
        "glow", "flash", "highlight", "prompt", "cooldown", "overlay", "edge", "wedge",
        "actionbutton", "button", "anim", "reticle", "interrupt", "arrow", "autocast",
        "textoverlay", "slot",
    }) do
        if low:find(deny, 1, true) then
            return true
        end
    end
    return false
end

local function IsBarOrClassFrame(f)
    if not f then return false end
    if f == S.holder or f == S.mover or f == S.art or f == S.tray or f == UIParent
        or f == S.root or f == S.pageUnit or f == S.guide or f == S.pageIndicator then
        return true
    end
    if S.slots[f] or S.sectionOfAnchor[f] or S.flatBarInfo[f] then
        return true
    end
    for _, grp in ipairs(S.flatBars) do
        if f == grp.bar or f == grp.bar.Left or f == grp.bar.Right then
            return true
        end
    end
    for _, side in ipairs(CFG.SIDES) do
        if f == S.classSlots[side] or f == S.classPromptSlots[side] or f == S.classPlates[side] then
            return true
        end
    end
    if S.pageUnit then
        for _, key in ipairs(CFG.CLASS_FRAMES) do
            if f == S.pageUnit[key] then return true end
        end
        for _, sec in ipairs(CFG.SECTIONS) do
            if f == S.pageUnit[sec.anchorKey] then return true end
        end
    end
    return false
end

local function ReanchorBarButtonIfDrifted(button)
    if S.reanchorBarGuard or not S.applied then return end
    local slot = S.slots[button]
    if not slot or IsForbiddenSafe(button) then return end
    if InCombatLockdown() then
        S.barDriftPending = true
        return
    end
    local okN, n = pcall(button.GetNumPoints, button)
    if okN and n == 1 then
        local okP, pt, rel, relPt, ox, oy = pcall(button.GetPoint, button, 1)
        if okP and pt == "CENTER" and rel == slot and relPt == "CENTER"
            and math.abs(tonumber(ox) or 0) < 0.5 and math.abs(tonumber(oy) or 0) <= 3 then
            return
        end
    end
    S.reanchorBarGuard = true
    pcall(function()
        button:ClearAllPoints()
        button:SetPoint("CENTER", slot, "CENTER")
    end)
    S.reanchorBarGuard = false
end

local function ReanchorDriftedBarButtons()
    if S.reanchorBarGuard or not S.applied or InCombatLockdown() then return end
    S.barDriftPending = false
    for button in pairs(S.slots) do
        ReanchorBarButtonIfDrifted(button)
    end
end

local function IsFlyoutExcludedFrame(frame)
    if IsForbiddenSafe(frame) then return true end
    local okFrm, isFrm = pcall(function()
        return type(frame.IsObjectType) == "function" and frame:IsObjectType("Frame")
    end)
    if not okFrm or not isFrm then
        return true
    end
    -- Never treat clickable UI buttons (ActionButton, ClassAction, flyout slice buttons) as radial containers
    local okBtn, isBtn = pcall(function()
        return type(frame.IsObjectType) == "function" and frame:IsObjectType("Button")
    end)
    if okBtn and isBtn then
        return true
    end
    if IsBarOrClassFrame(frame) then
        return true
    end
    if HasDeniedFlyoutToken(SafeFrameLabel(frame):lower()) then
        return true
    end
    local cur = frame
    for _ = 1, 6 do
        local okPar, par = pcall(cur.GetParent, cur)
        if not okPar or not par or par == UIParent then break end
        if par ~= S.root and par ~= S.pageUnit and IsBarOrClassFrame(par) then
            return true
        end
        local okPBtn, pBtn = pcall(function()
            return type(par.IsObjectType) == "function" and par:IsObjectType("Button")
        end)
        if okPBtn and pBtn then
            return true
        end
        cur = par
    end
    return false
end

local function ApplyFlyoutCenterPoint(flyout)
    if S.centeringFlyoutGuard or IsFlyoutExcludedFrame(flyout) then return end
    local db = GetDB()
    if not (db and db.enabled and db.centerFlyoutWheel ~= false and IsGamepadUIOn() and not S.disabled and not S.stopped and not S.conflictTriggerBar) then
        return
    end
    if InCombatLockdown() and IsProtectedSafe(flyout) then
        return
    end
    if not S.origFlyoutPoints[flyout] and type(flyout.GetNumPoints) == "function" then
        local okN, n = pcall(flyout.GetNumPoints, flyout)
        if okN and type(n) == "number" and n > 0 then
            local pts = {}
            for i = 1, n do
                pts[i] = { flyout:GetPoint(i) }
            end
            S.origFlyoutPoints[flyout] = pts
        end
    end
    local alreadyCentered = false
    if type(flyout.GetNumPoints) == "function" and type(flyout.GetPoint) == "function" then
        local okN, n = pcall(flyout.GetNumPoints, flyout)
        if okN and n == 1 then
            local okP, pt, rel, relPt, ox, oy = pcall(flyout.GetPoint, flyout, 1)
            if okP and pt == "CENTER" and rel == UIParent and relPt == "CENTER"
                and math.abs(tonumber(ox) or 0) < 0.5 and math.abs(tonumber(oy) or 0) < 0.5 then
                alreadyCentered = true
            end
        end
    end
    if not alreadyCentered then
        S.centeringFlyoutGuard = true
        pcall(function()
            flyout:ClearAllPoints()
            flyout:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end)
        S.centeringFlyoutGuard = false
    end
end

local function CenterFlyoutFrame(flyout)
    if S.centeringFlyoutGuard or IsFlyoutExcludedFrame(flyout) then return end
    ApplyFlyoutCenterPoint(flyout)
    if not S.flyoutConfirmPending[flyout] then
        S.flyoutConfirmPending[flyout] = true
        local function Recheck()
            local okS, shown = pcall(function() return type(flyout.IsShown) == "function" and flyout:IsShown() end)
            if okS and shown then
                ApplyFlyoutCenterPoint(flyout)
            end
        end
        C_Timer.After(0, Recheck)
        C_Timer.After(0.05, function()
            S.flyoutConfirmPending[flyout] = nil
            Recheck()
        end)
    end
end

local function RegisterFlyoutCandidate(frame)
    if IsFlyoutExcludedFrame(frame) or S.hookedFlyouts[frame] or type(frame.SetPoint) ~= "function" then
        return
    end
    S.hookedFlyouts[frame] = true
    if type(frame.HookScript) == "function" then
        pcall(frame.HookScript, frame, "OnShow", CenterFlyoutFrame)
        pcall(frame.HookScript, frame, "OnHide", function()
            C_Timer.After(0, ReanchorDriftedBarButtons)
        end)
        local low = SafeFrameLabel(frame):lower()
        if low:find("flyout", 1, true) or low:find("radial", 1, true) or low:find("wheel", 1, true) then
            pcall(frame.HookScript, frame, "OnUpdate", ApplyFlyoutCenterPoint)
        end
    end
    pcall(hooksecurefunc, frame, "SetPoint", CenterFlyoutFrame)
    pcall(hooksecurefunc, frame, "SetAllPoints", CenterFlyoutFrame)
    pcall(hooksecurefunc, frame, "Show", CenterFlyoutFrame)
    pcall(hooksecurefunc, frame, "SetShown", function(f, shown)
        if shown then
            CenterFlyoutFrame(f)
        else
            C_Timer.After(0, ReanchorDriftedBarButtons)
        end
    end)
    if type(frame.Layout) == "function" then
        pcall(hooksecurefunc, frame, "Layout", CenterFlyoutFrame)
    end
    local ok, shown = pcall(function() return type(frame.IsShown) == "function" and frame:IsShown() end)
    if ok and shown then
        CenterFlyoutFrame(frame)
    end
end

local function MatchesFlyoutName(low)
    if type(low) ~= "string" or low == "" then return false end
    if not (low:find("flyout", 1, true) or low:find("radial", 1, true) or low:find("wheel", 1, true)) then
        return false
    end
    return not HasDeniedFlyoutToken(low)
end

local function ScanFlyoutCandidates()
    local function CheckKids(parent)
        if IsForbiddenSafe(parent) then return end
        pcall(function()
            for k, v in pairs(parent) do
                if type(k) == "string" and not IsFlyoutExcludedFrame(v) then
                    if MatchesFlyoutName(k:lower()) then
                        RegisterFlyoutCandidate(v)
                    end
                end
            end
        end)
        if type(parent.GetChildren) == "function" then
            local ok, kids = pcall(function() return { parent:GetChildren() } end)
            if ok and type(kids) == "table" then
                for _, child in ipairs(kids) do
                    if not IsFlyoutExcludedFrame(child) then
                        local low = SafeFrameLabel(child):lower()
                        if MatchesFlyoutName(low) then
                            RegisterFlyoutCandidate(child)
                        end
                    end
                end
            end
        end
    end

    if S.pageUnit then
        CheckKids(S.pageUnit)
    end
    if S.root then
        CheckKids(S.root)
    end
    if UIParent and type(UIParent.GetChildren) == "function" then
        local ok, kids = pcall(function() return { UIParent:GetChildren() } end)
        if ok and type(kids) == "table" then
            for _, child in ipairs(kids) do
                if not IsFlyoutExcludedFrame(child) then
                    local low = SafeFrameLabel(child):lower()
                    if MatchesFlyoutName(low) then
                        RegisterFlyoutCandidate(child)
                    end
                end
            end
        end
    end
    for _, gName in ipairs({
        "GamepadRadial", "SpellFlyout",
        "ClassSpellFlyoutFrame", "PetActionFlyoutFrame", "PetSpellFlyoutFrame",
        "GamepadClassActionFlyout", "GamepadFlyoutRadialFrame", "FlyoutRadialFrame",
        "FlyoutRadial", "GamepadActionFlyoutFrame",
        "ClassActionFlyoutFrame", "StanceFlyoutFrame", "PetFlyoutFrame",
    }) do
        if type(_G[gName]) == "table" then
            RegisterFlyoutCandidate(_G[gName])
        end
    end
    for f in pairs(S.hookedFlyouts) do
        local okS, shown = pcall(function() return type(f.IsShown) == "function" and f:IsShown() end)
        if okS and shown then
            CenterFlyoutFrame(f)
        end
    end
end

local function RestoreFlyoutFrames()
    for flyout, pts in pairs(S.origFlyoutPoints) do
        if type(flyout) == "table" and type(flyout.ClearAllPoints) == "function"
            and not (InCombatLockdown() and IsProtectedSafe(flyout)) then
            S.centeringFlyoutGuard = true
            pcall(function()
                flyout:ClearAllPoints()
                for _, pt in ipairs(pts) do
                    flyout:SetPoint(unpack(pt, 1, 5))
                end
            end)
            S.centeringFlyoutGuard = false
        end
    end
end

--------------------------------------------------------------------------------
-- Class / Stance / Pet Extra Buttons (Inline Left/Right + Square Style)
--------------------------------------------------------------------------------
local function SaveClassOriginals(key, frame)
    if IsForbiddenSafe(frame) or S.classOrigPoints[frame] then return end
    pcall(function()
        local pts = {}
        if type(frame.GetNumPoints) == "function" then
            for i = 1, frame:GetNumPoints() do
                pts[i] = { frame:GetPoint(i) }
            end
        end
        S.classOrigPoints[frame] = pts
        if type(frame.GetSize) == "function" then
            local w, h = frame:GetSize()
            S.classOrigSizes[frame] = { w, h }
        end
        if type(frame.GetScale) == "function" then
            S.classOrigScales[frame] = frame:GetScale()
        end
    end)
end

local function StylePlacardFrame(frame)
    if not frame then return end
    local mui = YRG and YRG.MinimapUI
    if type(mui) == "table" and type(mui.ApplyHeaderNineSliceStyle) == "function" then
        mui.ApplyHeaderNineSliceStyle(frame)
        return
    end
    if not frame._yrgFallbackTex then
        local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
        bgTex:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        bgTex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
        bgTex:SetColorTexture(0.04, 0.03, 0.02, 0.72)
        frame._yrgFallbackTex = bgTex
    end
end

local function ApplySquareClassButtonStyle(side, btn, makeSquare)
    if IsForbiddenSafe(btn) or InCombatLockdown() then return end
    local plate = S.classPlates[side]
    local icon = btn.Icon or btn.icon or btn.IconTexture
    if not makeSquare then
        local sz = S.classOrigSizes[btn]
        if sz and sz[1] and sz[2] and type(btn.SetSize) == "function" then
            pcall(btn.SetSize, btn, sz[1], sz[2])
        end
        if type(icon) == "table" then
            if S.classMaskSaved[icon] and type(icon.AddMaskTexture) == "function" then
                for _, mask in ipairs(S.classMaskSaved[icon]) do
                    pcall(icon.AddMaskTexture, icon, mask)
                end
                S.classMaskSaved[icon] = nil
            end
            if S.classTexCoordSaved[icon] and type(icon.SetTexCoord) == "function" then
                pcall(icon.SetTexCoord, icon, unpack(S.classTexCoordSaved[icon]))
                S.classTexCoordSaved[icon] = nil
            end
            if S.classIconPoints[icon] and type(icon.ClearAllPoints) == "function" then
                pcall(function()
                    icon:ClearAllPoints()
                    for _, pt in ipairs(S.classIconPoints[icon]) do
                        icon:SetPoint(unpack(pt, 1, 5))
                    end
                end)
                S.classIconPoints[icon] = nil
            end
        end
        for region, origA in pairs(S.classAlphaSaved) do
            if S.classRegionSide[region] == side and type(region.SetAlpha) == "function" then
                pcall(region.SetAlpha, region, origA)
            end
        end
        if plate then plate:Hide() end
        return
    end

    if type(btn.SetSize) == "function" then
        pcall(btn.SetSize, btn, CFG.BUTTON_SIZE, CFG.BUTTON_SIZE)
    end
    if type(icon) == "table" then
        pcall(function()
            if type(icon.GetNumMaskTextures) == "function" and not S.classMaskSaved[icon] then
                local saved = {}
                for m = 1, icon:GetNumMaskTextures() do
                    local mask = icon:GetMaskTexture(m)
                    if mask then saved[#saved + 1] = mask end
                end
                if #saved > 0 then
                    S.classMaskSaved[icon] = saved
                end
            end
            if S.classMaskSaved[icon] and type(icon.RemoveMaskTexture) == "function" then
                for _, mask in ipairs(S.classMaskSaved[icon]) do
                    pcall(icon.RemoveMaskTexture, icon, mask)
                end
            end
            if type(icon.GetTexCoord) == "function" and not S.classTexCoordSaved[icon] then
                local tc = { pcall(icon.GetTexCoord, icon) }
                if tc[1] and #tc >= 9 then
                    S.classTexCoordSaved[icon] = { tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8], tc[9] }
                end
            end
            if type(icon.SetTexCoord) == "function" then
                pcall(icon.SetTexCoord, icon, 0.07, 0.93, 0.07, 0.93)
            end
            if not S.classIconPoints[icon] and type(icon.GetNumPoints) == "function" then
                local pts = {}
                for i = 1, icon:GetNumPoints() do
                    pts[i] = { icon:GetPoint(i) }
                end
                if #pts > 0 then
                    S.classIconPoints[icon] = pts
                end
            end
            if type(icon.ClearAllPoints) == "function" and type(icon.SetPoint) == "function" then
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
                icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
            end
        end)
    end

    local function MuteClassRegion(r)
        if type(r) ~= "table" or r == icon or IsForbiddenSafe(r) or type(r.SetAlpha) ~= "function" then
            return
        end
        -- Only mute non-icon decorative textures/masks, never child Frames
        local okF, isFrm = pcall(function() return type(r.IsObjectType) == "function" and r:IsObjectType("Frame") end)
        if okF and isFrm then return end
        if S.classAlphaSaved[r] == nil and type(r.GetAlpha) == "function" then
            local okA, curA = pcall(r.GetAlpha, r)
            if okA then S.classAlphaSaved[r] = curA end
        end
        S.classRegionSide[r] = side
        pcall(r.SetAlpha, r, 0)
    end
    for _, regKey in ipairs({ "CircleMask", "IconMask", "Mask", "SlotBackground", "Ring", "Border" }) do
        MuteClassRegion(btn[regKey])
    end
    if type(btn.GetNormalTexture) == "function" and icon ~= nil then
        local okN, norm = pcall(btn.GetNormalTexture, btn)
        if okN and norm and norm ~= icon then MuteClassRegion(norm) end
    end

    if S.art and not plate then
        local slot = S.classSlots[side]
        if slot then
            pcall(function()
                plate = CreateFrame("Frame", nil, S.art)
                plate:SetFrameStrata("BACKGROUND")
                plate:SetFrameLevel(1)
                local insets = CFG.PLATE_INSETS
                plate:SetPoint("TOPLEFT", slot, "CENTER", -CFG.BUTTON_SIZE / 2 - insets.left, CFG.BUTTON_SIZE / 2 + insets.top)
                plate:SetPoint("BOTTOMRIGHT", slot, "CENTER", CFG.BUTTON_SIZE / 2 + insets.right, -CFG.BUTTON_SIZE / 2 - insets.bottom)
                StylePlacardFrame(plate)
                S.classPlates[side] = plate
            end)
        end
    end
    if S.classPlates[side] then
        local db = GetDB()
        local showBg = (not db) or (db.showBarBackground ~= false)
        local okS, shown = pcall(function() return type(btn.IsShown) == "function" and btn:IsShown() end)
        local vis = S.styleShown and showBg and okS and shown
        S.classPlates[side]:SetShown(vis and true or false)
    end
end

local function ApplyClassButtonFrames(db)
    if not S.pageUnit or InCombatLockdown() or S.reanchorGuard then return end
    local inline = (db.classButtonLayout or "INLINE") == "INLINE"
    local makeSquare = (db.squareClassButtons ~= false)
    local classSize = GetClassButtonSize(db)

    if S.header then
        S.header:SetAttribute("classInline", inline)
        S.header:SetAttribute("classBtnSize", classSize)
    end

    S.reanchorGuard = true
    pcall(function()
        for _, side in ipairs(CFG.SIDES) do
            local btn = S.pageUnit[side .. "ClassAction"]
            local prompt = S.pageUnit[side .. "InputPrompt"]
            local slot = S.classSlots[side]
            local pSlot = S.classPromptSlots[side]

            if not IsForbiddenSafe(btn) and type(btn.SetPoint) == "function" then
                SaveClassOriginals(side, btn)
                if type(btn.SetIgnoreParentAlpha) == "function" then
                    S.classIgnParentAlpha[btn] = true
                    btn:SetIgnoreParentAlpha(true)
                end
                if inline and slot then
                    btn:ClearAllPoints()
                    btn:SetPoint("CENTER", slot, "CENTER", 0, 0)
                    if type(btn.SetScale) == "function" then btn:SetScale(1) end
                    ApplySquareClassButtonStyle(side, btn, makeSquare)
                else
                    ApplySquareClassButtonStyle(side, btn, false)
                    if type(btn.SetScale) == "function" then
                        btn:SetScale(S.classOrigScales[btn] or 1)
                    end
                    if S.classOrigPoints[btn] then
                        btn:ClearAllPoints()
                        for _, pt in ipairs(S.classOrigPoints[btn]) do
                            btn:SetPoint(unpack(pt, 1, 5))
                        end
                    end
                end
            end

            local pScale = GetClassPromptScale(db)
            if not IsForbiddenSafe(prompt) and type(prompt.SetPoint) == "function" then
                SaveClassOriginals(side .. "Prompt", prompt)
                if type(prompt.SetIgnoreParentAlpha) == "function" then
                    S.classIgnParentAlpha[prompt] = true
                    prompt:SetIgnoreParentAlpha(true)
                end
                if inline and pSlot then
                    prompt:ClearAllPoints()
                    prompt:SetPoint("CENTER", pSlot, "CENTER", 0, 0)
                else
                    if S.classOrigPoints[prompt] then
                        prompt:ClearAllPoints()
                        for _, pt in ipairs(S.classOrigPoints[prompt]) do
                            prompt:SetPoint(unpack(pt, 1, 5))
                        end
                    end
                end
                if type(prompt.SetScale) == "function" then
                    prompt:SetScale(pScale)
                elseif type(prompt.SetFont) == "function" then
                    local okF, fPath, fSize, fFlags = pcall(prompt.GetFont, prompt)
                    if okF and fPath and type(fSize) == "number" then
                        if not S.fontBaseSizes[prompt] then S.fontBaseSizes[prompt] = fSize end
                        pcall(prompt.SetFont, prompt, fPath, math.max(6, math.floor(S.fontBaseSizes[prompt] * pScale + 0.5)), fFlags)
                    end
                end
            end
        end
    end)
    S.reanchorGuard = false
end

local function RestoreClassButtonFrames()
    if InCombatLockdown() then return end
    for _, plate in pairs(S.classPlates) do
        plate:Hide()
    end
    S.reanchorGuard = true
    pcall(function()
        for _, side in ipairs(CFG.SIDES) do
            local btn = S.pageUnit and S.pageUnit[side .. "ClassAction"]
            local prompt = S.pageUnit and S.pageUnit[side .. "InputPrompt"]
            if not IsForbiddenSafe(btn) then
                ApplySquareClassButtonStyle(side, btn, false)
                if type(btn.SetScale) == "function" then
                    btn:SetScale(S.classOrigScales[btn] or 1)
                end
                if S.classOrigPoints[btn] and type(btn.ClearAllPoints) == "function" then
                    btn:ClearAllPoints()
                    for _, pt in ipairs(S.classOrigPoints[btn]) do
                        btn:SetPoint(unpack(pt, 1, 5))
                    end
                end
                if S.classIgnParentAlpha[btn] and type(btn.SetIgnoreParentAlpha) == "function" then
                    btn:SetIgnoreParentAlpha(false)
                end
            end
            if not IsForbiddenSafe(prompt) then
                if type(prompt.SetScale) == "function" then
                    prompt:SetScale(S.classOrigScales[prompt] or 1)
                end
                if S.classOrigPoints[prompt] and type(prompt.ClearAllPoints) == "function" then
                    prompt:ClearAllPoints()
                    for _, pt in ipairs(S.classOrigPoints[prompt]) do
                        prompt:SetPoint(unpack(pt, 1, 5))
                    end
                end
                if S.classIgnParentAlpha[prompt] and type(prompt.SetIgnoreParentAlpha) == "function" then
                    prompt:SetIgnoreParentAlpha(false)
                end
            end
        end
    end)
    S.reanchorGuard = false
end

local function InstallClassButtonHooks()
    if not S.pageUnit then return end
    local function ReSnapIfInline()
        if S.reanchorGuard or not S.applied or InCombatLockdown() then return end
        local db = GetDB()
        if db and db.enabled then
            ApplyClassButtonFrames(db)
        end
    end
    local function RescanFlyoutLater()
        ScanFlyoutCandidates()
        C_Timer.After(0, ScanFlyoutCandidates)
    end

    for _, side in ipairs(CFG.SIDES) do
        local btn = S.pageUnit[side .. "ClassAction"]
        if btn and not S.classHooked[btn] then
            S.classHooked[btn] = true
            SaveClassOriginals(side, btn)
            pcall(hooksecurefunc, btn, "SetPoint", ReSnapIfInline)
            pcall(hooksecurefunc, btn, "SetSize", ReSnapIfInline)
            pcall(hooksecurefunc, btn, "SetWidth", ReSnapIfInline)
            pcall(hooksecurefunc, btn, "SetHeight", ReSnapIfInline)
            if type(btn.HookScript) == "function" then
                pcall(btn.HookScript, btn, "OnShow", function()
                    ReSnapIfInline()
                    if S.classPlates[side] and S.styleShown then
                        local db = GetDB()
                        local showBg = (not db) or (db.showBarBackground ~= false)
                        S.classPlates[side]:SetShown(showBg and db and (db.classButtonLayout or "INLINE") == "INLINE" and db.squareClassButtons ~= false)
                    end
                    RescanFlyoutLater()
                end)
                pcall(btn.HookScript, btn, "OnHide", function()
                    if S.classPlates[side] then
                        S.classPlates[side]:Hide()
                    end
                end)
                pcall(btn.HookScript, btn, "OnClick", RescanFlyoutLater)
                pcall(btn.HookScript, btn, "OnMouseDown", RescanFlyoutLater)
                pcall(btn.HookScript, btn, "OnEvent", RescanFlyoutLater)
            end
            pcall(function()
                for k, v in pairs(btn) do
                    if type(k) == "string" and type(v) == "function" then
                        local low = k:lower()
                        if low:find("flyout", 1, true) or low:find("radial", 1, true) or low:find("wheel", 1, true)
                            or low:find("open", 1, true) or low:find("toggle", 1, true) or low:find("activate", 1, true) then
                            pcall(hooksecurefunc, btn, k, RescanFlyoutLater)
                        end
                    end
                end
            end)
        end
        local prompt = S.pageUnit[side .. "InputPrompt"]
        if prompt and not S.classHooked[prompt] then
            S.classHooked[prompt] = true
            SaveClassOriginals(side .. "Prompt", prompt)
            pcall(hooksecurefunc, prompt, "SetPoint", ReSnapIfInline)
            pcall(hooksecurefunc, prompt, "SetScale", ReSnapIfInline)
            if type(prompt.HookScript) == "function" then
                pcall(prompt.HookScript, prompt, "OnShow", ReSnapIfInline)
            end
        end
    end
    pcall(function()
        for k, v in pairs(S.pageUnit) do
            if type(k) == "string" and type(v) == "function" then
                local low = k:lower()
                if low:find("flyout", 1, true) or low:find("radial", 1, true) or low:find("wheel", 1, true)
                    or low:find("classaction", 1, true) then
                    pcall(hooksecurefunc, S.pageUnit, k, RescanFlyoutLater)
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Flat Layout Engine (One Bar Mode)
--------------------------------------------------------------------------------
local PRE_CLICK = "return nil, true"
local POST_CLICK = [[
    if owner:GetAttribute("flat") then
        local pressed
        for i = 1, $COUNT do
            local barButton, slot = owner:GetFrameRef("b$BAR-" .. i), owner:GetFrameRef("s$BAR-" .. i)
            if barButton and slot then
                barButton:ClearAllPoints()
                barButton:SetPoint("CENTER", slot, "CENTER", 0, (down and barButton == self) and $DIP or 0)
                if barButton == self then
                    pressed = i
                end
            end
        end
        if pressed and not down then
            local size = pressed > $GROUP and $ROUND or $SQUARE
            for bar = 1, $BARS do
                local other, slot = owner:GetFrameRef("b" .. bar .. "-" .. pressed), owner:GetFrameRef("s" .. bar .. "-" .. pressed)
                if other and slot and bar ~= $BAR then
                    other:ClearAllPoints()
                    other:SetPoint("CENTER", slot, "CENTER", 0, 0)
                    other:SetWidth(size)
                    other:SetHeight(size)
                end
            end
        end
    end
]]

local CLASS_POST_CLICK = [[
    if owner:GetAttribute("flat") and owner:GetAttribute("classInline") then
        local cBtn = owner:GetFrameRef("$CREF")
        local cSlot = owner:GetFrameRef("$SREF")
        if cBtn and cSlot then
            cBtn:ClearAllPoints()
            cBtn:SetPoint("CENTER", cSlot, "CENTER", 0, 0)
            local cSize = owner:GetAttribute("classBtnSize")
            if cSize then
                cBtn:SetWidth(cSize)
                cBtn:SetHeight(cSize)
            end
        end
        local pFrm = owner:GetFrameRef("$PREF")
        local pSlot = owner:GetFrameRef("$PSREF")
        if pFrm and pSlot then
            pFrm:ClearAllPoints()
            pFrm:SetPoint("CENTER", pSlot, "CENTER", 0, 0)
        end
    end
]]

local function SetPointer(frame, on)
    if not frame then return end
    if on then
        if S.pointerOff[frame] then
            frame:EnableMouse(true)
            S.pointerOff[frame] = nil
        end
    elseif not S.pointerOff[frame] then
        frame:EnableMouse(false)
        S.pointerOff[frame] = true
    end
end

local function PlacePointer()
    for _, info in ipairs(S.flatBars) do
        local bar = info.bar
        local comesAndGoes = info.wrap and true or false
        SetPointer(bar, not comesAndGoes)
        for _, button in ipairs(S.barButtons[bar]) do
            SetPointer(button, not comesAndGoes)
        end
    end
end

local function RestorePointer()
    for frame in pairs(S.pointerOff) do
        frame:EnableMouse(true)
        S.pointerOff[frame] = nil
    end
end

local function PlaceSlots(db)
    local sectionHolder = S.holder
    local pitch = GetSlotPitch(db)
    local cSize = GetClassButtonSize(db)
    local pScale = GetClassPromptScale(db)
    local classOff = GetClassSlotOffsetFromBarEdge(db)
    local promptOffY = GetPromptOffsetY(db, cSize, pScale)

    for _, info in ipairs(S.flatBars) do
        local bar = info.bar
        EachBarButton(bar, function(button, side, idx)
            local slot = S.slots[button]
            if slot then
                local ox = SlotOffsetX(side, idx, db)
                S.slotOffsets[button] = ox
                slot:ClearAllPoints()
                slot:SetPoint("CENTER", sectionHolder, "BOTTOM", ox, CFG.BUTTON_SIZE / 2)
            end
        end)
    end

    if S.classSlots.Left then
        S.classSlots.Left:ClearAllPoints()
        S.classSlots.Left:SetPoint("CENTER", sectionHolder, "BOTTOMLEFT", -classOff, CFG.BUTTON_SIZE / 2)
    end
    if S.classSlots.Right then
        S.classSlots.Right:ClearAllPoints()
        S.classSlots.Right:SetPoint("CENTER", sectionHolder, "BOTTOMRIGHT", classOff, CFG.BUTTON_SIZE / 2)
    end
    if S.classPromptSlots.Left and S.classSlots.Left then
        S.classPromptSlots.Left:ClearAllPoints()
        S.classPromptSlots.Left:SetPoint("CENTER", S.classSlots.Left, "CENTER", 0, promptOffY)
    end
    if S.classPromptSlots.Right and S.classSlots.Right then
        S.classPromptSlots.Right:ClearAllPoints()
        S.classPromptSlots.Right:SetPoint("CENTER", S.classSlots.Right, "CENTER", 0, promptOffY)
    end

    -- Anchor Trigger Guide icons to top-left above placard (replacing NO TRIGGER label)
    if S.guideHolder then
        S.guideHolder:SetSize(CFG.GUIDE_WIDTH, CFG.GUIDE_HEIGHT)
        S.guideHolder:ClearAllPoints()
        S.guideHolder:SetPoint("BOTTOMLEFT", S.holder, "BOTTOMLEFT", -CFG.PLATE_INSETS.left + CFG.LABEL_INSET_X, CFG.BUTTON_SIZE + CFG.PLATE_INSETS.top + CFG.LABEL_INSET_Y)
    end
    if S.toolsHolder then
        local w = HotbarSize(db)
        S.toolsHolder:SetSize(CFG.TOOLS_WIDTH, CFG.LABEL_SPACE)
        S.toolsHolder:ClearAllPoints()
        S.toolsHolder:SetPoint("TOPLEFT", S.holder, "TOP", w / 2 - CFG.TOOLS_WIDTH, 0)
    end
end

local function AnchorButtons(bar)
    local enlarged = bar.actionBarScaledUp
    S.reanchorBarGuard = true
    pcall(function()
        for _, button in ipairs(S.barButtons[bar]) do
            local slot = S.slots[button]
            if slot then
                button:ClearAllPoints()
                button:SetPoint("CENTER", slot, "CENTER")
                if enlarged then
                    button:SetSize(S.buttonSizes[button], S.buttonSizes[button])
                end
            end
        end
    end)
    S.reanchorBarGuard = false
end

local function BuildFlatRows(db)
    local newHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    local square = GamepadActionBarStyleUtil.squareStyleParams
    local round = GamepadActionBarStyleUtil.circleStyleParams
    local squareSize = type(square) == "table" and tonumber(square.collapsedSize) or CFG.BUTTON_SIZE
    local roundSize = type(round) == "table" and tonumber(round.collapsedSize) or CFG.ROUND_BUTTON_SIZE

    S.wrappedBars = {}
    for _, info in ipairs(S.flatBars) do
        if info.wrap then
            table.insert(S.wrappedBars, info.bar)
            info.wrapIndex = #S.wrappedBars
        end
    end

    for _, info in ipairs(S.flatBars) do
        local bar, buttons = info.bar, {}
        S.barButtons[bar] = buttons
        EachBarButton(bar, function(button, side, i)
            table.insert(buttons, button)
            S.buttonSizes[button] = (side == "Left") and squareSize or roundSize
            S.slotOffsets[button] = SlotOffsetX(side, i, db)
            if type(button.GetNumPoints) == "function" and button:GetNumPoints() > 0 then
                S.buttonPoints[button] = { button:GetPoint(1) }
            end
            local slot = CreateFrame("Frame", nil, bar, "SecureFrameTemplate")
            slot:SetSize(1, 1)
            slot:SetPoint("CENTER", S.holder, "BOTTOM", S.slotOffsets[button], CFG.BUTTON_SIZE / 2)
            S.slots[button] = slot
            if not S.barButtonHooked[button] then
                S.barButtonHooked[button] = true
                pcall(hooksecurefunc, button, "SetPoint", ReanchorBarButtonIfDrifted)
                if type(button.HookScript) == "function" then
                    pcall(button.HookScript, button, "OnShow", ReanchorBarButtonIfDrifted)
                end
            end
            if info.wrapIndex then
                pcall(SecureHandlerSetFrameRef, newHeader, "b" .. info.wrapIndex .. "-" .. #buttons, button)
                pcall(SecureHandlerSetFrameRef, newHeader, "s" .. info.wrapIndex .. "-" .. #buttons, slot)
            end
        end)
        if info.wrapIndex then
            local postClick = POST_CLICK:gsub("%$(%u+)", {
                COUNT = #buttons, BAR = info.wrapIndex, BARS = #S.wrappedBars, DIP = CFG.PRESSED_NUDGE_Y,
                GROUP = CFG.BUTTONS_PER_GROUP, SQUARE = squareSize, ROUND = roundSize,
            })
            S.postClicks[bar] = postClick
            for _, button in ipairs(buttons) do
                pcall(SecureHandlerWrapScript, button, "OnClick", newHeader, PRE_CLICK, postClick)
            end
        end
    end

    -- Secure slots + wrappers for inline class/pet/stance buttons (LeftClassAction / RightClassAction)
    for _, side in ipairs(CFG.SIDES) do
        local cSlot = CreateFrame("Frame", nil, S.pageUnit, "SecureFrameTemplate")
        cSlot:SetSize(1, 1)
        S.classSlots[side] = cSlot
        local pSlot = CreateFrame("Frame", nil, S.pageUnit, "SecureFrameTemplate")
        pSlot:SetSize(1, 1)
        S.classPromptSlots[side] = pSlot

        local cBtn = S.pageUnit[side .. "ClassAction"]
        local pFrm = S.pageUnit[side .. "InputPrompt"]
        local isFrameBtn = type(cBtn) == "table" and not IsForbiddenSafe(cBtn)
            and type(cBtn.IsObjectType) == "function" and select(2, pcall(cBtn.IsObjectType, cBtn, "Frame"))
        if isFrameBtn then
            local cRef = "classBtn" .. side
            local sRef = "classSlot" .. side
            local pRef = "classPrompt" .. side
            local psRef = "classPSlot" .. side
            local okRef = pcall(SecureHandlerSetFrameRef, newHeader, cRef, cBtn)
                and pcall(SecureHandlerSetFrameRef, newHeader, sRef, cSlot)
            if okRef then
                local isFramePrompt = type(pFrm) == "table" and not IsForbiddenSafe(pFrm)
                    and type(pFrm.IsObjectType) == "function" and select(2, pcall(pFrm.IsObjectType, pFrm, "Frame"))
                if isFramePrompt then
                    pcall(SecureHandlerSetFrameRef, newHeader, pRef, pFrm)
                    pcall(SecureHandlerSetFrameRef, newHeader, psRef, pSlot)
                end
                local snip = CLASS_POST_CLICK:gsub("%$(%u+)", {
                    CREF = cRef, SREF = sRef, PREF = pRef, PSREF = psRef,
                })
                pcall(SecureHandlerWrapScript, cBtn, "OnClick", newHeader, PRE_CLICK, snip)
                pcall(SecureHandlerWrapScript, cBtn, "OnShow", newHeader, PRE_CLICK, snip)
            end
        end
    end

    S.header = newHeader

    local resting
    for _, info in ipairs(S.flatBars) do
        if not info.bar.actionBarScaledUp then
            resting = info.bar
            break
        end
    end
    for _, info in ipairs(S.flatBars) do
        local bar = info.bar
        if resting and bar.actionBarScaledUp then
            for i, button in ipairs(S.barButtons[bar]) do
                local point = S.buttonPoints[S.barButtons[resting][i]]
                if point then
                    S.buttonPoints[button] = { point[1], point[2] == resting and bar or point[2], point[3], point[4], point[5] }
                end
            end
        end
    end
end

local function WrapFixedSlots()
    local topBar = S.bars[1]
    if not (topBar and S.header and S.postClicks[topBar]) then return end
    for i = 1, CFG.BUTTONS_PER_GROUP do
        SecureHandlerWrapScript(topBar.Right["ActionButton" .. i], "OnClick", S.header, PRE_CLICK, S.postClicks[topBar])
    end
end

PlaceSections = function()
    local db = GetDB()
    local scale = GetScale(db)
    S.pageUnit:SetScale(scale)

    local width, height = HotbarSize(db)
    local xOff = IsCenterXLocked(db) and 0 or (tonumber(db.x) or 0)
    S.holder:SetSize(width, height)
    S.holder:ClearAllPoints()
    S.holder:SetPoint("TOP", S.pageUnit, "CENTER", xOff / scale, (tonumber(db.y) or -16) / scale)

    local margin = CFG.SCREEN_MARGIN / (UnitSize() * scale)
    local left, right, top, bottom = ComputeBounds(db)
    S.holder:SetClampRectInsets((left + width / 2) - margin, (right - width / 2) + margin, top + margin, (bottom + height) - margin)

    local inline = (db.classButtonLayout or "INLINE") == "INLINE"
    local hasClass = HasClassButton("Left") or HasClassButton("Right")

    for index, anchor in ipairs(S.anchors) do
        anchor:SetScale(1)
        anchor:ClearAllPoints()
        if (not inline) and hasClass and index == #S.anchors then
            anchor:SetPoint("CENTER", S.holder, "BOTTOM", 0, CFG.BUTTON_SIZE / 2 + CFG.CLASS_BUTTON_Y)
        else
            anchor:SetPoint("CENTER", S.holder, "BOTTOM", 0, CFG.BUTTON_SIZE / 2)
        end
    end

    PlaceSlots(db)
    PlacePointer()
    SafeTry("classButtons", function()
        ApplyClassButtonFrames(db)
    end)
end

local function BuildLayoutFrames()
    local db = GetDB()
    S.holder = CreateFrame("Frame", nil, S.pageUnit)
    S.holder:SetMovable(true)
    S.holder:SetClampedToScreen(true)

    S.guideHolder = CreateFrame("Frame", nil, S.pageUnit)
    S.toolsHolder = CreateFrame("Frame", nil, S.pageUnit)

    for index, anchor in ipairs(S.anchors) do
        S.anchorPoints[index] = {}
        if type(anchor.GetNumPoints) == "function" then
            for i = 1, anchor:GetNumPoints() do
                S.anchorPoints[index][i] = { anchor:GetPoint(i) }
            end
        end
    end
    BuildFlatRows(db)
    SafeTry("classButtons", InstallClassButtonHooks)
    SafeTry("flyoutScan", ScanFlyoutCandidates)
    S.built = true
end

local function ApplyLayout()
    if not S.built then
        BuildLayoutFrames()
    end
    PlaceSections()
    for _, info in ipairs(S.flatBars) do
        AnchorButtons(info.bar)
    end
    S.header:SetAttribute("flat", true)
    S.applied = true
end

HandBack = function()
    S.applied = false
    if S.header then
        S.header:SetAttribute("flat", false)
    end
    if not S.holder then return end
    if S.dragging and S.mover then
        S.mover:StopMovingOrSizing()
        S.dragging = false
    end
    RestoreClassButtonFrames()
    RestoreFlyoutFrames()
    for index, anchor in ipairs(S.anchors) do
        local points = S.anchorPoints[index]
        if points and #points > 0 then
            anchor:ClearAllPoints()
            for _, pt in ipairs(points) do
                anchor:SetPoint(unpack(pt, 1, 5))
            end
        end
        anchor:SetScale(1)
        anchor:SetAlpha(1)
    end
    RestorePointer()
    if IsCVarOn("GamepadUseCompactActionBar") then
        local bottomAnchor = S.anchors[#S.anchors]
        for index = 1, #S.anchors - 1 do
            S.anchors[index]:ClearAllPoints()
            S.anchors[index]:SetAllPoints(bottomAnchor)
        end
    end
    S.pageUnit:SetScale(1)
    for button, point in pairs(S.buttonPoints) do
        if button:GetNumPoints() == 0 or select(2, button:GetPoint(1)) == S.slots[button] then
            button:ClearAllPoints()
            button:SetPoint(unpack(point, 1, 5))
        end
    end
end

HandBackWhenPossible = function()
    if InCombatLockdown() then
        S.handBackPending = true
    else
        xpcall(HandBack, geterrorhandler())
    end
end

--------------------------------------------------------------------------------
-- Styling (One Bar Plate, Wells, Labels, Glyphs, Page Tracker, Guide, Flash)
--------------------------------------------------------------------------------
local function EachMutedRegion(fn)
    if not S.pageUnit then return end
    for _, key in ipairs(CFG.MUTED_PAGE_ART) do
        local region = S.pageUnit[key]
        if region then fn(region) end
    end
    for _, info in ipairs(S.flatBars) do
        for _, key in ipairs(CFG.MUTED_BAR_ART) do
            local region = info.bar[key]
            if region then fn(region) end
        end
    end
end

local function MuteRegion(region)
    if type(region) ~= "table" or IsForbiddenSafe(region) then return end
    if type(region.GetAlpha) == "function" and type(region.SetAlpha) == "function" then
        if S.mutedAlpha[region] == nil then
            local ok, curA = pcall(region.GetAlpha, region)
            if ok then S.mutedAlpha[region] = curA end
        end
        pcall(region.SetAlpha, region, 0)
    end
end

local function UnmuteRegion(region)
    if type(region) ~= "table" or IsForbiddenSafe(region) then return end
    if S.mutedAlpha[region] ~= nil and type(region.SetAlpha) == "function" then
        pcall(region.SetAlpha, region, S.mutedAlpha[region])
    end
end

local function GetButtonAtlas(key)
    if not S.features.glyphs then return nil end
    return InputIconTextureSetUtility.GetActiveInputIconButtonTextures(key)
        and InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture(key)
end

local function SetGlyphAtlas(glyph, key)
    local atlas = GetButtonAtlas(key)
    if not atlas then
        glyph:SetTexture(nil)
        return
    end
    glyph:SetAtlas(atlas)
    local info = C_Texture.GetAtlasInfo(atlas)
    if info and info.width == CFG.PADDED_W and info.height == CFG.PADDED_H then
        glyph:SetTexCoord(unpack(CFG.PADDED_TC))
        glyph:SetSize(CFG.GLYPH_SIZE, CFG.GLYPH_SIZE)
    else
        glyph:SetTexCoord(0, 1, 0, 1)
        glyph:SetSize(CFG.PLAIN_GLYPH_SIZE, CFG.PLAIN_GLYPH_SIZE)
    end
end

local function FitGlyphs()
    local db = GetDB()
    local scale = tonumber(db.glyphScale)
    if scale == nil then scale = 1 end
    local pos = (db.glyphPosition == "CORNER") and "CORNER" or "BELOW"
    local belowOff = GetGlyphBelowOffset(db)
    local shown = S.styleShown and scale > 0
    if S.fitted.glyphScale == scale and S.fitted.glyphsShown == shown
        and S.fitted.glyphPos == pos and S.fitted.glyphBelowOff == belowOff then
        return
    end
    S.fitted.glyphScale, S.fitted.glyphsShown, S.fitted.glyphPos, S.fitted.glyphBelowOff = scale, shown, pos, belowOff
    for _, frame in ipairs(S.glyphFrames) do
        if scale > 0 then
            frame:SetScale(scale)
            frame:ClearAllPoints()
            if pos == "CORNER" then
                frame:SetPoint("TOPLEFT", S.glyphSlots[frame], "CENTER", CFG.GLYPH_CORNER_X / scale, CFG.GLYPH_CORNER_Y / scale)
            else
                frame:SetPoint("TOP", S.glyphSlots[frame], "CENTER", 0, -(CFG.BUTTON_SIZE / 2 + belowOff) / scale)
            end
        end
        frame:SetShown(shown)
    end
end

local function CreateGlyphs()
    for _, info in ipairs(S.flatBars) do
        EachBarButton(info.bar, function(button)
            local icon = button.ButtonIcon
            local key = type(icon) == "table" and icon.mappedButtonKey
            if type(key) ~= "string" then return end
            local frame = CreateFrame("Frame", nil, button)
            frame:SetFrameStrata("MEDIUM")
            if frame.SetFixedFrameStrata then frame:SetFixedFrameStrata(true) end
            frame:SetSize(CFG.GLYPH_SIZE, CFG.GLYPH_SIZE)
            local glyph = frame:CreateTexture(nil, "OVERLAY")
            glyph:SetPoint("CENTER")
            S.glyphs[glyph] = key
            S.glyphSlots[frame] = S.slots[button]
            table.insert(S.glyphFrames, frame)
            SetGlyphAtlas(glyph, key)
        end)
    end
end

local function UpdatePlateAndTrayGeometry(db)
    local sec = S.sectionArt and S.sectionArt[1]
    if sec and sec.bg then
        StylePlacardFrame(sec.bg)
    end
    for _, cPlate in pairs(S.classPlates) do
        StylePlacardFrame(cPlate)
    end
end

local function CreateSingleBarPlate()
    S.art = CreateFrame("Frame", nil, S.pageUnit)
    local insets = CFG.PLATE_INSETS
    local plate = CreateFrame("Frame", nil, S.art)
    plate:SetFrameStrata("BACKGROUND")
    plate:SetPoint("TOPLEFT", S.holder, "BOTTOMLEFT", -insets.left, CFG.BUTTON_SIZE + insets.top)
    plate:SetPoint("BOTTOMRIGHT", S.holder, "BOTTOMRIGHT", insets.right, -insets.bottom)

    local bg = CreateFrame("Frame", nil, plate)
    bg:SetFrameStrata("BACKGROUND")
    bg:SetFrameLevel(1)
    bg:SetAllPoints(plate)
    StylePlacardFrame(bg)

    S.sectionArt[1] = { plate = plate, bg = bg }

    UpdatePlateAndTrayGeometry(GetDB())
end

local function ArrangePageIndicator()
    local previous
    for i = #S.pageEntries, 1, -1 do
        local entry = S.pageEntries[i]
        if entry and entry.frame:IsShown() then
            local w = math.max(10, math.ceil(YRG.SafeNumber(entry.text:GetStringWidth(), 8)) + 4)
            local h = math.max(CFG.GUIDE_HEIGHT, math.ceil(YRG.SafeNumber(entry.text:GetStringHeight(), 12)) + 6)
            entry.frame:SetSize(w, h)
            entry.frame:ClearAllPoints()
            if previous then
                entry.frame:SetPoint("BOTTOMRIGHT", previous, "BOTTOMLEFT", -CFG.PAGE_SPACING, 0)
            else
                entry.frame:SetPoint("BOTTOMRIGHT", S.pageIndicator, "BOTTOMRIGHT")
            end
            previous = entry.frame
        end
    end
end

local function UpdatePageIndicator()
    if not (S.pageIndicator and S.pageUnit and S.pageTracker) then return end
    local currentPage = S.pageUnit:GetCurrentPage()
    local specialSlot = S.pageTracker.specialSlot
    local showSpecial = (type(S.pageUnit.IsSpecialPageAvailableForSelection) == "function")
        and (S.pageUnit:IsSpecialPageAvailableForSelection() and true or false)
        or (specialSlot ~= nil and specialSlot:IsShown())
    for i, slot in ipairs(S.pageTracker.slots) do
        local entry = S.pageEntries[i]
        if entry then
            if slot == specialSlot then
                entry.frame:SetShown(showSpecial)
            end
            if (slot.num or i) == currentPage then
                entry.text:SetTextColor(1, 1, 1)
                entry.frame:SetAlpha(1)
                entry.line:Show()
            else
                if slot.currentState == CFG.EMPTY_PAGE_STATE then
                    entry.text:SetTextColor(unpack(CFG.EMPTY_PAGE_COLOR))
                else
                    entry.text:SetTextColor(unpack(CFG.AVAILABLE_PAGE_COLOR))
                end
                entry.frame:SetAlpha(CFG.GUIDE_UNLIT_ALPHA)
                entry.line:Hide()
            end
        end
    end
    if showSpecial ~= S.specialPageShown then
        S.specialPageShown = showSpecial
        ArrangePageIndicator()
    end
end

local function OnPageTrackerRefreshed()
    if S.pageIndicator and not SafeTry("pages", UpdatePageIndicator) then
        S.pageIndicator:Hide()
        S.pageIndicator = nil
        if S.pageTracker then S.pageTracker:SetAlpha(1) end
    end
end

local function CreatePageIndicator()
    S.pageTracker = S.pageUnit.PageTracker
    local indicator = CreateFrame("Frame", nil, S.art)
    indicator:SetSize(1, 1)
    indicator:SetPoint("BOTTOMRIGHT", S.toolsHolder, "TOPRIGHT", CFG.PLATE_INSETS.right - CFG.LABEL_INSET_X, -(CFG.LABEL_SPACE - CFG.PLATE_INSETS.top - CFG.LABEL_INSET_Y))

    local accentColor = GetAccentColor(GetDB())
    for i, slot in ipairs(S.pageTracker.slots) do
        local entryFrame = CreateFrame("Frame", nil, indicator)
        entryFrame:SetAlpha(CFG.GUIDE_UNLIT_ALPHA)

        local fs = entryFrame:CreateFontString(nil, "OVERLAY")
        fs:SetFontObject(GameFontNormalSmallOutline or GameFontNormalSmall)
        fs:SetPoint("BOTTOM", entryFrame, "BOTTOM", 0, 4)
        fs:SetText(slot == S.pageTracker.specialSlot and "S" or tostring(slot.num or i))

        local line = entryFrame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(2)
        line:SetPoint("BOTTOMLEFT", entryFrame, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", entryFrame, "BOTTOMRIGHT", 0, 0)
        line:SetColorTexture(accentColor[1], accentColor[2], accentColor[3])
        line:Hide()

        S.pageTexts[i] = fs
        S.pageEntries[i] = { frame = entryFrame, text = fs, line = line }
    end

    S.pageIndicator = indicator
    ArrangePageIndicator()
    hooksecurefunc(S.pageUnit, "RefreshPageTracker", OnPageTrackerRefreshed)
    hooksecurefunc(S.pageUnit, "RefreshPageTrackerSpecialPageSlotVisibility", OnPageTrackerRefreshed)
    local possessBar = type(S.pageUnit.actionBars) == "table" and S.pageUnit.actionBars.possessBar
    if type(possessBar) == "table" and type(possessBar.ActivateOverrideBar) == "function" then
        hooksecurefunc(possessBar, "ActivateOverrideBar", OnPageTrackerRefreshed)
    end
    UpdatePageIndicator()
end

local function CreateGuide()
    local frame = CreateFrame("Frame", nil, S.art)
    S.guide, S.guideLit = frame, false
    frame:SetSize(CFG.GUIDE_WIDTH, CFG.GUIDE_HEIGHT)
    frame:SetPoint("TOPLEFT", S.guideHolder, "TOPLEFT")
    local x = 0
    for side = 1, 2 do
        local entry = CreateFrame("Frame", nil, frame)
        entry:SetSize(CFG.GUIDE_ICON, CFG.GUIDE_HEIGHT)
        entry:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
        entry:SetAlpha(CFG.GUIDE_UNLIT_ALPHA)
        local icon = entry:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", entry, "TOP", 0, -CFG.GUIDE_ICON / 2)
        S.glyphs[icon] = CFG.TRIGGER_KEYS[side]
        SetGlyphAtlas(icon, CFG.TRIGGER_KEYS[side])
        local text = entry:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(GameFontNormalSmallOutline or GameFontNormalSmall)
        text:SetPoint("CENTER", entry, "TOP", 0, -CFG.GUIDE_ICON / 2)
        local line = entry:CreateTexture(nil, "ARTWORK")
        line:SetHeight(2)
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:Hide()
        S.guideEntries[side] = { frame = entry, line = line, text = text, icons = { icon } }
        x = x + CFG.GUIDE_ICON + CFG.GUIDE_GAP
    end
end

local function RefreshGuideArt()
    for side, entry in pairs(S.guideEntries) do
        local hasArt = true
        for _, icon in ipairs(entry.icons) do
            hasArt = hasArt and icon:GetAtlas() ~= nil
        end
        for _, icon in ipairs(entry.icons) do
            icon:SetShown(hasArt)
        end
        entry.text:SetText(GetSectionLabel(side + 1))
        entry.text:SetShown(not hasArt)
    end
end

local function UpdateGuide(activeIndex)
    local lit = (activeIndex and activeIndex > 1) and activeIndex or false
    if S.guide and lit ~= S.guideLit and S.guide:IsShown() then
        S.guideLit = lit
        local held = lit and CFG.SECTION_TRIGGERS[lit] or {}
        local isHeld = {}
        for _, side in ipairs(held) do
            isHeld[side] = true
        end
        for side, entry in pairs(S.guideEntries) do
            local active = isHeld[side] and true or false
            entry.frame:SetAlpha(active and 1 or CFG.GUIDE_UNLIT_ALPHA)
            entry.line:SetShown(active)
        end
    end
end

local function CreateFlashes()
    for i = 1, CFG.FLASH_COUNT do
        local frame = CreateFrame("Frame", nil, S.art)
        frame:Hide()
        frame:SetFrameStrata("MEDIUM")
        frame:SetSize(CFG.BUTTON_SIZE, CFG.BUTTON_SIZE)
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetBlendMode("ADD")
        S.flashes[i], S.flashTextures[i] = frame, texture
    end
end

local function StopFlashes()
    S.flashesBusy = false
    for frame in pairs(S.flashLeft) do
        S.flashLeft[frame] = nil
        frame:Hide()
    end
end

local function FlashPressedButton()
    local bar = S.pageUnit and S.pageUnit:GetActiveBar()
    local button = bar and type(bar.actionButtons) == "table" and bar.actionButtons[S.pressedIndex]
    local slot = button and S.slots[button]
    if not (slot and button:IsVisible()) then return end
    local frame = S.flashes[S.nextFlash]
    S.nextFlash = S.nextFlash % CFG.FLASH_COUNT + 1
    local scale = YRG.SafeNumber(button:GetEffectiveScale(), 1) / math.max(YRG.SafeNumber(S.art:GetEffectiveScale(), 1), 0.01)
    if S.flashScales[frame] ~= scale then
        S.flashScales[frame] = scale
        frame:SetScale(scale)
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", slot, "CENTER")
    frame:SetAlpha(CFG.FLASH_PEAK)
    frame:Show()
    S.flashLeft[frame] = CFG.FLASH_SECONDS
    S.flashesBusy = true
    if S.fader then S.fader:Show() end
end

local function OnButtonPressed(_, index, _, down)
    local db = GetDB()
    if down and S.styleShown and db and db.flash ~= false and S.flashes[1] and S.fader then
        S.pressedIndex = index
        SafeTry("flash", FlashPressedButton)
    end
end

local function GetOverrideOn(index)
    local anchor = S.anchors[index]
    for _, info in ipairs(S.flatBars) do
        if not info.section and info.bar:IsShown() and info.bar:GetParent() == anchor then
            return info
        end
    end
end

-- In One-Bar mode, only the active trigger's section is visible (alpha 1); others are hidden (alpha 0).
local function UpdateSections()
    if not S.pageUnit then return end
    local activeBar = S.pageUnit:GetActiveBar()
    local activeIndex = activeBar and S.sectionOfAnchor[activeBar:GetParent()]
    local shownIdx = activeIndex or 1

    for index, anchor in ipairs(S.anchors) do
        local override = GetOverrideOn(index)
        local bar = override and override.bar or S.bars[index]
        local barAlpha = bar and math.max(bar:GetAlpha(), CFG.MIN_BAR_ALPHA) or 1
        local target = (index == shownIdx) and (1 / barAlpha) or 0
        anchor:SetAlpha(math.min(1, target))
    end

    UpdateGuide(activeIndex)
end

RefreshEmphasis = function()
    if S.styleShown and not SafeTry("emphasis", UpdateSections) then
        for _, anchor in ipairs(S.anchors) do
            anchor:SetAlpha(1)
        end
    end
end

local function SetFontScaleSafe(fs, scale)
    if type(fs) ~= "table" then return end
    local s = tonumber(scale) or 1
    if type(fs.SetTextScale) == "function" then
        pcall(fs.SetTextScale, fs, s)
        return
    end
    if type(fs.GetFont) == "function" and type(fs.SetFont) == "function" then
        local ok, path, size, flags = pcall(fs.GetFont, fs)
        if ok and path and type(size) == "number" then
            if not S.fontBaseSizes[fs] then
                S.fontBaseSizes[fs] = size
            end
            local targetSize = math.max(6, math.floor(S.fontBaseSizes[fs] * s + 0.5))
            pcall(fs.SetFont, fs, path, targetSize, flags)
        end
    end
end

FitStyle = function()
    if not S.styled then return end
    local db = GetDB()

    SafeTry("plates", function()
        UpdatePlateAndTrayGeometry(db)
        local showBg = (db.showBarBackground ~= false)
        local sec = S.sectionArt[1]
        if sec and sec.bg then
            sec.bg:SetShown(showBg)
        end
        if S.tray then
            S.tray:SetShown(S.styleShown and showBg)
        end
        for _, txt in pairs(S.pageTexts) do
            SetFontScaleSafe(txt, tonumber(db.labelScale) or 1)
        end
        local c = GetAccentColor(db)
        for _, entry in pairs(S.guideEntries) do
            entry.line:SetColorTexture(c[1], c[2], c[3])
        end
        for _, entry in pairs(S.pageEntries) do
            entry.line:SetColorTexture(c[1], c[2], c[3])
        end
        for _, tex in ipairs(S.flashTextures) do
            tex:SetColorTexture(c[1], c[2], c[3])
        end
        for side, plate in pairs(S.classPlates) do
            local btn = S.pageUnit and S.pageUnit[side .. "ClassAction"]
            local showClassPlate = S.styleShown and showBg and btn and btn:IsShown()
                and (db.classButtonLayout or "INLINE") == "INLINE"
                and (db.squareClassButtons ~= false)
            plate:SetShown(showClassPlate and true or false)
        end
        if S.pageIndicator then
            ArrangePageIndicator()
            OnPageTrackerRefreshed()
        end
    end)

    if S.features.glyphs then
        SafeTry("glyphs", FitGlyphs)
    end
    if S.guide then
        SafeTry("guide", function()
            local shown = S.styleShown and (db.guide ~= false)
            if shown ~= S.guide:IsShown() then
                S.guide:SetShown(shown)
                S.guideLit = nil
            end
        end)
    end
    RefreshEmphasis()
end

SetStyleShown = function(shown)
    if not S.styled or shown == S.styleShown then return end
    S.styleShown = shown
    local db = GetDB()
    local showBg = (not db) or (db.showBarBackground ~= false)
    if S.art then S.art:SetShown(shown) end
    if S.tray then S.tray:SetShown(shown and showBg) end
    S.fitted.glyphsShown = nil
    if S.features.glyphs then
        SafeTry("glyphs", FitGlyphs)
    end
    EachMutedRegion((shown and S.art ~= nil) and MuteRegion or UnmuteRegion)
    if S.pageIndicator and type(S.pageTracker) == "table" and type(S.pageTracker.SetAlpha) == "function" then
        pcall(S.pageTracker.SetAlpha, S.pageTracker, shown and 0 or 1)
    end
    if not shown then
        StopFlashes()
        for _, anchor in ipairs(S.anchors) do
            anchor:SetAlpha(1)
        end
        for _, plate in pairs(S.classPlates) do
            plate:Hide()
        end
    end
end

local function CreateFader()
    S.fader = CreateFrame("Frame")
    S.fader:Hide()
    S.fader:SetScript("OnUpdate", function(self, elapsed)
        S.flashesBusy = false
        for frame, left in pairs(S.flashLeft) do
            left = left - elapsed
            if left > 0 then
                S.flashLeft[frame] = left
                frame:SetAlpha(CFG.FLASH_PEAK * left / CFG.FLASH_SECONDS)
                S.flashesBusy = true
            else
                S.flashLeft[frame] = nil
                frame:Hide()
            end
        end
        if not S.flashesBusy then
            self:Hide()
        end
    end)
end

local function WatchBlizzardStyle()
    if S.features.activeBarCallback then
        S.pageUnit:RegisterActiveActionBarUpdatedCallback(RefreshEmphasis, S.sectionArt)
    else
        hooksecurefunc(S.pageUnit, "SetActiveActionBar", RefreshEmphasis)
    end
    for _, info in ipairs(S.flatBars) do
        hooksecurefunc(info.bar, "SetAlpha", function(bar)
            if S.styleShown and S.sectionOfAnchor[bar:GetParent()] then
                RefreshEmphasis()
            end
        end)
    end
    if S.features.glyphs or S.features.triggerNames then
        InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(function()
            S.iconMarkup = {}
            if S.features.glyphs then
                SafeTry("glyphs", function()
                    for g, key in pairs(S.glyphs) do SetGlyphAtlas(g, key) end
                end)
            end
            if S.guide then
                SafeTry("guide", RefreshGuideArt)
            end
            RefreshEmphasis()
        end, S.glyphs)
    end
    if S.features.pressFlash then
        hooksecurefunc(GamepadMainActionBarFrame, "PressActionButton", OnButtonPressed)
    end
end

ApplyStyle = function()
    if not S.styled then
        S.styled = true
        SafeTry("plates", CreateSingleBarPlate)
        if S.features.glyphs then SafeTry("glyphs", CreateGlyphs) end
        local tracker = S.pageUnit and S.pageUnit.PageTracker
        if S.art and S.features.pageIndicator and type(tracker) == "table" and type(tracker.slots) == "table" then
            if not SafeTry("pages", CreatePageIndicator) and S.pageIndicator then
                S.pageIndicator:Hide()
                S.pageIndicator = nil
            end
        end
        if S.art then
            SafeTry("guide", CreateGuide)
            if S.guide then SafeTry("guide", RefreshGuideArt) end
            if S.features.pressFlash then SafeTry("flash", CreateFlashes) end
        end
        SafeTry("emphasis", CreateFader)
        SafeTry("emphasis", WatchBlizzardStyle)
    end
    SetStyleShown(true)
    SafeTry("classButtons", function()
        ApplyClassButtonFrames(GetDB())
    end)
    FitStyle()
end

--------------------------------------------------------------------------------
-- Whole-Bar Drag Mover (Out-of-Combat Move & Corner Resize)
--------------------------------------------------------------------------------
UpdateMoverBox = function()
    if not (S.mover and S.holder) then return end
    local db = GetDB()
    local left, right, top, bottom = ComputeBounds(db)
    S.mover:ClearAllPoints()
    S.mover:SetPoint("TOPLEFT", S.holder, "TOP", left - 6, top + 6)
    S.mover:SetPoint("BOTTOMRIGHT", S.holder, "TOP", right + 6, bottom - 6)
end

local function UpdateMoverAxisButton()
    if S.moverAxisBtn then
        S.moverAxisBtn:SetText(IsCenterXLocked(GetDB()) and "Vertical Only" or "All Directions")
    end
end

local function SaveWholeBarDrop()
    if not (S.holder and S.pageUnit) then return end
    local holderX, holderTop = S.holder:GetCenter(), S.holder:GetTop()
    local unitX, unitY = S.pageUnit:GetCenter()
    if holderX and holderTop and unitX and unitY then
        local db = GetDB()
        local scale = GetScale(db)
        if IsCenterXLocked(db) then
            db.x = 0
        else
            local x = math.floor((holderX - unitX) * scale + 0.5)
            db.x = math.abs(x) <= CFG.CENTRE_SNAP and 0 or x
        end
        db.y = math.floor((holderTop - unitY) * scale + 0.5)
    end
end

local function CreateMoverOverlay()
    local mover = CreateFrame("Frame", nil, S.holder)
    mover:Hide()
    mover:SetFrameStrata("DIALOG")
    mover:EnableMouse(true)
    mover:EnableMouseWheel(true)
    mover:RegisterForDrag("LeftButton")

    local fill = mover:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.31, 0.76, 0.97, 0.14)
    for _, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false },
        { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true },
    }) do
        local edge = mover:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(0.31, 0.76, 0.97, 0.9)
        edge:SetPoint(spec[1])
        edge:SetPoint(spec[2])
        if spec[3] then edge:SetWidth(2) else edge:SetHeight(2) end
    end

    mover:SetScript("OnDragStart", function(self)
        if S.applied and not S.dragging and not InCombatLockdown() then
            S.dragging = true
            local db = GetDB()
            if IsCenterXLocked(db) then
                local _, startCursorY = GetCursorPosition()
                local startYVal = tonumber(db and db.y) or -16
                local parentFrame = S.pageUnit and S.pageUnit:GetParent()
                local parentEff = math.max(YRG.SafeNumber(parentFrame and parentFrame:GetEffectiveScale(), 1), 0.01)
                self:SetScript("OnUpdate", function()
                    if not S.dragging or InCombatLockdown() then
                        self:SetScript("OnUpdate", nil)
                        return
                    end
                    local curDB = GetDB()
                    local _, curY = GetCursorPosition()
                    local nextY = math.floor(startYVal + (curY - startCursorY) / parentEff + 0.5)
                    local scale = GetScale(curDB)
                    local _, _, topB, botB = ComputeBounds(curDB)
                    local pageEff = math.max(YRG.SafeNumber(S.pageUnit and S.pageUnit:GetEffectiveScale(), 1), 0.01)
                    local uScale = math.max(YRG.SafeNumber(UIParent and UIParent:GetEffectiveScale(), 1), 0.01)
                    local uH = YRG.SafeNumber(UIParent and UIParent:GetHeight(), 800)
                    local _, unitY = S.pageUnit:GetCenter()
                    if unitY then
                        local minHolderTop = (CFG.SCREEN_MARGIN * uScale) / pageEff - botB
                        local maxHolderTop = ((uH - CFG.SCREEN_MARGIN) * uScale) / pageEff - topB
                        local minY = math.floor((minHolderTop - unitY) * scale + 0.5)
                        local maxY = math.floor((maxHolderTop - unitY) * scale + 0.5)
                        if minY <= maxY then
                            nextY = math.max(minY, math.min(maxY, nextY))
                        end
                    end
                    if curDB then
                        curDB.x = 0
                        curDB.y = nextY
                    end
                    S.holder:ClearAllPoints()
                    S.holder:SetPoint("TOP", S.pageUnit, "CENTER", 0, nextY / scale)
                end)
            else
                S.holder:StartMoving()
            end
        end
    end)
    mover:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if S.dragging and not InCombatLockdown() then
            S.dragging = false
            local db = GetDB()
            if IsCenterXLocked(db) then
                if db then db.x = 0 end
            else
                S.holder:StopMovingOrSizing()
                SaveWholeBarDrop()
            end
            PlaceSections()
            FitStyle()
            UpdateMoverBox()
            if S.settingsCtx then S.settingsCtx:NotifyAll() end
        end
    end)
    mover:SetScript("OnMouseWheel", function(_, delta)
        if not InCombatLockdown() then
            local db = GetDB()
            db.scale = math.min(Snap((db.scale or 1) + delta * CFG.STEP, CFG.SCALE_RANGE), FitScaleForMargin(db, CFG.SCREEN_MARGIN))
            PlaceSections()
            FitStyle()
            UpdateMoverBox()
            if S.settingsCtx then S.settingsCtx:NotifyAll() end
        end
    end)

    local grip = CreateFrame("Button", nil, mover)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self)
        if InCombatLockdown() then return end
        local db = GetDB()
        local startX, startScale = GetCursorPosition(), GetScale(db)
        local startW = mover:GetWidth() * mover:GetEffectiveScale()
        self:SetScript("OnUpdate", function()
            if InCombatLockdown() then self:SetScript("OnUpdate", nil); return end
            local wanted = startScale * (1 + 2 * (GetCursorPosition() - startX) / math.max(startW, 1))
            local nextScale = math.min(Snap(wanted, CFG.SCALE_RANGE), FitScaleForMargin(db, CFG.SCREEN_MARGIN))
            if nextScale ~= GetScale(db) then
                db.scale = nextScale
                PlaceSections()
                FitStyle()
                UpdateMoverBox()
                if S.settingsCtx then S.settingsCtx:NotifyAll() end
            end
        end)
    end)
    local function StopGrip(self) self:SetScript("OnUpdate", nil) end
    grip:SetScript("OnMouseUp", StopGrip)
    grip:SetScript("OnHide", StopGrip)

    local lockBtn = CreateFrame("Button", nil, mover, "UIPanelButtonTemplate")
    lockBtn:SetSize(110, 22)
    lockBtn:SetPoint("BOTTOMRIGHT", mover, "TOPRIGHT", 0, 4)
    lockBtn:SetText("Lock Hotbar")
    lockBtn:SetScript("OnClick", function()
        SetMoverActive(false)
    end)

    local axisBtn = CreateFrame("Button", nil, mover, "UIPanelButtonTemplate")
    axisBtn:SetSize(116, 22)
    axisBtn:SetPoint("RIGHT", lockBtn, "LEFT", -6, 0)
    axisBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        local db = GetDB()
        if db then
            local lockNow = not IsCenterXLocked(db)
            db.lockCenterX = lockNow
            if lockNow then
                db.x = 0
            end
        end
        UpdateMoverAxisButton()
        PlaceSections()
        FitStyle()
        UpdateMoverBox()
        if S.settingsCtx then S.settingsCtx:NotifyAll() end
    end)

    S.mover = mover
    S.moverLockBtn = lockBtn
    S.moverAxisBtn = axisBtn
    UpdateMoverAxisButton()
end

SetMoverActive = function(active)
    if active and (InCombatLockdown() or not S.applied or not S.holder or not S.holder:IsVisible()) then
        active = false
    end
    S.moving = active
    if active and not S.mover then
        CreateMoverOverlay()
    end
    if not S.mover then return end
    if not active then
        S.mover:SetScript("OnUpdate", nil)
        if S.dragging and not InCombatLockdown() then
            S.dragging = false
            S.holder:StopMovingOrSizing()
        end
    end
    if active then
        UpdateMoverAxisButton()
        UpdateMoverBox()
        S.mover:Show()
    else
        S.mover:Hide()
    end
end

--------------------------------------------------------------------------------
-- Refresh / Menu-Safe Scheduler & Lifecycle
--------------------------------------------------------------------------------
local function RefreshWhenMenusClose()
    if S.menuTicker then return end
    S.menuTicker = C_Timer.NewTicker(0.2, function()
        if not IsMenuOpen() then
            S.menuTicker:Cancel()
            S.menuTicker = nil
            CompactBar:Refresh()
        end
    end)
end

SyncLayout = function()
    if not ShouldBeActiveNow() then
        SetMoverActive(false)
        SetStyleShown(false)
        if S.built and S.applied then
            HandBack()
        end
        return
    end
    if IsMenuOpen() then
        if S.built and not S.applied then
            HandBack()
        end
        RefreshWhenMenusClose()
        return
    end
    if not S.dragging then
        ApplyLayout()
        ApplyStyle()
        if S.moving then
            UpdateMoverBox()
        end
        CompactBar:UpdateStatusText()
    end
end

function CompactBar:Refresh()
    if not S.initialized then return end
    if S.stopped then
        if S.built then HandBackWhenPossible() end
        return
    end
    if not ShouldBeActiveNow() then
        SetMoverActive(false)
        SetStyleShown(false)
        if S.built then HandBackWhenPossible() end
        return
    end
    RunOutOfCombat("layout", SyncLayout)
end

local function ScanBlizzardFrames()
    local scan = { missing = {}, features = {}, anchors = {}, bars = {} }
    local function need(path, val, wantType)
        if type(val) == wantType then return val end
        scan.missing[#scan.missing + 1] = path
        return nil
    end
    for _, path in ipairs(CFG.REQUIRED_FUNCS) do
        need(path, ResolvePath(path), "function")
    end
    for feat, paths in pairs(CFG.OPTIONAL_FUNCS) do
        local ok = true
        for _, p in ipairs(paths) do
            ok = ok and type(ResolvePath(p)) == "function"
        end
        scan.features[feat] = ok
    end
    local root = need("GamepadMainActionBarFrame", GamepadMainActionBarFrame, "table")
    local pageUnit = root and need("GamepadMainActionBarFrame.PageUnit", root.PageUnit, "table")
    scan.root, scan.pageUnit = root, pageUnit
    if not pageUnit then return scan end

    for idx, sec in ipairs(CFG.SECTIONS) do
        local ap = "PageUnit." .. sec.anchorKey
        local anchor = need(ap, pageUnit[sec.anchorKey], "table")
        local bar = anchor and need(ap .. ".Bar", anchor.Bar, "table")
        scan.anchors[idx], scan.bars[idx] = anchor, bar
        if bar then
            for _, side in ipairs(CFG.SIDES) do
                local gp = ap .. ".Bar." .. side
                local group = need(gp, bar[side], "table")
                for i = 1, CFG.BUTTONS_PER_GROUP do
                    need(gp .. ".ActionButton" .. i, group and group["ActionButton" .. i], "table")
                end
            end
        end
    end
    return scan
end

local function HasButtonGroups(bar)
    if type(bar) ~= "table" then return false end
    for _, side in ipairs(CFG.SIDES) do
        local grp = bar[side]
        for i = 1, CFG.BUTTONS_PER_GROUP do
            if type(grp) ~= "table" or type(grp["ActionButton" .. i]) ~= "table" then
                return false
            end
        end
    end
    return true
end

local function CollectFlatBars(scan)
    local out = {}
    for index, bar in ipairs(scan.bars) do
        table.insert(out, { bar = bar, key = "section" .. index, section = index, wrap = true })
    end
    local actionBars = scan.pageUnit and scan.pageUnit.actionBars
    for _, ov in ipairs(CFG.OVERRIDE_BARS) do
        local bar = type(actionBars) == "table" and actionBars[ov.key]
        if HasButtonGroups(bar) then
            table.insert(out, { bar = bar, key = ov.key, wrap = ov.wrap, label = ov.label, title = ov.title })
        end
    end
    return out
end

local function InstallBlizzardHooks()
    if S.hooksInstalled or not S.pageUnit or not S.root then return end
    S.hooksInstalled = true

    hooksecurefunc(S.pageUnit, "RefreshCompactLayout", function()
        if S.applied then RunOutOfCombat("sections", function()
            if S.applied then PlaceSections(); FitStyle() end
        end) end
    end)

    local restyleJobs, restyleKeys = {}, {}
    for _, info in ipairs(S.flatBars) do
        local bar = info.bar
        restyleJobs[bar] = function()
            if S.applied then AnchorButtons(bar) end
        end
        restyleKeys[bar] = "buttons_" .. info.key
    end
    local function OnBarRestyled(bar)
        if S.applied and restyleJobs[bar] and not IsBlocked() then
            RunOutOfCombat(restyleKeys[bar], restyleJobs[bar])
        end
    end
    hooksecurefunc(GamepadActionBarStyleUtil, "ApplyCollapsedActionBarStyle", OnBarRestyled)
    hooksecurefunc(GamepadActionBarStyleUtil, "ApplyExpandedActionBarStyle", OnBarRestyled)

    hooksecurefunc(GamepadMainActionBarFrame, "SetupNonbindableActions", function()
        if S.built then RunOutOfCombat("fixed_slots", WrapFixedSlots) end
    end)

    if type(S.root.HookScript) == "function" then
        S.root:HookScript("OnShow", function()
            CompactBar:Refresh()
        end)
        S.root:HookScript("OnHide", function()
            SetMoverActive(false)
            SetStyleShown(false)
        end)
    end

    if S.features.releaseFix then
        local releasedIndex
        local strayReleases = {}
        local function ClearPushedLook()
            for _, bar in ipairs(S.wrappedBars) do
                local btn = S.barButtons[bar][releasedIndex]
                if btn and btn:IsEnabled() then btn:SetButtonState("NORMAL") end
            end
        end
        local function ResetStrayReleases()
            for index in pairs(strayReleases) do
                strayReleases[index] = nil
                for _, bar in ipairs(S.wrappedBars) do
                    local btn = S.applied and S.barButtons[bar][index]
                    if btn and S.slots[btn] then
                        btn:ClearAllPoints()
                        btn:SetPoint("CENTER", S.slots[btn], "CENTER")
                        btn:SetSize(S.buttonSizes[btn], S.buttonSizes[btn])
                    end
                end
            end
        end
        hooksecurefunc(GamepadMainActionBarFrame, "PressActionButton", function(_, index, _, down)
            if S.applied then
                if not down then
                    releasedIndex = index
                    SafeTry("releaseFix", ClearPushedLook)
                    local activeBar = S.pageUnit:GetActiveBar()
                    if activeBar and not S.postClicks[activeBar] then
                        strayReleases[index] = true
                        RunOutOfCombat("released_buttons", ResetStrayReleases)
                    end
                elseif down then
                    C_Timer.After(0, ScanFlyoutCandidates)
                end
            end
        end)
    end

    if S.features.settingWatch and CVarCallbackRegistry then
        local function OnCVar()
            C_Timer.After(0, function() CompactBar:Refresh() end)
        end
        local owner = {}
        CVarCallbackRegistry:RegisterCallback("GamepadUseCompactActionBar", OnCVar, owner)
        CVarCallbackRegistry:RegisterCallback("GamepadShowActionBarScaling", OnCVar, owner)
        local function OnOverrideMoved()
            C_Timer.After(0, function()
                if S.applied then RunOutOfCombat("sections", function()
                    if S.applied then PlaceSections(); FitStyle() end
                end) end
            end)
        end
        CVarCallbackRegistry:RegisterCallback("GamepadPossessBarOverride", OnOverrideMoved, owner)
        CVarCallbackRegistry:RegisterCallback("GamepadStanceBarOverride", OnOverrideMoved, owner)
    end
end

local function TryInitializeBlizzardBars()
    if S.initialized then return true end
    if IsStandaloneTriggerBarLoaded() then
        S.conflictTriggerBar = true
        return false
    end
    local scan = ScanBlizzardFrames()
    S.root = scan.root
    S.pageUnit = scan.pageUnit
    S.features = scan.features
    if #scan.missing > 0 then
        S.disabled = true
        S.missing = scan.missing
        return false
    end
    S.disabled = false
    S.missing = {}
    S.anchors = scan.anchors
    S.bars = scan.bars
    S.flatBars = CollectFlatBars(scan)
    S.flatBarInfo, S.sectionOfAnchor = {}, {}
    for _, info in ipairs(S.flatBars) do
        S.flatBarInfo[info.bar] = info
    end
    for index, anchor in ipairs(S.anchors) do
        S.sectionOfAnchor[anchor] = index
    end
    InstallBlizzardHooks()
    S.initialized = true
    return true
end

function CompactBar:GetStatusMessage()
    local db = GetDB()
    if IsStandaloneTriggerBarLoaded() then
        return "Paused: Standalone TriggerBar addon is enabled (disable TriggerBar to avoid conflicts)."
    elseif not db or not db.enabled then
        return "Disabled in YRG module settings."
    elseif S.disabled then
        return "Inactive: Missing Blizzard GamepadActionBars (" .. (#S.missing > 0 and S.missing[1] or "not loaded") .. ")."
    elseif S.stopped then
        if S.lastError and S.lastError ~= "" then
            return "Stopped after layout error (" .. S.lastError .. ")."
        end
        return "Stopped after a layout error (/reload to reset)."
    elseif not IsGamepadUIOn() then
        return "Standby: Visible only when Controller / Gamepad UI Mode is active."
    elseif IsBlocked() then
        return "Paused: Turn off " .. table.concat(GetBlockers(), " & ") .. " in Options > Gameplay > Gamepad."
    elseif S.applied then
        local arr = (db.arrangement == "XYAB") and "XYAB" or "XYBA"
        return string.format("Active (One Bar, %s, Pad %dpx, Scale %d%%).",
            arr, GetPadding(db), math.floor(GetScale(db) * 100 + 0.5))
    else
        return "Ready (applies automatically when settings close / combat ends)."
    end
end

function CompactBar:UpdateStatusText()
    if self._statusInitializer and self._statusInitializer.data then
        self._statusInitializer.data.name = "Status: " .. self:GetStatusMessage()
    end
end

function CompactBar:OnInitialize(db)
    -- Migrate/sanitize DB values cleanly
    db.buttonPadding = GetPadding(db)
    if db.arrangement == "XYAB" then
        db.arrangement = "XYAB"
    else
        db.arrangement = "XYBA"
    end
    db.classButtonLayout = (db.classButtonLayout == "BELOW") and "BELOW" or "INLINE"
    db.classPromptScale = nil
    if db.glyphPosition ~= "CORNER" and db.glyphPosition ~= "BELOW" then
        db.glyphPosition = "BELOW"
    end
    db.glyphBelowOffset = GetGlyphBelowOffset(db)
    if db.lockCenterX == nil then db.lockCenterX = true end
    if IsCenterXLocked(db) then db.x = 0 end
    if db.showBarBackground == nil then db.showBarBackground = true end
    db.labelStyle = nil
    db.accent = nil
    db.scale = Snap(db.scale or 1, CFG.SCALE_RANGE)

    self.eventFrame = CreateFrame("Frame")
    for _, ev in ipairs({
        "ADDON_LOADED", "PLAYER_LOGIN", "VARIABLES_LOADED",
        "INPUT_DEVICE_INTERFACE_TRANSITION", "GAME_PAD_ACTIVE_CHANGED",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
        "UPDATE_SHAPESHIFT_FORM", "PET_BAR_UPDATE", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED",
    }) do
        pcall(self.eventFrame.RegisterEvent, self.eventFrame, ev)
    end
    self.eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" and arg1 == "Blizzard_GamepadActionBars" then
            if S.enabled then
                TryInitializeBlizzardBars()
                CompactBar:Refresh()
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            SetMoverActive(false)
        elseif event == "PLAYER_REGEN_ENABLED" then
            if S.handBackPending then
                S.handBackPending = false
                xpcall(HandBack, geterrorhandler())
            end
            if S.barDriftPending and S.applied then
                RunOutOfCombat("reanchor_bars", ReanchorDriftedBarButtons)
            end
            local order, work = S.pendingOrder, S.pendingWork
            S.pendingOrder, S.pendingWork = {}, {}
            for _, key in ipairs(order) do
                RunOutOfCombat(key, work[key])
            end
        elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "PET_BAR_UPDATE"
            or event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" then
            if S.enabled and S.built then
                ScanFlyoutCandidates()
            end
        elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" or event == "GAME_PAD_ACTIVE_CHANGED" then
            C_Timer.After(0, function()
                if S.enabled and not S.initialized then
                    TryInitializeBlizzardBars()
                end
                CompactBar:Refresh()
                CompactBar:UpdateStatusText()
            end)
        elseif event == "VARIABLES_LOADED" or event == "PLAYER_LOGIN"
            or event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
            if S.enabled and not S.initialized then
                TryInitializeBlizzardBars()
            end
            CompactBar:Refresh()
        end
        CompactBar:UpdateStatusText()
    end)
end

local function EnsureSettingsPanelHooks()
    if S.settingsHooked or not SettingsPanel or type(SettingsPanel.HookScript) ~= "function" then
        return
    end
    S.settingsHooked = true
    pcall(SettingsPanel.HookScript, SettingsPanel, "OnShow", function()
        CompactBar:UpdateStatusText()
    end)
    pcall(SettingsPanel.HookScript, SettingsPanel, "OnHide", function()
        C_Timer.After(0, function()
            if S.initialized or S.enabled then
                CompactBar:Refresh()
                CompactBar:UpdateStatusText()
            end
        end)
    end)
end

function CompactBar:OnEnable(db)
    S.enabled = true
    S.stopped = false
    S.lastError = nil
    EnsureSettingsPanelHooks()
    TryInitializeBlizzardBars()
    self:Refresh()
    self:UpdateStatusText()
end

function CompactBar:OnDisable(db)
    S.enabled = false
    if S.menuTicker then
        S.menuTicker:Cancel()
        S.menuTicker = nil
    end
    SetMoverActive(false)
    SetStyleShown(false)
    if S.built then
        if IsAnyMenuOpen() then
            RefreshWhenMenusClose()
        else
            HandBackWhenPossible()
        end
    end
    self:UpdateStatusText()
end

--------------------------------------------------------------------------------
-- YRG Native Blizzard Settings UI
--------------------------------------------------------------------------------
local function NotifyAfterSettingChange()
    CompactBar:UpdateStatusText()
    if S.enabled and not S.pendingSettingRefresh then
        S.pendingSettingRefresh = true
        C_Timer.After(0, function()
            S.pendingSettingRefresh = false
            if S.enabled then
                CompactBar:Refresh()
                CompactBar:UpdateStatusText()
            end
        end)
    end
end

local function CaptureClassAndFlyoutDebug(db)
    local out = {}
    local mdb = GetDB()
    local pu = S.pageUnit or (GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit)
    out[#out + 1] = "Status=" .. CompactBar:GetStatusMessage()
    out[#out + 1] = string.format("State: built=%s applied=%s stopped=%s blocked=%s menu=%s yrgCat=%s",
        tostring(S.built), tostring(S.applied), tostring(S.stopped), tostring(IsBlocked()),
        tostring(IsMenuOpen()), tostring(IsYRGSettingsCategoryOpen()))
    local actualScale = (pu and type(pu.GetScale) == "function") and YRG.SafeNumber(pu:GetScale(), -1) or -1
    out[#out + 1] = string.format("Config: dbScale=%.2f getScale=%.2f actualPageScale=%.2f pad=%s arr=%s classLayout=%s sq=%s",
        tonumber(mdb and mdb.scale) or -1, GetScale(mdb), actualScale,
        tostring(mdb and mdb.buttonPadding), tostring(mdb and mdb.arrangement),
        tostring(mdb and mdb.classButtonLayout), tostring(mdb and mdb.squareClassButtons))
    if S.bars and S.bars[1] and S.bars[1].Left then
        local oxs = {}
        for i = 1, CFG.BUTTONS_PER_GROUP do
            local btn = S.bars[1].Left["ActionButton" .. i]
            oxs[i] = string.format("%d:%.0f", i, tonumber(btn and S.slotOffsets[btn]) or 0)
        end
        out[#out + 1] = "LeftSlotOffsets=[" .. table.concat(oxs, " ") .. "]"
    end
    local fails = {}
    for k in pairs(S.failedPieces) do fails[#fails + 1] = tostring(k) end
    if #fails > 0 then
        out[#out + 1] = "FailedPieces=[" .. table.concat(fails, ", ") .. "]"
    end
    out[#out + 1] = "GamepadUI=" .. tostring(IsGamepadUIOn()) .. " RootShown=" .. tostring(S.root and S.root:IsShown())
    if pu then
        for _, side in ipairs(CFG.SIDES) do
            local btn = pu[side .. "ClassAction"]
            if not IsForbiddenSafe(btn) then
                local kids = {}
                if type(btn.GetChildren) == "function" then
                    local ok, chList = pcall(function() return { btn:GetChildren() } end)
                    if ok and type(chList) == "table" then
                        for _, ch in ipairs(chList) do
                            local nm = SafeFrameLabel(ch)
                            if nm == "" then nm = "anon" end
                            local okS, sh = pcall(function() return ch.IsShown and ch:IsShown() end)
                            kids[#kids + 1] = nm .. "(" .. tostring(okS and sh) .. ")"
                        end
                    end
                end
                local fields = {}
                for k, v in pairs(btn) do
                    if type(k) == "string" and (k:lower():find("flyout") or k:lower():find("mask") or k:lower():find("icon") or k:lower():find("wheel")) then
                        fields[#fields + 1] = k .. "=" .. type(v)
                    end
                end
                local parName = btn.GetParent and SafeFrameLabel(btn:GetParent()) or "nil"
                out[#out + 1] = string.format("%sClassAction: sh=%s parent=%s sz=%.0fx%.0f kids=[%s] fields=[%s]",
                    side, tostring(btn.IsShown and btn:IsShown()),
                    parName ~= "" and parName or "anon",
                    YRG.SafeNumber(btn.GetWidth and btn:GetWidth(), 0), YRG.SafeNumber(btn.GetHeight and btn:GetHeight(), 0),
                    table.concat(kids, ","), table.concat(fields, ","))
            else
                out[#out + 1] = side .. "ClassAction=" .. (btn and "forbidden" or "nil")
            end
        end
    end
    local flyList = {}
    for f in pairs(S.hookedFlyouts) do
        local nm = SafeFrameLabel(f)
        if nm == "" then nm = "anon" end
        local okS, sh = pcall(function() return f.IsShown and f:IsShown() end)
        local okP, pt, rel = pcall(function() return f.GetPoint and f:GetPoint(1) end)
        local relNm = (okP and rel) and SafeFrameLabel(rel) or "nil"
        flyList[#flyList + 1] = string.format("%s(sh=%s,pt=%s->%s,prot=%s)",
            nm, tostring(okS and sh), tostring(okP and pt), relNm ~= "" and relNm or "anon", tostring(IsProtectedSafe(f)))
    end
    out[#out + 1] = "HookedFlyouts=[" .. table.concat(flyList, "; ") .. "]"
    if db then db._lastInspect = out end
    for _, line in ipairs(out) do
        print("|cffffd100[CCB]|r " .. line)
    end
end

function CompactBar:BuildConfigUI(ctx, db)
    EnsureSettingsPanelHooks()
    S.settingsCtx = ctx
    local function IsClassInline()
        local mdb = GetDB()
        return mdb == nil or (mdb.classButtonLayout or "INLINE") == "INLINE"
    end

    ctx:AddHeader(
        "1. One-Bar Position, Scale & Spacing (Controller Only)",
        "CompactControllerBar uses a single stacked hotbar and is visible only while Controller / Gamepad UI mode is active."
    )

    self._statusInitializer = ctx:AddButton({
        name = "Status: " .. self:GetStatusMessage(),
        buttonText = "Check Status",
        tooltip = "Refreshes and prints the current CompactControllerBar state to chat.",
        onClick = function()
            self:UpdateStatusText()
            print("|cffffd100YRG CompactControllerBar:|r " .. self:GetStatusMessage())
        end,
    })

    ctx:AddButton({
        name = "Move / Resize Whole Hotbar",
        buttonText = "Unlock Mover",
        tooltip = "Closes Settings and displays a drag box with a corner resize handle around the entire hotbar (main slots + class buttons). Only available out of combat in Controller Mode.",
        onClick = function()
            if not IsGamepadUIOn() then
                print("|cffffd100YRG CompactControllerBar:|r Switch to Controller / Gamepad UI Mode to position the hotbar.")
                return
            end
            if InCombatLockdown() then
                print("|cffffd100YRG CompactControllerBar:|r Cannot unlock hotbar mover during combat.")
                return
            end
            if SettingsPanel and SettingsPanel:IsShown() then
                if type(HideUIPanel) == "function" then
                    pcall(HideUIPanel, SettingsPanel)
                else
                    SettingsPanel:Hide()
                end
            end
            C_Timer.After(0.25, function()
                if S.enabled and not InCombatLockdown() then
                    if not S.initialized then TryInitializeBlizzardBars() end
                    CompactBar:Refresh()
                    C_Timer.After(0.05, function()
                        SetMoverActive(true)
                    end)
                end
            end)
        end,
    })

    ctx:AddSlider({
        key = "scale",
        name = "Hotbar Scale",
        tooltip = "Overall scale of the compact controller bar (50% to 150%, clamped to fit screen edges).",
        min = 0.5, max = 1.5, step = 0.05, defaultValue = 1.0,
        format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        get = function()
            local mdb = GetDB()
            return Snap(mdb and mdb.scale or 1, CFG.SCALE_RANGE)
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.scale = Snap(val, CFG.SCALE_RANGE) end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddSlider({
        key = "buttonPadding",
        name = "Button Padding (Spacing)",
        tooltip = "Pixel spacing between adjacent action buttons inside the hotbar (default 5 px).",
        min = 0, max = 16, step = 1, defaultValue = 5,
        format = function(v) return string.format("%d px", v) end,
        get = function()
            return GetPadding(GetDB())
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.buttonPadding = math.max(0, math.min(16, math.floor((tonumber(val) or 5) + 0.5))) end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddCheckbox({
        key = "lockCenterX",
        name = "Lock Centered Horizontally (Vertical Move Only)",
        tooltip = "Locks the hotbar centered horizontally (X = 0) so dragging only moves it vertically. Also toggleable right on the drag mover ('Vertical Only' / 'All Directions').",
        defaultValue = true,
        notifies = { "YRG_CompactControllerBar_x" },
        get = function()
            return IsCenterXLocked(GetDB())
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.lockCenterX = val and true or false
                if mdb.lockCenterX then mdb.x = 0 end
            end
            UpdateMoverAxisButton()
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddSlider({
        key = "x",
        name = "Horizontal Offset (X)",
        tooltip = "Fine horizontal offset from center (0 snaps to center; disabled when Vertical Move Only is checked).",
        min = -600, max = 600, step = 2, defaultValue = 0,
        format = function(v) return string.format("%+d", v) end,
        canModify = function()
            return not IsCenterXLocked(GetDB())
        end,
        get = function()
            local mdb = GetDB()
            if IsCenterXLocked(mdb) then return 0 end
            return tonumber(mdb and mdb.x) or 0
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.x = math.floor((tonumber(val) or 0) + 0.5) end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddSlider({
        key = "y",
        name = "Vertical Offset (Y)",
        tooltip = "Vertical offset relative to Blizzard's default gamepad bar anchor center (default -16).",
        min = -400, max = 400, step = 2, defaultValue = -16,
        format = function(v) return string.format("%+d", v) end,
        get = function()
            local mdb = GetDB()
            return tonumber(mdb and mdb.y) or -16
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.y = math.floor((tonumber(val) or -16) + 0.5) end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddButton({
        name = "Reset Position & Scale",
        buttonText = "Reset",
        tooltip = "Resets hotbar position (0, -16), scale (100%), and button padding (5 px) back to defaults.",
        onClick = function()
            local mdb = GetDB()
            if mdb then
                mdb.x = 0
                mdb.y = -16
                mdb.scale = 1.0
                mdb.buttonPadding = 5
            end
            ctx:NotifyAll()
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddHeader(
        "2. Button Arrangement & Extra Class / Pet / Stance Slots",
        "Customize D-pad/face order and how the LT+LB and RT+RB extra buttons and selection wheel appear."
    )

    ctx:AddDropdown({
        key = "arrangement",
        name = "Button Arrangement",
        tooltip = "XYBA (Default): Left, Up, Right, Down and X, Y, B, A (Clockwise). XYAB: Left, Up, Down, Right and X, Y, A, B.",
        defaultValue = "XYBA",
        options = CFG.ARRANGEMENT_OPTIONS,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.arrangement == "XYAB") and "XYAB" or "XYBA"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.arrangement = (val == "XYAB") and "XYAB" or "XYBA" end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddDropdown({
        key = "classButtonLayout",
        name = "Extra Buttons Layout (LT+LB / RT+RB)",
        tooltip = "Places stance, aura, and pet action buttons inline to the left and right of the action bar, or below it.",
        defaultValue = "INLINE",
        options = CFG.CLASS_LAYOUT_OPTIONS,
        notifies = { "YRG_CompactControllerBar_squareClassButtons" },
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.classButtonLayout == "BELOW") and "BELOW" or "INLINE"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.classButtonLayout = (val == "BELOW") and "BELOW" or "INLINE" end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddCheckbox({
        key = "squareClassButtons",
        name = "Square Extra Buttons (LT+LB / RT+RB)",
        tooltip = "Restyles the Left and Right extra stance/aura/pet buttons into 32x32 square action slots matching the main bar.",
        defaultValue = true,
        canModify = IsClassInline,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.squareClassButtons ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.squareClassButtons = val and true or false end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddCheckbox({
        key = "centerFlyoutWheel",
        name = "Spawn Selection Wheel in Center of Screen",
        tooltip = "Automatically centers the LT+LB / RT+RB stance, pet, and spell selection wheel in the middle of the screen instead of anchoring to the bar edge.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.centerFlyoutWheel ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.centerFlyoutWheel = val and true or false end
            if not val then RestoreFlyoutFrames() else ScanFlyoutCandidates() end
        end,
    })

    ctx:AddHeader(
        "3. Appearance, Icons & Background",
        "Customize bar background, trigger guide icons, page numbers, and controller button glyphs."
    )

    ctx:AddCheckbox({
        key = "showBarBackground",
        name = "Show Placard Bar Background",
        tooltip = "Toggles the placard border and dark fill frame (with ~5 px internal padding) behind the hotbar and square extra buttons.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showBarBackground ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showBarBackground = val and true or false end
            if S.styled then SafeTry("plates", FitStyle) end
        end,
    })

    ctx:AddDropdown({
        key = "labelScale",
        name = "Page Number Size",
        tooltip = "Font size of the page numbers above the right side of the bar.",
        defaultValue = 1.0,
        options = CFG.LABEL_SIZE_OPTIONS,
        get = function()
            local mdb = GetDB()
            local v = tonumber(mdb and mdb.labelScale) or 1.0
            if math.abs(v - 0.85) < 0.05 then return 0.85 end
            if math.abs(v - 1.25) < 0.05 then return 1.25 end
            return 1.0
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.labelScale = tonumber(val) or 1.0 end
            if S.styled then FitStyle() end
        end,
    })

    ctx:AddDropdown({
        key = "glyphScale",
        name = "Controller Button Icon Size",
        tooltip = "Size of the small D-pad / face button glyph on each slot (or Off to hide).",
        defaultValue = 1.0,
        options = CFG.GLYPH_SIZE_OPTIONS,
        notifies = { "YRG_CompactControllerBar_glyphPosition", "YRG_CompactControllerBar_glyphBelowOffset" },
        get = function()
            local mdb = GetDB()
            local v = tonumber(mdb and mdb.glyphScale)
            if v == nil then return 1.0 end
            if v <= 0.1 then return 0 end
            if math.abs(v - 0.75) < 0.05 then return 0.75 end
            if math.abs(v - 1.3) < 0.05 then return 1.3 end
            return 1.0
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.glyphScale = tonumber(val) or 1.0 end
            if S.styled then FitStyle() end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddDropdown({
        key = "glyphPosition",
        name = "Controller Button Icon Position",
        tooltip = "Places the D-pad / X Y B A icon centered below each button, or anchored to the top-left corner.",
        defaultValue = "BELOW",
        options = CFG.GLYPH_POS_OPTIONS,
        notifies = { "YRG_CompactControllerBar_glyphBelowOffset" },
        canModify = function()
            local mdb = GetDB()
            local v = tonumber(mdb and mdb.glyphScale)
            return v == nil or v > 0.1
        end,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.glyphPosition == "CORNER") and "CORNER" or "BELOW"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.glyphPosition = (val == "CORNER") and "CORNER" or "BELOW" end
            if S.styled then SafeTry("glyphs", FitGlyphs) end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddSlider({
        key = "glyphBelowOffset",
        name = "Button Icon Vertical Offset (Below Mode)",
        tooltip = "Distance in pixels below the main buttons for D-pad / X Y B A icons (default 7 px); extra LT+LB / RT+RB labels stay vertically aligned with them.",
        min = 0, max = 24, step = 1, defaultValue = 7,
        format = function(v) return string.format("%d px", v) end,
        canModify = function()
            local mdb = GetDB()
            local v = tonumber(mdb and mdb.glyphScale)
            local shown = (v == nil or v > 0.1)
            return shown and (mdb == nil or (mdb.glyphPosition or "BELOW") == "BELOW")
        end,
        get = function()
            return GetGlyphBelowOffset(GetDB())
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.glyphBelowOffset = GetGlyphBelowOffset({ glyphBelowOffset = val }) end
            if S.styled then SafeTry("glyphs", FitGlyphs) end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddCheckbox({
        key = "guide",
        name = "Show Trigger Guide Icons (LT / RT)",
        tooltip = "Displays compact LT and RT icons at the top-left of the bar that highlight and underline individually or together as you hold triggers.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.guide ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.guide = val and true or false end
            NotifyAfterSettingChange()
        end,
    })

    ctx:AddCheckbox({
        key = "flash",
        name = "Flash Slot on Controller Press",
        tooltip = "Briefly flashes a gold highlight glow over each slot when pressed.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.flash ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.flash = val and true or false end
            if not val then StopFlashes() end
        end,
    })

    ctx:AddButton({
        name = "Inspect Extra Class / Flyout Frames",
        buttonText = "Inspect",
        tooltip = "Logs LT+LB / RT+RB class button and radial wheel frame metadata into YRGDB._lastInspect for troubleshooting.",
        onClick = function()
            CaptureClassAndFlyoutDebug(GetDB())
        end,
    })
end

YRG:RegisterModule("CompactControllerBar", CompactBar)
