local _, YRG = ...

-- Default exclusion list: Grey (Poor) Shoulder and Head items from levels 15-18
local DEFAULT_EXCLUSIONS = {
    -- Level 15-18 Poor (Grey) Shoulder Items
    ["Canvas Shoulderpads"] = true,
    ["Brocade Shoulderpads"] = true,
    ["Cross-Stitched Shoulderpads"] = true,
    ["Patched Leather Shoulderpads"] = true,
    ["Rawhide Shoulderpads"] = true,
    ["Tough Leather Shoulderpads"] = true,
    ["Worn Leather Shoulderpads"] = true,
    ["Laced Mail Shoulderpads"] = true,
    ["Linked Chain Shoulderpads"] = true,
    ["Rusted Chain Shoulderpads"] = true,
    ["Double Mail Shoulderpads"] = true,
    -- Level 15-18 Poor (Grey) Head Items
    ["Canvas Hat"] = true,
    ["Canvas Hood"] = true,
    ["Brocade Hat"] = true,
    ["Brocade Hood"] = true,
    ["Cross-Stitched Hat"] = true,
    ["Interlaced Cowl"] = true,
    ["Patched Leather Hat"] = true,
    ["Patched Leather Cap"] = true,
    ["Rawhide Hat"] = true,
    ["Rawhide Cap"] = true,
    ["Tough Leather Cap"] = true,
    ["Hardened Leather Helm"] = true,
    ["Laced Mail Coif"] = true,
    ["Linked Chain Coif"] = true,
    ["Rusted Chain Coif"] = true,
    ["Double Mail Coif"] = true,
}

local function CopyTable(src)
    local out = {}
    for k, v in pairs(src or {}) do
        out[k] = v
    end
    return out
end

local BetterBags = {
    name = "BetterBagsModule",
    description = "Bag automation (Auto-Sort, Auto-Open Clams, Auto-Repair, Auto-Sell Greys), Controller Mode separate bag strip, and Non-Controller Reagent Bag merge.",
    defaultEnabled = true,
    defaults = {
        enabled = true,
        controllerBagStrip = true,
        rowGap = 8,
        showDivider = true,
        bagPinAlignment = "RIGHT", -- "LEFT", "CENTER", "RIGHT"
        includeReagentBagInCombined = true,
        reagentBagTintPurple = true,
        autoSortOnOpen = true,
        autoOpenClams = true,
        autoRepair = true,
        autoRepairMaxSilver = 25, -- 0 = Unlimited, stored in silver (1..1000 = 1s..10g)
        autoSellGreys = true,
        sellExclusionList = CopyTable(DEFAULT_EXCLUSIONS),
    }
}

local controllerStripHooked = false
local gamepadBagBarHooked = false
local reagentSearchHooked = false
local autoSortHooked = false
local pending, applying = false, false
local deferredPassPending = false
local dividerFrame = nil
local divider = nil
local reagentDividerFrame = nil
local reagentDivider = nil
local reagentBagHolder = nil
local reagentSlotButtons = {}
local lastSortTime = 0

local function IsControllerUIActive()
    if InputUtil and type(InputUtil.IsGamepadUIEnabled) == "function" then
        return InputUtil.IsGamepadUIEnabled() and true or false
    end
    return false
end

local function IsFrameProtectedOrForbidden(f)
    if not f then return true end
    if type(f.IsForbidden) == "function" and f:IsForbidden() then
        return true
    end
    if type(f.IsProtected) == "function" then
        local ok, prot = pcall(f.IsProtected, f)
        if ok and prot then
            return true
        end
    end
    return false
end

local function GetReagentBagID()
    if REAGENTBAG_CONTAINER ~= nil then
        return REAGENTBAG_CONTAINER
    end
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag ~= nil then
        return Enum.BagIndex.ReagentBag
    end
    return 5
end

local nativeBagBaseY = setmetatable({}, { __mode = "k" })
local ApplyUnifiedBagLayout

local function HideDividerOverlay()
    if dividerFrame then
        dividerFrame:Hide()
    end
end

local function CollectControllerBagButtons(bar, includeHiddenReagent)
    if not bar or type(bar.GetBagButton) ~= "function" then return nil end
    local bags, seenBagIDs = {}, {}

    local function TryAdd(id, requireShown)
        if id == nil or seenBagIDs[id] then return true end
        seenBagIDs[id] = true
        local button = bar:GetBagButton(id)
        if not button then return true end
        if requireShown and type(button.IsShown) == "function" and not button:IsShown() then
            return true
        end
        if IsFrameProtectedOrForbidden(button) then return false end
        bags[#bags + 1] = button
        return true
    end

    local startBag = BACKPACK_CONTAINER or 0
    local endBag = ENDING_BAG_INDEX or 4
    for id = startBag, endBag do
        if not TryAdd(id, false) then return nil end
    end

    local reagentID = GetReagentBagID()
    if reagentID ~= nil then
        if not TryAdd(reagentID, not includeHiddenReagent) then return nil end
    end

    if KEYRING_CONTAINER then
        local showKR = (GetCVarBool and GetCVarBool("showKeyring"))
        local krBtn = bar:GetBagButton(KEYRING_CONTAINER)
        if krBtn and (showKR or (type(krBtn.IsShown) == "function" and krBtn:IsShown())) then
            if not TryAdd(KEYRING_CONTAINER, false) then return nil end
        end
    end

    return bags
end

local function ResetControllerBagButtonScales()
    if InCombatLockdown() then return end
    local bar = GamepadBagBar
    if not bar or IsFrameProtectedOrForbidden(bar) then return end
    local bags = CollectControllerBagButtons(bar, true)
    if not bags then return end
    for _, button in ipairs(bags) do
        if not IsFrameProtectedOrForbidden(button) and type(button.SetScale) == "function" then
            local curScale = YRG.SafeNumber(button.GetScale and button:GetScale(), 1)
            if math.abs(curScale - 1) >= 0.005 then
                button:SetScale(1)
            end
        end
    end
end

-- =========================================================================
-- CONTROLLER MODE EXCLUSIVE: Separate Bag Strip & Pinning
-- =========================================================================
local function ApplyControllerBagStripLayout()
    if applying then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false

    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled or db.controllerBagStrip == false then
        HideDividerOverlay()
        ResetControllerBagButtonScales()
        return
    end

    local frame, bar = ContainerFrameCombinedBags, GamepadBagBar
    if not frame or not bar or not frame:IsShown() then
        HideDividerOverlay()
        return
    end
    if not IsControllerUIActive() then
        HideDividerOverlay()
        ResetControllerBagButtonScales()
        return
    end
    if IsFrameProtectedOrForbidden(frame) or IsFrameProtectedOrForbidden(bar) then
        HideDividerOverlay()
        return
    end

    local columns = frame:GetColumns()
    if not frame.itemButtonPool or type(frame.itemButtonPool.GetTemplate) ~= "function" then
        HideDividerOverlay()
        return
    end
    local template = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(frame.itemButtonPool:GetTemplate())
    if not template or not template.width or not template.height then
        HideDividerOverlay()
        return
    end

    local anchor = frame.MoneyFrame
    if not anchor or IsFrameProtectedOrForbidden(anchor) or columns < 1 then
        HideDividerOverlay()
        return
    end

    local bags = CollectControllerBagButtons(bar, false)
    if not bags or #bags == 0 then
        HideDividerOverlay()
        return
    end

    local items = {}
    local itemW, itemH = template.width, template.height
    local maxX, minY
    local xs, ys = {}, {}
    for _, button in frame:EnumerateValidItems() do
        if IsFrameProtectedOrForbidden(button) then
            HideDividerOverlay()
            return
        end
        if type(button.IsShown) ~= "function" or button:IsShown() then
            local bag = bar:GetBagButton(button:GetBagID())
            if not bag or bag.isCollapsed ~= true then
                local point, relativeTo, relativePoint, x, y = button:GetPoint(1)
                if point ~= "BOTTOMRIGHT" or relativeTo ~= anchor
                    or relativePoint ~= "TOPRIGHT"
                    or type(x) ~= "number" or type(y) ~= "number" then
                    HideDividerOverlay()
                    return
                end
                if not maxX or x > maxX then maxX = x end
                if not minY or y < minY then minY = y end
                xs[#xs + 1] = x
                ys[#ys + 1] = y
                items[#items + 1] = { button = button, x = x, y = y }
            end
        end
    end

    -- Preserve Blizzard's native bottom offset across mode switches and repeat layout passes
    if minY and minY < 20 then
        nativeBagBaseY[frame] = minY
    end
    local baseX = (maxX and maxX <= 2) and maxX or 0
    local baseY = nativeBagBaseY[frame] or 4
    local stepX = itemW + 5
    local stepY = itemH + 5

    -- Measure actual horizontal/vertical slot spacing from live items to match native spacing cleanly
    -- Use a tight upper bound (< 1.4x button size) so inline bag header gaps never masquerade as slot spacing.
    if #xs > 1 then
        table.sort(xs, function(a, b) return a > b end)
        local minDx = nil
        for i = 2, #xs do
            local dx = xs[i - 1] - xs[i]
            if dx > itemW * 0.5 and (not minDx or dx < minDx) then
                minDx = dx
            end
        end
        if minDx and minDx < itemW * 1.4 then
            stepX = minDx
        end
    end
    if #ys > 1 then
        table.sort(ys)
        local minDy = nil
        for i = 2, #ys do
            local dy = ys[i] - ys[i - 1]
            if dy > itemH * 0.5 and (not minDy or dy < minDy) then
                minDy = dy
            end
        end
        if minDy and minDy < itemH * 1.4 then
            stepY = minDy
        end
    end

    -- Quantize Y relative to minY so sub-pixel float jitter never scrambles row ordering in table.sort
    local halfStepY = math.max(stepY * 0.5, 4)
    for _, entry in ipairs(items) do
        entry.rowKey = math.floor(((entry.y - baseY) / halfStepY) + 0.5)
    end
    table.sort(items, function(a, b)
        if a.rowKey ~= b.rowKey then return a.rowKey < b.rowKey end
        return a.x > b.x
    end)

    local gap = db.rowGap or 8
    local pinAlign = db.bagPinAlignment or "RIGHT"
    local itemRows = math.ceil(#items / columns)
    local bagRows = math.ceil(#bags / columns)
    local height = frame:CalculateHeight()
        + (itemRows + bagRows - frame:GetRows()) * stepY + gap

    applying = true
    for i, entry in ipairs(items) do
        local index = i - 1
        local tx = baseX - (index % columns) * stepX
        local ty = baseY + math.floor(index / columns) * stepY
        if math.abs(entry.x - tx) >= 0.4 or math.abs(entry.y - ty) >= 0.4 then
            entry.button:ClearAllPoints()
            entry.button:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", tx, ty)
        end
    end

    local frameStrata = (frame.GetFrameStrata and frame:GetFrameStrata()) or "MEDIUM"
    local frameLevel = math.max((frame.GetFrameLevel and frame:GetFrameLevel()) or 1, 1)
    if type(bar.SetFrameStrata) == "function" and bar.GetFrameStrata and bar:GetFrameStrata() ~= frameStrata then
        bar:SetFrameStrata(frameStrata)
    end
    if type(bar.SetFrameLevel) == "function" and bar.GetFrameLevel then
        local curBarLevel = YRG.SafeNumber(bar:GetFrameLevel(), 0)
        if curBarLevel <= frameLevel + 1 then
            bar:SetFrameLevel(frameLevel + 2)
        end
    end

    local ancScale = math.max(YRG.SafeNumber(anchor.GetEffectiveScale and anchor:GetEffectiveScale(), 1), 0.01)
    local totalBags = #bags
    for i, button in ipairs(bags) do
        local index = i - 1
        local rowIdx = math.floor(index / columns)
        local colInRow = index % columns
        local remainingAfterRowStart = totalBags - (rowIdx * columns)
        local countInRow = math.min(columns, remainingAfterRowStart)

        local colFromRight
        if pinAlign == "RIGHT" then
            local startColFromLeft = columns - countInRow
            local targetColFromLeft = startColFromLeft + colInRow
            colFromRight = columns - 1 - targetColFromLeft
        elseif pinAlign == "CENTER" then
            local startColFromLeft = (columns - countInRow) / 2
            local targetColFromLeft = startColFromLeft + colInRow
            colFromRight = columns - 1 - targetColFromLeft
        else -- "LEFT"
            colFromRight = columns - 1 - colInRow
        end

        -- Match each bag button's screen-space scale to the container (essential when 1280x800 auto-scales
        -- ContainerFrameCombinedBags smaller than GamepadBagBar so bag rects do not overlap neighbors or items).
        local rawBtnW = YRG.SafeNumber(button.GetWidth and button:GetWidth(), itemW)
        local fitScale = (rawBtnW > 0 and rawBtnW > (stepX - 2)) and ((stepX - 2) / rawBtnW) or 1
        local btnParent = button.GetParent and button:GetParent()
        local btnParentScale = math.max(YRG.SafeNumber(btnParent and btnParent.GetEffectiveScale and btnParent:GetEffectiveScale(), 1), 0.01)
        local targetSelfScale = (ancScale * fitScale) / btnParentScale
        if type(button.SetScale) == "function" then
            local curSelfScale = YRG.SafeNumber(button.GetScale and button:GetScale(), 1)
            if math.abs(curSelfScale - targetSelfScale) >= 0.005 then
                button:SetScale(targetSelfScale)
            end
        end

        -- Center bag button horizontally & vertically inside its column cell in anchor space,
        -- then scale to bag button space so Gamepad directional focus never drifts diagonally.
        local cellCenterX = baseX - colFromRight * stepX - (itemW / 2)
        local cellCenterY = baseY + (itemRows + bagRows - 1 - rowIdx) * stepY + gap + (itemH / 2)
        local btnScale = math.max(YRG.SafeNumber(button.GetEffectiveScale and button:GetEffectiveScale(), 1), 0.01)
        local scaleRatio = ancScale / btnScale
        local bx = cellCenterX * scaleRatio
        local by = cellCenterY * scaleRatio

        local curPt, curRelTo, curRelPt, curX, curY = button:GetPoint(1)
        if curPt ~= "CENTER" or curRelTo ~= anchor or curRelPt ~= "TOPRIGHT"
            or type(curX) ~= "number" or type(curY) ~= "number"
            or math.abs(curX - bx) >= 0.4 or math.abs(curY - by) >= 0.4 then
            button:ClearAllPoints()
            button:SetPoint("CENTER", anchor, "TOPRIGHT", bx, by)
        end
    end

    local curH = YRG.SafeNumber(frame.GetHeight and frame:GetHeight(), 0)
    if math.abs(curH - height) >= 0.4 then
        frame:SetHeight(height)
    end

    if not dividerFrame then
        dividerFrame = CreateFrame("Frame", "YRGBetterBagsDividerFrame", UIParent)
        dividerFrame:EnableMouse(false)
        if dividerFrame.SetMouseClickEnabled then dividerFrame:SetMouseClickEnabled(false) end
        if dividerFrame.SetMouseMotionEnabled then dividerFrame:SetMouseMotionEnabled(false) end
        divider = dividerFrame:CreateTexture(nil, "ARTWORK")
        divider:SetAllPoints(dividerFrame)
        divider:SetColorTexture(0.65, 0.55, 0.35, 0.45)
        frame:HookScript("OnHide", HideDividerOverlay)
    end
    local uiScale = math.max(YRG.SafeNumber(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale(), 1), 0.01)
    dividerFrame:SetScale(ancScale / uiScale)
    dividerFrame:SetFrameStrata(frameStrata)
    dividerFrame:SetFrameLevel(frameLevel + 2)
    dividerFrame:ClearAllPoints()
    dividerFrame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", baseX,
        baseY + itemRows * stepY + (gap - (stepY - itemH)) / 2)
    dividerFrame:SetSize((columns - 1) * stepX + itemW, 1)
    dividerFrame:SetShown(db.showDivider ~= false and itemRows > 0)

    applying = false

    if BetterBags._statusText then
        BetterBags:UpdateStatusText()
    end
end

-- =========================================================================
-- NON-CONTROLLER MODE: Merge Reagent Bag into Combined Bags (Optional Purple Tint)
-- =========================================================================
local function GetBagNumSlotsSafe(bagID)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        return YRG.SafeNumber(C_Container.GetContainerNumSlots(bagID), 0)
    elseif type(GetContainerNumSlots) == "function" then
        return YRG.SafeNumber(GetContainerNumSlots(bagID), 0)
    end
    return 0
end

local function HideReagentOverlays()
    if reagentDividerFrame then
        reagentDividerFrame:Hide()
    end
    if reagentBagHolder then
        reagentBagHolder:Hide()
    end
    for _, btn in ipairs(reagentSlotButtons) do
        btn:Hide()
    end
end

local function ApplyButtonPurpleTint(btn, showTint, hasItem)
    if not btn or IsFrameProtectedOrForbidden(btn) then return end
    if not showTint then
        if btn._yrgPurpleBg then btn._yrgPurpleBg:Hide() end
        if btn._yrgPurpleTint then btn._yrgPurpleTint:Hide() end
        return
    end

    if not btn._yrgPurpleBg then
        local bg = btn:CreateTexture(nil, "BACKGROUND", nil, 7)
        bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        bg:SetColorTexture(0.28, 0.12, 0.48, 0.18)
        btn._yrgPurpleBg = bg
    end
    btn._yrgPurpleBg:Show()

    if not btn._yrgPurpleTint then
        local tf = CreateFrame("Frame", nil, btn)
        tf:SetAllPoints(btn)
        tf:EnableMouse(false)
        if tf.SetMouseClickEnabled then tf:SetMouseClickEnabled(false) end
        if tf.SetMouseMotionEnabled then tf:SetMouseMotionEnabled(false) end

        -- Keep tint strictly inside the cell interior without any purple outline so native quality borders stay intact
        local fill = tf:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", tf, "TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", -3, 3)
        fill:SetColorTexture(0.34, 0.16, 0.56, 0.14)
        tf.fill = fill

        btn._yrgPurpleTint = tf
    end
    btn._yrgPurpleTint:SetFrameLevel(math.max((btn.GetFrameLevel and btn:GetFrameLevel() or 1) + 1, 2))
    btn._yrgPurpleTint:SetShown(not hasItem)
end

local function GetReagentItemInfoSafe(bagID, slot)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if type(info) == "table" and info.iconFileID then
            return info.iconFileID,
                YRG.SafeNumber(info.stackCount, 1),
                info.isLocked and true or false,
                info.quality,
                info.isReadable and true or false,
                info.hasLoot and true or false,
                info.hyperlink,
                info.isFiltered and true or false,
                info.itemID,
                info.isBound and true or false
        end
        return nil
    elseif type(GetContainerItemInfo) == "function" then
        local icon, count, locked, quality, isReadable, hasLoot, itemLink, isFiltered, _, itemID, isBound = GetContainerItemInfo(bagID, slot)
        if icon then
            return icon,
                YRG.SafeNumber(count, 1),
                locked and true or false,
                quality,
                isReadable and true or false,
                hasLoot and true or false,
                itemLink,
                isFiltered and true or false,
                itemID,
                isBound and true or false
        end
    end
    return nil
end

local function UpdateReagentSlotButton(btn, bagID, slot, tintPurple)
    if not btn or IsFrameProtectedOrForbidden(btn) then return end

    btn:SetID(slot)
    if type(btn.SetBagID) == "function" then
        btn:SetBagID(bagID)
    end
    btn.bagID = bagID

    local icon, count, locked, quality, isReadable, _, itemLink, isFiltered, _, isBound = GetReagentItemInfoSafe(bagID, slot)
    local hasItem = (icon ~= nil)

    if type(SetItemButtonTexture) == "function" then
        SetItemButtonTexture(btn, icon)
    elseif btn.icon then
        if icon then
            btn.icon:SetTexture(icon)
            btn.icon:Show()
        else
            btn.icon:SetTexture(nil)
            btn.icon:Hide()
        end
    end

    if type(SetItemButtonCount) == "function" then
        SetItemButtonCount(btn, hasItem and count or 0)
    end
    if type(SetItemButtonDesaturated) == "function" then
        SetItemButtonDesaturated(btn, hasItem and locked or false)
    end
    if type(btn.SetItemButtonQuality) == "function" then
        pcall(btn.SetItemButtonQuality, btn, hasItem and quality or nil, hasItem and itemLink or nil, false, hasItem and isBound or false)
    elseif type(SetItemButtonQuality) == "function" then
        pcall(SetItemButtonQuality, btn, hasItem and quality or nil, hasItem and itemLink or nil, false, hasItem and isBound or false)
    end

    btn.hasItem = hasItem
    if type(btn.SetHasItem) == "function" then
        pcall(btn.SetHasItem, btn, hasItem)
    end
    if type(btn.SetReadable) == "function" then
        pcall(btn.SetReadable, btn, hasItem and isReadable or false)
    end

    if not hasItem then
        if btn.IconBorder then btn.IconBorder:Hide() end
        if btn.IconOverlay then btn.IconOverlay:Hide() end
        if btn.IconOverlay2 then btn.IconOverlay2:Hide() end
        if btn.JunkIcon then btn.JunkIcon:Hide() end
        if btn.UpgradeIcon then btn.UpgradeIcon:Hide() end
        if btn.IconQuestTexture then btn.IconQuestTexture:Hide() end
        if btn.NewItemTexture then btn.NewItemTexture:Hide() end
        if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide() end
        if btn.Cooldown then btn.Cooldown:Hide() end
    else
        if btn.Cooldown and C_Container and type(C_Container.GetContainerItemCooldown) == "function" and type(CooldownFrame_Set) == "function" then
            local start, duration, enable = C_Container.GetContainerItemCooldown(bagID, slot)
            CooldownFrame_Set(btn.Cooldown, YRG.SafeNumber(start, 0), YRG.SafeNumber(duration, 0), enable)
        elseif type(btn.UpdateCooldown) == "function" then
            pcall(btn.UpdateCooldown, btn, bagID)
        end

        if type(btn.UpdateNewItem) == "function" then
            pcall(btn.UpdateNewItem, btn, quality)
        elseif btn.NewItemTexture and C_NewItems and type(C_NewItems.IsNewItem) == "function" then
            btn.NewItemTexture:SetShown(C_NewItems.IsNewItem(bagID, slot) and true or false)
        end
    end

    local dimmed = hasItem and isFiltered or false
    if type(btn.SetMatchesSearch) == "function" then
        pcall(btn.SetMatchesSearch, btn, not dimmed)
    elseif btn.searchOverlay then
        btn.searchOverlay:SetShown(dimmed)
    end

    if type(btn.UpdateItemContextMatching) == "function" then
        pcall(btn.UpdateItemContextMatching, btn)
    end

    ApplyButtonPurpleTint(btn, tintPurple, hasItem)

    if GameTooltip and type(GameTooltip.IsOwned) == "function" and GameTooltip:IsOwned(btn) then
        if type(btn.UpdateTooltip) == "function" then
            pcall(btn.UpdateTooltip, btn)
        elseif type(GameTooltip.SetBagItem) == "function" then
            pcall(GameTooltip.SetBagItem, GameTooltip, bagID, slot)
        end
    end
end

local function GetOrCreateReagentHolder(frame)
    if not reagentBagHolder then
        local holder = CreateFrame("Frame", "YRGReagentBagHolder", frame)
        holder:EnableMouse(false)
        if holder.SetMouseClickEnabled then holder:SetMouseClickEnabled(false) end
        if holder.SetMouseMotionEnabled then holder:SetMouseMotionEnabled(false) end
        holder.GetBagID = function() return GetReagentBagID() end
        holder.MatchesBagID = function(_, id) return id == GetReagentBagID() end
        holder.IsBagOpen = function(_, id)
            return id == GetReagentBagID() and ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()
        end
        holder.IsCombinedBagContainer = function() return true end
        holder.GetBagSize = function() return GetBagNumSlotsSafe(GetReagentBagID()) end
        holder.IsPlusTwoBag = function() return false end
        holder.GetPaddingWidth = function() return 0 end
        holder.GetPaddingHeight = function() return 0 end
        holder.SetItemsMatchingBagHighlighted = function() end
        holder.OnBagSlotEnter = function() end
        holder.OnBagSlotLeave = function() end
        reagentBagHolder = holder
    end
    if reagentBagHolder:GetParent() ~= frame then
        reagentBagHolder:SetParent(frame)
    end
    reagentBagHolder:SetID(GetReagentBagID())
    reagentBagHolder:ClearAllPoints()
    reagentBagHolder:SetAllPoints(frame)
    return reagentBagHolder
end

local function GetOrCreateReagentSlotButton(slot, holder, templateName, bagID)
    local btn = reagentSlotButtons[slot]
    if not btn then
        local ok, created = pcall(CreateFrame, "ItemButton", "YRGReagentBagSlot" .. slot, holder, templateName or "ContainerFrameItemButtonTemplate")
        if not ok or not created then
            created = CreateFrame("ItemButton", "YRGReagentBagSlot" .. slot, holder, "ContainerFrameItemButtonTemplate")
        end
        btn = created
        if not btn:GetScript("OnDragStart") then
            btn:SetScript("OnDragStart", function(self)
                if C_Container and type(C_Container.PickupContainerItem) == "function" then
                    C_Container.PickupContainerItem(self:GetBagID(), self:GetID())
                elseif type(PickupContainerItem) == "function" then
                    PickupContainerItem(self:GetBagID(), self:GetID())
                end
            end)
        end
        if not btn:GetScript("OnReceiveDrag") then
            btn:SetScript("OnReceiveDrag", function(self)
                if C_Container and type(C_Container.PickupContainerItem) == "function" then
                    C_Container.PickupContainerItem(self:GetBagID(), self:GetID())
                elseif type(PickupContainerItem) == "function" then
                    PickupContainerItem(self:GetBagID(), self:GetID())
                end
            end)
        end
        if not btn.SplitStack then
            btn.SplitStack = function(self, split)
                if split and split > 0 then
                    if C_Container and type(C_Container.SplitContainerItem) == "function" then
                        C_Container.SplitContainerItem(self:GetBagID(), self:GetID(), split)
                    elseif type(SplitContainerItem) == "function" then
                        SplitContainerItem(self:GetBagID(), self:GetID(), split)
                    end
                end
            end
        end
        reagentSlotButtons[slot] = btn
    end
    if btn:GetParent() ~= holder then
        btn:SetParent(holder)
    end
    btn:SetID(slot)
    if type(btn.SetBagID) == "function" then
        btn:SetBagID(bagID)
    end
    btn.bagID = bagID
    if type(btn.GetBagID) ~= "function" or btn:GetBagID() ~= bagID then
        btn.GetBagID = function() return GetReagentBagID() end
    end
    return btn
end

local function UpdateAllReagentSlotButtons()
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled or db.includeReagentBagInCombined == false
        or IsControllerUIActive()
        or not ContainerFrameCombinedBags or not ContainerFrameCombinedBags:IsShown()
        or not reagentBagHolder or not reagentBagHolder:IsShown() then
        return
    end
    local reagentBagID = GetReagentBagID()
    local numSlots = GetBagNumSlotsSafe(reagentBagID)
    local tintPurple = (db.reagentBagTintPurple ~= false)
    for slot = 1, numSlots do
        local btn = reagentSlotButtons[slot]
        if btn and btn:IsShown() then
            UpdateReagentSlotButton(btn, reagentBagID, slot, tintPurple)
        end
    end
end

local function RestoreCombinedBagsFromMerge(frame)
    HideReagentOverlays()
    if InCombatLockdown() or not frame or IsFrameProtectedOrForbidden(frame) then return end
    if type(frame.IsShown) ~= "function" or not frame:IsShown() then return end

    local anchor = frame.MoneyFrame
    if not anchor or IsFrameProtectedOrForbidden(anchor) then return end
    local minY
    local stdEntries = {}
    if type(frame.EnumerateValidItems) == "function" then
        for _, btn in frame:EnumerateValidItems() do
            if not IsFrameProtectedOrForbidden(btn) and (type(btn.IsShown) ~= "function" or btn:IsShown()) then
                local pt, relTo, relPt, x, y = btn:GetPoint(1)
                if pt == "BOTTOMRIGHT" and relTo == anchor and relPt == "TOPRIGHT"
                    and type(x) == "number" and type(y) == "number" then
                    stdEntries[#stdEntries + 1] = { button = btn, x = x, y = y }
                    if not minY or y < minY then minY = y end
                end
            end
        end
    end
    local baseY = nativeBagBaseY[frame] or 4
    if minY and minY > baseY + 1 then
        local restoreDelta = baseY - minY
        for _, entry in ipairs(stdEntries) do
            entry.button:ClearAllPoints()
            entry.button:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", entry.x, entry.y + restoreDelta)
        end
    end
    if type(frame.CalculateHeight) == "function" then
        local calcH = YRG.SafeNumber(frame:CalculateHeight(), 0)
        local curH = YRG.SafeNumber(frame.GetHeight and frame:GetHeight(), 0)
        if calcH > 0 and math.abs(curH - calcH) >= 0.4 then
            frame:SetHeight(calcH)
        end
    end
end

local function ApplyNonControllerReagentMerge()
    if applying then return end
    if InCombatLockdown() then
        pending = true
        return
    end

    local db = YRG:GetModuleDB("BetterBagsModule")
    local frame = ContainerFrameCombinedBags
    local reagentBagID = GetReagentBagID()

    if not db or not db.enabled or db.includeReagentBagInCombined == false
        or IsControllerUIActive() or not frame or not frame:IsShown()
        or IsFrameProtectedOrForbidden(frame) then
        RestoreCombinedBagsFromMerge(frame)
        return
    end

    local numReagentSlots = GetBagNumSlotsSafe(reagentBagID)
    if numReagentSlots <= 0 then
        RestoreCombinedBagsFromMerge(frame)
        return
    end

    local columns = frame:GetColumns()
    if not columns or columns < 1 or not frame.itemButtonPool or type(frame.itemButtonPool.GetTemplate) ~= "function" then
        HideReagentOverlays()
        return
    end
    local templateName = frame.itemButtonPool:GetTemplate()
    local template = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(templateName)
    if not template or not template.width or not template.height then
        HideReagentOverlays()
        return
    end
    local anchor = frame.MoneyFrame
    if not anchor or IsFrameProtectedOrForbidden(anchor) then
        HideReagentOverlays()
        return
    end

    -- Collect regular combined bag items to find exact grid origin, spacing, and shift offset
    local itemW, itemH = template.width, template.height
    local maxX, minY
    local xs, ys, stdEntries = {}, {}, {}
    for _, btn in frame:EnumerateValidItems() do
        if IsFrameProtectedOrForbidden(btn) then return end
        if (type(btn.IsShown) ~= "function" or btn:IsShown()) and btn:GetBagID() ~= reagentBagID then
            local pt, relTo, relPt, x, y = btn:GetPoint(1)
            if pt ~= "BOTTOMRIGHT" or relTo ~= anchor or relPt ~= "TOPRIGHT"
                or type(x) ~= "number" or type(y) ~= "number" then
                HideReagentOverlays()
                return
            end
            stdEntries[#stdEntries + 1] = { button = btn, x = x, y = y }
            if not maxX or x > maxX then maxX = x end
            if not minY or y < minY then minY = y end
            xs[#xs + 1] = x
            ys[#ys + 1] = y
        end
    end

    local stdCount = #stdEntries
    if stdCount == 0 or not minY then
        HideReagentOverlays()
        return
    end

    -- Preserve Blizzard's native bottom offset (typically 4) across repeat UpdateItems passes
    if minY < 20 then
        nativeBagBaseY[frame] = minY
    end
    local baseX = (maxX and maxX <= 2) and maxX or 0
    local baseY = nativeBagBaseY[frame] or 4
    local stepX = itemW + 5
    local stepY = itemH + 5
    if #xs > 1 then
        table.sort(xs, function(a, b) return a > b end)
        local minDx = nil
        for i = 2, #xs do
            local dx = xs[i - 1] - xs[i]
            if dx > itemW * 0.5 and (not minDx or dx < minDx) then minDx = dx end
        end
        if minDx and minDx < itemW * 1.4 then stepX = minDx end
    end
    if #ys > 1 then
        table.sort(ys)
        local minDy = nil
        for i = 2, #ys do
            local dy = ys[i] - ys[i - 1]
            if dy > itemH * 0.5 and (not minDy or dy < minDy) then minDy = dy end
        end
        if minDy and minDy < itemH * 1.4 then stepY = minDy end
    end

    local reagentGap = 8
    local reagentRows = math.ceil(numReagentSlots / columns)
    local stdShiftTarget = baseY + (reagentRows * stepY) + reagentGap
    local deltaY = stdShiftTarget - minY
    local targetHeight = frame:CalculateHeight() + (reagentRows * stepY) + reagentGap

    applying = true

    local holder = GetOrCreateReagentHolder(frame)
    local frameLevel = math.max((frame.GetFrameLevel and frame:GetFrameLevel() or 1), 1)
    holder:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    holder:SetFrameLevel(frameLevel + 1)
    holder:Show()

    local curH = YRG.SafeNumber(frame.GetHeight and frame:GetHeight(), 0)
    if math.abs(curH - targetHeight) >= 0.4 then
        frame:SetHeight(targetHeight)
    end

    if math.abs(deltaY) >= 0.4 then
        for _, entry in ipairs(stdEntries) do
            entry.button:ClearAllPoints()
            entry.button:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", entry.x, entry.y + deltaY)
        end
    end

    local tintPurple = (db.reagentBagTintPurple ~= false)
    local btnLevel = frameLevel + 2
    -- Render Slot N..1 from bottom-right leftward & upward, matching Blizzard's Combined Bags order
    for i = 1, numReagentSlots do
        local slot = numReagentSlots - i + 1
        local btn = GetOrCreateReagentSlotButton(slot, holder, templateName, reagentBagID)
        local idx = i - 1
        local tx = baseX - (idx % columns) * stepX
        local ty = baseY + math.floor(idx / columns) * stepY

        btn:SetSize(itemW, itemH)
        btn:SetFrameLevel(btnLevel)
        local pt, relTo, relPt, curX, curY = btn:GetPoint(1)
        if pt ~= "BOTTOMRIGHT" or relTo ~= anchor or relPt ~= "TOPRIGHT"
            or type(curX) ~= "number" or type(curY) ~= "number"
            or math.abs(curX - tx) >= 0.4 or math.abs(curY - ty) >= 0.4 then
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", tx, ty)
        end

        btn:Show()
        UpdateReagentSlotButton(btn, reagentBagID, slot, tintPurple)
    end

    for slot = numReagentSlots + 1, #reagentSlotButtons do
        reagentSlotButtons[slot]:Hide()
    end

    if not reagentDividerFrame then
        reagentDividerFrame = CreateFrame("Frame", "YRGReagentDividerFrame", frame)
        reagentDividerFrame:EnableMouse(false)
        if reagentDividerFrame.SetMouseClickEnabled then reagentDividerFrame:SetMouseClickEnabled(false) end
        if reagentDividerFrame.SetMouseMotionEnabled then reagentDividerFrame:SetMouseMotionEnabled(false) end
        reagentDivider = reagentDividerFrame:CreateTexture(nil, "ARTWORK")
        reagentDivider:SetAllPoints(reagentDividerFrame)
        reagentDivider:SetColorTexture(0, 0, 0, 0.50)
    end
    if reagentDividerFrame:GetParent() ~= frame then
        reagentDividerFrame:SetParent(frame)
    end
    reagentDividerFrame:SetFrameLevel(frameLevel + 2)
    reagentDividerFrame:ClearAllPoints()
    reagentDividerFrame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", baseX,
        baseY + (reagentRows - 1) * stepY + itemH + (reagentGap + (stepY - itemH)) / 2)
    reagentDividerFrame:SetSize((columns - 1) * stepX + itemW, 1)
    reagentDividerFrame:Show()

    applying = false

    if BetterBags._statusText then
        BetterBags:UpdateStatusText()
    end
end

ApplyUnifiedBagLayout = function()
    if IsControllerUIActive() then
        HideReagentOverlays()
        ApplyControllerBagStripLayout()
    else
        HideDividerOverlay()
        ResetControllerBagButtonScales()
        ApplyNonControllerReagentMerge()
    end
end

-- =========================================================================
-- ALL-MODE BAG AUTOMATION (Works in Keyboard/Mouse AND Controller Mode)
-- =========================================================================
local function ExecuteBagSort()
    if InCombatLockdown() then return end
    if C_Container and type(C_Container.SortBags) == "function" then
        C_Container.SortBags()
    elseif type(SortBags) == "function" then
        SortBags()
    end
end

local function TriggerAutoSortIfEnabled()
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled or not db.autoSortOnOpen then return end
    if InCombatLockdown() then return end

    local now = GetTime and GetTime() or 0
    if now - lastSortTime < 0.75 then return end
    lastSortTime = now

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.05, ExecuteBagSort)
    else
        ExecuteBagSort()
    end
end

local function SafeGetItemInfo(item)
    if not item then return nil end
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        return C_Item.GetItemInfo(item)
    elseif type(GetItemInfo) == "function" then
        return GetItemInfo(item)
    end
    return nil
end

local function NormalizeItemName(str)
    if not str then return nil end
    local linkName = str:match("%[(.-)%]")
    local clean = linkName or str
    clean = clean:gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" then return nil end
    return clean
end

local function IsItemExcluded(db, itemName)
    if not itemName then return false end
    local list = db and db.sellExclusionList
    if list then
        if list[itemName] then return true end
        local lowerTarget = itemName:lower()
        for k, v in pairs(list) do
            if v and type(k) == "string" and k:lower() == lowerTarget then
                return true
            end
        end
    end
    return false
end

local sellTicker = nil
local activeSellState = nil

local function PrintSoldSummary(state)
    if not state or state.printed or state.itemsSoldCount <= 0 then return end
    state.printed = true
    if DEFAULT_CHAT_FRAME then
        local g = math.floor(state.totalSoldCopper / 10000)
        local s = math.floor((state.totalSoldCopper % 10000) / 100)
        local c = state.totalSoldCopper % 100
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffd100YRG BetterBags:|r Sold %d grey item(s) for %dg %ds %dc.", state.itemsSoldCount, g, s, c))
    end
end

local function StopSellTicker()
    if sellTicker and type(sellTicker.Cancel) == "function" then
        sellTicker:Cancel()
    end
    sellTicker = nil
    if activeSellState then
        PrintSoldSummary(activeSellState)
        activeSellState = nil
    end
end

local function SellGreyItemsPass(db, state)
    local soldThisPass = 0
    local startBag = BACKPACK_CONTAINER or 0
    local endBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 5

    for bag = startBag, endBag do
        local numSlots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag))
            or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0

        for slot = 1, numSlots do
            local itemLink, quality, itemCount, isLocked, hasNoValue, itemID
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    itemLink = info.hyperlink
                    quality = info.quality
                    itemCount = info.stackCount or 1
                    isLocked = info.isLocked
                    hasNoValue = info.hasNoValue
                    itemID = info.itemID
                end
            elseif GetContainerItemInfo then
                local _, count, locked, qual, _, _, link, _, noVal, id = GetContainerItemInfo(bag, slot)
                itemLink = link
                quality = qual
                itemCount = count or 1
                isLocked = locked
                hasNoValue = noVal
                itemID = id
            end

            if not itemLink and C_Container and C_Container.GetContainerItemLink then
                itemLink = C_Container.GetContainerItemLink(bag, slot)
            end

            local itemName, _, infoQuality, _, _, _, _, _, _, _, sellPrice = SafeGetItemInfo(itemLink or itemID)
            if quality == nil then
                quality = infoQuality
            end

            if (itemLink or itemID) and quality == 0 and not isLocked and not hasNoValue then
                local resolvedName = itemName or NormalizeItemName(itemLink)
                if resolvedName and not IsItemExcluded(db, resolvedName) then
                    local unitPrice = YRG.SafeNumber(sellPrice, 0)
                    if sellPrice == nil or unitPrice > 0 then
                        local slotKey = bag .. ":" .. slot
                        if not state.countedSlots[slotKey] then
                            state.countedSlots[slotKey] = true
                            state.totalSoldCopper = state.totalSoldCopper + (unitPrice * (itemCount or 1))
                            state.itemsSoldCount = state.itemsSoldCount + 1
                        end
                        soldThisPass = soldThisPass + 1
                        if C_Container and C_Container.UseContainerItem then
                            C_Container.UseContainerItem(bag, slot)
                        elseif UseContainerItem then
                            UseContainerItem(bag, slot)
                        end
                    end
                end
            end
        end
    end

    return soldThisPass
end

local function FormatRepairLimit(silverVal)
    local s = math.max(0, math.floor((tonumber(silverVal) or 0) + 0.5))
    if s <= 0 then
        return "Unlimited"
    end
    local gold = math.floor(s / 100)
    local remSilver = s % 100
    if gold > 0 and remSilver > 0 then
        return string.format("%dg %ds", gold, remSilver)
    elseif gold > 0 then
        return string.format("%dg", gold)
    end
    return string.format("%ds", remSilver)
end

local function HandleMerchantShow()
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end

    StopSellTicker()

    -- 1. Auto-Repair with Cost Cap (stored in silver; 0 = Unlimited)
    if db.autoRepair and type(CanMerchantRepair) == "function" and CanMerchantRepair() then
        local rawCost, canRepair = GetRepairAllCost()
        local repairCost = YRG.SafeNumber(rawCost, 0)
        if canRepair and repairCost > 0 then
            local maxSilver = math.max(0, tonumber(db.autoRepairMaxSilver) or 0)
            local maxCopper = maxSilver * 100
            if maxSilver <= 0 or repairCost <= maxCopper then
                local playerMoney = YRG.SafeNumber(GetMoney and GetMoney() or 0, 0)
                if playerMoney >= repairCost then
                    RepairAllItems()
                    local g = math.floor(repairCost / 10000)
                    local s = math.floor((repairCost % 10000) / 100)
                    local c = repairCost % 100
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffd100YRG BetterBags:|r Auto-repaired gear for %dg %ds %dc.", g, s, c))
                    end
                end
            else
                local g = math.floor(repairCost / 10000)
                local s = math.floor((repairCost % 10000) / 100)
                local c = repairCost % 100
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffd100YRG BetterBags:|r Skipped auto-repair (%dg %ds %dc exceeds your %s limit).", g, s, c, FormatRepairLimit(maxSilver)))
                end
            end
        end
    end

    -- 2. Auto-Sell Greys (Poor Quality) with Exclusion List
    if db.autoSellGreys then
        local state = {
            totalSoldCopper = 0,
            itemsSoldCount = 0,
            countedSlots = {},
            printed = false,
        }
        activeSellState = state

        local soldNow = SellGreyItemsPass(db, state)
        if soldNow > 0 and soldNow < 10 then
            PrintSoldSummary(state)
        end
        if C_Timer and type(C_Timer.NewTicker) == "function" then
            local ticks = 0
            sellTicker = C_Timer.NewTicker(0.2, function()
                ticks = ticks + 1
                if (MerchantFrame and not MerchantFrame:IsShown()) or not db.autoSellGreys then
                    StopSellTicker()
                    return
                end
                local moreSold = SellGreyItemsPass(db, state)
                if moreSold == 0 or ticks >= 8 then
                    StopSellTicker()
                end
            end, 8)
        else
            StopSellTicker()
        end
    end
end

-- =========================================================================
-- AUTO-OPEN CLAMS ON LOOT
-- =========================================================================
local CLAM_ITEM_IDS = {
    [5523]  = true, -- Small Barnacled Clam
    [5524]  = true, -- Thick-shelled Clam
    [7973]  = true, -- Big-mouth Clam
    [15874] = true, -- Soft-shelled Clam
    [24476] = true, -- Jaggal Clam
}

local clamOpenTimer = nil
local isLootingWindowOpen = false
local isOpeningClamNow = false
local clamBlockedByClient = false
local clamLastAttempt = nil
local clamFullBagWarnAt = 0

local function HasPlainCastActive()
    if type(UnitCastingInfo) == "function" then
        local ok, sp = pcall(UnitCastingInfo, "player")
        if ok and not YRG.IsSecret(sp) and sp ~= nil then
            return true
        end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, sp = pcall(UnitChannelInfo, "player")
        if ok and not YRG.IsSecret(sp) and sp ~= nil then
            return true
        end
    end
    return false
end

local function IsClamOpeningBlockedByUI()
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
    if HasPlainCastActive() then return true end
    if CursorHasItem and CursorHasItem() then return true end
    if isLootingWindowOpen or (LootFrame and LootFrame:IsShown()) then return true end
    for _, frame in ipairs({
        MerchantFrame,
        BankFrame,
        MailFrame,
        SendMailFrame,
        TradeFrame,
        AuctionFrame,
        AuctionHouseFrame,
        GuildBankFrame,
    }) do
        if frame and type(frame.IsShown) == "function" and frame:IsShown() then
            return true
        end
    end
    return false
end

local function GetGeneralFreeBagSlots()
    local total = 0
    local startBag = BACKPACK_CONTAINER or 0
    local endBag = NUM_BAG_SLOTS or 4
    for bag = startBag, endBag do
        local free, family = 0, 0
        if C_Container and type(C_Container.GetContainerNumFreeSlots) == "function" then
            free, family = C_Container.GetContainerNumFreeSlots(bag)
        elseif type(GetContainerNumFreeSlots) == "function" then
            free, family = GetContainerNumFreeSlots(bag)
        end
        free = YRG.SafeNumber(free, 0)
        family = YRG.SafeNumber(family, 0)
        if family == 0 and free > 0 then
            total = total + free
        end
    end
    return total
end

local function IsClamContainerItem(itemID, itemLink, hasLoot, isLocked)
    if not itemID or isLocked then
        return false
    end
    if CLAM_ITEM_IDS[itemID] then
        return true
    end
    if not hasLoot then
        return false
    end
    local itemName, _, _, _, _, _, _, _, _, _, _, classID = SafeGetItemInfo(itemLink or itemID)
    itemName = YRG.SafeString(itemName, nil) or NormalizeItemName(itemLink)
    if not itemName then
        return false
    end
    local questClass = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
    classID = YRG.SafeOptionalNumber(classID)
    if classID ~= nil and classID == questClass then
        return false
    end
    local low = itemName:lower()
    if not low:find("clam", 1, true) then
        return false
    end
    for _, nonContainer in ipairs({ "meat", "chowder", "bait", "cake", "juice", "soup", "boiled", "deviled", "stew", "pearl" }) do
        if low:find(nonContainer, 1, true) then
            return false
        end
    end
    return true
end

local ScheduleClamOpen

local function TryAutoOpenClams()
    if clamBlockedByClient then return end
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled or db.autoOpenClams == false then
        return
    end
    if IsClamOpeningBlockedByUI() then
        return
    end

    local now = (type(GetTime) == "function") and GetTime() or 0
    local freeGeneral = GetGeneralFreeBagSlots()
    local startBag = BACKPACK_CONTAINER or 0
    local endBag = NUM_BAG_SLOTS or 4
    local sawClamWithoutSpace = false

    for bag = startBag, endBag do
        local numSlots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag))
            or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        numSlots = YRG.SafeNumber(numSlots, 0)
        for slot = 1, numSlots do
            local itemID, itemLink, stackCount, isLocked, hasLoot
            if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if type(info) == "table" then
                    itemID = YRG.SafeOptionalNumber(info.itemID)
                    itemLink = info.hyperlink
                    stackCount = YRG.SafeNumber(info.stackCount, 1)
                    isLocked = info.isLocked and true or false
                    hasLoot = info.hasLoot and true or false
                end
            elseif type(GetContainerItemInfo) == "function" then
                local _, count, locked, _, _, lootable, link, _, _, id = GetContainerItemInfo(bag, slot)
                itemID = YRG.SafeOptionalNumber(id)
                itemLink = link
                stackCount = YRG.SafeNumber(count, 1)
                isLocked = locked and true or false
                hasLoot = lootable and true or false
            end

            if IsClamContainerItem(itemID, itemLink, hasLoot, isLocked) then
                local neededFree = (stackCount > 1) and 2 or 1
                if freeGeneral < neededFree then
                    sawClamWithoutSpace = true
                else
                    local retryBlocked = false
                    if clamLastAttempt
                        and clamLastAttempt.bag == bag
                        and clamLastAttempt.slot == slot
                        and clamLastAttempt.itemID == itemID
                        and (now - clamLastAttempt.at) < 10
                        and clamLastAttempt.count >= 2 then
                        retryBlocked = true
                    end

                    if not retryBlocked then
                        if clamLastAttempt and clamLastAttempt.bag == bag and clamLastAttempt.slot == slot and clamLastAttempt.itemID == itemID and (now - clamLastAttempt.at) < 10 then
                            clamLastAttempt.count = clamLastAttempt.count + 1
                            clamLastAttempt.at = now
                        else
                            clamLastAttempt = { bag = bag, slot = slot, itemID = itemID, at = now, count = 1 }
                        end

                        isOpeningClamNow = true
                        if C_Container and type(C_Container.UseContainerItem) == "function" then
                            pcall(C_Container.UseContainerItem, bag, slot)
                        elseif type(UseContainerItem) == "function" then
                            pcall(UseContainerItem, bag, slot)
                        end
                        isOpeningClamNow = false

                        if not clamBlockedByClient then
                            ScheduleClamOpen(0.28)
                        end
                        return
                    end
                end
            end
        end
    end

    if sawClamWithoutSpace and (now - clamFullBagWarnAt) >= 15 then
        clamFullBagWarnAt = now
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd100YRG BetterBags:|r Need at least 1 free bag slot to auto-open clams.")
        end
    end
end

ScheduleClamOpen = function(delaySec)
    if clamBlockedByClient then return end
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled or db.autoOpenClams == false then
        return
    end
    if clamOpenTimer and type(clamOpenTimer.Cancel) == "function" then
        clamOpenTimer:Cancel()
    end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        clamOpenTimer = C_Timer.NewTimer(delaySec or 0.15, function()
            clamOpenTimer = nil
            TryAutoOpenClams()
        end)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delaySec or 0.15, TryAutoOpenClams)
    else
        TryAutoOpenClams()
    end
end

local InstallControllerStripHooks

local function RefreshBlizzardBagLayout()
    -- Avoid calling UpdateContainerFrameAnchors() or frame:UpdateItemLayout() directly from addon code,
    -- which taints global container/UIPanel anchors in Controller Mode.
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled then
        HideDividerOverlay()
        ResetControllerBagButtonScales()
        RestoreCombinedBagsFromMerge(ContainerFrameCombinedBags)
        return
    end
    if InstallControllerStripHooks then InstallControllerStripHooks() end
    ApplyUnifiedBagLayout()
end

local function InstallAutomationHooks()
    if autoSortHooked then return end
    autoSortHooked = true

    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", TriggerAutoSortIfEnabled)
    end
    for i = 1, 13 do
        local cf = _G["ContainerFrame" .. i]
        if cf then
            cf:HookScript("OnShow", TriggerAutoSortIfEnabled)
        end
    end
    if type(ToggleAllBags) == "function" then
        hooksecurefunc("ToggleAllBags", function()
            if (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown())
                or (ContainerFrame1 and ContainerFrame1:IsShown()) then
                TriggerAutoSortIfEnabled()
            end
        end)
    end
    if type(OpenAllBags) == "function" then
        hooksecurefunc("OpenAllBags", TriggerAutoSortIfEnabled)
    end
    if type(OpenBackpack) == "function" then
        hooksecurefunc("OpenBackpack", TriggerAutoSortIfEnabled)
    end
end

local function ScheduleUnifiedBagLayout()
    if deferredPassPending then return end
    if C_Timer and type(C_Timer.After) == "function" then
        deferredPassPending = true
        C_Timer.After(0, function()
            deferredPassPending = false
            if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                ApplyUnifiedBagLayout()
            end
        end)
    end
end

local function ApplyAndScheduleUnifiedBagLayout()
    ApplyUnifiedBagLayout()
    ScheduleUnifiedBagLayout()
end

InstallControllerStripHooks = function()
    if not reagentSearchHooked and BagItemSearchBox and type(BagItemSearchBox.HookScript) == "function" then
        reagentSearchHooked = true
        BagItemSearchBox:HookScript("OnTextChanged", function()
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, UpdateAllReagentSlotButtons)
            else
                UpdateAllReagentSlotButtons()
            end
        end)
    end

    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled then return end
    if db.controllerBagStrip == false and db.includeReagentBagInCombined == false then return end

    if not controllerStripHooked and type(UpdateContainerFrameAnchors) == "function"
        and ContainerFrameCombinedBags then
        hooksecurefunc("UpdateContainerFrameAnchors", ApplyAndScheduleUnifiedBagLayout)
        for _, methodName in ipairs({ "UpdateItems", "UpdateItemLayout", "SetupGamepad", "FocusGamepad" }) do
            if type(ContainerFrameCombinedBags[methodName]) == "function" then
                local hookFn = (methodName == "SetupGamepad" or methodName == "FocusGamepad")
                    and ApplyAndScheduleUnifiedBagLayout or ApplyUnifiedBagLayout
                hooksecurefunc(ContainerFrameCombinedBags, methodName, hookFn)
            end
        end
        ContainerFrameCombinedBags:HookScript("OnShow", ApplyAndScheduleUnifiedBagLayout)
        ContainerFrameCombinedBags:HookScript("OnHide", function()
            HideDividerOverlay()
            HideReagentOverlays()
        end)
        controllerStripHooked = true
    end

    -- Hook GamepadBagBar separately so delayed Proton/Blizzard bag bar layouts or
    -- demand-loaded GamepadBagBar updates never leave bag buttons unpinned/unscaled.
    if GamepadBagBar and not gamepadBagBarHooked then
        if type(GamepadBagBar.HookScript) == "function" then
            GamepadBagBar:HookScript("OnShow", ApplyAndScheduleUnifiedBagLayout)
        end
        for _, methodName in ipairs({ "Layout", "Update", "SetupGamepad", "UpdateBagButtons" }) do
            if type(GamepadBagBar[methodName]) == "function" then
                hooksecurefunc(GamepadBagBar, methodName, ApplyAndScheduleUnifiedBagLayout)
            end
        end
        gamepadBagBarHooked = true
    end
end

function BetterBags:GetStatusMessage()
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled then
        return "Disabled in YRG module settings."
    elseif not IsControllerUIActive() then
        local rMsg = (db.includeReagentBagInCombined ~= false) and "Reagent Bag Merge ON" or "Reagent Bag Separate"
        return "Desktop Mode: " .. rMsg .. " + Bag Automation Active."
    elseif db.controllerBagStrip == false then
        return "Controller Mode Active (Bag Strip Disabled) + Bag Automation Active."
    elseif InCombatLockdown() then
        return "Layout changes will apply after combat."
    else
        return "Active: Controller Bag Strip pinned (" .. (db.bagPinAlignment or "RIGHT") .. ") + Bag Automation Active."
    end
end

function BetterBags:UpdateStatusText()
    if self._statusInitializer and self._statusInitializer.data then
        self._statusInitializer.data.name = "Status: " .. self:GetStatusMessage()
    end
end

function BetterBags:OnInitialize(db)
    if YRGDB and YRGDB.modules and YRGDB.modules.SeparateBagStrip then
        for k, v in pairs(YRGDB.modules.SeparateBagStrip) do
            if db[k] == nil then db[k] = v end
        end
        YRGDB.modules.SeparateBagStrip = nil
    end

    if not db.sellExclusionList then
        db.sellExclusionList = CopyTable(DEFAULT_EXCLUSIONS)
    end
    if db.autoRepairMaxSilver == nil then
        local oldGold = tonumber(db.autoRepairMaxGold) or 0
        if oldGold > 0 then
            db.autoRepairMaxSilver = math.min(1000, math.floor(oldGold * 100 + 0.5))
        else
            db.autoRepairMaxSilver = 0
        end
    end
    db.autoRepairMaxGold = nil
    db.autoRepairMaxSilver = math.max(0, math.min(1000, math.floor(tonumber(db.autoRepairMaxSilver) or 0)))

    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("PLAYER_LOGIN")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
    self.eventFrame:RegisterEvent("MERCHANT_SHOW")
    self.eventFrame:RegisterEvent("MERCHANT_CLOSED")
    self.eventFrame:RegisterEvent("LOOT_OPENED")
    self.eventFrame:RegisterEvent("LOOT_CLOSED")
    self.eventFrame:RegisterEvent("BAG_OPEN")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    self.eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    self.eventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
    self.eventFrame:RegisterEvent("BAG_NEW_ITEMS_UPDATED")
    self.eventFrame:RegisterEvent("INVENTORY_SEARCH_UPDATE")
    self.eventFrame:RegisterEvent("BAG_CONTAINER_UPDATE")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "ADDON_ACTION_BLOCKED")
    self.eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        InstallAutomationHooks()
        InstallControllerStripHooks()
        if event == "MERCHANT_SHOW" then
            HandleMerchantShow()
        elseif event == "MERCHANT_CLOSED" then
            StopSellTicker()
        elseif event == "LOOT_OPENED" then
            isLootingWindowOpen = true
        elseif event == "LOOT_CLOSED" then
            isLootingWindowOpen = false
            ScheduleClamOpen(0.15)
        elseif event == "BAG_OPEN" then
            TriggerAutoSortIfEnabled()
            ScheduleClamOpen(0.20)
        elseif event == "BAG_UPDATE" or event == "ITEM_LOCK_CHANGED" then
            if event == "BAG_UPDATE" then
                clamLastAttempt = nil
            end
            if arg1 == nil or arg1 == GetReagentBagID() then
                UpdateAllReagentSlotButtons()
            end
        elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE_COOLDOWN"
            or event == "BAG_NEW_ITEMS_UPDATED" or event == "INVENTORY_SEARCH_UPDATE" then
            UpdateAllReagentSlotButtons()
            if event == "BAG_UPDATE_DELAYED" then
                ScheduleClamOpen(0.15)
            end
        elseif event == "BAG_CONTAINER_UPDATE" then
            ApplyAndScheduleUnifiedBagLayout()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pending then
                ApplyAndScheduleUnifiedBagLayout()
            end
            ScheduleClamOpen(0.15)
        elseif event == "PLAYER_ENTERING_WORLD" then
            ScheduleClamOpen(0.25)
        elseif event == "PLAYER_LOGIN" or event == "GAME_PAD_ACTIVE_CHANGED" then
            ApplyAndScheduleUnifiedBagLayout()
        elseif event == "ADDON_ACTION_BLOCKED" then
            if isOpeningClamNow then
                isOpeningClamNow = false
                clamBlockedByClient = true
                if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                    local blockedFn = (type(arg2) == "string" and arg2 ~= "") and (" (" .. arg2 .. ")") or ""
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100YRG:|r Auto-open clams was blocked by the client" .. blockedFn .. " and paused for this session.")
                end
            end
        end
        self:UpdateStatusText()
    end)
    InstallAutomationHooks()
    InstallControllerStripHooks()
end

function BetterBags:OnEnable(db)
    InstallAutomationHooks()
    InstallControllerStripHooks()
    RefreshBlizzardBagLayout()
    ScheduleClamOpen(0.25)
    self:UpdateStatusText()
end

function BetterBags:OnDisable(db)
    if clamOpenTimer then
        clamOpenTimer:Cancel()
        clamOpenTimer = nil
    end
    isLootingWindowOpen = false
    isOpeningClamNow = false
    clamLastAttempt = nil
    HideDividerOverlay()
    ResetControllerBagButtonScales()
    RestoreCombinedBagsFromMerge(ContainerFrameCombinedBags)
    self:UpdateStatusText()
end

function BetterBags:BuildConfigUI(ctx, db)
    local function GetDB()
        return YRG:GetModuleDB("BetterBagsModule")
    end

    local function IsControllerStripEnabled()
        local mdb = GetDB()
        return mdb == nil or mdb.controllerBagStrip ~= false
    end

    -- =========================================================================
    -- SECTION 1: Controller Mode Exclusive — Separate Bag Strip
    -- =========================================================================
    ctx:AddHeader(
        "1. Controller Mode Exclusive: Separate Bag Strip",
        "Controls the detached bag slot strip docked above bags in Controller/Gamepad UI mode."
    )

    self._statusInitializer = ctx:AddButton({
        name = "Status: " .. self:GetStatusMessage(),
        buttonText = "Check Status",
        tooltip = "Refreshes and prints the current BetterBagsModule Controller / Automation status to chat.",
        onClick = function()
            self:UpdateStatusText()
            print("|cffffd100YRG BetterBagsModule:|r " .. self:GetStatusMessage())
        end,
    })

    local stripDepVars = {
        "YRG_BetterBagsModule_showDivider",
        "YRG_BetterBagsModule_bagPinAlignment",
        "YRG_BetterBagsModule_rowGap",
    }
    ctx:AddCheckbox({
        key = "controllerBagStrip",
        name = "Remove Inline Bags & Pin Bag Strip to Top (Controller Mode)",
        tooltip = "Removes inline bag headers inside bags and pins bag slots into a separate strip above your items in Controller Mode. Turn off to keep Blizzard's default inline bags while keeping Auto-Sort, Auto-Repair, and Auto-Sell Greys active (close and reopen bags to restore inline bags).",
        defaultValue = true,
        notifies = stripDepVars,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.controllerBagStrip ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.controllerBagStrip = val end
            RefreshBlizzardBagLayout()
            if not val and ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                print("|cffffd100YRG BetterBags:|r Inline bags re-enabled. Close and reopen bags to restore default layout.")
            end
            self:UpdateStatusText()
        end,
    })

    ctx:AddCheckbox({
        key = "showDivider",
        name = "Show Divider Line Between Bag Strip & Items (Controller)",
        tooltip = "Displays a thin gold divider line separating the top bag control row from your inventory items in Controller Mode.",
        defaultValue = true,
        canModify = IsControllerStripEnabled,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showDivider ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showDivider = val end
            ApplyControllerBagStripLayout()
        end,
    })

    ctx:AddDropdown({
        key = "bagPinAlignment",
        name = "Controller Bag Bar Pin Alignment",
        tooltip = "Horizontal alignment of the separate bag control strip above your bag grid in Controller Mode. Tip: Right alignment keeps bag buttons above filled top-right item columns when top-left slots are empty.",
        defaultValue = "RIGHT",
        canModify = IsControllerStripEnabled,
        options = {
            { value = "LEFT", label = "Left" },
            { value = "CENTER", label = "Center" },
            { value = "RIGHT", label = "Right" },
        },
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.bagPinAlignment) or "RIGHT"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.bagPinAlignment = val end
            ApplyControllerBagStripLayout()
            self:UpdateStatusText()
        end,
    })

    ctx:AddSlider({
        key = "rowGap",
        name = "Bag Strip Row Spacing",
        tooltip = "Vertical spacing in pixels between the detached controller bag strip and inventory items.",
        min = 4, max = 20, step = 1, defaultValue = 8,
        canModify = IsControllerStripEnabled,
        format = function(v) return string.format("%d px", v) end,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.rowGap) or 8
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.rowGap = val end
            ApplyControllerBagStripLayout()
        end,
    })

    -- =========================================================================
    -- SECTION 2: Non-Controller All-in-One Bags (Reagent Bag Integration)
    -- =========================================================================
    ctx:AddHeader(
        "2. All-in-One Bags: Reagent Bag (Non-Controller)",
        "Merges your separate Reagent Bag window directly into Blizzard's Combined Bags frame in Keyboard/Mouse mode."
    )

    local function IsReagentMergeEnabled()
        local mdb = GetDB()
        return mdb == nil or mdb.includeReagentBagInCombined ~= false
    end

    ctx:AddCheckbox({
        key = "includeReagentBagInCombined",
        name = "Include Reagent Bag When Using All-in-One Bags (Non-Controller)",
        tooltip = "Automatically opens and merges your Reagent Bag slots inside the top of Blizzard's Combined Bags window instead of keeping it as a separate bag frame (Keyboard/Mouse mode).",
        defaultValue = true,
        notifies = { "YRG_BetterBagsModule_reagentBagTintPurple" },
        get = function()
            return IsReagentMergeEnabled()
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.includeReagentBagInCombined = val end
            RefreshBlizzardBagLayout()
            self:UpdateStatusText()
        end,
    })

    ctx:AddCheckbox({
        key = "reagentBagTintPurple",
        name = "Tint Merged Reagent Bag Slots Purple",
        tooltip = "Adds a subtle purple background tint to empty merged Reagent Bag slots while preserving each item's native quality grading border.",
        defaultValue = true,
        canModify = IsReagentMergeEnabled,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.reagentBagTintPurple ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.reagentBagTintPurple = val end
            ApplyNonControllerReagentMerge()
        end,
    })

    -- =========================================================================
    -- SECTION 3: All Modes — Bag Automation & Vendor Repair
    -- =========================================================================
    ctx:AddHeader("3. Bag Automation & Vendor Repair (All Modes)")

    ctx:AddCheckbox({
        key = "autoSortOnOpen",
        name = "Auto-Sort Bags on Open",
        tooltip = "Automatically sorts your inventory bags whenever you open them in either Keyboard/Mouse or Controller Mode.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.autoSortOnOpen) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.autoSortOnOpen = val end
        end,
    })

    ctx:AddCheckbox({
        key = "autoOpenClams",
        name = "Auto-Open Clams on Loot",
        tooltip = "Automatically opens looted clam containers (such as Small Barnacled Clam, Thick-shelled Clam, Big-mouth Clam, Soft-shelled Clam, and Jaggal Clam) out of combat when general bag space is available.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.autoOpenClams ~= false) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.autoOpenClams = val
            end
            if val then
                ScheduleClamOpen(0.10)
            end
        end,
    })

    ctx:AddCheckbox({
        key = "autoRepair",
        name = "Auto-Repair Gear at Vendor NPC",
        tooltip = "Automatically repairs all equipped and inventory gear when visiting a repair-capable NPC in any mode.",
        defaultValue = true,
        notifies = { "YRG_BetterBagsModule_autoRepairMaxSilver" },
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.autoRepair) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.autoRepair = val end
        end,
    })

    ctx:AddSlider({
        key = "autoRepairMaxSilver",
        name = "Auto-Repair Cost Limit",
        tooltip = "Maximum repair cost allowed for automatic repairs (0 = Unlimited, 1s to 10g).",
        min = 0, max = 1000, step = 1, defaultValue = 25,
        format = FormatRepairLimit,
        canModify = function()
            local mdb = GetDB()
            return (mdb and mdb.autoRepair) and true or false
        end,
        get = function()
            local mdb = GetDB()
            local val = (mdb and tonumber(mdb.autoRepairMaxSilver)) or 25
            return math.max(0, math.min(1000, math.floor(val)))
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.autoRepairMaxSilver = val end
        end,
    })

    -- =========================================================================
    -- SECTION 4: All Modes — Auto-Sell Greys & Exclusion List
    -- =========================================================================
    ctx:AddHeader("4. Auto-Sell Greys & Exclusion List (All Modes)")

    ctx:AddCheckbox({
        key = "autoSellGreys",
        name = "Auto-Sell Grey (Poor) Items at Vendor NPC",
        tooltip = "Automatically sells poor-quality items in your bags except items listed on the Grey Exclusion List subpage.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.autoSellGreys) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.autoSellGreys = val end
        end,
    })

    ctx:AddButton({
        name = "Grey Item Exclusion List",
        buttonText = "Manage List...",
        tooltip = "Opens the BetterBags: Exclusion List subpage to add or remove protected grey items (supports typing, Shift-Click links, and item drag-and-drop).",
        onClick = function()
            YRG:OpenSettings("BetterBagsExclusionList")
        end,
    })
end

function BetterBags:BuildExtraCategories(mainCategory, db)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory and Settings.RegisterAddOnCategory and mainCategory) then
        return
    end

    local panel = CreateFrame("Frame", "YRGBetterBagsExclusionPanel", UIParent)
    panel.name = "BetterBags: Exclusion List"
    panel:Hide()

    local built = false
    local refreshFunc = nil

    local function BuildCanvas()
        if built then return end
        built = true

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -16)
        title:SetText("BetterBags: Grey Exclusion List")

        local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        subtitle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -44)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetText("Items listed below are protected from Auto-Sell Greys. Type an exact name, Shift-Click an item link, or drag an item into the input box.")

        local divider = panel:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -68)
        divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -68)
        if divider.SetAtlas then
            local okAtlas = pcall(divider.SetAtlas, divider, "Options_HorizontalDivider", true)
            if not okAtlas then
                divider:SetHeight(1)
                divider:SetColorTexture(0.65, 0.52, 0.25, 0.45)
            end
        else
            divider:SetHeight(1)
            divider:SetColorTexture(0.65, 0.52, 0.25, 0.45)
        end

        local addLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        addLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -86)
        addLabel:SetText("Add Item to Exclusion List:")

        local addInput = CreateFrame("EditBox", "YRGBetterBagsExcludeInput", panel, "InputBoxTemplate")
        addInput:SetSize(250, 24)
        addInput:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 4, -8)
        addInput:SetAutoFocus(false)

        local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        addBtn:SetSize(84, 24)
        addBtn:SetPoint("LEFT", addInput, "RIGHT", 8, 0)
        addBtn:SetText("Add Item")

        local resetExclBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        resetExclBtn:SetSize(124, 24)
        resetExclBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
        resetExclBtn:SetText("Reset Defaults")

        local countText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        countText:SetPoint("LEFT", resetExclBtn, "RIGHT", 12, 0)
        countText:SetTextColor(0.75, 0.75, 0.75)

        local listBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        listBox:SetPoint("TOPLEFT", addInput, "BOTTOMLEFT", -4, -12)
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

        local useModernScroll = CreateScrollBoxListLinearView
            and ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar
            and CreateDataProvider

        local scrollBox, scrollBar, listScroll, listContent
        local legacyRows = {}

        if useModernScroll then
            scrollBox = CreateFrame("Frame", nil, listBox, "WowScrollBoxList")
            scrollBox:SetPoint("TOPLEFT", listBox, "TOPLEFT", 6, -6)
            scrollBox:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -6, 6)

            local sbTemplate = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("WowTrimScrollBar")
                and "WowTrimScrollBar" or "MinimalScrollBar"
            scrollBar = CreateFrame("EventFrame", nil, listBox, sbTemplate)
            scrollBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 6, 0)
            scrollBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 6, 0)

            local view = CreateScrollBoxListLinearView(0, 0, 0, 0)
            view:SetElementExtent(24)
            view:SetElementInitializer("Frame", function(row, elementData)
                if not row._yrgInit then
                    row._yrgInit = true
                    local stripe = row:CreateTexture(nil, "BACKGROUND")
                    stripe:SetAllPoints()
                    row.stripe = stripe

                    local hl = row:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints()
                    hl:SetColorTexture(1, 0.82, 0, 0.08)

                    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    nameText:SetPoint("LEFT", row, "LEFT", 8, 0)
                    nameText:SetPoint("RIGHT", row, "RIGHT", -84, 0)
                    nameText:SetJustifyH("LEFT")
                    row.nameText = nameText

                    local remBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    remBtn:SetSize(70, 20)
                    remBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    remBtn:SetText("Remove")
                    row.remBtn = remBtn
                end

                local isEven = (elementData.index % 2) == 0
                row.stripe:SetColorTexture(1, 1, 1, isEven and 0.05 or 0.015)
                row.nameText:SetText("|cff9d9d9d[" .. elementData.name .. "]|r")
                row.remBtn:SetScript("OnClick", function()
                    local mdb = YRG:GetModuleDB("BetterBagsModule")
                    if mdb and mdb.sellExclusionList then
                        mdb.sellExclusionList[elementData.name] = nil
                    end
                    if refreshFunc then refreshFunc() end
                end)
            end)
            view:SetPanExtent(48)
            ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
        else
            listScroll = CreateFrame("ScrollFrame", "YRGBetterBagsExcludeScroll", listBox, "UIPanelScrollFrameTemplate")
            listScroll:SetPoint("TOPLEFT", listBox, "TOPLEFT", 6, -6)
            listScroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -28, 6)
            listContent = CreateFrame("Frame", nil, listScroll)
            listContent:SetSize(480, 240)
            listScroll:SetScrollChild(listContent)
        end

        refreshFunc = function()
            local mdb = YRG:GetModuleDB("BetterBagsModule")
            if not mdb then return end
            mdb.sellExclusionList = mdb.sellExclusionList or CopyTable(DEFAULT_EXCLUSIONS)

            local sortedNames = {}
            for name, enabled in pairs(mdb.sellExclusionList) do
                if enabled and type(name) == "string" then
                    table.insert(sortedNames, name)
                end
            end
            table.sort(sortedNames)

            countText:SetText(string.format("%d %s protected", #sortedNames, (#sortedNames == 1) and "item" or "items"))

            if useModernScroll and scrollBox then
                local rows = {}
                for idx, itemName in ipairs(sortedNames) do
                    table.insert(rows, { index = idx, name = itemName })
                end
                scrollBox:SetDataProvider(CreateDataProvider(rows), true)
            elseif listContent then
                for _, row in ipairs(legacyRows) do row:Hide() end
                local rowW = math.max(400, (listBox:GetWidth() or 480) - 36)
                for idx, itemName in ipairs(sortedNames) do
                    local row = legacyRows[idx]
                    if not row then
                        row = CreateFrame("Frame", nil, listContent)
                        row:SetHeight(24)
                        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        nameText:SetPoint("LEFT", row, "LEFT", 8, 0)
                        nameText:SetJustifyH("LEFT")
                        row.nameText = nameText

                        local remBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                        remBtn:SetSize(70, 20)
                        remBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                        remBtn:SetText("Remove")
                        row.remBtn = remBtn
                        legacyRows[idx] = row
                    end
                    row:SetWidth(rowW)
                    row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -((idx - 1) * 24))
                    row.nameText:SetText("|cff9d9d9d[" .. itemName .. "]|r")
                    row.remBtn:SetScript("OnClick", function()
                        mdb.sellExclusionList[itemName] = nil
                        refreshFunc()
                    end)
                    row:Show()
                end
                listContent:SetSize(rowW, math.max(#sortedNames * 24, 190))
            end
        end

        local function AddItemFromInput()
            local raw = addInput:GetText()
            local clean = NormalizeItemName(raw)
            if clean then
                local mdb = YRG:GetModuleDB("BetterBagsModule")
                if mdb then
                    mdb.sellExclusionList = mdb.sellExclusionList or {}
                    mdb.sellExclusionList[clean] = true
                end
                addInput:SetText("")
                addInput:ClearFocus()
                refreshFunc()
            end
        end

        addBtn:SetScript("OnClick", AddItemFromInput)
        addInput:SetScript("OnEnterPressed", AddItemFromInput)

        addInput:SetScript("OnReceiveDrag", function()
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" then
                local name = (itemLink and NormalizeItemName(itemLink)) or (itemID and SafeGetItemInfo(itemID))
                if name then
                    local mdb = YRG:GetModuleDB("BetterBagsModule")
                    if mdb then
                        mdb.sellExclusionList = mdb.sellExclusionList or {}
                        mdb.sellExclusionList[name] = true
                    end
                    ClearCursor()
                    refreshFunc()
                end
            end
        end)

        if type(ChatEdit_InsertLink) == "function" then
            hooksecurefunc("ChatEdit_InsertLink", function(text)
                if addInput:IsVisible() and addInput:HasFocus() and text then
                    local name = NormalizeItemName(text)
                    if name then
                        addInput:SetText(name)
                    end
                end
            end)
        end

        resetExclBtn:SetScript("OnClick", function()
            local mdb = YRG:GetModuleDB("BetterBagsModule")
            if mdb then
                mdb.sellExclusionList = CopyTable(DEFAULT_EXCLUSIONS)
            end
            refreshFunc()
        end)
    end

    panel:SetScript("OnShow", function()
        BuildCanvas()
        if refreshFunc then refreshFunc() end
    end)

    panel.OnDefault = function()
        local mdb = YRG:GetModuleDB("BetterBagsModule")
        if mdb then
            mdb.sellExclusionList = CopyTable(DEFAULT_EXCLUSIONS)
        end
        if refreshFunc then refreshFunc() end
    end

    local exclCat = Settings.RegisterCanvasLayoutSubcategory(mainCategory, panel, "BetterBags: Exclusion List")
    Settings.RegisterAddOnCategory(exclCat)
    YRG:RegisterExtraCategory("BetterBagsExclusionList", exclCat)
end

SLASH_SEPARATEBAGSTRIP1 = "/bagstrip"
SLASH_SEPARATEBAGSTRIP2 = "/betterbags"
SlashCmdList.SEPARATEBAGSTRIP = function()
    print("|cffffd100YRG BetterBagsModule:|r " .. BetterBags:GetStatusMessage())
end

local function CollectKeysMatching(tbl, pattern, out, seen)
    if type(tbl) ~= "table" then return end
    for k, _ in pairs(tbl) do
        if type(k) == "string" and not seen[k] and k:lower():find(pattern) then
            seen[k] = true
            out[#out + 1] = k
        end
    end
end

local function FmtPt(frame)
    if not frame or type(frame.GetPoint) ~= "function" then return "n/a" end
    local pt, relTo, relPt, x, y = frame:GetPoint(1)
    local rn = (type(relTo) == "table" and relTo.GetName and relTo:GetName()) or (relTo and "anon") or "nil"
    return string.format("%s->%s.%s(%.1f,%.1f)", tostring(pt), tostring(rn), tostring(relPt), tonumber(x) or 0, tonumber(y) or 0)
end

SLASH_YRGBAGDEBUG1 = "/yrgbagdebug"
SlashCmdList.YRGBAGDEBUG = function()
    local f, b = ContainerFrameCombinedBags, GamepadBagBar
    local db = YRG:GetModuleDB("BetterBagsModule")
    local lines = {}
    local function Emit(s)
        lines[#lines + 1] = s
        print("|cffffd100[BagDbg]|r " .. s)
    end

    if not f then
        Emit("ContainerFrameCombinedBags=nil")
        return
    end

    local cols = (f.GetColumns and f:GetColumns()) or -1
    local rows = (f.GetRows and f:GetRows()) or -1
    local calcH = (f.CalculateHeight and f:CalculateHeight()) or -1
    local curH = (f.GetHeight and f:GetHeight()) or -1
    local fScale = (f.GetEffectiveScale and f:GetEffectiveScale()) or 1
    local fSelfScale = (f.GetScale and f:GetScale()) or 1
    local fStrata = (f.GetFrameStrata and f:GetFrameStrata()) or "?"
    local fLvl = (f.GetFrameLevel and f:GetFrameLevel()) or -1
    local bShown = b and b.IsShown and b:IsShown() or false
    local bMouse = b and b.IsMouseEnabled and b:IsMouseEnabled() or false
    local bScale = b and b.GetEffectiveScale and b:GetEffectiveScale() or -1
    local bStrata = (b and b.GetFrameStrata and b:GetFrameStrata()) or "?"
    local bLvl = (b and b.GetFrameLevel and b:GetFrameLevel()) or -1
    local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or -1
    local physW, physH = 0, 0
    if type(GetPhysicalScreenSize) == "function" then
        physW, physH = GetPhysicalScreenSize()
    end
    local combCVar = GetCVar and GetCVar("combinedBags")
    Emit(string.format("F:sh=%s strip=%s gp=%s pin=%s gap=%s cols=%d rows=%d calcH=%.0f curH=%.0f fSc=%.2f(s=%.2f) fZ=%s:%d Bar:sh=%s m=%s sc=%.2f bZ=%s:%d",
        tostring(f:IsShown()), tostring(db and db.controllerBagStrip), tostring(IsControllerUIActive()),
        tostring(db and db.bagPinAlignment), tostring(db and db.rowGap),
        cols, rows, calcH, curH, fScale, fSelfScale, tostring(fStrata), fLvl,
        tostring(bShown), tostring(bMouse), bScale, tostring(bStrata), bLvl))
    Emit(string.format("Env: phys=%dx%d uiSc=%.2f combinedBags=%s",
        tonumber(physW) or 0, tonumber(physH) or 0, uiScale, tostring(combCVar)))

    local fKeys, bKeys, fSeen, bSeen = {}, {}, {}, {}
    local pats = { "pad", "nav", "cursor", "focus", "grid", "inline", "bag", "reagent", "item", "slot", "pool", "calc", "row", "col", "height", "layout" }
    local mtF = getmetatable(f)
    for _, pat in ipairs(pats) do
        CollectKeysMatching(f, pat, fKeys, fSeen)
        if type(mtF) == "table" and type(mtF.__index) == "table" then
            CollectKeysMatching(mtF.__index, pat, fKeys, fSeen)
        end
    end
    if b then
        local mtB = getmetatable(b)
        for _, pat in ipairs({ "pad", "nav", "cursor", "focus", "bag" }) do
            CollectKeysMatching(b, pat, bKeys, bSeen)
            if type(mtB) == "table" and type(mtB.__index) == "table" then
                CollectKeysMatching(mtB.__index, pat, bKeys, bSeen)
            end
        end
    end
    Emit("KeysF=[" .. table.concat(fKeys, ",") .. "]")
    Emit("KeysB=[" .. table.concat(bKeys, ",") .. "]")

    local scNames = { "OnGamePadButtonDown", "OnKeyDown", "OnUpdate" }
    local fSc, bSc = {}, {}
    for _, sn in ipairs(scNames) do
        if f.GetScript and f:GetScript(sn) then fSc[#fSc + 1] = sn end
        if b and b.GetScript and b:GetScript(sn) then bSc[#bSc + 1] = sn end
    end
    Emit("ScriptsF=[" .. table.concat(fSc, ",") .. "] ScriptsB=[" .. table.concat(bSc, ",") .. "]")

    local itemSet, itemList = {}, {}
    if type(f.EnumerateValidItems) == "function" then
        for _, btn in f:EnumerateValidItems() do
            itemSet[btn] = true
            if type(btn.IsShown) ~= "function" or btn:IsShown() then
                itemList[#itemList + 1] = btn
            end
        end
    end
    local extraKids = {}
    for _, child in ipairs({ f:GetChildren() }) do
        if not itemSet[child] and type(child.IsShown) == "function" and child:IsShown() then
            local nm = (child.GetName and child:GetName())
                or (type(child.GetDebugName) == "function" and child:GetDebugName())
                or "anon"
            local me = (child.IsMouseEnabled and child:IsMouseEnabled()) and "M" or "-"
            local cx, cy = child:GetCenter()
            extraKids[#extraKids + 1] = string.format("%s(%s:%.0f,%.0f)", nm, me, tonumber(cx) or -1, tonumber(cy) or -1)
        end
    end
    if b then
        for _, child in ipairs({ b:GetChildren() }) do
            if type(child.IsShown) == "function" and child:IsShown() then
                local nm = (child.GetName and child:GetName())
                    or (type(child.GetDebugName) == "function" and child:GetDebugName())
                    or "bChild"
                local me = (child.IsMouseEnabled and child:IsMouseEnabled()) and "M" or "-"
                local cx, cy = child:GetCenter()
                extraKids[#extraKids + 1] = string.format("B:%s(%s:%.0f,%.0f)", nm, me, tonumber(cx) or -1, tonumber(cy) or -1)
            end
        end
    end
    Emit("Items=" .. #itemList .. " NonItems(" .. #extraKids .. "): " .. table.concat(extraKids, "; "))

    local sampleIdx = { 1, 2, math.min(cols > 0 and cols or 8, #itemList), math.min((cols > 0 and cols or 8) + 1, #itemList), #itemList }
    local seenIdx = {}
    for _, idx in ipairs(sampleIdx) do
        local btn = itemList[idx]
        if btn and not seenIdx[idx] then
            seenIdx[idx] = true
            local cx, cy = btn:GetCenter()
            local bw, bh = btn:GetSize()
            local pn = (btn.GetParent and btn:GetParent() and btn:GetParent().GetName and btn:GetParent():GetName()) or "anonP"
            Emit(string.format("I[%d] bag=%s slot=%s p=%s sz=%.0fx%.0f pt=%s ctr=(%.1f,%.1f)",
                idx, tostring(btn.GetBagID and btn:GetBagID()), tostring(btn.GetID and btn:GetID()),
                tostring(pn), tonumber(bw) or -1, tonumber(bh) or -1,
                FmtPt(btn), tonumber(cx) or -1, tonumber(cy) or -1))
        end
    end

    -- Inspect Reagent Bag Holder & integrated Reagent Bag slots
    local rBagID = GetReagentBagID()
    local tmpl = (f.itemButtonPool and f.itemButtonPool.GetTemplate and f.itemButtonPool:GetTemplate()) or "nil"
    local holderInfo = reagentBagHolder and string.format("sh=%s id=%s lvl=%s",
        tostring(reagentBagHolder:IsShown()), tostring(reagentBagHolder:GetID()), tostring(reagentBagHolder:GetFrameLevel())) or "nil"
    Emit(string.format("ReagentBagID=%s slots=%d tmpl=%s Holder=[%s] btnCount=%d",
        tostring(rBagID), GetBagNumSlotsSafe(rBagID), tostring(tmpl), holderInfo, #reagentSlotButtons))
    for i = 1, math.min(2, #reagentSlotButtons) do
        local rbtn = reagentSlotButtons[i]
        if rbtn then
            local info = GetReagentItemInfoSafe(rBagID, i)
            local rpn = (rbtn.GetParent and rbtn:GetParent() and rbtn:GetParent().GetName and rbtn:GetParent():GetName()) or "anonP"
            Emit(string.format("R[%d] sh=%s m=%s bag=%s id=%s p=%s pt=%s lvl=%s icon=%s",
                i, tostring(rbtn:IsShown()), tostring(rbtn.IsMouseEnabled and rbtn:IsMouseEnabled()),
                tostring(rbtn.GetBagID and rbtn:GetBagID()), tostring(rbtn.GetID and rbtn:GetID()),
                tostring(rpn), FmtPt(rbtn), tostring(rbtn.GetFrameLevel and rbtn:GetFrameLevel()),
                tostring(info)))
        end
    end
    local openCFs = {}
    for i = 1, 13 do
        local cf = _G["ContainerFrame" .. i]
        if cf and (cf:IsShown() or ((cf.GetID and cf:GetID()) == rBagID) or cf.bagID == rBagID) then
            local cid = (cf.GetID and cf:GetID()) or cf.bagID
            openCFs[#openCFs + 1] = string.format("CF%d(id=%s,sh=%s,sz=%s,lvl=%s)", i, tostring(cid), tostring(cf:IsShown()), tostring(cf.size), tostring(cf:GetFrameLevel()))
        end
    end
    Emit("OpenCFs=[" .. table.concat(openCFs, "; ") .. "]")

    if b and type(b.GetBagButton) == "function" then
        local maxBagID = math.max((ENDING_BAG_INDEX or 4), rBagID or 5)
        for id = (KEYRING_CONTAINER or -2), maxBagID do
            local btn = b:GetBagButton(id)
            if btn then
                local cx, cy = btn:GetCenter()
                local bw, bh = btn:GetSize()
                local bl, br, bb, bt = btn:GetLeft(), btn:GetRight(), btn:GetBottom(), btn:GetTop()
                Emit(string.format("Bag[%d] sh=%s col=%s m=%s s=%.2f eff=%.2f sz=%.0fx%.0f pt=%s ctr=(%.1f,%.1f) rect=%.0f..%.0f,%.0f..%.0f",
                    id, tostring(btn:IsShown()), tostring(btn.isCollapsed), tostring(btn.IsMouseEnabled and btn:IsMouseEnabled()),
                    (btn.GetScale and btn:GetScale()) or 1,
                    (btn.GetEffectiveScale and btn:GetEffectiveScale()) or -1,
                    tonumber(bw) or -1, tonumber(bh) or -1,
                    FmtPt(btn), tonumber(cx) or -1, tonumber(cy) or -1,
                    tonumber(bl) or -1, tonumber(br) or -1, tonumber(bb) or -1, tonumber(bt) or -1))
            end
        end
    end

    local cAuto = GetCVar and GetCVar("GamePadCursorAutoEnable")
    local cCtr = GetCVar and GetCVar("GamePadCursorCentering")
    local cTgt = GetCVar and GetCVar("GamePadCursorForTargeting")
    local cStk = GetCVar and GetCVar("GamePadCursorAutoDisableSticks")
    Emit(string.format("CVars: AutoEnable=%s Centering=%s Targeting=%s Sticks=%s SoftCursor=%s",
        tostring(cAuto), tostring(cCtr), tostring(cTgt), tostring(cStk),
        tostring(SoftCursor and SoftCursor.IsShown and SoftCursor:IsShown())))

    if db then
        db._lastDebug = lines
    end
end

YRG:RegisterModule("BetterBagsModule", BetterBags)
