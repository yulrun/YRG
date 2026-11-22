local addonName, YRG = ...
_G.YRG = YRG

YRG.version = "2.4.3"
YRG.author = "Shaemus Shadowstep & Sylas Swiftarrow | NA RP-PVP"
YRG.modules = {}
YRG.moduleOrder = {}
YRG.extraCategories = {}
YRG.slashSubcommands = {}

local TEX_CHAT_GRADIENT = "Interface\\AddOns\\YRG\\Textures\\ChatGradientBg"

function YRG.IsSecret(val)
    return type(issecretvalue) == "function" and issecretvalue(val)
end

function YRG.SafeNumber(val, default)
    if type(val) ~= "number" or YRG.IsSecret(val) then
        return default or 0
    end
    return val
end

function YRG.SafeOptionalNumber(val)
    if type(val) ~= "number" or YRG.IsSecret(val) then
        return nil
    end
    return val
end

function YRG.SafeString(val, default)
    if type(val) ~= "string" or YRG.IsSecret(val) or val == "" then
        return default
    end
    return val
end

local function CopyDefaults(src, dst)
    if type(src) ~= "table" then return {} end
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local defaultDB = {
    steamdeck = {
        disableChatScrollBar = true,
        hideChatEditBox = true,
        autoFadeChatTabs = true,
        gradientChatBackground = true,
        chatGradientMainOnly = true,
        chatGradientWidthPct = 135,
        chatGradientHeightPct = 135,
        chatGradientOpacityPct = 65,
        fadeChatTopText = true,
        chatTextTopFadePct = 45,
        fadeChatOnInactivity = true,
        chatInactivityIncludeFloating = true,
        chatInactivityMinutes = 5,
        quickLoot = true,
        quickLootDelay = 0.3,
        maxCameraZoom = true,
        fasterMovieSkip = true,
        showFlightTimes = true,
        flightBarPos = { point = "TOP", relPoint = "TOP", x = 0, y = -66 },
        _origChatX = nil,
        _origChatY = nil,
    },
    modules = {}
}

function YRG:GetSteamdeckDB()
    YRGDB = YRGDB or {}
    YRGDB.steamdeck = CopyDefaults(defaultDB.steamdeck, YRGDB.steamdeck)
    return YRGDB.steamdeck
end

function YRG:RegisterModule(id, mod)
    if not id or not mod then return end
    mod.id = id
    mod.name = mod.name or id
    mod.description = mod.description or ""
    if mod.defaultEnabled == nil then
        mod.defaultEnabled = true
    end

    defaultDB.modules[id] = CopyDefaults(mod.defaults or {}, {
        enabled = mod.defaultEnabled
    })

    if not self.modules[id] then
        table.insert(self.moduleOrder, id)
    end
    self.modules[id] = mod
end

function YRG:GetModuleDB(id)
    YRGDB = YRGDB or {}
    YRGDB.modules = YRGDB.modules or {}
    if not YRGDB.modules[id] then
        local mod = self.modules[id]
        YRGDB.modules[id] = CopyDefaults(mod and mod.defaults or {}, {
            enabled = (mod and mod.defaultEnabled ~= false)
        })
    end
    if id == "MinimapExpTracker" and YRGDB.modules[id].masterScale == nil then
        local uiScale = (UIParent and UIParent.GetScale and UIParent:GetScale()) or 1.0
        if GetCVar and GetCVar("uiScale") then
            uiScale = tonumber(GetCVar("uiScale")) or uiScale
        end
        YRGDB.modules[id].masterScale = uiScale
    end
    return YRGDB.modules[id]
end

function YRG:IsModuleEnabled(id)
    local db = self:GetModuleDB(id)
    return db and db.enabled and true or false
end

function YRG:SetModuleEnabled(id, state)
    local db = self:GetModuleDB(id)
    local mod = self.modules[id]
    if not db or not mod then return end

    local newState = state and true or false
    db.enabled = newState

    if newState then
        if not mod._initialized and type(mod.OnInitialize) == "function" then
            mod:OnInitialize(db)
            mod._initialized = true
        end
        if type(mod.OnEnable) == "function" then
            mod:OnEnable(db)
        end
    else
        if type(mod.OnDisable) == "function" then
            mod:OnDisable(db)
        end
    end

    if mod._syncToggleUI then
        mod._syncToggleUI(newState)
    end
    if mod._mainToggleCheck then
        mod._mainToggleCheck:SetChecked(newState)
    end
    if mod._subToggleCheck then
        mod._subToggleCheck:SetChecked(newState)
    end
end

function YRG:RegisterExtraCategory(id, category)
    if id and category then
        self.extraCategories[id] = category
    end
end

function YRG:RegisterSlashSubcommand(cmd, handler)
    if type(cmd) == "string" and cmd ~= "" and type(handler) == "function" then
        self.slashSubcommands[cmd:lower()] = handler
    end
end

function YRG:OpenSettings(moduleID)
    local mod = moduleID and self.modules[moduleID]
    local targetCat = (mod and mod.settingsCategory)
        or (moduleID and self.extraCategories and self.extraCategories[moduleID])
        or self.settingsCategory
    local mainCat = self.settingsCategory

    if Settings and Settings.OpenToCategory then
        if targetCat and targetCat.GetID then
            if mainCat and targetCat ~= mainCat and mainCat.GetID then
                pcall(Settings.OpenToCategory, mainCat:GetID())
            end
            local ok = pcall(Settings.OpenToCategory, targetCat:GetID())
            if SettingsPanel and type(SettingsPanel.GetCurrentCategory) == "function"
                and type(SettingsPanel.SelectCategory) == "function" then
                local curOk, curCat = pcall(SettingsPanel.GetCurrentCategory, SettingsPanel)
                if curOk and curCat ~= targetCat then
                    pcall(SettingsPanel.SelectCategory, SettingsPanel, targetCat)
                end
            end
            if ok then return end
        end
        if mainCat and mainCat.GetID then
            pcall(Settings.OpenToCategory, mainCat:GetID())
        end
    elseif InterfaceOptionsFrame_OpenToCategory then
        if mod and mod.subPanel then
            InterfaceOptionsFrame_OpenToCategory(mod.subPanel)
            InterfaceOptionsFrame_OpenToCategory(mod.subPanel)
        else
            InterfaceOptionsFrame_OpenToCategory("YRG")
            InterfaceOptionsFrame_OpenToCategory("YRG")
        end
    end
end

-- =========================================================================
-- STEAMDECK CHAT WINDOW IMPROVEMENTS
-- =========================================================================
-- Weak tables avoid attaching custom keys directly onto Blizzard frames/tabs/editboxes
-- (critical in 1.60.1 EditMode / Controller Mode to prevent table taint).
local hookedScrollFrames = setmetatable({}, { __mode = "k" })
local suppressedState = setmetatable({}, { __mode = "k" })
local suppressedMouseChanged = setmetatable({}, { __mode = "k" })
local hookedEditBoxes = setmetatable({}, { __mode = "k" })
local editBoxMeta = setmetatable({}, { __mode = "k" })
local hookedChatFrames = setmetatable({}, { __mode = "k" })
local chatFrameMeta = setmetatable({}, { __mode = "k" })
local texMeta = setmetatable({}, { __mode = "k" })
local textLineMeta = setmetatable({}, { __mode = "k" })
local hookedFontStrings = setmetatable({}, { __mode = "k" })
local tabMeta = setmetatable({}, { __mode = "k" })
local dockManagerMeta = setmetatable({}, { __mode = "k" })
local originalEditBoxAnchors = setmetatable({}, { __mode = "k" })

local originalChat1Points = nil
local originalChat1Size = nil

local settingAlphaGuard = false
local settingScrollGuard = false
local settingBgAlphaGuard = false
local settingTextAlphaGuard = false
local settingTabAlphaGuard = false
local settingWindowAlphaGuard = false
local settingClampGuard = false
local settingChatPointGuard = false
local editModeHooked = false
local editModeActive = false
local chatSnapPending = false
local chatRefreshPending = false
local chatRectRetryCount = 0
local ScheduleChatSnap
local lastChatActivityTime = (GetTime and GetTime()) or 0
local currentChatFadeAlpha = 1.0
local desiredTabsAlpha = 1.0
local lastChatActiveState = nil

local CHAT_BORDER_SUFFIXES = {
    "Background",
    "TopTexture",
    "BottomTexture",
    "LeftTexture",
    "RightTexture",
    "TopLeftTexture",
    "TopRightTexture",
    "BottomLeftTexture",
    "BottomRightTexture",
}

local function IsControllerModeActive()
    return InputUtil and type(InputUtil.IsGamepadUIEnabled) == "function" and InputUtil.IsGamepadUIEnabled()
end

local function IsFrameHovered(frame)
    if not frame or type(frame.IsShown) ~= "function" or not frame:IsShown() then
        return false
    end
    if type(frame.IsMouseOver) == "function" then
        local ok, res = pcall(frame.IsMouseOver, frame)
        if ok and res then
            return true
        end
    end
    return false
end

local function IsMouseOverAnyChatOrTab()
    if IsFrameHovered(GeneralDockManager) then
        return true
    end
    local maxWindows = NUM_CHAT_WINDOWS or 10
    for i = 1, maxWindows do
        local cf = _G["ChatFrame" .. i]
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if IsFrameHovered(cf) or IsFrameHovered(tab) then
            return true
        end
    end
    return false
end

local function IsAnyChatEditBoxActive()
    if ChatFrame1EditBox and ChatFrame1EditBox:HasFocus() then
        return true
    end
    local maxWindows = NUM_CHAT_WINDOWS or 10
    for i = 1, maxWindows do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb and eb:HasFocus() then
            return true
        end
    end
    return false
end

-- Determines whether chat scrollbars/scroll buttons should be hidden right now:
-- 1. Always hidden if "Disable Chat Window Scroll Bar" is checked.
-- 2. Also auto-hidden when not hovering if "Auto-Fade Chat Tabs" is checked.
local function ShouldSuppressChatScrollBar()
    local sdb = YRG:GetSteamdeckDB()
    if not sdb then return false end
    if sdb.disableChatScrollBar then
        return true
    end
    if sdb.autoFadeChatTabs and not (IsMouseOverAnyChatOrTab() or IsAnyChatEditBoxActive()) then
        return true
    end
    return false
end

local function IsProtectedOrInCombat(frame)
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    if frame and type(frame.IsProtected) == "function" then
        local ok, prot = pcall(frame.IsProtected, frame)
        if ok and prot then
            return true
        end
    end
    return false
end

local function SetElementSubPartsAlpha(frame, alpha)
    local subParts = { frame.Track, frame.Back, frame.Forward, frame.ThumbTexture, frame.Begin, frame.End, frame.Middle }
    for _, sub in ipairs(subParts) do
        if sub and type(sub.SetAlpha) == "function" then
            sub:SetAlpha(alpha)
        end
    end
end

local function SetElementMouseForSuppression(frame, suppress)
    -- Skip mouse toggles in Controller Mode or on menu/social buttons to avoid Blizzard_Menu / Gamepad focus taint.
    if IsControllerModeActive() or IsProtectedOrInCombat(frame) then return end
    if frame == ChatFrameMenuButton or frame == ChatFrameChannelButton
        or frame == FriendsMicroButton or frame == QuickJoinToastButton then
        return
    end
    if suppress then
        if not suppressedMouseChanged[frame] and type(frame.EnableMouse) == "function" then
            local wasEnabled = (type(frame.IsMouseEnabled) == "function") and frame:IsMouseEnabled()
            if wasEnabled then
                suppressedMouseChanged[frame] = true
                pcall(frame.EnableMouse, frame, false)
            end
        end
    else
        if suppressedMouseChanged[frame] and type(frame.EnableMouse) == "function" then
            suppressedMouseChanged[frame] = nil
            pcall(frame.EnableMouse, frame, true)
        end
    end
end

local function ForceHideScrollElement(frame)
    if not frame or settingScrollGuard then return end
    suppressedState[frame] = true

    local curAlpha = (type(frame.GetAlpha) == "function") and frame:GetAlpha() or 1
    settingScrollGuard = true
    if type(frame.SetAlpha) == "function" and curAlpha ~= 0 then
        frame:SetAlpha(0)
    end
    SetElementSubPartsAlpha(frame, 0)
    settingScrollGuard = false

    SetElementMouseForSuppression(frame, true)
end

local function RestoreScrollElement(frame)
    if not frame or settingScrollGuard then return end
    local wasSuppressed = suppressedState[frame]
    suppressedState[frame] = false
    if not wasSuppressed and not suppressedMouseChanged[frame] then
        return
    end

    settingScrollGuard = true
    if type(frame.SetAlpha) == "function" then
        frame:SetAlpha(1)
    end
    SetElementSubPartsAlpha(frame, 1)
    settingScrollGuard = false

    SetElementMouseForSuppression(frame, false)
end

local function SetElementSuppressed(frame, suppress)
    if not frame then return end
    if not hookedScrollFrames[frame] then
        hookedScrollFrames[frame] = true
        if type(frame) == "table" and type(frame.SetAlpha) == "function" then
            pcall(hooksecurefunc, frame, "SetAlpha", function(self, alpha)
                if not settingScrollGuard and suppressedState[self] and alpha and alpha > 0 then
                    ForceHideScrollElement(self)
                end
            end)
        end
    end

    if suppress then
        ForceHideScrollElement(frame)
    else
        RestoreScrollElement(frame)
    end
end

local function EnforceAllChatScrollBarsState()
    local suppress = ShouldSuppressChatScrollBar()
    local sdb = YRG:GetSteamdeckDB()
    local hardDisable = sdb and sdb.disableChatScrollBar and true or false

    local maxWindows = NUM_CHAT_WINDOWS or 10
    for i = 1, maxWindows do
        local cf = _G["ChatFrame" .. i]
        if cf then
            local btnFrame = cf.buttonFrame or _G["ChatFrame" .. i .. "ButtonFrame"]
            local scrollBar = cf.ScrollBar or _G["ChatFrame" .. i .. "ScrollBar"]
            local scrollToBottom = cf.ScrollToBottomButton or _G["ChatFrame" .. i .. "BottomButton"] or _G["ChatFrame" .. i .. "ButtonFrameBottomButton"]
            local upBtn = _G["ChatFrame" .. i .. "UpButton"] or _G["ChatFrame" .. i .. "ButtonFrameUpButton"]
            local downBtn = _G["ChatFrame" .. i .. "DownButton"] or _G["ChatFrame" .. i .. "ButtonFrameDownButton"]
            local minBtn = cf.minimizeButton or _G["ChatFrame" .. i .. "ButtonFrameMinimizeButton"]

            SetElementSuppressed(btnFrame, suppress)
            SetElementSuppressed(scrollBar, suppress)
            SetElementSuppressed(scrollToBottom, suppress)
            SetElementSuppressed(upBtn, suppress)
            SetElementSuppressed(downBtn, suppress)
            if minBtn then
                SetElementSuppressed(minBtn, suppress)
            end
        end
    end

    SetElementSuppressed(ChatFrameMenuButton, hardDisable)
    SetElementSuppressed(ChatFrameChannelButton, hardDisable)
    SetElementSuppressed(FriendsMicroButton, hardDisable)
    SetElementSuppressed(QuickJoinToastButton, hardDisable)
end

local function SaveOriginalEditBoxAnchor(eb)
    if not eb or originalEditBoxAnchors[eb] then return end
    local points = {}
    for p = 1, (eb:GetNumPoints() or 0) do
        local pt, relTo, relPt, xOfs, yOfs = eb:GetPoint(p)
        table.insert(points, { pt = pt, relTo = relTo, relPt = relPt, xOfs = xOfs, yOfs = yOfs })
    end
    originalEditBoxAnchors[eb] = points
end

local function RestoreOriginalEditBoxAnchor(eb)
    local pts = eb and originalEditBoxAnchors[eb]
    if not pts or #pts == 0 or IsProtectedOrInCombat(eb) then return end
    eb:ClearAllPoints()
    for _, p in ipairs(pts) do
        eb:SetPoint(p.pt, p.relTo, p.relPt, p.xOfs or 0, p.yOfs or 0)
    end
end

local function ApplyEditBoxVisualState(eb, isTyping)
    if not eb then return end
    local sdb = YRG:GetSteamdeckDB()
    local locked = IsProtectedOrInCombat(eb)
    local meta = editBoxMeta[eb]
    if not meta then
        meta = {}
        editBoxMeta[eb] = meta
    end
    settingAlphaGuard = true
    if sdb and sdb.hideChatEditBox then
        if isTyping or eb:HasFocus() then
            meta.typing = true
            eb:SetAlpha(1)
            if not locked and eb.EnableMouse then eb:EnableMouse(true) end
            lastChatActivityTime = (GetTime and GetTime()) or 0
        else
            meta.typing = false
            eb:SetAlpha(0)
            if not locked and not IsControllerModeActive() and eb.EnableMouse then
                eb:EnableMouse(false)
            end
        end
    else
        meta.typing = nil
        eb:SetAlpha(1)
        if not locked and eb.EnableMouse then eb:EnableMouse(true) end
    end
    settingAlphaGuard = false
end

local function UpdateEditBoxLayoutAndVisibility(eb, cf)
    if not eb then return end
    local sdb = YRG:GetSteamdeckDB()
    if sdb and sdb.hideChatEditBox then
        SaveOriginalEditBoxAnchor(eb)
        local targetCF = cf or eb.chatFrame or ChatFrame1
        if targetCF and not IsProtectedOrInCombat(eb) then
            local numPts = (eb.GetNumPoints and eb:GetNumPoints()) or 0
            local alreadyAnchored = false
            if numPts == 2 then
                local pt1, relTo1, relPt1, x1, y1 = eb:GetPoint(1)
                local pt2, relTo2, relPt2, x2, y2 = eb:GetPoint(2)
                if pt1 == "BOTTOMLEFT" and relTo1 == targetCF and relPt1 == "BOTTOMLEFT"
                    and math.abs((x1 or 0) - (-2)) < 0.5 and math.abs(y1 or 0) < 0.5
                    and pt2 == "BOTTOMRIGHT" and relTo2 == targetCF and relPt2 == "BOTTOMRIGHT"
                    and math.abs((x2 or 0) - 2) < 0.5 and math.abs(y2 or 0) < 0.5 then
                    alreadyAnchored = true
                end
            end
            if not alreadyAnchored then
                eb:ClearAllPoints()
                eb:SetPoint("BOTTOMLEFT", targetCF, "BOTTOMLEFT", -2, 0)
                eb:SetPoint("BOTTOMRIGHT", targetCF, "BOTTOMRIGHT", 2, 0)
            end
        end
        ApplyEditBoxVisualState(eb, eb:HasFocus())
    else
        RestoreOriginalEditBoxAnchor(eb)
        ApplyEditBoxVisualState(eb, true)
    end
end

local function HookChatEditBox(eb, cf)
    if not eb or hookedEditBoxes[eb] then return end
    hookedEditBoxes[eb] = true

    eb:HookScript("OnEditFocusGained", function(self)
        lastChatActivityTime = (GetTime and GetTime()) or 0
        UpdateEditBoxLayoutAndVisibility(self, self.chatFrame or cf or ChatFrame1)
        ApplyEditBoxVisualState(self, true)
    end)

    eb:HookScript("OnEditFocusLost", function(self)
        lastChatActivityTime = (GetTime and GetTime()) or 0
        ApplyEditBoxVisualState(self, false)
    end)

    if type(eb) == "table" then
        pcall(hooksecurefunc, eb, "SetAlpha", function(self, alpha)
            if settingAlphaGuard then return end
            local sdb = YRG:GetSteamdeckDB()
            local meta = editBoxMeta[self]
            if sdb and sdb.hideChatEditBox and not self:HasFocus() and not (meta and meta.typing) and alpha > 0 then
                settingAlphaGuard = true
                self:SetAlpha(0)
                settingAlphaGuard = false
            end
        end)
    end
end

local function IsMainOrDockedChatFrame(cf, index)
    if not cf then return false end
    local meta = chatFrameMeta[cf]
    local idx = index or (meta and meta.index) or (cf.GetID and cf:GetID())
    local mainCF = DEFAULT_CHAT_FRAME or ChatFrame1
    return (cf == mainCF or idx == 1 or cf.isDocked == true)
end

local function ShouldApplyGradientToChatFrame(cf, index)
    if not cf then return false end
    local sdb = YRG:GetSteamdeckDB()
    if not sdb or not sdb.gradientChatBackground then
        return false
    end
    if sdb.chatGradientMainOnly ~= false and not IsMainOrDockedChatFrame(cf, index) then
        return false
    end
    return true
end

local function ShouldApplyTopTextFade(cf, index)
    if not cf then return false end
    local sdb = YRG:GetSteamdeckDB()
    if not sdb or not sdb.fadeChatTopText then
        return false
    end
    local pct = tonumber(sdb.chatTextTopFadePct) or 0
    if pct <= 0 then
        return false
    end
    if sdb.chatGradientMainOnly ~= false and not IsMainOrDockedChatFrame(cf, index) then
        return false
    end
    return true
end

local function ComputeLineTopFade(region, cf, fadePct)
    if not region or not cf or fadePct <= 0 then return 1.0 end
    local boundsFrame = cf.FontStringContainer or cf
    local bTop = YRG.SafeNumber(boundsFrame.GetTop and boundsFrame:GetTop(), nil)
        or YRG.SafeNumber(cf.GetTop and cf:GetTop(), nil)
    local bBot = YRG.SafeNumber(boundsFrame.GetBottom and boundsFrame:GetBottom(), nil)
        or YRG.SafeNumber(cf.GetBottom and cf:GetBottom(), nil)
    if not bTop or not bBot or (bTop - bBot) <= 10 then
        return 1.0
    end
    local lTop = YRG.SafeNumber(region.GetTop and region:GetTop(), nil)
    local lBot = YRG.SafeNumber(region.GetBottom and region:GetBottom(), nil)
    if not lTop or not lBot then
        return 1.0
    end
    local lineCenterY = (lTop + lBot) * 0.5
    local fadeZone = math.max((bTop - bBot) * (fadePct / 100.0), 1)
    local fadeStartY = bTop - fadeZone
    if lineCenterY <= fadeStartY then
        return 1.0
    end
    local frac = (bTop - lineCenterY) / fadeZone
    return math.max(0.0, math.min(1.0, frac))
end

local function HookFontStringAlpha(region, cf)
    if hookedFontStrings[region] then return end
    hookedFontStrings[region] = true
    if type(region) == "table" and type(region.SetAlpha) == "function" then
        pcall(hooksecurefunc, region, "SetAlpha", function(self, alpha)
            if settingTextAlphaGuard then return end
            local lm = textLineMeta[self]
            if not lm then
                lm = { cf = cf }
                textLineMeta[self] = lm
            elseif not lm.cf then
                lm.cf = cf
            end
            local blizzAlpha = YRG.SafeNumber(alpha, 1)
            lm.blizzAlpha = blizzAlpha
            local targetCF = lm.cf or cf
            local meta = targetCF and chatFrameMeta[targetCF]
            if not ShouldApplyTopTextFade(targetCF, meta and meta.index) then
                lm.lastAppliedAlpha = nil
                return
            end
            local sdb = YRG:GetSteamdeckDB()
            local fadePct = (sdb and tonumber(sdb.chatTextTopFadePct)) or 45
            local topFade = ComputeLineTopFade(self, targetCF, fadePct)
            if topFade < 0.999 then
                local target = blizzAlpha * topFade
                lm.lastAppliedAlpha = target
                settingTextAlphaGuard = true
                self:SetAlpha(target)
                settingTextAlphaGuard = false
            else
                lm.lastAppliedAlpha = nil
            end
        end)
    end
end

local function ApplyChatTopTextFade(cf, index)
    if not cf or not cf.FontStringContainer or type(cf.FontStringContainer.GetRegions) ~= "function" then
        return
    end
    local shouldFade = ShouldApplyTopTextFade(cf, index)
    if not shouldFade and not chatFrameMeta[cf] then return end
    local sdb = YRG:GetSteamdeckDB()
    local fadePct = (sdb and tonumber(sdb.chatTextTopFadePct)) or 45
    local shown = (type(cf.IsShown) == "function") and cf:IsShown()

    for _, region in ipairs({ cf.FontStringContainer:GetRegions() }) do
        if type(region) == "table"
            and not (type(region.IsForbidden) == "function" and region:IsForbidden())
            and type(region.GetObjectType) == "function"
            and region:GetObjectType() == "FontString"
            and type(region.SetAlpha) == "function" then
            if shouldFade and shown then
                HookFontStringAlpha(region, cf)
                if type(region.IsShown) ~= "function" or region:IsShown() then
                    local curA = YRG.SafeNumber(region.GetAlpha and region:GetAlpha(), 1)
                    local lm = textLineMeta[region]
                    if not lm then
                        lm = { cf = cf, blizzAlpha = curA }
                        textLineMeta[region] = lm
                    else
                        lm.cf = cf
                        if lm.lastAppliedAlpha == nil or math.abs(curA - lm.lastAppliedAlpha) > 0.01 then
                            lm.blizzAlpha = curA
                        end
                    end
                    local topFade = ComputeLineTopFade(region, cf, fadePct)
                    local target = (topFade < 0.999) and (lm.blizzAlpha * topFade) or lm.blizzAlpha
                    lm.lastAppliedAlpha = (topFade < 0.999) and target or nil
                    if math.abs(curA - target) > 0.005 then
                        settingTextAlphaGuard = true
                        region:SetAlpha(target)
                        settingTextAlphaGuard = false
                    end
                end
            else
                local lm = textLineMeta[region]
                if lm and lm.lastAppliedAlpha ~= nil then
                    local restoreA = lm.blizzAlpha or 1
                    lm.lastAppliedAlpha = nil
                    lm.blizzAlpha = nil
                    settingTextAlphaGuard = true
                    region:SetAlpha(restoreA)
                    settingTextAlphaGuard = false
                end
            end
        end
    end
end

-- Zero-Flicker Suppression of Default Chat Background & Border Textures (no Hide/FADEFRAMES taint)
local function SuppressBgTexture(tex, suppress, cf, index)
    if not tex then return end
    local meta = texMeta[tex]
    if not meta then
        meta = {}
        texMeta[tex] = meta
    end
    if cf ~= nil then meta.cf = cf end
    if index ~= nil then meta.index = index end

    if not meta.hooked and type(tex) == "table" and type(tex.SetAlpha) == "function" then
        meta.hooked = true
        pcall(hooksecurefunc, tex, "SetAlpha", function(self, alpha)
            if settingBgAlphaGuard then return end
            local tm = texMeta[self]
            if tm and ShouldApplyGradientToChatFrame(tm.cf, tm.index) and alpha and alpha > 0 then
                settingBgAlphaGuard = true
                self:SetAlpha(0)
                settingBgAlphaGuard = false
            end
        end)
    end

    if suppress then
        if meta.origAlpha == nil and type(tex.GetAlpha) == "function" then
            local a = tex:GetAlpha()
            if a and a > 0 then
                meta.origAlpha = a
            end
        end
        if type(tex.SetAlpha) == "function" then
            local curA = (type(tex.GetAlpha) == "function") and tex:GetAlpha() or 1
            if curA ~= 0 then
                settingBgAlphaGuard = true
                tex:SetAlpha(0)
                settingBgAlphaGuard = false
            end
        end
    else
        if meta.origAlpha ~= nil and type(tex.SetAlpha) == "function" then
            settingBgAlphaGuard = true
            tex:SetAlpha(meta.origAlpha)
            settingBgAlphaGuard = false
            meta.origAlpha = nil
        end
    end
end

local function SuppressDefaultChatBgRegions(cf, index, suppress)
    if not cf then return end
    for _, suffix in ipairs(CHAT_BORDER_SUFFIXES) do
        local tex = _G["ChatFrame" .. index .. suffix]
        if tex then
            SuppressBgTexture(tex, suppress, cf, index)
        end
    end
    if cf.Background then
        SuppressBgTexture(cf.Background, suppress, cf, index)
    end
end

-- Half-Radial Warm Dark-Brown Gradient Chat Background Replacer (parented to UIParent to avoid ChatFrame taint)
local function UpdateChatFrameGradientBg(cf, index)
    if not cf then return end
    local sdb = YRG:GetSteamdeckDB()
    local enableGradient = ShouldApplyGradientToChatFrame(cf, index)

    SuppressDefaultChatBgRegions(cf, index, enableGradient)

    local meta = chatFrameMeta[cf]
    if not meta then
        meta = { index = index }
        chatFrameMeta[cf] = meta
    end

    if enableGradient then
        if not meta.gradFrame then
            local gradFrame = CreateFrame("Frame", nil, UIParent)
            gradFrame:SetFrameStrata("BACKGROUND")
            gradFrame:SetFrameLevel(0)
            gradFrame:EnableMouse(false)
            if gradFrame.SetMouseClickEnabled then gradFrame:SetMouseClickEnabled(false) end
            if gradFrame.SetMouseMotionEnabled then gradFrame:SetMouseMotionEnabled(false) end

            local grad = gradFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
            grad:SetAllPoints(gradFrame)
            grad:SetTexture(TEX_CHAT_GRADIENT)

            meta.gradFrame = gradFrame
            meta.gradBg = grad
        end

        local widthPct = (sdb and tonumber(sdb.chatGradientWidthPct)) or 135
        local heightPct = (sdb and tonumber(sdb.chatGradientHeightPct)) or 135
        local opacityPct = (sdb and tonumber(sdb.chatGradientOpacityPct)) or 65
        local baseAlpha = math.max(0, math.min(1, opacityPct / 100.0))

        local baseW = math.max((cf:GetWidth() or 320) + 8, 40)
        local baseH = math.max((cf:GetHeight() or 140) + 8, 30)
        local targetW = math.floor((baseW * (widthPct / 100.0)) + 0.5)
        local targetH = math.floor((baseH * (heightPct / 100.0)) + 0.5)

        local cfEff = math.max(YRG.SafeNumber(cf.GetEffectiveScale and cf:GetEffectiveScale(), 1), 0.01)
        local uiEff = math.max(YRG.SafeNumber(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale(), 1), 0.01)
        local relScale = cfEff / uiEff

        local gf = meta.gradFrame
        if meta.lastScale ~= relScale then
            meta.lastScale = relScale
            gf:SetScale(relScale)
        end
        if meta.lastW ~= targetW or meta.lastH ~= targetH or meta.lastAnchorCF ~= cf then
            meta.lastW = targetW
            meta.lastH = targetH
            meta.lastAnchorCF = cf
            gf:ClearAllPoints()
            gf:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", -4, -4)
            gf:SetSize(targetW, targetH)
        end

        meta.gradBg:SetVertexColor(1, 1, 1, baseAlpha * currentChatFadeAlpha)
        local shouldShow = (type(cf.IsShown) == "function" and cf:IsShown()) and true or false
        gf:SetShown(shouldShow)
    else
        if meta.gradFrame then
            meta.gradFrame:Hide()
        end
    end
end

local function HookTabAlphaGuard(frame, metaTable, isDock)
    if not frame or metaTable[frame] then return end
    metaTable[frame] = true
    if type(frame) == "table" and type(frame.SetAlpha) == "function" then
        pcall(hooksecurefunc, frame, "SetAlpha", function(self, alpha)
            if settingTabAlphaGuard then return end
            local sdb = YRG:GetSteamdeckDB()
            if sdb and sdb.autoFadeChatTabs and desiredTabsAlpha == 0 and alpha and alpha > 0 then
                settingTabAlphaGuard = true
                self:SetAlpha(0)
                settingTabAlphaGuard = false
            elseif isDock and sdb and sdb.autoFadeChatTabs and desiredTabsAlpha == 1 and alpha and alpha < 1 then
                settingTabAlphaGuard = true
                self:SetAlpha(1)
                settingTabAlphaGuard = false
            end
        end)
    end
end

local function UpdateChatTabsAlpha(showTabs)
    local sdb = YRG:GetSteamdeckDB()
    local maxWindows = NUM_CHAT_WINDOWS or 10
    local fadeEnabled = sdb and sdb.autoFadeChatTabs and true or false
    local targetAlpha = (not fadeEnabled or showTabs) and 1.0 or 0.0
    desiredTabsAlpha = targetAlpha

    settingTabAlphaGuard = true
    for i = 1, maxWindows do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab then
            HookTabAlphaGuard(tab, tabMeta, false)
            if type(tab.GetAlpha) ~= "function" or math.abs((tab:GetAlpha() or 1) - targetAlpha) > 0.01 then
                tab:SetAlpha(targetAlpha)
            end
        end
    end

    if GeneralDockManager then
        HookTabAlphaGuard(GeneralDockManager, dockManagerMeta, true)
        if type(GeneralDockManager.GetAlpha) ~= "function" or math.abs((GeneralDockManager:GetAlpha() or 1) - targetAlpha) > 0.01 then
            GeneralDockManager:SetAlpha(targetAlpha)
        end
    end
    settingTabAlphaGuard = false
end

local function SetChatWindowsContentAlpha(alpha)
    currentChatFadeAlpha = alpha
    local sdb = YRG:GetSteamdeckDB()
    local opacityPct = (sdb and tonumber(sdb.chatGradientOpacityPct)) or 65
    local baseAlpha = math.max(0, math.min(1, opacityPct / 100.0))
    local includeFloating = not sdb or (sdb.chatInactivityIncludeFloating ~= false)

    local maxWindows = NUM_CHAT_WINDOWS or 10
    for i = 1, maxWindows do
        local cf = _G["ChatFrame" .. i]
        if cf then
            local effAlpha = (includeFloating or IsMainOrDockedChatFrame(cf, i)) and alpha or 1.0
            local useGradient = ShouldApplyGradientToChatFrame(cf, i)
            if useGradient then
                if type(cf.SetAlpha) == "function" and type(cf.GetAlpha) == "function" and math.abs((cf:GetAlpha() or 1) - 1.0) > 0.002 then
                    cf:SetAlpha(1.0)
                end
                if cf.FontStringContainer and type(cf.FontStringContainer.SetAlpha) == "function" then
                    cf.FontStringContainer:SetAlpha(effAlpha)
                elseif type(cf.SetAlpha) == "function" then
                    cf:SetAlpha(effAlpha)
                end
                local meta = chatFrameMeta[cf]
                if meta and meta.gradBg then
                    meta.gradBg:SetVertexColor(1, 1, 1, baseAlpha * effAlpha)
                end
            else
                if cf.FontStringContainer and type(cf.FontStringContainer.SetAlpha) == "function" then
                    cf.FontStringContainer:SetAlpha(1.0)
                end
                if type(cf.SetAlpha) == "function" then
                    local curA = (type(cf.GetAlpha) == "function") and (cf:GetAlpha() or 1) or 1
                    if math.abs(curA - effAlpha) > 0.002 then
                        cf:SetAlpha(effAlpha)
                    end
                end
            end
        end
    end
end

local function IsEditModeActiveNow()
    if editModeActive then return true end
    if EditModeManagerFrame then
        if type(EditModeManagerFrame.IsEditModeActive) == "function" then
            local ok, active = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
            if ok and active then return true end
        end
        if type(EditModeManagerFrame.IsShown) == "function" then
            local ok, shown = pcall(EditModeManagerFrame.IsShown, EditModeManagerFrame)
            if ok and shown then return true end
        end
    end
    return false
end

local clampedChatFrames = setmetatable({}, { __mode = "k" })

local function EnforceChatFrameClampInsets(cf)
    if not cf or not cf.SetClampRectInsets or settingClampGuard or IsProtectedOrInCombat(cf) or IsEditModeActiveNow() then return end
    local sdb = YRG:GetSteamdeckDB()
    if not sdb then return end
    local hideScroll = sdb.disableChatScrollBar and true or false
    local hideInput  = sdb.hideChatEditBox and true or false
    if not hideScroll and not hideInput and not clampedChatFrames[cf] then
        return
    end
    local leftInset = hideScroll and 0 or -35
    local bottomInset = hideInput and 0 or -50
    clampedChatFrames[cf] = (hideScroll or hideInput) and true or nil
    settingClampGuard = true
    cf:SetClampRectInsets(leftInset, 35, 26, bottomInset)
    settingClampGuard = false
end

local function EnforceChatFrame1EdgeSnap()
    if not ChatFrame1 or settingChatPointGuard or InCombatLockdown() or IsEditModeActiveNow() then return end
    if ChatFrame1.isDragging then return end
    local sdb = YRG:GetSteamdeckDB()
    if not sdb then return end
    local hideScroll = sdb.disableChatScrollBar and true or false
    local hideInput  = sdb.hideChatEditBox and true or false

    EnforceChatFrameClampInsets(ChatFrame1)

    if not hideScroll and not hideInput then
        if originalChat1Points and #originalChat1Points > 0 then
            settingChatPointGuard = true
            ChatFrame1:ClearAllPoints()
            for _, p in ipairs(originalChat1Points) do
                ChatFrame1:SetPoint(p.pt, p.relTo, p.relPt, p.xOfs or 0, p.yOfs or 0)
            end
            if originalChat1Size then
                ChatFrame1:SetSize(originalChat1Size.w, originalChat1Size.h)
            end
            settingChatPointGuard = false
            originalChat1Points = nil
            originalChat1Size = nil
        end
        return
    end

    -- Measure live screen-edge distance in ChatFrame1 coordinate space regardless of EditMode anchor point/relativeTo.
    local cfLeft = YRG.SafeNumber(ChatFrame1.GetLeft and ChatFrame1:GetLeft(), nil)
    local cfBottom = YRG.SafeNumber(ChatFrame1.GetBottom and ChatFrame1:GetBottom(), nil)
    if not cfLeft or not cfBottom then
        if chatRectRetryCount < 5 and C_Timer and type(C_Timer.After) == "function" then
            chatRectRetryCount = chatRectRetryCount + 1
            C_Timer.After(0.05, ScheduleChatSnap)
        end
        return
    end
    chatRectRetryCount = 0

    local uiLeft = YRG.SafeNumber(UIParent and UIParent.GetLeft and UIParent:GetLeft(), 0)
    local uiBottom = YRG.SafeNumber(UIParent and UIParent.GetBottom and UIParent:GetBottom(), 0)
    local cfScale = math.max(YRG.SafeNumber(ChatFrame1.GetEffectiveScale and ChatFrame1:GetEffectiveScale(), 1), 0.01)
    local uiScale = math.max(YRG.SafeNumber(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale(), 1), 0.01)
    local scaleRatio = uiScale / cfScale

    local curX = cfLeft - (uiLeft * scaleRatio)
    local curY = cfBottom - (uiBottom * scaleRatio)

    if not originalChat1Points then
        local pts = {}
        local numPts = ChatFrame1:GetNumPoints() or 0
        for p = 1, numPts do
            local pt, relTo, relPt, xOfs, yOfs = ChatFrame1:GetPoint(p)
            if pt then
                pts[#pts + 1] = { pt = pt, relTo = relTo, relPt = relPt, xOfs = xOfs or 0, yOfs = yOfs or 0 }
            end
        end
        if #pts > 0 then
            originalChat1Points = pts
            local w, h = ChatFrame1:GetSize()
            if w and h and w > 0 and h > 0 then
                originalChat1Size = { w = w, h = h }
            end
        end
    end

    if curX > 10 then sdb._origChatX = curX end
    if curY > 10 then sdb._origChatY = curY end

    local targetX = hideScroll and 6 or (sdb._origChatX or curX)
    local targetY = hideInput and 6 or (sdb._origChatY or curY)

    local numPts = ChatFrame1:GetNumPoints() or 0
    local pt, relTo, relPt, xOfs, yOfs = ChatFrame1:GetPoint(1)
    local relIsUIParent = (not relTo) or (relTo == UIParent) or (type(relTo) == "table" and relTo.GetName and relTo:GetName() == "UIParent")
    local isAlreadyAnchored = (numPts == 1 and pt == "BOTTOMLEFT" and relIsUIParent and relPt == "BOTTOMLEFT"
        and type(xOfs) == "number" and type(yOfs) == "number"
        and math.abs(xOfs - targetX) <= 0.5 and math.abs(yOfs - targetY) <= 0.5)

    if (not isAlreadyAnchored) or math.abs(curX - targetX) > 1.0 or math.abs(curY - targetY) > 1.0 then
        local w, h = ChatFrame1:GetSize()
        settingChatPointGuard = true
        ChatFrame1:ClearAllPoints()
        ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", targetX, targetY)
        if w and h and w > 0 and h > 0 then
            ChatFrame1:SetSize(w, h)
        end
        settingChatPointGuard = false
    end
end

ScheduleChatSnap = function()
    if chatSnapPending then return end
    chatSnapPending = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            chatSnapPending = false
            EnforceChatFrame1EdgeSnap()
        end)
    else
        chatSnapPending = false
        EnforceChatFrame1EdgeSnap()
    end
end

local function ScheduleChatRefresh()
    if chatRefreshPending then return end
    chatRefreshPending = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            chatRefreshPending = false
            YRG:ApplySteamdeckSettings()
        end)
    else
        chatRefreshPending = false
        YRG:ApplySteamdeckSettings()
    end
end

local function HookChatFrameForActivityAndSize(cf, index)
    if not cf or hookedChatFrames[cf] then return end
    hookedChatFrames[cf] = true

    local meta = chatFrameMeta[cf]
    if not meta then
        meta = { index = index }
        chatFrameMeta[cf] = meta
    else
        meta.index = index
    end

    if type(cf) == "table" then
        if type(cf.AddMessage) == "function" then
            pcall(hooksecurefunc, cf, "AddMessage", function(self)
                local sdb = YRG:GetSteamdeckDB()
                if not sdb or sdb.chatInactivityIncludeFloating ~= false or IsMainOrDockedChatFrame(self, index) then
                    lastChatActivityTime = (GetTime and GetTime()) or 0
                    if currentChatFadeAlpha < 1.0 then
                        SetChatWindowsContentAlpha(1.0)
                    end
                end
                if ShouldSuppressChatScrollBar() then
                    if self.ScrollBar then ForceHideScrollElement(self.ScrollBar) end
                    if self.ScrollToBottomButton then ForceHideScrollElement(self.ScrollToBottomButton) end
                    if self.buttonFrame then ForceHideScrollElement(self.buttonFrame) end
                end
                if ShouldApplyTopTextFade(self, index) then
                    ApplyChatTopTextFade(self, index)
                    if C_Timer and type(C_Timer.After) == "function" then
                        C_Timer.After(0, function()
                            if self and self:IsShown() then
                                ApplyChatTopTextFade(self, index)
                            end
                        end)
                    end
                end
            end)
        end
        for _, methodName in ipairs({
            "RefreshDisplay",
            "ScrollUp",
            "ScrollDown",
            "PageUp",
            "PageDown",
            "ScrollToTop",
            "ScrollToBottom",
            "SetScrollOffset",
            "Update",
        }) do
            if type(cf[methodName]) == "function" then
                pcall(hooksecurefunc, cf, methodName, function(self)
                    if ShouldApplyTopTextFade(self, index) then
                        ApplyChatTopTextFade(self, index)
                    end
                end)
            end
        end
        if type(cf.UpdateScrollBar) == "function" then
            pcall(hooksecurefunc, cf, "UpdateScrollBar", function(self)
                if ShouldSuppressChatScrollBar() then
                    if self.ScrollBar then ForceHideScrollElement(self.ScrollBar) end
                    if self.ScrollToBottomButton then ForceHideScrollElement(self.ScrollToBottomButton) end
                end
            end)
        end
        if type(cf.SetClampRectInsets) == "function" then
            pcall(hooksecurefunc, cf, "SetClampRectInsets", function(self)
                if not settingClampGuard then
                    ScheduleChatSnap()
                end
            end)
        end
        if index == 1 then
            if type(cf.SetPoint) == "function" then
                pcall(hooksecurefunc, cf, "SetPoint", function()
                    if not settingChatPointGuard then
                        ScheduleChatSnap()
                    end
                end)
            end
            if type(cf.SetPointBase) == "function" then
                pcall(hooksecurefunc, cf, "SetPointBase", function()
                    if not settingChatPointGuard then
                        ScheduleChatSnap()
                    end
                end)
            end
            if type(cf.SetAllPoints) == "function" then
                pcall(hooksecurefunc, cf, "SetAllPoints", function()
                    if not settingChatPointGuard then
                        ScheduleChatSnap()
                    end
                end)
            end
            if type(cf.SetAllPointsBase) == "function" then
                pcall(hooksecurefunc, cf, "SetAllPointsBase", function()
                    if not settingChatPointGuard then
                        ScheduleChatSnap()
                    end
                end)
            end
            if type(cf.ApplySystemAnchor) == "function" then
                pcall(hooksecurefunc, cf, "ApplySystemAnchor", function()
                    if not settingChatPointGuard then
                        ScheduleChatSnap()
                    end
                end)
            end
            if type(cf.UpdateSystem) == "function" then
                pcall(hooksecurefunc, cf, "UpdateSystem", function()
                    if not settingChatPointGuard then
                        ScheduleChatSnap()
                    end
                end)
            end
        end
    end

    cf:HookScript("OnShow", function(self)
        UpdateChatFrameGradientBg(self, index)
        ApplyChatTopTextFade(self, index)
    end)

    cf:HookScript("OnHide", function(self)
        local m = chatFrameMeta[self]
        if m and m.gradFrame then
            m.gradFrame:Hide()
        end
    end)

    if type(cf.HookScript) == "function" and (type(cf.HasScript) ~= "function" or cf:HasScript("OnMouseWheel")) then
        pcall(cf.HookScript, cf, "OnMouseWheel", function(self)
            if ShouldApplyTopTextFade(self, index) then
                ApplyChatTopTextFade(self, index)
            end
        end)
    end

    cf:HookScript("OnSizeChanged", function(self)
        local sdb = YRG:GetSteamdeckDB()
        if sdb and sdb.gradientChatBackground then
            UpdateChatFrameGradientBg(self, index)
        end
        ApplyChatTopTextFade(self, index)
        if ShouldSuppressChatScrollBar() then
            if self.ScrollBar then ForceHideScrollElement(self.ScrollBar) end
            if self.ScrollToBottomButton then ForceHideScrollElement(self.ScrollToBottomButton) end
        end
    end)
end

local function HookEditModeForChat()
    if editModeHooked then return end
    if not EditModeManagerFrame then return end
    editModeHooked = true

    local function OnEnterEditMode()
        editModeActive = true
        originalChat1Points = nil
        originalChat1Size = nil
    end

    local function OnExitEditMode()
        editModeActive = false
        ScheduleChatRefresh()
    end

    EditModeManagerFrame:HookScript("OnShow", OnEnterEditMode)
    EditModeManagerFrame:HookScript("OnHide", OnExitEditMode)

    if type(EditModeManagerFrame.EnterEditMode) == "function" then
        pcall(hooksecurefunc, EditModeManagerFrame, "EnterEditMode", OnEnterEditMode)
    end
    if type(EditModeManagerFrame.ExitEditMode) == "function" then
        pcall(hooksecurefunc, EditModeManagerFrame, "ExitEditMode", OnExitEditMode)
    end
    if type(EditModeManagerFrame.UpdateSystems) == "function" then
        pcall(hooksecurefunc, EditModeManagerFrame, "UpdateSystems", ScheduleChatRefresh)
    end
    if type(EditModeManagerFrame.UpdateLayoutInfo) == "function" then
        pcall(hooksecurefunc, EditModeManagerFrame, "UpdateLayoutInfo", function()
            originalChat1Points = nil
            originalChat1Size = nil
            ScheduleChatRefresh()
        end)
    end
    if type(EditModeManagerFrame.SelectLayout) == "function" then
        pcall(hooksecurefunc, EditModeManagerFrame, "SelectLayout", function()
            originalChat1Points = nil
            originalChat1Size = nil
            ScheduleChatRefresh()
        end)
    end
    if type(EditModeManagerFrame.RevertAllChanges) == "function" then
        pcall(hooksecurefunc, EditModeManagerFrame, "RevertAllChanges", ScheduleChatRefresh)
    end

    if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", OnEnterEditMode, YRG)
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", OnExitEditMode, YRG)
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.LayoutsUpdated", ScheduleChatRefresh, YRG)
    end
end

function YRG:ResetChatInactivityTimer()
    lastChatActivityTime = (GetTime and GetTime()) or 0
    if currentChatFadeAlpha < 1.0 then
        SetChatWindowsContentAlpha(1.0)
    end
end

function YRG:ApplySteamdeckSettings()
    local sdb = self:GetSteamdeckDB()

    HookEditModeForChat()

    local maxWindows = NUM_CHAT_WINDOWS or 10
    for i = 1, maxWindows do
        local cf = _G["ChatFrame" .. i]
        if cf then
            HookChatFrameForActivityAndSize(cf, i)

            if cf.EnableMouseWheel then
                cf:EnableMouseWheel(true)
            end

            -- EditBox overlap positioning & alpha hiding (never disabling input)
            local eb = cf.editBox or _G["ChatFrame" .. i .. "EditBox"]
            if eb then
                HookChatEditBox(eb, cf)
                UpdateEditBoxLayoutAndVisibility(eb, cf)
            end

            -- Update ClampRectInsets so chat frame can snap flush to left & bottom edges
            EnforceChatFrameClampInsets(cf)

            -- Custom half-radial Forever-tinted gradient background & optional top-edge text fade
            UpdateChatFrameGradientBg(cf, i)
            ApplyChatTopTextFade(cf, i)
        end
    end

    -- Enforce ScrollBar & Side Button suppression / auto-hide
    EnforceAllChatScrollBarsState()

    if ChatFrame1EditBox then
        HookChatEditBox(ChatFrame1EditBox, ChatFrame1)
        UpdateEditBoxLayoutAndVisibility(ChatFrame1EditBox, ChatFrame1)
    end

    -- Chat Tab Auto-Fade
    if sdb.autoFadeChatTabs then
        local active = IsMouseOverAnyChatOrTab() or IsAnyChatEditBoxActive()
        lastChatActiveState = active
        UpdateChatTabsAlpha(active)
    else
        lastChatActiveState = nil
        UpdateChatTabsAlpha(true)
    end

    -- Sync Inactivity Fade state across main & floating chat windows
    SetChatWindowsContentAlpha(sdb.fadeChatOnInactivity and currentChatFadeAlpha or 1.0)

    -- Snap ChatFrame1 closer to the left and/or bottom screen edges (and re-verify next frame after EditMode/Gamepad layout)
    EnforceChatFrame1EdgeSnap()
    ScheduleChatSnap()
    if self.ApplyQuickLootSettings then
        self:ApplyQuickLootSettings()
    end
    if self.ApplyCameraZoomSettings then
        self:ApplyCameraZoomSettings(false)
    end
    if self.ApplyMovieSkipSettings then
        self:ApplyMovieSkipSettings()
    end
    if self.ApplyFlightTimesSettings then
        self:ApplyFlightTimesSettings()
    end
end

-- =========================================================================
-- QUICK LOOT (Faster Auto Loot, modeled after Leatrix Plus)
-- =========================================================================
local quickLootFrame = nil
local lastQuickLootTime = 0

function YRG:ApplyQuickLootSettings()
    local sdb = self:GetSteamdeckDB()
    local enabled = sdb and sdb.quickLoot and true or false
    if not quickLootFrame then
        quickLootFrame = CreateFrame("Frame")
        quickLootFrame:SetScript("OnEvent", function()
            local db = YRG:GetSteamdeckDB()
            if not db or not db.quickLoot then return end

            local delay = YRG.SafeNumber(db.quickLootDelay, 0.3)
            local now = (type(GetTime) == "function") and GetTime() or 0
            if (now - lastQuickLootTime) >= delay then
                lastQuickLootTime = now
                local autoLoot = (type(GetCVarBool) == "function") and GetCVarBool("autoLootDefault") or false
                local modified = (type(IsModifiedClick) == "function") and IsModifiedClick("AUTOLOOTTOGGLE") or false
                if (autoLoot and not modified) or (not autoLoot and modified) then
                    if TSMDestroyBtn and TSMDestroyBtn.IsShown and TSMDestroyBtn:IsShown()
                        and TSMDestroyBtn.GetButtonState and TSMDestroyBtn:GetButtonState() == "DISABLED" then
                        lastQuickLootTime = (type(GetTime) == "function") and GetTime() or now
                        return
                    end
                    local numItems = (type(GetNumLootItems) == "function") and YRG.SafeNumber(GetNumLootItems(), 0) or 0
                    for i = numItems, 1, -1 do
                        if type(LootSlot) == "function" then
                            pcall(LootSlot, i)
                        end
                    end
                    lastQuickLootTime = (type(GetTime) == "function") and GetTime() or now
                end
            end
        end)
    end

    quickLootFrame:UnregisterAllEvents()
    if enabled then
        quickLootFrame:RegisterEvent("LOOT_READY")
    end
end

-- =========================================================================
-- MAX CAMERA ZOOM & FASTER MOVIE SKIP (Modeled after Leatrix Plus)
-- =========================================================================
local movieSkipHooksInstalled = false

function YRG:ApplyCameraZoomSettings(explicitToggle)
    local sdb = self:GetSteamdeckDB()
    local enabled = sdb and sdb.maxCameraZoom and true or false
    if type(SetCVar) ~= "function" then return end

    if enabled then
        pcall(SetCVar, "cameraDistanceMaxZoomFactor", 2.6)
    elseif explicitToggle then
        pcall(SetCVar, "cameraDistanceMaxZoomFactor", 1.9)
    end
end

function YRG:ApplyMovieSkipSettings()
    local sdb = self:GetSteamdeckDB()
    if not (sdb and sdb.fasterMovieSkip) then
        return
    end
    if movieSkipHooksInstalled then
        return
    end
    movieSkipHooksInstalled = true

    if CinematicFrame and type(CinematicFrame.HookScript) == "function" then
        pcall(CinematicFrame.HookScript, CinematicFrame, "OnKeyDown", function(_, key)
            local db = YRG:GetSteamdeckDB()
            if not (db and db.fasterMovieSkip) or InCombatLockdown() then return end
            if key == "ESCAPE" and CinematicFrame:IsShown() and CinematicFrame.closeDialog
                and CinematicFrameCloseDialogConfirmButton and CinematicFrameCloseDialog then
                pcall(CinematicFrameCloseDialog.Hide, CinematicFrameCloseDialog)
            end
        end)
        pcall(CinematicFrame.HookScript, CinematicFrame, "OnKeyUp", function(_, key)
            local db = YRG:GetSteamdeckDB()
            if not (db and db.fasterMovieSkip) or InCombatLockdown() then return end
            if (key == "SPACE" or key == "ESCAPE" or key == "ENTER")
                and CinematicFrame:IsShown() and CinematicFrame.closeDialog
                and CinematicFrameCloseDialogConfirmButton then
                pcall(CinematicFrameCloseDialogConfirmButton.Click, CinematicFrameCloseDialogConfirmButton)
            end
        end)
    end

    if MovieFrame and type(MovieFrame.HookScript) == "function" then
        pcall(MovieFrame.HookScript, MovieFrame, "OnKeyUp", function(_, key)
            local db = YRG:GetSteamdeckDB()
            if not (db and db.fasterMovieSkip) or InCombatLockdown() then return end
            if (key == "SPACE" or key == "ESCAPE" or key == "ENTER")
                and MovieFrame:IsShown() and MovieFrame.CloseDialog and MovieFrame.CloseDialog.Buttons
                and MovieFrame.CloseDialog.Buttons.ConfirmButton then
                pcall(MovieFrame.CloseDialog.Buttons.ConfirmButton.Click, MovieFrame.CloseDialog.Buttons.ConfirmButton)
            end
        end)
    end
end

-- =========================================================================
-- SHOW FLIGHT TIMES (Modeled after Leatrix Plus)
-- =========================================================================
local function BuildAllianceFlightData()
    return {
        [1415] = {
            ["0.55:0.25:0.51:0.49:0.43:0.67:0.43:0.93"]=658, ["0.55:0.25:0.51:0.49:0.43:0.67:0.61:0.78"]=591, ["0.55:0.25:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75"]=477, ["0.55:0.25:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70"]=419, ["0.55:0.25:0.51:0.49:0.51:0.57:0.58:0.65"]=390, ["0.55:0.25:0.51:0.49:0.43:0.67"]=429,
            ["0.55:0.25:0.51:0.49:0.43:0.67:0.41:0.75"]=492, ["0.55:0.25:0.51:0.49:0.51:0.57"]=304, ["0.55:0.25:0.57:0.32:0.59:0.52"]=245, ["0.55:0.25:0.51:0.49"]=256, ["0.55:0.25:0.48:0.30:0.49:0.44"]=176, ["0.55:0.25:0.57:0.32"]=75,
            ["0.55:0.25:0.48:0.30"]=68, ["0.55:0.25:0.52:0.22"]=54, ["0.55:0.25:0.70:0.16"]=164, ["0.55:0.25:0.51:0.49:0.43:0.67:0.51:0.75"]=531, ["0.55:0.25:0.51:0.49:0.43:0.67:0.56:0.70"]=527, ["0.55:0.25:0.48:0.30:0.49:0.44:0.59:0.52"]=338,
            ["0.55:0.25:0.51:0.49:0.43:0.67:0.58:0.65"]=573, ["0.55:0.25:0.57:0.32:0.49:0.44"]=202, ["0.43:0.93:0.41:0.75"]=181, ["0.43:0.93:0.51:0.75"]=175, ["0.43:0.93:0.51:0.75:0.61:0.78"]=266, ["0.43:0.93:0.51:0.75:0.56:0.70"]=230,
            ["0.43:0.93:0.51:0.75:0.56:0.70:0.58:0.65"]=291, ["0.43:0.93:0.43:0.67"]=220, ["0.43:0.93:0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57"]=383, ["0.43:0.93:0.43:0.67:0.51:0.49:0.59:0.52"]=523, ["0.43:0.93:0.43:0.67:0.51:0.49"]=464, ["0.43:0.93:0.43:0.67:0.51:0.49:0.49:0.44"]=548,
            ["0.43:0.93:0.43:0.67:0.51:0.49:0.49:0.44:0.57:0.32"]=655, ["0.43:0.93:0.43:0.67:0.51:0.49:0.49:0.44:0.48:0.30"]=649, ["0.43:0.93:0.43:0.67:0.51:0.49:0.55:0.25"]=714, ["0.43:0.93:0.43:0.67:0.51:0.49:0.52:0.22"]=712, ["0.43:0.93:0.43:0.67:0.51:0.49:0.70:0.16"]=770, ["0.43:0.93:0.43:0.67:0.51:0.49:0.51:0.57"]=496,
            ["0.43:0.93:0.43:0.67:0.56:0.70"]=319, ["0.43:0.93:0.41:0.75:0.56:0.70"]=312, ["0.43:0.93:0.55:0.57:0.56:0.61"]=492, ["0.43:0.93:0.43:0.67:0.51:0.49:0.57:0.32"]=674, ["0.43:0.93:0.43:0.67:0.51:0.49:0.48:0.30"]=680, ["0.43:0.93:0.41:0.75:0.56:0.70:0.58:0.65"]=373,
            ["0.43:0.93:0.43:0.67:0.58:0.65"]=363, ["0.43:0.93:0.43:0.67:0.58:0.65:0.51:0.57"]=454, ["0.43:0.93:0.51:0.75:0.56:0.70:0.68:0.68"]=362, ["0.43:0.93:0.51:0.75:0.56:0.70:0.68:0.68:0.59:0.52:0.57:0.32"]=696, ["0.43:0.93:0.51:0.75:0.56:0.70:0.68:0.68:0.59:0.52"]=534, ["0.43:0.93:0.51:0.75:0.56:0.70:0.68:0.68:0.59:0.52:0.57:0.32:0.55:0.25"]=768,
            ["0.52:0.22:0.51:0.49:0.43:0.67:0.43:0.93"]=662, ["0.52:0.22:0.51:0.49:0.43:0.67:0.61:0.78"]=595, ["0.52:0.22:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75"]=482, ["0.52:0.22:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70"]=424, ["0.52:0.22:0.51:0.49:0.51:0.57:0.58:0.65"]=395, ["0.52:0.22:0.51:0.49:0.43:0.67"]=432,
            ["0.52:0.22:0.51:0.49:0.43:0.67:0.41:0.75"]=495, ["0.52:0.22:0.51:0.49:0.51:0.57"]=309, ["0.52:0.22:0.51:0.49"]=261, ["0.52:0.22:0.48:0.30:0.49:0.44"]=193, ["0.52:0.22:0.55:0.25:0.57:0.32"]=138, ["0.52:0.22:0.48:0.30"]=85,
            ["0.52:0.22:0.55:0.25"]=66, ["0.52:0.22:0.70:0.16"]=147, ["0.52:0.22:0.51:0.49:0.43:0.67:0.56:0.70"]=530, ["0.52:0.22:0.48:0.30:0.57:0.32"]=157, ["0.52:0.22:0.51:0.49:0.49:0.44:0.57:0.32"]=460, ["0.52:0.22:0.51:0.49:0.43:0.67:0.51:0.75"]=534,
            ["0.52:0.22:0.55:0.25:0.57:0.32:0.59:0.52"]=309, ["0.52:0.22:0.51:0.49:0.43:0.67:0.58:0.65"]=576, ["0.52:0.22:0.48:0.30:0.57:0.32:0.59:0.52"]=327, ["0.52:0.22:0.51:0.49:0.49:0.44"]=352, ["0.52:0.22:0.51:0.49:0.59:0.52"]=325, ["0.52:0.22:0.55:0.25:0.57:0.32:0.49:0.44"]=264,
            ["0.51:0.75:0.43:0.93"]=171, ["0.51:0.75:0.41:0.75"]=113, ["0.51:0.75:0.43:0.67"]=60, ["0.51:0.75:0.61:0.78"]=97, ["0.51:0.75:0.56:0.70"]=60, ["0.51:0.75:0.56:0.70:0.58:0.65"]=120,
            ["0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57"]=212, ["0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.59:0.52"]=354, ["0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49"]=295, ["0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44"]=380, ["0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44:0.57:0.32"]=487, ["0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44:0.48:0.30"]=481,
            ["0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.55:0.25"]=545, ["0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.52:0.22"]=543, ["0.51:0.75:0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.70:0.16"]=600, ["0.51:0.75:0.43:0.67:0.51:0.49:0.49:0.44:0.48:0.30"]=518, ["0.51:0.75:0.43:0.67:0.51:0.49:0.49:0.44"]=417, ["0.51:0.75:0.43:0.67:0.51:0.49"]=333,
            ["0.51:0.75:0.43:0.67:0.51:0.49:0.49:0.44:0.57:0.32"]=524, ["0.51:0.75:0.43:0.67:0.51:0.49:0.59:0.52"]=392, ["0.51:0.75:0.43:0.67:0.51:0.49:0.55:0.25"]=582, ["0.51:0.75:0.43:0.67:0.51:0.49:0.52:0.22"]=580, ["0.51:0.75:0.43:0.67:0.51:0.49:0.51:0.57"]=365, ["0.51:0.75:0.43:0.67:0.51:0.49:0.48:0.30"]=549,
            ["0.51:0.75:0.43:0.67:0.58:0.65:0.51:0.57"]=322, ["0.51:0.75:0.43:0.67:0.51:0.49:0.57:0.32"]=543, ["0.51:0.75:0.56:0.70:0.68:0.68:0.59:0.52"]=364, ["0.51:0.75:0.56:0.70:0.68:0.68"]=191, ["0.51:0.49:0.43:0.67:0.43:0.93"]=440, ["0.51:0.49:0.43:0.67:0.61:0.78"]=373,
            ["0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75"]=260, ["0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70"]=201, ["0.51:0.49:0.51:0.57:0.58:0.65"]=173, ["0.51:0.49:0.43:0.67"]=210, ["0.51:0.49:0.43:0.67:0.41:0.75"]=274, ["0.51:0.49:0.51:0.57"]=87,
            ["0.51:0.49:0.59:0.52"]=101, ["0.51:0.49:0.49:0.44"]=128, ["0.51:0.49:0.57:0.32"]=253, ["0.51:0.49:0.48:0.30"]=265, ["0.51:0.49:0.55:0.25"]=298, ["0.51:0.49:0.52:0.22"]=294,
            ["0.51:0.49:0.70:0.16"]=349, ["0.51:0.49:0.43:0.67:0.51:0.75"]=313, ["0.51:0.49:0.43:0.67:0.56:0.70"]=312, ["0.51:0.49:0.43:0.67:0.58:0.65"]=354, ["0.51:0.49:0.59:0.52:0.68:0.68"]=283, ["0.51:0.49:0.43:0.67:0.56:0.70:0.68:0.68"]=440,
            ["0.51:0.49:0.51:0.57:0.58:0.65:0.61:0.78"]=342, ["0.56:0.70:0.51:0.75:0.43:0.93"]=227, ["0.56:0.70:0.51:0.75:0.61:0.78"]=148, ["0.56:0.70:0.51:0.75"]=60, ["0.56:0.70:0.41:0.75"]=133, ["0.56:0.70:0.43:0.67"]=113,
            ["0.56:0.70:0.58:0.65"]=61, ["0.56:0.70:0.58:0.65:0.51:0.57"]=153, ["0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.59:0.52"]=295, ["0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49"]=237, ["0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44"]=321, ["0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44:0.57:0.32"]=428,
            ["0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44:0.48:0.30"]=422, ["0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.55:0.25"]=486, ["0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.52:0.22"]=485, ["0.56:0.70:0.58:0.65:0.51:0.57:0.51:0.49:0.70:0.16"]=540, ["0.56:0.70:0.43:0.67:0.51:0.49:0.49:0.44:0.48:0.30"]=542, ["0.56:0.70:0.43:0.67:0.51:0.49:0.59:0.52"]=416,
            ["0.56:0.70:0.43:0.67:0.51:0.49"]=358, ["0.56:0.70:0.43:0.67:0.51:0.49:0.49:0.44"]=442, ["0.56:0.70:0.41:0.75:0.43:0.93"]=317, ["0.56:0.70:0.43:0.67:0.51:0.49:0.49:0.44:0.57:0.32"]=549, ["0.56:0.70:0.43:0.67:0.51:0.49:0.55:0.25"]=606, ["0.56:0.70:0.43:0.67:0.51:0.49:0.52:0.22"]=605,
            ["0.56:0.70:0.43:0.67:0.51:0.49:0.51:0.57"]=390, ["0.56:0.70:0.43:0.67:0.43:0.93"]=343, ["0.56:0.70:0.43:0.67:0.51:0.49:0.48:0.30"]=573, ["0.56:0.70:0.43:0.67:0.51:0.49:0.57:0.32"]=567, ["0.56:0.70:0.68:0.68"]=132, ["0.56:0.70:0.68:0.68:0.59:0.52:0.49:0.44"]=456,
            ["0.56:0.70:0.68:0.68:0.59:0.52:0.57:0.32:0.48:0.30"]=553, ["0.56:0.70:0.68:0.68:0.59:0.52"]=305, ["0.56:0.70:0.68:0.68:0.59:0.52:0.49:0.44:0.48:0.30"]=556, ["0.56:0.70:0.68:0.68:0.59:0.52:0.57:0.32"]=467, ["0.70:0.16:0.51:0.49:0.43:0.67:0.43:0.93"]=771, ["0.70:0.16:0.51:0.49:0.43:0.67:0.61:0.78"]=704,
            ["0.70:0.16:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75"]=591, ["0.70:0.16:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70"]=532, ["0.70:0.16:0.51:0.49:0.51:0.57:0.58:0.65"]=503, ["0.70:0.16:0.51:0.49:0.43:0.67"]=541, ["0.70:0.16:0.51:0.49:0.51:0.57"]=417, ["0.70:0.16:0.51:0.49"]=369,
            ["0.70:0.16:0.55:0.25:0.48:0.30:0.49:0.44"]=333, ["0.70:0.16:0.55:0.25:0.57:0.32"]=233, ["0.70:0.16:0.55:0.25:0.48:0.30"]=226, ["0.70:0.16:0.55:0.25"]=163, ["0.70:0.16:0.52:0.22"]=150, ["0.70:0.16:0.52:0.22:0.48:0.30:0.57:0.32"]=298,
            ["0.70:0.16:0.52:0.22:0.48:0.30"]=227, ["0.70:0.16:0.52:0.22:0.48:0.30:0.49:0.44"]=334, ["0.70:0.16:0.51:0.49:0.43:0.67:0.41:0.75"]=604, ["0.70:0.16:0.55:0.25:0.57:0.32:0.59:0.52"]=402, ["0.70:0.16:0.51:0.49:0.43:0.67:0.56:0.70"]=639, ["0.70:0.16:0.51:0.49:0.49:0.44:0.48:0.30"]=563,
            ["0.70:0.16:0.51:0.49:0.49:0.44"]=462, ["0.70:0.16:0.51:0.49:0.43:0.67:0.58:0.65"]=684, ["0.70:0.16:0.51:0.49:0.49:0.44:0.57:0.32"]=569, ["0.70:0.16:0.51:0.49:0.43:0.67:0.51:0.75"]=643, ["0.70:0.16:0.55:0.25:0.57:0.32:0.49:0.44"]=358, ["0.70:0.16:0.51:0.49:0.59:0.52"]=434,
            ["0.49:0.44:0.51:0.49:0.43:0.67:0.43:0.93"]=490, ["0.49:0.44:0.51:0.49:0.43:0.67:0.61:0.78"]=423, ["0.49:0.44:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75"]=309, ["0.49:0.44:0.51:0.49:0.43:0.67:0.41:0.75"]=324, ["0.49:0.44:0.51:0.49:0.43:0.67"]=261, ["0.49:0.44:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70"]=250,
            ["0.49:0.44:0.51:0.49:0.51:0.57:0.58:0.65"]=221, ["0.49:0.44:0.51:0.49:0.51:0.57"]=135, ["0.49:0.44:0.59:0.52"]=163, ["0.49:0.44:0.51:0.49"]=89, ["0.49:0.44:0.57:0.32"]=113, ["0.49:0.44:0.48:0.30"]=107,
            ["0.49:0.44:0.48:0.30:0.55:0.25"]=176, ["0.49:0.44:0.48:0.30:0.52:0.22"]=186, ["0.49:0.44:0.48:0.30:0.52:0.22:0.70:0.16"]=324, ["0.49:0.44:0.51:0.49:0.43:0.67:0.51:0.75"]=362, ["0.49:0.44:0.51:0.49:0.43:0.67:0.56:0.70"]=359, ["0.49:0.44:0.57:0.32:0.55:0.25"]=185,
            ["0.49:0.44:0.51:0.49:0.43:0.67:0.58:0.65"]=403, ["0.49:0.44:0.51:0.49:0.52:0.22"]=344, ["0.49:0.44:0.51:0.49:0.70:0.16"]=394, ["0.49:0.44:0.57:0.32:0.55:0.25:0.52:0.22"]=236, ["0.49:0.44:0.57:0.32:0.55:0.25:0.70:0.16"]=346, ["0.49:0.44:0.59:0.52:0.68:0.68"]=347,
            ["0.58:0.65:0.56:0.70:0.51:0.75:0.43:0.93"]=288, ["0.58:0.65:0.61:0.78"]=210, ["0.58:0.65:0.56:0.70:0.51:0.75"]=121, ["0.58:0.65:0.56:0.70"]=64, ["0.58:0.65:0.43:0.67"]=151, ["0.58:0.65:0.56:0.70:0.41:0.75"]=195,
            ["0.58:0.65:0.51:0.57"]=104, ["0.58:0.65:0.51:0.57:0.51:0.49:0.59:0.52"]=245, ["0.58:0.65:0.51:0.57:0.51:0.49"]=187, ["0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44"]=270, ["0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44:0.57:0.32"]=378, ["0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44:0.48:0.30"]=372,
            ["0.58:0.65:0.51:0.57:0.51:0.49:0.55:0.25"]=436, ["0.58:0.65:0.51:0.57:0.51:0.49:0.52:0.22"]=435, ["0.58:0.65:0.51:0.57:0.51:0.49:0.70:0.16"]=491, ["0.58:0.65:0.43:0.67:0.51:0.49:0.59:0.52"]=455, ["0.58:0.65:0.43:0.67:0.51:0.49"]=397, ["0.58:0.65:0.43:0.67:0.51:0.49:0.49:0.44"]=480,
            ["0.58:0.65:0.43:0.67:0.51:0.75"]=254, ["0.58:0.65:0.43:0.67:0.41:0.75"]=215, ["0.58:0.65:0.43:0.67:0.51:0.49:0.55:0.25"]=645, ["0.58:0.65:0.43:0.67:0.51:0.49:0.49:0.44:0.48:0.30"]=581, ["0.58:0.65:0.43:0.67:0.51:0.49:0.49:0.44:0.57:0.32"]=588, ["0.58:0.65:0.43:0.67:0.51:0.49:0.52:0.22"]=644,
            ["0.58:0.65:0.43:0.67:0.43:0.93"]=382, ["0.58:0.65:0.43:0.67:0.51:0.49:0.70:0.16"]=701, ["0.58:0.65:0.56:0.70:0.41:0.75:0.43:0.93"]=378, ["0.58:0.65:0.68:0.68:0.59:0.52"]=304, ["0.58:0.65:0.68:0.68:0.59:0.52:0.49:0.44:0.48:0.30"]=556, ["0.58:0.65:0.68:0.68"]=132,
            ["0.61:0.78:0.51:0.75:0.43:0.93"]=260, ["0.61:0.78:0.51:0.75"]=91, ["0.61:0.78:0.51:0.75:0.56:0.70"]=150, ["0.61:0.78:0.58:0.65"]=207, ["0.61:0.78:0.43:0.67"]=189, ["0.61:0.78:0.51:0.75:0.41:0.75"]=184,
            ["0.61:0.78:0.58:0.65:0.51:0.57"]=300, ["0.61:0.78:0.58:0.65:0.51:0.57:0.51:0.49"]=382, ["0.61:0.78:0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44"]=467, ["0.61:0.78:0.58:0.65:0.51:0.57:0.51:0.49:0.55:0.25"]=635, ["0.61:0.78:0.58:0.65:0.51:0.57:0.51:0.49:0.52:0.22"]=631, ["0.61:0.78:0.58:0.65:0.51:0.57:0.51:0.49:0.70:0.16"]=687,
            ["0.61:0.78:0.58:0.65:0.51:0.57:0.51:0.49:0.59:0.52"]=444, ["0.61:0.78:0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44:0.57:0.32"]=577, ["0.61:0.78:0.51:0.75:0.43:0.67:0.51:0.49:0.55:0.25"]=673, ["0.61:0.78:0.51:0.75:0.43:0.67:0.51:0.49"]=424, ["0.61:0.78:0.51:0.75:0.43:0.67:0.51:0.49:0.49:0.44:0.48:0.30"]=608, ["0.61:0.78:0.51:0.75:0.43:0.67:0.51:0.49:0.49:0.44:0.57:0.32"]=615,
            ["0.61:0.78:0.51:0.75:0.43:0.67:0.51:0.49:0.49:0.44"]=508, ["0.61:0.78:0.51:0.75:0.43:0.67:0.51:0.49:0.59:0.52"]=482, ["0.61:0.78:0.51:0.75:0.43:0.67:0.51:0.49:0.51:0.57"]=456, ["0.61:0.78:0.58:0.65:0.51:0.57:0.51:0.49:0.49:0.44:0.48:0.30"]=570, ["0.61:0.78:0.51:0.75:0.43:0.67:0.51:0.49:0.52:0.22"]=671, ["0.61:0.78:0.51:0.75:0.43:0.67:0.51:0.49:0.70:0.16"]=728,
            ["0.61:0.78:0.43:0.67:0.41:0.75"]=253, ["0.61:0.78:0.43:0.67:0.51:0.49:0.51:0.57"]=466, ["0.61:0.78:0.43:0.67:0.51:0.49:0.49:0.44"]=518, ["0.61:0.78:0.43:0.67:0.51:0.49"]=434, ["0.61:0.78:0.43:0.67:0.56:0.70"]=288, ["0.61:0.78:0.51:0.75:0.56:0.70:0.68:0.68"]=282,
            ["0.61:0.78:0.51:0.75:0.56:0.70:0.68:0.68:0.59:0.52"]=454, ["0.61:0.78:0.51:0.75:0.56:0.70:0.68:0.68:0.59:0.52:0.57:0.32:0.55:0.25"]=687, ["0.57:0.32:0.49:0.44:0.51:0.49:0.43:0.67:0.43:0.93"]=614, ["0.57:0.32:0.49:0.44:0.51:0.49:0.43:0.67:0.61:0.78"]=547, ["0.57:0.32:0.49:0.44:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75"]=433, ["0.57:0.32:0.49:0.44:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70"]=374,
            ["0.57:0.32:0.49:0.44:0.51:0.49:0.51:0.57:0.58:0.65"]=346, ["0.57:0.32:0.49:0.44:0.51:0.49:0.43:0.67:0.41:0.75"]=448, ["0.57:0.32:0.59:0.52"]=171, ["0.57:0.32:0.51:0.49"]=271, ["0.57:0.32:0.49:0.44"]=126, ["0.57:0.32:0.48:0.30"]=87,
            ["0.57:0.32:0.55:0.25"]=72, ["0.57:0.32:0.55:0.25:0.52:0.22"]=122, ["0.57:0.32:0.55:0.25:0.70:0.16"]=233, ["0.57:0.32:0.49:0.44:0.51:0.49:0.51:0.57"]=260, ["0.57:0.32:0.48:0.30:0.52:0.22:0.70:0.16"]=304, ["0.57:0.32:0.49:0.44:0.51:0.49:0.43:0.67"]=384,
            ["0.57:0.32:0.49:0.44:0.51:0.49:0.43:0.67:0.51:0.75"]=486, ["0.57:0.32:0.49:0.44:0.51:0.49:0.43:0.67:0.56:0.70"]=483, ["0.57:0.32:0.48:0.30:0.52:0.22"]=166, ["0.57:0.32:0.49:0.44:0.51:0.49:0.52:0.22"]=469, ["0.57:0.32:0.49:0.44:0.51:0.49:0.43:0.67:0.58:0.65"]=528, ["0.57:0.32:0.51:0.49:0.43:0.67:0.41:0.75"]=502,
            ["0.57:0.32:0.51:0.49:0.43:0.67:0.56:0.70"]=538, ["0.57:0.32:0.49:0.44:0.51:0.49:0.70:0.16"]=518, ["0.57:0.32:0.51:0.49:0.43:0.67:0.51:0.75"]=541, ["0.57:0.32:0.51:0.49:0.43:0.67"]=439, ["0.57:0.32:0.59:0.52:0.68:0.68"]=355, ["0.41:0.75:0.43:0.93"]=185,
            ["0.41:0.75:0.51:0.75:0.61:0.78"]=186, ["0.41:0.75:0.51:0.75"]=97, ["0.41:0.75:0.56:0.70"]=130, ["0.41:0.75:0.56:0.70:0.58:0.65"]=191, ["0.41:0.75:0.43:0.67"]=86, ["0.41:0.75:0.56:0.70:0.58:0.65:0.51:0.57"]=282,
            ["0.41:0.75:0.43:0.67:0.51:0.49:0.59:0.52"]=389, ["0.41:0.75:0.43:0.67:0.51:0.49"]=331, ["0.41:0.75:0.43:0.67:0.51:0.49:0.49:0.44"]=414, ["0.41:0.75:0.43:0.67:0.51:0.49:0.55:0.25"]=579, ["0.41:0.75:0.43:0.67:0.51:0.49:0.52:0.22"]=578, ["0.41:0.75:0.43:0.67:0.51:0.49:0.51:0.57"]=363,
            ["0.41:0.75:0.43:0.67:0.51:0.49:0.49:0.44:0.57:0.32"]=522, ["0.41:0.75:0.43:0.67:0.51:0.49:0.49:0.44:0.48:0.30"]=515, ["0.41:0.75:0.43:0.67:0.51:0.49:0.70:0.16"]=635, ["0.41:0.75:0.43:0.67:0.51:0.49:0.48:0.30"]=546, ["0.41:0.75:0.43:0.67:0.51:0.49:0.57:0.32"]=540, ["0.48:0.30:0.49:0.44:0.51:0.49:0.43:0.67:0.43:0.93"]=597,
            ["0.48:0.30:0.49:0.44:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75"]=415, ["0.48:0.30:0.49:0.44:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70"]=357, ["0.48:0.30:0.49:0.44:0.51:0.49:0.51:0.57:0.58:0.65"]=329, ["0.48:0.30:0.49:0.44:0.51:0.49:0.43:0.67"]=367, ["0.48:0.30:0.49:0.44:0.51:0.49:0.43:0.67:0.41:0.75"]=430, ["0.48:0.30:0.57:0.32:0.59:0.52"]=244,
            ["0.48:0.30:0.51:0.49"]=206, ["0.48:0.30:0.49:0.44"]=110, ["0.48:0.30:0.57:0.32"]=74, ["0.48:0.30:0.55:0.25"]=71, ["0.48:0.30:0.52:0.22"]=81, ["0.48:0.30:0.52:0.22:0.70:0.16"]=219,
            ["0.48:0.30:0.49:0.44:0.51:0.49:0.43:0.67:0.51:0.75"]=468, ["0.48:0.30:0.49:0.44:0.51:0.49:0.51:0.57"]=243, ["0.48:0.30:0.49:0.44:0.51:0.49:0.43:0.67:0.61:0.78"]=529, ["0.48:0.30:0.49:0.44:0.51:0.49:0.43:0.67:0.56:0.70"]=465, ["0.48:0.30:0.49:0.44:0.59:0.52"]=273, ["0.48:0.30:0.51:0.49:0.43:0.67:0.51:0.75"]=474,
            ["0.48:0.30:0.51:0.49:0.59:0.52"]=262, ["0.48:0.30:0.51:0.49:0.43:0.67"]=372, ["0.48:0.30:0.51:0.49:0.43:0.67:0.56:0.70"]=471, ["0.48:0.30:0.49:0.44:0.51:0.49:0.43:0.67:0.58:0.65"]=510, ["0.48:0.30:0.51:0.49:0.43:0.67:0.41:0.75"]=436, ["0.48:0.30:0.51:0.49:0.51:0.57"]=248,
            ["0.48:0.30:0.49:0.44:0.51:0.49:0.43:0.67:0.56:0.70:0.68:0.68"]=596, ["0.48:0.30:0.57:0.32:0.59:0.52:0.68:0.68"]=428, ["0.43:0.67:0.43:0.93"]=245, ["0.43:0.67:0.41:0.75"]=78, ["0.43:0.67:0.51:0.75"]=116, ["0.43:0.67:0.61:0.78"]=176,
            ["0.43:0.67:0.56:0.70"]=113, ["0.43:0.67:0.58:0.65"]=157, ["0.43:0.67:0.58:0.65:0.51:0.57"]=247, ["0.43:0.67:0.51:0.49:0.59:0.52"]=317, ["0.43:0.67:0.51:0.49"]=259, ["0.43:0.67:0.51:0.49:0.49:0.44"]=343,
            ["0.43:0.67:0.51:0.49:0.49:0.44:0.57:0.32"]=450, ["0.43:0.67:0.51:0.49:0.49:0.44:0.48:0.30"]=443, ["0.43:0.67:0.51:0.49:0.55:0.25"]=508, ["0.43:0.67:0.51:0.49:0.52:0.22"]=506, ["0.43:0.67:0.51:0.49:0.70:0.16"]=563, ["0.43:0.67:0.51:0.49:0.51:0.57"]=291,
            ["0.43:0.67:0.51:0.49:0.48:0.30"]=475, ["0.43:0.67:0.51:0.49:0.57:0.32"]=469, ["0.43:0.67:0.56:0.70:0.68:0.68"]=245, ["0.59:0.52:0.51:0.49:0.43:0.67:0.43:0.93"]=508, ["0.59:0.52:0.51:0.49:0.43:0.67:0.61:0.78"]=441, ["0.59:0.52:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75"]=326,
            ["0.59:0.52:0.51:0.49:0.51:0.57:0.58:0.65:0.56:0.70"]=267, ["0.59:0.52:0.51:0.49:0.43:0.67"]=279, ["0.59:0.52:0.51:0.49:0.43:0.67:0.41:0.75"]=342, ["0.59:0.52:0.51:0.49:0.51:0.57"]=152, ["0.59:0.52:0.51:0.49"]=109, ["0.59:0.52:0.49:0.44"]=153,
            ["0.59:0.52:0.57:0.32"]=164, ["0.59:0.52:0.57:0.32:0.48:0.30"]=250, ["0.59:0.52:0.57:0.32:0.55:0.25"]=235, ["0.59:0.52:0.57:0.32:0.55:0.25:0.52:0.22"]=285, ["0.59:0.52:0.51:0.49:0.43:0.67:0.56:0.70"]=377, ["0.59:0.52:0.51:0.49:0.70:0.16"]=421,
            ["0.59:0.52:0.51:0.49:0.43:0.67:0.51:0.75"]=381, ["0.59:0.52:0.49:0.44:0.48:0.30"]=254, ["0.59:0.52:0.57:0.32:0.55:0.25:0.70:0.16"]=397, ["0.59:0.52:0.57:0.32:0.48:0.30:0.52:0.22"]=328, ["0.59:0.52:0.51:0.49:0.51:0.57:0.58:0.65"]=239, ["0.59:0.52:0.49:0.44:0.48:0.30:0.55:0.25"]=323,
            ["0.59:0.52:0.49:0.44:0.48:0.30:0.52:0.22"]=332, ["0.59:0.52:0.51:0.49:0.48:0.30"]=328, ["0.59:0.52:0.51:0.49:0.43:0.67:0.58:0.65"]=422, ["0.59:0.52:0.51:0.49:0.52:0.22"]=355, ["0.59:0.52:0.68:0.68:0.56:0.70"]=315, ["0.59:0.52:0.68:0.68"]=185,
            ["0.59:0.52:0.68:0.68:0.56:0.70:0.51:0.75"]=375, ["0.59:0.52:0.68:0.68:0.56:0.70:0.51:0.75:0.61:0.78"]=463, ["0.59:0.52:0.68:0.68:0.56:0.70:0.51:0.75:0.43:0.93"]=542, ["0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75:0.43:0.93"]=350, ["0.51:0.57:0.58:0.65:0.61:0.78"]=265, ["0.51:0.57:0.58:0.65:0.56:0.70:0.51:0.75"]=183,
            ["0.51:0.57:0.58:0.65"]=96, ["0.51:0.57:0.51:0.49:0.49:0.44"]=178, ["0.51:0.57:0.51:0.49"]=94, ["0.51:0.57:0.51:0.49:0.59:0.52"]=152, ["0.51:0.57:0.51:0.49:0.55:0.25"]=343, ["0.51:0.57:0.51:0.49:0.52:0.22"]=342,
            ["0.51:0.57:0.51:0.49:0.70:0.16"]=398, ["0.51:0.57:0.58:0.65:0.56:0.70"]=125, ["0.51:0.57:0.51:0.49:0.49:0.44:0.57:0.32"]=286, ["0.51:0.57:0.51:0.49:0.49:0.44:0.48:0.30"]=280, ["0.51:0.57:0.51:0.49:0.43:0.67"]=257, ["0.51:0.57:0.51:0.49:0.43:0.67:0.61:0.78"]=420,
            ["0.51:0.57:0.51:0.49:0.43:0.67:0.41:0.75"]=321, ["0.51:0.57:0.58:0.65:0.43:0.67"]=220, ["0.51:0.57:0.51:0.49:0.43:0.67:0.56:0.70"]=356, ["0.51:0.57:0.58:0.65:0.56:0.70:0.41:0.75"]=257, ["0.51:0.57:0.51:0.49:0.43:0.67:0.43:0.93"]=488, ["0.51:0.57:0.51:0.49:0.43:0.67:0.51:0.75"]=359,
            ["0.51:0.57:0.58:0.65:0.43:0.67:0.51:0.75"]=322, ["0.68:0.68:0.56:0.70"]=131, ["0.68:0.68:0.59:0.52:0.49:0.44"]=324, ["0.68:0.68:0.56:0.70:0.43:0.67"]=244, ["0.68:0.68:0.56:0.70:0.51:0.75"]=191, ["0.68:0.68:0.59:0.52"]=174,
            ["0.68:0.68:0.59:0.52:0.51:0.49"]=282, ["0.68:0.68:0.59:0.52:0.57:0.32"]=336, ["0.68:0.68:0.59:0.52:0.57:0.32:0.48:0.30"]=421, ["0.68:0.68:0.56:0.70:0.51:0.75:0.43:0.93"]=358, ["0.68:0.68:0.56:0.70:0.41:0.75"]=264, ["0.68:0.68:0.56:0.70:0.51:0.75:0.61:0.78"]=278,
            ["0.68:0.68:0.59:0.52:0.57:0.32:0.55:0.25"]=407, ["0.68:0.68:0.56:0.70:0.43:0.67:0.51:0.49:0.49:0.44:0.48:0.30"]=673, ["0.68:0.68:0.56:0.70:0.43:0.67:0.51:0.49"]=488, ["0.68:0.68:0.56:0.70:0.43:0.67:0.51:0.49:0.52:0.22"]=736, ["0.68:0.68:0.59:0.52:0.49:0.44:0.48:0.30"]=425,
        },
        [1414] = {
            ["0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=538, ["0.46:0.40:0.39:0.40:0.40:0.51:0.31:0.69"]=511, ["0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67"]=381, ["0.46:0.40:0.61:0.40:0.61:0.55"]=283, ["0.46:0.40:0.61:0.40"]=150, ["0.46:0.40:0.39:0.40:0.40:0.51"]=279,
            ["0.46:0.40:0.39:0.40"]=153, ["0.46:0.40:0.43:0.25"]=148, ["0.46:0.40:0.43:0.25:0.42:0.16"]=231, ["0.46:0.40:0.43:0.25:0.53:0.26"]=338, ["0.46:0.40:0.43:0.25:0.64:0.67:0.61:0.55"]=932, ["0.46:0.40:0.43:0.25:0.55:0.21"]=299,
            ["0.46:0.40:0.61:0.40:0.65:0.23"]=327, ["0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=545, ["0.46:0.40:0.39:0.40:0.40:0.51:0.31:0.69:0.42:0.79"]=668, ["0.46:0.40:0.43:0.25:0.40:0.51"]=439, ["0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=642, ["0.46:0.40:0.39:0.40:0.40:0.51:0.64:0.67:0.61:0.55"]=701,
            ["0.46:0.40:0.43:0.25:0.64:0.67:0.48:0.70"]=982, ["0.46:0.40:0.61:0.40:0.64:0.67"]=390, ["0.46:0.40:0.43:0.25:0.64:0.67"]=823, ["0.46:0.40:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81"]=903, ["0.46:0.40:0.43:0.25:0.31:0.69"]=620, ["0.46:0.40:0.43:0.25:0.55:0.21:0.65:0.23"]=429,
            ["0.46:0.40:0.39:0.40:0.40:0.51:0.64:0.67:0.60:0.81"]=744, ["0.46:0.40:0.43:0.25:0.40:0.51:0.64:0.67:0.61:0.55"]=861, ["0.46:0.40:0.39:0.40:0.40:0.51:0.64:0.67"]=587, ["0.46:0.40:0.43:0.25:0.40:0.51:0.64:0.67"]=746, ["0.46:0.40:0.39:0.40:0.40:0.51:0.64:0.67:0.48:0.70"]=750, ["0.46:0.40:0.39:0.40:0.40:0.51:0.31:0.69:0.48:0.70"]=666,
            ["0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=736, ["0.46:0.40:0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81"]=945, ["0.46:0.40:0.39:0.40:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76"]=848, ["0.46:0.40:0.61:0.40:0.64:0.67:0.48:0.70"]=551, ["0.46:0.40:0.43:0.25:0.64:0.67:0.60:0.81"]=976, ["0.46:0.40:0.43:0.25:0.31:0.69:0.48:0.70"]=775,
            ["0.46:0.40:0.39:0.40:0.40:0.51:0.31:0.69:0.48:0.70:0.60:0.81"]=836, ["0.46:0.40:0.61:0.40:0.64:0.67:0.60:0.81"]=545, ["0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.42:0.79"]=734, ["0.46:0.40:0.43:0.25:0.31:0.69:0.42:0.79"]=778, ["0.46:0.40:0.43:0.25:0.53:0.26:0.65:0.23"]=439, ["0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67:0.40:0.51"]=715,
            ["0.46:0.40:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76"]=1006, ["0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=689, ["0.43:0.25:0.64:0.67"]=675, ["0.43:0.25:0.31:0.69:0.42:0.79:0.50:0.76"]=712, ["0.43:0.25:0.31:0.69"]=473, ["0.43:0.25:0.61:0.40:0.61:0.55"]=435,
            ["0.43:0.25:0.61:0.40"]=301, ["0.43:0.25:0.46:0.40"]=176, ["0.43:0.25:0.40:0.51"]=291, ["0.43:0.25:0.39:0.40"]=181, ["0.43:0.25:0.42:0.16"]=84, ["0.43:0.25:0.55:0.21"]=151,
            ["0.43:0.25:0.53:0.26"]=190, ["0.43:0.25:0.55:0.21:0.65:0.23"]=282, ["0.43:0.25:0.31:0.69:0.48:0.70"]=627, ["0.43:0.25:0.31:0.69:0.42:0.79"]=630, ["0.43:0.25:0.53:0.26:0.65:0.23"]=292, ["0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81"]=755,
            ["0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=696, ["0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=793, ["0.43:0.25:0.64:0.67:0.61:0.55"]=784, ["0.43:0.25:0.64:0.67:0.48:0.70"]=834, ["0.43:0.25:0.40:0.51:0.64:0.67:0.48:0.70"]=761, ["0.43:0.25:0.40:0.51:0.64:0.67:0.61:0.55"]=713,
            ["0.43:0.25:0.64:0.67:0.60:0.81"]=828, ["0.43:0.25:0.61:0.40:0.64:0.67:0.48:0.70"]=704, ["0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=887, ["0.43:0.25:0.61:0.40:0.65:0.23"]=479, ["0.43:0.25:0.61:0.40:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=895, ["0.43:0.25:0.61:0.40:0.64:0.67:0.60:0.81"]=697,
            ["0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81:0.50:0.76"]=902, ["0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81"]=798, ["0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76"]=859, ["0.42:0.79:0.60:0.81"]=189, ["0.42:0.79:0.50:0.76"]=92, ["0.42:0.79:0.31:0.69:0.48:0.70"]=329,
            ["0.42:0.79:0.31:0.69"]=175, ["0.42:0.79:0.60:0.81:0.64:0.67"]=342, ["0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.40"]=576, ["0.42:0.79:0.31:0.69:0.43:0.25:0.42:0.16"]=726, ["0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.55"]=450, ["0.42:0.79:0.31:0.69:0.40:0.51"]=402,
            ["0.42:0.79:0.31:0.69:0.40:0.51:0.39:0.40"]=521, ["0.42:0.79:0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40"]=675, ["0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.40:0.65:0.23"]=755, ["0.42:0.79:0.31:0.69:0.43:0.25:0.53:0.26"]=832, ["0.42:0.79:0.31:0.69:0.43:0.25:0.55:0.21"]=793, ["0.42:0.79:0.31:0.69:0.43:0.25"]=643,
            ["0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40"]=729, ["0.42:0.79:0.60:0.81:0.48:0.70"]=366, ["0.42:0.79:0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26:0.65:0.23"]=1242, ["0.42:0.79:0.31:0.69:0.43:0.25:0.53:0.26:0.65:0.23"]=934, ["0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.39:0.40"]=881, ["0.42:0.79:0.60:0.81:0.64:0.67:0.40:0.51"]=669,
            ["0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25:0.42:0.16"]=961, ["0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.40:0.53:0.26"]=859, ["0.42:0.79:0.31:0.69:0.43:0.25:0.55:0.21:0.65:0.23"]=923, ["0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.40:0.65:0.23:0.55:0.21"]=876, ["0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25"]=876, ["0.42:0.79:0.31:0.69:0.43:0.25:0.46:0.40"]=818,
            ["0.42:0.79:0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.55:0.21"]=1101, ["0.42:0.79:0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26:0.65:0.23:0.57:0.33"]=1323, ["0.65:0.23:0.55:0.21"]=122, ["0.65:0.23:0.53:0.26"]=123, ["0.65:0.23:0.55:0.21:0.43:0.25:0.42:0.16"]=346, ["0.65:0.23:0.61:0.40"]=176,
            ["0.65:0.23:0.55:0.21:0.43:0.25"]=263, ["0.65:0.23:0.61:0.40:0.46:0.40"]=328, ["0.65:0.23:0.55:0.21:0.43:0.25:0.39:0.40"]=443, ["0.65:0.23:0.61:0.40:0.61:0.55"]=310, ["0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67"]=408, ["0.65:0.23:0.55:0.21:0.43:0.25:0.40:0.51"]=553,
            ["0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=565, ["0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=668, ["0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=763, ["0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=571, ["0.65:0.23:0.55:0.21:0.43:0.25:0.31:0.69"]=735, ["0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70:0.31:0.69"]=748,
            ["0.65:0.23:0.53:0.26:0.43:0.25:0.42:0.16"]=376, ["0.65:0.23:0.55:0.21:0.43:0.25:0.46:0.40"]=438, ["0.65:0.23:0.53:0.26:0.43:0.25:0.46:0.40"]=468, ["0.65:0.23:0.53:0.26:0.43:0.25"]=293, ["0.65:0.23:0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81"]=1017, ["0.65:0.23:0.61:0.40:0.64:0.67"]=416,
            ["0.65:0.23:0.53:0.26:0.43:0.25:0.64:0.67"]=967, ["0.65:0.23:0.53:0.26:0.43:0.25:0.40:0.51:0.64:0.67"]=890, ["0.65:0.23:0.55:0.21:0.43:0.25:0.64:0.67:0.48:0.70"]=1097, ["0.65:0.23:0.55:0.21:0.43:0.25:0.31:0.69:0.42:0.79"]=892, ["0.65:0.23:0.53:0.26:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81"]=1046, ["0.65:0.23:0.53:0.26:0.43:0.25:0.40:0.51"]=583,
            ["0.65:0.23:0.55:0.21:0.43:0.25:0.64:0.67:0.61:0.55"]=1046, ["0.65:0.23:0.53:0.26:0.43:0.25:0.31:0.69"]=764, ["0.65:0.23:0.61:0.40:0.46:0.40:0.43:0.25:0.42:0.16"]=559, ["0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.42:0.79"]=762, ["0.65:0.23:0.61:0.40:0.46:0.40:0.39:0.40"]=480, ["0.65:0.23:0.61:0.40:0.64:0.67:0.60:0.81:0.50:0.76"]=676,
            ["0.65:0.23:0.61:0.40:0.64:0.67:0.48:0.70"]=579, ["0.65:0.23:0.53:0.26:0.43:0.25:0.31:0.69:0.42:0.79"]=921, ["0.65:0.23:0.61:0.40:0.46:0.40:0.39:0.40:0.40:0.51:0.31:0.69"]=838, ["0.65:0.23:0.55:0.21:0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81"]=1060, ["0.65:0.23:0.53:0.26:0.43:0.25:0.64:0.67:0.60:0.81"]=1120, ["0.65:0.23:0.61:0.40:0.46:0.40:0.43:0.25"]=475,
            ["0.65:0.23:0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76"]=1120, ["0.65:0.23:0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67"]=861, ["0.65:0.23:0.55:0.21:0.43:0.25:0.31:0.69:0.42:0.79:0.50:0.76"]=975, ["0.65:0.23:0.53:0.26:0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81"]=1089, ["0.65:0.23:0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=1215, ["0.65:0.23:0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67:0.61:0.55"]=975,
            ["0.65:0.23:0.53:0.26:0.43:0.25:0.40:0.51:0.64:0.67:0.61:0.55"]=1005, ["0.65:0.23:0.55:0.21:0.43:0.25:0.31:0.69:0.48:0.70"]=889, ["0.65:0.23:0.53:0.26:0.43:0.25:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=1318, ["0.65:0.23:0.61:0.40:0.64:0.67:0.60:0.81"]=572, ["0.65:0.23:0.61:0.40:0.46:0.40:0.39:0.40:0.40:0.51"]=606, ["0.65:0.23:0.53:0.26:0.43:0.25:0.39:0.40"]=474,
            ["0.31:0.69:0.48:0.70:0.60:0.81"]=326, ["0.31:0.69:0.48:0.70:0.64:0.67"]=314, ["0.31:0.69:0.48:0.70"]=155, ["0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40"]=500, ["0.31:0.69:0.40:0.51:0.39:0.40"]=347, ["0.31:0.69:0.40:0.51"]=227,
            ["0.31:0.69:0.43:0.25"]=468, ["0.31:0.69:0.43:0.25:0.42:0.16"]=551, ["0.31:0.69:0.42:0.79:0.50:0.76"]=243, ["0.31:0.69:0.48:0.70:0.60:0.81:0.50:0.76"]=430, ["0.31:0.69:0.42:0.79"]=160, ["0.31:0.69:0.48:0.70:0.64:0.67:0.61:0.55"]=429,
            ["0.31:0.69:0.48:0.70:0.64:0.67:0.61:0.40:0.65:0.23"]=726, ["0.31:0.69:0.48:0.70:0.64:0.67:0.61:0.40"]=548, ["0.31:0.69:0.43:0.25:0.55:0.21"]=619, ["0.31:0.69:0.43:0.25:0.46:0.40"]=643, ["0.31:0.69:0.43:0.25:0.53:0.26"]=657, ["0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40:0.61:0.40:0.61:0.55"]=783,
            ["0.31:0.69:0.40:0.51:0.64:0.67"]=534, ["0.31:0.69:0.43:0.25:0.55:0.21:0.65:0.23"]=748, ["0.31:0.69:0.42:0.79:0.60:0.81"]=341, ["0.31:0.69:0.40:0.51:0.64:0.67:0.60:0.81"]=691, ["0.31:0.69:0.43:0.25:0.39:0.40"]=649, ["0.31:0.69:0.40:0.51:0.64:0.67:0.61:0.55"]=649,
            ["0.31:0.69:0.43:0.25:0.64:0.67:0.60:0.81"]=1296, ["0.31:0.69:0.43:0.25:0.53:0.26:0.65:0.23"]=759, ["0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40:0.61:0.40"]=648, ["0.31:0.69:0.43:0.25:0.61:0.40"]=767, ["0.31:0.69:0.48:0.70:0.64:0.67:0.61:0.40:0.46:0.40"]=700, ["0.31:0.69:0.42:0.79:0.60:0.81:0.64:0.67"]=494,
            ["0.31:0.69:0.43:0.25:0.64:0.67"]=1143, ["0.31:0.69:0.42:0.79:0.60:0.81:0.64:0.67:0.61:0.40"]=728, ["0.60:0.81:0.50:0.76"]=104, ["0.60:0.81:0.42:0.79"]=197, ["0.60:0.81:0.48:0.70:0.31:0.69"]=354, ["0.60:0.81:0.48:0.70"]=177,
            ["0.60:0.81:0.64:0.67"]=154, ["0.60:0.81:0.64:0.67:0.61:0.55"]=262, ["0.60:0.81:0.64:0.67:0.61:0.40"]=388, ["0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40"]=540, ["0.60:0.81:0.64:0.67:0.40:0.51"]=480, ["0.60:0.81:0.64:0.67:0.40:0.51:0.39:0.40"]=600,
            ["0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25"]=688, ["0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25:0.42:0.16"]=772, ["0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.42:0.16"]=847, ["0.60:0.81:0.64:0.67:0.61:0.40:0.53:0.26"]=671, ["0.60:0.81:0.64:0.67:0.61:0.40:0.65:0.23:0.55:0.21"]=688, ["0.60:0.81:0.64:0.67:0.40:0.51:0.31:0.69"]=712,
            ["0.60:0.81:0.64:0.67:0.61:0.40:0.65:0.23"]=567, ["0.60:0.81:0.64:0.67:0.40:0.51:0.39:0.40:0.46:0.40"]=753, ["0.60:0.81:0.64:0.67:0.43:0.25:0.39:0.40"]=949, ["0.60:0.81:0.64:0.67:0.43:0.25:0.42:0.16"]=852, ["0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25"]=763, ["0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.55:0.21:0.65:0.23"]=1043,
            ["0.60:0.81:0.50:0.76:0.42:0.79:0.31:0.69"]=362, ["0.60:0.81:0.64:0.67:0.43:0.25:0.46:0.40"]=944, ["0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26"]=952, ["0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.39:0.40"]=693, ["0.60:0.81:0.64:0.67:0.43:0.25"]=768, ["0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.46:0.40"]=938,
            ["0.60:0.81:0.64:0.67:0.43:0.25:0.53:0.26:0.65:0.23"]=1059, ["0.60:0.81:0.64:0.67:0.61:0.40:0.43:0.25"]=690, ["0.60:0.81:0.48:0.70:0.31:0.69:0.43:0.25:0.42:0.16"]=906, ["0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.55:0.21"]=913, ["0.60:0.81:0.64:0.67:0.43:0.25:0.55:0.21:0.65:0.23"]=1049, ["0.60:0.81:0.48:0.70:0.31:0.69:0.43:0.25"]=822,
            ["0.60:0.81:0.48:0.70:0.31:0.69:0.43:0.25:0.46:0.40"]=998, ["0.60:0.81:0.48:0.70:0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40:0.61:0.40:0.61:0.55"]=1136, ["0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25:0.55:0.21"]=839, ["0.60:0.81:0.64:0.67:0.43:0.25:0.55:0.21"]=919, ["0.60:0.81:0.48:0.70:0.31:0.69:0.40:0.51"]=581, ["0.60:0.81:0.64:0.67:0.61:0.40:0.53:0.26:0.55:0.21"]=730,
            ["0.60:0.81:0.48:0.70:0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40:0.61:0.40"]=1002, ["0.60:0.81:0.48:0.70:0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40"]=855, ["0.60:0.81:0.64:0.67:0.61:0.40:0.43:0.25:0.31:0.69"]=1161, ["0.60:0.81:0.64:0.67:0.43:0.25:0.53:0.26"]=958, ["0.60:0.81:0.64:0.67:0.61:0.40:0.43:0.25:0.42:0.16"]=774, ["0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26:0.65:0.23"]=1054,
            ["0.60:0.81:0.50:0.76:0.42:0.79:0.31:0.69:0.43:0.25:0.53:0.26"]=1019, ["0.50:0.76:0.60:0.81"]=104, ["0.50:0.76:0.42:0.79"]=94, ["0.50:0.76:0.42:0.79:0.31:0.69"]=258, ["0.50:0.76:0.60:0.81:0.48:0.70"]=281, ["0.50:0.76:0.60:0.81:0.64:0.67"]=257,
            ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.55"]=364, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40"]=644, ["0.50:0.76:0.42:0.79:0.31:0.69:0.40:0.51"]=485, ["0.50:0.76:0.42:0.79:0.31:0.69:0.43:0.25:0.42:0.16"]=809, ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.42:0.16"]=950, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40"]=492,
            ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.65:0.23:0.55:0.21"]=792, ["0.50:0.76:0.42:0.79:0.31:0.69:0.40:0.51:0.39:0.40"]=605, ["0.50:0.76:0.60:0.81:0.48:0.70:0.31:0.69"]=458, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.65:0.23"]=670, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25:0.42:0.16"]=876, ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26"]=1055,
            ["0.50:0.76:0.42:0.79:0.31:0.69:0.43:0.25"]=726, ["0.50:0.76:0.60:0.81:0.64:0.67:0.43:0.25:0.42:0.16"]=956, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.53:0.26"]=774, ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.55:0.21:0.65:0.23"]=1147, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25"]=792, ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51"]=584,
            ["0.50:0.76:0.42:0.79:0.31:0.69:0.43:0.25:0.53:0.26"]=915, ["0.50:0.76:0.42:0.79:0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40"]=758, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.53:0.26:0.55:0.21"]=833, ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.46:0.40"]=1042, ["0.50:0.76:0.42:0.79:0.31:0.69:0.43:0.25:0.55:0.21"]=876, ["0.50:0.76:0.42:0.79:0.31:0.69:0.43:0.25:0.46:0.40"]=902,
            ["0.50:0.76:0.42:0.79:0.31:0.69:0.43:0.25:0.55:0.21:0.65:0.23"]=1006, ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51:0.39:0.40:0.46:0.40"]=856, ["0.50:0.76:0.60:0.81:0.48:0.70:0.31:0.69:0.43:0.25:0.42:0.16"]=1010, ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25"]=866, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25:0.55:0.21"]=942, ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51:0.39:0.40"]=703,
            ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26:0.65:0.23"]=1157, ["0.50:0.76:0.60:0.81:0.64:0.67:0.43:0.25"]=871, ["0.50:0.76:0.60:0.81:0.64:0.67:0.40:0.51:0.31:0.69"]=815, ["0.50:0.76:0.60:0.81:0.64:0.67:0.43:0.25:0.46:0.40"]=1047, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.65:0.23:0.57:0.33:0.59:0.30"]=788, ["0.55:0.21:0.43:0.25:0.31:0.69"]=614,
            ["0.55:0.21:0.65:0.23"]=131, ["0.55:0.21:0.53:0.26"]=62, ["0.55:0.21:0.43:0.25"]=143, ["0.55:0.21:0.43:0.25:0.42:0.16"]=226, ["0.55:0.21:0.65:0.23:0.61:0.40"]=307, ["0.55:0.21:0.43:0.25:0.39:0.40"]=323,
            ["0.55:0.21:0.43:0.25:0.46:0.40"]=318, ["0.55:0.21:0.43:0.25:0.40:0.51"]=433, ["0.55:0.21:0.65:0.23:0.61:0.40:0.61:0.55"]=440, ["0.55:0.21:0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=695, ["0.55:0.21:0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67"]=538, ["0.55:0.21:0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=701,
            ["0.55:0.21:0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=799, ["0.55:0.21:0.43:0.25:0.31:0.69:0.42:0.79"]=772, ["0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81"]=897, ["0.55:0.21:0.43:0.25:0.61:0.40"]=441, ["0.55:0.21:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=837, ["0.55:0.21:0.43:0.25:0.61:0.40:0.61:0.55"]=576,
            ["0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67"]=740, ["0.55:0.21:0.53:0.26:0.61:0.40"]=330, ["0.55:0.21:0.43:0.25:0.64:0.67:0.61:0.55"]=925, ["0.55:0.21:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=831, ["0.55:0.21:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67"]=674, ["0.55:0.21:0.43:0.25:0.64:0.67"]=817,
            ["0.55:0.21:0.53:0.26:0.61:0.40:0.61:0.55"]=464, ["0.55:0.21:0.43:0.25:0.64:0.67:0.60:0.81"]=970, ["0.55:0.21:0.53:0.26:0.61:0.40:0.61:0.55:0.64:0.67"]=562, ["0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67:0.48:0.70"]=903, ["0.55:0.21:0.43:0.25:0.31:0.69:0.48:0.70"]=769, ["0.55:0.21:0.43:0.25:0.64:0.67:0.48:0.70"]=976,
            ["0.55:0.21:0.53:0.26:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=822, ["0.55:0.21:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=935, ["0.55:0.21:0.53:0.26:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=718, ["0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67:0.61:0.55"]=855, ["0.55:0.21:0.43:0.25:0.31:0.69:0.42:0.79:0.50:0.76"]=854, ["0.55:0.21:0.43:0.25:0.61:0.40:0.64:0.67"]=682,
            ["0.55:0.21:0.53:0.26:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=725, ["0.55:0.21:0.43:0.25:0.61:0.40:0.64:0.67:0.60:0.81"]=838, ["0.55:0.21:0.53:0.26:0.61:0.40:0.64:0.67"]=570, ["0.55:0.21:0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=892, ["0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76"]=1000, ["0.55:0.21:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=1094,
            ["0.55:0.21:0.65:0.23:0.61:0.40:0.64:0.67"]=546, ["0.55:0.21:0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81"]=939, ["0.55:0.21:0.43:0.25:0.61:0.40:0.64:0.67:0.48:0.70"]=845, ["0.55:0.21:0.65:0.23:0.61:0.40:0.64:0.67:0.48:0.70"]=709, ["0.55:0.21:0.65:0.23:0.61:0.40:0.64:0.67:0.60:0.81:0.50:0.76"]=806, ["0.40:0.51:0.64:0.67:0.60:0.81"]=464,
            ["0.40:0.51:0.64:0.67"]=308, ["0.40:0.51:0.31:0.69:0.48:0.70"]=387, ["0.40:0.51:0.31:0.69"]=232, ["0.40:0.51:0.64:0.67:0.61:0.55"]=422, ["0.40:0.51:0.39:0.40:0.46:0.40:0.61:0.40"]=421, ["0.40:0.51:0.39:0.40:0.46:0.40"]=273,
            ["0.40:0.51:0.39:0.40"]=120, ["0.40:0.51:0.43:0.25"]=282, ["0.40:0.51:0.43:0.25:0.42:0.16"]=367, ["0.40:0.51:0.43:0.25:0.55:0.21:0.65:0.23"]=563, ["0.40:0.51:0.43:0.25:0.53:0.26"]=472, ["0.40:0.51:0.43:0.25:0.55:0.21"]=434,
            ["0.40:0.51:0.31:0.69:0.42:0.79:0.50:0.76"]=471, ["0.40:0.51:0.31:0.69:0.42:0.79"]=388, ["0.40:0.51:0.64:0.67:0.48:0.70"]=471, ["0.40:0.51:0.43:0.25:0.61:0.40:0.61:0.55"]=717, ["0.40:0.51:0.43:0.25:0.46:0.40"]=458, ["0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76"]=568,
            ["0.40:0.51:0.39:0.40:0.46:0.40:0.61:0.40:0.61:0.55"]=555, ["0.40:0.51:0.64:0.67:0.61:0.40"]=541, ["0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=662, ["0.40:0.51:0.43:0.25:0.61:0.40"]=582, ["0.40:0.51:0.31:0.69:0.48:0.70:0.60:0.81"]=558, ["0.40:0.51:0.64:0.67:0.60:0.81:0.42:0.79"]=661,
            ["0.40:0.51:0.43:0.25:0.53:0.26:0.65:0.23"]=574, ["0.61:0.55:0.64:0.67:0.60:0.81"]=261, ["0.61:0.55:0.64:0.67"]=106, ["0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=366, ["0.61:0.55:0.64:0.67:0.48:0.70"]=268, ["0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=459,
            ["0.61:0.55:0.64:0.67:0.48:0.70:0.31:0.69"]=446, ["0.61:0.55:0.64:0.67:0.40:0.51"]=439, ["0.61:0.55:0.61:0.40:0.46:0.40:0.39:0.40"]=437, ["0.61:0.55:0.61:0.40:0.46:0.40"]=284, ["0.61:0.55:0.61:0.40"]=132, ["0.61:0.55:0.61:0.40:0.46:0.40:0.43:0.25:0.42:0.16"]=516,
            ["0.61:0.55:0.61:0.40:0.53:0.26"]=415, ["0.61:0.55:0.61:0.40:0.65:0.23:0.55:0.21"]=433, ["0.61:0.55:0.61:0.40:0.65:0.23"]=311, ["0.61:0.55:0.61:0.40:0.46:0.40:0.43:0.25"]=432, ["0.61:0.55:0.64:0.67:0.43:0.25:0.46:0.40"]=900, ["0.61:0.55:0.64:0.67:0.43:0.25:0.39:0.40"]=906,
            ["0.61:0.55:0.64:0.67:0.40:0.51:0.39:0.40:0.46:0.40"]=711, ["0.61:0.55:0.64:0.67:0.43:0.25"]=725, ["0.61:0.55:0.64:0.67:0.43:0.25:0.42:0.16"]=809, ["0.61:0.55:0.64:0.67:0.40:0.51:0.43:0.25:0.42:0.16"]=805, ["0.61:0.55:0.64:0.67:0.40:0.51:0.43:0.25:0.55:0.21:0.65:0.23"]=1001, ["0.61:0.55:0.64:0.67:0.40:0.51:0.43:0.25:0.46:0.40"]=896,
            ["0.61:0.55:0.64:0.67:0.40:0.51:0.31:0.69"]=671, ["0.61:0.55:0.64:0.67:0.40:0.51:0.39:0.40"]=558, ["0.61:0.55:0.64:0.67:0.40:0.51:0.43:0.25"]=721, ["0.61:0.55:0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26"]=910, ["0.61:0.55:0.64:0.67:0.60:0.81:0.42:0.79"]=459, ["0.61:0.55:0.61:0.40:0.46:0.40:0.39:0.40:0.40:0.51"]=563,
            ["0.61:0.55:0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26:0.65:0.23"]=1012, ["0.61:0.55:0.61:0.40:0.43:0.25"]=434, ["0.61:0.55:0.61:0.40:0.46:0.40:0.43:0.25:0.31:0.69:0.48:0.70"]=1058, ["0.61:0.55:0.61:0.40:0.46:0.40:0.43:0.25:0.40:0.51"]=723, ["0.61:0.55:0.61:0.40:0.46:0.40:0.43:0.25:0.55:0.21"]=583, ["0.61:0.55:0.61:0.40:0.46:0.40:0.39:0.40:0.40:0.51:0.31:0.69"]=795,
            ["0.61:0.55:0.61:0.40:0.46:0.40:0.39:0.40:0.40:0.51:0.31:0.69:0.48:0.70:0.60:0.81"]=1120, ["0.61:0.55:0.61:0.40:0.46:0.40:0.43:0.25:0.31:0.69"]=904, ["0.61:0.55:0.64:0.67:0.40:0.51:0.43:0.25:0.55:0.21"]=871, ["0.61:0.55:0.61:0.40:0.53:0.26:0.55:0.21"]=474, ["0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79:0.31:0.69"]=624, ["0.61:0.55:0.64:0.67:0.43:0.25:0.53:0.26"]=914,
            ["0.61:0.55:0.64:0.67:0.43:0.25:0.53:0.26:0.65:0.23"]=1016, ["0.61:0.55:0.64:0.67:0.60:0.81:0.42:0.79:0.31:0.69"]=625, ["0.61:0.55:0.61:0.40:0.43:0.25:0.42:0.16"]=517, ["0.61:0.55:0.64:0.67:0.48:0.70:0.31:0.69:0.42:0.79"]=602, ["0.61:0.55:0.61:0.40:0.65:0.23:0.53:0.26"]=434, ["0.42:0.16:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=774,
            ["0.42:0.16:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67"]=617, ["0.42:0.16:0.43:0.25:0.31:0.69:0.42:0.79:0.50:0.76"]=797, ["0.42:0.16:0.43:0.25:0.31:0.69:0.48:0.70"]=711, ["0.42:0.16:0.43:0.25:0.31:0.69:0.42:0.79"]=714, ["0.42:0.16:0.43:0.25:0.31:0.69"]=557, ["0.42:0.16:0.43:0.25:0.61:0.40:0.61:0.55"]=519,
            ["0.42:0.16:0.43:0.25:0.61:0.40"]=385, ["0.42:0.16:0.43:0.25:0.40:0.51"]=376, ["0.42:0.16:0.43:0.25:0.46:0.40"]=261, ["0.42:0.16:0.43:0.25:0.39:0.40"]=267, ["0.42:0.16:0.43:0.25"]=86, ["0.42:0.16:0.43:0.25:0.53:0.26"]=275,
            ["0.42:0.16:0.43:0.25:0.55:0.21"]=236, ["0.42:0.16:0.43:0.25:0.55:0.21:0.65:0.23"]=366, ["0.42:0.16:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=878, ["0.42:0.16:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81"]=840, ["0.42:0.16:0.43:0.25:0.64:0.67"]=761, ["0.42:0.16:0.43:0.25:0.64:0.67:0.61:0.55"]=868,
            ["0.42:0.16:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76"]=943, ["0.42:0.16:0.43:0.25:0.40:0.51:0.64:0.67"]=684, ["0.42:0.16:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=781, ["0.42:0.16:0.43:0.25:0.40:0.51:0.64:0.67:0.48:0.70"]=846, ["0.42:0.16:0.43:0.25:0.53:0.26:0.65:0.23"]=376, ["0.42:0.16:0.43:0.25:0.61:0.40:0.65:0.23"]=563,
            ["0.42:0.16:0.43:0.25:0.40:0.51:0.64:0.67:0.61:0.55"]=798, ["0.42:0.16:0.43:0.25:0.64:0.67:0.48:0.70"]=920, ["0.42:0.16:0.43:0.25:0.64:0.67:0.60:0.81"]=913, ["0.42:0.16:0.43:0.25:0.61:0.40:0.64:0.67:0.60:0.81"]=782, ["0.42:0.16:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=972, ["0.42:0.16:0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81"]=883,
            ["0.42:0.16:0.43:0.25:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=1111, ["0.42:0.16:0.43:0.25:0.61:0.40:0.64:0.67"]=625, ["0.42:0.16:0.43:0.25:0.61:0.40:0.64:0.67:0.48:0.70"]=788, ["0.42:0.16:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=1038, ["0.42:0.16:0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81:0.50:0.76"]=987, ["0.42:0.16:0.43:0.25:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.42:0.79"]=971,
            ["0.42:0.16:0.43:0.25:0.64:0.67:0.60:0.81:0.42:0.79"]=1110, ["0.42:0.16:0.43:0.25:0.31:0.69:0.42:0.79:0.60:0.81"]=896, ["0.42:0.16:0.43:0.25:0.64:0.67:0.60:0.81:0.50:0.76"]=1017, ["0.42:0.16:0.43:0.25:0.61:0.40:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=980, ["0.39:0.40:0.40:0.51:0.64:0.67:0.60:0.81"]=591, ["0.39:0.40:0.40:0.51:0.64:0.67"]=434,
            ["0.39:0.40:0.40:0.51"]=126, ["0.39:0.40:0.46:0.40"]=154, ["0.39:0.40:0.43:0.25"]=177, ["0.39:0.40:0.43:0.25:0.42:0.16"]=261, ["0.39:0.40:0.46:0.40:0.61:0.40"]=302, ["0.39:0.40:0.43:0.25:0.55:0.21:0.65:0.23"]=458,
            ["0.39:0.40:0.43:0.25:0.53:0.26"]=367, ["0.39:0.40:0.43:0.25:0.55:0.21"]=328, ["0.39:0.40:0.46:0.40:0.61:0.40:0.61:0.55"]=437, ["0.39:0.40:0.40:0.51:0.31:0.69:0.48:0.70"]=513, ["0.39:0.40:0.40:0.51:0.31:0.69:0.42:0.79"]=515, ["0.39:0.40:0.43:0.25:0.64:0.67:0.61:0.55"]=961,
            ["0.39:0.40:0.40:0.51:0.64:0.67:0.48:0.70"]=597, ["0.39:0.40:0.43:0.25:0.64:0.67"]=853, ["0.39:0.40:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76"]=695, ["0.39:0.40:0.40:0.51:0.64:0.67:0.61:0.55"]=549, ["0.39:0.40:0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=698, ["0.39:0.40:0.40:0.51:0.31:0.69"]=359,
            ["0.39:0.40:0.43:0.25:0.64:0.67:0.48:0.70"]=1011, ["0.39:0.40:0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67"]=535, ["0.39:0.40:0.46:0.40:0.61:0.40:0.65:0.23"]=481, ["0.39:0.40:0.43:0.25:0.64:0.67:0.60:0.81"]=1005, ["0.39:0.40:0.46:0.40:0.61:0.40:0.64:0.67"]=543, ["0.39:0.40:0.46:0.40:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=691,
            ["0.53:0.26:0.55:0.21"]=68, ["0.53:0.26:0.65:0.23"]=121, ["0.53:0.26:0.43:0.25"]=188, ["0.53:0.26:0.43:0.25:0.42:0.16"]=272, ["0.53:0.26:0.61:0.40"]=283, ["0.53:0.26:0.43:0.25:0.46:0.40"]=364,
            ["0.53:0.26:0.43:0.25:0.39:0.40"]=369, ["0.53:0.26:0.61:0.40:0.61:0.55"]=417, ["0.53:0.26:0.43:0.25:0.40:0.51"]=479, ["0.53:0.26:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81"]=942, ["0.53:0.26:0.61:0.40:0.61:0.55:0.64:0.67"]=516, ["0.53:0.26:0.43:0.25:0.31:0.69"]=660,
            ["0.53:0.26:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=672, ["0.53:0.26:0.43:0.25:0.31:0.69:0.42:0.79"]=817, ["0.53:0.26:0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=678, ["0.53:0.26:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=777, ["0.53:0.26:0.43:0.25:0.40:0.51:0.64:0.67:0.60:0.81:0.50:0.76"]=1046, ["0.53:0.26:0.43:0.25:0.64:0.67:0.61:0.55"]=972,
            ["0.53:0.26:0.43:0.25:0.40:0.51:0.64:0.67:0.48:0.70"]=948, ["0.53:0.26:0.43:0.25:0.40:0.51:0.64:0.67"]=786, ["0.53:0.26:0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=870, ["0.53:0.26:0.43:0.25:0.31:0.69:0.42:0.79:0.50:0.76"]=900, ["0.53:0.26:0.43:0.25:0.64:0.67"]=862, ["0.53:0.26:0.43:0.25:0.40:0.51:0.64:0.67:0.61:0.55"]=900,
            ["0.53:0.26:0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81"]=985, ["0.53:0.26:0.61:0.40:0.64:0.67:0.48:0.70"]=686, ["0.53:0.26:0.61:0.40:0.46:0.40"]=434, ["0.53:0.26:0.43:0.25:0.31:0.69:0.48:0.70"]=815, ["0.53:0.26:0.43:0.25:0.64:0.67:0.60:0.81"]=1016, ["0.53:0.26:0.43:0.25:0.64:0.67:0.48:0.70"]=1021,
            ["0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81"]=391, ["0.61:0.40:0.64:0.67"]=241, ["0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76"]=494, ["0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=588, ["0.61:0.40:0.61:0.55"]=135, ["0.61:0.40:0.46:0.40"]=153,
            ["0.61:0.40:0.43:0.25"]=301, ["0.61:0.40:0.53:0.26"]=284, ["0.61:0.40:0.65:0.23:0.55:0.21"]=301, ["0.61:0.40:0.46:0.40:0.39:0.40:0.40:0.51"]=432, ["0.61:0.40:0.46:0.40:0.39:0.40"]=305, ["0.61:0.40:0.65:0.23"]=180,
            ["0.61:0.40:0.46:0.40:0.43:0.25:0.42:0.16"]=385, ["0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70"]=397, ["0.61:0.40:0.61:0.55:0.64:0.67:0.48:0.70:0.31:0.69"]=574, ["0.61:0.40:0.64:0.67:0.60:0.81"]=398, ["0.61:0.40:0.46:0.40:0.43:0.25:0.55:0.21"]=451, ["0.61:0.40:0.43:0.25:0.42:0.16"]=386,
            ["0.61:0.40:0.46:0.40:0.39:0.40:0.40:0.51:0.31:0.69"]=663, ["0.61:0.40:0.61:0.55:0.64:0.67:0.40:0.51"]=567, ["0.61:0.40:0.46:0.40:0.43:0.25:0.40:0.51"]=591, ["0.61:0.40:0.53:0.26:0.55:0.21"]=342, ["0.61:0.40:0.46:0.40:0.43:0.25:0.31:0.69"]=773, ["0.61:0.40:0.64:0.67:0.48:0.70"]=405,
            ["0.61:0.40:0.46:0.40:0.39:0.40:0.40:0.51:0.31:0.69:0.48:0.70:0.60:0.81"]=988, ["0.61:0.40:0.46:0.40:0.43:0.25:0.31:0.69:0.48:0.70"]=927, ["0.61:0.40:0.46:0.40:0.43:0.25:0.31:0.69:0.48:0.70:0.60:0.81"]=1098, ["0.61:0.40:0.61:0.55:0.64:0.67:0.60:0.81:0.42:0.79"]=587, ["0.61:0.40:0.64:0.67:0.40:0.51"]=575, ["0.61:0.40:0.64:0.67:0.48:0.70:0.31:0.69"]=582,
            ["0.48:0.70:0.60:0.81"]=171, ["0.48:0.70:0.60:0.81:0.50:0.76"]=274, ["0.48:0.70:0.31:0.69:0.42:0.79"]=335, ["0.48:0.70:0.31:0.69"]=179, ["0.48:0.70:0.64:0.67"]=159, ["0.48:0.70:0.64:0.67:0.61:0.55"]=274,
            ["0.48:0.70:0.31:0.69:0.40:0.51"]=405, ["0.48:0.70:0.31:0.69:0.43:0.25:0.42:0.16"]=729, ["0.48:0.70:0.64:0.67:0.40:0.51"]=494, ["0.48:0.70:0.64:0.67:0.61:0.40"]=394, ["0.48:0.70:0.31:0.69:0.40:0.51:0.39:0.40"]=524, ["0.48:0.70:0.64:0.67:0.61:0.40:0.46:0.40"]=545,
            ["0.48:0.70:0.64:0.67:0.61:0.40:0.65:0.23"]=572, ["0.48:0.70:0.64:0.67:0.61:0.40:0.53:0.26"]=676, ["0.48:0.70:0.64:0.67:0.61:0.40:0.65:0.23:0.55:0.21"]=693, ["0.48:0.70:0.31:0.69:0.43:0.25"]=646, ["0.48:0.70:0.64:0.67:0.40:0.51:0.43:0.25:0.42:0.16"]=859, ["0.48:0.70:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25"]=693,
            ["0.48:0.70:0.64:0.67:0.43:0.25:0.46:0.40"]=955, ["0.48:0.70:0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25:0.42:0.16"]=777, ["0.48:0.70:0.64:0.67:0.40:0.51:0.39:0.40"]=613, ["0.48:0.70:0.64:0.67:0.43:0.25:0.39:0.40"]=961, ["0.48:0.70:0.64:0.67:0.43:0.25:0.42:0.16"]=864, ["0.48:0.70:0.64:0.67:0.40:0.51:0.39:0.40:0.46:0.40"]=766,
            ["0.48:0.70:0.64:0.67:0.43:0.25"]=780, ["0.48:0.70:0.64:0.67:0.61:0.40:0.46:0.40:0.39:0.40"]=698, ["0.48:0.70:0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40"]=678, ["0.48:0.70:0.31:0.69:0.40:0.51:0.39:0.40:0.46:0.40:0.61:0.40:0.61:0.55"]=960, ["0.48:0.70:0.64:0.67:0.40:0.51:0.43:0.25"]=775, ["0.48:0.70:0.64:0.67:0.61:0.40:0.53:0.26:0.55:0.21"]=734,
            ["0.48:0.70:0.64:0.67:0.40:0.51:0.43:0.25:0.46:0.40"]=950, ["0.48:0.70:0.60:0.81:0.42:0.79"]=368, ["0.48:0.70:0.31:0.69:0.43:0.25:0.46:0.40"]=821, ["0.48:0.70:0.60:0.81:0.50:0.76:0.42:0.79"]=370, ["0.48:0.70:0.31:0.69:0.43:0.25:0.53:0.26"]=835, ["0.48:0.70:0.31:0.69:0.43:0.25:0.55:0.21:0.65:0.23"]=926,
            ["0.48:0.70:0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26"]=965, ["0.64:0.67:0.60:0.81"]=157, ["0.64:0.67:0.60:0.81:0.50:0.76"]=261, ["0.64:0.67:0.48:0.70"]=162, ["0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79"]=354, ["0.64:0.67:0.48:0.70:0.31:0.69"]=341,
            ["0.64:0.67:0.61:0.55"]=115, ["0.64:0.67:0.61:0.40"]=235, ["0.64:0.67:0.61:0.40:0.46:0.40"]=387, ["0.64:0.67:0.40:0.51"]=334, ["0.64:0.67:0.40:0.51:0.39:0.40"]=454, ["0.64:0.67:0.43:0.25"]=620,
            ["0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25:0.42:0.16"]=619, ["0.64:0.67:0.43:0.25:0.46:0.40"]=796, ["0.64:0.67:0.40:0.51:0.43:0.25:0.42:0.16"]=700, ["0.64:0.67:0.61:0.40:0.65:0.23"]=414, ["0.64:0.67:0.61:0.40:0.53:0.26"]=518, ["0.64:0.67:0.43:0.25:0.42:0.16"]=705,
            ["0.64:0.67:0.61:0.40:0.46:0.40:0.39:0.40"]=540, ["0.64:0.67:0.40:0.51:0.39:0.40:0.46:0.40"]=607, ["0.64:0.67:0.61:0.40:0.65:0.23:0.55:0.21"]=536, ["0.64:0.67:0.60:0.81:0.42:0.79"]=354, ["0.64:0.67:0.40:0.51:0.43:0.25:0.46:0.40"]=792, ["0.64:0.67:0.43:0.25:0.39:0.40"]=802,
            ["0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26:0.65:0.23"]=907, ["0.64:0.67:0.40:0.51:0.43:0.25:0.53:0.26"]=806, ["0.64:0.67:0.40:0.51:0.43:0.25:0.55:0.21:0.65:0.23"]=897, ["0.64:0.67:0.40:0.51:0.31:0.69"]=566, ["0.64:0.67:0.61:0.40:0.53:0.26:0.55:0.21"]=576, ["0.64:0.67:0.43:0.25:0.53:0.26:0.65:0.23"]=911,
            ["0.64:0.67:0.43:0.25:0.53:0.26"]=810, ["0.64:0.67:0.61:0.40:0.46:0.40:0.43:0.25:0.55:0.21"]=686, ["0.64:0.67:0.60:0.81:0.50:0.76:0.42:0.79:0.31:0.69"]=519, ["0.64:0.67:0.48:0.70:0.31:0.69:0.42:0.79"]=498, ["0.64:0.67:0.61:0.40:0.43:0.25:0.42:0.16"]=621, ["0.64:0.67:0.43:0.25:0.55:0.21:0.65:0.23"]=901,
            ["0.64:0.67:0.43:0.25:0.31:0.69"]=1093, ["0.64:0.67:0.40:0.51:0.31:0.69:0.42:0.79"]=721, ["0.64:0.67:0.40:0.51:0.43:0.25:0.55:0.21"]=767, ["0.64:0.67:0.60:0.81:0.42:0.79:0.31:0.69"]=520, ["0.59:0.30:0.57:0.33:0.65:0.23:0.61:0.40:0.61:0.55:0.64:0.67"]=357, ["0.59:0.30:0.57:0.33:0.65:0.23"]=113,
            ["0.59:0.30:0.57:0.33:0.65:0.23:0.61:0.40"]=217,
        },
    }
end

local function BuildHordeFlightData()
    return {
        [1415] = {
            ["0.43:0.93:0.45:0.84"]=102, ["0.43:0.93:0.61:0.75"]=267, ["0.43:0.93:0.61:0.75:0.56:0.61"]=464, ["0.43:0.93:0.55:0.57"]=406, ["0.43:0.93:0.55:0.57:0.51:0.57"]=462, ["0.43:0.93:0.55:0.57:0.62:0.31"]=668,
            ["0.43:0.93:0.55:0.57:0.62:0.31:0.67:0.30"]=757, ["0.43:0.93:0.55:0.57:0.62:0.31:0.67:0.30:0.70:0.16"]=896, ["0.43:0.93:0.55:0.57:0.62:0.31:0.49:0.27"]=783, ["0.43:0.93:0.55:0.57:0.44:0.19"]=903, ["0.43:0.93:0.55:0.57:0.62:0.31:0.49:0.27:0.38:0.24"]=857, ["0.43:0.93:0.55:0.57:0.44:0.19:0.49:0.27"]=970,
            ["0.43:0.93:0.55:0.57:0.44:0.19:0.38:0.24"]=938, ["0.43:0.93:0.61:0.75:0.56:0.61:0.51:0.57"]=534, ["0.43:0.93:0.55:0.57:0.44:0.19:0.67:0.30"]=1112, ["0.43:0.93:0.55:0.57:0.44:0.19:0.70:0.16"]=1092, ["0.43:0.93:0.55:0.57:0.56:0.61"]=492, ["0.43:0.93:0.61:0.75:0.67:0.63"]=436,
            ["0.43:0.93:0.61:0.75:0.67:0.63:0.62:0.31"]=764, ["0.43:0.93:0.55:0.57:0.67:0.63"]=533, ["0.56:0.61:0.61:0.75:0.43:0.93"]=472, ["0.56:0.61:0.61:0.75:0.45:0.84"]=401, ["0.56:0.61:0.61:0.75"]=213, ["0.56:0.61:0.51:0.57"]=72,
            ["0.56:0.61:0.55:0.57"]=99, ["0.56:0.61:0.55:0.57:0.62:0.31"]=361, ["0.56:0.61:0.55:0.57:0.62:0.31:0.67:0.30"]=451, ["0.56:0.61:0.55:0.57:0.62:0.31:0.67:0.30:0.70:0.16"]=589, ["0.56:0.61:0.55:0.57:0.62:0.31:0.49:0.27"]=477, ["0.56:0.61:0.55:0.57:0.44:0.19"]=597,
            ["0.56:0.61:0.55:0.57:0.62:0.31:0.49:0.27:0.38:0.24"]=576, ["0.56:0.61:0.55:0.57:0.45:0.84:0.43:0.93"]=492, ["0.56:0.61:0.55:0.57:0.45:0.84"]=412, ["0.56:0.61:0.55:0.57:0.44:0.19:0.49:0.27"]=663, ["0.56:0.61:0.55:0.57:0.44:0.19:0.67:0.30"]=805, ["0.56:0.61:0.55:0.57:0.44:0.19:0.70:0.16"]=785,
            ["0.56:0.61:0.55:0.57:0.43:0.93"]=516, ["0.56:0.61:0.67:0.63"]=138, ["0.45:0.84:0.43:0.93"]=81, ["0.45:0.84:0.61:0.75"]=205, ["0.45:0.84:0.61:0.75:0.56:0.61"]=402, ["0.45:0.84:0.55:0.57"]=327,
            ["0.45:0.84:0.55:0.57:0.51:0.57"]=382, ["0.45:0.84:0.55:0.57:0.62:0.31"]=588, ["0.45:0.84:0.55:0.57:0.62:0.31:0.67:0.30"]=677, ["0.45:0.84:0.55:0.57:0.62:0.31:0.67:0.30:0.70:0.16"]=816, ["0.45:0.84:0.55:0.57:0.62:0.31:0.49:0.27"]=704, ["0.45:0.84:0.55:0.57:0.44:0.19"]=823,
            ["0.45:0.84:0.55:0.57:0.62:0.31:0.49:0.27:0.38:0.24"]=802, ["0.45:0.84:0.55:0.57:0.44:0.19:0.49:0.27"]=890, ["0.45:0.84:0.55:0.57:0.56:0.61"]=413, ["0.45:0.84:0.55:0.57:0.44:0.19:0.70:0.16"]=1012, ["0.45:0.84:0.55:0.57:0.44:0.19:0.38:0.24"]=858, ["0.45:0.84:0.61:0.75:0.56:0.61:0.51:0.57"]=473,
            ["0.45:0.84:0.55:0.57:0.44:0.19:0.67:0.30"]=1032, ["0.45:0.84:0.55:0.57:0.67:0.63"]=454, ["0.45:0.84:0.61:0.75:0.67:0.63"]=375, ["0.45:0.84:0.61:0.75:0.67:0.63:0.62:0.31:0.49:0.27:0.44:0.19"]=957, ["0.62:0.31:0.55:0.57:0.45:0.84:0.43:0.93"]=651, ["0.62:0.31:0.55:0.57:0.45:0.84"]=571,
            ["0.62:0.31:0.55:0.57:0.61:0.75"]=539, ["0.62:0.31:0.55:0.57:0.56:0.61"]=344, ["0.62:0.31:0.55:0.57"]=259, ["0.62:0.31:0.55:0.57:0.51:0.57"]=314, ["0.62:0.31:0.67:0.30"]=91, ["0.62:0.31:0.67:0.30:0.70:0.16"]=229,
            ["0.62:0.31:0.49:0.27"]=117, ["0.62:0.31:0.44:0.19"]=259, ["0.62:0.31:0.49:0.27:0.38:0.24"]=190, ["0.62:0.31:0.49:0.27:0.44:0.19:0.70:0.16"]=441, ["0.62:0.31:0.44:0.19:0.38:0.24"]=290, ["0.62:0.31:0.55:0.57:0.43:0.93"]=675,
            ["0.62:0.31:0.44:0.19:0.70:0.16"]=444, ["0.62:0.31:0.67:0.63"]=326, ["0.62:0.31:0.67:0.63:0.61:0.75:0.45:0.84"]=668, ["0.62:0.31:0.67:0.63:0.61:0.75"]=480, ["0.55:0.57:0.43:0.93"]=417, ["0.55:0.57:0.45:0.84"]=313,
            ["0.55:0.57:0.61:0.75"]=280, ["0.55:0.57:0.56:0.61"]=87, ["0.55:0.57:0.51:0.57"]=56, ["0.55:0.57:0.62:0.31"]=263, ["0.55:0.57:0.62:0.31:0.67:0.30"]=352, ["0.55:0.57:0.62:0.31:0.67:0.30:0.70:0.16"]=491,
            ["0.55:0.57:0.62:0.31:0.49:0.27"]=379, ["0.55:0.57:0.44:0.19"]=497, ["0.55:0.57:0.62:0.31:0.49:0.27:0.38:0.24"]=477, ["0.55:0.57:0.44:0.19:0.49:0.27"]=565, ["0.55:0.57:0.44:0.19:0.70:0.16"]=686, ["0.55:0.57:0.44:0.19:0.38:0.24"]=532,
            ["0.55:0.57:0.44:0.19:0.67:0.30"]=706, ["0.55:0.57:0.67:0.63"]=128, ["0.70:0.16:0.67:0.30:0.62:0.31:0.55:0.57:0.45:0.84:0.43:0.93"]=884, ["0.70:0.16:0.67:0.30:0.62:0.31:0.55:0.57:0.45:0.84"]=804, ["0.70:0.16:0.67:0.30:0.62:0.31:0.55:0.57:0.61:0.75"]=773, ["0.70:0.16:0.67:0.30:0.62:0.31:0.55:0.57:0.56:0.61"]=578,
            ["0.70:0.16:0.67:0.30:0.62:0.31:0.55:0.57"]=492, ["0.70:0.16:0.67:0.30:0.62:0.31:0.55:0.57:0.51:0.57"]=547, ["0.70:0.16:0.67:0.30:0.62:0.31"]=234, ["0.70:0.16:0.67:0.30"]=141, ["0.70:0.16:0.67:0.30:0.49:0.27"]=301, ["0.70:0.16:0.44:0.19"]=262,
            ["0.70:0.16:0.44:0.19:0.38:0.24"]=294, ["0.70:0.16:0.44:0.19:0.55:0.57:0.45:0.84"]=985, ["0.70:0.16:0.44:0.19:0.49:0.27:0.62:0.31"]=443, ["0.70:0.16:0.44:0.19:0.55:0.57"]=673, ["0.70:0.16:0.44:0.19:0.49:0.27"]=327, ["0.70:0.16:0.44:0.19:0.55:0.57:0.61:0.75"]=953,
            ["0.70:0.16:0.44:0.19:0.62:0.31"]=489, ["0.70:0.16:0.44:0.19:0.55:0.57:0.45:0.84:0.43:0.93"]=1065, ["0.70:0.16:0.44:0.19:0.55:0.57:0.56:0.61"]=758, ["0.70:0.16:0.44:0.19:0.55:0.57:0.51:0.57"]=729, ["0.70:0.16:0.67:0.30:0.62:0.31:0.55:0.57:0.43:0.93"]=908, ["0.67:0.30:0.62:0.31:0.55:0.57:0.45:0.84:0.43:0.93"]=743,
            ["0.67:0.30:0.62:0.31:0.55:0.57:0.45:0.84"]=663, ["0.67:0.30:0.62:0.31:0.55:0.57:0.61:0.75"]=631, ["0.67:0.30:0.62:0.31:0.55:0.57:0.56:0.61"]=437, ["0.67:0.30:0.62:0.31:0.55:0.57"]=351, ["0.67:0.30:0.62:0.31:0.55:0.57:0.51:0.57"]=407, ["0.67:0.30:0.62:0.31"]=93,
            ["0.67:0.30:0.70:0.16"]=139, ["0.67:0.30:0.49:0.27"]=159, ["0.67:0.30:0.44:0.19"]=284, ["0.67:0.30:0.49:0.27:0.38:0.24"]=257, ["0.67:0.30:0.44:0.19:0.55:0.57"]=697, ["0.67:0.30:0.62:0.31:0.55:0.57:0.43:0.93"]=768,
            ["0.67:0.30:0.44:0.19:0.55:0.57:0.51:0.57"]=752, ["0.67:0.30:0.44:0.19:0.55:0.57:0.61:0.75"]=977, ["0.67:0.30:0.62:0.31:0.67:0.63"]=418, ["0.67:0.30:0.62:0.31:0.67:0.63:0.61:0.75"]=572, ["0.61:0.75:0.43:0.93"]=260, ["0.61:0.75:0.45:0.84"]=189,
            ["0.61:0.75:0.56:0.61"]=197, ["0.61:0.75:0.55:0.57"]=285, ["0.61:0.75:0.56:0.61:0.51:0.57"]=267, ["0.61:0.75:0.55:0.57:0.62:0.31"]=547, ["0.61:0.75:0.55:0.57:0.62:0.31:0.67:0.30"]=636, ["0.61:0.75:0.55:0.57:0.62:0.31:0.67:0.30:0.70:0.16"]=774,
            ["0.61:0.75:0.55:0.57:0.62:0.31:0.49:0.27"]=663, ["0.61:0.75:0.55:0.57:0.44:0.19"]=782, ["0.61:0.75:0.55:0.57:0.62:0.31:0.49:0.27:0.38:0.24"]=761, ["0.61:0.75:0.55:0.57:0.51:0.57"]=341, ["0.61:0.75:0.55:0.57:0.44:0.19:0.38:0.24"]=817, ["0.61:0.75:0.55:0.57:0.44:0.19:0.49:0.27"]=849,
            ["0.61:0.75:0.55:0.57:0.44:0.19:0.70:0.16"]=970, ["0.61:0.75:0.67:0.63"]=170, ["0.61:0.75:0.67:0.63:0.62:0.31:0.49:0.27:0.44:0.19"]=752, ["0.61:0.75:0.67:0.63:0.62:0.31"]=498, ["0.61:0.75:0.67:0.63:0.62:0.31:0.49:0.27"]=614, ["0.61:0.75:0.67:0.63:0.62:0.31:0.67:0.30"]=587,
            ["0.49:0.27:0.62:0.31:0.55:0.57:0.45:0.84:0.43:0.93"]=768, ["0.49:0.27:0.62:0.31:0.55:0.57:0.45:0.84"]=688, ["0.49:0.27:0.62:0.31:0.55:0.57:0.61:0.75"]=656, ["0.49:0.27:0.62:0.31:0.55:0.57:0.56:0.61"]=462, ["0.49:0.27:0.62:0.31:0.55:0.57"]=376, ["0.49:0.27:0.62:0.31:0.55:0.57:0.51:0.57"]=431,
            ["0.49:0.27:0.62:0.31"]=118, ["0.49:0.27:0.67:0.30"]=195, ["0.49:0.27:0.67:0.30:0.70:0.16"]=329, ["0.49:0.27:0.44:0.19"]=139, ["0.49:0.27:0.38:0.24"]=75, ["0.49:0.27:0.62:0.31:0.55:0.57:0.43:0.93"]=792,
            ["0.49:0.27:0.44:0.19:0.70:0.16"]=325, ["0.49:0.27:0.44:0.19:0.55:0.57:0.45:0.84"]=862, ["0.49:0.27:0.44:0.19:0.55:0.57:0.43:0.93"]=966, ["0.49:0.27:0.44:0.19:0.55:0.57:0.61:0.75"]=830, ["0.49:0.27:0.44:0.19:0.55:0.57"]=404, ["0.49:0.27:0.44:0.19:0.55:0.57:0.45:0.84:0.43:0.93"]=942,
            ["0.49:0.27:0.62:0.31:0.67:0.63:0.61:0.75:0.43:0.93"]=857, ["0.49:0.27:0.62:0.31:0.67:0.63"]=443, ["0.49:0.27:0.62:0.31:0.67:0.63:0.61:0.75"]=598, ["0.38:0.24:0.49:0.27:0.62:0.31:0.55:0.57:0.45:0.84:0.43:0.93"]=863, ["0.38:0.24:0.49:0.27:0.62:0.31:0.55:0.57:0.45:0.84"]=782, ["0.38:0.24:0.49:0.27:0.62:0.31:0.55:0.57:0.61:0.75"]=751,
            ["0.38:0.24:0.49:0.27:0.62:0.31:0.55:0.57:0.56:0.61"]=556, ["0.38:0.24:0.49:0.27:0.62:0.31:0.55:0.57"]=471, ["0.38:0.24:0.49:0.27:0.62:0.31:0.55:0.57:0.51:0.57"]=526, ["0.38:0.24:0.49:0.27:0.62:0.31"]=145, ["0.38:0.24:0.49:0.27:0.67:0.30"]=289, ["0.38:0.24:0.44:0.19:0.70:0.16"]=299,
            ["0.38:0.24:0.49:0.27"]=74, ["0.38:0.24:0.44:0.19"]=112, ["0.38:0.24:0.44:0.19:0.55:0.57"]=526, ["0.38:0.24:0.44:0.19:0.55:0.57:0.45:0.84:0.43:0.93"]=917, ["0.38:0.24:0.44:0.19:0.62:0.31"]=338, ["0.51:0.57:0.55:0.57:0.45:0.84:0.43:0.93"]=462,
            ["0.51:0.57:0.55:0.57:0.45:0.84"]=382, ["0.51:0.57:0.56:0.61:0.61:0.75"]=286, ["0.51:0.57:0.56:0.61"]=77, ["0.51:0.57:0.55:0.57"]=70, ["0.51:0.57:0.55:0.57:0.62:0.31"]=331, ["0.51:0.57:0.55:0.57:0.62:0.31:0.67:0.30"]=420,
            ["0.51:0.57:0.55:0.57:0.62:0.31:0.67:0.30:0.70:0.16"]=559, ["0.51:0.57:0.55:0.57:0.62:0.31:0.49:0.27"]=447, ["0.51:0.57:0.55:0.57:0.44:0.19"]=566, ["0.51:0.57:0.55:0.57:0.62:0.31:0.49:0.27:0.38:0.24"]=545, ["0.51:0.57:0.55:0.57:0.61:0.75"]=351, ["0.51:0.57:0.55:0.57:0.44:0.19:0.70:0.16"]=755,
            ["0.51:0.57:0.55:0.57:0.44:0.19:0.49:0.27"]=633, ["0.51:0.57:0.55:0.57:0.44:0.19:0.67:0.30"]=775, ["0.51:0.57:0.55:0.57:0.43:0.93"]=486, ["0.51:0.57:0.56:0.61:0.61:0.75:0.45:0.84"]=474, ["0.51:0.57:0.55:0.57:0.67:0.63"]=196, ["0.44:0.19:0.55:0.57:0.45:0.84:0.43:0.93"]=572,
            ["0.44:0.19:0.55:0.57:0.45:0.84"]=524, ["0.44:0.19:0.55:0.57:0.61:0.75"]=505, ["0.44:0.19:0.55:0.57:0.56:0.61"]=393, ["0.44:0.19:0.55:0.57"]=342, ["0.44:0.19:0.55:0.57:0.51:0.57"]=543, ["0.44:0.19:0.62:0.31"]=301,
            ["0.44:0.19:0.67:0.30"]=284, ["0.44:0.19:0.70:0.16"]=261, ["0.44:0.19:0.49:0.27"]=141, ["0.44:0.19:0.38:0.24"]=106, ["0.44:0.19:0.55:0.57:0.43:0.93"]=586, ["0.44:0.19:0.49:0.27:0.62:0.31:0.67:0.63"]=583,
            ["0.44:0.19:0.49:0.27:0.62:0.31:0.67:0.63:0.61:0.75"]=737, ["0.67:0.63:0.61:0.75:0.45:0.84"]=343, ["0.67:0.63:0.55:0.57:0.45:0.84"]=432, ["0.67:0.63:0.62:0.31"]=328, ["0.67:0.63:0.55:0.57"]=121, ["0.67:0.63:0.61:0.75:0.43:0.93"]=414,
            ["0.67:0.63:0.62:0.31:0.49:0.27:0.44:0.19"]=583, ["0.67:0.63:0.61:0.75"]=154, ["0.67:0.63:0.55:0.57:0.45:0.84:0.43:0.93"]=512, ["0.67:0.63:0.62:0.31:0.49:0.27"]=444, ["0.67:0.63:0.62:0.31:0.67:0.30"]=418, ["0.67:0.63:0.55:0.57:0.44:0.19"]=617,
            ["0.67:0.63:0.62:0.31:0.49:0.27:0.38:0.24"]=518,
        },
        [1414] = {
            ["0.57:0.64:0.61:0.80"]=222, ["0.57:0.64:0.61:0.80:0.55:0.73"]=309, ["0.57:0.64:0.61:0.80:0.50:0.76"]=329, ["0.57:0.64:0.56:0.53:0.44:0.69"]=414, ["0.57:0.64:0.61:0.80:0.50:0.76:0.42:0.79"]=430, ["0.57:0.64:0.56:0.53:0.53:0.61"]=252,
            ["0.57:0.64:0.56:0.53:0.61:0.55"]=214, ["0.57:0.64:0.56:0.53"]=162, ["0.57:0.64:0.63:0.44"]=217, ["0.57:0.64:0.63:0.44:0.63:0.36"]=316, ["0.57:0.64:0.63:0.44:0.55:0.42"]=306, ["0.57:0.64:0.63:0.44:0.63:0.36:0.64:0.23"]=445,
            ["0.57:0.64:0.56:0.53:0.46:0.30:0.54:0.21"]=536, ["0.57:0.64:0.56:0.53:0.46:0.30"]=415, ["0.57:0.64:0.56:0.53:0.41:0.37"]=392, ["0.57:0.64:0.56:0.53:0.41:0.47"]=311, ["0.57:0.64:0.45:0.56"]=224, ["0.57:0.64:0.45:0.56:0.32:0.58"]=383,
            ["0.57:0.64:0.56:0.53:0.55:0.73"]=347, ["0.57:0.64:0.63:0.44:0.64:0.23"]=537, ["0.57:0.64:0.45:0.56:0.53:0.61"]=312, ["0.57:0.64:0.56:0.53:0.41:0.47:0.32:0.58"]=454, ["0.46:0.30:0.56:0.53:0.55:0.73:0.61:0.80"]=518, ["0.46:0.30:0.56:0.53:0.55:0.73"]=426,
            ["0.46:0.30:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=625, ["0.46:0.30:0.56:0.53:0.44:0.69:0.42:0.79"]=623, ["0.46:0.30:0.56:0.53:0.44:0.69"]=493, ["0.46:0.30:0.56:0.53:0.57:0.64"]=404, ["0.46:0.30:0.56:0.53:0.53:0.61"]=331, ["0.46:0.30:0.56:0.53:0.61:0.55"]=292,
            ["0.46:0.30:0.56:0.53"]=241, ["0.46:0.30:0.63:0.44"]=259, ["0.46:0.30:0.63:0.36:0.55:0.42"]=333, ["0.46:0.30:0.63:0.36"]=241, ["0.46:0.30:0.64:0.23"]=190, ["0.46:0.30:0.54:0.21"]=166,
            ["0.46:0.30:0.56:0.53:0.41:0.37"]=471, ["0.46:0.30:0.56:0.53:0.41:0.47"]=390, ["0.46:0.30:0.56:0.53:0.45:0.56"]=423, ["0.46:0.30:0.56:0.53:0.41:0.47:0.32:0.58"]=533, ["0.46:0.30:0.63:0.44:0.55:0.42"]=348, ["0.46:0.30:0.56:0.53:0.61:0.80"]=545,
            ["0.44:0.69:0.61:0.80"]=201, ["0.44:0.69:0.55:0.73"]=107, ["0.44:0.69:0.42:0.79:0.50:0.76"]=222, ["0.44:0.69:0.42:0.79"]=130, ["0.44:0.69:0.55:0.73:0.61:0.80:0.57:0.64"]=421, ["0.44:0.69:0.55:0.73:0.53:0.61"]=244,
            ["0.44:0.69:0.56:0.53:0.61:0.55"]=315, ["0.44:0.69:0.56:0.53"]=263, ["0.44:0.69:0.56:0.53:0.63:0.44"]=406, ["0.44:0.69:0.56:0.53:0.55:0.42"]=426, ["0.44:0.69:0.56:0.53:0.63:0.36"]=432, ["0.44:0.69:0.56:0.53:0.63:0.36:0.64:0.23"]=562,
            ["0.44:0.69:0.56:0.53:0.46:0.30:0.54:0.21"]=639, ["0.44:0.69:0.56:0.53:0.46:0.30"]=517, ["0.44:0.69:0.56:0.53:0.41:0.37"]=494, ["0.44:0.69:0.32:0.58:0.41:0.47"]=400, ["0.44:0.69:0.45:0.56"]=259, ["0.44:0.69:0.32:0.58"]=201,
            ["0.44:0.69:0.56:0.53:0.57:0.64"]=427, ["0.44:0.69:0.56:0.53:0.41:0.47"]=414, ["0.44:0.69:0.55:0.73:0.61:0.80:0.50:0.76"]=307, ["0.44:0.69:0.56:0.53:0.46:0.30:0.64:0.23"]=661, ["0.44:0.69:0.45:0.56:0.53:0.61"]=346, ["0.44:0.69:0.56:0.53:0.63:0.44:0.64:0.23"]=725,
            ["0.53:0.61:0.55:0.73:0.61:0.80"]=218, ["0.53:0.61:0.55:0.73"]=125, ["0.53:0.61:0.55:0.73:0.61:0.80:0.50:0.76"]=325, ["0.53:0.61:0.55:0.73:0.44:0.69:0.42:0.79"]=378, ["0.53:0.61:0.55:0.73:0.44:0.69"]=248, ["0.53:0.61:0.56:0.53:0.57:0.64"]=242,
            ["0.53:0.61:0.56:0.53:0.61:0.55"]=130, ["0.53:0.61:0.56:0.53"]=79, ["0.53:0.61:0.56:0.53:0.63:0.44"]=221, ["0.53:0.61:0.56:0.53:0.55:0.42"]=242, ["0.53:0.61:0.56:0.53:0.63:0.36"]=248, ["0.53:0.61:0.56:0.53:0.63:0.36:0.64:0.23"]=377,
            ["0.53:0.61:0.56:0.53:0.46:0.30:0.54:0.21"]=454, ["0.53:0.61:0.56:0.53:0.46:0.30"]=333, ["0.53:0.61:0.56:0.53:0.41:0.37"]=310, ["0.53:0.61:0.56:0.53:0.41:0.47"]=229, ["0.53:0.61:0.45:0.56"]=114, ["0.53:0.61:0.45:0.56:0.32:0.58"]=273,
            ["0.53:0.61:0.45:0.56:0.63:0.44"]=321, ["0.53:0.61:0.56:0.53:0.41:0.47:0.32:0.58"]=372, ["0.53:0.61:0.56:0.53:0.44:0.69"]=332, ["0.53:0.61:0.56:0.53:0.63:0.44:0.64:0.23"]=542, ["0.53:0.61:0.56:0.53:0.46:0.30:0.64:0.23"]=476, ["0.53:0.61:0.56:0.53:0.61:0.80"]=383,
            ["0.42:0.79:0.61:0.80"]=241, ["0.42:0.79:0.44:0.69:0.55:0.73"]=236, ["0.42:0.79:0.50:0.76"]=97, ["0.42:0.79:0.44:0.69"]=129, ["0.42:0.79:0.50:0.76:0.61:0.80:0.57:0.64"]=425, ["0.42:0.79:0.44:0.69:0.55:0.73:0.53:0.61"]=373,
            ["0.42:0.79:0.44:0.69:0.45:0.56"]=389, ["0.42:0.79:0.44:0.69:0.56:0.53:0.61:0.55"]=445, ["0.42:0.79:0.44:0.69:0.56:0.53"]=394, ["0.42:0.79:0.44:0.69:0.56:0.53:0.63:0.44"]=535, ["0.42:0.79:0.44:0.69:0.56:0.53:0.55:0.42"]=556, ["0.42:0.79:0.44:0.69:0.56:0.53:0.63:0.36"]=562,
            ["0.42:0.79:0.44:0.69:0.56:0.53:0.63:0.36:0.64:0.23"]=691, ["0.42:0.79:0.44:0.69:0.56:0.53:0.46:0.30:0.54:0.21"]=768, ["0.42:0.79:0.44:0.69:0.56:0.53:0.46:0.30"]=647, ["0.42:0.79:0.44:0.69:0.56:0.53:0.41:0.37"]=625, ["0.42:0.79:0.44:0.69:0.32:0.58:0.41:0.47"]=529, ["0.42:0.79:0.44:0.69:0.32:0.58"]=330,
            ["0.42:0.79:0.50:0.76:0.61:0.80:0.63:0.44"]=555, ["0.42:0.79:0.61:0.80:0.63:0.44"]=591, ["0.42:0.79:0.50:0.76:0.61:0.80:0.55:0.73"]=292, ["0.42:0.79:0.61:0.80:0.55:0.73"]=328, ["0.42:0.79:0.44:0.69:0.56:0.53:0.41:0.47"]=544, ["0.42:0.79:0.50:0.76:0.61:0.80:0.45:0.56"]=509,
            ["0.42:0.79:0.61:0.80:0.57:0.64"]=463, ["0.42:0.79:0.44:0.69:0.56:0.53:0.46:0.30:0.64:0.23"]=790, ["0.42:0.79:0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53:0.63:0.36:0.64:0.23"]=782, ["0.42:0.79:0.61:0.80:0.55:0.73:0.56:0.53:0.61:0.55"]=572, ["0.42:0.79:0.61:0.80:0.45:0.56"]=545, ["0.42:0.79:0.50:0.76:0.61:0.80:0.45:0.56:0.53:0.61"]=595,
            ["0.42:0.79:0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53:0.61:0.55"]=536, ["0.56:0.53:0.61:0.80"]=303, ["0.56:0.53:0.55:0.73"]=184, ["0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=384, ["0.56:0.53:0.44:0.69:0.42:0.79"]=382, ["0.56:0.53:0.44:0.69"]=252,
            ["0.56:0.53:0.57:0.64"]=162, ["0.56:0.53:0.53:0.61"]=90, ["0.56:0.53:0.61:0.55"]=52, ["0.56:0.53:0.63:0.44"]=142, ["0.56:0.53:0.55:0.42"]=162, ["0.56:0.53:0.63:0.36"]=168,
            ["0.56:0.53:0.63:0.36:0.64:0.23"]=297, ["0.56:0.53:0.46:0.30:0.54:0.21"]=375, ["0.56:0.53:0.46:0.30"]=253, ["0.56:0.53:0.41:0.37"]=231, ["0.56:0.53:0.41:0.47"]=150, ["0.56:0.53:0.45:0.56"]=182,
            ["0.56:0.53:0.41:0.47:0.32:0.58"]=292, ["0.56:0.53:0.45:0.56:0.32:0.58"]=342, ["0.56:0.53:0.46:0.30:0.64:0.23"]=397, ["0.64:0.23:0.63:0.36:0.56:0.53:0.55:0.73:0.61:0.80"]=584, ["0.64:0.23:0.63:0.36:0.56:0.53:0.55:0.73"]=492, ["0.64:0.23:0.63:0.36:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=691,
            ["0.64:0.23:0.63:0.36:0.56:0.53:0.44:0.69:0.42:0.79"]=688, ["0.64:0.23:0.63:0.36:0.56:0.53:0.44:0.69"]=558, ["0.64:0.23:0.63:0.36:0.56:0.53:0.57:0.64"]=470, ["0.64:0.23:0.63:0.36:0.56:0.53:0.53:0.61"]=397, ["0.64:0.23:0.63:0.36:0.56:0.53:0.61:0.55"]=357, ["0.64:0.23:0.63:0.36:0.56:0.53"]=307,
            ["0.64:0.23:0.63:0.44"]=304, ["0.64:0.23:0.63:0.36"]=135, ["0.64:0.23:0.63:0.36:0.55:0.42"]=228, ["0.64:0.23:0.54:0.21"]=134, ["0.64:0.23:0.46:0.30"]=195, ["0.64:0.23:0.63:0.36:0.55:0.42:0.41:0.37"]=388,
            ["0.64:0.23:0.63:0.36:0.56:0.53:0.41:0.47"]=456, ["0.64:0.23:0.63:0.36:0.45:0.56"]=392, ["0.64:0.23:0.63:0.36:0.45:0.56:0.32:0.58"]=550, ["0.64:0.23:0.63:0.44:0.55:0.42"]=393, ["0.64:0.23:0.63:0.44:0.56:0.53:0.61:0.55"]=466, ["0.64:0.23:0.63:0.44:0.56:0.53:0.44:0.69"]=666,
            ["0.64:0.23:0.63:0.44:0.55:0.42:0.41:0.37"]=553, ["0.64:0.23:0.63:0.44:0.56:0.53:0.55:0.73:0.61:0.80"]=691, ["0.64:0.23:0.63:0.44:0.45:0.56"]=529, ["0.64:0.23:0.63:0.44:0.56:0.53:0.61:0.80"]=717, ["0.64:0.23:0.63:0.36:0.56:0.53:0.61:0.80"]=611, ["0.64:0.23:0.63:0.44:0.56:0.53:0.55:0.73"]=599,
            ["0.64:0.23:0.63:0.44:0.45:0.56:0.32:0.58"]=689, ["0.64:0.23:0.63:0.44:0.56:0.53:0.53:0.61"]=504, ["0.64:0.23:0.63:0.44:0.57:0.64"]=533, ["0.64:0.23:0.63:0.44:0.56:0.53:0.41:0.47"]=564, ["0.64:0.23:0.63:0.44:0.56:0.53"]=414, ["0.64:0.23:0.63:0.44:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=799,
            ["0.64:0.23:0.63:0.44:0.56:0.53:0.44:0.69:0.42:0.79"]=796, ["0.55:0.73:0.61:0.80"]=93, ["0.55:0.73:0.61:0.80:0.50:0.76"]=200, ["0.55:0.73:0.44:0.69:0.42:0.79"]=252, ["0.55:0.73:0.44:0.69"]=124, ["0.55:0.73:0.61:0.80:0.57:0.64"]=315,
            ["0.55:0.73:0.53:0.61"]=137, ["0.55:0.73:0.56:0.53:0.61:0.55"]=245, ["0.55:0.73:0.56:0.53"]=194, ["0.55:0.73:0.56:0.53:0.63:0.44"]=335, ["0.55:0.73:0.56:0.53:0.55:0.42"]=356, ["0.55:0.73:0.56:0.53:0.63:0.36"]=362,
            ["0.55:0.73:0.56:0.53:0.63:0.36:0.64:0.23"]=491, ["0.55:0.73:0.56:0.53:0.46:0.30:0.54:0.21"]=569, ["0.55:0.73:0.56:0.53:0.46:0.30"]=448, ["0.55:0.73:0.56:0.53:0.41:0.37"]=424, ["0.55:0.73:0.56:0.53:0.41:0.47"]=343, ["0.55:0.73:0.45:0.56"]=225,
            ["0.55:0.73:0.44:0.69:0.32:0.58"]=323, ["0.55:0.73:0.56:0.53:0.57:0.64"]=357, ["0.55:0.73:0.45:0.56:0.32:0.58"]=385, ["0.55:0.73:0.56:0.53:0.41:0.47:0.32:0.58"]=486, ["0.61:0.80:0.42:0.79"]=233, ["0.61:0.80:0.50:0.76"]=108,
            ["0.61:0.80:0.55:0.73"]=87, ["0.61:0.80:0.44:0.69"]=200, ["0.61:0.80:0.57:0.64"]=222, ["0.61:0.80:0.55:0.73:0.53:0.61"]=223, ["0.61:0.80:0.55:0.73:0.56:0.53:0.61:0.55"]=331, ["0.61:0.80:0.56:0.53"]=301,
            ["0.61:0.80:0.63:0.44"]=350, ["0.61:0.80:0.63:0.44:0.55:0.42"]=439, ["0.61:0.80:0.55:0.73:0.56:0.53:0.63:0.36"]=448, ["0.61:0.80:0.55:0.73:0.56:0.53:0.63:0.36:0.64:0.23"]=577, ["0.61:0.80:0.55:0.73:0.56:0.53:0.46:0.30:0.54:0.21"]=653, ["0.61:0.80:0.55:0.73:0.56:0.53:0.46:0.30"]=532,
            ["0.61:0.80:0.55:0.73:0.56:0.53:0.41:0.37"]=510, ["0.61:0.80:0.55:0.73:0.56:0.53:0.41:0.47"]=429, ["0.61:0.80:0.45:0.56"]=304, ["0.61:0.80:0.44:0.69:0.32:0.58"]=400, ["0.61:0.80:0.45:0.56:0.32:0.58"]=463, ["0.61:0.80:0.45:0.56:0.53:0.61"]=392,
            ["0.61:0.80:0.63:0.44:0.64:0.23"]=670, ["0.61:0.80:0.56:0.53:0.41:0.37"]=531, ["0.61:0.80:0.55:0.73:0.56:0.53:0.41:0.47:0.32:0.58"]=572, ["0.61:0.80:0.56:0.53:0.61:0.55"]=352, ["0.61:0.80:0.63:0.44:0.64:0.23:0.54:0.21"]=804, ["0.61:0.80:0.56:0.53:0.53:0.61"]=391,
            ["0.61:0.80:0.63:0.44:0.64:0.23:0.57:0.33"]=751, ["0.61:0.80:0.56:0.53:0.41:0.47"]=450, ["0.61:0.80:0.55:0.73:0.56:0.53:0.55:0.42"]=442, ["0.50:0.76:0.61:0.80"]=113, ["0.50:0.76:0.61:0.80:0.55:0.73"]=200, ["0.50:0.76:0.42:0.79:0.44:0.69"]=224,
            ["0.50:0.76:0.42:0.79"]=100, ["0.50:0.76:0.61:0.80:0.57:0.64"]=333, ["0.50:0.76:0.61:0.80:0.55:0.73:0.53:0.61"]=336, ["0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53:0.61:0.55"]=443, ["0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53"]=392, ["0.50:0.76:0.61:0.80:0.63:0.44"]=462,
            ["0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53:0.63:0.36"]=559, ["0.50:0.76:0.61:0.80:0.63:0.44:0.55:0.42"]=551, ["0.50:0.76:0.61:0.80:0.45:0.56"]=416, ["0.50:0.76:0.42:0.79:0.44:0.69:0.32:0.58"]=424, ["0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53:0.41:0.47"]=542, ["0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53:0.41:0.37"]=623,
            ["0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53:0.46:0.30"]=645, ["0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53:0.46:0.30:0.54:0.21"]=766, ["0.50:0.76:0.61:0.80:0.55:0.73:0.56:0.53:0.63:0.36:0.64:0.23"]=689, ["0.50:0.76:0.61:0.80:0.44:0.69"]=312, ["0.50:0.76:0.60:0.81:0.64:0.67:0.61:0.40:0.53:0.26"]=774, ["0.50:0.76:0.61:0.80:0.44:0.69:0.32:0.58"]=513,
            ["0.50:0.76:0.61:0.80:0.45:0.56:0.32:0.58"]=576, ["0.50:0.76:0.61:0.80:0.63:0.44:0.64:0.23"]=782, ["0.50:0.76:0.61:0.80:0.56:0.53:0.46:0.30"]=666, ["0.54:0.21:0.46:0.30:0.56:0.53:0.55:0.73:0.61:0.80"]=629, ["0.54:0.21:0.46:0.30:0.56:0.53:0.55:0.73"]=537, ["0.54:0.21:0.46:0.30:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=736,
            ["0.54:0.21:0.46:0.30:0.56:0.53:0.44:0.69:0.42:0.79"]=734, ["0.54:0.21:0.46:0.30:0.56:0.53:0.44:0.69"]=604, ["0.54:0.21:0.46:0.30:0.56:0.53:0.57:0.64"]=515, ["0.54:0.21:0.46:0.30:0.56:0.53:0.53:0.61"]=443, ["0.54:0.21:0.46:0.30:0.56:0.53:0.61:0.55"]=404, ["0.54:0.21:0.46:0.30:0.56:0.53"]=353,
            ["0.54:0.21:0.64:0.23:0.63:0.36:0.63:0.44"]=396, ["0.54:0.21:0.64:0.23:0.63:0.36:0.55:0.42"]=369, ["0.54:0.21:0.64:0.23:0.63:0.36"]=275, ["0.54:0.21:0.64:0.23"]=142, ["0.54:0.21:0.46:0.30"]=157, ["0.54:0.21:0.64:0.23:0.63:0.36:0.55:0.42:0.41:0.37"]=528,
            ["0.54:0.21:0.46:0.30:0.56:0.53:0.41:0.47"]=502, ["0.54:0.21:0.64:0.23:0.63:0.36:0.45:0.56"]=532, ["0.54:0.21:0.46:0.30:0.56:0.53:0.41:0.47:0.32:0.58"]=645, ["0.54:0.21:0.46:0.30:0.63:0.44"]=371, ["0.54:0.21:0.46:0.30:0.63:0.36"]=346, ["0.54:0.21:0.46:0.30:0.56:0.53:0.45:0.56"]=535,
            ["0.54:0.21:0.46:0.30:0.63:0.44:0.55:0.42"]=460, ["0.54:0.21:0.46:0.30:0.56:0.53:0.41:0.37"]=583, ["0.54:0.21:0.46:0.30:0.63:0.36:0.55:0.42"]=438, ["0.54:0.21:0.64:0.23:0.63:0.44"]=446, ["0.54:0.21:0.64:0.23:0.63:0.44:0.57:0.64"]=674, ["0.54:0.21:0.64:0.23:0.63:0.44:0.56:0.53:0.61:0.55"]=607,
            ["0.54:0.21:0.64:0.23:0.63:0.36:0.56:0.53:0.61:0.55"]=499, ["0.54:0.21:0.64:0.23:0.63:0.44:0.55:0.42"]=535, ["0.54:0.21:0.64:0.23:0.63:0.44:0.56:0.53:0.41:0.47"]=705, ["0.54:0.21:0.64:0.23:0.63:0.36:0.56:0.53:0.55:0.73"]=632, ["0.54:0.21:0.64:0.23:0.63:0.36:0.45:0.56:0.32:0.58"]=692, ["0.54:0.21:0.46:0.30:0.56:0.53:0.61:0.80"]=656,
            ["0.54:0.21:0.64:0.23:0.63:0.36:0.56:0.53:0.55:0.73:0.61:0.80"]=725, ["0.54:0.21:0.64:0.23:0.63:0.36:0.56:0.53:0.44:0.69"]=699, ["0.54:0.21:0.64:0.23:0.63:0.36:0.56:0.53:0.44:0.69:0.42:0.79"]=829, ["0.54:0.21:0.64:0.23:0.63:0.36:0.56:0.53"]=448, ["0.54:0.21:0.64:0.23:0.63:0.44:0.56:0.53:0.53:0.61"]=646, ["0.54:0.21:0.64:0.23:0.63:0.44:0.45:0.56"]=671,
            ["0.54:0.21:0.64:0.23:0.63:0.36:0.56:0.53:0.53:0.61"]=538, ["0.54:0.21:0.64:0.23:0.63:0.44:0.56:0.53"]=555, ["0.54:0.21:0.64:0.23:0.63:0.44:0.55:0.42:0.41:0.37"]=695, ["0.54:0.21:0.64:0.23:0.63:0.44:0.56:0.53:0.44:0.69:0.42:0.79"]=937, ["0.63:0.44:0.61:0.80"]=417, ["0.63:0.44:0.56:0.53:0.55:0.73"]=294,
            ["0.63:0.44:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=494, ["0.63:0.44:0.56:0.53:0.44:0.69:0.42:0.79"]=492, ["0.63:0.44:0.56:0.53:0.44:0.69"]=361, ["0.63:0.44:0.57:0.64"]=229, ["0.63:0.44:0.56:0.53:0.53:0.61"]=200, ["0.63:0.44:0.56:0.53:0.61:0.55"]=161,
            ["0.63:0.44:0.56:0.53"]=110, ["0.63:0.44:0.63:0.36"]=99, ["0.63:0.44:0.55:0.42"]=89, ["0.63:0.44:0.64:0.23"]=319, ["0.63:0.44:0.63:0.36:0.64:0.23:0.54:0.21"]=361, ["0.63:0.44:0.46:0.30"]=252,
            ["0.63:0.44:0.55:0.42:0.41:0.37"]=250, ["0.63:0.44:0.56:0.53:0.41:0.47"]=260, ["0.63:0.44:0.45:0.56"]=224, ["0.63:0.44:0.45:0.56:0.32:0.58"]=385, ["0.63:0.44:0.46:0.30:0.54:0.21"]=373, ["0.63:0.44:0.56:0.53:0.41:0.37"]=341,
            ["0.63:0.44:0.56:0.53:0.61:0.80:0.50:0.76"]=521, ["0.63:0.44:0.45:0.56:0.53:0.61"]=312, ["0.63:0.44:0.56:0.53:0.41:0.47:0.32:0.58"]=403, ["0.63:0.44:0.45:0.56:0.44:0.69"]=478, ["0.63:0.44:0.56:0.53:0.44:0.69:0.32:0.58"]=563, ["0.63:0.44:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76:0.42:0.79"]=594,
            ["0.63:0.44:0.45:0.56:0.44:0.69:0.42:0.79"]=607, ["0.63:0.44:0.64:0.23:0.54:0.21"]=454, ["0.63:0.44:0.56:0.53:0.55:0.73:0.61:0.80:0.42:0.79"]=620, ["0.63:0.44:0.45:0.56:0.55:0.73"]=429, ["0.63:0.44:0.56:0.53:0.61:0.80:0.42:0.79"]=646, ["0.63:0.44:0.56:0.53:0.61:0.80:0.50:0.76:0.42:0.79"]=621,
            ["0.61:0.55:0.56:0.53:0.55:0.73:0.61:0.80"]=345, ["0.61:0.55:0.56:0.53:0.55:0.73"]=252, ["0.61:0.55:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=452, ["0.61:0.55:0.56:0.53:0.44:0.69:0.42:0.79"]=450, ["0.61:0.55:0.56:0.53:0.44:0.69"]=320, ["0.61:0.55:0.56:0.53:0.57:0.64"]=231,
            ["0.61:0.55:0.56:0.53:0.53:0.61"]=158, ["0.61:0.55:0.56:0.53"]=69, ["0.61:0.55:0.56:0.53:0.63:0.44"]=210, ["0.61:0.55:0.56:0.53:0.55:0.42"]=231, ["0.61:0.55:0.56:0.53:0.63:0.36"]=236, ["0.61:0.55:0.56:0.53:0.63:0.36:0.64:0.23"]=366,
            ["0.61:0.55:0.56:0.53:0.46:0.30:0.54:0.21"]=443, ["0.61:0.55:0.56:0.53:0.46:0.30"]=322, ["0.61:0.55:0.56:0.53:0.41:0.37"]=299, ["0.61:0.55:0.56:0.53:0.41:0.47"]=218, ["0.61:0.55:0.56:0.53:0.45:0.56"]=250, ["0.61:0.55:0.56:0.53:0.41:0.47:0.32:0.58"]=360,
            ["0.61:0.55:0.56:0.53:0.61:0.80"]=372, ["0.61:0.55:0.56:0.53:0.45:0.56:0.32:0.58"]=410, ["0.61:0.55:0.56:0.53:0.46:0.30:0.64:0.23"]=465, ["0.61:0.55:0.56:0.53:0.63:0.44:0.64:0.23"]=530, ["0.61:0.55:0.56:0.53:0.55:0.73:0.61:0.80:0.42:0.79"]=578, ["0.32:0.58:0.44:0.69:0.55:0.73:0.61:0.80"]=395,
            ["0.32:0.58:0.44:0.69:0.55:0.73"]=303, ["0.32:0.58:0.44:0.69:0.42:0.79:0.50:0.76"]=417, ["0.32:0.58:0.44:0.69:0.42:0.79"]=326, ["0.32:0.58:0.44:0.69"]=196, ["0.32:0.58:0.45:0.56:0.57:0.64"]=416, ["0.32:0.58:0.45:0.56:0.53:0.61"]=265,
            ["0.32:0.58:0.45:0.56:0.56:0.53:0.61:0.55"]=388, ["0.32:0.58:0.45:0.56:0.56:0.53"]=337, ["0.32:0.58:0.45:0.56:0.63:0.44"]=385, ["0.32:0.58:0.45:0.56:0.63:0.44:0.55:0.42"]=474, ["0.32:0.58:0.45:0.56:0.63:0.36"]=447, ["0.32:0.58:0.45:0.56:0.63:0.36:0.64:0.23"]=576,
            ["0.32:0.58:0.45:0.56:0.63:0.36:0.64:0.23:0.54:0.21"]=709, ["0.32:0.58:0.45:0.56:0.56:0.53:0.46:0.30"]=590, ["0.32:0.58:0.45:0.56:0.56:0.53:0.41:0.37"]=566, ["0.32:0.58:0.41:0.47"]=199, ["0.32:0.58:0.45:0.56"]=178, ["0.32:0.58:0.45:0.56:0.55:0.73"]=382,
            ["0.32:0.58:0.44:0.69:0.55:0.73:0.61:0.80:0.50:0.76"]=503, ["0.32:0.58:0.45:0.56:0.61:0.80"]=468, ["0.32:0.58:0.45:0.56:0.63:0.44:0.64:0.23"]=705, ["0.32:0.58:0.41:0.47:0.56:0.53:0.63:0.44"]=490, ["0.32:0.58:0.41:0.47:0.56:0.53:0.53:0.61"]=439, ["0.32:0.58:0.41:0.47:0.56:0.53"]=349,
            ["0.32:0.58:0.41:0.47:0.56:0.53:0.61:0.55"]=400, ["0.32:0.58:0.45:0.56:0.56:0.53:0.46:0.30:0.54:0.21"]=711, ["0.32:0.58:0.41:0.47:0.56:0.53:0.46:0.30"]=602, ["0.32:0.58:0.44:0.69:0.56:0.53:0.61:0.55"]=511, ["0.32:0.58:0.44:0.69:0.61:0.80"]=397, ["0.32:0.58:0.41:0.47:0.56:0.53:0.57:0.64"]=511,
            ["0.32:0.58:0.41:0.47:0.56:0.53:0.55:0.42"]=511, ["0.32:0.58:0.44:0.69:0.56:0.53:0.63:0.44"]=602, ["0.32:0.58:0.45:0.56:0.53:0.61:0.55:0.73"]=389, ["0.32:0.58:0.45:0.56:0.53:0.61:0.56:0.53:0.41:0.37"]=574, ["0.32:0.58:0.45:0.56:0.53:0.61:0.56:0.53:0.61:0.55"]=395, ["0.32:0.58:0.45:0.56:0.53:0.61:0.56:0.53"]=344,
            ["0.55:0.42:0.56:0.53:0.55:0.73:0.61:0.80"]=436, ["0.55:0.42:0.56:0.53:0.55:0.73"]=345, ["0.55:0.42:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=544, ["0.55:0.42:0.56:0.53:0.44:0.69:0.42:0.79"]=541, ["0.55:0.42:0.56:0.53:0.44:0.69"]=412, ["0.55:0.42:0.56:0.53:0.57:0.64"]=323,
            ["0.55:0.42:0.56:0.53:0.53:0.61"]=250, ["0.55:0.42:0.56:0.53:0.61:0.55"]=212, ["0.55:0.42:0.56:0.53"]=160, ["0.55:0.42:0.63:0.44"]=96, ["0.55:0.42:0.63:0.36"]=96, ["0.55:0.42:0.63:0.36:0.64:0.23"]=224,
            ["0.55:0.42:0.63:0.36:0.64:0.23:0.54:0.21"]=356, ["0.55:0.42:0.63:0.36:0.46:0.30"]=327, ["0.55:0.42:0.41:0.37"]=166, ["0.55:0.42:0.56:0.53:0.41:0.47"]=310, ["0.55:0.42:0.63:0.44:0.45:0.56"]=321, ["0.55:0.42:0.56:0.53:0.41:0.47:0.32:0.58"]=453,
            ["0.55:0.42:0.63:0.44:0.46:0.30"]=348, ["0.55:0.42:0.63:0.36:0.46:0.30:0.54:0.21"]=445, ["0.55:0.42:0.63:0.44:0.64:0.23"]=416, ["0.55:0.42:0.63:0.44:0.46:0.30:0.54:0.21"]=469, ["0.55:0.42:0.63:0.44:0.45:0.56:0.32:0.58"]=480, ["0.55:0.42:0.56:0.53:0.61:0.80"]=464,
            ["0.55:0.42:0.56:0.53:0.45:0.56"]=343, ["0.41:0.47:0.56:0.53:0.55:0.73:0.61:0.80"]=426, ["0.41:0.47:0.56:0.53:0.55:0.73"]=333, ["0.41:0.47:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=534, ["0.41:0.47:0.32:0.58:0.44:0.69:0.42:0.79"]=469, ["0.41:0.47:0.32:0.58:0.44:0.69"]=339,
            ["0.41:0.47:0.56:0.53:0.57:0.64"]=312, ["0.41:0.47:0.56:0.53:0.53:0.61"]=240, ["0.41:0.47:0.56:0.53:0.61:0.55"]=200, ["0.41:0.47:0.56:0.53"]=150, ["0.41:0.47:0.56:0.53:0.63:0.44"]=290, ["0.41:0.47:0.56:0.53:0.55:0.42"]=311,
            ["0.41:0.47:0.56:0.53:0.63:0.36"]=318, ["0.41:0.47:0.56:0.53:0.63:0.36:0.64:0.23"]=447, ["0.41:0.47:0.56:0.53:0.46:0.30:0.54:0.21"]=524, ["0.41:0.47:0.56:0.53:0.46:0.30"]=403, ["0.41:0.47:0.56:0.53:0.41:0.37"]=380, ["0.41:0.47:0.32:0.58"]=143,
            ["0.41:0.47:0.45:0.56"]=175, ["0.41:0.47:0.56:0.53:0.44:0.69"]=401, ["0.41:0.47:0.45:0.56:0.63:0.44"]=382, ["0.45:0.56:0.61:0.80"]=290, ["0.45:0.56:0.55:0.73"]=219, ["0.45:0.56:0.61:0.80:0.50:0.76"]=397,
            ["0.45:0.56:0.44:0.69:0.42:0.79"]=381, ["0.45:0.56:0.44:0.69"]=252, ["0.45:0.56:0.57:0.64"]=239, ["0.45:0.56:0.53:0.61"]=87, ["0.45:0.56:0.56:0.53:0.61:0.55"]=210, ["0.45:0.56:0.56:0.53"]=159,
            ["0.45:0.56:0.63:0.44"]=207, ["0.45:0.56:0.63:0.44:0.55:0.42"]=296, ["0.45:0.56:0.63:0.36"]=269, ["0.45:0.56:0.63:0.36:0.64:0.23"]=398, ["0.45:0.56:0.63:0.36:0.64:0.23:0.54:0.21"]=532, ["0.45:0.56:0.56:0.53:0.46:0.30"]=411,
            ["0.45:0.56:0.56:0.53:0.41:0.37"]=389, ["0.45:0.56:0.41:0.47"]=182, ["0.45:0.56:0.32:0.58"]=159, ["0.45:0.56:0.56:0.53:0.46:0.30:0.54:0.21"]=534, ["0.45:0.56:0.63:0.44:0.64:0.23"]=527, ["0.45:0.56:0.61:0.80:0.50:0.76:0.42:0.79"]=498,
            ["0.45:0.56:0.56:0.53:0.55:0.42"]=321, ["0.45:0.56:0.63:0.44:0.64:0.23:0.54:0.21"]=661, ["0.45:0.56:0.61:0.80:0.42:0.79"]=522, ["0.45:0.56:0.53:0.61:0.56:0.53:0.61:0.55"]=217, ["0.45:0.56:0.53:0.61:0.56:0.53:0.41:0.37"]=396, ["0.45:0.56:0.53:0.61:0.56:0.53:0.46:0.30"]=420,
            ["0.63:0.36:0.56:0.53:0.55:0.73:0.61:0.80"]=449, ["0.63:0.36:0.56:0.53:0.55:0.73"]=357, ["0.63:0.36:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=556, ["0.63:0.36:0.56:0.53:0.44:0.69:0.42:0.79"]=553, ["0.63:0.36:0.56:0.53:0.44:0.69"]=423, ["0.63:0.36:0.56:0.53:0.57:0.64"]=335,
            ["0.63:0.36:0.56:0.53:0.53:0.61"]=263, ["0.63:0.36:0.56:0.53:0.61:0.55"]=223, ["0.63:0.36:0.56:0.53"]=172, ["0.63:0.36:0.63:0.44"]=121, ["0.63:0.36:0.55:0.42"]=94, ["0.63:0.36:0.64:0.23"]=131,
            ["0.63:0.36:0.64:0.23:0.54:0.21"]=264, ["0.63:0.36:0.46:0.30"]=232, ["0.63:0.36:0.55:0.42:0.41:0.37"]=253, ["0.63:0.36:0.56:0.53:0.41:0.47"]=322, ["0.63:0.36:0.45:0.56"]=257, ["0.63:0.36:0.45:0.56:0.32:0.58"]=416,
            ["0.63:0.36:0.46:0.30:0.54:0.21"]=350, ["0.63:0.36:0.56:0.53:0.41:0.47:0.32:0.58"]=465, ["0.63:0.36:0.56:0.53:0.61:0.80"]=476, ["0.41:0.37:0.56:0.53:0.55:0.73:0.61:0.80"]=504, ["0.41:0.37:0.56:0.53:0.55:0.73"]=412, ["0.41:0.37:0.56:0.53:0.55:0.73:0.61:0.80:0.50:0.76"]=611,
            ["0.41:0.37:0.56:0.53:0.44:0.69:0.42:0.79"]=610, ["0.41:0.37:0.56:0.53:0.44:0.69"]=480, ["0.41:0.37:0.56:0.53:0.57:0.64"]=391, ["0.41:0.37:0.56:0.53:0.53:0.61"]=318, ["0.41:0.37:0.56:0.53:0.61:0.55"]=279, ["0.41:0.37:0.56:0.53"]=228,
            ["0.41:0.37:0.55:0.42:0.63:0.44"]=256, ["0.41:0.37:0.55:0.42"]=167, ["0.41:0.37:0.55:0.42:0.63:0.36"]=256, ["0.41:0.37:0.55:0.42:0.63:0.36:0.64:0.23"]=384, ["0.41:0.37:0.55:0.42:0.63:0.36:0.64:0.23:0.54:0.21"]=518, ["0.41:0.37:0.56:0.53:0.46:0.30"]=481,
            ["0.41:0.37:0.56:0.53:0.41:0.47"]=378, ["0.41:0.37:0.56:0.53:0.45:0.56"]=410, ["0.41:0.37:0.56:0.53:0.41:0.47:0.32:0.58"]=520, ["0.41:0.37:0.56:0.53:0.63:0.44"]=412, ["0.41:0.37:0.56:0.53:0.46:0.30:0.54:0.21"]=602, ["0.59:0.30:0.57:0.33:0.64:0.23:0.63:0.36:0.63:0.44"]=270,
            ["0.59:0.30:0.57:0.33:0.64:0.23:0.63:0.36:0.56:0.53"]=302, ["0.59:0.30:0.57:0.33:0.64:0.23:0.63:0.44:0.56:0.53:0.61:0.55"]=396,
        },
    }
end

local flightDataCache = {}
local flightHooksInstalled = false
local flightEventFrame = nil
local flightBar = nil
local flightActive = false
local flightState = { names = {}, times = {} }
local flightTicks = {}
local flightReport = {}
local flightLastSec, flightSinceUpdate = -1, 0
local flightRouteKeys, flightRouteX, flightRouteY, flightRouteNames = {}, {}, {}, {}

local function GetBuiltInFlightDataForFaction(faction)
    if not faction then return nil end
    if flightDataCache[faction] then
        return flightDataCache[faction]
    end
    if faction == "Alliance" and type(BuildAllianceFlightData) == "function" then
        flightDataCache[faction] = BuildAllianceFlightData()
    elseif faction == "Horde" and type(BuildHordeFlightData) == "function" then
        flightDataCache[faction] = BuildHordeFlightData()
    end
    return flightDataCache[faction]
end

local function FormatFlightSeconds(seconds)
    local s = math.ceil(math.max(0, seconds or 0))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function PlayerHasFrequentFlier()
    if type(IsPlayerSpell) ~= "function" then return false end
    local ok, has = pcall(IsPlayerSpell, 1225490)
    return ok and not YRG.IsSecret(has) and has and true or false
end

local function GetFlightContinentMapID()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local info = C_Map.GetMapInfo(mapID)
    local guard = 0
    while info and info.mapType and info.mapType > 2 and guard < 16 do
        guard = guard + 1
        info = info.parentMapID and C_Map.GetMapInfo(info.parentMapID) or nil
    end
    if info and info.mapType == 2 then
        return info.mapID
    end
    return nil
end

local function GetFlightRouteLookup(continent)
    if not continent then return nil, nil end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if not faction or YRG.IsSecret(faction) then return nil, nil end
    local builtin = GetBuiltInFlightDataForFaction(faction)
    local custom = YRGDB and YRGDB.flightTimes and YRGDB.flightTimes[faction] and YRGDB.flightTimes[faction][continent]
    local staticCont = builtin and builtin[continent]
    return custom, staticCont
end

local function LookupFlightDuration(continent, routeString)
    local custom, staticCont = GetFlightRouteLookup(continent)
    if custom and type(custom[routeString]) == "number" then
        return custom[routeString]
    end
    if staticCont and type(staticCont[routeString]) == "number" then
        return staticCont[routeString]
    end
    return nil
end

local function SaveCustomFlightDuration(faction, continent, routeString, duration)
    if not (faction and continent and routeString and type(duration) == "number" and duration > 2) then return end
    YRGDB = YRGDB or {}
    YRGDB.flightTimes = YRGDB.flightTimes or {}
    YRGDB.flightTimes[faction] = YRGDB.flightTimes[faction] or {}
    YRGDB.flightTimes[faction][continent] = YRGDB.flightTimes[faction][continent] or {}
    YRGDB.flightTimes[faction][continent][routeString] = duration
end

local function GetTaxiNodeNameShort(slotIdx)
    if type(TaxiNodeName) ~= "function" then return "" end
    local raw = YRG.SafeString(TaxiNodeName(slotIdx), "") or ""
    return string.match(raw, "[^,]+") or raw
end

local function GetCurrentTaxiNodeSlot()
    if type(NumTaxiNodes) ~= "function" or type(TaxiNodeGetType) ~= "function" then return nil end
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then
            return i
        end
    end
    return nil
end

local function GetTaxiNodeKey(slotIdx)
    if type(TaxiNodePosition) ~= "function" then return "0.00:0.00", 0, 0 end
    local x, y = TaxiNodePosition(slotIdx)
    x = YRG.SafeNumber(x, 0)
    y = YRG.SafeNumber(y, 0)
    return string.format("%0.2f:%0.2f", x, y), x, y
end

local function AddFlightRouteNode(slotIdx)
    local n = #flightRouteKeys + 1
    flightRouteKeys[n], flightRouteX[n], flightRouteY[n] = GetTaxiNodeKey(slotIdx)
    flightRouteNames[n] = GetTaxiNodeNameShort(slotIdx)
end

local function BuildFlightRoute(currentSlot, destSlot)
    wipe(flightRouteKeys); wipe(flightRouteX); wipe(flightRouteY); wipe(flightRouteNames)
    AddFlightRouteNode(currentSlot)
    local numRoutes = (type(GetNumRoutes) == "function" and GetNumRoutes(destSlot)) or 0
    for i = 2, numRoutes + 1 do
        local hopSlot = type(TaxiGetNodeSlot) == "function" and TaxiGetNodeSlot(destSlot, i, true) or nil
        if hopSlot then
            AddFlightRouteNode(hopSlot)
        end
    end
    local destKey = GetTaxiNodeKey(destSlot)
    local routeString = table.concat(flightRouteKeys, ":")
    if not string.find(routeString, destKey, 1, true) then
        AddFlightRouteNode(destSlot)
        routeString = routeString .. ":" .. destKey
    end
    return routeString, destKey
end

local function LookupSubRouteDuration(continent, firstIdx, lastIdx)
    local parts = {}
    for i = firstIdx, lastIdx do
        table.insert(parts, flightRouteKeys[i])
    end
    local d = LookupFlightDuration(continent, table.concat(parts, ":"))
    if type(d) == "number" and d > 0 then
        return d
    end
    return nil
end

local function ComputeFlightStopTimes(continent, total, names, times)
    wipe(names); wipe(times)
    local last = #flightRouteKeys
    local prevTime = 0
    for i = 2, last - 1 do
        local stopTime = LookupSubRouteDuration(continent, 1, i)
        if not stopTime then
            local rest = LookupSubRouteDuration(continent, i, last)
            stopTime = rest and (total - rest) or nil
        end
        if not stopTime or stopTime <= prevTime or stopTime >= total then
            wipe(times)
            break
        end
        times[i - 1] = stopTime
        prevTime = stopTime
    end
    if last > 2 and #times ~= last - 2 then
        local totalDist = 0
        for i = 2, last do
            local dx = (flightRouteX[i] or 0) - (flightRouteX[i - 1] or 0)
            local dy = (flightRouteY[i] or 0) - (flightRouteY[i - 1] or 0)
            totalDist = totalDist + math.sqrt(dx * dx + dy * dy)
            if i < last then
                times[i - 1] = totalDist
            end
        end
        for i = 1, last - 2 do
            times[i] = totalDist > 0 and (total * times[i] / totalDist) or (total * i / (last - 1))
        end
    end
    for i = 2, last - 1 do
        names[i - 1] = flightRouteNames[i]
    end
end

local function EnsureFlightTimerBar()
    if flightBar then return flightBar end

    local bar = CreateFrame("Frame", "YRGFlightTimerBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:Hide()

    local sdb = YRG:GetSteamdeckDB()
    local pos = (sdb and sdb.flightBarPos) or { point = "TOP", relPoint = "TOP", x = 0, y = -66 }
    bar:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or -66)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.04, 0.04, 0.06, 0.78)

    bar.edges = {}
    for i = 1, 4 do
        bar.edges[i] = bar:CreateTexture(nil, "BORDER")
        bar.edges[i]:SetColorTexture(1, 1, 1, 0.12)
    end
    bar.edges[1]:SetPoint("TOPLEFT"); bar.edges[1]:SetPoint("TOPRIGHT")
    bar.edges[2]:SetPoint("BOTTOMLEFT"); bar.edges[2]:SetPoint("BOTTOMRIGHT")
    bar.edges[3]:SetPoint("TOPLEFT"); bar.edges[3]:SetPoint("BOTTOMLEFT")
    bar.edges[4]:SetPoint("TOPRIGHT"); bar.edges[4]:SetPoint("BOTTOMRIGHT")

    local function MakeFlightFont(justify)
        local fs = bar:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH(justify)
        fs:SetWordWrap(false)
        return fs
    end

    bar.dest = MakeFlightFont("LEFT")
    bar.time = MakeFlightFont("RIGHT")
    bar.time:SetTextColor(0.92, 0.92, 0.92)

    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local fillR, fillG, fillB = 0.95, 0.27, 0.27
    if faction == "Alliance" then
        fillR, fillG, fillB = 0.30, 0.62, 1.00
    end

    bar.track = CreateFrame("StatusBar", nil, bar)
    bar.track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.track:SetStatusBarColor(fillR, fillG, fillB, 1)
    bar.track:SetMinMaxValues(0, 1)
    bar.track.bg = bar.track:CreateTexture(nil, "BACKGROUND")
    bar.track.bg:SetAllPoints()
    bar.track.bg:SetColorTexture(1, 1, 1, 0.14)

    bar.spark = bar.track:CreateTexture(nil, "OVERLAY", nil, 1)
    bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetPoint("CENTER", bar.track:GetStatusBarTexture(), "RIGHT")

    bar.nextIcon = bar:CreateTexture(nil, "OVERLAY")
    bar.nextIcon:SetTexture("Interface\\TaxiFrame\\UI-Taxi-Icon-White")
    bar.nextIcon:SetVertexColor(0.72, 0.72, 0.72)
    bar.nextName = MakeFlightFont("LEFT")
    bar.nextName:SetTextColor(0.72, 0.72, 0.72)
    bar.nextTime = MakeFlightFont("RIGHT")
    bar.nextTime:SetTextColor(0.72, 0.72, 0.72)

    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, relPt, x, y = self:GetPoint()
        local db = YRG:GetSteamdeckDB()
        if db and pt then
            db.flightBarPos = { point = pt, relPoint = relPt or pt, x = x or 0, y = y or 0 }
        end
    end)

    flightBar = bar
    return bar
end

local function PlaceFlightTicks(bar, trackW, thick, px)
    local count = #flightState.times
    for i = 1, math.max(count, #flightTicks) do
        local tick = flightTicks[i]
        if i <= count then
            if not tick then
                tick = bar.track:CreateTexture(nil, "OVERLAY")
                tick:SetColorTexture(0.04, 0.04, 0.06, 0.90)
                flightTicks[i] = tick
            end
            local frac = 1 - (flightState.times[i] / flightState.total)
            tick:SetSize(px * 2, thick)
            tick:ClearAllPoints()
            tick:SetPoint("CENTER", bar.track, "LEFT", trackW * frac, 0)
            tick:Show()
        elseif tick then
            tick:Hide()
        end
    end
end

local function LayoutFlightBar()
    local bar = EnsureFlightTimerBar()
    local size = 10
    local small = math.max(6, size - 2)
    local showNext = flightState.nextStop ~= nil
    local pad = math.max(3, math.floor(size * 0.4 + 0.5))
    local thick = math.max(2, math.floor(size / 4 + 0.5))
    local gap = math.max(2, math.floor(size / 4 + 0.5))
    local width = 230

    bar:SetScale(1.8)
    bar:SetWidth(width)
    bar:SetHeight(pad + size + gap + thick + (showNext and (gap + small) or 0) + pad)

    local px = (PixelUtil and PixelUtil.GetPixelToUIUnitFactor) and (PixelUtil.GetPixelToUIUnitFactor() / (bar:GetEffectiveScale() or 1)) or 1
    bar.edges[1]:SetHeight(px); bar.edges[2]:SetHeight(px)
    bar.edges[3]:SetWidth(px); bar.edges[4]:SetWidth(px)

    local font = GameFontNormal and GameFontNormal:GetFont() or STANDARD_TEXT_FONT
    bar.dest:SetFont(font, size, "")
    bar.time:SetFont(font, size, "")
    bar.nextName:SetFont(font, small, "")
    bar.nextTime:SetFont(font, small, "")
    bar.dest:SetShadowOffset(1, -1)
    bar.time:SetShadowOffset(1, -1)
    bar.nextName:SetShadowOffset(1, -1)
    bar.nextTime:SetShadowOffset(1, -1)

    bar.time:ClearAllPoints()
    bar.time:SetPoint("TOPRIGHT", -pad, -pad)
    bar.dest:ClearAllPoints()
    bar.dest:SetPoint("TOPLEFT", pad, -pad)
    bar.dest:SetPoint("RIGHT", bar.time, "LEFT", -size / 2, 0)
    bar.dest:SetText(flightState.dest or "")

    local y = pad + size + gap
    bar.track:ClearAllPoints()
    bar.track:SetPoint("TOPLEFT", pad, -y)
    bar.track:SetPoint("TOPRIGHT", -pad, -y)
    bar.track:SetHeight(thick)
    bar.spark:SetSize(math.max(8, thick * 4), thick * 4)
    PlaceFlightTicks(bar, width - (pad * 2), thick, px)

    bar.nextIcon:SetShown(showNext)
    bar.nextName:SetShown(showNext)
    bar.nextTime:SetShown(showNext)
    if showNext then
        y = y + thick + gap
        bar.nextIcon:SetSize(small, small)
        bar.nextIcon:ClearAllPoints()
        bar.nextIcon:SetPoint("TOPLEFT", pad, -y)
        bar.nextTime:ClearAllPoints()
        bar.nextTime:SetPoint("TOPRIGHT", -pad, -y)
        bar.nextName:ClearAllPoints()
        bar.nextName:SetPoint("TOPLEFT", bar.nextIcon, "TOPRIGHT", 3, 0)
        bar.nextName:SetPoint("RIGHT", bar.nextTime, "LEFT", -small / 2, 0)
        bar.nextName:SetText(flightState.names[flightState.nextStop] or "")
    end
end

local function StopFlightTimerBar()
    flightActive = false
    if flightBar then
        flightBar:SetScript("OnUpdate", nil)
        flightBar:Hide()
    end
end

local function SetFlightBarProgress(elapsed)
    if not flightBar then return 0 end
    local remaining = (flightState.total or 1) - elapsed
    if remaining < 0 then remaining = 0 end
    local val = (flightState.total and flightState.total > 0) and (remaining / flightState.total) or 0
    flightBar.track:SetValue(val)
    flightBar.spark:SetShown(val > 0 and val < 1)
    return remaining
end

local function UpdateFlightBarText(elapsed, remaining)
    if not flightBar then return end
    flightBar.time:SetText(FormatFlightSeconds(remaining))
    local nextStop = flightState.nextStop
    if nextStop then
        while nextStop and elapsed >= (flightState.times[nextStop] or math.huge) do
            nextStop = flightState.times[nextStop + 1] and (nextStop + 1) or nil
        end
        if nextStop ~= flightState.nextStop then
            flightState.nextStop = nextStop
            if nextStop then
                flightBar.nextName:SetText(flightState.names[nextStop] or "")
            else
                LayoutFlightBar()
            end
        end
        if nextStop then
            flightBar.nextTime:SetText(FormatFlightSeconds((flightState.times[nextStop] or elapsed) - elapsed))
        end
    end
end

local function OnFlightBarUpdate(_, elapsed)
    local db = YRG:GetSteamdeckDB()
    if not db or not db.showFlightTimes then
        StopFlightTimerBar()
        return
    end
    flightSinceUpdate = flightSinceUpdate + elapsed
    if flightSinceUpdate < 0.1 then return end
    flightSinceUpdate = 0

    local flown = GetTime() - (flightState.start or GetTime())
    local remaining = SetFlightBarProgress(flown)
    local sec = math.ceil(remaining)
    if sec ~= flightLastSec then
        flightLastSec = sec
        if remaining <= 0 or (flown > 2 and type(UnitOnTaxi) == "function" and not UnitOnTaxi("player")) then
            StopFlightTimerBar()
            return
        end
        UpdateFlightBarText(flown, remaining)
    end
end

local function StartFlightTimerBar(total, destination)
    local bar = EnsureFlightTimerBar()
    flightActive = true
    flightState.total = total
    flightState.dest = destination
    flightState.start = GetTime()
    flightState.nextStop = flightState.times[1] and 1 or nil
    LayoutFlightBar()
    SetFlightBarProgress(0)
    UpdateFlightBarText(0, total)
    flightLastSec, flightSinceUpdate = -1, 0
    bar:SetScript("OnUpdate", OnFlightBarUpdate)
    bar:Show()
end

function YRG:ApplyFlightTimesSettings()
    local sdb = self:GetSteamdeckDB()
    local enabled = sdb and sdb.showFlightTimes and true or false

    if not enabled then
        if flightEventFrame then
            flightEventFrame:UnregisterAllEvents()
        end
        StopFlightTimerBar()
        return
    end

    -- Warm faction flight table
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction and not YRG.IsSecret(faction) then
        GetBuiltInFlightDataForFaction(faction)
    end

    if not flightEventFrame then
        flightEventFrame = CreateFrame("Frame")
        flightEventFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_ENTERING_WORLD" then
                if not (type(UnitOnTaxi) == "function" and UnitOnTaxi("player")) then
                    flightEventFrame:UnregisterEvent("PLAYER_CONTROL_GAINED")
                    if flightActive then
                        StopFlightTimerBar()
                    end
                end
                return
            end
            flightEventFrame:UnregisterEvent("PLAYER_CONTROL_GAINED")
            local speedMult = flightReport.frequentFlier and 1.2 or 1
            if flightReport.route and flightReport.continent and flightReport.faction and flightReport.start and not flightReport.saved then
                local taken = math.floor(((GetTime() - flightReport.start) * speedMult) + 0.5)
                SaveCustomFlightDuration(flightReport.faction, flightReport.continent, flightReport.route, taken)
            end
            if flightActive then
                StopFlightTimerBar()
            end
        end)
    end

    if flightHooksInstalled then return end
    flightHooksInstalled = true

    local function StopLandingEvent()
        if flightEventFrame then
            flightEventFrame:UnregisterEvent("PLAYER_CONTROL_GAINED")
        end
    end

    if type(TakeTaxiNode) == "function" then
        hooksecurefunc("TakeTaxiNode", function(node)
            local db = YRG:GetSteamdeckDB()
            if not db or not db.showFlightTimes then return end
            if UnitAffectingCombat and UnitAffectingCombat("player") then return end

            local current = GetCurrentTaxiNodeSlot()
            if not current or not node then return end

            local continent = GetFlightContinentMapID()
            local routeString = BuildFlightRoute(current, node)
            local duration = LookupFlightDuration(continent, routeString)
            if type(duration) ~= "number" then duration = nil end

            if duration == 0 then
                StopLandingEvent()
                StopFlightTimerBar()
                return
            end

            local destName = GetTaxiNodeNameShort(node)
            local fac = UnitFactionGroup and UnitFactionGroup("player")
            flightReport.start = GetTime()
            flightReport.route = routeString
            flightReport.continent = continent
            flightReport.faction = (not YRG.IsSecret(fac)) and fac or nil
            flightReport.saved = duration
            flightReport.frequentFlier = PlayerHasFrequentFlier()

            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(1, function()
                    local mdb = YRG:GetSteamdeckDB()
                    if not mdb or not mdb.showFlightTimes then
                        StopLandingEvent()
                        StopFlightTimerBar()
                        return
                    end
                    if type(UnitOnTaxi) == "function" and UnitOnTaxi("player") then
                        flightEventFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
                    else
                        StopLandingEvent()
                        StopFlightTimerBar()
                    end
                end)
            end

            if duration then
                ComputeFlightStopTimes(continent, duration, flightState.names, flightState.times)
                local barTime = duration
                if flightReport.frequentFlier then
                    barTime = duration / 1.2
                    for i = 1, #flightState.times do
                        flightState.times[i] = flightState.times[i] / 1.2
                    end
                end
                StartFlightTimerBar(barTime, destName)
            else
                StopFlightTimerBar()
            end
        end)
    end

    if type(TaxiRequestEarlyLanding) == "function" then
        hooksecurefunc("TaxiRequestEarlyLanding", function()
            StopLandingEvent()
            if not flightActive then return end
            local nextStop = flightState.nextStop
            if nextStop then
                flightState.total = flightState.times[nextStop]
                flightState.dest = flightState.names[nextStop]
                for i = #flightState.times, nextStop, -1 do
                    flightState.times[i] = nil
                    flightState.names[i] = nil
                end
                flightState.nextStop = nil
                LayoutFlightBar()
                SetFlightBarProgress(GetTime() - (flightState.start or GetTime()))
                flightLastSec = -1
            end
        end)
    end

    if type(TaxiNodeOnButtonEnter) == "function" then
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
            StopLandingEvent()
            local db = YRG:GetSteamdeckDB()
            if not db or not db.showFlightTimes then return end
            if not button or type(button.GetID) ~= "function" then return end

            local current = GetCurrentTaxiNodeSlot()
            if not current then return end
            local continent = GetFlightContinentMapID()
            local routeString, destKey = BuildFlightRoute(current, button:GetID())
            local duration = LookupFlightDuration(continent, routeString)
            if type(duration) == "number" then
                if duration == 0 then
                    GameTooltip:AddLine("Flight times are not available for this route.", 0.9, 0.9, 0.9, true)
                else
                    if PlayerHasFrequentFlier() then
                        duration = duration / 1.2
                    end
                    GameTooltip:AddLine("Duration: " .. FormatFlightSeconds(duration), 0.9, 0.9, 0.9, true)
                end
                GameTooltip:Show()
            elseif flightRouteKeys[1] ~= destKey then
                GameTooltip:AddLine("Duration: -:--", 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end
        end)
    end

    -- Avoid post-hooking protected teleport/BG confirm APIs (`AcceptBattlefieldPort`, `ConfirmSummon`);
    -- `PLAYER_ENTERING_WORLD` and `OnFlightBarUpdate` (`UnitOnTaxi`) already stop the timer cleanly.
    if flightEventFrame then
        flightEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
end

-- Hook Blizzard's FloatingChatFrame fade functions so default backgrounds & scrollbars never flash
local function EnforceChatFrameOverridesOnHook(chatFrame)
    if not chatFrame then return end
    local meta = chatFrameMeta[chatFrame]
    local idx = (meta and meta.index) or (chatFrame.GetID and chatFrame:GetID()) or 1
    if ShouldApplyGradientToChatFrame(chatFrame, idx) then
        SuppressDefaultChatBgRegions(chatFrame, idx, true)
    end
    if ShouldSuppressChatScrollBar() then
        if chatFrame.ScrollBar then ForceHideScrollElement(chatFrame.ScrollBar) end
        if chatFrame.ScrollToBottomButton then ForceHideScrollElement(chatFrame.ScrollToBottomButton) end
        if chatFrame.buttonFrame then ForceHideScrollElement(chatFrame.buttonFrame) end
    end
end

if type(FCF_FadeInChatFrame) == "function" then
    hooksecurefunc("FCF_FadeInChatFrame", EnforceChatFrameOverridesOnHook)
end

if type(FCF_FadeOutChatFrame) == "function" then
    hooksecurefunc("FCF_FadeOutChatFrame", EnforceChatFrameOverridesOnHook)
end

if type(FCF_SetWindowAlpha) == "function" then
    hooksecurefunc("FCF_SetWindowAlpha", function(chatFrame, alpha)
        if settingWindowAlphaGuard or not chatFrame then return end
        local meta = chatFrameMeta[chatFrame]
        local idx = (meta and meta.index) or (chatFrame.GetID and chatFrame:GetID()) or 1
        if ShouldApplyGradientToChatFrame(chatFrame, idx) then
            settingWindowAlphaGuard = true
            SuppressDefaultChatBgRegions(chatFrame, idx, true)
            settingWindowAlphaGuard = false
        end
    end)
end

-- Periodic watcher for Chat Tab hover-fade, ScrollBar auto-hide, top-edge text fade, and Chat Inactivity fade
-- Runs only when autoFadeChatTabs, fadeChatOnInactivity, or fadeChatTopText is enabled.
local chatWatcher = CreateFrame("Frame")
local watcherElapsed = 0
chatWatcher:SetScript("OnUpdate", function(_, elapsed)
    watcherElapsed = watcherElapsed + elapsed
    if watcherElapsed < 0.1 then return end
    local dt = watcherElapsed
    watcherElapsed = 0

    local sdb = YRG:GetSteamdeckDB()
    if not sdb or (not sdb.autoFadeChatTabs and not sdb.fadeChatOnInactivity and not sdb.fadeChatTopText) then return end

    if sdb.fadeChatTopText then
        local maxWindows = NUM_CHAT_WINDOWS or 10
        for i = 1, maxWindows do
            local cf = _G["ChatFrame" .. i]
            if cf and cf.IsShown and cf:IsShown() and ShouldApplyTopTextFade(cf, i) then
                ApplyChatTopTextFade(cf, i)
            end
        end
    end

    if not sdb.autoFadeChatTabs and not sdb.fadeChatOnInactivity then return end

    local active = IsMouseOverAnyChatOrTab() or IsAnyChatEditBoxActive()

    if sdb.autoFadeChatTabs and active ~= lastChatActiveState then
        lastChatActiveState = active
        UpdateChatTabsAlpha(active)
        if not sdb.disableChatScrollBar then
            EnforceAllChatScrollBarsState()
        end
    end

    if sdb.fadeChatOnInactivity then
        if active then
            lastChatActivityTime = (GetTime and GetTime()) or 0
            if currentChatFadeAlpha < 1.0 then
                SetChatWindowsContentAlpha(1.0)
            end
        else
            local timeoutSec = math.max(1, tonumber(sdb.chatInactivityMinutes) or 5) * 60
            local idleSec = ((GetTime and GetTime()) or 0) - lastChatActivityTime
            if idleSec >= timeoutSec then
                if currentChatFadeAlpha > 0.0 then
                    local nextAlpha = math.max(0.0, currentChatFadeAlpha - (dt * 2.0))
                    if math.abs(nextAlpha - currentChatFadeAlpha) >= 0.002 or nextAlpha == 0.0 then
                        SetChatWindowsContentAlpha(nextAlpha)
                    end
                end
            elseif currentChatFadeAlpha < 1.0 then
                SetChatWindowsContentAlpha(1.0)
            end
        end
    end
end)

if type(ChatEdit_ActivateChat) == "function" then
    hooksecurefunc("ChatEdit_ActivateChat", function(editBox)
        lastChatActivityTime = (GetTime and GetTime()) or 0
        if currentChatFadeAlpha < 1.0 then
            SetChatWindowsContentAlpha(1.0)
        end
        if editBox then
            UpdateEditBoxLayoutAndVisibility(editBox, editBox.chatFrame or ChatFrame1)
            ApplyEditBoxVisualState(editBox, true)
        end
    end)
end

if type(ChatEdit_DeactivateChat) == "function" then
    hooksecurefunc("ChatEdit_DeactivateChat", function(editBox)
        lastChatActivityTime = (GetTime and GetTime()) or 0
        if editBox then
            ApplyEditBoxVisualState(editBox, false)
        end
    end)
end

if type(FCF_DockUpdate) == "function" then
    hooksecurefunc("FCF_DockUpdate", function()
        ScheduleChatRefresh()
    end)
end

if type(FCF_UnDockFrame) == "function" then
    hooksecurefunc("FCF_UnDockFrame", function()
        ScheduleChatRefresh()
    end)
end

if type(FCF_UpdateDockPosition) == "function" then
    hooksecurefunc("FCF_UpdateDockPosition", function()
        ScheduleChatSnap()
    end)
end

if type(UIParent_ManageFramePositions) == "function" then
    hooksecurefunc("UIParent_ManageFramePositions", function()
        ScheduleChatSnap()
    end)
elseif type(ManageFramePositions) == "function" then
    hooksecurefunc("ManageFramePositions", function()
        ScheduleChatSnap()
    end)
end

if type(FCF_RestorePositionAndDimensions) == "function" then
    hooksecurefunc("FCF_RestorePositionAndDimensions", function(chatFrame)
        if not chatFrame or chatFrame == ChatFrame1 then
            ScheduleChatSnap()
        end
    end)
end

if type(FCFTab_UpdateAlpha) == "function" then
    hooksecurefunc("FCFTab_UpdateAlpha", function()
        local sdb = YRG:GetSteamdeckDB()
        if sdb and sdb.autoFadeChatTabs then
            local active = IsMouseOverAnyChatOrTab() or IsAnyChatEditBoxActive()
            lastChatActiveState = active
            UpdateChatTabsAlpha(active)
        end
    end)
end

if type(FCF_StartAlertFlash) == "function" then
    hooksecurefunc("FCF_StartAlertFlash", function()
        lastChatActivityTime = (GetTime and GetTime()) or 0
        if currentChatFadeAlpha < 1.0 then
            SetChatWindowsContentAlpha(1.0)
        end
    end)
end

-- =========================================================================
-- MODERN SETTINGS BUILDER & COLOR PICKER HELPERS (WoW Forever 1.60.1)
-- =========================================================================
function YRG:OpenColorPicker(getColorAlpha, setColorAlpha)
    if not ColorPickerFrame then return end
    local origR, origG, origB, origA = getColorAlpha()
    origR, origG, origB = origR or 1, origG or 1, origB or 1
    origA = (origA ~= nil) and origA or 1

    if ColorPickerFrame.SetupColorPickerAndShow then
        local function ApplyModernColor()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha()
                or (1 - (ColorPickerFrame.GetOpacity and ColorPickerFrame:GetOpacity() or 0))
            setColorAlpha(nr, ng, nb, na)
        end

        ColorPickerFrame:Hide()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = origR,
            g = origG,
            b = origB,
            opacity = origA,
            hasOpacity = true,
            swatchFunc = ApplyModernColor,
            opacityFunc = ApplyModernColor,
            cancelFunc = function()
                setColorAlpha(origR, origG, origB, origA)
            end,
        })
    else
        local function ApplyLegacyColor()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = 1 - (ColorPickerFrame.GetOpacity and ColorPickerFrame:GetOpacity() or 0)
            setColorAlpha(nr, ng, nb, na)
        end

        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.previousValues = { r = origR, g = origG, b = origB, opacity = 1 - origA }
        ColorPickerFrame.func = ApplyLegacyColor
        ColorPickerFrame.opacityFunc = ApplyLegacyColor
        ColorPickerFrame.cancelFunc = function()
            setColorAlpha(origR, origG, origB, origA)
        end
        ColorPickerFrame:SetColorRGB(origR, origG, origB)
        if ColorPickerFrame.SetOpacity then
            ColorPickerFrame:SetOpacity(1 - origA)
        end
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function SnapSliderValue(val, minVal, step)
    local num = tonumber(val) or minVal
    step = step or 1
    if step < 1 then
        local decimals = (step >= 0.1) and 1 or 2
        local factor = 10 ^ decimals
        local stepSnapped = minVal + math.floor((num - minVal) / step + 0.5) * step
        local snapped = math.floor(stepSnapped * factor + 0.5) / factor
        if snapped == 0 then snapped = 0 end
        return snapped
    end
    local snapped = minVal + math.floor((num - minVal) / step + 0.5) * step
    if snapped == 0 then snapped = 0 end
    return snapped
end

local function FormatColorButtonLabel(baseLabel, getColorAlpha)
    local r, g, b, a = getColorAlpha()
    local ir = math.floor(math.max(0, math.min(1, r or 1)) * 255 + 0.5)
    local ig = math.floor(math.max(0, math.min(1, g or 1)) * 255 + 0.5)
    local ib = math.floor(math.max(0, math.min(1, b or 1)) * 255 + 0.5)
    local pct = math.floor(math.max(0, math.min(1, (a ~= nil) and a or 1)) * 100 + 0.5)
    return string.format("%s  |cff%02x%02x%02x[Sample]|r |cffaaaaaa(%d%%)|r", baseLabel, ir, ig, ib, pct)
end

local SettingsContextMixin = {}

--- Notify registered setting variables so Blizzard's SettingsList re-evaluates values and ModifyPredicates.
function SettingsContextMixin:Notify(vars)
    if not (Settings and Settings.NotifyUpdate) or not vars then return end
    for _, var in ipairs(vars) do
        pcall(Settings.NotifyUpdate, var)
    end
end

--- Notify all settings registered inside this context.
function SettingsContextMixin:NotifyAll()
    self:Notify(self._vars)
end

--- Add a native Blizzard vertical settings section header row.
function SettingsContextMixin:AddHeader(title, tooltip)
    if self.layout and type(CreateSettingsListSectionHeaderInitializer) == "function" then
        local init = tooltip
            and CreateSettingsListSectionHeaderInitializer(title, tooltip)
            or CreateSettingsListSectionHeaderInitializer(title)
        self.layout:AddInitializer(init)
        return init
    end
    return nil
end

--- Register and create a native boolean checkbox row backed by a proxy setting.
function SettingsContextMixin:AddCheckbox(opts)
    local var = opts.var or (self.prefix .. "_" .. opts.key)
    local defaultBool = opts.defaultValue and true or false
    local setting = Settings.RegisterProxySetting(
        self.category,
        var,
        Settings.VarType.Boolean,
        opts.name,
        defaultBool,
        function() return opts.get() and true or false end,
        function(val)
            opts.set(val and true or false)
            if opts.notifies then
                self:Notify(opts.notifies)
            end
        end
    )
    table.insert(self._vars, var)
    local init = Settings.CreateCheckbox(self.category, setting, opts.tooltip)
    if opts.canModify and init and init.AddModifyPredicate then
        init:AddModifyPredicate(opts.canModify)
    end
    return setting, init, var
end

--- Register and create a native MinimalSliderWithSteppers row backed by a proxy setting.
function SettingsContextMixin:AddSlider(opts)
    local var = opts.var or (self.prefix .. "_" .. opts.key)
    local minVal = opts.min
    local maxVal = opts.max
    local step = opts.step or 1
    local defaultNum = tonumber(opts.defaultValue) or minVal

    local function CleanValue(v)
        return opts.roundFn and opts.roundFn(v) or SnapSliderValue(v, minVal, step)
    end

    local sliderOptions = Settings.CreateSliderOptions(minVal, maxVal, step)
    local formatter = opts.format or function(v)
        local c = CleanValue(v)
        if step < 1 then
            return string.format("%.2f", c)
        end
        return tostring(c)
    end
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
        return formatter(CleanValue(v))
    end)

    local setting = Settings.RegisterProxySetting(
        self.category,
        var,
        Settings.VarType.Number,
        opts.name,
        defaultNum,
        function()
            local v = tonumber(opts.get())
            if v == nil then v = defaultNum end
            return math.max(minVal, math.min(maxVal, v))
        end,
        function(val)
            opts.set(CleanValue(val))
        end
    )
    table.insert(self._vars, var)
    local init = Settings.CreateSlider(self.category, setting, sliderOptions, opts.tooltip)
    if opts.canModify and init and init.AddModifyPredicate then
        init:AddModifyPredicate(opts.canModify)
    end
    return setting, init, var
end

--- Register and create a native WowStyle1Dropdown / Blizzard_Menu row backed by a proxy setting.
function SettingsContextMixin:AddDropdown(opts)
    local var = opts.var or (self.prefix .. "_" .. opts.key)
    local varType = (type(opts.defaultValue) == "number") and Settings.VarType.Number or Settings.VarType.String
    local setting = Settings.RegisterProxySetting(
        self.category,
        var,
        varType,
        opts.name,
        opts.defaultValue,
        function()
            local v = opts.get()
            if v == nil then return opts.defaultValue end
            return v
        end,
        function(val)
            opts.set(val)
            if opts.notifies then
                self:Notify(opts.notifies)
            end
        end
    )
    table.insert(self._vars, var)

    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        local list = (type(opts.options) == "function") and opts.options() or (opts.options or {})
        for _, item in ipairs(list) do
            if item.tooltip then
                container:Add(item.value, item.label, item.tooltip)
            else
                container:Add(item.value, item.label)
            end
        end
        return container:GetData()
    end

    local init = Settings.CreateDropdown(self.category, setting, GetOptions, opts.tooltip)
    if opts.canModify and init and init.AddModifyPredicate then
        init:AddModifyPredicate(opts.canModify)
    end
    return setting, init, var
end

--- Add a native Settings button row (with addSearchTags=false to avoid Blizzard Options search taint).
function SettingsContextMixin:AddButton(opts)
    if not (self.layout and type(CreateSettingsButtonInitializer) == "function") then
        return nil
    end
    local init = CreateSettingsButtonInitializer(
        opts.name or "",
        opts.buttonText or "Apply",
        opts.onClick,
        opts.tooltip,
        false
    )
    self.layout:AddInitializer(init)
    if opts.canModify and init and init.AddModifyPredicate then
        init:AddModifyPredicate(opts.canModify)
    end
    return init
end

--- Add a native button row paired with Blizzard's ColorPickerFrame and a hex preview sample.
function SettingsContextMixin:AddColorPicker(opts)
    local init
    local function RefreshLabel()
        if init and init.data then
            init.data.name = FormatColorButtonLabel(opts.name, opts.get)
        end
    end

    init = self:AddButton({
        name = FormatColorButtonLabel(opts.name, opts.get),
        buttonText = opts.buttonText or "Choose Color",
        tooltip = opts.tooltip,
        canModify = opts.canModify,
        onClick = function()
            YRG:OpenColorPicker(opts.get, function(r, g, b, a)
                opts.set(r, g, b, a)
                RefreshLabel()
            end)
        end,
    })

    return {
        initializer = init,
        Refresh = RefreshLabel,
    }
end

--- Create a builder context wrapping a Blizzard Vertical Settings category and layout.
function YRG:CreateSettingsContext(category, layout, prefix)
    local ctx = {
        category = category,
        layout = layout,
        prefix = prefix or "YRG",
        _vars = {},
    }
    for k, fn in pairs(SettingsContextMixin) do
        ctx[k] = fn
    end
    return ctx
end

local function BuildSettingsPanels()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    local mainCategory, mainLayout = Settings.RegisterVerticalLayoutCategory("YRG")
    Settings.RegisterAddOnCategory(mainCategory)
    YRG.settingsCategory = mainCategory

    local mainCtx = YRG:CreateSettingsContext(mainCategory, mainLayout, "YRG_Main")
    local sdb = YRG:GetSteamdeckDB()

    -- =========================================================================
    -- BASE ADDON INFO
    -- =========================================================================
    mainCtx:AddHeader(
        "|cffffd100Author:|r " .. YRG.author,
        "|cffffd100YRG|r - YulRun Gaming Master Addon\nVersion: " .. YRG.version .. "\nAuthor: " .. YRG.author
    )

    -- =========================================================================
    -- BASE ADDON SETTINGS: Steamdeck & Compact Chat Improvements
    -- =========================================================================
    mainCtx:AddHeader(
        "Steamdeck & Compact Chat Improvements",
        "Version " .. YRG.version .. " — Author: " .. YRG.author .. "\n\nChat scrollbar, editbox, auto-fade, and gradient styling tuned for Steamdeck and compact UIs."
    )

    mainCtx:AddCheckbox({
        key = "disableChatScrollBar",
        name = "Disable Chat Window Scroll Bar (Snap Left)",
        tooltip = "Permanently hides the chat scroll bar and side button strip so they never pop up, and snaps the chat frame closer to the left edge.",
        defaultValue = true,
        get = function() return YRG:GetSteamdeckDB().disableChatScrollBar end,
        set = function(val)
            YRG:GetSteamdeckDB().disableChatScrollBar = val
            YRG:ApplySteamdeckSettings()
        end,
    })

    mainCtx:AddCheckbox({
        key = "hideChatEditBox",
        name = "Auto-Hide Chat Input Box (Overlap & Snap to Bottom)",
        tooltip = "Moves the chat input box up to overlap the bottom of the chat frame and hides it until you press Enter to type, allowing the chat frame to snap down.",
        defaultValue = true,
        get = function() return YRG:GetSteamdeckDB().hideChatEditBox end,
        set = function(val)
            YRG:GetSteamdeckDB().hideChatEditBox = val
            YRG:ApplySteamdeckSettings()
        end,
    })

    mainCtx:AddCheckbox({
        key = "autoFadeChatTabs",
        name = "Auto-Fade Chat Tabs & Scroll Bar (Show Only on Hover)",
        tooltip = "Fades out chat tabs and the scroll bar when idle, only showing them when hovering over the chat box or tab bar.",
        defaultValue = true,
        get = function() return YRG:GetSteamdeckDB().autoFadeChatTabs end,
        set = function(val)
            YRG:GetSteamdeckDB().autoFadeChatTabs = val
            YRG:ApplySteamdeckSettings()
        end,
    })

    local gradientVars = {
        "YRG_Main_chatGradientMainOnly",
        "YRG_Main_chatGradientWidthPct",
        "YRG_Main_chatGradientHeightPct",
        "YRG_Main_chatGradientOpacityPct",
    }
    mainCtx:AddCheckbox({
        key = "gradientChatBackground",
        name = "Replace Chat Background with Forever-Tinted Gradient",
        tooltip = "Replaces the default chat background with a doubled-up warm dark-brown/black half-radial gradient that fades smoothly toward the top and right.",
        defaultValue = true,
        notifies = gradientVars,
        get = function() return YRG:GetSteamdeckDB().gradientChatBackground end,
        set = function(val)
            YRG:GetSteamdeckDB().gradientChatBackground = val
            YRG:ApplySteamdeckSettings()
        end,
    })

    local function IsGradientEnabled()
        return YRG:GetSteamdeckDB().gradientChatBackground and true or false
    end

    local function IsTopTextFadeEnabled()
        return YRG:GetSteamdeckDB().fadeChatTopText and true or false
    end

    local function IsGradientOrTopFadeEnabled()
        return IsGradientEnabled() or IsTopTextFadeEnabled()
    end

    mainCtx:AddCheckbox({
        key = "chatGradientMainOnly",
        name = "Apply Gradient / Top Text Fade to Main Chat Only",
        tooltip = "Only applies the gradient background overlay and top-edge text fade to the main docked chat window (and its docked tabs), leaving separate free-floating chat windows untouched.",
        defaultValue = true,
        canModify = IsGradientOrTopFadeEnabled,
        get = function() return YRG:GetSteamdeckDB().chatGradientMainOnly ~= false end,
        set = function(val)
            YRG:GetSteamdeckDB().chatGradientMainOnly = val and true or false
            YRG:ApplySteamdeckSettings()
        end,
    })

    mainCtx:AddSlider({
        key = "chatGradientWidthPct",
        name = "Gradient Width (%)",
        tooltip = "Horizontal stretch percentage of the chat half-radial gradient background.",
        min = 50, max = 200, step = 5, defaultValue = 135,
        format = function(v) return string.format("%d%%", v) end,
        canModify = IsGradientEnabled,
        get = function() return YRG:GetSteamdeckDB().chatGradientWidthPct or 135 end,
        set = function(val)
            YRG:GetSteamdeckDB().chatGradientWidthPct = val
            YRG:ApplySteamdeckSettings()
        end,
    })

    mainCtx:AddSlider({
        key = "chatGradientHeightPct",
        name = "Gradient Height (%)",
        tooltip = "Vertical stretch percentage of the chat half-radial gradient background.",
        min = 25, max = 200, step = 5, defaultValue = 135,
        format = function(v) return string.format("%d%%", v) end,
        canModify = IsGradientEnabled,
        get = function() return YRG:GetSteamdeckDB().chatGradientHeightPct or 135 end,
        set = function(val)
            YRG:GetSteamdeckDB().chatGradientHeightPct = val
            YRG:ApplySteamdeckSettings()
        end,
    })

    mainCtx:AddSlider({
        key = "chatGradientOpacityPct",
        name = "Gradient Opacity (%)",
        tooltip = "Opacity percentage of the half-radial chat background gradient.",
        min = 5, max = 100, step = 5, defaultValue = 65,
        format = function(v) return string.format("%d%%", v) end,
        canModify = IsGradientEnabled,
        get = function() return YRG:GetSteamdeckDB().chatGradientOpacityPct or 65 end,
        set = function(val)
            YRG:GetSteamdeckDB().chatGradientOpacityPct = val
            YRG:ApplySteamdeckSettings()
        end,
    })

    mainCtx:AddCheckbox({
        key = "fadeChatTopText",
        name = "Fade Chat Text Near Top Edge",
        tooltip = "Softly fades chat lines as they scroll into the top portion of the chat window to blend cleanly with the gradient background.",
        defaultValue = true,
        notifies = { "YRG_Main_chatTextTopFadePct", "YRG_Main_chatGradientMainOnly" },
        get = function() return YRG:GetSteamdeckDB().fadeChatTopText and true or false end,
        set = function(val)
            YRG:GetSteamdeckDB().fadeChatTopText = val and true or false
            YRG:ApplySteamdeckSettings()
        end,
    })

    mainCtx:AddSlider({
        key = "chatTextTopFadePct",
        name = "Top Text Fade Amount (%)",
        tooltip = "Percentage of the chat window height from the top edge over which chat text fades out.",
        min = 10, max = 75, step = 5, defaultValue = 45,
        format = function(v) return string.format("%d%%", v) end,
        canModify = IsTopTextFadeEnabled,
        get = function() return YRG:GetSteamdeckDB().chatTextTopFadePct or 45 end,
        set = function(val)
            YRG:GetSteamdeckDB().chatTextTopFadePct = val
            YRG:ApplySteamdeckSettings()
        end,
    })

    mainCtx:AddCheckbox({
        key = "fadeChatOnInactivity",
        name = "Fade Chat Window When No New Messages",
        tooltip = "Automatically fades out the chat window when no new chat messages have been received for the configured number of minutes.",
        defaultValue = true,
        notifies = { "YRG_Main_chatInactivityIncludeFloating", "YRG_Main_chatInactivityMinutes" },
        get = function() return YRG:GetSteamdeckDB().fadeChatOnInactivity end,
        set = function(val)
            YRG:GetSteamdeckDB().fadeChatOnInactivity = val
            YRG:ResetChatInactivityTimer()
            YRG:ApplySteamdeckSettings()
        end,
    })

    local function IsInactivityFadeEnabled()
        return YRG:GetSteamdeckDB().fadeChatOnInactivity and true or false
    end

    mainCtx:AddCheckbox({
        key = "chatInactivityIncludeFloating",
        name = "Include Other Chat Windows in Inactivity Fade",
        tooltip = "Also fades separate free-floating chat tabs/windows when chat is inactive (even when excluded from the Forever background gradient).",
        defaultValue = true,
        canModify = IsInactivityFadeEnabled,
        get = function() return YRG:GetSteamdeckDB().chatInactivityIncludeFloating ~= false end,
        set = function(val)
            YRG:GetSteamdeckDB().chatInactivityIncludeFloating = val and true or false
            YRG:ApplySteamdeckSettings()
        end,
    })

    mainCtx:AddSlider({
        key = "chatInactivityMinutes",
        name = "Chat Inactivity Fade Timer (Minutes)",
        tooltip = "Minutes without new chat messages before fading the chat window.",
        min = 1, max = 30, step = 1, defaultValue = 5,
        format = function(v) return string.format("%d min", v) end,
        canModify = IsInactivityFadeEnabled,
        get = function() return YRG:GetSteamdeckDB().chatInactivityMinutes or 5 end,
        set = function(val)
            YRG:GetSteamdeckDB().chatInactivityMinutes = val
            YRG:ResetChatInactivityTimer()
        end,
    })

    -- =========================================================================
    -- BASE ADDON SETTINGS: General Gameplay Improvements
    -- =========================================================================
    mainCtx:AddHeader("General Gameplay Improvements")

    mainCtx:AddCheckbox({
        key = "quickLoot",
        name = "Quick Loot (Faster Auto Loot)",
        tooltip = "Accelerates looting all items immediately on LOOT_READY when Auto Loot is active (hold your Auto Loot modifier key to loot manually). Modeled after Leatrix Plus.",
        defaultValue = true,
        get = function() return YRG:GetSteamdeckDB().quickLoot end,
        set = function(val)
            YRG:GetSteamdeckDB().quickLoot = val
            YRG:ApplyQuickLootSettings()
        end,
    })

    mainCtx:AddCheckbox({
        key = "maxCameraZoom",
        name = "Max Camera Zoom",
        tooltip = "Increases maximum camera zoom distance factor from 1.9 to 2.6 (modeled after Leatrix Plus).",
        defaultValue = true,
        get = function() return YRG:GetSteamdeckDB().maxCameraZoom end,
        set = function(val)
            YRG:GetSteamdeckDB().maxCameraZoom = val
            YRG:ApplyCameraZoomSettings(true)
        end,
    })

    mainCtx:AddCheckbox({
        key = "fasterMovieSkip",
        name = "Faster Movie Skip",
        tooltip = "Allows Space, Escape, or Enter to cancel in-game cinematics and movies without confirmation prompts (modeled after Leatrix Plus).",
        defaultValue = true,
        get = function() return YRG:GetSteamdeckDB().fasterMovieSkip end,
        set = function(val)
            YRG:GetSteamdeckDB().fasterMovieSkip = val
            YRG:ApplyMovieSkipSettings()
        end,
    })

    mainCtx:AddCheckbox({
        key = "showFlightTimes",
        name = "Show Flight Times",
        tooltip = "Displays estimated flight durations in taxi map tooltips and shows a draggable flight countdown progress bar while flying (modeled after Leatrix Plus).",
        defaultValue = true,
        get = function() return YRG:GetSteamdeckDB().showFlightTimes end,
        set = function(val)
            YRG:GetSteamdeckDB().showFlightTimes = val
            YRG:ApplyFlightTimesSettings()
        end,
    })

    -- =========================================================================
    -- INSTALLED MODULES
    -- =========================================================================
    mainCtx:AddHeader("Installed Modules", "Enable or disable YRG feature modules below, or open their dedicated subpages in the left menu.")

    local isSyncingModuleToggle = false
    for _, id in ipairs(YRG.moduleOrder) do
        local mod = YRG.modules[id]
        local db = YRG:GetModuleDB(id)
        local mainVar = "YRG_Enable_" .. id
        local subVar = "YRG_SubEnable_" .. id
        local defaultModEnabled = (mod.defaultEnabled ~= false)

        mainCtx:AddCheckbox({
            var = mainVar,
            name = "Enable " .. mod.name,
            tooltip = (mod.description or "") .. "\n\nSelect \"" .. mod.name .. "\" in the left sidebar to configure detailed options.",
            defaultValue = defaultModEnabled,
            get = function() return YRG:IsModuleEnabled(id) end,
            set = function(val) YRG:SetModuleEnabled(id, val) end,
        })

        local subCat, subLayout = Settings.RegisterVerticalLayoutSubcategory(mainCategory, mod.name)
        mod.settingsCategory = subCat

        local subCtx = YRG:CreateSettingsContext(subCat, subLayout, "YRG_" .. id)

        subCtx:AddCheckbox({
            var = subVar,
            name = "Enable " .. mod.name,
            tooltip = mod.description or ("Master toggle for " .. mod.name .. "."),
            defaultValue = defaultModEnabled,
            get = function() return YRG:IsModuleEnabled(id) end,
            set = function(val) YRG:SetModuleEnabled(id, val) end,
        })

        if type(mod.BuildSettingsUI) == "function" then
            mod:BuildSettingsUI(subCtx, db)
        elseif type(mod.BuildConfigUI) == "function" then
            mod:BuildConfigUI(subCtx, db)
        end

        mod._syncToggleUI = function()
            if isSyncingModuleToggle then return end
            isSyncingModuleToggle = true
            if Settings and Settings.NotifyUpdate then
                pcall(Settings.NotifyUpdate, mainVar)
                pcall(Settings.NotifyUpdate, subVar)
            end
            subCtx:NotifyAll()
            isSyncingModuleToggle = false
        end

        Settings.RegisterAddOnCategory(subCat)

        if type(mod.BuildExtraCategories) == "function" then
            mod:BuildExtraCategories(mainCategory, db)
        end
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
for _, optEvent in ipairs({
    "UPDATE_CHAT_WINDOWS",
    "EDIT_MODE_LAYOUTS_UPDATED",
    "GAME_PAD_ACTIVE_CHANGED",
    "GAME_PAD_CONNECTED",
    "GAME_PAD_DISCONNECTED",
    "CVAR_UPDATE",
    "UI_SCALE_CHANGED",
    "DISPLAY_SIZE_CHANGED",
}) do
    pcall(loader.RegisterEvent, loader, optEvent)
end

local function ScheduleModeTransitionSnap()
    originalChat1Points = nil
    originalChat1Size = nil
    ScheduleChatRefresh()
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.05, ScheduleChatSnap)
        C_Timer.After(0.25, ScheduleChatRefresh)
        C_Timer.After(0.6, ScheduleChatSnap)
        C_Timer.After(1.2, ScheduleChatSnap)
    end
end

loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        YRGDB = CopyDefaults(defaultDB, YRGDB)
        for _, id in ipairs(YRG.moduleOrder) do
            local mod = YRG.modules[id]
            local db = YRG:GetModuleDB(id)
            if type(mod.OnInitialize) == "function" then
                mod:OnInitialize(db)
                mod._initialized = true
            end
        end
    elseif event == "PLAYER_LOGIN" then
        BuildSettingsPanels()
        YRG:ResetChatInactivityTimer()
        YRG:ApplySteamdeckSettings()
        for _, id in ipairs(YRG.moduleOrder) do
            local mod = YRG.modules[id]
            local db = YRG:GetModuleDB(id)
            if db.enabled and type(mod.OnEnable) == "function" then
                mod:OnEnable(db)
            end
        end
    elseif event == "GAME_PAD_ACTIVE_CHANGED" or event == "GAME_PAD_CONNECTED"
        or event == "GAME_PAD_DISCONNECTED" or event == "UI_SCALE_CHANGED"
        or event == "DISPLAY_SIZE_CHANGED" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
        ScheduleModeTransitionSnap()
    elseif event == "CVAR_UPDATE" then
        local cvarName = YRG.SafeString(arg1, "")
        if cvarName == "GamePadEnable" or cvarName == "GamepadEnable"
            or cvarName == "GamepadUseCompactActionBar"
            or cvarName == "uiScale" or cvarName == "useUiScale" then
            ScheduleModeTransitionSnap()
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_FLOATING_CHAT_WINDOWS"
        or event == "UPDATE_CHAT_WINDOWS" or event == "PLAYER_REGEN_ENABLED" then
        YRG:ApplySteamdeckSettings()
        if event ~= "PLAYER_REGEN_ENABLED" and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.1, ScheduleChatSnap)
            C_Timer.After(0.5, ScheduleChatSnap)
            C_Timer.After(1.2, ScheduleChatSnap)
        end
    end
end)

SLASH_YRG1 = "/yrg"
SlashCmdList["YRG"] = function(msg)
    local clean = (type(msg) == "string") and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if clean ~= "" then
        local cmd, rest = clean:match("^(%S+)%s*(.*)$")
        local handler = cmd and YRG.slashSubcommands and YRG.slashSubcommands[cmd:lower()]
        if handler then
            handler(rest or "")
            return
        end
    end
    YRG:OpenSettings()
end
