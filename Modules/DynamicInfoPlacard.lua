local _, YRG = ...

local ICON_SKULL  = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local ICON_WATCH  = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local ICON_MAP    = "Interface\\Icons\\INV_Misc_Map_01"
local ICON_BAG    = "Interface\\Icons\\INV_Misc_Bag_08"
local ICON_ARROW  = 132382 -- INV_Ammo_Arrow_01
local ICON_BULLET = 132384 -- INV_Ammo_Bullet_01
local ICON_SHARD  = 134075 -- INV_Misc_Gem_Amethyst_02
local SOUL_SHARD_ITEM_ID = 6265

local MASK_CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TEX_FALLBACK_RING = "Interface\\Minimap\\MiniMap-TrackingBorder"

local ROW1_LEFT_OPTIONS = {
    { value = "gold",   label = "Current Gold (Default)" },
    { value = "coords", label = "Coordinates" },
    { value = "none",   label = "None (Hidden)" },
}

local PLACARD_LOCATION_OPTIONS = {
    { value = "BOTTOM", label = "Bottom (Default)" },
    { value = "TOP",    label = "Top" },
}

local PLACARD_ANCHOR_OPTIONS = {
    { value = "ZONE_TITLE", label = "Zone Title (Auto-Center & Extend)" },
    { value = "MINIMAP",    label = "Minimap" },
}

local function GetRow1LeftMode(db)
    if not db then return "gold" end
    if db.row1LeftMode == "coords" or db.row1LeftMode == "gold" or db.row1LeftMode == "none" then
        return db.row1LeftMode
    end
    if db.showCoordinates == false then
        return "none"
    end
    return "gold"
end

local function FormatPlacardMoneyText(copper, iconSz)
    local total = math.max(0, math.floor(YRG.SafeNumber(copper, 0)))
    local gold = math.floor(total / 10000)
    local silver = math.floor((total % 10000) / 100)
    local bronze = total % 100
    local sz = math.max(9, math.floor((iconSz or 12) * 0.9 + 0.5))
    local gIcon = string.format("|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:1:0|t", sz, sz)
    local sIcon = string.format("|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:1:0|t", sz, sz)
    local cIcon = string.format("|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:1:0|t", sz, sz)
    if gold > 0 then
        return string.format("%d%s %d%s %d%s", gold, gIcon, silver, sIcon, bronze, cIcon)
    elseif silver > 0 then
        return string.format("%d%s %d%s", silver, sIcon, bronze, cIcon)
    end
    return string.format("%d%s", bronze, cIcon)
end

local InfoPlacard = {
    name = "Dynamic Info Placard",
    description = "Independent minimap placard showing Coordinates/Gold, Bag Slots, Ammo, Soul Shards, and Farming pace.",
    defaultEnabled = true,
    defaults = {
        enabled = true,
        placardLocation = "BOTTOM",
        placardAnchorPoint = "ZONE_TITLE",
        infoPlacardOffsetY = -1,
        infoPlacardWidth = 254,
        rowDividerOpacityPct = 15,
        rowExtraPadding = 6,
        row1LeftMode = "gold",
        showBagSlots = true,
        showArrowsRemaining = true,
        showSoulShards = true,
        showFarmingRow = true,
        bagWarnThreshold = 5,
        ammoWarnThreshold = 200,
        ammoWarnThresholdMelee = 25,
        bagRaidWarnings = true,
        cellPadding = 9,
        row1TextSize = 13,
        row2TextSize = 14,
    }
}

local sessionKillsData = {}
local windowStartTime = nil
local activeCombatStart = nil
local lastCombatEnd = nil
local inCombatState = false

local function GetMinimapUI()
    YRG.MinimapUI = YRG.MinimapUI or {}
    return YRG.MinimapUI
end

local function HandleBuiltInCoordinates(takeOver)
    local builtInCoords = {
        _G["MinimapCoordinates"] or false,
        _G["MinimapCoordinatesText"] or false,
        (Minimap and Minimap.CoordinateFrame) or false,
        (Minimap and Minimap.Coordinates) or false,
    }

    for _, frame in ipairs(builtInCoords) do
        if frame then
            local canToggleVis = (not InCombatLockdown()) and not (type(frame.IsProtected) == "function" and frame:IsProtected())
            if takeOver then
                if not frame._yrgOriginalAlpha then
                    frame._yrgOriginalAlpha = frame:GetAlpha() or 1
                end
                frame:SetAlpha(0)
                if canToggleVis then
                    frame:Hide()
                end
            else
                if frame._yrgOriginalAlpha then
                    frame:SetAlpha(frame._yrgOriginalAlpha)
                else
                    frame:SetAlpha(1)
                end
                if canToggleVis then
                    frame:Show()
                end
            end
        end
    end
end

-- =========================================================================
-- MOB KILL PACE & TIME-TO-LEVEL TRACKING (Excludes Quests & Exploration)
-- =========================================================================
local COMBAT_XP_KILL_WINDOW_MAX_SIZE = 10
local COMBAT_XP_MAX_OUT_OF_COMBAT_GAP = 120 -- >2m out-of-combat gap starts a fresh grind window
local COMBAT_XP_IDLE_RESET_SEC = 300        -- >5m with no kills clears pace display

local function BuildCombatXPPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local out, order = {}, {}
    local i = 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            local pos, conv = fmt:match("^%%(%d+)%$([sd])", i)
            local skip
            if conv then
                skip = #tostring(pos) + 3
            else
                conv = fmt:match("^%%([sd])", i)
                skip = 2
            end
            if conv then
                local argIdx = tonumber(pos) or (#order + 1)
                table.insert(order, { argIdx = argIdx, conv = conv })
                table.insert(out, conv == "d" and "([%d%.,]+)" or "(.-)")
                i = i + skip
            elseif fmt:sub(i + 1, i + 1) == "%" then
                table.insert(out, "%%")
                i = i + 2
            else
                table.insert(out, "%%")
                i = i + 1
            end
        elseif c:find("[%(%)%.%%%+%-%*%?%[%]%^%$]") then
            table.insert(out, "%" .. c)
            i = i + 1
        else
            table.insert(out, c)
            i = i + 1
        end
    end

    local dCapIdx = nil
    for k, meta in ipairs(order) do
        if meta.conv == "d" then
            if dCapIdx == nil or meta.argIdx < (order[dCapIdx] and order[dCapIdx].argIdx or 999) then
                dCapIdx = k
            end
        end
    end
    if not dCapIdx then return nil end
    return { pattern = "^" .. table.concat(out), dCaptureIndex = dCapIdx }
end

local combatXPPatterns = nil

local function GetCombatXPPatterns()
    if combatXPPatterns then
        return combatXPPatterns
    end
    combatXPPatterns = {}
    -- Match ONLY creature-kill XP messages (with dying unit name), never UNNAMED quest/exploration XP
    for _, globalKey in ipairs({
        "COMBATLOG_XPGAIN_FIRSTPERSON",
        "COMBATLOG_XPGAIN_EXHAUSTION1",
        "COMBATLOG_XPGAIN_EXHAUSTION2",
        "COMBATLOG_XPGAIN_EXHAUSTION4",
        "COMBATLOG_XPGAIN_EXHAUSTION5",
        "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP",
        "COMBATLOG_XPGAIN_FIRSTPERSON_RAID",
    }) do
        local pat = BuildCombatXPPattern(_G[globalKey])
        if pat then
            table.insert(combatXPPatterns, pat)
        end
    end
    table.insert(combatXPPatterns, {
        pattern = "^.-%s+dies,?%s+you%s+gain%s+([%d%.,]+)%s+experience",
        dCaptureIndex = 1,
    })
    return combatXPPatterns
end

local function ParseCombatKillXP(rawMsg)
    local msg = YRG.SafeString(rawMsg, nil)
    if not msg or msg == "" then return nil end
    for _, spec in ipairs(GetCombatXPPatterns()) do
        local caps = { msg:match(spec.pattern) }
        if #caps > 0 then
            local rawNum = caps[spec.dCaptureIndex]
            if type(rawNum) == "string" then
                local digits = rawNum:gsub("[^%d]", "")
                local xp = tonumber(digits)
                if xp and xp > 0 then
                    return xp
                end
            end
        end
    end
    return nil
end

local function GetEffectivePullStart(now)
    if inCombatState and activeCombatStart and activeCombatStart <= now then
        return activeCombatStart
    end
    if lastCombatEnd and (now - lastCombatEnd) <= 2.0 and activeCombatStart and activeCombatStart <= now then
        return activeCombatStart
    end
    return nil
end

local function RecordMobKillXP(xp, now)
    if type(xp) ~= "number" or xp <= 0 then return end
    local pullStart = GetEffectivePullStart(now)
    local lastEntry = sessionKillsData[#sessionKillsData]

    if type(lastEntry) == "table" then
        local idleSinceKill = now - lastEntry.t
        local outOfCombatRef = (pullStart and pullStart > lastEntry.t) and pullStart or now
        local gapBetweenPulls = outOfCombatRef - lastEntry.t
        if idleSinceKill > COMBAT_XP_IDLE_RESET_SEC or gapBetweenPulls > COMBAT_XP_MAX_OUT_OF_COMBAT_GAP then
            sessionKillsData = {}
            windowStartTime = nil
            lastEntry = nil
        end
    end

    if #sessionKillsData == 0 then
        -- First kill in window: anchor window start cleanly at combat pull start when available
        windowStartTime = pullStart
    end

    table.insert(sessionKillsData, {
        xp = xp,
        t = now,
        pullStart = pullStart,
    })

    if #sessionKillsData > COMBAT_XP_KILL_WINDOW_MAX_SIZE then
        local removed = table.remove(sessionKillsData, 1)
        local newFirst = sessionKillsData[1]
        if type(removed) == "table" and type(newFirst) == "table" then
            if newFirst.pullStart and removed.pullStart and math.abs(newFirst.pullStart - removed.pullStart) < 0.05 then
                -- Same AoE/multi-mob pull still occupies the front of the window: advance linearly across its shared span
                local baseStart = windowStartTime or newFirst.pullStart
                local sharedLastT = removed.t
                local remInPull = 1
                for _, e in ipairs(sessionKillsData) do
                    if type(e) == "table" and e.pullStart and math.abs(e.pullStart - newFirst.pullStart) < 0.05 then
                        remInPull = remInPull + 1
                        if e.t > sharedLastT then
                            sharedLastT = e.t
                        end
                    else
                        break
                    end
                end
                windowStartTime = baseStart + (math.max(0, sharedLastT - baseStart) / remInPull)
            else
                windowStartTime = removed.t
            end
        end
    end
end

local function IsQuestXPBlocked(questTurnInUntil, now)
    return (questTurnInUntil and now <= questTurnInUntil) and true or false
end

local function GetKillPaceMetrics(remXP)
    local count = #sessionKillsData
    if count == 0 then
        return nil, nil, nil, nil
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    local lastEntry = sessionKillsData[count]
    if type(lastEntry) == "table" and now > 0 and (now - lastEntry.t) > COMBAT_XP_IDLE_RESET_SEC then
        return nil, nil, nil, nil
    end

    local totalXP = 0
    local validEntries = 0
    for _, entry in ipairs(sessionKillsData) do
        local xp = (type(entry) == "table" and entry.xp) or (type(entry) == "number" and entry) or 0
        if xp > 0 then
            totalXP = totalXP + xp
            validEntries = validEntries + 1
        end
    end
    if validEntries == 0 or totalXP <= 0 then
        return nil, nil, nil, nil
    end

    local avgXP = totalXP / validEntries
    local estKills = math.ceil(math.max(remXP, 0) / avgXP)

    local avgInterval = nil
    if type(lastEntry) == "table" then
        if windowStartTime and lastEntry.t > windowStartTime then
            local totalDuration = lastEntry.t - windowStartTime
            if totalDuration >= 0.5 then
                avgInterval = totalDuration / count
            end
        elseif count >= 2 and type(sessionKillsData[1]) == "table" then
            local span = lastEntry.t - sessionKillsData[1].t
            if span >= 0.5 then
                avgInterval = span / (count - 1)
            end
        end
    end

    local estSeconds = nil
    if estKills == 0 then
        estSeconds = 0
    elseif avgInterval then
        estSeconds = estKills * avgInterval
    end
    return estKills, avgXP, avgInterval, estSeconds
end

local function FormatTimeEstimate(estSeconds)
    if estSeconds == nil then
        return "--"
    end
    local roundedSec = math.floor(math.max(0, estSeconds) + 0.5)
    if roundedSec < 60 then
        return string.format("%ds", roundedSec)
    end
    local fullMins = math.max(1, math.floor((estSeconds / 60) + 0.5))
    return string.format("%dm", fullMins)
end

-- =========================================================================
-- INVENTORY, AMMO & WARLOCK SOUL SHARD TRACKERS
-- =========================================================================
local AMMO_CAPABLE_CLASSES = {
    HUNTER = true,
    WARRIOR = true,
    ROGUE = true,
}

local CLASS_WEAPON = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local SUBCLASS_BOW = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Bows) or 2
local SUBCLASS_GUN = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Guns) or 3
local SUBCLASS_CROSSBOW = (Enum and Enum.ItemWeaponSubclass and (Enum.ItemWeaponSubclass.Crossbow or Enum.ItemWeaponSubclass.Crossbows)) or 18

local function ClassifyCapableRangedWeapon(itemID)
    if not itemID then return false, false end
    local _, _, itemSubType, _, _, classID, subClassID
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, itemSubType, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    elseif GetItemInfoInstant then
        _, _, itemSubType, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    end

    if not classID or not subClassID then
        local _, _, _, _, _, _, fullSub, _, _, _, _, fullClass, fullSubClass
        if C_Item and C_Item.GetItemInfo then
            _, _, _, _, _, _, fullSub, _, _, _, _, fullClass, fullSubClass = C_Item.GetItemInfo(itemID)
        elseif GetItemInfo then
            _, _, _, _, _, _, fullSub, _, _, _, _, fullClass, fullSubClass = GetItemInfo(itemID)
        end
        itemSubType = itemSubType or fullSub
        classID = classID or fullClass
        subClassID = subClassID or fullSubClass
    end

    if classID == CLASS_WEAPON then
        if subClassID == SUBCLASS_GUN then
            return true, true
        elseif subClassID == SUBCLASS_BOW or subClassID == SUBCLASS_CROSSBOW then
            return true, false
        end
    end

    if not classID or classID == CLASS_WEAPON then
        local subLower = type(itemSubType) == "string" and itemSubType:lower() or ""
        if subLower:find("gun") then
            return true, true
        elseif subLower:find("bow") or subLower:find("crossbow") then
            return true, false
        end
    end

    return false, false
end

local function GetInventoryAndAmmoStatus()
    local freeNormalSlots = 0
    local maxBagIndex = NUM_BAG_SLOTS or 4
    for bagID = 0, maxBagIndex do
        local numSlots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bagID))
            or (GetContainerNumSlots and GetContainerNumSlots(bagID)) or 0
        if numSlots and numSlots > 0 then
            local freeSlots, bagFamily = 0, 0
            if C_Container and C_Container.GetContainerNumFreeSlots then
                freeSlots, bagFamily = C_Container.GetContainerNumFreeSlots(bagID)
            elseif GetContainerNumFreeSlots then
                freeSlots, bagFamily = GetContainerNumFreeSlots(bagID)
            end
            freeSlots = YRG.SafeNumber(freeSlots, 0)
            bagFamily = YRG.SafeNumber(bagFamily, 0)

            local bagName = (C_Container and C_Container.GetBagName and C_Container.GetBagName(bagID))
                or (GetBagName and GetBagName(bagID))
            local lowerName = type(bagName) == "string" and bagName:lower() or ""

            local isQuiver = (bit and bit.band and bit.band(bagFamily, 1) > 0)
                or (lowerName:find("quiver") ~= nil)
            local isPouch = (bit and bit.band and bit.band(bagFamily, 2) > 0)
                or (lowerName:find("ammo") ~= nil or lowerName:find("pouch") ~= nil or lowerName:find("bandolier") ~= nil)
            local isSoul = (bit and bit.band and bit.band(bagFamily, 4) > 0)
                or (lowerName:find("soul") ~= nil or lowerName:find("felcloth") ~= nil)

            if bagFamily == 0 and not isQuiver and not isPouch and not isSoul then
                freeNormalSlots = freeNormalSlots + freeSlots
            end
        end
    end

    local _, playerClass = UnitClass("player")
    if not (playerClass and AMMO_CAPABLE_CLASSES[playerClass]) then
        return freeNormalSlots, false, 0, ICON_ARROW, playerClass
    end

    local rangedSlot = INVSLOT_RANGED or 18
    local rangedID = GetInventoryItemID and GetInventoryItemID("player", rangedSlot) or nil
    if type(rangedID) ~= "number" or rangedID <= 0 then
        return freeNormalSlots, false, 0, ICON_ARROW, playerClass
    end

    local hasCapableWeapon, rangedUsesBullets = ClassifyCapableRangedWeapon(rangedID)
    if not hasCapableWeapon then
        return freeNormalSlots, false, 0, ICON_ARROW, playerClass
    end

    local ammoSlot = INVSLOT_AMMO or 0
    local equippedAmmoID = GetInventoryItemID and GetInventoryItemID("player", ammoSlot) or nil
    if type(equippedAmmoID) ~= "number" or equippedAmmoID <= 0 then
        return freeNormalSlots, true, 0, (rangedUsesBullets and ICON_BULLET or ICON_ARROW), playerClass
    end

    local ammoCount = (GetInventoryItemCount and YRG.SafeNumber(GetInventoryItemCount("player", ammoSlot), 0)) or 0
    local ammoIcon = GetInventoryItemTexture and GetInventoryItemTexture("player", ammoSlot) or nil
    if not ammoIcon then
        ammoIcon = rangedUsesBullets and ICON_BULLET or ICON_ARROW
    end

    return freeNormalSlots, true, ammoCount, ammoIcon, playerClass
end

local function GetWarlockSoulShardCount()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "WARLOCK" then
        return false, 0
    end
    local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(SOUL_SHARD_ITEM_ID))
        or (GetItemCount and GetItemCount(SOUL_SHARD_ITEM_ID))
        or 0
    return true, YRG.SafeNumber(count, 0)
end

-- =========================================================================
-- BADGE FACTORY & WARNING HELPERS
-- =========================================================================
local function CreatePlacardBadge(parent, iconSide, defaultR, defaultG, defaultB)
    local side = (iconSide == "LEFT") and "LEFT" or "RIGHT"
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(36, 16)
    holder:EnableMouse(false)
    holder.iconSide = side
    holder.hasIcon = false
    holder.defaultColor = { defaultR or 0.92, defaultG or 0.92, defaultB or 0.92 }

    local iconBox = CreateFrame("Frame", nil, holder)
    iconBox:SetSize(16, 16)
    iconBox:SetPoint(side, holder, side, 0, 0)
    iconBox:EnableMouse(false)
    holder.iconBox = iconBox

    local bg = iconBox:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetColorTexture(0.05, 0.04, 0.03, 0.96)
    local bgMask = iconBox:CreateMaskTexture()
    bgMask:SetTexture(MASK_CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    bg:AddMaskTexture(bgMask)
    holder.bg = bg
    holder.bgMask = bgMask

    local icon = iconBox:CreateTexture(nil, "ARTWORK", nil, 0)
    icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    local iconMask = iconBox:CreateMaskTexture()
    iconMask:SetTexture(MASK_CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(iconMask)
    holder.icon = icon
    holder.iconMask = iconMask

    local ring = iconBox:CreateTexture(nil, "OVERLAY", nil, 1)
    ring:SetAllPoints(iconBox)
    local hasBagBorder = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bag-border")) ~= nil
    if hasBagBorder then
        ring:SetAtlas("bag-border")
    else
        ring:SetTexture(TEX_FALLBACK_RING)
        ring:SetTexCoord(0.055, 0.555, 0.062, 0.562)
    end
    ring:SetVertexColor(1.0, 0.88, 0.50, 1.0)
    holder.ring = ring
    holder.useBagAtlas = hasBagBorder

    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint(side, iconBox, (side == "LEFT") and "RIGHT" or "LEFT", (side == "LEFT") and 3 or -3, 0)
    text:SetJustifyH(side)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetTextColor(holder.defaultColor[1], holder.defaultColor[2], holder.defaultColor[3], 1.0)
    holder.text = text

    local ag = text:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local aOut = ag:CreateAnimation("Alpha")
    aOut:SetFromAlpha(1.0)
    aOut:SetToAlpha(0.22)
    aOut:SetDuration(0.45)
    aOut:SetOrder(1)
    local aIn = ag:CreateAnimation("Alpha")
    aIn:SetFromAlpha(0.22)
    aIn:SetToAlpha(1.0)
    aIn:SetDuration(0.45)
    aIn:SetOrder(2)
    holder.flashAnim = ag

    function holder:ApplyFontSize(fontSize)
        local sz = fontSize or 12
        local ringSz = math.max(16, math.floor(sz * 2.0 + 0.5))
        local innerSz = math.max(10, math.floor(sz * 1.25 + 0.5))
        local bgSz = math.max(innerSz, math.floor(ringSz * 0.68 + 0.5))
        local maskSz = math.floor(innerSz * 1.08 + 0.5)
        local ox = self.useBagAtlas and 0 or -(ringSz * 0.045)
        local oy = self.useBagAtlas and 0 or (ringSz * 0.045)

        self.iconBox:SetSize(ringSz, ringSz)
        self.bg:ClearAllPoints()
        self.bg:SetPoint("CENTER", self.iconBox, "CENTER", ox, oy)
        self.bg:SetSize(bgSz, bgSz)
        self.bgMask:ClearAllPoints()
        self.bgMask:SetPoint("CENTER", self.iconBox, "CENTER", ox, oy)
        self.bgMask:SetSize(math.max(maskSz, bgSz), math.max(maskSz, bgSz))

        self.icon:ClearAllPoints()
        self.icon:SetPoint("CENTER", self.iconBox, "CENTER", ox, oy)
        self.icon:SetSize(innerSz, innerSz)
        self.iconMask:ClearAllPoints()
        self.iconMask:SetPoint("CENTER", self.iconBox, "CENTER", ox, oy)
        self.iconMask:SetSize(maskSz, maskSz)

        self.text:SetFont(STANDARD_TEXT_FONT, sz, "OUTLINE")
        self.text:ClearAllPoints()
        local textW = math.max(YRG.SafeNumber(self.text:GetStringWidth(), 0), 8)
        if self.hasIcon then
            self.iconBox:Show()
            if self.iconSide == "LEFT" then
                self.text:SetPoint("LEFT", self.iconBox, "RIGHT", 3, 0)
                self.text:SetJustifyH("LEFT")
            else
                self.text:SetPoint("RIGHT", self.iconBox, "LEFT", -3, 0)
                self.text:SetJustifyH("RIGHT")
            end
            self:SetSize(ringSz + 3 + textW, math.max(ringSz, sz))
        else
            self.iconBox:Hide()
            self.text:SetPoint(self.iconSide, self, self.iconSide, 0, 0)
            self.text:SetJustifyH(self.iconSide)
            self:SetSize(textW, math.max(sz, 10))
        end
    end

    function holder:UpdateBadge(fontSize, texIcon, valueStr, warnState)
        if texIcon then
            self.icon:SetTexture(texIcon)
            self.hasIcon = true
        else
            self.hasIcon = false
        end
        self.text:SetText(valueStr or "")

        if warnState == "critical" then
            self.text:SetTextColor(1.0, 0.20, 0.20, 1.0)
            self.ring:SetVertexColor(1.0, 0.25, 0.25, 1.0)
            if not self.flashAnim:IsPlaying() then
                self.flashAnim:Play()
            end
        elseif warnState == "warn" then
            self.text:SetTextColor(1.0, 0.58, 0.08, 1.0)
            self.ring:SetVertexColor(1.0, 0.62, 0.14, 1.0)
            if not self.flashAnim:IsPlaying() then
                self.flashAnim:Play()
            end
        else
            if self.flashAnim:IsPlaying() then
                self.flashAnim:Stop()
            end
            self.text:SetAlpha(1.0)
            self.text:SetTextColor(self.defaultColor[1], self.defaultColor[2], self.defaultColor[3], 1.0)
            self.ring:SetVertexColor(1.0, 0.88, 0.50, 1.0)
        end

        self:ApplyFontSize(fontSize)
    end

    return holder
end

local WARN_RANK = {
    normal = 0,
    warn = 1,
    critical = 2,
}

local function GetCountWarnState(count, threshold)
    if count <= 0 then
        return "critical"
    elseif threshold > 0 and count <= threshold then
        return "warn"
    end
    return "normal"
end

local function GetAmmoWarnThreshold(db, playerClass)
    if not db then return 0 end
    if playerClass == "WARRIOR" or playerClass == "ROGUE" then
        return math.max(0, YRG.SafeNumber(db.ammoWarnThresholdMelee, 25))
    end
    return math.max(0, YRG.SafeNumber(db.ammoWarnThreshold, 200))
end

local yrgRaidWarningFrame = nil

local function GetOrCreateLocalRaidWarningFrame()
    if yrgRaidWarningFrame then
        return yrgRaidWarningFrame
    end
    local ok, frame = pcall(CreateFrame, "Frame", "YRGRaidWarningFrame", UIParent, "RaidWarningFrameTemplate")
    if ok and frame then
        frame:UnregisterAllEvents()
        frame:SetFrameStrata("HIGH")
        if RaidWarningFrame then
            frame:SetPoint("TOP", RaidWarningFrame, "TOP")
        else
            frame:SetPoint("TOP", UIParent, "TOP", 0, -220)
        end
        yrgRaidWarningFrame = frame
        return frame
    end
    return nil
end

local function EmitLocalRaidWarning(msg, isCritical)
    if not msg or msg == "" then return end
    local color = isCritical
        and { r = 1.0, g = 0.16, b = 0.16 }
        or  { r = 1.0, g = 0.56, b = 0.10 }
    local rwFrame = GetOrCreateLocalRaidWarningFrame()
    if rwFrame and type(rwFrame.AddMessage) == "function" then
        pcall(rwFrame.AddMessage, rwFrame, msg, color, 4.0)
    elseif type(RaidNotice_AddMessage) == "function" and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, color, 4.0)
    elseif UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, color.r, color.g, color.b, 1.0)
    end
end

function InfoPlacard:CheckRaidWarningTransition(stateKey, newState, warnMsg, critMsg)
    local prevState = self[stateKey]
    if prevState == nil then
        self[stateKey] = newState
        return
    end
    local prevRank = WARN_RANK[prevState] or 0
    local newRank = WARN_RANK[newState] or 0
    if newRank > prevRank then
        if newState == "warn" then
            EmitLocalRaidWarning(warnMsg, false)
        elseif newState == "critical" then
            EmitLocalRaidWarning(critMsg, true)
        end
    end
    self[stateKey] = newState
end

local function StopBadgeFlash(badge)
    if badge and badge.flashAnim and badge.flashAnim:IsPlaying() then
        badge.flashAnim:Stop()
    end
    if badge and badge.text then
        badge.text:SetAlpha(1.0)
    end
end

-- =========================================================================
-- TOOLTIP & SESSION CONTROL
-- =========================================================================
local function AppendKillPaceLines(remXP)
    local estKills, avgXP, avgInterval, estSeconds = GetKillPaceMetrics(remXP)
    if estKills and avgXP then
        GameTooltip:AddDoubleLine("Est. Kills to Level (Last 10):", string.format("%d (Avg %d XP/kill)", estKills, math.floor(avgXP)), 0.7, 0.9, 1.0, 1, 1, 1)
    end
    if estSeconds then
        local paceStr = avgInterval and string.format("%s (%.1fs/kill)", FormatTimeEstimate(estSeconds), avgInterval) or FormatTimeEstimate(estSeconds)
        GameTooltip:AddDoubleLine("Est. Time to Level:", paceStr, 0.7, 0.9, 1.0, 1, 1, 1)
    end
end

local function ShowInfoTooltip(ownerFrame)
    local curXP = YRG.SafeNumber(UnitXP("player"), 0)
    local maxXP = math.max(YRG.SafeNumber(UnitXPMax("player"), 1), 1)
    local remXP = math.max(maxXP - curXP, 0)

    GameTooltip:SetOwner(ownerFrame, "ANCHOR_BOTTOM")
    GameTooltip:SetText("YRG Dynamic Info Placard", 1.0, 0.82, 0.0)
    if C_Map and C_Map.GetPlayerMapPosition then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local pos = C_Map.GetPlayerMapPosition(mapID, "player")
            if pos and pos.x and pos.y then
                GameTooltip:AddDoubleLine("Coordinates:", string.format("%.1f, %.1f", pos.x * 100, pos.y * 100), 0.7, 0.7, 0.7, 1, 1, 1)
            end
        end
    end

    local freeSlots, hasAmmoSource, totalAmmo = GetInventoryAndAmmoStatus()
    GameTooltip:AddDoubleLine("Free Inventory Slots:", tostring(freeSlots), 0.8, 0.8, 0.8, 1, 1, 1)
    if hasAmmoSource then
        GameTooltip:AddDoubleLine("Ammo Remaining:", tostring(totalAmmo), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local isWarlock, shardCount = GetWarlockSoulShardCount()
    if isWarlock then
        GameTooltip:AddDoubleLine("Soul Shards:", tostring(shardCount), 0.75, 0.5, 1.0, 1, 1, 1)
    end

    AppendKillPaceLines(remXP)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-Click: Open Dynamic Info Placard Settings", 0.65, 0.65, 0.65)
    GameTooltip:AddLine("Right-Click: Reset Kill Pace Trackers", 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

function InfoPlacard:SyncXPBaseline(clearPending)
    self.lastKnownXP = YRG.SafeNumber(UnitXP("player"), 0)
    self.lastMaxXP = math.max(YRG.SafeNumber(UnitXPMax("player"), 1), 1)
    if clearPending then
        self._pendingXPUpdate = nil
        self._pendingSecretCombatAt = nil
        self._questTurnInUntil = nil
    end
end

function InfoPlacard:ResetSessionTrackers()
    sessionKillsData = {}
    windowStartTime = nil
    lastCombatEnd = nil
    inCombatState = (type(InCombatLockdown) == "function" and InCombatLockdown()) and true or false
    activeCombatStart = inCombatState and GetTime() or nil
    self:SyncXPBaseline(true)
    self:UpdateInfo()
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100YRG:|r Session Kills & Time-to-Level trackers have been reset.")
    end
end

local function OnInfoPlacardMouseUp(frame, button)
    if button == "LeftButton" then
        YRG:OpenSettings("DynamicInfoPlacard")
    elseif button == "RightButton" then
        InfoPlacard:ResetSessionTrackers()
        if GameTooltip and GameTooltip:IsOwned(frame) then
            ShowInfoTooltip(frame)
        end
    end
end

-- =========================================================================
-- FRAME CREATION, LAYOUT & UPDATES
-- =========================================================================
function InfoPlacard:EnsureFrames()
    if self.infoFrame then return end

    local mui = GetMinimapUI()
    local parent = MinimapCluster or Minimap or UIParent
    local infoFrame = CreateFrame("Frame", "YRGMinimapInfoPlacard", parent, "BackdropTemplate")
    local bestStrata = (parent.GetFrameStrata and parent:GetFrameStrata()) or "MEDIUM"
    local baseLvl = (parent.GetFrameLevel and parent:GetFrameLevel()) or 1
    if type(mui.GetMinimapOverlayBaseLayer) == "function" then
        bestStrata, baseLvl = mui.GetMinimapOverlayBaseLayer()
    end
    infoFrame:SetFrameStrata(bestStrata)
    infoFrame:SetFrameLevel(baseLvl + 6)
    infoFrame:EnableMouse(true)
    infoFrame:SetScript("OnEnter", ShowInfoTooltip)
    infoFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    infoFrame:SetScript("OnMouseUp", OnInfoPlacardMouseUp)
    infoFrame:Hide()
    self.infoFrame = infoFrame
    mui.infoFrame = infoFrame

    local rowDivider = infoFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    rowDivider:SetHeight(1)
    rowDivider:SetColorTexture(0.65, 0.52, 0.25, 0.60)
    rowDivider:Hide()
    self.rowDivider = rowDivider

    self.killBadge = CreatePlacardBadge(infoFrame, "RIGHT", 1.00, 0.84, 0.35)
    self.coordBadge = CreatePlacardBadge(infoFrame, "LEFT", 0.90, 0.90, 0.90)
    self.timeBadge = CreatePlacardBadge(infoFrame, "LEFT", 1.00, 0.84, 0.35)
    self.bagSlotsBadge = CreatePlacardBadge(infoFrame, "RIGHT", 0.92, 0.92, 0.92)
    self.arrowsBadge = CreatePlacardBadge(infoFrame, "RIGHT", 0.92, 0.92, 0.92)
    self.shardsBadge = CreatePlacardBadge(infoFrame, "RIGHT", 0.84, 0.58, 1.00)
end

function InfoPlacard:LayoutPlacard()
    if not self.infoFrame then return end
    local db = YRG:GetModuleDB("DynamicInfoPlacard")
    local mui = GetMinimapUI()

    if not db or not db.enabled then
        self.infoFrame:Hide()
        HandleBuiltInCoordinates(false)
        if type(mui.UpdateEditModeSelection) == "function" then
            mui.UpdateEditModeSelection()
        end
        return
    end

    if type(mui.ApplyHeaderNineSliceStyle) == "function" then
        mui.ApplyHeaderNineSliceStyle(self.infoFrame)
    end

    local row1TSize = YRG.SafeNumber(db.row1TextSize or db.textSize, 13)
    local row2TSize = YRG.SafeNumber(db.row2TextSize or db.textSize, 14)
    local pad = db.cellPadding or 9
    local userOffsetY = YRG.SafeNumber(db.infoPlacardOffsetY, -1)
    local fixedWidth = YRG.SafeNumber(db.infoPlacardWidth, 254)
    local dividerAlpha = math.max(0, math.min(1, (YRG.SafeNumber(db.rowDividerOpacityPct, 15)) / 100.0))
    local extraRowPad = math.max(0, YRG.SafeNumber(db.rowExtraPadding, 6))

    local rowBadges = {
        { self.coordBadge, row1TSize },
        { self.bagSlotsBadge, row1TSize },
        { self.arrowsBadge, row1TSize },
        { self.shardsBadge, row1TSize },
        { self.timeBadge, row2TSize },
        { self.killBadge, row2TSize },
    }
    for _, entry in ipairs(rowBadges) do
        local badge, sz = entry[1], entry[2]
        if badge then
            badge:ApplyFontSize(sz)
            badge:ClearAllPoints()
            badge:Hide()
        end
    end
    if self.rowDivider then
        self.rowDivider:ClearAllPoints()
        self.rowDivider:Hide()
    end

    local row1LeftMode = GetRow1LeftMode(db)
    local hasRow1Col1 = (row1LeftMode ~= "none" and self.coordBadge) and true or false

    local activeRow1Col2 = {}
    if db.showBagSlots ~= false and self.bagSlotsBadge then
        table.insert(activeRow1Col2, self.bagSlotsBadge)
    end
    if db.showArrowsRemaining ~= false and self._hasArrowsEquipped and self.arrowsBadge then
        table.insert(activeRow1Col2, self.arrowsBadge)
    end
    if db.showSoulShards ~= false and self._isWarlock and self.shardsBadge then
        table.insert(activeRow1Col2, self.shardsBadge)
    end

    local hasRow2 = (db.showFarmingRow ~= false) and ((self.timeBadge or self.killBadge) and true or false)
    local hasRow1 = hasRow1Col1 or (#activeRow1Col2 > 0)

    if not hasRow1 and not hasRow2 then
        self.infoFrame:Hide()
        HandleBuiltInCoordinates(false)
        if type(mui.SyncHeaderAndEditMode) == "function" then
            mui.SyncHeaderAndEditMode()
        end
        return
    end

    HandleBuiltInCoordinates(row1LeftMode == "coords")

    local minInfoW = self.infoFrame._yrgNineSliceMinW or 44
    local minInfoH = self.infoFrame._yrgNineSliceMinH or 20
    local sidePad = pad + 4

    local badgeGap = math.max(6, math.floor(pad * 0.75 + 0.5))
    local finalInfoW = math.max(fixedWidth, minInfoW, 44)

    local row1HasRing = (hasRow1Col1 and row1LeftMode == "coords") or (#activeRow1Col2 > 0)
    local row1VisualH = row1HasRing and math.max(row1TSize, math.floor(row1TSize * 1.75 + 0.5)) or row1TSize
    local row2VisualH = math.max(row2TSize, math.floor(row2TSize * 1.75 + 0.5))
    local baseRowGap = math.max(5, math.floor(pad * 0.5 + 0.5))
    local totalRowSep = baseRowGap + extraRowPad
    local totalHeight = (hasRow1 and hasRow2)
        and (row1VisualH + row2VisualH + totalRowSep + (pad * 2) + 2)
        or ((hasRow1 and row1VisualH or row2VisualH) + (pad * 2) + 2)
    local finalInfoH = math.max(totalHeight, minInfoH)

    local row1Y = (hasRow1 and hasRow2) and ((row2VisualH + totalRowSep) * 0.5) or 0
    local row2Y = (hasRow1 and hasRow2) and -((row1VisualH + totalRowSep) * 0.5) or 0
    local dividerY = (hasRow1 and hasRow2) and ((row2VisualH - row1VisualH) * 0.5) or 0

    if hasRow1 and hasRow2 and self.rowDivider and dividerAlpha > 0 then
        local divInset = math.max(8, math.floor(sidePad * 0.6))
        self.rowDivider:SetColorTexture(0.65, 0.52, 0.25, dividerAlpha)
        self.rowDivider:SetPoint("LEFT", self.infoFrame, "LEFT", divInset, dividerY)
        self.rowDivider:SetPoint("RIGHT", self.infoFrame, "RIGHT", -divInset, dividerY)
        self.rowDivider:Show()
    end

    if hasRow1Col1 then
        self.coordBadge:SetPoint("LEFT", self.infoFrame, "LEFT", sidePad, row1Y)
        self.coordBadge:Show()
    end

    if #activeRow1Col2 > 0 then
        local prevBadge = nil
        for idx, badge in ipairs(activeRow1Col2) do
            badge:Show()
            if idx == 1 then
                badge:SetPoint("RIGHT", self.infoFrame, "RIGHT", -sidePad, row1Y)
            else
                badge:SetPoint("RIGHT", prevBadge, "LEFT", -badgeGap, 0)
            end
            prevBadge = badge
        end
    end

    if hasRow2 then
        if self.timeBadge then
            self.timeBadge:SetPoint("LEFT", self.infoFrame, "LEFT", sidePad, row2Y)
            self.timeBadge:Show()
        end
        if self.killBadge then
            self.killBadge:SetPoint("RIGHT", self.infoFrame, "RIGHT", -sidePad, row2Y)
            self.killBadge:Show()
        end
    end

    local infoScale = mui.SafeRegionScale(self.infoFrame, 1)
    local function AnchorToMinimapOrExp(targetLoc, expAnchor)
        if expAnchor then
            local expScale = mui.SafeRegionScale(expAnchor.container, infoScale)
            local ratio = (infoScale > 0) and (expScale / infoScale) or 1
            if targetLoc == "TOP" then
                self.infoFrame:SetPoint("BOTTOM", expAnchor.container, "TOP", 0, (expAnchor.ringTopRimY * ratio) + 2 + userOffsetY)
            else
                self.infoFrame:SetPoint("TOP", expAnchor.expFrame, "BOTTOM", 0, 3 + userOffsetY)
            end
        elseif targetLoc == "TOP" then
            self.infoFrame:SetPoint("BOTTOM", Minimap, "TOP", 0, 4 + userOffsetY)
        else
            self.infoFrame:SetPoint("TOP", Minimap, "BOTTOM", 0, -4 + userOffsetY)
        end
    end

    self.infoFrame:SetSize(finalInfoW, finalInfoH)
    self.infoFrame:ClearAllPoints()

    local loc = (db.placardLocation == "TOP") and "TOP" or "BOTTOM"
    local anchorMode = (db.placardAnchorPoint == "MINIMAP") and "MINIMAP" or "ZONE_TITLE"
    local expInfo = (type(mui.GetExpAnchorInfo) == "function") and mui.GetExpAnchorInfo() or nil

    if anchorMode == "ZONE_TITLE" then
        local zoneTitle = (type(mui.GetZoneTitleAnchorFrame) == "function") and mui.GetZoneTitleAnchorFrame() or nil
        if zoneTitle then
            local zScale = mui.SafeRegionScale(zoneTitle, 1)
            local mScale = mui.SafeRegionScale(Minimap, 1)
            if loc == "TOP" then
                local zTop = (type(mui.SafeRegionTop) == "function") and mui.SafeRegionTop(zoneTitle) or nil
                local mTop = (type(mui.SafeRegionTop) == "function") and mui.SafeRegionTop(Minimap) or nil
                if zTop and mTop and infoScale > 0 then
                    local yRelMapTop = ((zTop * zScale) - (mTop * mScale)) / infoScale + userOffsetY
                    self.infoFrame:SetPoint("BOTTOM", Minimap, "TOP", 0, yRelMapTop)
                else
                    self.infoFrame:SetPoint("BOTTOM", zoneTitle, "TOP", 0, userOffsetY)
                end
            else
                local zBot = (type(mui.SafeRegionBottom) == "function") and mui.SafeRegionBottom(zoneTitle) or nil
                local mBot = (type(mui.SafeRegionBottom) == "function") and mui.SafeRegionBottom(Minimap) or nil
                if zBot and mBot and infoScale > 0 then
                    local yRelMapBot = ((zBot * zScale) - (mBot * mScale)) / infoScale + userOffsetY
                    self.infoFrame:SetPoint("TOP", Minimap, "BOTTOM", 0, yRelMapBot)
                else
                    self.infoFrame:SetPoint("TOP", zoneTitle, "BOTTOM", 0, userOffsetY)
                end
            end
        else
            AnchorToMinimapOrExp(loc, expInfo)
        end
    else
        AnchorToMinimapOrExp(loc, expInfo)
    end

    self.infoFrame:Show()
    if type(mui.SyncHeaderAndEditMode) == "function" then
        mui.SyncHeaderAndEditMode()
    end
end

function InfoPlacard:UpdateInfo()
    if not self.infoFrame then return end
    local db = YRG:GetModuleDB("DynamicInfoPlacard")
    if not db or not db.enabled then
        self.infoFrame:Hide()
        HandleBuiltInCoordinates(false)
        return
    end

    local curXP = YRG.SafeNumber(UnitXP("player"), 0)
    local maxXP = math.max(YRG.SafeNumber(UnitXPMax("player"), 1), 1)
    local remXP = math.max(maxXP - curXP, 0)

    local row1TSize = YRG.SafeNumber(db.row1TextSize or db.textSize, 13)
    local row2TSize = YRG.SafeNumber(db.row2TextSize or db.textSize, 14)
    local row1IconSz = math.max(10, row1TSize)

    if db.showFarmingRow ~= false then
        local estKills, _, _, estSeconds = GetKillPaceMetrics(remXP)
        if self.killBadge then
            local killsStr = estKills and tostring(estKills) or "--"
            self.killBadge:UpdateBadge(row2TSize, ICON_SKULL, killsStr, "normal")
        end
        if self.timeBadge then
            local timeStr = FormatTimeEstimate(estSeconds)
            self.timeBadge:UpdateBadge(row2TSize, ICON_WATCH, timeStr, "normal")
        end
    end

    local row1LeftMode = GetRow1LeftMode(db)
    if row1LeftMode == "coords" and self.coordBadge then
        local coordStr = "--, --"
        if C_Map and C_Map.GetPlayerMapPosition then
            local mapID = C_Map.GetBestMapForUnit("player")
            if mapID then
                local pos = C_Map.GetPlayerMapPosition(mapID, "player")
                if pos and pos.x and pos.y then
                    coordStr = string.format("%.1f, %.1f", pos.x * 100, pos.y * 100)
                end
            end
        end
        self.coordBadge:UpdateBadge(row1TSize, ICON_MAP, coordStr, "normal")
    elseif row1LeftMode == "gold" and self.coordBadge then
        local copper = (type(GetMoney) == "function") and GetMoney() or 0
        self.coordBadge:UpdateBadge(row1TSize, nil, FormatPlacardMoneyText(copper, row1IconSz), "normal")
    end

    local tSize = row1TSize
    local freeSlots, hasAmmoSource, totalAmmoCount, ammoDisplayIcon, playerClass = GetInventoryAndAmmoStatus()

    if db.showBagSlots ~= false and self.bagSlotsBadge then
        local bagThresh = math.max(0, YRG.SafeNumber(db.bagWarnThreshold, 5))
        local bagState = GetCountWarnState(freeSlots, bagThresh)
        self.bagSlotsBadge:UpdateBadge(tSize, ICON_BAG, tostring(freeSlots), bagState)
        if db.bagRaidWarnings then
            self:CheckRaidWarningTransition(
                "_lastBagWarnState",
                bagState,
                string.format("Low Bag Space! (%d free slot%s left)", freeSlots, freeSlots == 1 and "" or "s"),
                "Bags Full! No space left!"
            )
        else
            self._lastBagWarnState = nil
        end
    else
        StopBadgeFlash(self.bagSlotsBadge)
        self._lastBagWarnState = nil
    end

    self._hasArrowsEquipped = hasAmmoSource and true or false
    if db.showArrowsRemaining ~= false and hasAmmoSource and self.arrowsBadge then
        local ammoThresh = GetAmmoWarnThreshold(db, playerClass)
        local ammoState = GetCountWarnState(totalAmmoCount, ammoThresh)
        self.arrowsBadge:UpdateBadge(tSize, ammoDisplayIcon or ICON_ARROW, tostring(totalAmmoCount), ammoState)
        if db.bagRaidWarnings then
            self:CheckRaidWarningTransition(
                "_lastAmmoWarnState",
                ammoState,
                string.format("Low Ammo! (%d remaining)", totalAmmoCount),
                "Out of Ammo! No arrows or bullets left!"
            )
        else
            self._lastAmmoWarnState = nil
        end
    else
        StopBadgeFlash(self.arrowsBadge)
        self._lastAmmoWarnState = nil
    end

    local isWarlock, shardCount = GetWarlockSoulShardCount()
    self._isWarlock = isWarlock and true or false
    if db.showSoulShards ~= false and isWarlock and self.shardsBadge then
        self.shardsBadge:UpdateBadge(tSize, ICON_SHARD, tostring(shardCount), "normal")
    else
        StopBadgeFlash(self.shardsBadge)
    end

    self:LayoutPlacard()
end

-- =========================================================================
-- MODULE LIFECYCLE & SAVEDVARIABLES MIGRATION
-- =========================================================================
local MIGRATED_KEYS = {
    "infoPlacardOffsetY", "infoPlacardWidth",
    "rowDividerOpacityPct", "rowExtraPadding", "row1LeftMode",
    "showBagSlots", "showArrowsRemaining", "showSoulShards",
    "showFarmingRow", "bagWarnThreshold", "ammoWarnThreshold",
    "ammoWarnThresholdMelee", "bagRaidWarnings", "cellPadding",
    "row1TextSize", "row2TextSize",
}

local function MigrateLegacyExpTrackerPlacardSettings(db)
    if db._migratedFromExpTrackerV1 then return end
    db._migratedFromExpTrackerV1 = true

    local expDB = YRGDB and YRGDB.modules and YRGDB.modules.MinimapExpTracker
    if type(expDB) ~= "table" then return end

    if expDB.showInfoPlacard == false then
        db.enabled = false
    end
    for _, key in ipairs(MIGRATED_KEYS) do
        if expDB[key] ~= nil then
            db[key] = expDB[key]
        end
    end
    if expDB.row1LeftMode == nil and expDB.showCoordinates == false then
        db.row1LeftMode = "none"
    end
    if expDB.infoPlacardExtraWidth ~= nil and expDB.infoPlacardWidth == nil then
        db.infoPlacardWidth = math.min(360, math.max(100, 200 + YRG.SafeNumber(expDB.infoPlacardExtraWidth, 0)))
    end
    if expDB.textSize ~= nil then
        if expDB.row1TextSize == nil then
            db.row1TextSize = tonumber(expDB.textSize) or 12
        end
        if expDB.row2TextSize == nil then
            db.row2TextSize = tonumber(expDB.textSize) or 12
        end
    end

    -- Clean up legacy Info Placard keys from MinimapExpTracker SavedVariables
    for _, key in ipairs(MIGRATED_KEYS) do
        expDB[key] = nil
    end
    expDB.followMapOrientation = nil
    expDB.showInfoPlacard = nil
    expDB.showCoordinates = nil
    expDB.infoPlacardExtraWidth = nil
    expDB.textSize = nil
    expDB.showEstimatedTime = nil
    expDB.showEstimatedKills = nil
end

function InfoPlacard:OnInitialize(db)
    MigrateLegacyExpTrackerPlacardSettings(db)

    db.followMapOrientation = nil
    if db.placardLocation ~= "TOP" and db.placardLocation ~= "BOTTOM" then
        db.placardLocation = "BOTTOM"
    end
    if db.placardAnchorPoint ~= "ZONE_TITLE" and db.placardAnchorPoint ~= "MINIMAP" then
        db.placardAnchorPoint = "ZONE_TITLE"
    end
    if db.row1LeftMode ~= "coords" and db.row1LeftMode ~= "gold" and db.row1LeftMode ~= "none" then
        db.row1LeftMode = "gold"
    end
    if db.row1TextSize == nil then db.row1TextSize = 13 end
    if db.row2TextSize == nil then db.row2TextSize = 14 end

    self:EnsureFrames()
    self.eventFrame = CreateFrame("Frame")
    self.coordTimer = 0
    self:SyncXPBaseline(true)

    local mui = GetMinimapUI()
    mui.onInfoPlacardLayout = function()
        local modDB = YRG:GetModuleDB("DynamicInfoPlacard")
        if modDB and modDB.enabled then
            InfoPlacard:LayoutPlacard()
        end
    end
    mui.AppendKillPaceTooltipLines = function(remXP)
        local modDB = YRG:GetModuleDB("DynamicInfoPlacard")
        if modDB and modDB.enabled then
            AppendKillPaceLines(remXP)
        end
    end
    mui.ResetSessionTrackers = function()
        InfoPlacard:ResetSessionTrackers()
    end

    self.eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "PLAYER_REGEN_DISABLED" then
            local now = GetTime()
            if not inCombatState then
                inCombatState = true
                activeCombatStart = now
            end
        elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
            -- Track only creature kill XP from combat XP messages so quest turn-ins and exploration do not skew pace
            local now = GetTime()
            if YRG.IsSecret and YRG.IsSecret(arg1) then
                if self._pendingXPUpdate and (now - self._pendingXPUpdate.t) <= 0.5 then
                    local pendingXP = self._pendingXPUpdate.xp
                    self._pendingXPUpdate = nil
                    if not IsQuestXPBlocked(self._questTurnInUntil, now) then
                        RecordMobKillXP(pendingXP, now)
                    end
                elseif not IsQuestXPBlocked(self._questTurnInUntil, now) then
                    self._pendingSecretCombatAt = now
                end
            else
                local parsedXP = ParseCombatKillXP(arg1)
                self._pendingXPUpdate = nil
                self._pendingSecretCombatAt = nil
                if parsedXP and parsedXP > 0 and not IsQuestXPBlocked(self._questTurnInUntil, now) then
                    RecordMobKillXP(parsedXP, now)
                end
            end
            self:UpdateInfo()
        elseif event == "QUEST_TURNED_IN" then
            local now = GetTime()
            self._questTurnInUntil = now + 2.5
            self._pendingXPUpdate = nil
            self._pendingSecretCombatAt = nil
            self:SyncXPBaseline(false)
            self:UpdateInfo()
        elseif event == "PLAYER_XP_UPDATE" then
            local now = GetTime()
            local newXP = YRG.SafeNumber(UnitXP("player"), 0)
            local newMaxXP = math.max(YRG.SafeNumber(UnitXPMax("player"), 1), 1)
            local diff = 0
            if self.lastKnownXP then
                if newXP >= self.lastKnownXP then
                    diff = newXP - self.lastKnownXP
                elseif self.lastMaxXP and self.lastMaxXP > self.lastKnownXP then
                    diff = (self.lastMaxXP - self.lastKnownXP) + newXP
                end
            end
            self.lastKnownXP = newXP
            self.lastMaxXP = newMaxXP
            if diff > 0 and not IsQuestXPBlocked(self._questTurnInUntil, now) then
                if self._pendingSecretCombatAt and (now - self._pendingSecretCombatAt) <= 0.5 then
                    self._pendingSecretCombatAt = nil
                    RecordMobKillXP(diff, now)
                else
                    -- Stash passively in case CHAT_MSG_COMBAT_XP_GAIN arrives right after with a secret payload (instances)
                    self._pendingXPUpdate = { xp = diff, t = now }
                end
            end
            self:UpdateInfo()
        elseif event == "UNIT_INVENTORY_CHANGED" then
            if arg1 == "player" then
                self:UpdateInfo()
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombatState = false
            lastCombatEnd = GetTime()
            self:LayoutPlacard()
        elseif event == "PLAYER_ENTERING_WORLD" then
            inCombatState = (type(InCombatLockdown) == "function" and InCombatLockdown()) and true or false
            if inCombatState then
                activeCombatStart = GetTime()
            end
            self:SyncXPBaseline(true)
            self:UpdateInfo()
        else
            self:UpdateInfo()
        end
    end)
end

function InfoPlacard:OnEnable(db)
    self:EnsureFrames()
    inCombatState = (type(InCombatLockdown) == "function" and InCombatLockdown()) and true or false
    if inCombatState and not activeCombatStart then
        activeCombatStart = GetTime()
    end
    self:SyncXPBaseline(true)
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "CHAT_MSG_COMBAT_XP_GAIN")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "QUEST_TURNED_IN")
    self.eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
    self.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    self.eventFrame:RegisterEvent("PLAYER_MONEY")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    self.eventFrame:SetScript("OnUpdate", function(frame, elapsed)
        frame.coordTimer = (frame.coordTimer or 0) + elapsed
        if frame.coordTimer >= 0.5 then
            frame.coordTimer = 0
            local modDB = YRG:GetModuleDB("DynamicInfoPlacard")
            if modDB and modDB.enabled then
                InfoPlacard:UpdateInfo()
            end
        end
    end)

    self:UpdateInfo()
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            local modDB = YRG:GetModuleDB("DynamicInfoPlacard")
            if modDB and modDB.enabled then
                self:LayoutPlacard()
            end
        end)
    end
end

function InfoPlacard:OnDisable(db)
    self._lastBagWarnState = nil
    self._lastAmmoWarnState = nil
    self._pendingXPUpdate = nil
    self._pendingUnparsedCombatAt = nil
    self._lastQuestTurnIn = nil
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame:SetScript("OnUpdate", nil)
    end
    if self.infoFrame then
        self.infoFrame:Hide()
    end
    HandleBuiltInCoordinates(false)
    local mui = GetMinimapUI()
    if type(mui.SyncHeaderAndEditMode) == "function" then
        mui.SyncHeaderAndEditMode()
    end
end

-- =========================================================================
-- SETTINGS PANEL UI
-- =========================================================================
function InfoPlacard:BuildConfigUI(ctx, db)
    local function GetDB()
        return YRG:GetModuleDB("DynamicInfoPlacard")
    end

    local function AddPlacardSlider(key, name, tooltip, minVal, maxVal, step, defaultVal, formatFn)
        ctx:AddSlider({
            key = key,
            name = name,
            tooltip = tooltip,
            min = minVal, max = maxVal, step = step, defaultValue = defaultVal,
            format = formatFn,
            get = function()
                local mdb = GetDB()
                if mdb and mdb[key] ~= nil then
                    return mdb[key]
                end
                return defaultVal
            end,
            set = function(val)
                local mdb = GetDB()
                if mdb then mdb[key] = math.floor(val + 0.5) end
                self:UpdateInfo()
            end,
        })
    end

    -- =========================================================================
    -- SECTION 1: Placard Layout & Styling
    -- =========================================================================
    ctx:AddHeader(
        "1. Placard Layout & Styling",
        "Controls placement, anchor point, sizing, spacing, and row divider styling for the Dynamic Info Placard."
    )

    ctx:AddDropdown({
        key = "placardLocation",
        name = "Location",
        tooltip = "Places the Dynamic Info Placard above (Top) or below (Bottom) the selected Anchor Point.",
        defaultValue = "BOTTOM",
        options = PLACARD_LOCATION_OPTIONS,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.placardLocation == "TOP") and "TOP" or "BOTTOM"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.placardLocation = (val == "TOP") and "TOP" or "BOTTOM"
            end
            self:UpdateInfo()
        end,
    })

    ctx:AddDropdown({
        key = "placardAnchorPoint",
        name = "Anchor Point",
        tooltip = "Attaches the Dynamic Info Placard to the Zone Title bar or the Minimap (or EXP Badge when active). Selecting Zone Title automatically centers the Zone Title and extends it to match your Info Placard width.",
        defaultValue = "ZONE_TITLE",
        options = PLACARD_ANCHOR_OPTIONS,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.placardAnchorPoint == "MINIMAP") and "MINIMAP" or "ZONE_TITLE"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.placardAnchorPoint = (val == "MINIMAP") and "MINIMAP" or "ZONE_TITLE"
            end
            self:UpdateInfo()
        end,
    })

    AddPlacardSlider("infoPlacardOffsetY", "Vertical Offset from Anchor", "Vertical offset in pixels from the selected Anchor Point to align placard placement.", -30, 30, 1, -1, function(v) return string.format("%d px", v) end)
    AddPlacardSlider("infoPlacardWidth", "Info Placard Width", "Fixed width in pixels of the Dynamic Info Placard.", 100, 360, 2, 254, function(v) return string.format("%d px", v) end)
    AddPlacardSlider("cellPadding", "Info Cell Padding", "Inner padding around placard content in pixels.", 2, 20, 1, 9, function(v) return string.format("%d px", v) end)
    AddPlacardSlider("rowDividerOpacityPct", "Row Divider Line Opacity (%)", "Opacity of the horizontal divider line between Row 1 and Row 2.", 0, 100, 5, 15, function(v) return string.format("%d%%", v) end)
    AddPlacardSlider("rowExtraPadding", "Row 2 Vertical Padding", "Extra spacing between Row 1 and Row 2 inside the Dynamic Info Placard.", 0, 20, 1, 6, function(v) return string.format("%d px", v) end)

    -- =========================================================================
    -- SECTION 2: Row 1 — Trackers & Bags
    -- =========================================================================
    ctx:AddHeader("2. Row 1 — Trackers & Bags")

    AddPlacardSlider("row1TextSize", "Row 1 Font Size", "Font and icon size used for Row 1 (Coordinates/Gold and Bag/Ammo trackers).", 8, 18, 1, 13, function(v) return string.format("%d px", v) end)

    ctx:AddDropdown({
        key = "row1LeftMode",
        name = "Row 1 Left Display",
        tooltip = "Choose what appears on the left side of Row 1: Current Gold (default, with gold/silver/copper icons), Coordinates (hides built-in minimap coordinates), or None.",
        defaultValue = "gold",
        options = ROW1_LEFT_OPTIONS,
        get = function()
            return GetRow1LeftMode(GetDB())
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.row1LeftMode = (val == "coords" or val == "none") and val or "gold"
            end
            self:UpdateInfo()
        end,
    })

    ctx:AddCheckbox({
        key = "showBagSlots",
        name = "Show Inventory Free Slots",
        tooltip = "Displays remaining free general bag slots far-right in Row 1 Column 2.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showBagSlots ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showBagSlots = val end
            self:UpdateInfo()
        end,
    })

    ctx:AddCheckbox({
        key = "showArrowsRemaining",
        name = "Show Arrows / Ammo Remaining",
        tooltip = "Displays equipped arrows or bullets expanding left in Row 1 Column 2 for Hunters, Warriors, and Rogues with a Bow, Crossbow, or Gun equipped.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showArrowsRemaining ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showArrowsRemaining = val end
            self:UpdateInfo()
        end,
    })

    ctx:AddCheckbox({
        key = "showSoulShards",
        name = "Show Soul Shards (Warlock)",
        tooltip = "Displays Soul Shards expanding left in Row 1 Column 2 (Warlock only).",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showSoulShards ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showSoulShards = val end
            self:UpdateInfo()
        end,
    })

    local function FormatCountThreshold(v)
        return (v <= 0) and "Off" or string.format("%d", v)
    end

    AddPlacardSlider("bagWarnThreshold", "Inventory Low Warning Threshold", "Free general bag slots threshold to trigger low-space warning highlight / raid warning (0 = Off).", 0, 20, 1, 5, FormatCountThreshold)

    AddPlacardSlider("ammoWarnThreshold", "Ammo Low Warning (Hunter)", "Equipped arrow/bullet count threshold for Hunters to trigger low-ammo warning highlight / raid warning (0 = Off).", 0, 1000, 10, 200, FormatCountThreshold)

    AddPlacardSlider("ammoWarnThresholdMelee", "Ammo Low Warning (Rogue / Warrior)", "Equipped arrow/bullet count threshold for Rogues and Warriors (typically 1-2 stacks) to trigger low-ammo warning highlight / raid warning (0 = Off).", 0, 400, 5, 25, FormatCountThreshold)

    ctx:AddCheckbox({
        key = "bagRaidWarnings",
        name = "Include Raid Warnings (Inventory & Ammo)",
        tooltip = "Shows a local center-screen Raid Warning once when bag space or ammo drops below the low threshold (orange) or hits 0 remaining (red).",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.bagRaidWarnings) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.bagRaidWarnings = val end
            if val then
                self._lastBagWarnState = "normal"
                self._lastAmmoWarnState = "normal"
            else
                self._lastBagWarnState = nil
                self._lastAmmoWarnState = nil
            end
            self:UpdateInfo()
        end,
    })

    -- =========================================================================
    -- SECTION 3: Row 2 — Farming Data
    -- =========================================================================
    ctx:AddHeader("3. Row 2 — Farming Data")

    ctx:AddCheckbox({
        key = "showFarmingRow",
        name = "Enable Farming Data Row (Time to Level & Kills)",
        tooltip = "Displays the 2-column Row 2 farming bar (Estimated Time to Level left-justified, Estimated Mob Kills right-justified).",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showFarmingRow ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showFarmingRow = val end
            self:UpdateInfo()
        end,
    })

    AddPlacardSlider("row2TextSize", "Row 2 Font Size", "Font and icon size used for Row 2 (Estimated Time to Level and Mob Kills).", 8, 18, 1, 14, function(v) return string.format("%d px", v) end)
end

YRG:RegisterModule("DynamicInfoPlacard", InfoPlacard)
