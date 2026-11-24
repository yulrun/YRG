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

local DEFAULT_OB_PREP_ELIXIRS = {
    "Elixir of Minor Defense",
    "Elixir of Minor Strength",
}

local ClassImprovements = {
    name = "ClassImprovementsModule",
    description = "Class UI enhancements including circular nameplate combo points (Rogues/Cat Form), Druid form Mana bar, OB Prep (One-Button Prep), and Hunter Pet AutoFeeder.",
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
        obPrepMainHand = "INSTANT_BEST",
        obPrepOffHand = "INSTANT_BEST",
        obPrepUseStones = true,
        obPrepUseWizardOils = false,
        obPrepWeaponOverbuffMinutes = 5,
        obPrepAutoSelfBuff = true,
        obPrepBuffOverbuffMinutes = 5,
        obPrepUseFoodBuff = true,
        obPrepFoodName = "Longjaw Mud Snapper",
        obPrepUseElixirs = true,
        obPrepElixirList = {},
        obPrepOverrideBuffs = false,
        obPrepOverrideBuffsCSV = "",
        petFeederEnabled = true,
        petFeederIgnoreCrafted = true,
        petFeederBlacklist = {},
        hunterBetterPartyMember = true,
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

local function HasPlainCastInfo(castFn, unit)
    if type(castFn) ~= "function" then
        return false
    end
    local ok, spellName = pcall(castFn, unit or "target")
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

local EnsureRoguePrepButtons
local EnsureRoguePrepMacro
local HandleReplaceEnchantEvent
local HandlePrepUIError
local HandlePrepUnitSpellcast
local HandlePrepStateInvalidation
local PetFeeder = {}
local BetterParty = {}

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

    -- Migrate previous roguePrep* settings into obPrep* seamlessly
    if db.roguePrepMainHand ~= nil and (db.obPrepMainHand == nil or db.obPrepMainHand == "NONE") then
        db.obPrepMainHand = db.roguePrepMainHand
    end
    if db.roguePrepOffHand ~= nil and (db.obPrepOffHand == nil or db.obPrepOffHand == "NONE") then
        db.obPrepOffHand = db.roguePrepOffHand
    end
    if db.roguePrepUseStones ~= nil and not db._migratedRoguePrepV2 then
        db.obPrepUseStones = db.roguePrepUseStones
    end
    if db.roguePrepOverbuffMinutes ~= nil and not db._migratedRoguePrepV2 then
        db.obPrepWeaponOverbuffMinutes = db.roguePrepOverbuffMinutes
    end
    db._migratedRoguePrepV2 = true

    if type(db.obPrepElixirList) ~= "table" then
        db.obPrepElixirList = {}
    end
    if not db._initializedDefaultElixirsV1 then
        db._initializedDefaultElixirsV1 = true
        if #db.obPrepElixirList == 0 then
            for _, itemName in ipairs(DEFAULT_OB_PREP_ELIXIRS) do
                table.insert(db.obPrepElixirList, itemName)
            end
        end
    end

    if type(db.petFeederBlacklist) ~= "table" then
        db.petFeederBlacklist = {}
    end

    db.pipSize = math.max(8, math.min(32, math.floor(YRG.SafeNumber(db.pipSize, 18) + 0.5)))
    db.obPrepWeaponOverbuffMinutes = math.max(0, math.min(30, math.floor(YRG.SafeNumber(db.obPrepWeaponOverbuffMinutes, 5) + 0.5)))
    db.obPrepBuffOverbuffMinutes = math.max(0, math.min(30, math.floor(YRG.SafeNumber(db.obPrepBuffOverbuffMinutes, 5) + 0.5)))

    self:EnsureFrames()
    if EnsureRoguePrepButtons then
        EnsureRoguePrepButtons()
    end
    if PetFeeder.EnsureUI then
        PetFeeder.EnsureUI()
    end

    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
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
            if EnsureRoguePrepMacro then
                EnsureRoguePrepMacro(false, false)
            end
            if HandlePrepStateInvalidation then
                HandlePrepStateInvalidation(event)
            end
            if PetFeeder.OnEvent then
                PetFeeder.OnEvent(event, arg1, arg2, arg3)
            end
            if BetterParty.OnEvent then
                BetterParty.OnEvent(event, arg1, arg2)
            end
        elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PET_BAR_UPDATE" then
            if BetterParty.OnEvent then
                BetterParty.OnEvent(event, arg1, arg2)
            end
        elseif event == "UPDATE_MACROS" then
            if EnsureRoguePrepMacro then
                EnsureRoguePrepMacro(false, false)
            end
            if PetFeeder.OnEvent then
                PetFeeder.OnEvent(event, arg1, arg2, arg3)
            end
        elseif event == "REPLACE_ENCHANT" then
            if HandleReplaceEnchantEvent then
                HandleReplaceEnchantEvent()
            end
        elseif event == "UI_ERROR_MESSAGE" then
            if HandlePrepUIError then
                HandlePrepUIError(arg1, arg2)
            end
            if PetFeeder.OnEvent then
                PetFeeder.OnEvent(event, arg1, arg2, arg3)
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" or event == "UNIT_INVENTORY_CHANGED" then
            if event ~= "UNIT_INVENTORY_CHANGED" or arg1 == "player" then
                if HandlePrepStateInvalidation then
                    HandlePrepStateInvalidation(event)
                end
                if PetFeeder.OnEvent then
                    PetFeeder.OnEvent(event, arg1, arg2, arg3)
                end
            end
        elseif event == "UNIT_PET" or event == "PET_UI_UPDATE" or event == "UNIT_HAPPINESS"
            or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED"
            or event == "EDIT_MODE_LAYOUTS_UPDATED" or event == "UNIT_LEVEL" or event == "PLAYER_LEVEL_UP" then
            if PetFeeder.OnEvent then
                PetFeeder.OnEvent(event, arg1, arg2, arg3)
            end
            if BetterParty.OnEvent and (event == "UNIT_PET" or event == "PET_BAR_UPDATE" or event == "PLAYER_REGEN_ENABLED") then
                BetterParty.OnEvent(event, arg1, arg2)
            end
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
                if event == "UPDATE_SHAPESHIFT_FORM" and HandlePrepStateInvalidation then
                    HandlePrepStateInvalidation(event)
                end
            end
        elseif event == "UNIT_AURA" then
            if arg1 == "player" then
                if playerClass == "DRUID" then
                    self:UpdateTargetNameplate()
                end
                if HandlePrepStateInvalidation then
                    HandlePrepStateInvalidation(event)
                end
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
            if arg1 == "player" then
                if HandlePrepUnitSpellcast then
                    HandlePrepUnitSpellcast(event, arg3)
                end
                if PetFeeder.OnEvent then
                    PetFeeder.OnEvent(event, arg1, arg2, arg3)
                end
            end
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
    if EnsureRoguePrepButtons then
        EnsureRoguePrepButtons()
    end
    if PetFeeder.EnsureUI then
        PetFeeder.EnsureUI()
    end
    playerClass = select(2, UnitClass("player"))

    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "ZONE_CHANGED_NEW_AREA")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "PET_BAR_UPDATE")
    self.eventFrame:RegisterEvent("UPDATE_MACROS")
    self.eventFrame:RegisterEvent("REPLACE_ENCHANT")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "UI_ERROR_MESSAGE")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "BAG_UPDATE_DELAYED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "PLAYER_EQUIPMENT_CHANGED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "UNIT_INVENTORY_CHANGED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "UNIT_PET")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "PET_UI_UPDATE")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "UNIT_HAPPINESS")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "PLAYER_REGEN_ENABLED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "PLAYER_REGEN_DISABLED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "EDIT_MODE_LAYOUTS_UPDATED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "UNIT_LEVEL")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "PLAYER_LEVEL_UP")
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
    if PetFeeder.OnEnable then
        PetFeeder.OnEnable()
    end
    if BetterParty.OnEnable then
        BetterParty.OnEnable()
    end
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
    if HandlePrepStateInvalidation then
        HandlePrepStateInvalidation("DISABLE")
    end
    if PetFeeder.OnDisable then
        PetFeeder.OnDisable()
    end
    if BetterParty.OnDisable then
        BetterParty.OnDisable()
    end
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

-- ============================================================================
-- OB PREP — ONE-BUTTON PREP (Poisons, Weapon Stones/Oils, Food, Elixirs, Buffs)
-- ============================================================================
local OB_PREP_MACRO_NAME = "YRGOBP"
local OB_PREP_MACRO_BODY = "/yrgobprep\n/click YRGOBPrepButton LeftButton 1\n/click YRGOBPrepButton LeftButton 0\n/click YRGOBPrepConfirm LeftButton 1\n/click YRGOBPrepConfirm LeftButton 0"
local ROGUE_PREP_MACRO_NAME = "YRGRP"
local ROGUE_PREP_LEGACY_BODIES = {
    ["/yrgrogueprep\n/click YRGRoguePrepButton"] = true,
    ["/yrgrogueprep\n/click YRGRoguePrepButton LeftButton 1\n/click YRGRoguePrepButton LeftButton 0"] = true,
    ["/yrgrogueprep\n/click YRGRoguePrepButton LeftButton 1\n/click YRGRoguePrepButton LeftButton 0\n/click YRGRoguePrepConfirm LeftButton 1\n/click YRGRoguePrepConfirm LeftButton 0"] = true,
}
local INV_SLOT_MAINHAND = INVSLOT_MAINHAND or 16
local INV_SLOT_OFFHAND = INVSLOT_OFFHAND or 17

local ROMAN_TO_NUM = {
    [""] = 1, ["i"] = 1, ["ii"] = 2, ["iii"] = 3, ["iv"] = 4, ["v"] = 5,
    ["vi"] = 6, ["vii"] = 7, ["viii"] = 8, ["ix"] = 9, ["x"] = 10,
}

local POISON_FAMILIES = {
    INSTANT = { key = "INSTANT", prefix = "instant poison", label = "Instant Poison" },
    DEADLY = { key = "DEADLY", prefix = "deadly poison", label = "Deadly Poison" },
    CRIPPLING = { key = "CRIPPLING", prefix = "crippling poison", label = "Crippling Poison" },
    MINDNUMBING = { key = "MINDNUMBING", prefix = "mind-numbing poison", label = "Mind-numbing Poison" },
    WOUND = { key = "WOUND", prefix = "wound poison", label = "Wound Poison" },
}

local POISON_ITEM_BY_ID = {
    [6947]  = { family = "INSTANT",     rank = 1, name = "Instant Poison" },
    [6949]  = { family = "INSTANT",     rank = 2, name = "Instant Poison II" },
    [6950]  = { family = "INSTANT",     rank = 3, name = "Instant Poison III" },
    [8926]  = { family = "INSTANT",     rank = 4, name = "Instant Poison IV" },
    [8927]  = { family = "INSTANT",     rank = 5, name = "Instant Poison V" },
    [8928]  = { family = "INSTANT",     rank = 6, name = "Instant Poison VI" },
    [2892]  = { family = "DEADLY",      rank = 1, name = "Deadly Poison" },
    [2893]  = { family = "DEADLY",      rank = 2, name = "Deadly Poison II" },
    [8984]  = { family = "DEADLY",      rank = 3, name = "Deadly Poison III" },
    [8985]  = { family = "DEADLY",      rank = 4, name = "Deadly Poison IV" },
    [20844] = { family = "DEADLY",      rank = 5, name = "Deadly Poison V" },
    [3775]  = { family = "CRIPPLING",   rank = 1, name = "Crippling Poison" },
    [3776]  = { family = "CRIPPLING",   rank = 2, name = "Crippling Poison II" },
    [5237]  = { family = "MINDNUMBING", rank = 1, name = "Mind-numbing Poison" },
    [6951]  = { family = "MINDNUMBING", rank = 2, name = "Mind-numbing Poison II" },
    [9186]  = { family = "MINDNUMBING", rank = 3, name = "Mind-numbing Poison III" },
    [10918] = { family = "WOUND",       rank = 1, name = "Wound Poison" },
    [10920] = { family = "WOUND",       rank = 2, name = "Wound Poison II" },
    [10921] = { family = "WOUND",       rank = 3, name = "Wound Poison III" },
    [10922] = { family = "WOUND",       rank = 4, name = "Wound Poison IV" },
}

local POISON_DROPDOWN_OPTIONS = {
    { label = "None (Disabled)",                    value = "NONE" },
    { label = "Instant Poison (Best in Bags)",      value = "INSTANT_BEST" },
    { label = "Deadly Poison (Best in Bags)",       value = "DEADLY_BEST" },
    { label = "Crippling Poison (Best in Bags)",    value = "CRIPPLING_BEST" },
    { label = "Mind-numbing Poison (Best in Bags)", value = "MINDNUMBING_BEST" },
    { label = "Wound Poison (Best in Bags)",        value = "WOUND_BEST" },
    { label = "Instant Poison I",                   value = "INSTANT_1" },
    { label = "Instant Poison II",                  value = "INSTANT_2" },
    { label = "Instant Poison III",                 value = "INSTANT_3" },
    { label = "Instant Poison IV",                  value = "INSTANT_4" },
    { label = "Instant Poison V",                   value = "INSTANT_5" },
    { label = "Instant Poison VI",                  value = "INSTANT_6" },
    { label = "Deadly Poison I",                    value = "DEADLY_1" },
    { label = "Deadly Poison II",                   value = "DEADLY_2" },
    { label = "Deadly Poison III",                  value = "DEADLY_3" },
    { label = "Deadly Poison IV",                   value = "DEADLY_4" },
    { label = "Deadly Poison V",                    value = "DEADLY_5" },
    { label = "Crippling Poison I",                 value = "CRIPPLING_1" },
    { label = "Crippling Poison II",                value = "CRIPPLING_2" },
    { label = "Mind-numbing Poison I",              value = "MINDNUMBING_1" },
    { label = "Mind-numbing Poison II",             value = "MINDNUMBING_2" },
    { label = "Mind-numbing Poison III",            value = "MINDNUMBING_3" },
    { label = "Wound Poison I",                     value = "WOUND_1" },
    { label = "Wound Poison II",                    value = "WOUND_2" },
    { label = "Wound Poison III",                   value = "WOUND_3" },
    { label = "Wound Poison IV",                    value = "WOUND_4" },
}

local VALID_POISON_SELECTIONS = {}
for _, opt in ipairs(POISON_DROPDOWN_OPTIONS) do
    VALID_POISON_SELECTIONS[opt.value] = true
end

local STONE_ITEM_BY_ID = {
    [2862]  = { kind = "SHARP", tier = 10, name = "Rough Sharpening Stone" },
    [2863]  = { kind = "SHARP", tier = 20, name = "Coarse Sharpening Stone" },
    [2871]  = { kind = "SHARP", tier = 30, name = "Heavy Sharpening Stone" },
    [7964]  = { kind = "SHARP", tier = 40, name = "Solid Sharpening Stone" },
    [23122] = { kind = "SHARP", tier = 45, name = "Consecrated Sharpening Stone" },
    [12404] = { kind = "SHARP", tier = 50, name = "Dense Sharpening Stone" },
    [18262] = { kind = "SHARP", tier = 60, name = "Elemental Sharpening Stone" },
    [3239]  = { kind = "BLUNT", tier = 10, name = "Rough Weightstone" },
    [3240]  = { kind = "BLUNT", tier = 20, name = "Coarse Weightstone" },
    [3241]  = { kind = "BLUNT", tier = 30, name = "Heavy Weightstone" },
    [7965]  = { kind = "BLUNT", tier = 40, name = "Solid Weightstone" },
    [12643] = { kind = "BLUNT", tier = 50, name = "Dense Weightstone" },
}

local OIL_ITEM_BY_ID = {
    [20745] = { kind = "OIL", tier = 25,  name = "Minor Mana Oil" },
    [20747] = { kind = "OIL", tier = 45,  name = "Lesser Mana Oil" },
    [20748] = { kind = "OIL", tier = 65,  name = "Brilliant Mana Oil" },
    [20744] = { kind = "OIL", tier = 110, name = "Minor Wizard Oil" },
    [20746] = { kind = "OIL", tier = 120, name = "Lesser Wizard Oil" },
    [20750] = { kind = "OIL", tier = 130, name = "Wizard Oil" },
    [20749] = { kind = "OIL", tier = 140, name = "Brilliant Wizard Oil" },
}

local SHARP_SUBCLASSES = {}
local BLUNT_SUBCLASSES = {}
do
    local ws = Enum and Enum.ItemWeaponSubclass
    SHARP_SUBCLASSES[(ws and ws.Axe1H) or 0] = true
    SHARP_SUBCLASSES[(ws and ws.Axe2H) or 1] = true
    SHARP_SUBCLASSES[(ws and ws.Polearm) or 6] = true
    SHARP_SUBCLASSES[(ws and ws.Sword1H) or 7] = true
    SHARP_SUBCLASSES[(ws and ws.Sword2H) or 8] = true
    SHARP_SUBCLASSES[(ws and ws.Dagger) or 15] = true
    BLUNT_SUBCLASSES[(ws and ws.Mace1H) or 4] = true
    BLUNT_SUBCLASSES[(ws and ws.Mace2H) or 5] = true
    BLUNT_SUBCLASSES[(ws and ws.Staff) or 10] = true
    BLUNT_SUBCLASSES[(ws and ws.Unarmed) or 13] = true
end

local CONSUMABLE_AURA_ALIASES = {
    ["elixir of minor fortitude"] = { "health", "elixir of minor fortitude" },
    ["elixir of fortitude"] = { "health ii", "elixir of fortitude" },
    ["elixir of major fortitude"] = { "elixir of major fortitude" },
    ["elixir of minor defense"] = { "armor", "elixir of minor defense" },
    ["elixir of defense"] = { "armor", "elixir of defense" },
    ["elixir of greater defense"] = { "greater armor", "elixir of greater defense" },
    ["elixir of superior defense"] = { "greater armor", "elixir of superior defense" },
    ["elixir of major defense"] = { "elixir of major defense" },
    ["elixir of shadow power"] = { "shadow power", "elixir of shadow power" },
    ["elixir of major shadow power"] = { "elixir of major shadow power" },
    ["elixir of frost power"] = { "frost power", "elixir of frost power" },
    ["elixir of major frost power"] = { "elixir of major frost power" },
    ["elixir of firepower"] = { "fire power", "elixir of firepower" },
    ["elixir of greater firepower"] = { "greater firepower", "fire power", "elixir of greater firepower" },
    ["elixir of major firepower"] = { "elixir of major firepower" },
    ["arcane elixir"] = { "arcane elixir" },
    ["greater arcane elixir"] = { "greater arcane elixir" },
    ["elixir of wisdom"] = { "intellect", "elixir of wisdom" },
    ["elixir of greater intellect"] = { "greater intellect", "elixir of greater intellect" },
    ["elixir of draenic wisdom"] = { "elixir of draenic wisdom" },
    ["elixir of the sages"] = { "elixir of the sages", "sages" },
    ["elixir of minor agility"] = { "agility", "elixir of minor agility" },
    ["elixir of lesser agility"] = { "agility", "elixir of lesser agility" },
    ["elixir of agility"] = { "agility", "elixir of agility" },
    ["elixir of greater agility"] = { "greater agility", "elixir of greater agility" },
    ["elixir of the mongoose"] = { "elixir of the mongoose" },
    ["elixir of major agility"] = { "elixir of major agility" },
    ["elixir of minor strength"] = { "strength", "elixir of minor strength" },
    ["elixir of lion's strength"] = { "strength", "elixir of lion's strength" },
    ["elixir of ogre's strength"] = { "strength", "elixir of ogre's strength" },
    ["elixir of giants"] = { "strength", "elixir of giants" },
    ["elixir of major strength"] = { "elixir of major strength" },
    ["mighty troll's blood potion"] = { "regeneration", "mighty troll's blood potion" },
    ["major troll's blood potion"] = { "regeneration", "major troll's blood potion" },
    ["strong troll's blood potion"] = { "regeneration", "strong troll's blood potion" },
    ["weak troll's blood potion"] = { "regeneration", "weak troll's blood potion" },
    ["mageblood potion"] = { "mageblood potion", "mana regeneration" },
    ["scroll of protection"] = { "armor", "scroll of protection" },
    ["scroll of strength"] = { "strength", "scroll of strength" },
    ["scroll of agility"] = { "agility", "scroll of agility" },
    ["scroll of intellect"] = { "intellect", "scroll of intellect" },
    ["scroll of stamina"] = { "stamina", "scroll of stamina" },
    ["scroll of spirit"] = { "spirit", "scroll of spirit" },
    ["flask of the titans"] = { "flask of the titans", "titans" },
    ["flask of supreme power"] = { "flask of supreme power", "supreme power" },
    ["flask of distilled wisdom"] = { "flask of distilled wisdom", "distilled wisdom" },
    ["flask of chromatic resistance"] = { "flask of chromatic resistance", "chromatic resistance" },
}

-- Strictly stronger auras that prevent applying a weaker consumable while active (even if <= overbuff min left)
local CONSUMABLE_STRONGER_AURAS = {
    ["elixir of minor fortitude"] = { "health ii", "elixir of fortitude", "elixir of major fortitude" },
    ["elixir of fortitude"] = { "elixir of major fortitude" },
    ["elixir of minor defense"] = { "greater armor", "elixir of greater defense", "elixir of superior defense", "elixir of major defense" },
    ["elixir of defense"] = { "greater armor", "elixir of greater defense", "elixir of superior defense", "elixir of major defense" },
    ["elixir of greater defense"] = { "elixir of superior defense", "elixir of major defense" },
    ["elixir of superior defense"] = { "elixir of major defense" },
    ["scroll of protection"] = { "greater armor", "elixir of greater defense", "elixir of superior defense", "elixir of major defense" },
    ["elixir of firepower"] = { "greater firepower", "elixir of greater firepower", "elixir of major firepower" },
    ["elixir of greater firepower"] = { "elixir of major firepower" },
    ["arcane elixir"] = { "greater arcane elixir" },
    ["elixir of shadow power"] = { "elixir of major shadow power" },
    ["elixir of frost power"] = { "elixir of major frost power" },
    ["elixir of wisdom"] = { "greater intellect", "elixir of greater intellect", "elixir of the sages", "elixir of draenic wisdom" },
    ["elixir of greater intellect"] = { "elixir of draenic wisdom" },
    ["elixir of minor agility"] = { "greater agility", "elixir of greater agility", "elixir of the mongoose", "elixir of major agility" },
    ["elixir of lesser agility"] = { "greater agility", "elixir of greater agility", "elixir of the mongoose", "elixir of major agility" },
    ["elixir of agility"] = { "greater agility", "elixir of greater agility", "elixir of the mongoose", "elixir of major agility" },
    ["elixir of greater agility"] = { "elixir of the mongoose", "elixir of major agility" },
    ["elixir of the mongoose"] = { "elixir of major agility" },
    ["elixir of minor strength"] = { "elixir of ogre's strength", "elixir of giants", "elixir of major strength" },
    ["elixir of lion's strength"] = { "elixir of ogre's strength", "elixir of giants", "elixir of major strength" },
    ["elixir of ogre's strength"] = { "elixir of giants", "elixir of major strength" },
    ["elixir of giants"] = { "elixir of major strength" },
}

-- Strictly stronger raid/group buff auras that block single-target refreshes while active
local STRONGER_SPELL_AURAS = {
    ["mark of the wild"]       = { "gift of the wild" },
    ["power word: fortitude"]  = { "prayer of fortitude" },
    ["divine spirit"]          = { "prayer of spirit" },
    ["shadow protection"]      = { "prayer of shadow protection" },
    ["arcane intellect"]       = { "arcane brilliance" },
    ["blessing of might"]      = { "greater blessing of might" },
    ["blessing of wisdom"]     = { "greater blessing of wisdom" },
    ["blessing of kings"]      = { "greater blessing of kings" },
    ["blessing of sanctuary"]  = { "greater blessing of sanctuary" },
    ["blessing of light"]      = { "greater blessing of light" },
    ["blessing of salvation"]  = { "greater blessing of salvation" },
}

local CLASS_BUFF_PRIORITIES = {
    DRUID = {
        { match = { "mark of the wild", "gift of the wild" }, cast = { "Mark of the Wild" }, target = "player" },
        { match = { "thorns" }, cast = { "Thorns" }, target = "player" },
        { match = { "omen of clarity" }, cast = { "Omen of Clarity" } },
    },
    PRIEST = {
        { match = { "power word: fortitude", "prayer of fortitude" }, cast = { "Power Word: Fortitude" }, target = "player" },
        { match = { "inner fire" }, cast = { "Inner Fire" } },
        { match = { "divine spirit", "prayer of spirit" }, cast = { "Divine Spirit" }, target = "player" },
        { match = { "shadow protection", "prayer of shadow protection" }, cast = { "Shadow Protection" }, target = "player" },
        { match = { "shadowform" }, cast = { "Shadowform" } },
        { match = { "touch of weakness" }, cast = { "Touch of Weakness" } },
    },
    MAGE = {
        { match = { "arcane intellect", "arcane brilliance" }, cast = { "Arcane Intellect" }, target = "player" },
        { match = { "molten armor", "mage armor", "ice armor", "frost armor" }, cast = { "Mage Armor", "Ice Armor", "Molten Armor", "Frost Armor" }, keepActive = true },
    },
    WARLOCK = {
        { match = { "fel armor", "demon armor", "demon skin" }, cast = { "Fel Armor", "Demon Armor", "Demon Skin" }, keepActive = true },
        { match = { "soul link" }, cast = { "Soul Link" }, requiresPet = true },
    },
    PALADIN = {
        { match = { "sanctity aura", "retribution aura", "devotion aura", "concentration aura", "shadow resistance aura", "frost resistance aura", "fire resistance aura" }, cast = { "Retribution Aura", "Devotion Aura", "Sanctity Aura" }, keepActive = true },
        { match = { "greater blessing of kings", "blessing of kings", "greater blessing of might", "blessing of might", "greater blessing of wisdom", "blessing of wisdom", "greater blessing of sanctuary", "blessing of sanctuary", "greater blessing of light", "blessing of light", "greater blessing of salvation", "blessing of salvation" }, cast = { "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom", "Blessing of Sanctuary", "Blessing of Light" }, target = "player", keepActive = true },
    },
    SHAMAN = {
        { match = { "water shield", "earth shield", "lightning shield" }, cast = { "Water Shield", "Lightning Shield" }, keepActive = true },
        { weaponImbue = true, cast = { "Windfury Weapon", "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon" } },
    },
    HUNTER = {
        { match = { "aspect of the hawk", "aspect of the monkey", "aspect of the cheetah", "aspect of the pack", "aspect of the beast", "aspect of the wild", "aspect of the viper" }, cast = { "Aspect of the Hawk", "Aspect of the Monkey" }, keepActive = true },
        { match = { "trueshot aura" }, cast = { "Trueshot Aura" } },
    },
    WARRIOR = {}, -- Battle/Commanding Shout require Rage built in combat
    ROGUE = {},
}

local BUFF_ALIAS_EXPANSIONS = {
    ["might"] = { "Blessing of Might" },
    ["wisdom"] = { "Blessing of Wisdom" },
    ["kings"] = { "Blessing of Kings" },
    ["sanctuary"] = { "Blessing of Sanctuary" },
    ["salvation"] = { "Blessing of Salvation" },
    ["light"] = { "Blessing of Light" },
    ["shield"] = { "Lightning Shield", "Water Shield", "Earth Shield", "Power Word: Shield", "Ice Barrier", "Mana Shield" },
    ["motw"] = { "Mark of the Wild" },
    ["mark"] = { "Mark of the Wild" },
    ["fort"] = { "Power Word: Fortitude" },
    ["fortitude"] = { "Power Word: Fortitude" },
    ["int"] = { "Arcane Intellect" },
    ["intellect"] = { "Arcane Intellect" },
    ["spirit"] = { "Divine Spirit" },
    ["shadow"] = { "Shadow Protection", "Shadowform" },
    ["thorns"] = { "Thorns" },
    ["omen"] = { "Omen of Clarity" },
    ["windfury"] = { "Windfury Weapon" },
    ["rockbiter"] = { "Rockbiter Weapon" },
    ["flametongue"] = { "Flametongue Weapon" },
    ["frostbrand"] = { "Frostbrand Weapon" },
    ["hawk"] = { "Aspect of the Hawk" },
    ["monkey"] = { "Aspect of the Monkey" },
    ["cheetah"] = { "Aspect of the Cheetah" },
    ["trueshot"] = { "Trueshot Aura" },
    ["shout"] = { "Battle Shout", "Commanding Shout" },
    ["battle shout"] = { "Battle Shout" },
    ["commanding"] = { "Commanding Shout" },
    ["demon"] = { "Demon Armor", "Demon Skin" },
    ["armor"] = { "Mage Armor", "Ice Armor", "Molten Armor", "Frost Armor", "Fel Armor", "Demon Armor", "Demon Skin" },
    ["devotion"] = { "Devotion Aura" },
    ["retribution"] = { "Retribution Aura" },
    ["concentration"] = { "Concentration Aura" },
    ["sanctity"] = { "Sanctity Aura" },
}

local FRIENDLY_TARGET_BUFFS = {
    ["mark of the wild"] = true,
    ["gift of the wild"] = true,
    ["thorns"] = true,
    ["power word: fortitude"] = true,
    ["prayer of fortitude"] = true,
    ["divine spirit"] = true,
    ["prayer of spirit"] = true,
    ["shadow protection"] = true,
    ["prayer of shadow protection"] = true,
    ["power word: shield"] = true,
    ["fear ward"] = true,
    ["arcane intellect"] = true,
    ["arcane brilliance"] = true,
    ["amplify magic"] = true,
    ["dampen magic"] = true,
    ["blessing of might"] = true,
    ["blessing of wisdom"] = true,
    ["blessing of kings"] = true,
    ["blessing of sanctuary"] = true,
    ["blessing of salvation"] = true,
    ["blessing of light"] = true,
    ["greater blessing of might"] = true,
    ["greater blessing of wisdom"] = true,
    ["greater blessing of kings"] = true,
    ["greater blessing of sanctuary"] = true,
    ["greater blessing of salvation"] = true,
    ["greater blessing of light"] = true,
    ["earth shield"] = true,
    ["detect lesser invisibility"] = true,
    ["detect invisibility"] = true,
    ["detect greater invisibility"] = true,
    ["unending breath"] = true,
}

local SHAMAN_IMBUE_SPELLS = {
    ["windfury weapon"] = true,
    ["rockbiter weapon"] = true,
    ["flametongue weapon"] = true,
    ["frostbrand weapon"] = true,
}

local prepActionBtn = nil
local prepConfirmBtn = nil
local prepScanTooltip = nil
local prepArmedUntil = 0
local lastMissingWarnAt = 0
local lastWarnAtByKey = {}
local lastStoneOverwriteNoteAt = 0
local lastStoneAppliedInfo = nil
local blockedPrepActions = {}
local pendingPrepAttempt = nil
local prepDebugMode = false
local lastPrepTrace = "none"
local obPrepSummaryUpdaters = {}

local function MakeWeaponActionKey(slot, kind, itemID)
    return string.format("WEAPON:%d:%s:%d", tonumber(slot) or 0, tostring(kind or ""), tonumber(itemID) or 0)
end

local function MakeBagItemActionKey(kind, itemID)
    return string.format("ITEM:%s:%d", tostring(kind or ""), tonumber(itemID) or 0)
end

local function MakeSpellActionKey(spellName)
    return "SPELL:" .. tostring(spellName or ""):lower()
end

local function IsPrepKeyBlocked(actionKey)
    if not actionKey then return false, nil end
    local entry = blockedPrepActions[actionKey]
    if not entry then return false, nil end
    local now = (type(GetTime) == "function") and GetTime() or 0
    if entry.expiresAt and now >= entry.expiresAt then
        blockedPrepActions[actionKey] = nil
        return false, nil
    end
    return true, entry
end

local function StripColorCodes(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizePrepItemName(str)
    if type(str) ~= "string" then return nil end
    local linkName = str:match("%[(.-)%]")
    local clean = StripColorCodes(linkName or str)
    if clean == "" then return nil end
    return clean
end

local function SplitCSV(csv)
    local out = {}
    if type(csv) ~= "string" or csv == "" then return out end
    for token in csv:gmatch("[^,;\r\n]+") do
        local clean = StripColorCodes(token)
        if clean ~= "" then
            out[#out + 1] = clean
        end
    end
    return out
end

local function ParsePoisonSelection(sel)
    if type(sel) ~= "string" or sel == "" or sel == "NONE" then
        return nil, nil
    end
    local famKey, suffix = sel:match("^([A-Z]+)_([A-Z0-9]+)$")
    if not famKey or not POISON_FAMILIES[famKey] then
        return nil, nil
    end
    if suffix == "BEST" then
        return famKey, nil
    end
    local rankNum = tonumber(suffix)
    if rankNum and rankNum >= 1 then
        return famKey, rankNum
    end
    return nil, nil
end

local function MatchPoisonText(lowerText)
    if type(lowerText) ~= "string" or lowerText == "" then
        return nil, nil
    end
    for famKey, fam in pairs(POISON_FAMILIES) do
        local pre = fam.prefix
        local escaped = pre:gsub("%-", "%%-")
        local rest = lowerText:match("^" .. escaped .. "(.*)$")
        if rest then
            local rankToken = rest:gsub("%b()", ""):gsub("^%s+", ""):gsub("%s+$", "")
            local rank = ROMAN_TO_NUM[rankToken]
            if rank or rankToken == "" then
                return famKey, rank or 1
            end
        end
    end
    return nil, nil
end

local function GetOBPrepMacroIcon()
    local path = "Interface\\Icons\\Trade_BrewPoison"
    if type(GetFileIDFromPath) == "function" then
        local ok, fileID = pcall(GetFileIDFromPath, path)
        if ok and type(fileID) == "number" and fileID > 0 then
            return fileID
        end
    end
    return "INV_Misc_QuestionMark"
end

local function SafeGetContainerNumSlots(bagID)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        return YRG.SafeNumber(C_Container.GetContainerNumSlots(bagID), 0)
    elseif type(GetContainerNumSlots) == "function" then
        return YRG.SafeNumber(GetContainerNumSlots(bagID), 0)
    end
    return 0
end

local function SafeGetContainerItemDetails(bagID, slot)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if type(info) == "table" and info.itemID then
            return info.itemID, info.hyperlink
        end
        return nil, nil
    elseif type(GetContainerItemLink) == "function" then
        local link = GetContainerItemLink(bagID, slot)
        local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
        return itemID, link
    end
    return nil, nil
end

local function SafeGetItemStatsForPrep(itemID, itemLink)
    local query = itemLink or itemID
    if not query then return nil, 0, 0 end
    local name, _, _, itemLevel, itemMinLevel
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        name, _, _, itemLevel, itemMinLevel = C_Item.GetItemInfo(query)
    elseif type(GetItemInfo) == "function" then
        name, _, _, itemLevel, itemMinLevel = GetItemInfo(query)
    end
    name = YRG.SafeString(name, nil)
    itemLevel = YRG.SafeNumber(itemLevel, 0)
    itemMinLevel = YRG.SafeNumber(itemMinLevel, 0)
    return name, itemLevel, itemMinLevel
end

local function IsBagItemOnCooldown(bag, slot)
    local start, duration = 0, 0
    if C_Container and type(C_Container.GetContainerItemCooldown) == "function" then
        start, duration = C_Container.GetContainerItemCooldown(bag, slot)
    elseif type(GetContainerItemCooldown) == "function" then
        start, duration = GetContainerItemCooldown(bag, slot)
    end
    start = YRG.SafeNumber(start, 0)
    duration = YRG.SafeNumber(duration, 0)
    if start > 0 and duration > 1.5 then
        local now = (type(GetTime) == "function") and GetTime() or 0
        if (start + duration - now) > 0.25 then
            return true
        end
    end
    return false
end

local function FindPoisonInBags(selectionKey, skipFn)
    local desiredFam, targetRank = ParsePoisonSelection(selectionKey)
    if not desiredFam then return nil, false, nil end

    local playerLevel = YRG.SafeNumber(UnitLevel and UnitLevel("player"), 60)
    local maxBag = NUM_BAG_SLOTS or 4
    local best = nil
    local sawBlocked = false
    local minLevelBlocked = nil

    for bag = 0, maxBag do
        local numSlots = SafeGetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemID, itemLink = SafeGetContainerItemDetails(bag, slot)
            if itemID then
                local fam, rank, knownName
                local known = POISON_ITEM_BY_ID[itemID]
                local itemName, _, itemMinLevel = SafeGetItemStatsForPrep(itemID, itemLink)
                if known then
                    fam = known.family
                    rank = known.rank
                    knownName = itemName or known.name
                elseif itemName then
                    fam, rank = MatchPoisonText(itemName:lower())
                    knownName = itemName
                end

                if fam == desiredFam and rank and ((not targetRank) or (rank == targetRank)) then
                    if itemMinLevel > playerLevel then
                        if not minLevelBlocked or itemMinLevel < minLevelBlocked then
                            minLevelBlocked = itemMinLevel
                        end
                    elseif skipFn and skipFn(itemID, knownName) then
                        sawBlocked = true
                    elseif (not best) or (rank > best.rank) then
                        best = {
                            bag = bag,
                            slot = slot,
                            itemID = itemID,
                            name = knownName or POISON_FAMILIES[fam].label,
                            rank = rank,
                            family = fam,
                        }
                    end
                end
            end
        end
    end

    return best, sawBlocked, minLevelBlocked
end

local function FindBestStoneInBags(stoneKind, skipFn)
    if stoneKind ~= "SHARP" and stoneKind ~= "BLUNT" then
        return nil, false, nil
    end

    local playerLevel = YRG.SafeNumber(UnitLevel and UnitLevel("player"), 60)
    local maxBag = NUM_BAG_SLOTS or 4
    local best = nil
    local sawBlocked = false
    local minLevelBlocked = nil

    for bag = 0, maxBag do
        local numSlots = SafeGetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemID, itemLink = SafeGetContainerItemDetails(bag, slot)
            if itemID then
                local known = STONE_ITEM_BY_ID[itemID]
                local itemName, itemLevel, itemMinLevel = SafeGetItemStatsForPrep(itemID, itemLink)
                local kind, tier, displayName

                if known then
                    kind = known.kind
                    tier = known.tier
                    displayName = itemName or known.name
                elseif itemName then
                    local low = itemName:lower()
                    if low:find("sharpening stone", 1, true) then
                        kind = "SHARP"
                        tier = 100 + itemLevel
                        displayName = itemName
                    elseif low:find("weightstone", 1, true) then
                        kind = "BLUNT"
                        tier = 100 + itemLevel
                        displayName = itemName
                    end
                end

                if kind == stoneKind and tier then
                    if itemMinLevel > playerLevel then
                        if not minLevelBlocked or itemMinLevel < minLevelBlocked then
                            minLevelBlocked = itemMinLevel
                        end
                    elseif skipFn and skipFn(itemID, displayName) then
                        sawBlocked = true
                    elseif (not best) or (tier > best.tier) then
                        best = {
                            bag = bag,
                            slot = slot,
                            itemID = itemID,
                            name = displayName or "Enhancement Stone",
                            tier = tier,
                            kind = kind,
                        }
                    end
                end
            end
        end
    end

    return best, sawBlocked, minLevelBlocked
end

local function FindBestOilInBags(skipFn)
    local playerLevel = YRG.SafeNumber(UnitLevel and UnitLevel("player"), 60)
    local maxBag = NUM_BAG_SLOTS or 4
    local best = nil
    local sawBlocked = false
    local minLevelBlocked = nil

    for bag = 0, maxBag do
        local numSlots = SafeGetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemID, itemLink = SafeGetContainerItemDetails(bag, slot)
            if itemID then
                local known = OIL_ITEM_BY_ID[itemID]
                local itemName, itemLevel, itemMinLevel = SafeGetItemStatsForPrep(itemID, itemLink)
                local tier, displayName

                if known then
                    tier = known.tier
                    displayName = itemName or known.name
                elseif itemName then
                    local low = itemName:lower()
                    if low:find("wizard oil", 1, true) then
                        tier = 200 + itemLevel
                        displayName = itemName
                    elseif low:find("mana oil", 1, true) then
                        tier = 50 + itemLevel
                        displayName = itemName
                    end
                end

                if tier then
                    if itemMinLevel > playerLevel then
                        if not minLevelBlocked or itemMinLevel < minLevelBlocked then
                            minLevelBlocked = itemMinLevel
                        end
                    elseif skipFn and skipFn(itemID, displayName) then
                        sawBlocked = true
                    elseif (not best) or (tier > best.tier) then
                        best = {
                            bag = bag,
                            slot = slot,
                            itemID = itemID,
                            name = displayName or "Wizard Oil",
                            tier = tier,
                            kind = "OIL",
                        }
                    end
                end
            end
        end
    end

    return best, sawBlocked, minLevelBlocked
end

local function FindNamedItemInBags(targetName, skipFn)
    local clean = NormalizePrepItemName(targetName)
    if not clean then return nil, false, false, nil end
    local wantLow = clean:lower()
    local playerLevel = YRG.SafeNumber(UnitLevel and UnitLevel("player"), 60)
    local maxBag = NUM_BAG_SLOTS or 4
    local partialMatch = nil
    local sawCooldown = false
    local sawBlocked = false
    local minLevelBlocked = nil

    for bag = 0, maxBag do
        local numSlots = SafeGetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemID, itemLink = SafeGetContainerItemDetails(bag, slot)
            if itemID then
                local itemName, _, itemMinLevel = SafeGetItemStatsForPrep(itemID, itemLink)
                if itemName then
                    local low = itemName:lower()
                    local isExact = (low == wantLow)
                    local isPartial = (not isExact) and (low:find(wantLow, 1, true) ~= nil)
                    if isExact or isPartial then
                        if itemMinLevel > playerLevel then
                            if not minLevelBlocked or itemMinLevel < minLevelBlocked then
                                minLevelBlocked = itemMinLevel
                            end
                        elseif skipFn and skipFn(itemID, itemName) then
                            sawBlocked = true
                        elseif IsBagItemOnCooldown(bag, slot) then
                            sawCooldown = true
                        elseif isExact then
                            return {
                                bag = bag,
                                slot = slot,
                                itemID = itemID,
                                link = itemLink,
                                name = itemName,
                            }, sawCooldown, sawBlocked, minLevelBlocked
                        elseif not partialMatch then
                            partialMatch = {
                                bag = bag,
                                slot = slot,
                                itemID = itemID,
                                link = itemLink,
                                name = itemName,
                            }
                        end
                    end
                end
            end
        end
    end

    return partialMatch, sawCooldown, sawBlocked, minLevelBlocked
end

local function GetWeaponSlotKind(invSlot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", invSlot)
    if type(link) ~= "string" or link == "" then
        return false, false, nil
    end

    local _, itemType, itemSubType, equipLoc, _, classID, subClassID
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        _, itemType, itemSubType, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    elseif type(GetItemInfoInstant) == "function" then
        _, itemType, itemSubType, equipLoc, _, classID, subClassID = GetItemInfoInstant(link)
    end

    local weaponClassID = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
    classID = YRG.SafeOptionalNumber(classID)
    subClassID = YRG.SafeOptionalNumber(subClassID)

    if classID ~= nil and classID ~= weaponClassID then
        return true, false, nil
    end

    if subClassID ~= nil then
        if SHARP_SUBCLASSES[subClassID] then
            return true, true, "SHARP"
        elseif BLUNT_SUBCLASSES[subClassID] then
            return true, true, "BLUNT"
        elseif classID == weaponClassID then
            return true, false, nil
        end
    end

    local _, fullType, fullSubType = nil, nil, nil
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local _, _, _, _, _, t, st = C_Item.GetItemInfo(link)
        fullType, fullSubType = t, st
    elseif type(GetItemInfo) == "function" then
        local _, _, _, _, _, t, st = GetItemInfo(link)
        fullType, fullSubType = t, st
    end
    local stLow = YRG.SafeString(fullSubType or itemSubType, ""):lower()
    if stLow:find("dagger", 1, true) or stLow:find("sword", 1, true)
        or stLow:find("axe", 1, true) or stLow:find("polearm", 1, true) then
        return true, true, "SHARP"
    elseif stLow:find("mace", 1, true)
        or stLow:find("fist", 1, true)
        or (stLow:find("staff", 1, true) and not stLow:find("fishing", 1, true)) then
        return true, true, "BLUNT"
    end

    return true, false, nil
end

local function ReadInventoryTooltipLines(invSlot)
    local lines = {}
    if C_TooltipInfo and type(C_TooltipInfo.GetInventoryItem) == "function" then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", invSlot)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for i, line in ipairs(data.lines) do
                local txt = line and (line.leftText or line.text)
                if type(txt) == "string" and not IsSecret(txt) and txt ~= "" then
                    lines[#lines + 1] = txt
                end
            end
        end
    end

    if #lines == 0 and CreateFrame and UIParent then
        if not prepScanTooltip then
            local ok, tip = pcall(CreateFrame, "GameTooltip", "YRGRoguePrepScanTooltip", UIParent, "GameTooltipTemplate")
            if ok and tip then
                prepScanTooltip = tip
            end
        end
        if prepScanTooltip then
            prepScanTooltip:Hide()
            prepScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            if prepScanTooltip.ClearLines then prepScanTooltip:ClearLines() end
            local okSet = pcall(prepScanTooltip.SetInventoryItem, prepScanTooltip, "player", invSlot)
            if okSet then
                local numLines = YRG.SafeNumber(prepScanTooltip.NumLines and prepScanTooltip:NumLines(), 0)
                local tipName = prepScanTooltip.GetName and prepScanTooltip:GetName() or "YRGRoguePrepScanTooltip"
                for i = 1, numLines do
                    local fs = _G[tipName .. "TextLeft" .. i]
                    local txt = fs and fs.GetText and fs:GetText()
                    if type(txt) == "string" and not IsSecret(txt) and txt ~= "" then
                        lines[#lines + 1] = txt
                    end
                end
            end
            prepScanTooltip:Hide()
        end
    end

    return lines
end

local function ParseTooltipDurationMinutes(lowerText, allowUnparenthesized)
    if type(lowerText) ~= "string" then return nil end
    local hrs = lowerText:match("%((%d+)%s*h[ou]*r[s]?%)")
    if hrs then
        return tonumber(hrs) * 60
    end
    local mins = lowerText:match("%((%d+)%s*min[s]?%)")
    if mins then
        return tonumber(mins)
    end
    local secs = lowerText:match("%((%d+)%s*sec[s]?%)")
    if secs then
        return tonumber(secs) / 60
    end
    if allowUnparenthesized then
        local h2 = lowerText:match("(%d+)%s*h[ou]*r[s]?")
        if h2 then return tonumber(h2) * 60 end
        local m2 = lowerText:match("(%d+)%s*min")
        if m2 then return tonumber(m2) end
        local s2 = lowerText:match("(%d+)%s*sec")
        if s2 then return tonumber(s2) / 60 end
    end
    return nil
end

local function IsEnhancementStoneEnchantLine(lowerText)
    if type(lowerText) ~= "string" or lowerText == "" then return false end
    if lowerText:find("^use:") or lowerText:find("^equip:") or lowerText:find("^chance on hit:") then
        return false
    end
    if lowerText:find("sharpened", 1, true)
        or lowerText:find("weighted", 1, true)
        or lowerText:find("sharpening stone", 1, true)
        or lowerText:find("weightstone", 1, true)
        or lowerText:find("attack power vs undead", 1, true)
        or lowerText:find("critical %+%d+%%")
        or lowerText:find("crit %+%d+%%")
        or lowerText:find("%+%d+%% critical") then
        return true
    end
    return false
end

local function IsWeaponOilEnchantLine(lowerText)
    if type(lowerText) ~= "string" or lowerText == "" then return false end
    if lowerText:find("^use:") or lowerText:find("^equip:") or lowerText:find("^chance on hit:") then
        return false
    end
    if lowerText:find("wizard oil", 1, true)
        or lowerText:find("mana oil", 1, true)
        or (lowerText:find("spell damage", 1, true) and lowerText:find("%(%d+"))
        or (lowerText:find("healing spells", 1, true) and lowerText:find("%(%d+"))
        or (lowerText:find("mana every 5", 1, true) and lowerText:find("%(%d+")) then
        return true
    end
    return false
end

local function MatchShamanImbueLine(lowerText)
    if type(lowerText) ~= "string" or lowerText == "" then return nil end
    if lowerText:find("^use:") or lowerText:find("^equip:") or lowerText:find("^chance on hit:") then
        return nil
    end
    for _, key in ipairs({ "windfury", "rockbiter", "flametongue", "frostbrand" }) do
        if lowerText:find(key, 1, true) and lowerText:find("%(%d+") then
            return key
        end
    end
    return nil
end

local function InspectWeaponEnchantState(invSlot)
    local equipped, canPoison, stoneKind = GetWeaponSlotKind(invSlot)
    local state = {
        invSlot = invSlot,
        equipped = equipped,
        canPoison = canPoison,
        stoneKind = stoneKind,
        activePoison = nil,
        activeStone = nil,
        activeOil = nil,
        activeImbue = nil,
    }
    if not equipped then
        return state
    end

    local hasMH, mhExpMs, _, _, hasOH, ohExpMs = false, 0, nil, nil, false, 0
    if type(GetWeaponEnchantInfo) == "function" then
        local ok, a, b, c, d, e, f, g, h = pcall(GetWeaponEnchantInfo)
        if ok then
            hasMH = (not IsSecret(a)) and a and true or false
            mhExpMs = YRG.SafeNumber(b, 0)
            hasOH = (not IsSecret(e)) and e and true or false
            ohExpMs = YRG.SafeNumber(f, 0)
        end
    end

    local slotHasEnch = (invSlot == INV_SLOT_MAINHAND) and hasMH or hasOH
    local slotExpMins = ((invSlot == INV_SLOT_MAINHAND) and mhExpMs or ohExpMs) / 60000
    local lines = ReadInventoryTooltipLines(invSlot)
    local unrecognizedTimedEnch = nil

    for i = 2, #lines do
        local clean = StripColorCodes(lines[i])
        local low = clean:lower()
        local pFam, pRank = MatchPoisonText(low)
        local isOil = (not pFam) and IsWeaponOilEnchantLine(low)
        local isStone = (not pFam) and (not isOil) and IsEnhancementStoneEnchantLine(low)
        local imbueKey = (not pFam) and (not isOil) and (not isStone) and MatchShamanImbueLine(low)
        local minsLeft = ParseTooltipDurationMinutes(low, (pFam ~= nil or isOil or isStone or imbueKey ~= nil))
        local resolvedMins = minsLeft or (slotHasEnch and slotExpMins > 0 and slotExpMins or nil)

        if pFam then
            state.activePoison = {
                family = pFam,
                rank = pRank,
                minsLeft = resolvedMins,
                label = clean,
            }
        elseif isOil then
            state.activeOil = {
                kind = "OIL",
                minsLeft = resolvedMins,
                label = clean,
            }
        elseif isStone then
            state.activeStone = {
                kind = (low:find("weight", 1, true) and "BLUNT" or "SHARP"),
                minsLeft = resolvedMins,
                label = clean,
            }
        elseif imbueKey then
            state.activeImbue = {
                key = imbueKey,
                minsLeft = resolvedMins,
                label = clean,
            }
        elseif minsLeft and slotHasEnch and not low:find("^use:") and not low:find("^equip:") then
            unrecognizedTimedEnch = {
                minsLeft = minsLeft,
                label = clean,
            }
        end
    end

    if not state.activeStone and not state.activeOil and not state.activeImbue and unrecognizedTimedEnch then
        state.activeStone = {
            kind = stoneKind or "SHARP",
            minsLeft = unrecognizedTimedEnch.minsLeft,
            label = unrecognizedTimedEnch.label,
        }
    end

    return state
end

local function IsActionButtonUseKeyDown()
    if type(GetCVarBool) == "function" then
        local ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        if ok and v ~= nil then
            return v and true or false
        end
    end
    return false
end

local function SyncSecureButtonClickMode(btn)
    if not btn or (InCombatLockdown and InCombatLockdown()) then return end
    if IsActionButtonUseKeyDown() then
        btn:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    else
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
end

local function ClearRoguePrepActionAttributes()
    if InCombatLockdown and InCombatLockdown() then return end
    if prepActionBtn then
        prepActionBtn:SetAttribute("type", nil)
        prepActionBtn:SetAttribute("type1", nil)
        prepActionBtn:SetAttribute("item", nil)
        prepActionBtn:SetAttribute("item1", nil)
        prepActionBtn:SetAttribute("bag", nil)
        prepActionBtn:SetAttribute("slot", nil)
        prepActionBtn:SetAttribute("target-slot", nil)
        prepActionBtn:SetAttribute("target-slot1", nil)
        prepActionBtn:SetAttribute("spell", nil)
        prepActionBtn:SetAttribute("spell1", nil)
        prepActionBtn:SetAttribute("unit", nil)
        prepActionBtn:SetAttribute("unit1", nil)
        prepActionBtn:SetAttribute("macrotext", nil)
        prepActionBtn:SetAttribute("macrotext1", nil)
    end
    if prepConfirmBtn then
        prepConfirmBtn:SetAttribute("type", nil)
        prepConfirmBtn:SetAttribute("type1", nil)
        prepConfirmBtn:SetAttribute("clickbutton", nil)
        prepConfirmBtn:SetAttribute("clickbutton1", nil)
    end
end

EnsureRoguePrepButtons = function()
    if not prepConfirmBtn and CreateFrame and UIParent then
        local cbtn = CreateFrame("Button", "YRGOBPrepConfirm", UIParent, "SecureActionButtonTemplate")
        cbtn:SetSize(1, 1)
        cbtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
        cbtn:EnableMouse(false)
        cbtn:HookScript("PostClick", function(self, btnName, down)
            lastPrepTrace = lastPrepTrace .. string.format(" | ConfirmPost(%s,%s)", tostring(btnName), tostring(down))
            if not (InCombatLockdown and InCombatLockdown()) then
                self:SetAttribute("type", nil)
                self:SetAttribute("type1", nil)
                self:SetAttribute("clickbutton", nil)
                self:SetAttribute("clickbutton1", nil)
            end
        end)
        prepConfirmBtn = cbtn
        _G["YRGRoguePrepConfirm"] = cbtn
    end
    SyncSecureButtonClickMode(prepConfirmBtn)

    if not prepActionBtn and CreateFrame and UIParent then
        local btn = CreateFrame("Button", "YRGOBPrepButton", UIParent, "SecureActionButtonTemplate")
        btn:SetSize(1, 1)
        btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
        btn:EnableMouse(false)
        btn:HookScript("PreClick", function(self, btnName, down)
            if pendingPrepAttempt then
                local now = (type(GetTime) == "function") and GetTime() or 0
                pendingPrepAttempt.clicked = true
                pendingPrepAttempt.clickedAt = now
                pendingPrepAttempt.expiresAt = now + 1.5
            end
            lastPrepTrace = lastPrepTrace .. string.format(" | Pre(%s,%s,t=%s,i=%s,s=%s,ts=%s)",
                tostring(btnName), tostring(down),
                tostring(self:GetAttribute("type1") or self:GetAttribute("type")),
                tostring(self:GetAttribute("item1") or self:GetAttribute("item")),
                tostring(self:GetAttribute("spell1") or self:GetAttribute("spell")),
                tostring(self:GetAttribute("target-slot1") or self:GetAttribute("target-slot")))
        end)
        btn:HookScript("PostClick", function(_, btnName, down)
            lastPrepTrace = lastPrepTrace .. string.format(" | Post(%s,%s)", tostring(btnName), tostring(down))
            if prepDebugMode then
                print("|cffffd100YRG OB Prep Debug:|r " .. lastPrepTrace)
            end
            ClearRoguePrepActionAttributes()
        end)
        prepActionBtn = btn
        _G["YRGRoguePrepButton"] = btn
    end
    SyncSecureButtonClickMode(prepActionBtn)
end

HandleReplaceEnchantEvent = function()
    if InCombatLockdown and InCombatLockdown() then return end
    local now = (type(GetTime) == "function") and GetTime() or 0
    if now > prepArmedUntil then return end
    if not prepConfirmBtn then return end

    local popup = (type(StaticPopup_FindVisible) == "function") and StaticPopup_FindVisible("REPLACE_ENCHANT")
    if not popup then
        for i = 1, 4 do
            local sp = _G["StaticPopup" .. i]
            if sp and sp:IsShown() and sp.which == "REPLACE_ENCHANT" then
                popup = sp
                break
            end
        end
    end
    if popup then
        local pName = popup.GetName and popup:GetName()
        local okBtn = popup.button1 or (pName and _G[pName .. "Button1"])
        if okBtn then
            prepConfirmBtn:SetAttribute("type", "click")
            prepConfirmBtn:SetAttribute("type1", "click")
            prepConfirmBtn:SetAttribute("clickbutton", okBtn)
            prepConfirmBtn:SetAttribute("clickbutton1", okBtn)
            lastPrepTrace = lastPrepTrace .. " | ReplacePopupArmed"
        end
    end
end

local function EnsureSingleMacro(macroName, body, forceReset, legacyBodies, icon)
    local idx = GetMacroIndexByName(macroName)
    if idx and idx > 0 then
        local existingBody = (type(GetMacroBody) == "function") and GetMacroBody(idx) or nil
        if type(existingBody) == "string" then
            existingBody = existingBody:gsub("\r\n", "\n"):gsub("%s+$", "")
        end
        local needsMigration = (existingBody ~= nil and legacyBodies and legacyBodies[existingBody]) and true or false
        if (forceReset or needsMigration) and type(EditMacro) == "function" then
            EditMacro(idx, macroName, icon or GetOBPrepMacroIcon(), body)
            return true, needsMigration and "migrated" or "reset"
        end
        return true, "exists"
    end
    return false, "missing"
end

EnsureRoguePrepMacro = function(forceReset, verbose)
    if InCombatLockdown and InCombatLockdown() then
        if verbose then
            print("|cffffd100YRG OB Prep:|r Cannot create or update the YRGOBP macro during combat.")
        end
        return false, "combat"
    end
    if type(GetMacroIndexByName) ~= "function" or type(CreateMacro) ~= "function" then
        return false, "unavailable"
    end

    -- Keep any existing YRGRP macro from earlier versions working seamlessly
    EnsureSingleMacro(ROGUE_PREP_MACRO_NAME, OB_PREP_MACRO_BODY, false, ROGUE_PREP_LEGACY_BODIES)

    local existed, state = EnsureSingleMacro(OB_PREP_MACRO_NAME, OB_PREP_MACRO_BODY, forceReset, nil)
    if existed then
        if verbose and state == "reset" then
            print("|cffffd100YRG OB Prep:|r Reset macro |cff00ff00" .. OB_PREP_MACRO_NAME .. "|r.")
        end
        return true, state
    end

    local numAccount, numChar = 0, 0
    if type(GetNumMacros) == "function" then
        numAccount, numChar = GetNumMacros()
        numAccount = YRG.SafeNumber(numAccount, 0)
        numChar = YRG.SafeNumber(numChar, 0)
    end

    local perChar = nil
    if numChar < (MAX_CHARACTER_MACROS or 18) then
        perChar = true
    elseif numAccount < (MAX_ACCOUNT_MACROS or 120) then
        perChar = false
    else
        if verbose then
            print("|cffffd100YRG OB Prep:|r Macro slots are full; free a macro slot to generate " .. OB_PREP_MACRO_NAME .. ".")
        end
        return false, "full"
    end

    local createdIdx = CreateMacro(OB_PREP_MACRO_NAME, GetOBPrepMacroIcon(), OB_PREP_MACRO_BODY, perChar)
    if createdIdx and createdIdx > 0 then
        if verbose then
            print("|cffffd100YRG OB Prep:|r Created macro |cff00ff00" .. OB_PREP_MACRO_NAME .. "|r calling /yrgobprep.")
        end
        return true, "created"
    end
    return false, "failed"
end

local function GetSafeSpellName(spellIDOrName)
    if not spellIDOrName then return nil end
    local name
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local okS, sInfo = pcall(C_Spell.GetSpellInfo, spellIDOrName)
        if okS and type(sInfo) == "table" then name = sInfo.name end
    elseif type(GetSpellInfo) == "function" then
        local okS, sName = pcall(GetSpellInfo, spellIDOrName)
        if okS then name = sName end
    end
    return YRG.SafeString(name, nil)
end

local function GetSafeSpellRankNumber(spellIDOrName, knownSubtext)
    local subtext = YRG.SafeString(knownSubtext, nil)
    if not subtext and spellIDOrName then
        if C_Spell and type(C_Spell.GetSpellSubtext) == "function" then
            local ok, st = pcall(C_Spell.GetSpellSubtext, spellIDOrName)
            if ok then subtext = YRG.SafeString(st, nil) end
        elseif type(GetSpellSubtext) == "function" then
            local ok, st = pcall(GetSpellSubtext, spellIDOrName)
            if ok then subtext = YRG.SafeString(st, nil) end
        end
    end
    if subtext then
        local r = tonumber(subtext:lower():match("rank%s*(%d+)"))
        if r and r > 0 then
            return r
        end
    end
    return nil
end

local function ReadPlayerAuras()
    local auras = {}
    local now = (type(GetTime) == "function") and GetTime() or 0

    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for i = 1, 60 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(aura) ~= "table" then
                break
            end
            local name = YRG.SafeString(aura.name, nil)
            local spellId = YRG.SafeOptionalNumber(aura.spellId)
            local duration = YRG.SafeNumber(aura.duration, 0)
            local expirationTime = YRG.SafeNumber(aura.expirationTime, 0)
            local sourceUnit = YRG.SafeString(aura.sourceUnit, nil)
            if name then
                local minsLeft = (duration > 0 and expirationTime > 0) and math.max(0, (expirationTime - now) / 60) or nil
                local maxDurMins = (duration > 0) and (duration / 60) or nil
                auras[#auras + 1] = {
                    name = name,
                    lowName = name:lower(),
                    spellId = spellId,
                    rankNum = GetSafeSpellRankNumber(spellId),
                    sourceUnit = sourceUnit,
                    minsLeft = minsLeft,
                    maxDurationMins = maxDurMins,
                }
            end
        end
    elseif type(UnitAura) == "function" then
        for i = 1, 60 do
            local ok, name, _, _, _, duration, expirationTime, sourceUnit, _, _, spellId = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok then break end
            name = YRG.SafeString(name, nil)
            if not name then break end
            duration = YRG.SafeNumber(duration, 0)
            expirationTime = YRG.SafeNumber(expirationTime, 0)
            sourceUnit = YRG.SafeString(sourceUnit, nil)
            spellId = YRG.SafeOptionalNumber(spellId)
            local minsLeft = (duration > 0 and expirationTime > 0) and math.max(0, (expirationTime - now) / 60) or nil
            local maxDurMins = (duration > 0) and (duration / 60) or nil
            auras[#auras + 1] = {
                name = name,
                lowName = name:lower(),
                spellId = spellId,
                rankNum = GetSafeSpellRankNumber(spellId),
                sourceUnit = sourceUnit,
                minsLeft = minsLeft,
                maxDurationMins = maxDurMins,
            }
        end
    end

    -- Fallback: detect active Paladin Aura on the stance bar if omitted from UnitAura
    local _, cls = UnitClass("player")
    if (not IsSecret(cls) and cls == "PALADIN")
        and type(GetShapeshiftForm) == "function" and type(GetShapeshiftFormInfo) == "function" then
        local formIdx = YRG.SafeNumber(GetShapeshiftForm(), 0)
        if formIdx > 0 then
            local _, active, _, spellID = GetShapeshiftFormInfo(formIdx)
            spellID = YRG.SafeOptionalNumber(spellID)
            if active and spellID then
                local spName = GetSafeSpellName(spellID)
                if spName then
                    auras[#auras + 1] = {
                        name = spName,
                        lowName = spName:lower(),
                        spellId = spellID,
                        rankNum = GetSafeSpellRankNumber(spellID),
                        minsLeft = nil,
                        maxDurationMins = nil,
                    }
                end
            end
        end
    end

    return auras
end

local function HasPlayerDebuff(lowDebuffName)
    if type(lowDebuffName) ~= "string" or lowDebuffName == "" then return false end
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
            if not ok or type(aura) ~= "table" then break end
            local name = YRG.SafeString(aura.name, nil)
            if name and name:lower() == lowDebuffName then
                return true
            end
        end
    elseif type(UnitAura) == "function" then
        for i = 1, 40 do
            local ok, name = pcall(UnitAura, "player", i, "HARMFUL")
            if not ok then break end
            name = YRG.SafeString(name, nil)
            if not name then break end
            if name:lower() == lowDebuffName then
                return true
            end
        end
    end
    return false
end

local function EffectiveOverbuffThreshold(overbuffMinutes, maxDurationMins)
    if not overbuffMinutes or overbuffMinutes <= 0 then
        return 0
    end
    if maxDurationMins and maxDurationMins > 0 then
        return math.min(overbuffMinutes, maxDurationMins * 0.5)
    end
    return overbuffMinutes
end

local function IsAuraSatisfied(aura, overbuffMinutes)
    if not aura then return false end
    if aura.minsLeft == nil then
        return true -- Passive / unlimited aura (e.g. Paladin Aura, Trueshot Aura)
    end
    local eff = EffectiveOverbuffThreshold(overbuffMinutes, aura.maxDurationMins)
    return aura.minsLeft > eff
end

local function FindMatchingAuraByNames(namesLowList, auras)
    if type(namesLowList) ~= "table" then return nil end
    for _, aura in ipairs(auras) do
        for _, targetLow in ipairs(namesLowList) do
            if aura.lowName == targetLow then
                return aura
            end
        end
    end
    return nil
end

local function SnapshotPlayerAuraNames(auras)
    local snap = {}
    for _, aura in ipairs(auras) do
        snap[aura.lowName] = true
    end
    return snap
end

local function GetSlotEnchantLabel(state)
    if not state or not state.equipped then return "NONE" end
    if state.activePoison then return "P:" .. tostring(state.activePoison.label) end
    if state.activeOil then return "O:" .. tostring(state.activeOil.label) end
    if state.activeStone then return "S:" .. tostring(state.activeStone.label) end
    if state.activeImbue then return "I:" .. tostring(state.activeImbue.label) end
    return "NONE"
end

local function PruneBlockedPrepActions(auras, mhState, ohState)
    local now = (type(GetTime) == "function") and GetTime() or 0
    local activeSet = auras and SnapshotPlayerAuraNames(auras) or nil

    for key, entry in pairs(blockedPrepActions) do
        local remove = false
        if entry.expiresAt and now >= entry.expiresAt then
            remove = true
        elseif entry.blockType == "MORE_POWERFUL" then
            if activeSet and entry.auraSnap then
                for auraLow in pairs(entry.auraSnap) do
                    if not activeSet[auraLow] then
                        remove = true
                        break
                    end
                end
            end
            if not remove and entry.slot then
                local st = (entry.slot == INV_SLOT_MAINHAND) and mhState or ((entry.slot == INV_SLOT_OFFHAND) and ohState or nil)
                if st and GetSlotEnchantLabel(st) ~= entry.weaponLabel then
                    remove = true
                end
            end
        elseif entry.blockType == "UNUSABLE_TARGET" and entry.slot then
            local curLink = GetInventoryItemLink and GetInventoryItemLink("player", entry.slot) or nil
            if curLink ~= entry.equipLink then
                remove = true
            end
        end

        if remove then
            blockedPrepActions[key] = nil
        end
    end
end

local function ClassifyPrepUIError(msg)
    if type(msg) ~= "string" or msg == "" then return nil, nil, nil end
    local cleanMsg = (msg:gsub("%.$", ""))
    local low = msg:lower()

    local auraBounced = YRG.SafeString(_G.SPELL_FAILED_AURA_BOUNCED, nil)
    local errAuraBounced = YRG.SafeString(_G.ERR_AURA_BOUNCED, nil)
    if (auraBounced and msg == auraBounced)
        or (errAuraBounced and msg == errAuraBounced)
        or low:find("more powerful spell", 1, true)
        or low:find("more powerful buff", 1, true)
        or low:find("stronger spell", 1, true)
        or low:find("stronger buff", 1, true) then
        return "MORE_POWERFUL", "a more powerful buff is already active", 300
    end

    -- Transient movement / GCD / mounted errors should not blacklist an action
    if low:find("while moving", 1, true)
        or low:find("another action is in progress", 1, true)
        or low:find("spell is not ready yet", 1, true)
        or low:find("cannot do that right now", 1, true)
        or low:find("you are mounted", 1, true)
        or low:find("can't do that while mounted", 1, true) then
        return nil, nil, nil
    end

    if low:find("item is not ready", 1, true) or low:find("not ready yet", 1, true) then
        return "COOLDOWN", "item is on cooldown", 5
    end

    if low:find("cannot be enchanted", 1, true)
        or low:find("can't be enchanted", 1, true)
        or low:find("too low level", 1, true)
        or low:find("not high enough level", 1, true)
        or low:find("item level", 1, true)
        or low:find("wrong item", 1, true)
        or low:find("can't use that item", 1, true)
        or low:find("cannot use that", 1, true)
        or low:find("invalid target", 1, true) then
        return "UNUSABLE_TARGET", cleanMsg, 180
    end

    if low:find("reagent", 1, true) or low:find("requires ", 1, true) then
        return "MISSING_REAGENT", cleanMsg, 60
    end

    if low:find("shapeshift", 1, true) or low:find("in beast form", 1, true) then
        return "SHAPESHIFT", cleanMsg, 30
    end

    if low:find("not enough mana", 1, true)
        or low:find("not enough rage", 1, true)
        or low:find("not enough energy", 1, true) then
        return "RESOURCES", cleanMsg, 5
    end

    if low:find("already active", 1, true)
        or low:find("too full", 1, true)
        or low:find("already full", 1, true) then
        return "MORE_POWERFUL", cleanMsg, 120
    end

    return nil, nil, nil
end

local function GetPrepActionKey(action)
    if not action then return nil end
    if action.actionType == "WEAPON_ITEM" and action.item then
        return MakeWeaponActionKey(action.slot, action.kind, action.item.itemID)
    elseif action.actionType == "BAG_ITEM" and action.item then
        return MakeBagItemActionKey(action.kind, action.item.itemID)
    elseif action.actionType == "SPELL" and action.spell then
        return MakeSpellActionKey(action.spell)
    end
    return nil
end

local function GetPrepActionLabel(action)
    if not action then return "Unknown" end
    if action.actionType == "WEAPON_ITEM" and action.item then
        return string.format("%s (%s)", tostring(action.item.name), tostring(action.handLabel))
    elseif action.actionType == "BAG_ITEM" and action.item then
        return tostring(action.item.name)
    elseif action.actionType == "SPELL" and action.spell then
        return tostring(action.spell)
    end
    return "Unknown"
end

local function DoesSpellIDMatchAttempt(attempt, spellID)
    if not attempt or not spellID then return false end
    local idNum = YRG.SafeOptionalNumber(spellID)
    if not idNum then return false end
    local spName = GetSafeSpellName(idNum)
    if attempt.actionType == "SPELL" and attempt.spell then
        return spName ~= nil and spName:lower() == attempt.spell:lower()
    elseif attempt.itemID then
        local itemSpellName, itemSpellID
        if C_Item and type(C_Item.GetItemSpell) == "function" then
            itemSpellName, itemSpellID = C_Item.GetItemSpell(attempt.itemID)
        elseif type(GetItemSpell) == "function" then
            itemSpellName, itemSpellID = GetItemSpell(attempt.itemID)
        end
        itemSpellName = YRG.SafeString(itemSpellName, nil)
        itemSpellID = YRG.SafeOptionalNumber(itemSpellID)
        if itemSpellID and itemSpellID == idNum then
            return true
        end
        if itemSpellName and spName and itemSpellName:lower() == spName:lower() then
            return true
        end
    end
    return false
end

HandlePrepUIError = function(arg1, arg2)
    if not pendingPrepAttempt or not pendingPrepAttempt.clicked then return end
    local now = (type(GetTime) == "function") and GetTime() or 0
    if now > (pendingPrepAttempt.expiresAt or 0) then
        pendingPrepAttempt = nil
        return
    end

    local errType = (type(arg1) == "number" and not IsSecret(arg1)) and arg1 or nil
    local rawMsg = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or nil
    local msg = YRG.SafeString(rawMsg, nil)
    if not msg and errType and type(GetGameMessageInfo) == "function" then
        local okG, gMsg = pcall(GetGameMessageInfo, errType)
        if okG then msg = YRG.SafeString(gMsg, nil) end
    end

    local blockType, reasonText, ttl = ClassifyPrepUIError(msg)
    if not blockType then
        return
    end

    local attempt = pendingPrepAttempt
    pendingPrepAttempt = nil

    local auras = ReadPlayerAuras()
    local weaponLabel = nil
    local equipLink = nil
    if attempt.slot then
        weaponLabel = GetSlotEnchantLabel(InspectWeaponEnchantState(attempt.slot))
        equipLink = GetInventoryItemLink and GetInventoryItemLink("player", attempt.slot) or nil
    end

    blockedPrepActions[attempt.actionKey] = {
        label = attempt.label,
        blockType = blockType,
        reason = reasonText,
        expiresAt = now + (ttl or 60),
        auraSnap = (blockType == "MORE_POWERFUL") and SnapshotPlayerAuraNames(auras) or nil,
        slot = attempt.slot,
        equipLink = equipLink,
        weaponLabel = weaponLabel,
    }
    lastPrepTrace = lastPrepTrace .. string.format(" | Blocked(%s:%s)", tostring(attempt.label), tostring(blockType))

    local warnKey = "ERR:" .. tostring(attempt.actionKey) .. ":" .. tostring(blockType)
    if not lastWarnAtByKey[warnKey] or (now - lastWarnAtByKey[warnKey]) >= 3.0 then
        lastWarnAtByKey[warnKey] = now
        print(string.format("|cffffd100YRG OB Prep:|r Skipping %s (%s).", attempt.label, reasonText))
    end
end

HandlePrepUnitSpellcast = function(event, spellID)
    if not pendingPrepAttempt or not pendingPrepAttempt.clicked then return end
    local now = (type(GetTime) == "function") and GetTime() or 0
    if now > (pendingPrepAttempt.expiresAt or 0) then
        pendingPrepAttempt = nil
        return
    end
    if DoesSpellIDMatchAttempt(pendingPrepAttempt, spellID) then
        if event == "UNIT_SPELLCAST_START" then
            pendingPrepAttempt.expiresAt = now + 5.0
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            pendingPrepAttempt = nil
        end
    end
end

HandlePrepStateInvalidation = function(event)
    if event == "DISABLE" then
        pendingPrepAttempt = nil
        blockedPrepActions = {}
        lastWarnAtByKey = {}
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        pendingPrepAttempt = nil
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        for k, entry in pairs(blockedPrepActions) do
            if entry.blockType == "MISSING_REAGENT" then
                blockedPrepActions[k] = nil
            end
        end
        return
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        for k, entry in pairs(blockedPrepActions) do
            if entry.blockType == "SHAPESHIFT" then
                blockedPrepActions[k] = nil
            end
        end
        return
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
        for k, entry in pairs(blockedPrepActions) do
            if entry.slot then
                local curLink = GetInventoryItemLink and GetInventoryItemLink("player", entry.slot) or nil
                if curLink ~= entry.equipLink then
                    blockedPrepActions[k] = nil
                end
            end
        end
        return
    elseif event == "UNIT_AURA" then
        if next(blockedPrepActions) ~= nil then
            PruneBlockedPrepActions(ReadPlayerAuras(), nil, nil)
        end
        return
    end
end

local function ScanPlayerSpellBook()
    local knownByLow = {}
    local list = {}
    local knownMaxRankByLow = {}

    local function RecordRank(low, spellId, subName)
        local r = GetSafeSpellRankNumber(spellId, subName)
        if not r and spellId then
            r = GetSafeSpellRankNumber(spellId)
        end
        if r and (not knownMaxRankByLow[low] or r > knownMaxRankByLow[low]) then
            knownMaxRankByLow[low] = r
        end
    end

    if C_SpellBook and type(C_SpellBook.GetNumSpellBookSkillLines) == "function"
        and type(C_SpellBook.GetSpellBookSkillLineInfo) == "function"
        and type(C_SpellBook.GetSpellBookItemInfo) == "function" then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "player"
        local spellType = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
        local numLines = YRG.SafeNumber(C_SpellBook.GetNumSpellBookSkillLines(), 0)
        for line = 1, numLines do
            local okL, lineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
            if okL and type(lineInfo) == "table" then
                local offset = YRG.SafeNumber(lineInfo.itemIndexOffset, 0)
                local count = YRG.SafeNumber(lineInfo.numSpellBookItems, 0)
                for idx = offset + 1, offset + count do
                    local okI, info = pcall(C_SpellBook.GetSpellBookItemInfo, idx, bank)
                    if okI and type(info) == "table" and info.itemType == spellType and not info.isPassive then
                        local nm = YRG.SafeString(info.name, nil)
                        if nm then
                            local low = nm:lower()
                            local sid = YRG.SafeOptionalNumber(info.spellID)
                            if not knownByLow[low] then
                                knownByLow[low] = nm
                                list[#list + 1] = { name = nm, low = low, spellId = sid }
                            end
                            RecordRank(low, sid, info.subName)
                        end
                    end
                end
            end
        end
    elseif type(GetNumSpellTabs) == "function" and type(GetSpellTabInfo) == "function" then
        local bookType = BOOKTYPE_SPELL or "spell"
        local numTabs = YRG.SafeNumber(GetNumSpellTabs(), 0)
        for t = 1, numTabs do
            local _, _, offset, numEntries = GetSpellTabInfo(t)
            offset = YRG.SafeNumber(offset, 0)
            numEntries = YRG.SafeNumber(numEntries, 0)
            for idx = offset + 1, offset + numEntries do
                local stype, sid = GetSpellBookItemInfo and GetSpellBookItemInfo(idx, bookType)
                if stype == "SPELL" then
                    local nm, subName
                    if GetSpellBookItemName then
                        local rawNm, rawSub = GetSpellBookItemName(idx, bookType)
                        nm = YRG.SafeString(rawNm, nil)
                        subName = YRG.SafeString(rawSub, nil)
                    end
                    if nm then
                        local low = nm:lower()
                        local isPassive = type(IsPassiveSpell) == "function" and IsPassiveSpell(idx, bookType)
                        if not isPassive then
                            sid = YRG.SafeOptionalNumber(sid)
                            if not knownByLow[low] then
                                knownByLow[low] = nm
                                list[#list + 1] = { name = nm, low = low, spellId = sid }
                            end
                            RecordRank(low, sid, subName)
                        end
                    end
                end
            end
        end
    end

    for low, actualName in pairs(knownByLow) do
        if not knownMaxRankByLow[low] then
            RecordRank(low, actualName, nil)
        end
    end

    return knownByLow, list, knownMaxRankByLow
end

local function IsSpellKnownAndReady(spellName, knownByLow)
    if type(spellName) ~= "string" or spellName == "" then return false end
    local low = spellName:lower()
    local actualName = (knownByLow and knownByLow[low])
    if not actualName then
        return false
    end

    local usable, noMana
    if C_Spell and type(C_Spell.IsSpellUsable) == "function" then
        local ok, u, nm = pcall(C_Spell.IsSpellUsable, actualName)
        if ok then usable, noMana = u, nm end
    elseif type(IsUsableSpell) == "function" then
        local ok, u, nm = pcall(IsUsableSpell, actualName)
        if ok then usable, noMana = u, nm end
    end
    if not IsSecret(noMana) and noMana then
        return false, "resources"
    end
    if not IsSecret(usable) and usable == false then
        return false, "unusable"
    end

    local start, duration = 0, 0
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local ok, cd = pcall(C_Spell.GetSpellCooldown, actualName)
        if ok and type(cd) == "table" then
            start = YRG.SafeNumber(cd.startTime, 0)
            duration = YRG.SafeNumber(cd.duration, 0)
        end
    elseif type(GetSpellCooldown) == "function" then
        local ok, st, dur = pcall(GetSpellCooldown, actualName)
        if ok then
            start = YRG.SafeNumber(st, 0)
            duration = YRG.SafeNumber(dur, 0)
        end
    end
    if start > 0 and duration > 1.5 then
        local now = (type(GetTime) == "function") and GetTime() or 0
        if (start + duration - now) > 0.25 then
            return false, "cooldown"
        end
    end

    return true, actualName
end

local function ResolveSpellTargetUnit(spellName)
    if type(spellName) ~= "string" then return nil end
    local low = spellName:lower()
    if FRIENDLY_TARGET_BUFFS[low] then
        return "player"
    end
    if C_Spell and type(C_Spell.SpellHasRange) == "function" then
        local ok, hasRange = pcall(C_Spell.SpellHasRange, spellName)
        if ok and not IsSecret(hasRange) and hasRange then
            return "player"
        end
    elseif type(SpellHasRange) == "function" then
        local ok, hasRange = pcall(SpellHasRange, spellName)
        if ok and not IsSecret(hasRange) and hasRange then
            return "player"
        end
    end
    return nil
end

local function ResolveOverrideBuffSpell(term, knownByLow, knownList)
    local clean = StripColorCodes(term)
    if clean == "" then return nil end
    local low = clean:lower()

    if knownByLow[low] then
        return knownByLow[low]
    end

    local aliases = BUFF_ALIAS_EXPANSIONS[low]
    if aliases then
        for _, cand in ipairs(aliases) do
            if knownByLow[cand:lower()] then
                return knownByLow[cand:lower()]
            end
        end
    end

    local bestStarts, bestAny = nil, nil
    for _, entry in ipairs(knownList) do
        if entry.low:sub(1, #low) == low then
            if not bestStarts or #entry.name < #bestStarts then
                bestStarts = entry.name
            end
        elseif entry.low:find(low, 1, true) then
            if not bestAny or #entry.name < #bestAny then
                bestAny = entry.name
            end
        end
    end
    return bestStarts or bestAny
end

local function ShouldRefreshPoison(weaponState, selectionKey, bagItem, overbuffMinutes)
    local desiredFam = ParsePoisonSelection(selectionKey)
    if not desiredFam or not weaponState.equipped or not weaponState.canPoison then
        return false
    end

    local active = weaponState.activePoison
    if not active then
        return true
    end
    if active.family ~= desiredFam then
        return true
    end
    if bagItem and active.rank and bagItem.rank and bagItem.rank > active.rank then
        return true
    end
    if overbuffMinutes > 0 and active.minsLeft ~= nil and active.minsLeft <= overbuffMinutes then
        return true
    end
    return false
end

local function ShouldRefreshWeaponEnhancement(weaponState, wantsOil, wantsStone, overbuffMinutes)
    if not weaponState.equipped or not weaponState.canPoison then
        return false
    end
    if wantsOil then
        if weaponState.activeOil then
            if overbuffMinutes > 0 and weaponState.activeOil.minsLeft ~= nil and weaponState.activeOil.minsLeft <= overbuffMinutes then
                return true
            end
            return false
        end
        return true -- Missing Oil (or Stone needs upgrade to superseding Oil)
    elseif wantsStone and weaponState.stoneKind then
        if weaponState.activeStone then
            if overbuffMinutes > 0 and weaponState.activeStone.minsLeft ~= nil and weaponState.activeStone.minsLeft <= overbuffMinutes then
                return true
            end
            return false
        elseif weaponState.activeOil then
            return false -- Do not overwrite existing Oil with a lower Stone
        end
        return true
    end
    return false
end

local function LookupConsumableTables(lowItem)
    local aliases = CONSUMABLE_AURA_ALIASES[lowItem]
    local stronger = CONSUMABLE_STRONGER_AURAS[lowItem]
    if (not aliases or not stronger) and lowItem:find("^scroll of ") then
        local baseScroll = lowItem:gsub("%s+[ivx]+$", "")
        aliases = aliases or CONSUMABLE_AURA_ALIASES[baseScroll]
        stronger = stronger or CONSUMABLE_STRONGER_AURAS[baseScroll]
    end
    return aliases, stronger
end

local function IsConsumableBuffCovered(itemName, itemLink, itemID, auras, buffOverbuffMinutes)
    if type(itemName) ~= "string" or itemName == "" then
        return false, nil, nil
    end
    local lowItem = itemName:lower()
    local aliases, stronger = LookupConsumableTables(lowItem)

    -- Strictly stronger buff active (even if <= overbuff min left) blocks weaker consumable
    if stronger then
        local strongerAura = FindMatchingAuraByNames(stronger, auras)
        if strongerAura then
            local kind = IsAuraSatisfied(strongerAura, buffOverbuffMinutes) and "active" or "stronger"
            return true, kind, strongerAura.name
        end
    end

    if lowItem:find("^flask of") then
        for _, aura in ipairs(auras) do
            if aura.lowName:find("^flask of")
                or aura.lowName == "supreme power"
                or aura.lowName == "titans"
                or aura.lowName == "distilled wisdom"
                or aura.lowName == "chromatic resistance" then
                if IsAuraSatisfied(aura, buffOverbuffMinutes) then
                    return true, "active", aura.name
                end
            end
        end
    end

    local itemSpellName, itemSpellID
    if itemLink or itemID then
        if C_Item and type(C_Item.GetItemSpell) == "function" then
            itemSpellName, itemSpellID = C_Item.GetItemSpell(itemLink or itemID)
        elseif type(GetItemSpell) == "function" then
            itemSpellName, itemSpellID = GetItemSpell(itemLink or itemID)
        end
        itemSpellName = YRG.SafeString(itemSpellName, nil)
        itemSpellID = YRG.SafeOptionalNumber(itemSpellID)
    end

    local candidateNames = { [lowItem] = true }
    if itemSpellName then
        candidateNames[itemSpellName:lower()] = true
    end
    if aliases then
        for _, alias in ipairs(aliases) do
            candidateNames[alias] = true
        end
    end

    for _, aura in ipairs(auras) do
        if (itemSpellID and aura.spellId == itemSpellID) or candidateNames[aura.lowName] then
            if IsAuraSatisfied(aura, buffOverbuffMinutes) then
                return true, "active", aura.name
            end
        end
    end
    return false, nil, nil
end

local function IsConsumableItemBuffActive(bagItem, auras, buffOverbuffMinutes)
    return IsConsumableBuffCovered(bagItem and bagItem.name, bagItem and bagItem.link, bagItem and bagItem.itemID, auras, buffOverbuffMinutes)
end

local function IsStrongerBuffBlockingSpell(spellLow, auras, knownMaxRankByLow)
    if type(spellLow) ~= "string" or spellLow == "" then
        return false, nil
    end

    local strongerNames = STRONGER_SPELL_AURAS[spellLow]
    if strongerNames then
        local strongerAura = FindMatchingAuraByNames(strongerNames, auras)
        if strongerAura then
            return true, string.format("a more powerful buff (%s) is already active", strongerAura.name)
        end
    end

    local playerRank = knownMaxRankByLow and knownMaxRankByLow[spellLow]
    if playerRank then
        for _, aura in ipairs(auras) do
            if aura.lowName == spellLow and aura.rankNum and aura.rankNum > playerRank then
                return true, string.format("a higher rank %s (Rank %d) is already active", aura.name, aura.rankNum)
            end
        end
    end

    if spellLow == "power word: shield" and HasPlayerDebuff("weakened soul") then
        return true, "Weakened Soul is active"
    end

    return false, nil
end

local function EvaluateNextOBPrepAction(db)
    local weaponOverbuff = math.max(0, math.min(30, math.floor(YRG.SafeNumber(db and db.obPrepWeaponOverbuffMinutes, 5) + 0.5)))
    local buffOverbuff = math.max(0, math.min(30, math.floor(YRG.SafeNumber(db and db.obPrepBuffOverbuffMinutes, 5) + 0.5)))
    local cls = select(2, UnitClass("player"))
    local liveClass = (not IsSecret(cls) and cls) or playerClass
    local mhState = InspectWeaponEnchantState(INV_SLOT_MAINHAND)
    local ohState = InspectWeaponEnchantState(INV_SLOT_OFFHAND)
    local auras = ReadPlayerAuras()
    local warnings = {}
    local skippedNotes = {}

    PruneBlockedPrepActions(auras, mhState, ohState)

    local now = (type(GetTime) == "function") and GetTime() or 0
    if lastStoneAppliedInfo and (now - lastStoneAppliedInfo.at) < 12 then
        local checkedState = (lastStoneAppliedInfo.slot == INV_SLOT_MAINHAND) and mhState or ohState
        if lastStoneAppliedInfo.hadPoison and not checkedState.activePoison and (checkedState.activeStone or checkedState.activeOil) then
            if (now - lastStoneOverwriteNoteAt) > 10 then
                lastStoneOverwriteNoteAt = now
                print("|cffffd100YRG OB Prep:|r Item Enhancement replaced your active Poison on that weapon (this client supports one temporary weapon enchant per slot).")
            end
        end
    end

    -- 1. STAGE 1: Poisons (Rogues only, Main Hand then Off Hand)
    if liveClass == "ROGUE" then
        local poisonHands = {
            { slot = INV_SLOT_MAINHAND, handLabel = "Main Hand", state = mhState, sel = db.obPrepMainHand },
            { slot = INV_SLOT_OFFHAND,  handLabel = "Off Hand",  state = ohState, sel = db.obPrepOffHand },
        }
        for _, h in ipairs(poisonHands) do
            local fam = ParsePoisonSelection(h.sel)
            if fam and h.state.equipped and h.state.canPoison then
                local bagItem, sawBlocked, minLevelBlocked = FindPoisonInBags(h.sel, function(itemID)
                    return IsPrepKeyBlocked(MakeWeaponActionKey(h.slot, "POISON", itemID))
                end)
                if ShouldRefreshPoison(h.state, h.sel, bagItem, weaponOverbuff) then
                    if bagItem then
                        return {
                            actionType = "WEAPON_ITEM",
                            kind = "POISON",
                            slot = h.slot,
                            handLabel = h.handLabel,
                            item = bagItem,
                        }, mhState, ohState, auras, warnings, skippedNotes
                    elseif not sawBlocked then
                        local famLabel = POISON_FAMILIES[fam] and POISON_FAMILIES[fam].label or fam
                        if minLevelBlocked then
                            warnings[#warnings + 1] = string.format("%s for %s requires level %d.", famLabel, h.handLabel, minLevelBlocked)
                        else
                            warnings[#warnings + 1] = string.format("Missing %s for %s in bags.", famLabel, h.handLabel)
                        end
                    end
                end
            end
        end
    end

    local cachedKnownByLow, cachedKnownList, cachedKnownMaxRankByLow
    local function GetSpellBookCached()
        if not cachedKnownByLow then
            cachedKnownByLow, cachedKnownList, cachedKnownMaxRankByLow = ScanPlayerSpellBook()
        end
        return cachedKnownByLow, cachedKnownList, cachedKnownMaxRankByLow
    end

    -- 2. STAGE 2: Weapon Item Enhancements (Wizard/Mana Oils supersede Stones if both checked; MH then OH)
    if db.obPrepUseWizardOils or db.obPrepUseStones then
        local wantsOil = db.obPrepUseWizardOils and true or false
        local wantsStone = db.obPrepUseStones and true or false
        local shamanHasImbueSpell = false
        if liveClass == "SHAMAN" and db.obPrepAutoSelfBuff ~= false then
            local knownByLow = GetSpellBookCached()
            for imbueLow in pairs(SHAMAN_IMBUE_SPELLS) do
                if knownByLow[imbueLow] then
                    shamanHasImbueSpell = true
                    break
                end
            end
        end

        local enhHands = {
            { slot = INV_SLOT_MAINHAND, handLabel = "Main Hand", state = mhState, poisonSel = db.obPrepMainHand },
            { slot = INV_SLOT_OFFHAND,  handLabel = "Off Hand",  state = ohState, poisonSel = db.obPrepOffHand },
        }
        for _, h in ipairs(enhHands) do
            if h.state.equipped and h.state.canPoison then
                local skipForRoguePoison = (liveClass == "ROGUE")
                    and (ParsePoisonSelection(h.poisonSel) ~= nil)
                    and (h.state.activePoison ~= nil)
                local skipForShamanImbue = (liveClass == "SHAMAN")
                    and (db.obPrepAutoSelfBuff ~= false)
                    and (h.state.activeImbue ~= nil)

                if not skipForRoguePoison and not skipForShamanImbue then
                    local triedOilAndMissing = false
                    if wantsOil and ShouldRefreshWeaponEnhancement(h.state, true, false, weaponOverbuff) then
                        local oilItem, sawBlockedOil, minLevelOil = FindBestOilInBags(function(itemID)
                            return IsPrepKeyBlocked(MakeWeaponActionKey(h.slot, "OIL", itemID))
                        end)
                        if oilItem then
                            return {
                                actionType = "WEAPON_ITEM",
                                kind = "OIL",
                                slot = h.slot,
                                handLabel = h.handLabel,
                                hadPoison = (h.state.activePoison ~= nil),
                                item = oilItem,
                            }, mhState, ohState, auras, warnings, skippedNotes
                        else
                            triedOilAndMissing = true
                            if (not wantsStone or not h.state.stoneKind) and not sawBlockedOil then
                                if minLevelOil then
                                    warnings[#warnings + 1] = string.format("Wizard / Mana Oil for %s requires level %d.", h.handLabel, minLevelOil)
                                else
                                    warnings[#warnings + 1] = string.format("Missing usable Wizard / Mana Oil for %s in bags.", h.handLabel)
                                end
                            end
                        end
                    end

                    if wantsStone and h.state.stoneKind and ShouldRefreshWeaponEnhancement(h.state, false, true, weaponOverbuff) then
                        local stoneItem, sawBlockedStone, minLevelStone = FindBestStoneInBags(h.state.stoneKind, function(itemID)
                            return IsPrepKeyBlocked(MakeWeaponActionKey(h.slot, "STONE", itemID))
                        end)
                        if stoneItem then
                            return {
                                actionType = "WEAPON_ITEM",
                                kind = "STONE",
                                slot = h.slot,
                                handLabel = h.handLabel,
                                hadPoison = (h.state.activePoison ~= nil),
                                item = stoneItem,
                            }, mhState, ohState, auras, warnings, skippedNotes
                        elseif not sawBlockedStone and not (liveClass == "SHAMAN" and shamanHasImbueSpell) then
                            local stoneLabel = (h.state.stoneKind == "BLUNT") and "Weightstone" or "Sharpening Stone"
                            if triedOilAndMissing then
                                warnings[#warnings + 1] = string.format("Missing usable %s or Oil for %s in bags.", stoneLabel, h.handLabel)
                            elseif minLevelStone then
                                warnings[#warnings + 1] = string.format("%s for %s requires level %d.", stoneLabel, h.handLabel, minLevelStone)
                            else
                                warnings[#warnings + 1] = string.format("Missing usable %s for %s in bags.", stoneLabel, h.handLabel)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3. STAGE 3: Food Buff
    if db.obPrepUseFoodBuff then
        local foodTerms = SplitCSV(db.obPrepFoodName)
        if #foodTerms > 0 then
            local eatingAura = FindMatchingAuraByNames({ "food", "drink", "food & drink", "refreshment" }, auras)
            local wellFedAura = FindMatchingAuraByNames({ "well fed" }, auras)
            local foodReady = false
            if eatingAura then
                foodReady = true
            elseif wellFedAura and IsAuraSatisfied(wellFedAura, buffOverbuff) then
                foodReady = true
            else
                for _, foodTerm in ipairs(foodTerms) do
                    local exactAura = FindMatchingAuraByNames({ foodTerm:lower() }, auras)
                    if exactAura and IsAuraSatisfied(exactAura, buffOverbuff) then
                        foodReady = true
                        break
                    end
                end
            end

            if not foodReady then
                local foundFood = nil
                local anyCooldown, anyBlocked, minLvlFood = false, false, nil
                for _, foodTerm in ipairs(foodTerms) do
                    local item, sawCD, sawBlk, minLvl = FindNamedItemInBags(foodTerm, function(itemID)
                        return IsPrepKeyBlocked(MakeBagItemActionKey("FOOD", itemID))
                    end)
                    if item then
                        foundFood = item
                        break
                    end
                    if sawCD then anyCooldown = true end
                    if sawBlk then anyBlocked = true end
                    if minLvl and (not minLvlFood or minLvl < minLvlFood) then minLvlFood = minLvl end
                end
                if foundFood then
                    return {
                        actionType = "BAG_ITEM",
                        kind = "FOOD",
                        item = foundFood,
                    }, mhState, ohState, auras, warnings, skippedNotes
                elseif anyCooldown then
                    warnings[#warnings + 1] = "Configured Food Buff is currently on cooldown."
                elseif minLvlFood and not anyBlocked then
                    warnings[#warnings + 1] = string.format("Configured Food Buff (%s) requires level %d.", table.concat(foodTerms, ", "), minLvlFood)
                elseif not anyBlocked then
                    warnings[#warnings + 1] = "Missing configured Food Buff (" .. table.concat(foodTerms, ", ") .. ") in bags."
                end
            end
        end
    end

    -- 4. STAGE 4: Potions / Elixirs
    if db.obPrepUseElixirs and type(db.obPrepElixirList) == "table" then
        for _, entryName in ipairs(db.obPrepElixirList) do
            local bagItem, sawCD, sawBlocked, minLevelBlocked = FindNamedItemInBags(entryName, function(itemID)
                return IsPrepKeyBlocked(MakeBagItemActionKey("ELIXIR", itemID))
            end)
            if bagItem then
                local covered, reasonKind, blockerName = IsConsumableItemBuffActive(bagItem, auras, buffOverbuff)
                if not covered then
                    return {
                        actionType = "BAG_ITEM",
                        kind = "ELIXIR",
                        item = bagItem,
                    }, mhState, ohState, auras, warnings, skippedNotes
                elseif reasonKind == "stronger" then
                    skippedNotes[#skippedNotes + 1] = string.format("Skipped %s (stronger %s is active).", bagItem.name, tostring(blockerName))
                end
            else
                local alreadyCovered = IsConsumableBuffCovered(entryName, nil, nil, auras, buffOverbuff)
                if not alreadyCovered and not sawBlocked and not sawCD then
                    if minLevelBlocked then
                        warnings[#warnings + 1] = string.format("%s in bags requires level %d.", tostring(entryName), minLevelBlocked)
                    else
                        warnings[#warnings + 1] = "Missing " .. tostring(entryName) .. " in bags."
                    end
                elseif not alreadyCovered and sawCD then
                    warnings[#warnings + 1] = tostring(entryName) .. " is currently on cooldown."
                end
            end
        end
    end

    -- 5. STAGE 5: Self-Buffs (Override CSV or Level-Aware Class Priority)
    if db.obPrepAutoSelfBuff ~= false then
        local knownByLow, knownList, knownMaxRankByLow = GetSpellBookCached()

        if db.obPrepOverrideBuffs then
            local customTerms = SplitCSV(db.obPrepOverrideBuffsCSV)
            for _, term in ipairs(customTerms) do
                local spellName = ResolveOverrideBuffSpell(term, knownByLow, knownList)
                if spellName then
                    local low = spellName:lower()
                    local satisfied = false
                    if SHAMAN_IMBUE_SPELLS[low] then
                        if mhState.equipped and mhState.canPoison and mhState.activeImbue then
                            local eff = EffectiveOverbuffThreshold(buffOverbuff, 5)
                            if mhState.activeImbue.minsLeft == nil or mhState.activeImbue.minsLeft > eff then
                                satisfied = true
                            end
                        elseif not mhState.equipped or not mhState.canPoison then
                            satisfied = true
                        end
                    else
                        local checkNames = { low }
                        if low == "mark of the wild" then checkNames[#checkNames + 1] = "gift of the wild"
                        elseif low == "power word: fortitude" then checkNames[#checkNames + 1] = "prayer of fortitude"
                        elseif low == "divine spirit" then checkNames[#checkNames + 1] = "prayer of spirit"
                        elseif low == "shadow protection" then checkNames[#checkNames + 1] = "prayer of shadow protection"
                        elseif low == "arcane intellect" then checkNames[#checkNames + 1] = "arcane brilliance"
                        elseif low:sub(1, 12) == "blessing of " then checkNames[#checkNames + 1] = "greater " .. low
                        end
                        local aura = FindMatchingAuraByNames(checkNames, auras)
                        satisfied = IsAuraSatisfied(aura, buffOverbuff)
                        if not satisfied then
                            local blockedByStronger, strongerReason = IsStrongerBuffBlockingSpell(low, auras, knownMaxRankByLow)
                            if blockedByStronger then
                                satisfied = true
                                skippedNotes[#skippedNotes + 1] = string.format("Skipped %s (%s).", spellName, strongerReason)
                            end
                        end
                    end

                    if not satisfied and not IsPrepKeyBlocked(MakeSpellActionKey(spellName)) then
                        local ready, res = IsSpellKnownAndReady(spellName, knownByLow)
                        if ready then
                            return {
                                actionType = "SPELL",
                                kind = "BUFF",
                                spell = res,
                                unit = ResolveSpellTargetUnit(res),
                            }, mhState, ohState, auras, warnings, skippedNotes
                        elseif res == "resources" then
                            warnings[#warnings + 1] = "Not enough Mana/Rage for " .. spellName .. "."
                        elseif res == "unusable" then
                            warnings[#warnings + 1] = "Cannot cast " .. spellName .. " right now (missing reagent or form condition)."
                        end
                    end
                else
                    warnings[#warnings + 1] = "Override buff not learned/found: " .. term
                end
            end
        else
            local classGroups = CLASS_BUFF_PRIORITIES[liveClass]
            if classGroups then
                for _, grp in ipairs(classGroups) do
                    local petOk = (not grp.requiresPet) or (UnitExists and UnitExists("pet") and not (UnitIsDead and UnitIsDead("pet")))
                    if petOk and grp.weaponImbue then
                        if mhState.equipped and mhState.canPoison and not mhState.activeStone and not mhState.activeOil and not mhState.activePoison then
                            local needImbue = false
                            if not mhState.activeImbue then
                                needImbue = true
                            else
                                local eff = EffectiveOverbuffThreshold(buffOverbuff, 5)
                                if mhState.activeImbue.minsLeft ~= nil and mhState.activeImbue.minsLeft <= eff then
                                    needImbue = true
                                end
                            end
                            if needImbue then
                                for _, candSpell in ipairs(grp.cast) do
                                    if not IsPrepKeyBlocked(MakeSpellActionKey(candSpell)) then
                                        local ready, res = IsSpellKnownAndReady(candSpell, knownByLow)
                                        if ready then
                                            return {
                                                actionType = "SPELL",
                                                kind = "BUFF",
                                                spell = res,
                                                unit = nil,
                                            }, mhState, ohState, auras, warnings, skippedNotes
                                        end
                                    end
                                end
                            end
                        end
                    elseif petOk and grp.match then
                        local activeAura = FindMatchingAuraByNames(grp.match, auras)
                        if not IsAuraSatisfied(activeAura, buffOverbuff) then
                            local chosenSpell = nil
                            if activeAura and grp.keepActive then
                                local cleanName = activeAura.lowName:gsub("^greater%s+", "")
                                if knownByLow[cleanName] then
                                    chosenSpell = knownByLow[cleanName]
                                end
                            end
                            if not chosenSpell then
                                for _, candSpell in ipairs(grp.cast) do
                                    if knownByLow[candSpell:lower()] then
                                        chosenSpell = knownByLow[candSpell:lower()]
                                        break
                                    end
                                end
                            end
                            if chosenSpell then
                                local blockedByStronger, strongerReason = IsStrongerBuffBlockingSpell(chosenSpell:lower(), auras, knownMaxRankByLow)
                                if blockedByStronger then
                                    skippedNotes[#skippedNotes + 1] = string.format("Skipped %s (%s).", chosenSpell, strongerReason)
                                elseif not IsPrepKeyBlocked(MakeSpellActionKey(chosenSpell)) then
                                    local ready, res = IsSpellKnownAndReady(chosenSpell, knownByLow)
                                    if ready then
                                        return {
                                            actionType = "SPELL",
                                            kind = "BUFF",
                                            spell = res,
                                            unit = grp.target or ResolveSpellTargetUnit(res),
                                        }, mhState, ohState, auras, warnings, skippedNotes
                                    elseif res == "resources" then
                                        warnings[#warnings + 1] = "Not enough Mana/Rage for " .. chosenSpell .. "."
                                    elseif res == "unusable" then
                                        warnings[#warnings + 1] = "Cannot cast " .. chosenSpell .. " right now (missing reagent or form condition)."
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil, mhState, ohState, auras, warnings, skippedNotes
end

local function PrintOBPrepWarnings(warnings, skippedNotes, isMovingOn, now)
    local toPrint = {}
    local seen = {}
    local throttleSec = isMovingOn and 15.0 or 2.5

    if type(warnings) == "table" then
        for _, w in ipairs(warnings) do
            if type(w) == "string" and w ~= "" and not seen[w] then
                seen[w] = true
                if (not isMovingOn) or (not lastWarnAtByKey[w]) or ((now - lastWarnAtByKey[w]) >= throttleSec) then
                    toPrint[#toPrint + 1] = w
                end
            end
        end
    end

    if not isMovingOn and type(skippedNotes) == "table" then
        for _, note in ipairs(skippedNotes) do
            if type(note) == "string" and note ~= "" and not seen[note] then
                seen[note] = true
                if (not lastWarnAtByKey[note]) or ((now - lastWarnAtByKey[note]) >= 10.0) then
                    toPrint[#toPrint + 1] = note
                end
            end
        end
    end

    if #toPrint == 0 then return end

    for _, msg in ipairs(toPrint) do
        lastWarnAtByKey[msg] = now
    end

    if isMovingOn then
        if #toPrint == 1 then
            print("|cffffd100YRG OB Prep:|r " .. toPrint[1]:gsub("%.$", "") .. " (skipping).")
        else
            local parts = {}
            for _, msg in ipairs(toPrint) do
                parts[#parts + 1] = msg:gsub("%.$", "")
            end
            print("|cffffd100YRG OB Prep:|r Skipping: " .. table.concat(parts, "; ") .. ".")
        end
    else
        for _, msg in ipairs(toPrint) do
            print("|cffffd100YRG OB Prep:|r " .. msg)
        end
    end
end

local function RunOBPrepSlash(args)
    EnsureRoguePrepButtons()
    ClearRoguePrepActionAttributes()

    local modDB = YRG:GetModuleDB("ClassImprovementsModule")
    if not modDB or not modDB.enabled then
        print("|cffffd100YRG OB Prep:|r ClassImprovementsModule is disabled in /yrg settings.")
        return
    end

    local cmd = (type(args) == "string") and args:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if cmd == "macro" then
        EnsureRoguePrepMacro(true, true)
        return
    elseif cmd == "debug" then
        prepDebugMode = not prepDebugMode
        print("|cffffd100YRG OB Prep:|r Debug trace " .. (prepDebugMode and "|cff00ff00ON|r" or "|cffff6666OFF|r"))
        return
    elseif cmd == "clear" or cmd == "reset" then
        blockedPrepActions = {}
        pendingPrepAttempt = nil
        lastWarnAtByKey = {}
        lastMissingWarnAt = 0
        print("|cffffd100YRG OB Prep:|r Cleared runtime skip locks and warning timers.")
        return
    elseif cmd == "status" then
        local action, mhState, ohState, auras, warnings, skippedNotes = EvaluateNextOBPrepAction(modDB)
        local function FmtSlotState(st)
            if not st.equipped then return "Empty" end
            local parts = {}
            if st.activePoison then parts[#parts + 1] = st.activePoison.label .. (st.activePoison.minsLeft and string.format(" [%.1fm]", st.activePoison.minsLeft) or "") end
            if st.activeOil then parts[#parts + 1] = st.activeOil.label .. (st.activeOil.minsLeft and string.format(" [%.1fm]", st.activeOil.minsLeft) or "") end
            if st.activeStone then parts[#parts + 1] = st.activeStone.label .. (st.activeStone.minsLeft and string.format(" [%.1fm]", st.activeStone.minsLeft) or "") end
            if st.activeImbue then parts[#parts + 1] = st.activeImbue.label .. (st.activeImbue.minsLeft and string.format(" [%.1fm]", st.activeImbue.minsLeft) or "") end
            if #parts == 0 then return "None" end
            return table.concat(parts, " + ")
        end
        local macroIdx = (type(GetMacroIndexByName) == "function") and GetMacroIndexByName(OB_PREP_MACRO_NAME) or 0
        local macroExists = (macroIdx and macroIdx > 0) and "Present" or "Missing"
        local nextStr = "All ready"
        if action then
            if action.actionType == "WEAPON_ITEM" then
                nextStr = string.format("%s -> %s (%s bag=%d slot=%d inv=%d)", action.handLabel, action.item.name, action.kind, action.item.bag, action.item.slot, action.slot)
            elseif action.actionType == "BAG_ITEM" then
                nextStr = string.format("%s -> %s (bag=%d slot=%d)", action.kind, action.item.name, action.item.bag, action.item.slot)
            elseif action.actionType == "SPELL" then
                nextStr = string.format("BUFF -> %s", action.spell)
            end
        end
        print(string.format("|cffffd100YRG OB Prep:|r Macro %s=%s (UseKeyDown=%s Auras=%d) | MH: %s | OH: %s | Next: %s",
            OB_PREP_MACRO_NAME, macroExists, tostring(IsActionButtonUseKeyDown()), #auras, FmtSlotState(mhState), FmtSlotState(ohState), nextStr))
        print("|cffffd100YRG OB Prep Trace:|r " .. tostring(lastPrepTrace))
        for _, w in ipairs(warnings) do
            print("|cffffd100YRG OB Prep:|r " .. w)
        end
        if type(skippedNotes) == "table" then
            for _, note in ipairs(skippedNotes) do
                print("|cffffd100YRG OB Prep:|r " .. note)
            end
        end
        for _, entry in pairs(blockedPrepActions) do
            print(string.format("|cffffd100YRG OB Prep Skip:|r %s (%s)", tostring(entry.label), tostring(entry.reason)))
        end
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd100YRG OB Prep:|r Cannot prepare while in combat.")
        return
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        return
    end
    if IsMounted and IsMounted() then
        print("|cffffd100YRG OB Prep:|r Dismount before using OB Prep.")
        return
    end

    EnsureRoguePrepMacro(false, false)

    if HasPlainCastInfo(UnitCastingInfo, "player") or HasPlainCastInfo(UnitChannelInfo, "player") then
        return
    end

    local action, _, _, _, warnings, skippedNotes = EvaluateNextOBPrepAction(modDB)
    local now = (type(GetTime) == "function") and GetTime() or 0
    if not action then
        pendingPrepAttempt = nil
        if (#warnings > 0 or (skippedNotes and #skippedNotes > 0)) and (now - lastMissingWarnAt) >= 2.5 then
            lastMissingWarnAt = now
            PrintOBPrepWarnings(warnings, skippedNotes, false, now)
        end
        return
    end

    if #warnings > 0 then
        PrintOBPrepWarnings(warnings, nil, true, now)
    end

    if action.kind == "STONE" or action.kind == "OIL" then
        lastStoneAppliedInfo = { slot = action.slot, hadPoison = action.hadPoison, at = now }
    else
        lastStoneAppliedInfo = nil
    end

    if prepActionBtn then
        prepArmedUntil = now + 2.0
        pendingPrepAttempt = {
            actionKey = GetPrepActionKey(action),
            actionType = action.actionType,
            kind = action.kind,
            label = GetPrepActionLabel(action),
            spell = action.spell,
            itemID = action.item and action.item.itemID or nil,
            slot = action.slot,
            armedAt = now,
            clicked = false,
            expiresAt = now + 2.0,
        }
        if action.actionType == "WEAPON_ITEM" then
            local bagSlotStr = string.format("%d %d", action.item.bag, action.item.slot)
            prepActionBtn:SetAttribute("type", "item")
            prepActionBtn:SetAttribute("type1", "item")
            prepActionBtn:SetAttribute("item", bagSlotStr)
            prepActionBtn:SetAttribute("item1", bagSlotStr)
            prepActionBtn:SetAttribute("bag", action.item.bag)
            prepActionBtn:SetAttribute("slot", action.item.slot)
            prepActionBtn:SetAttribute("target-slot", action.slot)
            prepActionBtn:SetAttribute("target-slot1", action.slot)
            lastPrepTrace = string.format("Armed %s (%s) bag=%d slot=%d -> inv=%d",
                tostring(action.item.name), tostring(action.kind), action.item.bag, action.item.slot, action.slot)
        elseif action.actionType == "BAG_ITEM" then
            local bagSlotStr = string.format("%d %d", action.item.bag, action.item.slot)
            prepActionBtn:SetAttribute("type", "item")
            prepActionBtn:SetAttribute("type1", "item")
            prepActionBtn:SetAttribute("item", bagSlotStr)
            prepActionBtn:SetAttribute("item1", bagSlotStr)
            prepActionBtn:SetAttribute("bag", action.item.bag)
            prepActionBtn:SetAttribute("slot", action.item.slot)
            lastPrepTrace = string.format("Armed %s (%s) bag=%d slot=%d",
                tostring(action.item.name), tostring(action.kind), action.item.bag, action.item.slot)
        elseif action.actionType == "SPELL" then
            prepActionBtn:SetAttribute("type", "spell")
            prepActionBtn:SetAttribute("type1", "spell")
            prepActionBtn:SetAttribute("spell", action.spell)
            prepActionBtn:SetAttribute("spell1", action.spell)
            if action.unit then
                prepActionBtn:SetAttribute("unit", action.unit)
                prepActionBtn:SetAttribute("unit1", action.unit)
            end
            lastPrepTrace = string.format("Armed SPELL %s (unit=%s)", tostring(action.spell), tostring(action.unit))
        end
    end
end

-- ============================================================================
-- HUNTER PET AUTOFEEDER (/yrg petfeed & PetFrameHappiness Click)
-- ============================================================================
do
    local FEED_PET_SPELL_ID = 6991
    local FEED_PET_BUFF_ID = 1539
    local PET_FEED_MACRO_NAME = "YRGPF"
    local PET_FEED_MACRO_BODY = "/yrg petfeed\n/click YRGPetFeedButton LeftButton 1\n/click YRGPetFeedButton LeftButton 0"

    local DIET_DISPLAY_NAMES = {
        MEAT = "Meat",
        FISH = "Fish",
        BREAD = "Bread",
        CHEESE = "Cheese",
        FRUIT = "Fruit",
        FUNGUS = "Fungus",
    }

    local PET_DIET_BY_FAMILY = {
        ["bat"]          = { FRUIT = true, FUNGUS = true },
        ["bear"]         = { MEAT = true, FISH = true, BREAD = true, CHEESE = true, FRUIT = true, FUNGUS = true },
        ["boar"]         = { MEAT = true, FISH = true, BREAD = true, CHEESE = true, FRUIT = true, FUNGUS = true },
        ["carrion bird"] = { MEAT = true, FISH = true },
        ["cat"]          = { MEAT = true, FISH = true },
        ["crab"]         = { FISH = true, BREAD = true, FRUIT = true, FUNGUS = true },
        ["crocolisk"]    = { MEAT = true, FISH = true },
        ["dragonhawk"]   = { MEAT = true, FISH = true, FRUIT = true },
        ["gorilla"]      = { FRUIT = true, FUNGUS = true },
        ["hyena"]        = { MEAT = true, FRUIT = true },
        ["nether ray"]   = { MEAT = true, FISH = true },
        ["owl"]          = { MEAT = true, FISH = true },
        ["raptor"]       = { MEAT = true },
        ["ravager"]      = { MEAT = true },
        ["scorpid"]      = { MEAT = true },
        ["serpent"]      = { MEAT = true, FISH = true },
        ["spider"]       = { MEAT = true },
        ["sporebat"]     = { FRUIT = true, FUNGUS = true },
        ["tallstrider"]  = { FRUIT = true, FUNGUS = true, CHEESE = true },
        ["turtle"]       = { FISH = true, FRUIT = true, FUNGUS = true },
        ["warp stalker"] = { MEAT = true, FISH = true },
        ["wind serpent"] = { FISH = true, CHEESE = true, BREAD = true },
        ["wolf"]         = { MEAT = true },
    }

    -- Verified Classic/Vanilla & Conjured food items: { diet, crafted, level }
    local PET_FOOD_ITEMS_BY_ID = {
        -- Vendor & Raw Meats
        [117]   = { diet = "MEAT",   crafted = false, level = 1 },  -- Tough Jerky
        [769]   = { diet = "MEAT",   crafted = false, level = 1 },  -- Chunk of Boar Meat
        [2672]  = { diet = "MEAT",   crafted = false, level = 1 },  -- Stringy Wolf Meat
        [2287]  = { diet = "MEAT",   crafted = false, level = 5 },  -- Haunch of Meat
        [3173]  = { diet = "MEAT",   crafted = false, level = 10 }, -- Bear Meat
        [3770]  = { diet = "MEAT",   crafted = false, level = 15 }, -- Mutton Chop
        [3730]  = { diet = "MEAT",   crafted = false, level = 20 }, -- Big Bear Meat
        [3771]  = { diet = "MEAT",   crafted = false, level = 25 }, -- Wild Hog Shank
        [12184] = { diet = "MEAT",   crafted = false, level = 25 }, -- Raptor Flesh
        [12203] = { diet = "MEAT",   crafted = false, level = 30 }, -- Red Wolf Meat
        [4599]  = { diet = "MEAT",   crafted = false, level = 35 }, -- Cured Ham Steak
        [12208] = { diet = "MEAT",   crafted = false, level = 35 }, -- Tender Wolf Meat
        [8952]  = { diet = "MEAT",   crafted = false, level = 45 }, -- Roasted Quail
        -- Vendor & Raw Fish
        [6291]  = { diet = "FISH",   crafted = false, level = 1 },  -- Raw Brilliant Smallfish
        [6303]  = { diet = "FISH",   crafted = false, level = 1 },  -- Raw Slitherskin Mackerel
        [787]   = { diet = "FISH",   crafted = false, level = 1 },  -- Slitherskin Mackerel
        [4592]  = { diet = "FISH",   crafted = false, level = 5 },  -- Longjaw Mud Snapper
        [6289]  = { diet = "FISH",   crafted = false, level = 5 },  -- Raw Longjaw Mud Snapper
        [4593]  = { diet = "FISH",   crafted = false, level = 15 }, -- Bristle Whisker Catfish
        [6308]  = { diet = "FISH",   crafted = false, level = 15 }, -- Raw Bristle Whisker Catfish
        [4594]  = { diet = "FISH",   crafted = false, level = 25 }, -- Rockscale Cod
        [6359]  = { diet = "FISH",   crafted = false, level = 25 }, -- Raw Rockscale Cod
        [8957]  = { diet = "FISH",   crafted = false, level = 35 }, -- Spinefin Halibut
        [8959]  = { diet = "FISH",   crafted = false, level = 35 }, -- Raw Spinefin Halibut
        [13758] = { diet = "FISH",   crafted = false, level = 35 }, -- Raw Redgill
        [4603]  = { diet = "FISH",   crafted = false, level = 40 }, -- Raw Spotted Yellowtail
        [13760] = { diet = "FISH",   crafted = false, level = 45 }, -- Raw Sunscale Salmon
        [21153] = { diet = "FISH",   crafted = false, level = 45 }, -- Raw Spotted Yellowtail / Striped
        -- Vendor Cheeses
        [2070]  = { diet = "CHEESE", crafted = false, level = 1 },  -- Darnassian Bleu
        [414]   = { diet = "CHEESE", crafted = false, level = 5 },  -- Dalaran Sharp
        [1707]  = { diet = "CHEESE", crafted = false, level = 15 }, -- Stormwind Brie
        [3927]  = { diet = "CHEESE", crafted = false, level = 35 }, -- Fine Aged Cheddar
        [8932]  = { diet = "CHEESE", crafted = false, level = 45 }, -- Alterac Swiss
        -- Vendor & Conjured Breads
        [4540]  = { diet = "BREAD",  crafted = false, level = 1 },  -- Tough Hunk of Bread
        [5349]  = { diet = "BREAD",  crafted = false, level = 1 },  -- Conjured Muffin
        [4541]  = { diet = "BREAD",  crafted = false, level = 5 },  -- Freshly Baked Bread
        [1113]  = { diet = "BREAD",  crafted = false, level = 5 },  -- Conjured Bread
        [4542]  = { diet = "BREAD",  crafted = false, level = 15 }, -- Moist Cornbread
        [1114]  = { diet = "BREAD",  crafted = false, level = 15 }, -- Conjured Rye
        [4544]  = { diet = "BREAD",  crafted = false, level = 25 }, -- Mulgore Spice Bread
        [1487]  = { diet = "BREAD",  crafted = false, level = 25 }, -- Conjured Pumpernickel
        [4601]  = { diet = "BREAD",  crafted = false, level = 35 }, -- Soft Banana Bread
        [8075]  = { diet = "BREAD",  crafted = false, level = 35 }, -- Conjured Sourdough
        [8950]  = { diet = "BREAD",  crafted = false, level = 45 }, -- Homemade Cherry Pie
        [8076]  = { diet = "BREAD",  crafted = false, level = 45 }, -- Conjured Sweet Roll
        [22895] = { diet = "BREAD",  crafted = false, level = 55 }, -- Conjured Cinnamon Roll
        -- Vendor Fruits
        [4536]  = { diet = "FRUIT",  crafted = false, level = 1 },  -- Shiny Red Apple
        [4537]  = { diet = "FRUIT",  crafted = false, level = 5 },  -- Tel'Abim Banana
        [4538]  = { diet = "FRUIT",  crafted = false, level = 15 }, -- Snapvine Watermelon
        [4539]  = { diet = "FRUIT",  crafted = false, level = 25 }, -- Goldenbark Apple
        [4602]  = { diet = "FRUIT",  crafted = false, level = 35 }, -- Moon Harvest Pumpkin
        [8953]  = { diet = "FRUIT",  crafted = false, level = 45 }, -- Deep Fried Plantains
        -- Vendor Fungi
        [4604]  = { diet = "FUNGUS", crafted = false, level = 1 },  -- Forest Mushroom Cap
        [4605]  = { diet = "FUNGUS", crafted = false, level = 5 },  -- Red-speckled Mushroom
        [4606]  = { diet = "FUNGUS", crafted = false, level = 15 }, -- Spongy Morel
        [4607]  = { diet = "FUNGUS", crafted = false, level = 25 }, -- Delicious Cave Mold
        [4608]  = { diet = "FUNGUS", crafted = false, level = 35 }, -- Raw Black Truffle
        [8948]  = { diet = "FUNGUS", crafted = false, level = 45 }, -- Dried King Bolete
        -- Cooked / Crafted Foods
        [2679]  = { diet = "MEAT",   crafted = true,  level = 1 },  -- Charred Wolf Meat
        [2680]  = { diet = "MEAT",   crafted = true,  level = 1 },  -- Spiced Wolf Meat
        [2681]  = { diet = "MEAT",   crafted = true,  level = 1 },  -- Roasted Boar Meat
        [5472]  = { diet = "MEAT",   crafted = true,  level = 1 },  -- Kaldorei Spider Kabob
        [3220]  = { diet = "MEAT",   crafted = true,  level = 5 },  -- Blood Sausage
        [5474]  = { diet = "MEAT",   crafted = true,  level = 5 },  -- Roasted Kodo Meat
        [5479]  = { diet = "MEAT",   crafted = true,  level = 10 }, -- Crispy Lizard Tail
        [3662]  = { diet = "MEAT",   crafted = true,  level = 15 }, -- Crocolisk Steak
        [3665]  = { diet = "MEAT",   crafted = true,  level = 15 }, -- Curiously Tasty Omelet
        [3726]  = { diet = "MEAT",   crafted = true,  level = 25 }, -- Big Bear Steak
        [3727]  = { diet = "MEAT",   crafted = true,  level = 25 }, -- Hot Lion Chops
        [12209] = { diet = "MEAT",   crafted = true,  level = 30 }, -- Lean Wolf Steak
        [12210] = { diet = "MEAT",   crafted = true,  level = 30 }, -- Roast Raptor
        [12212] = { diet = "MEAT",   crafted = true,  level = 30 }, -- Jungle Stew
        [12218] = { diet = "MEAT",   crafted = true,  level = 35 }, -- Monster Omelet
        [18045] = { diet = "MEAT",   crafted = true,  level = 40 }, -- Tender Wolf Steak
        [20452] = { diet = "MEAT",   crafted = true,  level = 55 }, -- Smoked Desert Dumplings
        [21023] = { diet = "MEAT",   crafted = true,  level = 55 }, -- Dirge's Kickin' Chimaerok Chops
        [13927] = { diet = "FISH",   crafted = true,  level = 45 }, -- Cooked Glossy Mightfish
        [13928] = { diet = "FISH",   crafted = true,  level = 45 }, -- Grilled Squid
        [13931] = { diet = "FISH",   crafted = true,  level = 35 }, -- Nightfin Soup
        [21072] = { diet = "FISH",   crafted = true,  level = 10 }, -- Smoked Sagefish
        [21217] = { diet = "FISH",   crafted = true,  level = 30 }, -- Sagefish Delight
    }

    -- Name lookup for additional Classic/TBC foods (raw drops, cooked dishes, vendor staples)
    local PET_FOOD_BY_NAME = {
        -- Raw meats & fish
        ["lean wolf flank"]         = { diet = "MEAT",   crafted = false },
        ["crag boar rib"]           = { diet = "MEAT",   crafted = false },
        ["boar ribs"]               = { diet = "MEAT",   crafted = false },
        ["coyote meat"]             = { diet = "MEAT",   crafted = false },
        ["crisp spider meat"]       = { diet = "MEAT",   crafted = false },
        ["white spider meat"]       = { diet = "MEAT",   crafted = false },
        ["lion meat"]               = { diet = "MEAT",   crafted = false },
        ["mystery meat"]            = { diet = "MEAT",   crafted = false },
        ["tiger meat"]              = { diet = "MEAT",   crafted = false },
        ["stag meat"]               = { diet = "MEAT",   crafted = false },
        ["kodo meat"]               = { diet = "MEAT",   crafted = false },
        ["heavy kodo meat"]         = { diet = "MEAT",   crafted = false },
        ["tough condor meat"]       = { diet = "MEAT",   crafted = false },
        ["buzzard wing"]            = { diet = "MEAT",   crafted = false },
        ["strider meat"]            = { diet = "MEAT",   crafted = false },
        ["goretusk snout"]          = { diet = "MEAT",   crafted = false },
        ["goretusk liver"]          = { diet = "MEAT",   crafted = false },
        ["meaty bat wing"]          = { diet = "MEAT",   crafted = false },
        ["thunder lizard tail"]     = { diet = "MEAT",   crafted = false },
        ["sandworm meat"]           = { diet = "MEAT",   crafted = false },
        ["small egg"]               = { diet = "MEAT",   crafted = false },
        ["giant egg"]               = { diet = "MEAT",   crafted = false },
        ["raptor egg"]              = { diet = "MEAT",   crafted = false },
        ["dig rat"]                 = { diet = "MEAT",   crafted = false },
        ["clam meat"]               = { diet = "FISH",   crafted = false },
        ["tangy clam meat"]         = { diet = "FISH",   crafted = false },
        ["zesty clam meat"]         = { diet = "FISH",   crafted = false },
        ["crawler meat"]            = { diet = "FISH",   crafted = false },
        ["tender crab meat"]        = { diet = "FISH",   crafted = false },
        ["crawler claw"]            = { diet = "FISH",   crafted = false },
        ["soft frenzy flesh"]       = { diet = "FISH",   crafted = false },
        ["murloc fin"]              = { diet = "FISH",   crafted = false },
        ["raw rainbow fin albacore"] = { diet = "FISH",  crafted = false },
        ["raw mithril head trout"]  = { diet = "FISH",   crafted = false },
        ["raw loch frenzy"]         = { diet = "FISH",   crafted = false },
        ["raw sagefish"]            = { diet = "FISH",   crafted = false },
        ["raw greater sagefish"]    = { diet = "FISH",   crafted = false },
        ["raw nightfin snapper"]    = { diet = "FISH",   crafted = false },
        ["raw glossy mightfish"]    = { diet = "FISH",   crafted = false },
        ["raw summer bass"]         = { diet = "FISH",   crafted = false },
        ["raw whitescale salmon"]   = { diet = "FISH",   crafted = false },
        ["darkclaw lobster"]        = { diet = "FISH",   crafted = false },
        ["dwarven mild"]            = { diet = "CHEESE", crafted = false },
        -- Cooked / Crafted recipes
        ["herb baked egg"]          = { diet = "MEAT",   crafted = true },
        ["coyote steak"]            = { diet = "MEAT",   crafted = true },
        ["crab cake"]               = { diet = "FISH",   crafted = true },
        ["cooked crab claw"]        = { diet = "FISH",   crafted = true },
        ["dry pork ribs"]           = { diet = "MEAT",   crafted = true },
        ["beer basted boar ribs"]   = { diet = "MEAT",   crafted = true },
        ["succulent pork ribs"]     = { diet = "MEAT",   crafted = true },
        ["goretusk liver pie"]      = { diet = "MEAT",   crafted = true },
        ["westfall stew"]           = { diet = "MEAT",   crafted = true },
        ["redridge goulash"]        = { diet = "MEAT",   crafted = true },
        ["seasoned wolf kabob"]     = { diet = "MEAT",   crafted = true },
        ["scorpid surprise"]        = { diet = "MEAT",   crafted = true },
        ["strider stew"]            = { diet = "MEAT",   crafted = true },
        ["lean venison"]            = { diet = "MEAT",   crafted = true },
        ["murloc fin soup"]         = { diet = "FISH",   crafted = true },
        ["crocolisk gumbo"]         = { diet = "MEAT",   crafted = true },
        ["gooey spider cake"]       = { diet = "MEAT",   crafted = true },
        ["barbecued buzzard wing"]  = { diet = "MEAT",   crafted = true },
        ["soothing turtle bisque"]  = { diet = "FISH",   crafted = true },
        ["carrion surprise"]        = { diet = "MEAT",   crafted = true },
        ["mystery stew"]            = { diet = "MEAT",   crafted = true },
        ["heavy kodo stew"]         = { diet = "MEAT",   crafted = true },
        ["spiced chili crab"]       = { diet = "FISH",   crafted = true },
        ["spider sausage"]          = { diet = "MEAT",   crafted = true },
        ["heavy crocolisk stew"]    = { diet = "MEAT",   crafted = true },
        ["dig rat stew"]            = { diet = "MEAT",   crafted = true },
        ["crispy bat wing"]         = { diet = "MEAT",   crafted = true },
        ["brilliant smallfish"]     = { diet = "FISH",   crafted = true },
        ["loch frenzy delight"]     = { diet = "FISH",   crafted = true },
        ["rainbow fin albacore"]    = { diet = "FISH",   crafted = true },
        ["fillet of frenzy"]        = { diet = "FISH",   crafted = true },
        ["mithril head trout"]      = { diet = "FISH",   crafted = true },
        ["spotted yellowtail"]      = { diet = "FISH",   crafted = true },
        ["hot smoked bass"]         = { diet = "FISH",   crafted = true },
        ["filet of redgill"]        = { diet = "FISH",   crafted = true },
        ["poached sunscale salmon"] = { diet = "FISH",   crafted = true },
        ["lobster stew"]            = { diet = "FISH",   crafted = true },
        ["mightfish steak"]         = { diet = "FISH",   crafted = true },
        ["baked salmon"]            = { diet = "FISH",   crafted = true },
        ["clam chowder"]            = { diet = "FISH",   crafted = true },
        ["boiled clams"]            = { diet = "FISH",   crafted = true },
        ["goblin deviled clams"]    = { diet = "FISH",   crafted = true },
        ["undermine clam chowder"]  = { diet = "FISH",   crafted = true },
        ["runn tum tuber surprise"] = { diet = "FUNGUS", crafted = true },
        ["gingerbread cookie"]      = { diet = "BREAD",  crafted = true },
    }

    local petFeedBtn = nil
    local petFeedHappinessBtn = nil
    local hookedHappinessFrames = setmetatable({}, { __mode = "k" })
    local runtimeBlockedFoods = {}
    local pendingFeedAttempt = nil
    local lastFeedMsgAt = 0
    local petFeedDebug = false
    local petFeederBlacklistUpdater = nil

    local function GetFeedPetSpellName()
        return GetSafeSpellName(FEED_PET_SPELL_ID) or "Feed Pet"
    end

    local function IsFeedPetKnownAndReady()
        local spName = GetFeedPetSpellName()
        local known = false
        if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
            local ok, k = pcall(C_SpellBook.IsSpellKnown, FEED_PET_SPELL_ID)
            if ok and not IsSecret(k) and k then known = true end
        elseif type(IsSpellKnown) == "function" then
            local ok, k = pcall(IsSpellKnown, FEED_PET_SPELL_ID)
            if ok and not IsSecret(k) and k then known = true end
        end
        if not known then
            local knownByLow = ScanPlayerSpellBook()
            if knownByLow[spName:lower()] or knownByLow["feed pet"] then
                known = true
            end
        end
        if not known then
            return false, "not_learned", spName
        end

        local usable, noMana
        if C_Spell and type(C_Spell.IsSpellUsable) == "function" then
            local ok, u, nm = pcall(C_Spell.IsSpellUsable, spName)
            if ok then usable, noMana = u, nm end
        elseif type(IsUsableSpell) == "function" then
            local ok, u, nm = pcall(IsUsableSpell, spName)
            if ok then usable, noMana = u, nm end
        end
        if not IsSecret(noMana) and noMana then
            return false, "resources", spName
        end
        if not IsSecret(usable) and usable == false then
            return false, "unusable", spName
        end

        local start, duration = 0, 0
        if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
            local ok, cd = pcall(C_Spell.GetSpellCooldown, spName)
            if ok and type(cd) == "table" then
                start = YRG.SafeNumber(cd.startTime, 0)
                duration = YRG.SafeNumber(cd.duration, 0)
            end
        elseif type(GetSpellCooldown) == "function" then
            local ok, st, dur = pcall(GetSpellCooldown, spName)
            if ok then
                start = YRG.SafeNumber(st, 0)
                duration = YRG.SafeNumber(dur, 0)
            end
        end
        if start > 0 and duration > 1.5 then
            local now = (type(GetTime) == "function") and GetTime() or 0
            if (start + duration - now) > 0.25 then
                return false, "cooldown", spName
            end
        end

        return true, spName, spName
    end

    local function HasPetFeedEffect()
        if not (UnitExists and UnitExists("pet")) then return false end
        local feedBuffName = (GetSafeSpellName(FEED_PET_BUFF_ID) or "feed pet effect"):lower()
        if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
            for i = 1, 40 do
                local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "pet", i, "HELPFUL")
                if not ok or type(aura) ~= "table" then break end
                local sid = YRG.SafeOptionalNumber(aura.spellId)
                local nm = YRG.SafeString(aura.name, nil)
                if sid == FEED_PET_BUFF_ID or (nm and (nm:lower() == feedBuffName or nm:lower():find("feed pet", 1, true))) then
                    return true
                end
            end
        elseif type(UnitAura) == "function" then
            for i = 1, 40 do
                local ok, nm, _, _, _, _, _, _, _, _, sid = pcall(UnitAura, "pet", i, "HELPFUL")
                if not ok then break end
                nm = YRG.SafeString(nm, nil)
                if not nm then break end
                sid = YRG.SafeOptionalNumber(sid)
                if sid == FEED_PET_BUFF_ID or nm:lower() == feedBuffName or nm:lower():find("feed pet", 1, true) then
                    return true
                end
            end
        end
        return false
    end

    local function GetPetDietSet()
        local diets = {}
        local ordered = {}

        local function AddDiet(raw)
            local s = YRG.SafeString(raw, nil)
            if not s then return end
            local up = s:upper():gsub("^%s+", ""):gsub("%s+$", "")
            if up == "MUSHROOM" or up == "FUNGI" then up = "FUNGUS" end
            if DIET_DISPLAY_NAMES[up] and not diets[up] then
                diets[up] = true
                ordered[#ordered + 1] = DIET_DISPLAY_NAMES[up]
            end
        end

        if type(GetPetFoodTypes) == "function" then
            local ok, a, b, c, d, e, f, g, h = pcall(GetPetFoodTypes)
            if ok then
                for _, val in ipairs({ a, b, c, d, e, f, g, h }) do
                    AddDiet(val)
                end
            end
        end

        if #ordered == 0 and type(UnitCreatureFamily) == "function" then
            local ok, fam = pcall(UnitCreatureFamily, "pet")
            fam = ok and YRG.SafeString(fam, nil) or nil
            if fam then
                local fallback = PET_DIET_BY_FAMILY[fam:lower()]
                if fallback then
                    for key in pairs(fallback) do
                        AddDiet(key)
                    end
                end
            end
        end

        return diets, ordered
    end

    local function GetPetSignature()
        local fam = (type(UnitCreatureFamily) == "function") and YRG.SafeString(UnitCreatureFamily("pet"), "Pet") or "Pet"
        local lvl = YRG.SafeNumber(UnitLevel and UnitLevel("pet"), 1)
        return tostring(fam) .. ":" .. tostring(lvl)
    end

    local function ReadBagTooltipLines(bag, slot)
        local lines = {}
        if C_TooltipInfo and type(C_TooltipInfo.GetBagItem) == "function" then
            local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
            if ok and type(data) == "table" and type(data.lines) == "table" then
                for _, line in ipairs(data.lines) do
                    local txt = line and (line.leftText or line.text)
                    if type(txt) == "string" and not IsSecret(txt) and txt ~= "" then
                        lines[#lines + 1] = txt
                    end
                end
            end
        end
        if #lines == 0 and CreateFrame and UIParent then
            if not prepScanTooltip then
                local ok, tip = pcall(CreateFrame, "GameTooltip", "YRGRoguePrepScanTooltip", UIParent, "GameTooltipTemplate")
                if ok and tip then prepScanTooltip = tip end
            end
            if prepScanTooltip then
                prepScanTooltip:Hide()
                prepScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
                if prepScanTooltip.ClearLines then prepScanTooltip:ClearLines() end
                local okSet = pcall(prepScanTooltip.SetBagItem, prepScanTooltip, bag, slot)
                if okSet then
                    local numLines = YRG.SafeNumber(prepScanTooltip.NumLines and prepScanTooltip:NumLines(), 0)
                    local tipName = prepScanTooltip.GetName and prepScanTooltip:GetName() or "YRGRoguePrepScanTooltip"
                    for i = 1, numLines do
                        local fs = _G[tipName .. "TextLeft" .. i]
                        local txt = fs and fs.GetText and fs:GetText()
                        if type(txt) == "string" and not IsSecret(txt) and txt ~= "" then
                            lines[#lines + 1] = txt
                        end
                    end
                end
                prepScanTooltip:Hide()
            end
        end
        return lines
    end

    local function InspectBagFoodTooltip(bag, slot)
        local lines = ReadBagTooltipLines(bag, slot)
        local info = {
            isQuest = false,
            isBuffOrCrafted = false,
            isDrinkOnly = false,
            isEdibleFood = false,
            isInedibleTrade = false,
        }
        for _, line in ipairs(lines) do
            local low = StripColorCodes(line):lower()
            if low:find("quest item", 1, true) or low:find("starts a quest", 1, true) then
                info.isQuest = true
            end
            if low:find("well fed", 1, true)
                or low:find("if you spend at least", 1, true)
                or low:find("spend at least", 1, true) then
                info.isBuffOrCrafted = true
            end
            if low:find("must remain seated while drinking", 1, true) then
                info.isDrinkOnly = true
            end
            if low:find("must remain seated while eating", 1, true)
                or (low:find("use:", 1, true) and low:find("restores", 1, true) and low:find("health", 1, true)) then
                info.isEdibleFood = true
            end
            if low:find("increases", 1, true) and low:find("use:", 1, true) then
                info.isBuffOrCrafted = true
            end
        end
        if info.isEdibleFood then
            info.isDrinkOnly = false
        end
        return info
    end

    local function InferDietFromItemName(lowName)
        if type(lowName) ~= "string" or lowName == "" then return nil end
        for _, bad in ipairs({
            "recipe", "pattern", "formula", "schematic", "plans", "potion", "elixir", "flask",
            "bandage", "scroll", "water", "milk", "juice", "tea", "wine", "ale", "beer", "rum",
            "grog", "whiskey", "brandy", "nectar", "dew", "pelt", "hide", "leather", "silk",
            "scale", "bone", "ichor", "blood", "venom", "sac", "tooth", "fang", "feather",
            "oil", "spice", "flour", "salt", "thread", "blackmouth", "firefin", "stonescale", "deviate",
        }) do
            if lowName:find(bad, 1, true) and not lowName:find("beer basted", 1, true) then
                return nil
            end
        end

        if lowName:find("cheese", 1, true) or lowName:find("bleu", 1, true) or lowName:find("brie", 1, true)
            or lowName:find("cheddar", 1, true) or lowName:find("swiss", 1, true) or lowName:find("gouda", 1, true)
            or lowName:find("dwarven mild", 1, true) then
            return "CHEESE"
        elseif lowName:find("mushroom", 1, true) or lowName:find("fungus", 1, true) or lowName:find("morel", 1, true)
            or lowName:find("truffle", 1, true) or lowName:find("bolete", 1, true) or lowName:find("cave mold", 1, true)
            or lowName:find("toadstool", 1, true) then
            return "FUNGUS"
        elseif lowName:find("apple", 1, true) or lowName:find("banana", 1, true) or lowName:find("watermelon", 1, true)
            or lowName:find("pumpkin", 1, true) or lowName:find("plantain", 1, true) or lowName:find("melon", 1, true)
            or lowName:find("cherry", 1, true) or lowName:find("peach", 1, true) or lowName:find("pear", 1, true)
            or lowName:find("berry", 1, true) or lowName:find("fruit", 1, true) or lowName:find("orange", 1, true)
            or lowName:find("mango", 1, true) then
            return "FRUIT"
        elseif lowName:find("bread", 1, true) or lowName:find("muffin", 1, true) or lowName:find("rye", 1, true)
            or lowName:find("pumpernickel", 1, true) or lowName:find("sourdough", 1, true) or lowName:find("sweet roll", 1, true)
            or lowName:find("cinnamon roll", 1, true) or lowName:find("cornbread", 1, true) or lowName:find("croissant", 1, true)
            or lowName:find("biscuit", 1, true) or lowName:find("cookie", 1, true) or lowName:find("loaf", 1, true)
            or lowName:find("bagel", 1, true) or lowName:find("cake", 1, true) then
            return "BREAD"
        elseif lowName:find("fish", 1, true) or lowName:find("mackerel", 1, true) or lowName:find("snapper", 1, true)
            or lowName:find("catfish", 1, true) or lowName:find("halibut", 1, true) or lowName:find("yellowtail", 1, true)
            or lowName:find("salmon", 1, true) or lowName:find("trout", 1, true) or lowName:find("bass", 1, true)
            or lowName:find("frenzy", 1, true) or lowName:find("albacore", 1, true) or lowName:find("redgill", 1, true)
            or lowName:find("squid", 1, true) or lowName:find("clam", 1, true) or lowName:find("crab", 1, true)
            or lowName:find("lobster", 1, true) or lowName:find("cod", 1, true) or lowName:find("crawdad", 1, true)
            or lowName:find("mudfish", 1, true) or lowName:find("darter", 1, true) then
            return "FISH"
        elseif lowName:find("meat", 1, true) or lowName:find("jerky", 1, true) or lowName:find("haunch", 1, true)
            or lowName:find("mutton", 1, true) or lowName:find("shank", 1, true) or lowName:find("ham", 1, true)
            or lowName:find("steak", 1, true) or lowName:find("ribs", 1, true) or lowName:find("flank", 1, true)
            or lowName:find("venison", 1, true) or lowName:find("pork", 1, true) or lowName:find("quail", 1, true)
            or lowName:find("sausage", 1, true) or lowName:find("omelet", 1, true) or lowName:find("goulash", 1, true)
            or lowName:find("chops", 1, true) or lowName:find("roast", 1, true) or lowName:find("kabob", 1, true)
            or lowName:find("bacon", 1, true) or lowName:find("snout", 1, true) or lowName:find("liver", 1, true)
            or lowName:find("bat wing", 1, true) or lowName:find("buzzard wing", 1, true) or lowName:find("lizard tail", 1, true)
            or lowName:find("egg", 1, true) then
            return "MEAT"
        end
        return nil
    end

    local function IsPetFoodBlacklisted(db, itemName)
        if not db or type(db.petFeederBlacklist) ~= "table" or type(itemName) ~= "string" then
            return false
        end
        local low = itemName:lower()
        for _, entry in ipairs(db.petFeederBlacklist) do
            if type(entry) == "string" and entry ~= "" then
                local clean = NormalizePrepItemName(entry)
                if clean and clean:lower() == low then
                    return true
                end
            end
        end
        return false
    end

    local function GetFullBagItemStats(bag, slot, itemID, itemLink)
        local stackCount = 1
        local slotQuality = nil
        if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if type(info) == "table" then
                stackCount = YRG.SafeNumber(info.stackCount, 1)
                slotQuality = YRG.SafeOptionalNumber(info.quality)
            end
        elseif type(GetContainerItemInfo) == "function" then
            local _, count, _, q = GetContainerItemInfo(bag, slot)
            stackCount = YRG.SafeNumber(count, 1)
            slotQuality = YRG.SafeOptionalNumber(q)
        end

        local query = itemLink or itemID
        local itemName, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, sellPrice, classID, subClassID
        if query then
            if C_Item and type(C_Item.GetItemInfo) == "function" then
                itemName, _, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, _, _, _, sellPrice, classID, subClassID = C_Item.GetItemInfo(query)
            elseif type(GetItemInfo) == "function" then
                itemName, _, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, _, _, _, sellPrice, classID, subClassID = GetItemInfo(query)
            end
        end

        return {
            name = YRG.SafeString(itemName, nil),
            quality = YRG.SafeOptionalNumber(itemQuality) or slotQuality or 1,
            itemLevel = YRG.SafeNumber(itemLevel, 0),
            itemMinLevel = YRG.SafeNumber(itemMinLevel, 0),
            itemType = YRG.SafeString(itemType, ""),
            itemSubType = YRG.SafeString(itemSubType, ""),
            sellPrice = YRG.SafeNumber(sellPrice, 0),
            classID = YRG.SafeOptionalNumber(classID),
            subClassID = YRG.SafeOptionalNumber(subClassID),
            stackCount = math.max(1, stackCount),
        }
    end

    local function FindBestPetFood(db)
        local dietSet, dietList = GetPetDietSet()
        if #dietList == 0 then
            return nil, dietList, { noDiet = true }
        end

        local petLevel = math.max(1, YRG.SafeNumber(UnitLevel and UnitLevel("pet"), 1))
        local petSig = GetPetSignature()
        local ignoreCrafted = (db == nil) or (db.petFeederIgnoreCrafted ~= false)
        local minFoodLevel = math.max(1, petLevel - 30)
        local maxBag = NUM_BAG_SLOTS or 4

        local consumableClass = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
        local tradeGoodsClass = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
        local questClass = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

        local candidates = {}
        local skipStats = {
            blacklisted = 0,
            crafted = 0,
            tooLowLevel = 0,
            tooHighLevel = 0,
            rejected = 0,
        }

        for bag = 0, maxBag do
            local numSlots = SafeGetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local itemID, itemLink = SafeGetContainerItemDetails(bag, slot)
                if itemID and not IsBagItemOnCooldown(bag, slot) then
                    local stats = GetFullBagItemStats(bag, slot, itemID, itemLink)
                    local itemName = stats.name
                    if itemName then
                        local lowName = itemName:lower()
                        local known = PET_FOOD_ITEMS_BY_ID[itemID] or PET_FOOD_BY_NAME[lowName]
                        local diet, crafted, foodLevel

                        if known then
                            diet = known.diet
                            crafted = known.crafted and true or false
                            foodLevel = known.level or ((stats.itemMinLevel > 0) and stats.itemMinLevel or math.max(1, stats.itemLevel - 10))
                            if not crafted and ignoreCrafted and stats.classID == consumableClass then
                                local tipInfo = InspectBagFoodTooltip(bag, slot)
                                if tipInfo.isQuest then
                                    diet = nil
                                elseif tipInfo.isBuffOrCrafted then
                                    crafted = true
                                end
                            end
                        elseif stats.classID ~= questClass and (stats.classID == consumableClass or stats.classID == tradeGoodsClass or stats.classID == nil) then
                            local guessedDiet = InferDietFromItemName(lowName)
                            if guessedDiet then
                                local tipInfo = InspectBagFoodTooltip(bag, slot)
                                if not tipInfo.isQuest and not tipInfo.isDrinkOnly then
                                    local subLow = stats.itemSubType:lower()
                                    local isFoodSubtype = subLow:find("food", 1, true) ~= nil
                                    local isRawCooking = (stats.classID == tradeGoodsClass) and (guessedDiet == "MEAT" or guessedDiet == "FISH" or guessedDiet == "FUNGUS" or guessedDiet == "FRUIT")
                                    if tipInfo.isEdibleFood or isFoodSubtype or isRawCooking then
                                        diet = guessedDiet
                                        crafted = tipInfo.isBuffOrCrafted and true or false
                                        foodLevel = (stats.itemMinLevel > 0) and stats.itemMinLevel or math.max(1, stats.itemLevel - 10)
                                    end
                                end
                            end
                        end

                        if diet and dietSet[diet] then
                            local blockedEntry = runtimeBlockedFoods[itemID]
                            if blockedEntry and blockedEntry.petSig == petSig then
                                skipStats.rejected = skipStats.rejected + 1
                            elseif IsPetFoodBlacklisted(db, itemName) then
                                skipStats.blacklisted = skipStats.blacklisted + 1
                            elseif ignoreCrafted and crafted then
                                skipStats.crafted = skipStats.crafted + 1
                            elseif stats.itemMinLevel > petLevel then
                                skipStats.tooHighLevel = skipStats.tooHighLevel + 1
                            elseif foodLevel < minFoodLevel then
                                skipStats.tooLowLevel = skipStats.tooLowLevel + 1
                            else
                                candidates[#candidates + 1] = {
                                    bag = bag,
                                    slot = slot,
                                    itemID = itemID,
                                    link = itemLink,
                                    name = itemName,
                                    diet = diet,
                                    crafted = crafted and 1 or 0,
                                    quality = stats.quality,
                                    foodLevel = foodLevel,
                                    sellPrice = stats.sellPrice,
                                    stackCount = stats.stackCount,
                                }
                            end
                        end
                    end
                end
            end
        end

        if #candidates == 0 then
            return nil, dietList, skipStats
        end

        table.sort(candidates, function(a, b)
            if a.quality ~= b.quality then return a.quality < b.quality end
            if a.crafted ~= b.crafted then return a.crafted < b.crafted end
            if a.foodLevel ~= b.foodLevel then return a.foodLevel < b.foodLevel end
            if a.sellPrice ~= b.sellPrice then return a.sellPrice < b.sellPrice end
            if a.stackCount ~= b.stackCount then return a.stackCount < b.stackCount end
            if a.bag ~= b.bag then return a.bag < b.bag end
            return a.slot < b.slot
        end)

        return candidates[1], dietList, skipStats
    end

    local function FormatNoFoodMessage(petName, dietList, skipStats)
        local dietStr = (#dietList > 0) and table.concat(dietList, ", ") or "Unknown diet"
        if skipStats and skipStats.noDiet then
            return string.format("|cffffd100YRG Pet Feeder:|r Could not detect %s's diet.", petName)
        end
        local reasons = {}
        if skipStats then
            if skipStats.crafted and skipStats.crafted > 0 then reasons[#reasons + 1] = "crafted/buff food ignored" end
            if skipStats.blacklisted and skipStats.blacklisted > 0 then reasons[#reasons + 1] = "blacklisted" end
            if skipStats.tooLowLevel and skipStats.tooLowLevel > 0 then reasons[#reasons + 1] = "food level too low" end
            if skipStats.tooHighLevel and skipStats.tooHighLevel > 0 then reasons[#reasons + 1] = "pet level too low" end
            if skipStats.rejected and skipStats.rejected > 0 then reasons[#reasons + 1] = "pet rejected" end
        end
        if #reasons > 0 then
            return string.format("|cffffd100YRG Pet Feeder:|r No usable food found in bags for %s (%s) [%s].",
                petName, dietStr, table.concat(reasons, ", "))
        end
        return string.format("|cffffd100YRG Pet Feeder:|r No food found in bags for %s (%s).", petName, dietStr)
    end

    local function PrintFeedMsg(msg)
        local now = (type(GetTime) == "function") and GetTime() or 0
        if (now - lastFeedMsgAt) >= 0.4 then
            lastFeedMsgAt = now
            print(msg)
        end
    end

    local function ClearFeedButtonAttributes(btn)
        if not btn or (InCombatLockdown and InCombatLockdown()) then return end
        btn:SetAttribute("type", nil)
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("macrotext", nil)
        btn:SetAttribute("macrotext1", nil)
    end

    local function ConfirmFeedAttemptSuccess(attempt)
        if not attempt or attempt.confirmed then return end
        attempt.confirmed = true
        pendingFeedAttempt = nil
        local itemDisplay = attempt.itemLink or ("[" .. tostring(attempt.itemName) .. "]")
        print(string.format("|cffffd100YRG Pet Feeder:|r Fed %s to %s.", itemDisplay, tostring(attempt.petName)))
    end

    local function PrepareFeedOnButton(btn, isDirectClick, modDB)
        ClearFeedButtonAttributes(btn)

        if InCombatLockdown and InCombatLockdown() then
            PrintFeedMsg("|cffffd100YRG Pet Feeder:|r Cannot feed your pet while in combat.")
            return false
        end
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
            return false
        end
        if not (UnitExists and UnitExists("pet")) then
            PrintFeedMsg("|cffffd100YRG Pet Feeder:|r You don't have an active pet.")
            return false
        end
        if UnitIsDead and UnitIsDead("pet") then
            PrintFeedMsg("|cffffd100YRG Pet Feeder:|r Cannot feed a dead pet.")
            return false
        end
        if UnitAffectingCombat and UnitAffectingCombat("pet") then
            PrintFeedMsg("|cffffd100YRG Pet Feeder:|r Your pet is in combat.")
            return false
        end
        if IsMounted and IsMounted() then
            PrintFeedMsg("|cffffd100YRG Pet Feeder:|r Dismount before feeding your pet.")
            return false
        end
        if HasPlainCastInfo(UnitCastingInfo, "player") or HasPlainCastInfo(UnitChannelInfo, "player") then
            return false
        end

        local ready, spellOrReason, feedPetSpell = IsFeedPetKnownAndReady()
        if not ready then
            if spellOrReason == "not_learned" then
                PrintFeedMsg("|cffffd100YRG Pet Feeder:|r You haven't learned Feed Pet yet.")
            elseif spellOrReason == "resources" then
                PrintFeedMsg("|cffffd100YRG Pet Feeder:|r Not enough Focus/Mana to feed your pet.")
            elseif spellOrReason == "cooldown" then
                PrintFeedMsg("|cffffd100YRG Pet Feeder:|r Feed Pet is on cooldown.")
            end
            return false
        end

        if HasPetFeedEffect() then
            PrintFeedMsg("|cffffd100YRG Pet Feeder:|r Your pet is already eating.")
            return false
        end

        local inRange = nil
        if C_Spell and type(C_Spell.IsSpellInRange) == "function" then
            local ok, r = pcall(C_Spell.IsSpellInRange, feedPetSpell, "pet")
            if ok and not IsSecret(r) then inRange = r end
        elseif type(IsSpellInRange) == "function" then
            local ok, r = pcall(IsSpellInRange, feedPetSpell, "pet")
            if ok and not IsSecret(r) then inRange = r end
        end
        if inRange == 0 or inRange == false then
            PrintFeedMsg("|cffffd100YRG Pet Feeder:|r Your pet is too far away to feed.")
            return false
        end

        local petName = YRG.SafeString(UnitName and UnitName("pet"), "your pet") or "your pet"
        local food, dietList, skipStats = FindBestPetFood(modDB)
        if not food then
            PrintFeedMsg(FormatNoFoodMessage(petName, dietList, skipStats))
            return false
        end

        local macroBody = string.format("/cast [pet,nodead,nocombat] %s\n/use %d %d", feedPetSpell, food.bag, food.slot)
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("type1", "macro")
        btn:SetAttribute("macrotext", macroBody)
        btn:SetAttribute("macrotext1", macroBody)

        local now = (type(GetTime) == "function") and GetTime() or 0
        pendingFeedAttempt = {
            itemID = food.itemID,
            itemName = food.name,
            itemLink = food.link,
            petName = petName,
            petSig = GetPetSignature(),
            spellName = feedPetSpell,
            bag = food.bag,
            slot = food.slot,
            armedAt = now,
            clicked = isDirectClick and true or false,
            clickedAt = isDirectClick and now or nil,
            expiresAt = now + 2.0,
            confirmed = false,
        }

        if petFeedDebug then
            print(string.format("|cffffd100YRG Pet Feeder Debug:|r Armed %s (%s, q=%d, lvl=%d, bag=%d, slot=%d) for %s",
                tostring(food.name), tostring(food.diet), food.quality, food.foodLevel, food.bag, food.slot, petName))
        end

        return true
    end

    local function FindPetHappinessFrame()
        if _G.PetFrameHappiness then
            return _G.PetFrameHappiness
        end
        if PetFrame then
            if PetFrame.Happiness then return PetFrame.Happiness end
            if PetFrame.PetFrameHappiness then return PetFrame.PetFrameHappiness end
            if PetFrame.PetFrameContent then
                if PetFrame.PetFrameContent.Happiness then return PetFrame.PetFrameContent.Happiness end
                if PetFrame.PetFrameContent.PetFrameHappiness then return PetFrame.PetFrameContent.PetFrameHappiness end
            end
        end
        if _G.PetFrameHappinessTexture and _G.PetFrameHappinessTexture.GetParent then
            local p = _G.PetFrameHappinessTexture:GetParent()
            if p and p ~= PetFrame then
                return p
            end
        end
        return nil
    end

    local function SyncPetHappinessOverlay()
        if not petFeedHappinessBtn then return end
        if InCombatLockdown and InCombatLockdown() then return end

        local modDB = YRG:GetModuleDB("ClassImprovementsModule")
        local enabled = modDB and modDB.enabled and (modDB.petFeederEnabled ~= false)
        local _, liveClass = UnitClass("player")
        local isHunter = (not IsSecret(liveClass) and liveClass == "HUNTER") or (playerClass == "HUNTER")
        local hf = FindPetHappinessFrame()

        if not enabled or not isHunter or not hf or not (UnitExists and UnitExists("pet")) then
            petFeedHappinessBtn:Hide()
            return
        end

        if not hookedHappinessFrames[hf] and hf.HookScript then
            hookedHappinessFrames[hf] = true
            hf:HookScript("OnShow", function()
                SyncPetHappinessOverlay()
            end)
            hf:HookScript("OnHide", function()
                SyncPetHappinessOverlay()
            end)
        end

        if not hf:IsVisible() then
            petFeedHappinessBtn:Hide()
            return
        end

        petFeedHappinessBtn:ClearAllPoints()
        local w = YRG.SafeNumber(hf.GetWidth and hf:GetWidth(), 0)
        local h = YRG.SafeNumber(hf.GetHeight and hf:GetHeight(), 0)
        if w >= 14 and h >= 14 then
            petFeedHappinessBtn:SetAllPoints(hf)
        else
            petFeedHappinessBtn:SetSize(math.max(20, w), math.max(20, h))
            petFeedHappinessBtn:SetPoint("CENTER", hf, "CENTER", 0, 0)
        end
        petFeedHappinessBtn:SetFrameStrata(hf:GetFrameStrata() or "LOW")
        petFeedHappinessBtn:SetFrameLevel((hf:GetFrameLevel() or 1) + 5)
        SyncSecureButtonClickMode(petFeedHappinessBtn)
        petFeedHappinessBtn:Show()
    end

    local function SchedulePostFeedFallback(attemptRef)
        if not (C_Timer and type(C_Timer.After) == "function") then return end
        C_Timer.After(0.25, function()
            if pendingFeedAttempt == attemptRef and not attemptRef.confirmed then
                if HasPetFeedEffect() then
                    ConfirmFeedAttemptSuccess(attemptRef)
                else
                    pendingFeedAttempt = nil
                end
            end
        end)
    end

    function PetFeeder.EnsureUI()
        if not petFeedBtn and CreateFrame and UIParent then
            local btn = CreateFrame("Button", "YRGPetFeedButton", UIParent, "SecureActionButtonTemplate")
            btn:SetSize(1, 1)
            btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
            btn:EnableMouse(false)
            btn:HookScript("PreClick", function()
                if pendingFeedAttempt then
                    local now = (type(GetTime) == "function") and GetTime() or 0
                    pendingFeedAttempt.clicked = true
                    pendingFeedAttempt.clickedAt = now
                    pendingFeedAttempt.expiresAt = now + 1.5
                end
            end)
            btn:HookScript("PostClick", function(self)
                ClearFeedButtonAttributes(self)
                if pendingFeedAttempt then
                    SchedulePostFeedFallback(pendingFeedAttempt)
                end
            end)
            petFeedBtn = btn
        end
        SyncSecureButtonClickMode(petFeedBtn)

        if not petFeedHappinessBtn and CreateFrame and UIParent then
            local hbtn = CreateFrame("Button", "YRGPetFeedHappinessButton", UIParent, "SecureActionButtonTemplate")
            hbtn:SetSize(22, 22)
            hbtn:EnableMouse(true)
            hbtn:Hide()

            hbtn:SetScript("OnEnter", function(self)
                local hf = FindPetHappinessFrame()
                if hf and hf.GetScript then
                    local onEnter = hf:GetScript("OnEnter")
                    if type(onEnter) == "function" then
                        pcall(onEnter, hf)
                    end
                end
                if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff00ff00Left-Click:|r Feed pet (YRG AutoFeeder)", 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            hbtn:SetScript("OnLeave", function()
                local hf = FindPetHappinessFrame()
                if hf and hf.GetScript then
                    local onLeave = hf:GetScript("OnLeave")
                    if type(onLeave) == "function" then
                        pcall(onLeave, hf)
                        return
                    end
                end
                if GameTooltip and GameTooltip.Hide then
                    GameTooltip:Hide()
                end
            end)
            hbtn:HookScript("PreClick", function(self)
                local modDB = YRG:GetModuleDB("ClassImprovementsModule")
                if not modDB or not modDB.enabled or modDB.petFeederEnabled == false then
                    ClearFeedButtonAttributes(self)
                    return
                end
                PrepareFeedOnButton(self, true, modDB)
            end)
            hbtn:HookScript("PostClick", function(self)
                ClearFeedButtonAttributes(self)
                if pendingFeedAttempt then
                    SchedulePostFeedFallback(pendingFeedAttempt)
                end
            end)

            petFeedHappinessBtn = hbtn
        end
        SyncSecureButtonClickMode(petFeedHappinessBtn)
        SyncPetHappinessOverlay()
    end

    local function GetPetFeedMacroBody()
        return string.format("#showtooltip %s\n%s", GetFeedPetSpellName(), PET_FEED_MACRO_BODY)
    end

    local function GetPetFeedMacroIcon()
        if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
            local ok, tex = pcall(C_Spell.GetSpellTexture, FEED_PET_SPELL_ID)
            if ok and not IsSecret(tex) and ((type(tex) == "number" and tex > 0) or (type(tex) == "string" and tex ~= "")) then
                return tex
            end
        elseif type(GetSpellTexture) == "function" then
            local ok, tex = pcall(GetSpellTexture, FEED_PET_SPELL_ID)
            if ok and not IsSecret(tex) and ((type(tex) == "number" and tex > 0) or (type(tex) == "string" and tex ~= "")) then
                return tex
            end
        end
        local path = "Interface\\Icons\\Ability_Hunter_BeastTraining"
        if type(GetFileIDFromPath) == "function" then
            local ok, fileID = pcall(GetFileIDFromPath, path)
            if ok and type(fileID) == "number" and fileID > 0 then
                return fileID
            end
        end
        return "Ability_Hunter_BeastTraining"
    end

    function PetFeeder.EnsureMacro(forceReset, verbose)
        if InCombatLockdown and InCombatLockdown() then
            if verbose then
                print("|cffffd100YRG Pet Feeder:|r Cannot create or update the " .. PET_FEED_MACRO_NAME .. " macro during combat.")
            end
            return false, "combat"
        end
        if type(GetMacroIndexByName) ~= "function" or type(CreateMacro) ~= "function" then
            return false, "unavailable"
        end

        local body = GetPetFeedMacroBody()
        local icon = GetPetFeedMacroIcon()
        local existed, state = EnsureSingleMacro(PET_FEED_MACRO_NAME, body, forceReset, nil, icon)
        if existed then
            if state == "exists" and type(GetMacroInfo) == "function" and type(EditMacro) == "function" then
                local idx = GetMacroIndexByName(PET_FEED_MACRO_NAME)
                if idx and idx > 0 then
                    local _, curIcon, curBody = GetMacroInfo(idx)
                    local poisonIcon = GetOBPrepMacroIcon()
                    local curIconLow = (type(curIcon) == "string") and curIcon:lower() or ""
                    if curIcon == poisonIcon
                        or curIcon == 134400
                        or curIconLow:find("trade_brewpoison", 1, true)
                        or curIconLow:find("inv_misc_questionmark", 1, true) then
                        EditMacro(idx, PET_FEED_MACRO_NAME, icon, curBody or body)
                    end
                end
            end
            if verbose and state == "reset" then
                print("|cffffd100YRG Pet Feeder:|r Reset macro |cff00ff00" .. PET_FEED_MACRO_NAME .. "|r.")
            end
            return true, state
        end

        local numAccount, numChar = 0, 0
        if type(GetNumMacros) == "function" then
            numAccount, numChar = GetNumMacros()
            numAccount = YRG.SafeNumber(numAccount, 0)
            numChar = YRG.SafeNumber(numChar, 0)
        end

        local perChar = nil
        if numChar < (MAX_CHARACTER_MACROS or 18) then
            perChar = true
        elseif numAccount < (MAX_ACCOUNT_MACROS or 120) then
            perChar = false
        else
            if verbose then
                print("|cffffd100YRG Pet Feeder:|r Macro slots are full; free a macro slot to generate " .. PET_FEED_MACRO_NAME .. ".")
            end
            return false, "full"
        end

        local createdIdx = CreateMacro(PET_FEED_MACRO_NAME, icon, body, perChar)
        if createdIdx and createdIdx > 0 then
            if verbose then
                print("|cffffd100YRG Pet Feeder:|r Created macro |cff00ff00" .. PET_FEED_MACRO_NAME .. "|r calling /yrg petfeed.")
            end
            return true, "created"
        end
        return false, "failed"
    end

    function PetFeeder.RunSlash(args)
        PetFeeder.EnsureUI()
        ClearFeedButtonAttributes(petFeedBtn)

        local modDB = YRG:GetModuleDB("ClassImprovementsModule")
        if not modDB or not modDB.enabled then
            print("|cffffd100YRG Pet Feeder:|r ClassImprovementsModule is disabled in /yrg settings.")
            return
        end
        if modDB.petFeederEnabled == false then
            print("|cffffd100YRG Pet Feeder:|r Hunter Pet AutoFeeder is disabled in /yrg settings.")
            return
        end

        local cmd = (type(args) == "string") and args:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if cmd == "macro" then
            PetFeeder.EnsureMacro(true, true)
            return
        elseif cmd == "debug" then
            petFeedDebug = not petFeedDebug
            print("|cffffd100YRG Pet Feeder:|r Debug " .. (petFeedDebug and "|cff00ff00ON|r" or "|cffff6666OFF|r"))
            return
        elseif cmd == "clear" or cmd == "reset" then
            runtimeBlockedFoods = {}
            pendingFeedAttempt = nil
            print("|cffffd100YRG Pet Feeder:|r Cleared runtime rejected-food cache.")
            return
        elseif cmd == "status" then
            local hasPet = UnitExists and UnitExists("pet")
            if not hasPet then
                print("|cffffd100YRG Pet Feeder:|r No active pet.")
                return
            end
            local petName = YRG.SafeString(UnitName and UnitName("pet"), "Pet")
            local petLvl = YRG.SafeNumber(UnitLevel and UnitLevel("pet"), 1)
            local _, dietList = GetPetDietSet()
            local happ = (type(GetPetHappiness) == "function") and YRG.SafeOptionalNumber(GetPetHappiness()) or nil
            local happLabels = { [1] = "Unhappy", [2] = "Content", [3] = "Happy" }
            local food, _, skipStats = FindBestPetFood(modDB)
            local nextStr = food and string.format("%s (%s, lvl=%d, q=%d, bag=%d, slot=%d)", food.name, food.diet, food.foodLevel, food.quality, food.bag, food.slot) or "None"
            print(string.format("|cffffd100YRG Pet Feeder:|r Pet=%s (Lvl %d, %s) | Diet=%s | IgnoreCrafted=%s | Next=%s",
                tostring(petName), petLvl, tostring(happLabels[happ] or "?"), table.concat(dietList, ", "),
                tostring(modDB.petFeederIgnoreCrafted ~= false), nextStr))
            if not food then
                print(FormatNoFoodMessage(petName, dietList, skipStats))
            end
            return
        end

        local _, liveClass = UnitClass("player")
        local isHunter = (not IsSecret(liveClass) and liveClass == "HUNTER") or (playerClass == "HUNTER")
        if isHunter then
            PetFeeder.EnsureMacro(false, false)
        end

        local armed = PrepareFeedOnButton(petFeedBtn, false, modDB)
        if armed and pendingFeedAttempt and C_Timer and type(C_Timer.After) == "function" then
            local attemptRef = pendingFeedAttempt
            C_Timer.After(0.05, function()
                if pendingFeedAttempt == attemptRef and not attemptRef.clicked then
                    pendingFeedAttempt = nil
                    ClearFeedButtonAttributes(petFeedBtn)
                    PrintFeedMsg(string.format("|cffffd100YRG Pet Feeder:|r Selected %s. Use the |cff00ff00%s|r macro (or add /click YRGPetFeedButton LeftButton 1 and LeftButton 0 below /yrg petfeed) so the client can cast Feed Pet.",
                        tostring(attemptRef.itemLink or attemptRef.itemName), PET_FEED_MACRO_NAME))
                end
            end)
        end
    end

    function PetFeeder.OnEvent(event, arg1, arg2, arg3)
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            local _, liveClass = UnitClass("player")
            local modDB = YRG:GetModuleDB("ClassImprovementsModule")
            if (not IsSecret(liveClass) and liveClass == "HUNTER") and modDB and modDB.enabled and modDB.petFeederEnabled ~= false then
                PetFeeder.EnsureMacro(false, false)
            end
            SyncPetHappinessOverlay()
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0.15, SyncPetHappinessOverlay)
            end
        elseif event == "UPDATE_MACROS" then
            local _, liveClass = UnitClass("player")
            local modDB = YRG:GetModuleDB("ClassImprovementsModule")
            if (not IsSecret(liveClass) and liveClass == "HUNTER") and modDB and modDB.enabled and modDB.petFeederEnabled ~= false then
                PetFeeder.EnsureMacro(false, false)
            end
        elseif event == "UNIT_PET" or event == "PET_UI_UPDATE" or event == "UNIT_HAPPINESS"
            or event == "PLAYER_REGEN_ENABLED" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
            if event == "UNIT_PET" then
                runtimeBlockedFoods = {}
            end
            SyncPetHappinessOverlay()
            if event == "UNIT_PET" and C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0.1, SyncPetHappinessOverlay)
            end
        elseif event == "UNIT_LEVEL" or event == "PLAYER_LEVEL_UP" then
            if event == "PLAYER_LEVEL_UP" or arg1 == "pet" then
                runtimeBlockedFoods = {}
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if pendingFeedAttempt and pendingFeedAttempt.clicked and not pendingFeedAttempt.confirmed then
                local idNum = YRG.SafeOptionalNumber(arg3)
                local spName = idNum and GetSafeSpellName(idNum) or nil
                if idNum == FEED_PET_SPELL_ID
                    or (spName and pendingFeedAttempt.spellName and spName:lower() == pendingFeedAttempt.spellName:lower())
                    or (spName and spName:lower() == "feed pet") then
                    ConfirmFeedAttemptSuccess(pendingFeedAttempt)
                end
            end
        elseif event == "UI_ERROR_MESSAGE" then
            if pendingFeedAttempt and pendingFeedAttempt.clicked and not pendingFeedAttempt.confirmed then
                local now = (type(GetTime) == "function") and GetTime() or 0
                if now > (pendingFeedAttempt.expiresAt or 0) then
                    pendingFeedAttempt = nil
                    return
                end
                local errType = (type(arg1) == "number" and not IsSecret(arg1)) and arg1 or nil
                local rawMsg = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1) or nil
                local msg = YRG.SafeString(rawMsg, nil)
                if not msg and errType and type(GetGameMessageInfo) == "function" then
                    local okG, gMsg = pcall(GetGameMessageInfo, errType)
                    if okG then msg = YRG.SafeString(gMsg, nil) end
                end
                if msg then
                    local low = msg:lower()
                    if low:find("doesn't like that food", 1, true)
                        or low:find("does not like that food", 1, true)
                        or low:find("food's level is too low", 1, true)
                        or low:find("food level is too low", 1, true)
                        or low:find("isn't high enough level", 1, true)
                        or low:find("too low level", 1, true) then
                        local attempt = pendingFeedAttempt
                        pendingFeedAttempt = nil
                        runtimeBlockedFoods[attempt.itemID] = { petSig = attempt.petSig, reason = msg }
                        PrintFeedMsg(string.format("|cffffd100YRG Pet Feeder:|r Skipping %s (%s).",
                            tostring(attempt.itemLink or attempt.itemName), (msg:gsub("%.$", ""))))
                    elseif low:find("combat", 1, true) or low:find("far away", 1, true)
                        or low:find("mounted", 1, true) or low:find("already", 1, true) then
                        pendingFeedAttempt = nil
                    end
                end
            end
        end
    end

    function PetFeeder.OnEnable()
        PetFeeder.EnsureUI()
        local _, liveClass = UnitClass("player")
        local modDB = YRG:GetModuleDB("ClassImprovementsModule")
        if (not IsSecret(liveClass) and liveClass == "HUNTER") and modDB and modDB.enabled and modDB.petFeederEnabled ~= false then
            PetFeeder.EnsureMacro(false, false)
        end
    end

    function PetFeeder.OnDisable()
        pendingFeedAttempt = nil
        runtimeBlockedFoods = {}
        ClearFeedButtonAttributes(petFeedBtn)
        ClearFeedButtonAttributes(petFeedHappinessBtn)
        if petFeedHappinessBtn and not (InCombatLockdown and InCombatLockdown()) then
            petFeedHappinessBtn:Hide()
        end
    end

    function PetFeeder.SyncOverlay()
        SyncPetHappinessOverlay()
    end

    function PetFeeder.SetBlacklistUpdater(fn)
        petFeederBlacklistUpdater = fn
    end

    function PetFeeder.RefreshBlacklistSummary()
        if petFeederBlacklistUpdater then
            petFeederBlacklistUpdater()
        end
    end
end

-- ============================================================================
-- HUNTER: BETTER PARTY MEMBER (Passive + Growl Auto-Cast Off in Instances)
-- ============================================================================
do
    local GROWL_SPELL_IDS = {
        [2649] = true,
        [14916] = true,
        [14917] = true,
        [14918] = true,
        [14919] = true,
        [14920] = true,
        [14921] = true,
        [27047] = true,
        [61676] = true,
    }

    local wasInPvEInstance = false
    local lastInstanceKey = nil
    local pendingPartyPrep = false
    local pendingRetryDepth = 0

    local function GetGrowlSpellName()
        if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local ok, info = pcall(C_Spell.GetSpellInfo, 2649)
            if ok and type(info) == "table" and not IsSecret(info.name) and type(info.name) == "string" and info.name ~= "" then
                return info.name
            end
        end
        if type(GetSpellInfo) == "function" then
            local ok, nm = pcall(GetSpellInfo, 2649)
            if ok and not IsSecret(nm) and type(nm) == "string" and nm ~= "" then
                return nm
            end
        end
        return "Growl"
    end

    local function GetPvEInstanceState()
        if type(IsInInstance) ~= "function" then
            return false, nil, nil
        end
        local okInst, inInst, instType = pcall(IsInInstance)
        if not okInst or not inInst or IsSecret(instType) then
            return false, nil, nil
        end
        if instType ~= "party" and instType ~= "raid" and instType ~= "scenario" then
            return false, nil, nil
        end
        local instName, instMapID = "", 0
        if type(GetInstanceInfo) == "function" then
            local okInfo, nm, _, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
            if okInfo then
                instName = YRG.SafeString(nm, "") or ""
                instMapID = YRG.SafeNumber(mapID, 0)
            end
        end
        local key = instName .. ":" .. tostring(instMapID) .. ":" .. tostring(instType)
        return true, key, (instName ~= "" and instName or nil)
    end

    local function TryDisableGrowlInPetSpellbook(growlName)
        local petBook = BOOKTYPE_PET or "pet"
        local growlLow = growlName:lower()

        local function CheckAndDisableSpellArg(spellArg)
            if type(GetSpellAutocast) ~= "function" then return false end
            local okA, autocastable, autostate = pcall(GetSpellAutocast, spellArg, petBook)
            if okA and autocastable and autostate then
                if type(DisableSpellAutocast) == "function" then
                    pcall(DisableSpellAutocast, spellArg, petBook)
                    return true
                elseif type(ToggleSpellAutocast) == "function" then
                    pcall(ToggleSpellAutocast, spellArg, petBook)
                    return true
                end
            end
            return false
        end

        if type(GetSpellBookItemName) == "function" and type(HasPetSpells) == "function" then
            local okNum, numSpells = pcall(HasPetSpells)
            if okNum and type(numSpells) == "number" and not IsSecret(numSpells) and numSpells > 0 then
                for i = 1, numSpells do
                    local okSp, spName, spSub = pcall(GetSpellBookItemName, i, petBook)
                    if okSp and type(spName) == "string" and not IsSecret(spName) and spName:lower() == growlLow then
                        local fullArg = (type(spSub) == "string" and not IsSecret(spSub) and spSub ~= "")
                            and (spName .. "(" .. spSub .. ")") or spName
                        if CheckAndDisableSpellArg(fullArg) then
                            return true
                        end
                        if fullArg ~= spName and CheckAndDisableSpellArg(spName) then
                            return true
                        end
                        return false
                    end
                end
            end
        end

        return CheckAndDisableSpellArg(growlName)
    end

    local function TryApplyBetterPartyMember()
        if not pendingPartyPrep then return end
        local modDB = YRG:GetModuleDB("ClassImprovementsModule")
        if not modDB or not modDB.enabled or modDB.hunterBetterPartyMember == false then
            pendingPartyPrep = false
            return
        end
        local _, liveClass = UnitClass("player")
        if IsSecret(liveClass) or liveClass ~= "HUNTER" then
            pendingPartyPrep = false
            return
        end
        local inPvE, _, instName = GetPvEInstanceState()
        if not inPvE then
            pendingPartyPrep = false
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        if not (UnitExists and UnitExists("pet")) or (UnitIsDead and UnitIsDead("pet")) then
            return
        end

        local numSlots = NUM_PET_ACTION_SLOTS or 10
        local growlName = GetGrowlSpellName()
        local growlLow = growlName:lower()
        local sawAnySlot = false
        local passiveSlot, passiveActive = nil, false
        local growlSlot, growlAllowed, growlEnabled = nil, false, false

        if type(GetPetActionInfo) == "function" then
            for slot = 1, numSlots do
                local ok, name, _, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = pcall(GetPetActionInfo, slot)
                if ok and name ~= nil then
                    sawAnySlot = true
                    if isToken and not IsSecret(name) and name == "PET_MODE_PASSIVE" then
                        passiveSlot = slot
                        passiveActive = isActive and true or false
                    elseif not isToken then
                        local matchesName = (type(name) == "string" and not IsSecret(name) and name:lower() == growlLow)
                        local matchesID = (type(spellID) == "number" and not IsSecret(spellID) and GROWL_SPELL_IDS[spellID] == true)
                        if matchesName or matchesID then
                            growlSlot = slot
                            growlAllowed = autoCastAllowed and true or false
                            growlEnabled = autoCastEnabled and true or false
                        end
                    end
                end
            end
        end

        if not sawAnySlot then
            if pendingRetryDepth < 5 and C_Timer and type(C_Timer.After) == "function" then
                pendingRetryDepth = pendingRetryDepth + 1
                C_Timer.After(0.4, TryApplyBetterPartyMember)
            end
            return
        end

        local changedPassive, changedGrowl = false, false
        if not passiveActive then
            if type(PetPassiveMode) == "function" then
                pcall(PetPassiveMode)
                changedPassive = true
            elseif passiveSlot and type(CastPetAction) == "function" then
                pcall(CastPetAction, passiveSlot)
                changedPassive = true
            end
        end

        if growlSlot then
            if growlAllowed and growlEnabled and type(TogglePetAutocast) == "function" then
                pcall(TogglePetAutocast, growlSlot)
                changedGrowl = true
            end
        else
            if TryDisableGrowlInPetSpellbook(growlName) then
                changedGrowl = true
            end
        end

        pendingPartyPrep = false
        pendingRetryDepth = 0

        if changedPassive or changedGrowl then
            local locLabel = instName and (" (" .. instName .. ")") or ""
            local actions = {}
            if changedPassive then actions[#actions + 1] = "pet set to Passive" end
            if changedGrowl then actions[#actions + 1] = "Growl auto-cast disabled" end
            print(string.format("|cffffd100YRG Better Party Member:|r Entered instance%s — %s.",
                locLabel, table.concat(actions, " and ")))
        end
    end

    local function CheckInstanceEntry(isReloadingUi)
        local inPvE, curKey = GetPvEInstanceState()
        if not inPvE then
            wasInPvEInstance = false
            lastInstanceKey = nil
            pendingPartyPrep = false
            pendingRetryDepth = 0
            return
        end

        if (not isReloadingUi) and ((not wasInPvEInstance) or (lastInstanceKey ~= curKey)) then
            pendingPartyPrep = true
            pendingRetryDepth = 0
        end
        wasInPvEInstance = true
        lastInstanceKey = curKey

        if pendingPartyPrep then
            TryApplyBetterPartyMember()
        end
    end

    function BetterParty.OnEvent(event, arg1, arg2)
        if event == "PLAYER_ENTERING_WORLD" then
            local isReloading = (arg2 == true)
            CheckInstanceEntry(isReloading)
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            CheckInstanceEntry(false)
        elseif event == "UNIT_PET" then
            if arg1 == "player" and pendingPartyPrep then
                TryApplyBetterPartyMember()
            end
        elseif event == "PET_BAR_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
            if pendingPartyPrep then
                TryApplyBetterPartyMember()
            end
        end
    end

    function BetterParty.OnEnable()
        if type(IsLoggedIn) == "function" and IsLoggedIn() then
            CheckInstanceEntry(true)
        end
    end

    function BetterParty.OnDisable()
        wasInPvEInstance = false
        lastInstanceKey = nil
        pendingPartyPrep = false
        pendingRetryDepth = 0
    end
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
        tooltip = "Restores nameplate combo point and Druid Mana bar settings back to their default values.",
        onClick = function()
            local mdb = GetDB()
            if mdb then
                for _, key in ipairs({ "position", "pipSize", "spacing", "offsetX", "offsetY", "castBarDrop", "scale", "showDruidManaBar" }) do
                    mdb[key] = self.defaults[key]
                end
            end
            testMode = false
            ctx:NotifyAll()
            self:ApplyLayout()
            self:UpdateTargetNameplate()
            self:UpdateDruidManaBar()
        end,
    })

    ctx:AddHeader(
        "3. OB Prep (One-Button Prep)",
        "All-class one-button prep via YRGOBP (/yrgobprep). Checks in order: Poisons (Rogue) -> Weapon Oils / Stones -> Food Buff -> Potions / Elixirs -> Class Self-Buffs (1 action per press). Automatically warns and skips missing items or buffs blocked by a more powerful active effect."
    )

    ctx:AddButton({
        name = "Prep Macro (YRGOBP)",
        buttonText = "Create / Reset Macro",
        tooltip = "Creates (or resets) the YRGOBP macro calling /yrgobprep (also keeps YRGRP working if present).",
        onClick = function()
            EnsureRoguePrepMacro(true, true)
        end,
    })

    ctx:AddButton({
        name = "OB Prep Status",
        buttonText = "Check Status",
        tooltip = "Prints current Main Hand / Off Hand enchants, active buffs, and the next queued OB Prep action.",
        onClick = function()
            RunOBPrepSlash("status")
        end,
    })

    ctx:AddDropdown({
        key = "obPrepMainHand",
        name = "Main Hand Poison (Rogue)",
        tooltip = "Select the poison type or specific poison level to keep active on your Main Hand weapon (Rogues only).",
        defaultValue = "INSTANT_BEST",
        options = POISON_DROPDOWN_OPTIONS,
        get = function()
            local mdb = GetDB()
            local val = mdb and mdb.obPrepMainHand
            return (val and VALID_POISON_SELECTIONS[val]) and val or "INSTANT_BEST"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepMainHand = VALID_POISON_SELECTIONS[val] and val or "INSTANT_BEST"
            end
            EnsureRoguePrepMacro(false, false)
        end,
    })

    ctx:AddDropdown({
        key = "obPrepOffHand",
        name = "Off Hand Poison (Rogue)",
        tooltip = "Select the poison type or specific poison level to keep active on your Off Hand weapon (Rogues only).",
        defaultValue = "INSTANT_BEST",
        options = POISON_DROPDOWN_OPTIONS,
        get = function()
            local mdb = GetDB()
            local val = mdb and mdb.obPrepOffHand
            return (val and VALID_POISON_SELECTIONS[val]) and val or "INSTANT_BEST"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepOffHand = VALID_POISON_SELECTIONS[val] and val or "INSTANT_BEST"
            end
            EnsureRoguePrepMacro(false, false)
        end,
    })

    ctx:AddCheckbox({
        key = "obPrepUseStones",
        name = "Use Weapon Enhancement Stones (Sharpening / Weight)",
        tooltip = "Applies the highest-rank Sharpening Stone (bladed weapons) or Weightstone (maces/staves/fist weapons) found in your bags (only Sharpening Stones and Weightstones).",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.obPrepUseStones) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepUseStones = val and true or false
            end
            EnsureRoguePrepMacro(false, false)
        end,
    })

    ctx:AddCheckbox({
        key = "obPrepUseWizardOils",
        name = "Use Wizard / Mana Oils (Supersedes Weapon Stones)",
        tooltip = "Applies the best Wizard Oil (or Mana Oil fallback) in your bags to equipped weapons. Supersedes Weapon Enhancement Stones when both are checked and an Oil is in bags.",
        defaultValue = false,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.obPrepUseWizardOils) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepUseWizardOils = val and true or false
            end
            EnsureRoguePrepMacro(false, false)
        end,
    })

    ctx:AddSlider({
        key = "obPrepWeaponOverbuffMinutes",
        name = "Weapon / Poison Overbuff Early Timer",
        tooltip = "Refresh Poisons and Weapon Stones/Oils early when this many minutes or fewer remain (0 = only apply when missing).",
        min = 0,
        max = 30,
        step = 1,
        defaultValue = 5,
        format = function(v)
            local n = math.floor((tonumber(v) or 0) + 0.5)
            if n <= 0 then return "0 min (Missing Only)" end
            return string.format("%d min", n)
        end,
        roundFn = function(v)
            return math.max(0, math.min(30, math.floor((tonumber(v) or 0) + 0.5)))
        end,
        get = function()
            local mdb = GetDB()
            return math.max(0, math.min(30, math.floor(YRG.SafeNumber(mdb and mdb.obPrepWeaponOverbuffMinutes, 5) + 0.5)))
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepWeaponOverbuffMinutes = math.max(0, math.min(30, math.floor((tonumber(val) or 0) + 0.5)))
            end
        end,
    })

    ctx:AddCheckbox({
        key = "obPrepUseFoodBuff",
        name = "Use Food Buff",
        tooltip = "Eats your configured Food Buff when Well Fed (or Food) is missing or expiring.",
        defaultValue = true,
        notifies = { "YRG_ClassImprovementsModule_obPrepFoodSummary" },
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.obPrepUseFoodBuff) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepUseFoodBuff = val and true or false
            end
            EnsureRoguePrepMacro(false, false)
        end,
    })

    local function GetFoodSummaryLabel()
        local mdb = GetDB()
        local f = mdb and mdb.obPrepFoodName
        if type(f) == "string" and f ~= "" then
            return "Food Buff Item: [" .. f .. "]"
        end
        return "Food Buff Item: [Not Set]"
    end

    local foodBtnInit = ctx:AddButton({
        name = GetFoodSummaryLabel(),
        buttonText = "Configure...",
        tooltip = "Opens OB Prep: Consumables & Buffs to type, Shift-Click, or drop your Food Buff item.",
        onClick = function()
            YRG:OpenSettings("OBPrepConfig")
        end,
    })

    ctx:AddCheckbox({
        key = "obPrepUseElixirs",
        name = "Use Potions / Elixirs",
        tooltip = "Drinks missing or expiring Potions / Elixirs from your configured list in order.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.obPrepUseElixirs) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepUseElixirs = val and true or false
            end
            EnsureRoguePrepMacro(false, false)
        end,
    })

    local function GetElixirSummaryLabel()
        local mdb = GetDB()
        local cnt = (mdb and type(mdb.obPrepElixirList) == "table") and #mdb.obPrepElixirList or 0
        return string.format("Potions / Elixirs List (%d configured)", cnt)
    end

    local elixirBtnInit = ctx:AddButton({
        name = GetElixirSummaryLabel(),
        buttonText = "Manage List...",
        tooltip = "Opens OB Prep: Consumables & Buffs to add, remove, or reorder your Potions / Elixirs.",
        onClick = function()
            YRG:OpenSettings("OBPrepConfig")
        end,
    })

    ctx:AddCheckbox({
        key = "obPrepAutoSelfBuff",
        name = "Auto Self-Buff (Class Priority)",
        tooltip = "Automatically casts missing or expiring class self-buffs based on your class and level (or your custom Override CSV below).",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.obPrepAutoSelfBuff ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepAutoSelfBuff = val and true or false
            end
            EnsureRoguePrepMacro(false, false)
        end,
    })

    ctx:AddSlider({
        key = "obPrepBuffOverbuffMinutes",
        name = "Buffs / Consumables Rebuff Early Timer",
        tooltip = "Refresh Food, Potions/Elixirs, and Class Self-Buffs early when this many minutes or fewer remain (capped at half a spell's max duration for short buffs like Thorns or Lightning Shield; 0 = only when missing).",
        min = 0,
        max = 30,
        step = 1,
        defaultValue = 5,
        format = function(v)
            local n = math.floor((tonumber(v) or 0) + 0.5)
            if n <= 0 then return "0 min (Missing Only)" end
            return string.format("%d min", n)
        end,
        roundFn = function(v)
            return math.max(0, math.min(30, math.floor((tonumber(v) or 0) + 0.5)))
        end,
        get = function()
            local mdb = GetDB()
            return math.max(0, math.min(30, math.floor(YRG.SafeNumber(mdb and mdb.obPrepBuffOverbuffMinutes, 5) + 0.5)))
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepBuffOverbuffMinutes = math.max(0, math.min(30, math.floor((tonumber(val) or 0) + 0.5)))
            end
        end,
    })

    ctx:AddCheckbox({
        key = "obPrepOverrideBuffs",
        name = "Override Default Class Buffs",
        tooltip = "When checked, uses your custom comma-separated Buffs CSV list instead of the automatic class & level priority list.",
        defaultValue = false,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.obPrepOverrideBuffs) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.obPrepOverrideBuffs = val and true or false
            end
        end,
    })

    local function GetOverrideSummaryLabel()
        local mdb = GetDB()
        local csv = mdb and mdb.obPrepOverrideBuffsCSV
        if type(csv) == "string" and csv ~= "" then
            return "Override Buffs CSV: [" .. csv .. "]"
        end
        return "Override Buffs CSV: [Not Set]"
    end

    local overrideBtnInit = ctx:AddButton({
        name = GetOverrideSummaryLabel(),
        buttonText = "Edit CSV...",
        tooltip = "Opens OB Prep: Consumables & Buffs to enter custom buff names (e.g. \"Might, Shield\").",
        onClick = function()
            YRG:OpenSettings("OBPrepConfig")
        end,
    })

    obPrepSummaryUpdaters.refreshMain = function()
        if foodBtnInit and foodBtnInit.data then foodBtnInit.data.name = GetFoodSummaryLabel() end
        if elixirBtnInit and elixirBtnInit.data then elixirBtnInit.data.name = GetElixirSummaryLabel() end
        if overrideBtnInit and overrideBtnInit.data then overrideBtnInit.data.name = GetOverrideSummaryLabel() end
    end

    ctx:AddHeader(
        "4. Hunter Pet Improvements",
        "AutoFeeder picks the lowest-quality usable food matching your pet's diet and level (/yrg petfeed or click Pet Happiness). Better Party Member prepares your pet automatically on instance entry."
    )

    ctx:AddCheckbox({
        key = "hunterBetterPartyMember",
        name = "Better Party Member (Passive + Growl Off in Instances)",
        tooltip = "Automatically sets your Hunter pet to Passive and disables Growl auto-cast whenever entering a party, raid, or scenario instance (waits cleanly if your pet spawns after loading).",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.hunterBetterPartyMember ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.hunterBetterPartyMember = val and true or false
            end
        end,
    })

    ctx:AddCheckbox({
        key = "petFeederEnabled",
        name = "Enable Hunter Pet AutoFeeder",
        tooltip = "Enables clicking the Pet Happiness frame (PC) and the /yrg petfeed macro (Controller/SteamDeck) to feed your Hunter pet automatically.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.petFeederEnabled ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.petFeederEnabled = val and true or false
            end
            if PetFeeder.SyncOverlay then
                PetFeeder.SyncOverlay()
            end
            if val and PetFeeder.EnsureMacro then
                local _, liveClass = UnitClass("player")
                if not IsSecret(liveClass) and liveClass == "HUNTER" then
                    PetFeeder.EnsureMacro(false, false)
                end
            end
        end,
    })

    ctx:AddCheckbox({
        key = "petFeederIgnoreCrafted",
        name = "Ignore Crafted / Buff Foods",
        tooltip = "Ignores player-cooked recipes and Well Fed buff foods so they aren't accidentally fed to your pet (keeps raw drops, vendor foods, and conjured bread unless blacklisted).",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.petFeederIgnoreCrafted ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.petFeederIgnoreCrafted = val and true or false
            end
        end,
    })

    ctx:AddButton({
        name = "Pet Feed Macro (YRGPF)",
        buttonText = "Create / Reset Macro",
        tooltip = "Creates (or resets) the YRGPF macro calling /yrg petfeed for Controller/SteamDeck hotbars.",
        onClick = function()
            if PetFeeder.EnsureMacro then
                PetFeeder.EnsureMacro(true, true)
            end
        end,
    })

    ctx:AddButton({
        name = "Pet Feeder Status",
        buttonText = "Check Status",
        tooltip = "Prints active pet diet, happiness, and the next food item selected by Hunter Pet AutoFeeder.",
        onClick = function()
            if PetFeeder.RunSlash then
                PetFeeder.RunSlash("status")
            end
        end,
    })

    local function GetPetBlacklistSummaryLabel()
        local mdb = GetDB()
        local cnt = (mdb and type(mdb.petFeederBlacklist) == "table") and #mdb.petFeederBlacklist or 0
        return string.format("Pet Food Blacklist (%d avoided)", cnt)
    end

    local petBlacklistBtnInit = ctx:AddButton({
        name = GetPetBlacklistSummaryLabel(),
        buttonText = "Manage Blacklist...",
        tooltip = "Opens Hunter Pet AutoFeeder: Blacklist to enter, Shift-Click, or drag-and-drop foods to always avoid feeding.",
        onClick = function()
            YRG:OpenSettings("PetFeederBlacklist")
        end,
    })

    if PetFeeder.SetBlacklistUpdater then
        PetFeeder.SetBlacklistUpdater(function()
            if petBlacklistBtnInit and petBlacklistBtnInit.data then
                petBlacklistBtnInit.data.name = GetPetBlacklistSummaryLabel()
            end
        end)
    end
end

function ClassImprovements:BuildExtraCategories(mainCategory, db)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory and Settings.RegisterAddOnCategory and mainCategory) then
        return
    end

    local panel = CreateFrame("Frame", "YRGOBPrepConfigPanel", UIParent)
    panel.name = "OB Prep: Consumables & Buffs"
    panel:Hide()

    local built = false
    local refreshFunc = nil

    local function BuildCanvas()
        if built then return end
        built = true

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -16)
        title:SetText("OB Prep: Consumables & Custom Buffs")

        local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        subtitle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -44)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetText("Configure Food Buff, Potions/Elixirs priority list, and custom Buff Overrides CSV. Item boxes support typing, Shift-Click links, and drag-and-drop.")

        -- 1. FOOD BUFF
        local foodLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        foodLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -74)
        foodLabel:SetText("Food Buff Item Name (or comma-separated fallback names):")

        local foodInput = CreateFrame("EditBox", "YRGOBPrepFoodInput", panel, "InputBoxTemplate")
        foodInput:SetSize(280, 24)
        foodInput:SetPoint("TOPLEFT", foodLabel, "BOTTOMLEFT", 4, -6)
        foodInput:SetAutoFocus(false)

        local foodSaveBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        foodSaveBtn:SetSize(64, 24)
        foodSaveBtn:SetPoint("LEFT", foodInput, "RIGHT", 8, 0)
        foodSaveBtn:SetText("Save")

        local foodClearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        foodClearBtn:SetSize(64, 24)
        foodClearBtn:SetPoint("LEFT", foodSaveBtn, "RIGHT", 6, 0)
        foodClearBtn:SetText("Clear")

        local function SaveFoodInput()
            local mdb = YRG:GetModuleDB("ClassImprovementsModule")
            if mdb then
                local raw = foodInput:GetText() or ""
                local clean = StripColorCodes(raw)
                mdb.obPrepFoodName = clean
                foodInput:SetText(clean)
                foodInput:ClearFocus()
                if obPrepSummaryUpdaters.refreshMain then obPrepSummaryUpdaters.refreshMain() end
            end
        end
        foodSaveBtn:SetScript("OnClick", SaveFoodInput)
        foodInput:SetScript("OnEnterPressed", SaveFoodInput)
        foodClearBtn:SetScript("OnClick", function()
            local mdb = YRG:GetModuleDB("ClassImprovementsModule")
            if mdb then mdb.obPrepFoodName = "" end
            foodInput:SetText("")
            foodInput:ClearFocus()
            if obPrepSummaryUpdaters.refreshMain then obPrepSummaryUpdaters.refreshMain() end
        end)
        foodInput:SetScript("OnReceiveDrag", function()
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" then
                local name = NormalizePrepItemName(itemLink) or select(1, SafeGetItemStatsForPrep(itemID, itemLink))
                if name then
                    foodInput:SetText(name)
                    SaveFoodInput()
                    ClearCursor()
                end
            end
        end)

        -- 2. OVERRIDE BUFF CSV
        local csvLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        csvLabel:SetPoint("TOPLEFT", foodInput, "BOTTOMLEFT", -4, -18)
        csvLabel:SetText("Override Default Buffs CSV (e.g. \"Might, Shield\" or \"Mark of the Wild, Thorns\"):")

        local csvInput = CreateFrame("EditBox", "YRGOBPrepBuffCSVInput", panel, "InputBoxTemplate")
        csvInput:SetSize(280, 24)
        csvInput:SetPoint("TOPLEFT", csvLabel, "BOTTOMLEFT", 4, -6)
        csvInput:SetAutoFocus(false)

        local csvSaveBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        csvSaveBtn:SetSize(64, 24)
        csvSaveBtn:SetPoint("LEFT", csvInput, "RIGHT", 8, 0)
        csvSaveBtn:SetText("Save")

        local csvClearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        csvClearBtn:SetSize(64, 24)
        csvClearBtn:SetPoint("LEFT", csvSaveBtn, "RIGHT", 6, 0)
        csvClearBtn:SetText("Clear")

        local function SaveCSVInput()
            local mdb = YRG:GetModuleDB("ClassImprovementsModule")
            if mdb then
                local clean = StripColorCodes(csvInput:GetText() or "")
                mdb.obPrepOverrideBuffsCSV = clean
                csvInput:SetText(clean)
                csvInput:ClearFocus()
                if obPrepSummaryUpdaters.refreshMain then obPrepSummaryUpdaters.refreshMain() end
            end
        end
        csvSaveBtn:SetScript("OnClick", SaveCSVInput)
        csvInput:SetScript("OnEnterPressed", SaveCSVInput)
        csvClearBtn:SetScript("OnClick", function()
            local mdb = YRG:GetModuleDB("ClassImprovementsModule")
            if mdb then mdb.obPrepOverrideBuffsCSV = "" end
            csvInput:SetText("")
            csvInput:ClearFocus()
            if obPrepSummaryUpdaters.refreshMain then obPrepSummaryUpdaters.refreshMain() end
        end)

        -- 3. POTIONS / ELIXIRS PRIORITY LIST
        local elixirLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        elixirLabel:SetPoint("TOPLEFT", csvInput, "BOTTOMLEFT", -4, -18)
        elixirLabel:SetText("Add Potion / Elixir to Priority List (applied top-to-bottom):")

        local elixirInput = CreateFrame("EditBox", "YRGOBPrepElixirInput", panel, "InputBoxTemplate")
        elixirInput:SetSize(280, 24)
        elixirInput:SetPoint("TOPLEFT", elixirLabel, "BOTTOMLEFT", 4, -6)
        elixirInput:SetAutoFocus(false)

        local elixirAddBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        elixirAddBtn:SetSize(84, 24)
        elixirAddBtn:SetPoint("LEFT", elixirInput, "RIGHT", 8, 0)
        elixirAddBtn:SetText("Add Item")

        local listBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        listBox:SetPoint("TOPLEFT", elixirInput, "BOTTOMLEFT", -4, -10)
        listBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -34, 18)
        if listBox.SetBackdrop then
            listBox:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 }
            })
            listBox:SetBackdropColor(0.05, 0.05, 0.06, 0.75)
            listBox:SetBackdropBorderColor(0.45, 0.38, 0.24, 0.75)
        end

        local scrollFrame = CreateFrame("ScrollFrame", "YRGOBPrepElixirScroll", listBox, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", listBox, "TOPLEFT", 6, -6)
        scrollFrame:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -26, 6)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(460, 200)
        scrollFrame:SetScrollChild(scrollChild)

        local rows = {}
        refreshFunc = function()
            local mdb = YRG:GetModuleDB("ClassImprovementsModule")
            if not mdb then return end
            if type(mdb.obPrepElixirList) ~= "table" then mdb.obPrepElixirList = {} end

            if not foodInput:HasFocus() then
                foodInput:SetText(mdb.obPrepFoodName or "")
            end
            if not csvInput:HasFocus() then
                csvInput:SetText(mdb.obPrepOverrideBuffsCSV or "")
            end

            for _, r in ipairs(rows) do
                r:Hide()
            end

            local list = mdb.obPrepElixirList
            local rowH = 26
            scrollChild:SetWidth(math.max(380, scrollFrame:GetWidth() or 420))
            scrollChild:SetHeight(math.max(1, #list * rowH))

            for idx, itemName in ipairs(list) do
                local row = rows[idx]
                if not row then
                    row = CreateFrame("Frame", nil, scrollChild)
                    row:SetHeight(rowH)
                    local bg = row:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    row._bg = bg

                    local txt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                    txt:SetPoint("LEFT", row, "LEFT", 8, 0)
                    txt:SetPoint("RIGHT", row, "RIGHT", -130, 0)
                    txt:SetJustifyH("LEFT")
                    row._txt = txt

                    local rmBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    rmBtn:SetSize(64, 20)
                    rmBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                    rmBtn:SetText("Remove")
                    row._rmBtn = rmBtn

                    local dnBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    dnBtn:SetSize(24, 20)
                    dnBtn:SetPoint("RIGHT", rmBtn, "LEFT", -4, 0)
                    dnBtn:SetText("v")
                    row._dnBtn = dnBtn

                    local upBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    upBtn:SetSize(24, 20)
                    upBtn:SetPoint("RIGHT", dnBtn, "LEFT", -4, 0)
                    upBtn:SetText("^")
                    row._upBtn = upBtn

                    rows[idx] = row
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((idx - 1) * rowH))
                row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -((idx - 1) * rowH))
                row._bg:SetColorTexture(0.14, 0.14, 0.17, (idx % 2 == 0) and 0.45 or 0.22)
                row._txt:SetText(string.format("%d. %s", idx, tostring(itemName)))

                row._upBtn:SetEnabled(idx > 1)
                row._upBtn:SetScript("OnClick", function()
                    if idx > 1 then
                        list[idx], list[idx - 1] = list[idx - 1], list[idx]
                        refreshFunc()
                    end
                end)

                row._dnBtn:SetEnabled(idx < #list)
                row._dnBtn:SetScript("OnClick", function()
                    if idx < #list then
                        list[idx], list[idx + 1] = list[idx + 1], list[idx]
                        refreshFunc()
                    end
                end)

                row._rmBtn:SetScript("OnClick", function()
                    table.remove(list, idx)
                    refreshFunc()
                end)

                row:Show()
            end

            if obPrepSummaryUpdaters.refreshMain then
                obPrepSummaryUpdaters.refreshMain()
            end
        end

        local function AddElixirFromInput(nameOverride)
            local clean = NormalizePrepItemName(nameOverride or elixirInput:GetText() or "")
            if not clean then return end
            local mdb = YRG:GetModuleDB("ClassImprovementsModule")
            if mdb then
                if type(mdb.obPrepElixirList) ~= "table" then mdb.obPrepElixirList = {} end
                local exists = false
                local lowClean = clean:lower()
                for _, existing in ipairs(mdb.obPrepElixirList) do
                    if type(existing) == "string" and existing:lower() == lowClean then
                        exists = true
                        break
                    end
                end
                if not exists then
                    table.insert(mdb.obPrepElixirList, clean)
                end
            end
            elixirInput:SetText("")
            elixirInput:ClearFocus()
            refreshFunc()
        end

        elixirAddBtn:SetScript("OnClick", function() AddElixirFromInput() end)
        elixirInput:SetScript("OnEnterPressed", function() AddElixirFromInput() end)
        elixirInput:SetScript("OnReceiveDrag", function()
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" then
                local name = NormalizePrepItemName(itemLink) or select(1, SafeGetItemStatsForPrep(itemID, itemLink))
                if name then
                    ClearCursor()
                    AddElixirFromInput(name)
                end
            end
        end)

        if type(ChatEdit_InsertLink) == "function" then
            hooksecurefunc("ChatEdit_InsertLink", function(text)
                if not text then return end
                local name = NormalizePrepItemName(text)
                if not name then return end
                if foodInput:IsVisible() and foodInput:HasFocus() then
                    foodInput:SetText(name)
                elseif elixirInput:IsVisible() and elixirInput:HasFocus() then
                    elixirInput:SetText(name)
                end
            end)
        end
    end

    panel:SetScript("OnShow", function()
        BuildCanvas()
        if refreshFunc then refreshFunc() end
    end)

    local obCat = Settings.RegisterCanvasLayoutSubcategory(mainCategory, panel, "OB Prep: Consumables & Buffs")
    Settings.RegisterAddOnCategory(obCat)
    YRG:RegisterExtraCategory("OBPrepConfig", obCat)

    -- 2. HUNTER PET AUTOFEEDER: FOOD BLACKLIST SUBCATEGORY
    local petPanel = CreateFrame("Frame", "YRGPetFeederBlacklistPanel", UIParent)
    petPanel.name = "Hunter Pet AutoFeeder: Blacklist"
    petPanel:Hide()

    local petBuilt = false
    local petRefreshFunc = nil

    local function BuildPetBlacklistCanvas()
        if petBuilt then return end
        petBuilt = true

        local title = petPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
        title:SetPoint("TOPLEFT", petPanel, "TOPLEFT", 18, -16)
        title:SetText("Hunter Pet AutoFeeder: Food Blacklist")

        local subtitle = petPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        subtitle:SetPoint("TOPRIGHT", petPanel, "TOPRIGHT", -24, -44)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetText("Foods added here will NEVER be fed to your pet. Supports typing item names, Shift-Clicking bag items, or dragging items into the box.")

        local inputLabel = petPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        inputLabel:SetPoint("TOPLEFT", petPanel, "TOPLEFT", 18, -78)
        inputLabel:SetText("Add Food Item to Always Avoid:")

        local blInput = CreateFrame("EditBox", "YRGPetFeederBlacklistInput", petPanel, "InputBoxTemplate")
        blInput:SetSize(280, 24)
        blInput:SetPoint("TOPLEFT", inputLabel, "BOTTOMLEFT", 4, -6)
        blInput:SetAutoFocus(false)

        local blAddBtn = CreateFrame("Button", nil, petPanel, "UIPanelButtonTemplate")
        blAddBtn:SetSize(84, 24)
        blAddBtn:SetPoint("LEFT", blInput, "RIGHT", 8, 0)
        blAddBtn:SetText("Add Item")

        local blClearAllBtn = CreateFrame("Button", nil, petPanel, "UIPanelButtonTemplate")
        blClearAllBtn:SetSize(84, 24)
        blClearAllBtn:SetPoint("LEFT", blAddBtn, "RIGHT", 6, 0)
        blClearAllBtn:SetText("Clear All")

        local listBox = CreateFrame("Frame", nil, petPanel, "BackdropTemplate")
        listBox:SetPoint("TOPLEFT", blInput, "BOTTOMLEFT", -4, -12)
        listBox:SetPoint("BOTTOMRIGHT", petPanel, "BOTTOMRIGHT", -34, 18)
        if listBox.SetBackdrop then
            listBox:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 }
            })
            listBox:SetBackdropColor(0.05, 0.05, 0.06, 0.75)
            listBox:SetBackdropBorderColor(0.45, 0.38, 0.24, 0.75)
        end

        local scrollFrame = CreateFrame("ScrollFrame", "YRGPetFeederBlacklistScroll", listBox, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", listBox, "TOPLEFT", 6, -6)
        scrollFrame:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -26, 6)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(460, 200)
        scrollFrame:SetScrollChild(scrollChild)

        local rows = {}
        petRefreshFunc = function()
            local mdb = YRG:GetModuleDB("ClassImprovementsModule")
            if not mdb then return end
            if type(mdb.petFeederBlacklist) ~= "table" then mdb.petFeederBlacklist = {} end

            for _, r in ipairs(rows) do
                r:Hide()
            end

            local list = mdb.petFeederBlacklist
            local rowH = 26
            scrollChild:SetWidth(math.max(380, scrollFrame:GetWidth() or 420))
            scrollChild:SetHeight(math.max(1, #list * rowH))

            for idx, itemName in ipairs(list) do
                local row = rows[idx]
                if not row then
                    row = CreateFrame("Frame", nil, scrollChild)
                    row:SetHeight(rowH)
                    local bg = row:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    row._bg = bg

                    local txt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                    txt:SetPoint("LEFT", row, "LEFT", 8, 0)
                    txt:SetPoint("RIGHT", row, "RIGHT", -80, 0)
                    txt:SetJustifyH("LEFT")
                    row._txt = txt

                    local rmBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    rmBtn:SetSize(64, 20)
                    rmBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                    rmBtn:SetText("Remove")
                    row._rmBtn = rmBtn

                    rows[idx] = row
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((idx - 1) * rowH))
                row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -((idx - 1) * rowH))
                row._bg:SetColorTexture(0.14, 0.14, 0.17, (idx % 2 == 0) and 0.45 or 0.22)
                row._txt:SetText(string.format("%d. %s", idx, tostring(itemName)))

                row._rmBtn:SetScript("OnClick", function()
                    table.remove(list, idx)
                    petRefreshFunc()
                end)

                row:Show()
            end

            if PetFeeder.RefreshBlacklistSummary then
                PetFeeder.RefreshBlacklistSummary()
            end
        end

        local function AddBlacklistFromInput(nameOverride)
            local clean = NormalizePrepItemName(nameOverride or blInput:GetText() or "")
            if not clean then return end
            local mdb = YRG:GetModuleDB("ClassImprovementsModule")
            if mdb then
                if type(mdb.petFeederBlacklist) ~= "table" then mdb.petFeederBlacklist = {} end
                local exists = false
                local lowClean = clean:lower()
                for _, existing in ipairs(mdb.petFeederBlacklist) do
                    if type(existing) == "string" and existing:lower() == lowClean then
                        exists = true
                        break
                    end
                end
                if not exists then
                    table.insert(mdb.petFeederBlacklist, clean)
                end
            end
            blInput:SetText("")
            blInput:ClearFocus()
            petRefreshFunc()
        end

        blAddBtn:SetScript("OnClick", function() AddBlacklistFromInput() end)
        blInput:SetScript("OnEnterPressed", function() AddBlacklistFromInput() end)
        blClearAllBtn:SetScript("OnClick", function()
            local mdb = YRG:GetModuleDB("ClassImprovementsModule")
            if mdb then mdb.petFeederBlacklist = {} end
            petRefreshFunc()
        end)
        blInput:SetScript("OnReceiveDrag", function()
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" then
                local name = NormalizePrepItemName(itemLink) or select(1, SafeGetItemStatsForPrep(itemID, itemLink))
                if name then
                    ClearCursor()
                    AddBlacklistFromInput(name)
                end
            end
        end)

        if type(ChatEdit_InsertLink) == "function" then
            hooksecurefunc("ChatEdit_InsertLink", function(text)
                if not text then return end
                local name = NormalizePrepItemName(text)
                if not name then return end
                if blInput:IsVisible() and blInput:HasFocus() then
                    blInput:SetText(name)
                end
            end)
        end
    end

    petPanel:SetScript("OnShow", function()
        BuildPetBlacklistCanvas()
        if petRefreshFunc then petRefreshFunc() end
    end)

    local petCat = Settings.RegisterCanvasLayoutSubcategory(mainCategory, petPanel, "Hunter Pet AutoFeeder: Blacklist")
    Settings.RegisterAddOnCategory(petCat)
    YRG:RegisterExtraCategory("PetFeederBlacklist", petCat)
end

SLASH_YRGOBPREP1 = "/yrgobprep"
SlashCmdList["YRGOBPREP"] = function(msg)
    RunOBPrepSlash(msg)
end

SLASH_YRGROGUEPREP1 = "/yrgrogueprep"
SlashCmdList["YRGROGUEPREP"] = function(msg)
    RunOBPrepSlash(msg)
end

if type(YRG.RegisterSlashSubcommand) == "function" then
    YRG:RegisterSlashSubcommand("petfeed", function(msg)
        if PetFeeder.RunSlash then
            PetFeeder.RunSlash(msg)
        end
    end)
end

SLASH_YRGPETFEED1 = "/yrgpetfeed"
SlashCmdList["YRGPETFEED"] = function(msg)
    if PetFeeder.RunSlash then
        PetFeeder.RunSlash(msg)
    end
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
