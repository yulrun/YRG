local _, YRG = ...

local MAX_COMBO_POINTS = 5
local POWER_MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local POWER_RAGE = (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1
local POWER_COMBO_POINTS = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local POWER_ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
local CAT_FORM_SPELL_ID = 768
local CAT_FORM_ICON_ID = 132115 -- Ability_Druid_CatForm

local TEX_CIRCLE_FILL = "Interface\\AddOns\\YRG\\Textures\\ComboPipFill"
local TEX_CIRCLE_RING = "Interface\\AddOns\\YRG\\Textures\\ComboPipRing"

local PIP_COLORS = {
    [1] = { 1.00, 0.85, 0.15 }, -- Gold
    [2] = { 1.00, 0.75, 0.12 }, -- Warm Gold
    [3] = { 1.00, 0.58, 0.10 }, -- Amber
    [4] = { 1.00, 0.38, 0.10 }, -- Orange-Red
    [5] = { 1.00, 0.14, 0.18 }, -- Finisher Crimson
}

local POSITION_OPTIONS = {
    { label = "Below Nameplate (Smart)", value = "BELOW" },
    { label = "Right of Health Bar",     value = "RIGHT" },
}

local ClassImprovements = {
    name = "ClassImprovementsModule",
    description = "Class UI enhancements including circular nameplate combo points (Rogues/Cat Form) and a Druid form Mana bar.",
    defaultEnabled = true,
    defaults = {
        enabled = true,
        position = "BELOW", -- "BELOW" (castbar & class-resource aware) or "RIGHT"
        pipSize = 18,
        spacing = 3,
        offsetX = 0,
        offsetY = -4,
        castBarDrop = 6,
        scale = 1.0,
        showDruidManaBar = true,
    }
}

local CASTBAR_FADE_HOLD_SEC = 0.50
local playerClass = select(2, UnitClass("player"))
local testMode = false
local targetCasting = false
local targetCastStartTime = 0
local targetCastHoldUntil = 0
local wasCastAnchorActive = false
local lastCastAnchorNameplate = nil
local pips = {}
local lastAnchorTarget = nil
local lastAnchorExtraDrop = 0
local lastAnchorSource = "None"
local hookedFrames = setmetatable({}, { __mode = "k" })

local function ClearCastState()
    targetCasting = false
    targetCastStartTime = 0
    targetCastHoldUntil = 0
    wasCastAnchorActive = false
    lastCastAnchorNameplate = nil
end

local function IsSecret(val)
    return YRG.IsSecret and YRG.IsSecret(val) or false
end

local function IsDruidInCatForm()
    -- 1. Energy power type (Cat Form is the only Druid form using Energy)
    if type(UnitPowerType) == "function" then
        local powerType, powerToken = UnitPowerType("player")
        if (not IsSecret(powerType) and powerType == POWER_ENERGY)
            or (not IsSecret(powerToken) and powerToken == "ENERGY") then
            return true
        end
    end

    -- 2. Modern form ID check when CAT_FORM constant exists (positive match only)
    if type(CAT_FORM) == "number" and type(GetShapeshiftFormID) == "function" then
        local formID = GetShapeshiftFormID()
        if not IsSecret(formID) and formID == CAT_FORM then
            return true
        end
    end

    -- 3. Active stance slot spell/icon check (icon, active, castable, spellID)
    if type(GetShapeshiftForm) == "function" and type(GetShapeshiftFormInfo) == "function" then
        local idx = GetShapeshiftForm()
        if not IsSecret(idx) and type(idx) == "number" and idx > 0 then
            local icon, _, _, spellID = GetShapeshiftFormInfo(idx)
            if not IsSecret(spellID) and spellID == CAT_FORM_SPELL_ID then
                return true
            end
            if not IsSecret(icon) then
                if icon == CAT_FORM_ICON_ID then
                    return true
                end
                if type(icon) == "string" and icon:lower():find("catform") then
                    return true
                end
            end
        end
    end

    -- 4. Player aura fallback (Cat Form spell ID 768)
    if C_UnitAuras and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, CAT_FORM_SPELL_ID)
        if ok and aura ~= nil then
            return true
        end
    end

    return false
end

local function ShouldUseComboPoints(db)
    if not db or not db.enabled then
        return false
    end
    local _, liveClass = UnitClass("player")
    if liveClass and not IsSecret(liveClass) then
        playerClass = liveClass
    end
    if testMode then
        return true
    end
    if playerClass == "ROGUE" then
        return true
    end
    if playerClass == "DRUID" then
        return IsDruidInCatForm()
    end
    return false
end

local function GetCurrentComboPoints()
    if testMode then
        return 4
    end
    if GetComboPoints then
        local cp = GetComboPoints("player", "target")
        if IsSecret(cp) or type(cp) == "number" then
            return cp
        end
    end
    return UnitPower("player", POWER_COMBO_POINTS)
end

local function GetNameplateHealthBar(nameplate, unitFrame)
    if unitFrame.healthBar then return unitFrame.healthBar end
    if unitFrame.HealthBar then return unitFrame.HealthBar end
    if unitFrame.HealthBarsContainer then
        if unitFrame.HealthBarsContainer.healthBar then
            return unitFrame.HealthBarsContainer.healthBar
        end
        if unitFrame.HealthBarsContainer.HealthBar then
            return unitFrame.HealthBarsContainer.HealthBar
        end
    end
    if nameplate.healthBar then return nameplate.healthBar end
    return unitFrame
end

local function IsForbiddenFrame(frame)
    return frame and type(frame.IsForbidden) == "function" and frame:IsForbidden()
end

local function IsValidCastBarStatusBar(obj, healthBar)
    if type(obj) ~= "table" or obj == healthBar or IsForbiddenFrame(obj) then
        return false
    end
    if type(obj.IsShown) ~= "function" then
        return false
    end
    if type(obj.GetObjectType) == "function" then
        local okType, objType = pcall(obj.GetObjectType, obj)
        if okType and objType ~= "StatusBar" then
            return false
        end
    end
    return true
end

local function FindNameplateCastBar(nameplate, unitFrame, healthBar)
    local hbc = unitFrame and unitFrame.HealthBarsContainer
    local namedCandidates = {
        { unitFrame and unitFrame.castBar,             "unitFrame.castBar" },
        { unitFrame and unitFrame.CastBar,             "unitFrame.CastBar" },
        { unitFrame and unitFrame.spellBar,            "unitFrame.spellBar" },
        { unitFrame and unitFrame.SpellBar,            "unitFrame.SpellBar" },
        { unitFrame and unitFrame.castingBar,          "unitFrame.castingBar" },
        { unitFrame and unitFrame.CastingBar,          "unitFrame.CastingBar" },
        { unitFrame and unitFrame.castingBarFrame,     "unitFrame.castingBarFrame" },
        { unitFrame and unitFrame.CastingBarFrame,     "unitFrame.CastingBarFrame" },
        { unitFrame and unitFrame.castBarFrame,        "unitFrame.castBarFrame" },
        { unitFrame and unitFrame.CastBarFrame,        "unitFrame.CastBarFrame" },
        { hbc and hbc.castBar,                         "HealthBarsContainer.castBar" },
        { hbc and hbc.CastBar,                         "HealthBarsContainer.CastBar" },
        { nameplate and nameplate.castBar,             "nameplate.castBar" },
        { nameplate and nameplate.CastBar,             "nameplate.CastBar" },
        { nameplate and nameplate.SpellBar,            "nameplate.SpellBar" },
        { nameplate and nameplate.spellBar,            "nameplate.spellBar" },
    }
    for _, entry in ipairs(namedCandidates) do
        if IsValidCastBarStatusBar(entry[1], healthBar) then
            return entry[1], entry[2]
        end
    end

    -- Fallback: scan frame keys without touching geometry, requiring StatusBar type
    for ownerLabel, owner in pairs({ unitFrame = unitFrame, nameplate = nameplate }) do
        if type(owner) == "table" and not IsForbiddenFrame(owner) then
            for key, val in pairs(owner) do
                if type(key) == "string" and IsValidCastBarStatusBar(val, healthBar) then
                    local kl = key:lower()
                    if (kl:find("cast") or kl:find("spellbar"))
                        and not kl:find("container") and not kl:find("holder")
                        and not kl:find("text") and not kl:find("icon")
                        and not kl:find("spark") and not kl:find("flash")
                        and not kl:find("shield") and not kl:find("border")
                        and not kl:find("bg") and not kl:find("back") then
                        return val, ownerLabel .. "." .. key
                    end
                end
            end
        end
    end

    -- Last resort: inspect direct StatusBar children distinct from healthBar
    for ownerLabel, owner in pairs({ unitFrame = unitFrame, nameplate = nameplate }) do
        if owner and not IsForbiddenFrame(owner) and type(owner.GetChildren) == "function" then
            local okCh, children = pcall(function() return { owner:GetChildren() } end)
            if okCh and type(children) == "table" then
                for idx, child in ipairs(children) do
                    if IsValidCastBarStatusBar(child, healthBar) then
                        local okName, cname = pcall(child.GetName, child)
                        local lname = (okName and type(cname) == "string" and not IsSecret(cname)) and cname:lower() or ""
                        if lname:find("cast") or child.Spark or child.Flash or child.BorderShield then
                            return child, ownerLabel .. ":child[" .. idx .. "]"
                        end
                    end
                end
            end
        end
    end

    return nil, "none"
end

local function HasPlainCastInfo(castFn)
    if type(castFn) ~= "function" then
        return false
    end
    local ok, spellName = pcall(castFn, "target")
    if not ok or IsSecret(spellName) then
        return false
    end
    return type(spellName) == "string" and spellName ~= ""
end

local function IsTargetUnitCasting()
    if targetCasting then
        return true
    end
    if HasPlainCastInfo(UnitCastingInfo or CastingInfo) then
        return true
    end
    if HasPlainCastInfo(UnitChannelInfo or ChannelInfo) then
        return true
    end
    return false
end

local function IsCastBarActive(castBar)
    if not castBar or IsForbiddenFrame(castBar) or type(castBar.IsShown) ~= "function" then
        return false
    end
    local okShown, shown = pcall(castBar.IsShown, castBar)
    if okShown and not IsSecret(shown) then
        if not shown then
            return false
        end
        if type(castBar.GetAlpha) == "function" then
            local okAlpha, alpha = pcall(castBar.GetAlpha, castBar)
            if okAlpha and type(alpha) == "number" and not IsSecret(alpha) and alpha <= 0.05 then
                return IsTargetUnitCasting()
            end
        end
        return true
    end
    -- If IsShown() returned a secret boolean (Midnight 12.0 protection), rely on live event/cast state
    return IsTargetUnitCasting()
end

-- Uses pure frame anchoring (no GetBottom/GetRect measurements on restricted nameplate regions)
local function GetSmartBottomAnchor(nameplate, unitFrame, healthBar, db)
    local castExtraDrop = math.max(0, YRG.SafeNumber(db and db.castBarDrop, 6))
    local castBar = FindNameplateCastBar(nameplate, unitFrame, healthBar)
    local now = (type(GetTime) == "function") and GetTime() or 0

    if lastCastAnchorNameplate ~= nameplate then
        targetCastHoldUntil = 0
        wasCastAnchorActive = false
    end

    if castBar then
        local active = IsCastBarActive(castBar)
        if not active and targetCasting and (now - targetCastStartTime) > 0.25 then
            local okShown, shown = pcall(castBar.IsShown, castBar)
            if okShown and not IsSecret(shown) and not shown
                and not HasPlainCastInfo(UnitCastingInfo or CastingInfo)
                and not HasPlainCastInfo(UnitChannelInfo or ChannelInfo) then
                targetCasting = false
            end
        end
        local castingNow = IsTargetUnitCasting()
        if castingNow then
            targetCastHoldUntil = 0
        end
        if active or castingNow then
            wasCastAnchorActive = true
            lastCastAnchorNameplate = nameplate
            if targetCastHoldUntil > 0 and now < targetCastHoldUntil then
                return castBar, castExtraDrop, "CastBar(FadeHold)"
            end
            return castBar, castExtraDrop, "CastBar"
        end
        if wasCastAnchorActive and targetCastHoldUntil == 0 then
            targetCastHoldUntil = now + CASTBAR_FADE_HOLD_SEC
        end
        if targetCastHoldUntil > 0 and now < targetCastHoldUntil then
            return castBar, castExtraDrop, "CastBar(FadeHold)"
        end
        targetCastHoldUntil = 0
        wasCastAnchorActive = false
    elseif IsTargetUnitCasting() then
        targetCastHoldUntil = 0
        wasCastAnchorActive = true
        lastCastAnchorNameplate = nameplate
        return healthBar, 14 + castExtraDrop, "HealthBar+CastDrop"
    else
        if wasCastAnchorActive and targetCastHoldUntil == 0 then
            targetCastHoldUntil = now + CASTBAR_FADE_HOLD_SEC
        end
        if targetCastHoldUntil > 0 and now < targetCastHoldUntil then
            return healthBar, 14 + castExtraDrop, "HealthBar+FadeHold"
        end
        targetCastHoldUntil = 0
        wasCastAnchorActive = false
    end

    if ClassNameplateMechanicFrame and not IsForbiddenFrame(ClassNameplateMechanicFrame) then
        local okShown, shown = pcall(ClassNameplateMechanicFrame.IsShown, ClassNameplateMechanicFrame)
        local okParent, mechanicParent = pcall(ClassNameplateMechanicFrame.GetParent, ClassNameplateMechanicFrame)
        if okShown and not IsSecret(shown) and shown and okParent and (mechanicParent == nameplate or mechanicParent == unitFrame) then
            return ClassNameplateMechanicFrame, 0, "MechanicFrame"
        end
    end

    return healthBar, 0, "HealthBar"
end

function ClassImprovements:EnsureFrames()
    if self.container then return end

    local container = CreateFrame("Frame", "YRGClassComboPointsFrame", UIParent)
    container:SetFrameStrata("HIGH")
    container:SetFrameLevel(20)
    container:Hide()
    self.container = container

    local anchorCheckElapsed = 0
    container:SetScript("OnUpdate", function(_, elapsed)
        anchorCheckElapsed = anchorCheckElapsed + elapsed
        if anchorCheckElapsed < 0.05 then return end
        anchorCheckElapsed = 0

        local db = YRG:GetModuleDB("ClassImprovementsModule")
        if not ShouldUseComboPoints(db) then
            self.container:Hide()
            return
        end
        if db.position ~= "RIGHT" and self._activeNameplate and self._activeUnitFrame and self._activeHealthBar then
            local anchor, drop = GetSmartBottomAnchor(self._activeNameplate, self._activeUnitFrame, self._activeHealthBar, db)
            if anchor ~= lastAnchorTarget or drop ~= lastAnchorExtraDrop then
                self:UpdateTargetNameplate()
            end
        end
    end)

    for i = 1, MAX_COMBO_POINTS do
        local slot = CreateFrame("Frame", nil, container)

        local bg = slot:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(slot)
        bg:SetTexture(TEX_CIRCLE_FILL)
        bg:SetVertexColor(0.06, 0.06, 0.08, 0.88)
        slot.bg = bg

        -- StatusBar handles WoW: Forever secret values natively in C++ via SetMinMaxValues(i-1, i)
        local bar = CreateFrame("StatusBar", nil, slot)
        bar:SetAllPoints(slot)
        bar:SetFrameLevel(slot:GetFrameLevel() + 1)
        bar:SetStatusBarTexture(TEX_CIRCLE_FILL)
        bar:SetMinMaxValues(i - 1, i)
        bar:SetValue(0)

        local c = PIP_COLORS[i]
        bar:SetStatusBarColor(c[1], c[2], c[3], 1.0)
        slot.bar = bar

        -- Outer circular border ring drawn above StatusBar fill
        local ringFrame = CreateFrame("Frame", nil, slot)
        ringFrame:SetAllPoints(slot)
        ringFrame:SetFrameLevel(bar:GetFrameLevel() + 1)
        local ring = ringFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        ring:SetAllPoints(ringFrame)
        ring:SetTexture(TEX_CIRCLE_RING)
        slot.ring = ring

        pips[i] = slot
    end
end

function ClassImprovements:ApplyLayout()
    if not self.container then return end
    local db = YRG:GetModuleDB("ClassImprovementsModule")
    if not db then return end

    local size = math.max(8, YRG.SafeNumber(db.pipSize, 18))
    local gap = math.max(0, YRG.SafeNumber(db.spacing, 3))
    local scale = math.max(0.5, YRG.SafeNumber(db.scale, 1.0))

    self.container:SetScale(scale)

    if db.position == "RIGHT" then
        local totalHeight = (MAX_COMBO_POINTS * size) + ((MAX_COMBO_POINTS - 1) * gap)
        self.container:SetSize(size, totalHeight)
        for i = 1, MAX_COMBO_POINTS do
            local slot = pips[i]
            slot:ClearAllPoints()
            slot:SetSize(size, size)
            if i == 1 then
                slot:SetPoint("BOTTOM", self.container, "BOTTOM", 0, 0)
            else
                slot:SetPoint("BOTTOM", pips[i - 1], "TOP", 0, gap)
            end
        end
    else
        local totalWidth = (MAX_COMBO_POINTS * size) + ((MAX_COMBO_POINTS - 1) * gap)
        self.container:SetSize(totalWidth, size)
        for i = 1, MAX_COMBO_POINTS do
            local slot = pips[i]
            slot:ClearAllPoints()
            slot:SetSize(size, size)
            if i == 1 then
                slot:SetPoint("LEFT", self.container, "LEFT", 0, 0)
            else
                slot:SetPoint("LEFT", pips[i - 1], "RIGHT", gap, 0)
            end
        end
    end
end

function ClassImprovements:UpdateComboPointValues()
    local cp = GetCurrentComboPoints()
    for i = 1, MAX_COMBO_POINTS do
        if pips[i] and pips[i].bar then
            pips[i].bar:SetValue(cp)
        end
    end
end

local function HookDynamicElements(unitFrame, nameplate, healthBar)
    local function OnAnchorElementChanged()
        local mdb = YRG:GetModuleDB("ClassImprovementsModule")
        if mdb and mdb.enabled and ClassImprovements.container and ClassImprovements.container:IsShown() then
            ClassImprovements:UpdateTargetNameplate()
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function()
                    ClassImprovements:UpdateTargetNameplate()
                end)
            end
        end
    end

    local castBar = FindNameplateCastBar(nameplate, unitFrame, healthBar)
    if castBar and not hookedFrames[castBar] then
        hookedFrames[castBar] = true
        pcall(castBar.HookScript, castBar, "OnShow", OnAnchorElementChanged)
        pcall(castBar.HookScript, castBar, "OnHide", OnAnchorElementChanged)
    end

    if ClassNameplateMechanicFrame and not hookedFrames[ClassNameplateMechanicFrame] then
        hookedFrames[ClassNameplateMechanicFrame] = true
        pcall(ClassNameplateMechanicFrame.HookScript, ClassNameplateMechanicFrame, "OnShow", OnAnchorElementChanged)
        pcall(ClassNameplateMechanicFrame.HookScript, ClassNameplateMechanicFrame, "OnHide", OnAnchorElementChanged)
    end
end

function ClassImprovements:UpdateTargetNameplate()
    if not self.container then return end
    local db = YRG:GetModuleDB("ClassImprovementsModule")
    if not ShouldUseComboPoints(db) then
        ClearCastState()
        self._activeNameplate = nil
        self._activeUnitFrame = nil
        self._activeHealthBar = nil
        lastAnchorTarget = nil
        lastAnchorExtraDrop = 0
        self.container:Hide()
        return
    end

    if not UnitExists("target") then
        ClearCastState()
        self._activeNameplate = nil
        self.container:Hide()
        return
    end

    local canAttack = UnitCanAttack("player", "target")
    if not IsSecret(canAttack) and not canAttack and not testMode then
        ClearCastState()
        self._activeNameplate = nil
        self.container:Hide()
        return
    end

    local isDead = UnitIsDead("target")
    if not IsSecret(isDead) and isDead and not testMode then
        ClearCastState()
        self._activeNameplate = nil
        self.container:Hide()
        return
    end

    local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
    if not nameplate or (nameplate.IsForbidden and nameplate:IsForbidden()) then
        self._activeNameplate = nil
        self.container:Hide()
        return
    end

    local unitFrame = nameplate.UnitFrame or nameplate
    local healthBar = GetNameplateHealthBar(nameplate, unitFrame)

    HookDynamicElements(unitFrame, nameplate, healthBar)

    self._activeNameplate = nameplate
    self._activeUnitFrame = unitFrame
    self._activeHealthBar = healthBar

    self.container:SetParent(nameplate)
    self.container:SetFrameStrata("HIGH")
    self.container:ClearAllPoints()

    local offX = YRG.SafeNumber(db.offsetX, 0)
    local offY = YRG.SafeNumber(db.offsetY, -4)
    if db.position == "RIGHT" then
        lastAnchorTarget = healthBar
        lastAnchorExtraDrop = 0
        lastAnchorSource = "HealthBar(Right)"
        self.container:SetPoint("LEFT", healthBar, "RIGHT", 6 + offX, offY)
    else
        local bottomAnchor, extraDrop, anchorSrc = GetSmartBottomAnchor(nameplate, unitFrame, healthBar, db)
        lastAnchorTarget = bottomAnchor
        lastAnchorExtraDrop = extraDrop or 0
        lastAnchorSource = anchorSrc or "HealthBar"
        self.container:SetPoint("TOP", bottomAnchor, "BOTTOM", offX, offY - lastAnchorExtraDrop)
    end

    self:UpdateComboPointValues()
    self.container:Show()
end

function ClassImprovements:OnInitialize(db)
    -- Migrate from previous ComboPoints module key or standalone ForeverComboPlatesDB
    if YRGDB and YRGDB.modules and type(YRGDB.modules.ComboPoints) == "table" then
        local prev = YRGDB.modules.ComboPoints
        for k, v in pairs(prev) do
            if db[k] == nil or k == "enabled" then
                db[k] = v
            end
        end
        YRGDB.modules.ComboPoints = nil
    end

    if not db._migratedFromFCP and type(_G["ForeverComboPlatesDB"]) == "table" then
        local old = _G["ForeverComboPlatesDB"]
        if old.position == "RIGHT" or old.position == "BELOW" then
            db.position = old.position
        end
        if type(old.pipWidth) == "number" and type(old.pipHeight) == "number" then
            db.pipSize = math.max(8, math.min(32, math.floor(((old.pipWidth + old.pipHeight) * 0.5) + 0.5)))
        end
        if type(old.spacing) == "number" then db.spacing = old.spacing end
        if type(old.offsetX) == "number" then db.offsetX = old.offsetX end
        if type(old.offsetY) == "number" then db.offsetY = old.offsetY end
        if type(old.scale) == "number" then db.scale = old.scale end
        db._migratedFromFCP = true
    end

    if not db._castDropRefinedV3 then
        if db.castBarDrop == nil or db.castBarDrop == 14 or db.castBarDrop == 4 then
            db.castBarDrop = 6
        end
        db._castDropRefinedV3 = true
    end

    db.pipSize = math.max(8, math.min(32, math.floor(YRG.SafeNumber(db.pipSize, 18) + 0.5)))

    self:EnsureFrames()

    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:SetScript("OnEvent", function(_, event, arg1)
        local modDB = YRG:GetModuleDB("ClassImprovementsModule")
        if not modDB or not modDB.enabled then return end

        local function DeferredRefresh()
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function()
                    self:UpdateTargetNameplate()
                end)
            end
        end

        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            playerClass = select(2, UnitClass("player"))
            ClearCastState()
            self:ApplyLayout()
            self:UpdateTargetNameplate()
        elseif event == "PLAYER_TARGET_CHANGED"
            or event == "NAME_PLATE_UNIT_ADDED"
            or event == "NAME_PLATE_UNIT_REMOVED" then
            if event == "PLAYER_TARGET_CHANGED" then
                ClearCastState()
            end
            self:UpdateTargetNameplate()
        elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_DISPLAYPOWER" then
            if event == "UPDATE_SHAPESHIFT_FORM" or arg1 == "player" then
                self:UpdateTargetNameplate()
                DeferredRefresh()
            end
        elseif event == "UNIT_AURA" then
            if arg1 == "player" and playerClass == "DRUID" then
                self:UpdateTargetNameplate()
            end
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_COMBO_POINTS" then
            if arg1 == "player" or arg1 == nil then
                if self.container and self.container:IsShown() then
                    self:UpdateComboPointValues()
                else
                    self:UpdateTargetNameplate()
                end
            end
        elseif event == "UNIT_SPELLCAST_START"
            or event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_DELAYED"
            or event == "UNIT_SPELLCAST_INTERRUPTED"
            or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_SUCCEEDED"
            or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            local matchesTarget = (arg1 == "target")
            if not matchesTarget and arg1 ~= "player" and type(arg1) == "string" and UnitExists("target") and UnitIsUnit then
                local okU, same = pcall(UnitIsUnit, arg1, "target")
                if okU and not IsSecret(same) and same then
                    matchesTarget = true
                end
            end
            if matchesTarget then
                local now = (type(GetTime) == "function") and GetTime() or 0
                if event == "UNIT_SPELLCAST_START"
                    or event == "UNIT_SPELLCAST_DELAYED"
                    or event == "UNIT_SPELLCAST_CHANNEL_START"
                    or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
                    targetCasting = true
                    targetCastStartTime = now
                    targetCastHoldUntil = 0
                else
                    if (targetCasting or wasCastAnchorActive) and targetCastHoldUntil == 0 then
                        targetCastHoldUntil = now + CASTBAR_FADE_HOLD_SEC
                    end
                    targetCasting = false
                end
                self:UpdateTargetNameplate()
                DeferredRefresh()
            end
        end
    end)
end

function ClassImprovements:OnEnable(db)
    self:EnsureFrames()
    playerClass = select(2, UnitClass("player"))

    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    self.eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    self.eventFrame:RegisterEvent("UNIT_POWER_FREQUENT")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "UNIT_COMBO_POINTS")
    self.eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
    self.eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    self.eventFrame:RegisterEvent("UNIT_AURA")
    self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "UNIT_SPELLCAST_SUCCEEDED")
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

    self:ApplyLayout()
    self:UpdateTargetNameplate()
    self:UpdateDruidManaBar()
end

-- ============================================================================
-- DRUID FORM SECONDARY MANA BAR (Bear / Cat Form on PlayerFrame)
-- ============================================================================
local function GetDruidManaPercent()
    if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local okPct, pct = pcall(UnitPowerPercent, "player", POWER_MANA, false, CurveConstants.ScaleTo100)
        if okPct then
            return pct
        end
    end
    local cur = UnitPower("player", POWER_MANA)
    local max = UnitPowerMax("player", POWER_MANA)
    if IsSecret(cur) or IsSecret(max) or type(cur) ~= "number" or type(max) ~= "number" then
        return nil
    end
    if max > 0 then
        return (cur / max) * 100
    end
    return 0
end

function ClassImprovements:SetDruidPlayerFrameArt(showBar)
    local manaBar = PlayerFrame_GetManaBar and PlayerFrame_GetManaBar()
    local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
    if not PlayerFrame or not container or not container.AlternatePowerFrameTexture then
        return
    end
    if PlayerFrame.state == "vehicle" or PlayerFrame.activeAlternatePowerBar or UNIT_FRAME_SHOW_HEALTH_ONLY then
        return
    end

    local useAtlasSize = (TextureKitConstants and TextureKitConstants.UseAtlasSize) or true
    if showBar then
        if container.FrameTexture then container.FrameTexture:Hide() end
        container.AlternatePowerFrameTexture:Show()
        if container.FrameFlash then
            container.FrameFlash:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-ClassResource-InCombat", useAtlasSize)
            container.FrameFlash:ClearAllPoints()
            container.FrameFlash:SetPoint("CENTER", container, "CENTER", -2, 0.5)
        end
        if manaBar and manaBar.ManaBarMask then
            manaBar.ManaBarMask:SetAtlas("Unit_BarMask", useAtlasSize)
        end
        self._druidAltArtApplied = true
    elseif self._druidAltArtApplied then
        container.AlternatePowerFrameTexture:Hide()
        if container.FrameTexture then container.FrameTexture:Show() end
        if container.FrameFlash then
            container.FrameFlash:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-InCombat", useAtlasSize)
            container.FrameFlash:ClearAllPoints()
            container.FrameFlash:SetPoint("CENTER", container, "CENTER", -1.5, 1)
        end
        if manaBar and manaBar.ManaBarMask then
            manaBar.ManaBarMask:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", useAtlasSize)
        end
        self._druidAltArtApplied = false
    end
end

function ClassImprovements:UpdateDruidManaText()
    local bar = self.druidManaBar
    if not bar then return end

    local mode = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("statusTextDisplay")
    if not mode and GetCVar then
        mode = GetCVar("statusTextDisplay")
    end
    if not mode then
        local st = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("statusText")) or (GetCVar and GetCVar("statusText"))
        mode = (st == "1") and "NUMERIC" or "NONE"
    end
    if mode == "NONE" and bar._isMouseOver then
        mode = "NUMERIC"
    end

    bar.TextString:Hide()
    bar.LeftText:Hide()
    bar.RightText:Hide()

    if mode == "NUMERIC" then
        bar.TextString:SetFormattedText("%s / %s", UnitPower("player", POWER_MANA), UnitPowerMax("player", POWER_MANA))
        bar.TextString:Show()
    elseif mode == "PERCENT" then
        local percent = GetDruidManaPercent()
        if percent ~= nil then
            bar.TextString:SetFormattedText("%.0f%%", percent)
            bar.TextString:Show()
        end
    elseif mode == "BOTH" then
        local percent = GetDruidManaPercent()
        if percent ~= nil then
            bar.LeftText:SetFormattedText("%.0f%%", percent)
            bar.LeftText:Show()
        end
        bar.RightText:SetFormattedText("%s", UnitPower("player", POWER_MANA))
        bar.RightText:Show()
    end
end

function ClassImprovements:UpdateDruidManaValue()
    local bar = self.druidManaBar
    if not bar then return end
    bar:SetMinMaxValues(0, UnitPowerMax("player", POWER_MANA))
    bar:SetValue(UnitPower("player", POWER_MANA))
    self:UpdateDruidManaText()
end

function ClassImprovements:EnsureDruidManaBar()
    if self.druidManaBar then
        return self.druidManaBar
    end

    local _, liveClass = UnitClass("player")
    if not IsSecret(liveClass) and liveClass then
        playerClass = liveClass
    end
    if playerClass ~= "DRUID" then
        return nil
    end

    local manaBar = PlayerFrame_GetManaBar and PlayerFrame_GetManaBar()
    local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
    if not PlayerFrame or not manaBar or not container or not container.AlternatePowerFrameTexture then
        return nil
    end

    local barWidth = math.max(1, YRG.SafeNumber(manaBar.GetWidth and manaBar:GetWidth(), 124))
    local barHeight = math.max(1, YRG.SafeNumber(manaBar.GetHeight and manaBar:GetHeight(), 10))

    local bar = CreateFrame("StatusBar", "YRGClassDruidManaBar", PlayerFrame)
    bar:SetPoint("TOPLEFT", manaBar, "BOTTOMLEFT", 0, -1)
    bar:SetSize(barWidth, barHeight)
    bar:SetFrameLevel((manaBar.GetFrameLevel and manaBar:GetFrameLevel() or 1) + 1)
    bar:SetStatusBarTexture("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana")
    bar:Hide()

    local barTexture = bar:GetStatusBarTexture()
    if barTexture then
        if barTexture.SetTexelSnappingBias then
            barTexture:SetTexelSnappingBias(0)
        end
        if barTexture.SetSnapToPixelGrid then
            barTexture:SetSnapToPixelGrid(false)
        end
        if bar.CreateMaskTexture and barTexture.AddMaskTexture then
            bar.Mask = bar:CreateMaskTexture()
            local useAtlasSize = (TextureKitConstants and TextureKitConstants.UseAtlasSize) or true
            bar.Mask:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", useAtlasSize)
            bar.Mask:SetPoint("TOPLEFT", -2, 2)
            barTexture:AddMaskTexture(bar.Mask)
        end
    end

    bar.TextString = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    bar.TextString:SetPoint("CENTER")

    bar.LeftText = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    bar.LeftText:SetPoint("LEFT", 2, 0)

    bar.RightText = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    bar.RightText:SetPoint("RIGHT", -2, 0)

    bar._isMouseOver = false
    bar:SetMouseMotionEnabled(true)
    bar:SetMouseClickEnabled(false)
    bar:SetScript("OnEnter", function(f)
        f._isMouseOver = true
        self:UpdateDruidManaText()
    end)
    bar:SetScript("OnLeave", function(f)
        f._isMouseOver = false
        self:UpdateDruidManaText()
    end)

    bar:SetScript("OnEvent", function(_, event)
        local modDB = YRG:GetModuleDB("ClassImprovementsModule")
        if not modDB or not modDB.enabled or modDB.showDruidManaBar == false then
            return
        end
        if event == "PLAYER_ENTERING_WORLD" or event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then
            self:UpdateDruidManaBar()
        elseif bar:IsShown() then
            self:UpdateDruidManaValue()
        end
    end)

    if PlayerFrame_ToPlayerArt and not self._druidPlayerArtHooked then
        self._druidPlayerArtHooked = true
        hooksecurefunc("PlayerFrame_ToPlayerArt", function()
            local modDB = YRG:GetModuleDB("ClassImprovementsModule")
            if modDB and modDB.enabled and modDB.showDruidManaBar ~= false then
                self:UpdateDruidManaBar()
            end
        end)
    end

    self.druidManaBar = bar
    return bar
end

function ClassImprovements:RegisterDruidManaEvents(enable)
    local bar = self.druidManaBar
    if not bar then return end
    bar:UnregisterAllEvents()
    if enable then
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")
        bar:RegisterEvent("CVAR_UPDATE")
        bar:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        if bar.RegisterUnitEvent then
            bar:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
            bar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
            bar:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        else
            bar:RegisterEvent("UNIT_DISPLAYPOWER")
            bar:RegisterEvent("UNIT_MAXPOWER")
            bar:RegisterEvent("UNIT_POWER_FREQUENT")
        end
    end
end

function ClassImprovements:UpdateDruidManaBar()
    local db = YRG:GetModuleDB("ClassImprovementsModule")
    local _, liveClass = UnitClass("player")
    if not IsSecret(liveClass) and liveClass then
        playerClass = liveClass
    end

    local enabled = db and db.enabled and (db.showDruidManaBar ~= false) and (playerClass == "DRUID")
    if not enabled then
        if self.druidManaBar then
            self:RegisterDruidManaEvents(false)
            self.druidManaBar:Hide()
        end
        self:SetDruidPlayerFrameArt(false)
        return
    end

    local bar = self:EnsureDruidManaBar()
    if not bar then return end

    self:RegisterDruidManaEvents(true)

    local manaBar = PlayerFrame_GetManaBar and PlayerFrame_GetManaBar()
    if manaBar then
        local w = YRG.SafeOptionalNumber(manaBar.GetWidth and manaBar:GetWidth())
        local h = YRG.SafeOptionalNumber(manaBar.GetHeight and manaBar:GetHeight())
        if w and h and w > 0 and h > 0 then
            bar:SetSize(w, h)
        end
    end

    local powerType, powerToken = UnitPowerType("player")
    local inAltForm = (not IsSecret(powerType) and (powerType == POWER_RAGE or powerType == POWER_ENERGY))
        or (not IsSecret(powerToken) and (powerToken == "RAGE" or powerToken == "ENERGY"))
    local show = inAltForm and (not PlayerFrame or PlayerFrame.state ~= "vehicle") and true or false

    if show then
        self:UpdateDruidManaValue()
    end
    bar:SetShown(show)
    self:SetDruidPlayerFrameArt(show)
end

function ClassImprovements:OnDisable(db)
    testMode = false
    ClearCastState()
    self._activeNameplate = nil
    self._activeUnitFrame = nil
    self._activeHealthBar = nil
    lastAnchorTarget = nil
    lastAnchorExtraDrop = 0
    lastAnchorSource = "None"
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    if self.container then
        self.container:Hide()
        self.container:SetParent(UIParent)
        self.container:ClearAllPoints()
    end
    if self.druidManaBar then
        self:RegisterDruidManaEvents(false)
        self.druidManaBar:Hide()
    end
    self:SetDruidPlayerFrameArt(false)
end

function ClassImprovements:BuildConfigUI(ctx, db)
    local function GetDB()
        return YRG:GetModuleDB("ClassImprovementsModule")
    end

    local function PrintLiveDiagnostics()
        local mdb = GetDB()
        local _, liveClass = UnitClass("player")
        local cls = (not IsSecret(liveClass) and liveClass) or playerClass or "?"
        local pType, pToken = UnitPowerType("player")
        local pStr = IsSecret(pType) and "secret" or tostring(pType)
        if not IsSecret(pToken) and type(pToken) == "string" then
            pStr = pStr .. " (" .. pToken .. ")"
        end
        local catStr = (cls == "DRUID") and (IsDruidInCatForm() and "Yes" or "No") or "N/A"
        local activeStr = ShouldUseComboPoints(mdb) and "|cff44ff44Active|r" or "|cffff6666Hidden|r"

        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
        local castInfo = "No target nameplate"
        if np and not (np.IsForbidden and np:IsForbidden()) then
            local uf = np.UnitFrame or np
            local hb = GetNameplateHealthBar(np, uf)
            local cb, cbSrc = FindNameplateCastBar(np, uf, hb)
            local castingNow = IsTargetUnitCasting() and "Yes" or "No"
            if cb then
                local cbState = IsCastBarActive(cb) and "Shown" or "Idle"
                castInfo = string.format("%s (%s) | Casting: %s", tostring(cbSrc), cbState, castingNow)
            else
                castInfo = string.format("Not found | Casting: %s", castingNow)
            end
        end
        print(string.format(
            "|cffffd100YRG ClassImprovements:|r %s | Class: %s | Power: %s | Cat Form: %s | Anchor: %s (drop %d) | CastBar: %s",
            activeStr, tostring(cls), pStr, catStr, tostring(lastAnchorSource), tonumber(lastAnchorExtraDrop or 0), castInfo
        ))
    end

    ctx:AddHeader("1. Druid Class Bars")

    ctx:AddCheckbox({
        key = "showDruidManaBar",
        name = "Show Mana Bar in Bear / Cat Form",
        tooltip = "Displays a secondary Mana bar underneath Rage or Energy on the Player Frame when shifted into Bear or Cat Form (modeled after Leatrix Plus).",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showDruidManaBar ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showDruidManaBar = val end
            self:UpdateDruidManaBar()
        end,
    })

    ctx:AddHeader(
        "2. Nameplate Combo Points (Circle Pips)",
        "Displays 5 circular combo point pips on your targeted enemy nameplate for Rogues and Cat Form Druids (auto-hides for all other classes/forms). Automatically drops below active enemy cast bars."
    )

    ctx:AddButton({
        name = "Nameplate & CastBar Diagnostics",
        buttonText = "Check Status",
        tooltip = "Prints current class/form/power state, active nameplate anchor, and target cast bar detection to chat (same as /yrgcast).",
        onClick = PrintLiveDiagnostics,
    })

    ctx:AddDropdown({
        key = "position",
        name = "Anchor Position",
        tooltip = "Choose whether circular combo point pips sit below the target nameplate (cast-bar aware) or to the right of the health bar.",
        defaultValue = "BELOW",
        options = POSITION_OPTIONS,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.position) or "BELOW"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.position = (val == "RIGHT") and "RIGHT" or "BELOW"
            end
            self:ApplyLayout()
            self:UpdateTargetNameplate()
        end,
    })

    ctx:AddCheckbox({
        key = "testMode",
        name = "Test Preview (4/5 Pips on Target)",
        tooltip = "Temporarily previews 4 filled combo point circles on any targeted nameplate so you can tune size, spacing, and offsets.",
        defaultValue = false,
        get = function() return testMode and true or false end,
        set = function(val)
            testMode = val and true or false
            self:ApplyLayout()
            self:UpdateTargetNameplate()
        end,
    })

    local function AddModuleSlider(label, tooltip, minVal, maxVal, step, key, defaultVal, roundToInt, formatFn)
        ctx:AddSlider({
            key = key,
            name = label,
            tooltip = tooltip,
            min = minVal, max = maxVal, step = step, defaultValue = defaultVal,
            format = formatFn,
            roundFn = function(val)
                if roundToInt then
                    local r = math.floor(val + 0.5)
                    if r == 0 then r = 0 end
                    return r
                end
                return math.floor(val * 100 + 0.5) / 100
            end,
            get = function()
                local mdb = GetDB()
                if mdb and mdb[key] ~= nil then
                    return mdb[key]
                end
                return defaultVal
            end,
            set = function(val)
                local mdb = GetDB()
                if mdb then mdb[key] = val end
                self:ApplyLayout()
                self:UpdateTargetNameplate()
            end,
        })
    end

    AddModuleSlider("Circle Size (px)", "Diameter of each circular combo point pip.", 8, 32, 1, "pipSize", 18, true, function(v) return string.format("%d px", v) end)
    AddModuleSlider("Pip Spacing (px)", "Horizontal gap between adjacent combo point pips.", 0, 12, 1, "spacing", 3, true, function(v) return string.format("%d px", v) end)
    AddModuleSlider("Combo Points Scale", "Overall scale multiplier for the nameplate combo point container.", 0.50, 2.50, 0.05, "scale", 1.0, false, function(v) return string.format("%.2f", v) end)
    AddModuleSlider("Horizontal Offset (X)", "Horizontal fine offset relative to the target nameplate anchor.", -60, 60, 1, "offsetX", 0, true, function(v) return string.format("%d px", v) end)
    AddModuleSlider("Vertical Offset (Y)", "Vertical fine offset relative to the target nameplate anchor.", -60, 60, 1, "offsetY", -4, true, function(v) return string.format("%d px", v) end)
    AddModuleSlider("CastBar Extra Drop (px)", "Additional downward spacing beneath an active enemy cast bar.", 0, 32, 1, "castBarDrop", 6, true, function(v) return string.format("%d px", v) end)

    ctx:AddButton({
        name = "Reset Combo Point & Class Bar Settings",
        buttonText = "Reset Defaults",
        tooltip = "Restores all ClassImprovementsModule settings back to their default values.",
        onClick = function()
            local mdb = GetDB()
            if mdb then
                for k, v in pairs(self.defaults) do
                    if k ~= "enabled" then
                        mdb[k] = v
                    end
                end
            end
            testMode = false
            ctx:NotifyAll()
            self:ApplyLayout()
            self:UpdateTargetNameplate()
            self:UpdateDruidManaBar()
        end,
    })
end

SLASH_YRGCAST1 = "/yrgcast"
SlashCmdList["YRGCAST"] = function()
    local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
    if not np or IsForbiddenFrame(np) then
        print("|cffffd100YRG CastDebug:|r No target nameplate (target an enemy with nameplates on).")
        return
    end
    local uf = np.UnitFrame or np
    local hb = GetNameplateHealthBar(np, uf)
    local cb, cbSrc = FindNameplateCastBar(np, uf, hb)
    local okCast, castVal = false, nil
    if UnitCastingInfo then
        okCast, castVal = pcall(UnitCastingInfo, "target")
    end
    local rawStr = "nil"
    if okCast then
        if IsSecret(castVal) then
            rawStr = "secret(" .. type(castVal) .. ")"
        elseif castVal ~= nil then
            rawStr = type(castVal) .. ":" .. tostring(castVal)
        end
    else
        rawStr = "err"
    end
    local cbStr = "none"
    if cb then
        local okS, s = pcall(cb.IsShown, cb)
        local okA, a = pcall(cb.GetAlpha, cb)
        local sStr = IsSecret(s) and "secret" or tostring(s)
        local aStr = IsSecret(a) and "secret" or tostring(a)
        cbStr = string.format("%s shown=%s alpha=%s", tostring(cbSrc), sStr, aStr)
    end
    print(string.format("|cffffd100YRG CastDebug:|r anchor=%s drop=%s targetCasting=%s UnitCastingInfo=%s | cb=[%s]",
        tostring(lastAnchorSource), tostring(lastAnchorExtraDrop), tostring(targetCasting), rawStr, cbStr))
end

YRG:RegisterModule("ClassImprovementsModule", ClassImprovements)
