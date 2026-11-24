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
        emptyCellLocation = "TOP_LEFT", -- "TOP_LEFT", "BOTTOM_RIGHT", "DYNAMIC"
        separateAmmoBagRow = false,
        unlockBagFrame = true,
        bagFramePos = nil,
        dualZoneControllerNav = false,
        navEdgeBehavior = "STOP", -- "STOP", "WRAP_ROW", "WRAP_FLOW"
        shrinkBagButtonsToFit = false,
        includeReagentBagInCombined = true,
        reagentBagTintPurple = true,
        dimGreyItems = true,
        autoSortOnOpen = true,
        autoOpenClams = true,
        waylaidCrateCosts = true,
        waylaidNameIDMap = {},
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
local sectionDividers = {}
local customBags = {
    frame = nil,
    holder = nil,
    gridAnchor = nil,
    searchBox = nil,
    sortBtn = nil,
    freeText = nil,
    moneyText = nil,
    buttons = {},
    isOpen = false,
    openedInThisCall = false,
    pendingLayout = false,
    searchQuery = "",
}
local lastSortTime = 0

local function IsControllerUIActive()
    if C_InputInterfaceStyle and type(C_InputInterfaceStyle.GetCurrentStyle) == "function"
        and Enum and Enum.InputDeviceInterfaceType then
        local ok, style = pcall(C_InputInterfaceStyle.GetCurrentStyle)
        if ok and style ~= nil then
            return style == Enum.InputDeviceInterfaceType.Gamepad
        end
    end
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

local nativeBagGeom = setmetatable({}, { __mode = "k" })
local ApplyUnifiedBagLayout
local ScheduleUnifiedBagLayout
local ApplyAndScheduleUnifiedBagLayout

local function RunWithApplyingGuard(fn)
    if applying then return false, "already applying" end
    applying = true
    local ok, resOrErr = xpcall(fn, function(err)
        if type(CallErrorHandler) == "function" then
            CallErrorHandler(err)
        elseif type(geterrorhandler) == "function" then
            local handler = geterrorhandler()
            if type(handler) == "function" then
                pcall(handler, err)
            end
        end
        return err
    end)
    applying = false
    return ok, resOrErr
end

local NAV_EDGE_OPTIONS = {
    { value = "STOP", label = "Stop at Edges (Default)", tooltip = "Left and Right D-pad movement stops cleanly at row and bag-strip edges." },
    { value = "WRAP_ROW", label = "Wrap Within Row", tooltip = "Pressing Left or Right past a row or bag-strip edge wraps around to the opposite side of that same row." },
    { value = "WRAP_FLOW", label = "Wrap Across Rows (Items) / Strip", tooltip = "In the item grid, pressing Left or Right past a row edge moves to the adjacent row; in the bag strip, wraps around." },
}

local EMPTY_CELL_OPTIONS = {
    { value = "TOP_LEFT", label = "Top-Left (Default)", tooltip = "Standard Blizzard Combined Bags layout starting from the bottom-right so any unused cells appear at the top-left." },
    { value = "BOTTOM_RIGHT", label = "Bottom-Right", tooltip = "Fills the top rows completely across all columns and moves any unused cells to the bottom-right." },
    { value = "DYNAMIC", label = "Dynamic (Best Fit: 10 / 9 / 8 Cols)", tooltip = "Favors Bottom-Right empty cells and automatically selects 10, 9, or 8 columns to minimize wasted slots across your inventory (including merged Reagent Bag slots)." },
}

local function GetEmptyCellMode(db)
    local mode = db and db.emptyCellLocation
    if mode == "BOTTOM_RIGHT" or mode == "DYNAMIC" then
        return mode
    end
    return "TOP_LEFT"
end

local function ChooseDynamicColumns(baseCols, countA, countB, countC)
    baseCols = (type(baseCols) == "number" and baseCols >= 1) and math.floor(baseCols) or 10
    local maxCols = math.min(baseCols, 10)
    if maxCols <= 8 then
        return maxCols
    end

    local bestCols, bestEmpty, bestRows
    for _, c in ipairs({ 10, 9, 8 }) do
        if c <= maxCols then
            local empty, rows = 0, 0
            for _, cnt in ipairs({ countA or 0, countB or 0, countC or 0 }) do
                if type(cnt) == "number" and cnt > 0 then
                    local r = math.ceil(cnt / c)
                    rows = rows + r
                    empty = empty + (r * c - cnt)
                end
            end
            if not bestCols
                or empty < bestEmpty
                or (empty == bestEmpty and rows < bestRows)
                or (empty == bestEmpty and rows == bestRows and c > bestCols) then
                bestCols, bestEmpty, bestRows = c, empty, rows
            end
        end
    end
    return bestCols or maxCols
end

local function IsAmmoOrQuiverBag(bagID)
    local backpack = BACKPACK_CONTAINER or 0
    if type(bagID) ~= "number" or bagID <= backpack or bagID == KEYRING_CONTAINER or bagID == GetReagentBagID() then
        return false
    end
    local freeFn = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if type(freeFn) == "function" then
        local ok, _, bagFamily = pcall(freeFn, bagID)
        if ok and type(bagFamily) == "number" and not YRG.IsSecret(bagFamily) and bagFamily > 0 then
            if bit and type(bit.band) == "function" then
                if bit.band(bagFamily, 3) ~= 0 then return true end
            elseif (math.floor(bagFamily) % 4) ~= 0 then
                return true
            end
        end
    end
    local invFn = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
    if type(invFn) == "function" and type(GetInventoryItemLink) == "function" then
        local okInv, invID = pcall(invFn, bagID)
        if okInv and type(invID) == "number" then
            local link = YRG.SafeString(GetInventoryItemLink("player", invID), nil)
            if link then
                local instFn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
                if type(instFn) == "function" then
                    local okI, _, _, _, _, _, classID, subClassID = pcall(instFn, link)
                    if okI and classID == 11 and (subClassID == 2 or subClassID == 3 or subClassID == 0) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function SortItemEntriesByGrid(entries, stepY)
    if not entries or #entries <= 1 then return end
    local minY
    for _, entry in ipairs(entries) do
        if entry.y and (not minY or entry.y < minY) then
            minY = entry.y
        end
    end
    local refMinY = minY or 0
    local halfStepY = math.max((stepY or 42) * 0.5, 4)
    for _, entry in ipairs(entries) do
        entry.rowKey = math.floor((((entry.y or refMinY) - refMinY) / halfStepY) + 0.5)
    end
    table.sort(entries, function(a, b)
        if a.rowKey ~= b.rowKey then return a.rowKey < b.rowKey end
        return (a.x or 0) > (b.x or 0)
    end)
end

local function MeasureAndSortItemEntries(entries, frame, itemW, itemH)
    local maxX, minY
    local xs, ys = {}, {}
    for _, entry in ipairs(entries) do
        local x, y = entry.x, entry.y
        if x and y then
            if not maxX or x > maxX then maxX = x end
            if not minY or y < minY then minY = y end
            xs[#xs + 1] = x
            ys[#ys + 1] = y
        end
    end

    local geom = nativeBagGeom[frame]
    if not geom then
        geom = {}
        nativeBagGeom[frame] = geom
    end
    if minY and minY < 20 and (
        not geom.baseY
        or math.abs(minY - geom.baseY) < 0.4
        or not geom.padOffset
        or geom.padOffset == 0
        or math.abs(minY - (geom.baseY + geom.padOffset)) >= 0.4
    ) then
        geom.baseY = minY
        geom.padOffset = 0
    end
    if maxX and math.abs(maxX) <= 2 then
        geom.baseX = maxX
    end

    local stepX = geom.stepX or (itemW + 5)
    local stepY = geom.stepY or (itemH + 5)
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
            geom.stepX = minDx
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
            geom.stepY = minDy
        end
    end

    SortItemEntriesByGrid(entries, stepY)

    return geom.baseX or 0, geom.baseY or 4, stepX, stepY, minY
end

local function ApplyCombinedBagWidth(frame, baseCols, effCols, stepX)
    if not frame or IsFrameProtectedOrForbidden(frame) then return end
    if type(frame.CalculateWidth) ~= "function" or type(frame.SetWidth) ~= "function" then return end
    local calcW = YRG.SafeNumber(frame:CalculateWidth(), 0)
    if calcW <= 0 then return end

    local geom = nativeBagGeom[frame]
    if not geom then
        geom = {}
        nativeBagGeom[frame] = geom
    end
    geom.baseWidth = calcW

    local deltaCols = math.max(0, (baseCols or effCols) - effCols)
    local targetW = math.max(calcW - deltaCols * stepX, 220)
    local curW = YRG.SafeNumber(frame.GetWidth and frame:GetWidth(), 0)
    if math.abs(curW - targetW) >= 0.4 then
        frame:SetWidth(targetW)
    end

    if BagItemSearchBox and not IsFrameProtectedOrForbidden(BagItemSearchBox) then
        if geom.searchW == nil then
            geom.searchW = YRG.SafeNumber(BagItemSearchBox.GetWidth and BagItemSearchBox:GetWidth(), nil)
        end
        local numPts = (BagItemSearchBox.GetNumPoints and BagItemSearchBox:GetNumPoints()) or 0
        if numPts <= 1 and geom.searchW and type(BagItemSearchBox.SetWidth) == "function" then
            local desiredSW = (deltaCols > 0)
                and math.min(geom.searchW, math.max(100, targetW - 118))
                or geom.searchW
            local curSW = YRG.SafeNumber(BagItemSearchBox.GetWidth and BagItemSearchBox:GetWidth(), 0)
            if math.abs(curSW - desiredSW) >= 0.4 then
                BagItemSearchBox:SetWidth(desiredSW)
            end
        end
    end
end

local bagDragState = {
    dragging = false,
    hooked = setmetatable({}, { __mode = "k" }),
}

local function SaveNativeBagPoint(frame)
    local geom = nativeBagGeom[frame]
    if not geom then
        geom = {}
        nativeBagGeom[frame] = geom
    end
    if not geom.nativePoint and type(frame.GetPoint) == "function" then
        local pt, relTo, relPt, xOfs, yOfs = frame:GetPoint(1)
        if pt and relTo ~= UIParent then
            geom.nativePoint = { pt = pt, relTo = relTo, relPt = relPt or pt, x = xOfs or 0, y = yOfs or 0 }
        end
    end
    return geom
end

local function RestoreNativeBagPoint(frame)
    if not frame or InCombatLockdown() or IsFrameProtectedOrForbidden(frame) then return end
    local geom = nativeBagGeom[frame]
    if geom and geom.nativePoint then
        local p = geom.nativePoint
        frame:ClearAllPoints()
        frame:SetPoint(p.pt, p.relTo, p.relPt, p.x, p.y)
    end
end

local function SetupBagFrameDrag(frame)
    if not frame or IsFrameProtectedOrForbidden(frame) then return end

    local function CanDragNow(recordFail)
        local db = YRG:GetModuleDB("BetterBagsModule")
        local ok = db and db.enabled and db.unlockBagFrame ~= false
            and not IsControllerUIActive()
            and not InCombatLockdown()
            and not IsFrameProtectedOrForbidden(frame)
        if not ok and recordFail and frame == customBags.frame and db then
            db._lastDragFailReason = string.format("en=%s ulk=%s ctrl=%s cbt=%s prot=%s",
                tostring(db.enabled),
                tostring(db.unlockBagFrame),
                tostring(IsControllerUIActive()),
                tostring(InCombatLockdown()),
                tostring(IsFrameProtectedOrForbidden(frame)))
        end
        return ok
    end

    local function OnDragStart()
        if not CanDragNow(true) then return end
        if frame == customBags.frame then
            customBags:HideSecureProxy()
        end
        SaveNativeBagPoint(frame)
        if type(frame.SetDontSavePosition) == "function" then pcall(frame.SetDontSavePosition, frame, true) end
        if type(frame.SetMovable) == "function" then frame:SetMovable(true) end
        if type(frame.SetClampedToScreen) == "function" then frame:SetClampedToScreen(true) end
        bagDragState.dragging = true
        pcall(frame.StartMoving, frame)
    end

    local function OnDragStop()
        if not bagDragState.dragging then return end
        bagDragState.dragging = false
        pcall(frame.StopMovingOrSizing, frame)
        if InCombatLockdown() or IsControllerUIActive() or IsFrameProtectedOrForbidden(frame) then return end
        local uiTop = YRG.SafeNumber(UIParent and UIParent.GetTop and UIParent:GetTop(), nil)
        local fLeft = YRG.SafeNumber(frame.GetLeft and frame:GetLeft(), nil)
        local fTop = YRG.SafeNumber(frame.GetTop and frame:GetTop(), nil)
        if uiTop and fLeft and fTop then
            local uiScale = math.max(YRG.SafeNumber(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale(), 1), 0.01)
            local fScale = math.max(YRG.SafeNumber(frame.GetEffectiveScale and frame:GetEffectiveScale(), 1), 0.01)
            local db = YRG:GetModuleDB("BetterBagsModule")
            if db and db.unlockBagFrame ~= false then
                db.bagFramePos = {
                    x = fLeft,
                    y = fTop - uiTop * (uiScale / fScale),
                }
            end
        end
    end

    local function AttachDrag(widget)
        if not widget or bagDragState.hooked[widget] or IsFrameProtectedOrForbidden(widget) then return end
        bagDragState.hooked[widget] = true
        if type(widget.EnableMouse) == "function" then
            pcall(widget.EnableMouse, widget, true)
        end
        if type(widget.RegisterForDrag) == "function" then
            pcall(widget.RegisterForDrag, widget, "LeftButton")
        end
        if type(widget.HookScript) == "function" then
            pcall(widget.HookScript, widget, "OnDragStart", OnDragStart)
            pcall(widget.HookScript, widget, "OnDragStop", OnDragStop)
            pcall(widget.HookScript, widget, "OnMouseUp", function(_, mouseBtn)
                if mouseBtn == "LeftButton" and bagDragState.dragging then
                    OnDragStop()
                end
            end)
        end
    end

    AttachDrag(frame)
    if frame.TitleContainer then
        AttachDrag(frame.TitleContainer)
    end

    local fTop = YRG.SafeNumber(frame.GetTop and frame:GetTop(), nil)
    local itemSet = {}
    if type(frame.EnumerateValidItems) == "function" then
        for _, btn in frame:EnumerateValidItems() do itemSet[btn] = true end
    end
    local excluded = {
        [frame.CloseButton or false] = true,
        [_G.ContainerFrameCombinedBagsPortraitButton or false] = true,
        [frame.PortraitContainer or false] = true,
        [_G.BagItemSearchBox or false] = true,
        [_G.BagItemAutoSortButton or false] = true,
        [frame.MoneyFrame or false] = true,
        [frame.FilterIcon or false] = true,
        [_G.GamepadBagBar or false] = true,
        [customBags.holder or false] = true,
        [customBags.searchBox or false] = true,
        [customBags.sortBtn or false] = true,
        [sectionDividers.bagBar and sectionDividers.bagBar.frame or false] = true,
        [sectionDividers.ammo and sectionDividers.ammo.frame or false] = true,
        [sectionDividers.customAmmo and sectionDividers.customAmmo.frame or false] = true,
        [sectionDividers.customReag and sectionDividers.customReag.frame or false] = true,
    }
    local function ScanHeaderChildren(parentFrame)
        if not parentFrame or type(parentFrame.GetChildren) ~= "function" then return end
        for _, child in ipairs({ parentFrame:GetChildren() }) do
            if not excluded[child] and not itemSet[child] and not IsFrameProtectedOrForbidden(child) then
                local cTop = YRG.SafeNumber(child.GetTop and child:GetTop(), nil)
                local cW = YRG.SafeNumber(child.GetWidth and child:GetWidth(), 0)
                local mouseOn = child.IsMouseEnabled and child:IsMouseEnabled()
                if (child == frame.TitleContainer or mouseOn) and cW >= 30
                    and (not fTop or not cTop or math.abs(cTop - fTop) <= 44) then
                    AttachDrag(child)
                end
            end
        end
    end
    ScanHeaderChildren(frame)
    if frame.TitleContainer then
        ScanHeaderChildren(frame.TitleContainer)
    end
end

local function ApplyNonControllerBagUnlock(frame)
    if not frame or IsControllerUIActive() or InCombatLockdown() or IsFrameProtectedOrForbidden(frame) then
        return
    end
    local db = YRG:GetModuleDB("BetterBagsModule")
    local unlocked = db and db.enabled and db.unlockBagFrame ~= false
    if not unlocked then
        bagDragState.dragging = false
        if type(frame.SetMovable) == "function" then frame:SetMovable(false) end
        RestoreNativeBagPoint(frame)
        return
    end

    SaveNativeBagPoint(frame)
    if frame == customBags.frame then
        if type(frame.EnableMouse) == "function" then frame:EnableMouse(true) end
        if type(frame.SetDontSavePosition) == "function" then pcall(frame.SetDontSavePosition, frame, true) end
    end
    if type(frame.SetMovable) == "function" then frame:SetMovable(true) end
    if type(frame.SetClampedToScreen) == "function" then frame:SetClampedToScreen(true) end
    SetupBagFrameDrag(frame)

    if bagDragState.dragging or (not frame:IsShown() and frame ~= customBags.frame) then return end
    local pos = db.bagFramePos
    if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
        local pt, relTo, relPt, curX, curY = frame:GetPoint(1)
        if pt ~= "TOPLEFT" or relTo ~= UIParent or relPt ~= "TOPLEFT"
            or type(curX) ~= "number" or type(curY) ~= "number"
            or math.abs(curX - pos.x) >= 0.5 or math.abs(curY - pos.y) >= 0.5 then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x, pos.y)
        end
    end
end

local function UpdateSectionDividerOverlay(key, frame, anchor, frameLevel, baseX, divY, widthPx, alpha)
    local divKey = (key == true) and "ammo" or tostring(key)
    local isCustom = (customBags and customBags.frame and frame == customBags.frame) and true or false
    local targetParent = isCustom and customBags.frame or UIParent
    local entry = sectionDividers[divKey]
    if not entry then
        local gName = "YRGSectionDivider_" .. divKey
        local divF = CreateFrame("Frame", gName, targetParent)
        divF:EnableMouse(false)
        if divF.SetMouseClickEnabled then divF:SetMouseClickEnabled(false) end
        if divF.SetMouseMotionEnabled then divF:SetMouseMotionEnabled(false) end
        local topTex = divF:CreateTexture(nil, "OVERLAY")
        topTex:SetPoint("TOPLEFT", divF, "TOPLEFT", 0, 0)
        topTex:SetPoint("TOPRIGHT", divF, "TOPRIGHT", 0, 0)
        topTex:SetHeight(2)
        if type(topTex.SetSnapToPixelGrid) == "function" then pcall(topTex.SetSnapToPixelGrid, topTex, false) end
        if type(topTex.SetTexelSnappingBias) == "function" then pcall(topTex.SetTexelSnappingBias, topTex, 0) end
        local botTex = divF:CreateTexture(nil, "OVERLAY")
        botTex:SetPoint("TOPLEFT", topTex, "BOTTOMLEFT", 0, 0)
        botTex:SetPoint("TOPRIGHT", topTex, "BOTTOMRIGHT", 0, 0)
        botTex:SetHeight(1)
        if type(botTex.SetSnapToPixelGrid) == "function" then pcall(botTex.SetSnapToPixelGrid, botTex, false) end
        if type(botTex.SetTexelSnappingBias) == "function" then pcall(botTex.SetTexelSnappingBias, botTex, 0) end
        entry = { frame = divF, topTex = topTex, botTex = botTex }
        sectionDividers[divKey] = entry
    end
    local divF, topTex, botTex = entry.frame, entry.topTex, entry.botTex
    if divF:GetParent() ~= targetParent then
        divF:SetParent(targetParent)
    end
    local scaleFactor = 1
    if targetParent == UIParent then
        local ancScale = math.max(YRG.SafeNumber(anchor and anchor.GetEffectiveScale and anchor:GetEffectiveScale(), 1), 0.01)
        local uiScale = math.max(YRG.SafeNumber(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale(), 1), 0.01)
        scaleFactor = math.max(ancScale / uiScale, 0.01)
        divF:SetScale(scaleFactor)
    else
        divF:SetScale(1)
    end
    if type(divF.SetFrameStrata) == "function" and frame.GetFrameStrata then
        divF:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    end
    local topH = 2 / scaleFactor
    local botH = 1 / scaleFactor
    local lineAlpha = (type(alpha) == "number") and alpha or 0.50
    topTex:SetDrawLayer("OVERLAY")
    topTex:SetHeight(topH)
    topTex:SetColorTexture(0.02, 0.01, 0.005, math.min(0.85, lineAlpha + 0.08))
    botTex:SetDrawLayer("OVERLAY")
    botTex:SetHeight(botH)
    botTex:SetColorTexture(0.84, 0.72, 0.52, math.max(0.08, lineAlpha * 0.32))
    divF:SetFrameLevel(frameLevel + 5)
    divF:ClearAllPoints()
    local snappedBottomY = math.floor(((divY or 0) * scaleFactor) - 1.5 + 0.5) / scaleFactor
    divF:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", baseX, snappedBottomY)
    divF:SetSize(widthPx, topH + botH)
    divF:SetShown(isCustom or ((frame.IsShown and frame:IsShown()) and true or false))
end

local function HideSectionDivider(key)
    local divKey = (key == true) and "ammo" or tostring(key)
    local entry = sectionDividers[divKey]
    if entry and entry.frame then
        entry.frame:Hide()
    end
end

local function HideAmmoOverlay()
    HideSectionDivider("ammo")
end

local function PlaceItemSectionGrid(entries, anchor, baseX, sectionBaseY, stepX, stepY, cols, offset, zoneName, outGrid, outBtnMap, rowOffset)
    offset = offset or 0
    rowOffset = rowOffset or 0
    for i, entry in ipairs(entries) do
        local index = (i - 1) + offset
        local row = math.floor(index / cols)
        local colFromRight = index % cols
        local col = cols - colFromRight
        local tx = baseX - colFromRight * stepX
        local ty = sectionBaseY + row * stepY
        local pt, relTo, relPt, curX, curY = entry.button:GetPoint(1)
        if pt ~= "BOTTOMRIGHT" or relTo ~= anchor or relPt ~= "TOPRIGHT"
            or type(curX) ~= "number" or type(curY) ~= "number"
            or math.abs(curX - tx) >= 0.4 or math.abs(curY - ty) >= 0.4 then
            entry.button:ClearAllPoints()
            entry.button:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", tx, ty)
        end
        if outGrid and outBtnMap then
            local gRow = row + rowOffset
            if not outGrid[gRow] then outGrid[gRow] = {} end
            outGrid[gRow][col] = entry.button
            outBtnMap[entry.button] = { zone = zoneName, row = gRow, col = col }
        end
    end
end

local dualZoneData = {
    columns = 0,
    itemRows = 0,
    bagRows = 0,
    itemGrid = {},
    bagGrid = {},
    btnMap = {},
}
local dualZoneBindingOwner = nil
local dualZoneNavSink = nil
local dualZoneSyncFrame = nil
local dualZoneBindingsArmed = false
local dualZoneProbeFailed = false
local dualZoneNeedsRearm = false
local dualZonePendingClear = false
local dualZoneSnHooked = false
local settingDualZoneBindingsNow = false
local dualZoneBlockedByClient = false
local dualZoneLastMoveAt = {}
local dualZoneRepeat = { key = nil, nextAt = 0, canPollKeyDown = false }

local function SafeNavCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

local function SafeNavCallMulti(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function ClearDualZoneData()
    dualZoneData.columns = 0
    dualZoneData.itemRows = 0
    dualZoneData.bagRows = 0
    dualZoneData.itemGrid = {}
    dualZoneData.bagGrid = {}
    dualZoneData.btnMap = {}
end

local function ClearDualZoneBindings()
    dualZoneRepeat.key = nil
    dualZoneNeedsRearm = false
    dualZonePendingClear = false
    if dualZoneSyncFrame and type(dualZoneSyncFrame.Hide) == "function" then
        dualZoneSyncFrame:Hide()
    end
    if dualZoneBindingsArmed and dualZoneBindingOwner and type(ClearOverrideBindings) == "function" then
        if not (InCombatLockdown and InCombatLockdown()) then
            settingDualZoneBindingsNow = true
            pcall(ClearOverrideBindings, dualZoneBindingOwner)
            settingDualZoneBindingsNow = false
            dualZoneBindingsArmed = false
        end
    end
end

local function ScheduleClearDualZoneBindings()
    dualZoneRepeat.key = nil
    dualZoneNeedsRearm = false
    if dualZoneSyncFrame and type(dualZoneSyncFrame.Hide) == "function" then
        dualZoneSyncFrame:Hide()
    end
    if not dualZoneBindingsArmed then
        dualZonePendingClear = false
        return
    end
    if C_Timer and type(C_Timer.After) == "function" then
        if not dualZonePendingClear then
            dualZonePendingClear = true
            C_Timer.After(0, function()
                if dualZonePendingClear then
                    ClearDualZoneBindings()
                end
            end)
        end
    else
        ClearDualZoneBindings()
    end
end

local function ResetDualZoneNavState(immediateClear)
    ClearDualZoneData()
    if immediateClear then
        ClearDualZoneBindings()
    else
        ScheduleClearDualZoneBindings()
    end
end

local function HideDividerOverlay()
    HideSectionDivider("bagBar")
    HideAmmoOverlay()
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

local function EnsureDualZoneFrames()
    if not dualZoneBindingOwner then
        dualZoneBindingOwner = CreateFrame("Frame", "YRGBetterBagsBindingOwner", UIParent)
        dualZoneBindingOwner:Show()
    end
    if not dualZoneNavSink then
        dualZoneNavSink = CreateFrame("Button", "YRGBetterBagsNavSink", dualZoneBindingOwner)
        dualZoneNavSink:RegisterForClicks("AnyDown", "AnyUp")
        dualZoneNavSink:SetSize(1, 1)
        dualZoneNavSink:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
        dualZoneNavSink:EnableMouse(false)
        if dualZoneNavSink.SetMouseClickEnabled then dualZoneNavSink:SetMouseClickEnabled(false) end
        if dualZoneNavSink.SetMouseMotionEnabled then dualZoneNavSink:SetMouseMotionEnabled(false) end
        dualZoneNavSink:Show()
    end
    if not dualZoneSyncFrame then
        dualZoneSyncFrame = CreateFrame("Frame")
        dualZoneSyncFrame:Hide()
    end
end

local SyncDualZoneBindings

local cachedSnStrategy = nil

local function IsFrameWidget(v)
    return type(v) == "table" and type(v.GetObjectType) == "function"
end

local function IsPanelInfoLike(v)
    if type(v) ~= "table" or type(v.GetObjectType) == "function" then return false end
    if type(v.buttons) == "table" or type(v.buttonGroups) == "table" then return true end
    if IsFrameWidget(v.frame) and not IsFrameWidget(v.button) then return true end
    return false
end

local function InspectObjShallow(v, maxKeys)
    if v == nil then return "nil" end
    local tv = type(v)
    if tv ~= "table" then return tv .. "(" .. tostring(v) .. ")" end
    if IsFrameWidget(v) then
        local okN, nm = pcall(v.GetDebugName, v)
        if not okN or type(nm) ~= "string" or nm == "" then
            okN, nm = pcall(v.GetName, v)
        end
        local okT, ot = pcall(v.GetObjectType, v)
        return "Frame<" .. tostring(okT and ot or "?") .. ":" .. tostring(okN and nm or "anon") .. ">"
    end
    local keys, n = {}, #v
    local lim = maxKeys or 16
    for k in pairs(v) do
        if type(k) == "string" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    local truncated = (#keys > lim)
    while #keys > lim do
        keys[#keys] = nil
    end
    return "tbl(n=" .. tostring(n) .. ",k=[" .. table.concat(keys, ",") .. (truncated and ",..." or "") .. "])"
end

local function ResolveSmartNavButtonCandidates(sn, targetBtn, activeFrame)
    local panels, panelSeen = {}, {}
    local cands, candPanels, candSeen = {}, {}, {}

    local function AddPanel(p)
        if type(p) == "table" and not IsFrameWidget(p) and not panelSeen[p] then
            panelSeen[p] = true
            panels[#panels + 1] = p
        end
    end

    local function AddCand(info, pInfo)
        if type(info) ~= "table" or info == sn or IsPanelInfoLike(info) or candSeen[info] then
            return
        end
        candSeen[info] = true
        cands[#cands + 1] = info
        candPanels[info] = pInfo
    end

    local f, bar = ContainerFrameCombinedBags, GamepadBagBar
    AddPanel(sn.activeInfo)
    AddPanel(SafeNavCall(sn.GetPanelInfo, sn, activeFrame))
    AddPanel(SafeNavCall(sn.GetPanelInfo, sn, f))
    if bar then AddPanel(SafeNavCall(sn.GetPanelInfo, sn, bar)) end
    if type(sn.activePanels) == "table" then
        for _, p in pairs(sn.activePanels) do AddPanel(p) end
    end

    local function CollectFromFind(...)
        local ok, r1, r2, r3 = SafeNavCallMulti(sn.FindButton, sn, ...)
        if not ok then return end
        local rets = { r1, r2, r3 }
        local detectedPanel = nil
        for i = 1, 3 do
            local rv = rets[i]
            if IsPanelInfoLike(rv) then
                detectedPanel = rv
                AddPanel(rv)
            end
        end
        for i = 1, 3 do
            local rv = rets[i]
            if type(rv) == "table" and not IsPanelInfoLike(rv) and not IsFrameWidget(rv) and rv ~= sn then
                AddCand(rv, detectedPanel or rv.panelInfo or sn.activeInfo)
            end
        end
    end

    CollectFromFind(targetBtn)
    if sn.activeInfo then CollectFromFind(sn.activeInfo, targetBtn) end
    if activeFrame then CollectFromFind(activeFrame, targetBtn) end
    if bar then
        CollectFromFind(bar, targetBtn)
        local barPanel = SafeNavCall(sn.GetPanelInfo, sn, bar)
        if barPanel then CollectFromFind(barPanel, targetBtn) end
    end

    if type(sn.hookedButtons) == "table" and sn.hookedButtons[targetBtn] then
        local hb = sn.hookedButtons[targetBtn]
        if type(hb) == "table" and not IsFrameWidget(hb) then
            AddCand(hb, hb.panelInfo or sn.activeInfo)
        end
    end

    local function ScanContainerForBtn(tbl, pOwner, depth)
        if type(tbl) ~= "table" or depth > 2 then return end
        if tbl[targetBtn] and type(tbl[targetBtn]) == "table" and not IsFrameWidget(tbl[targetBtn]) then
            AddCand(tbl[targetBtn], pOwner)
        end
        local checked = 0
        for _, v in pairs(tbl) do
            checked = checked + 1
            if checked > 400 then break end
            if type(v) == "table" and not IsFrameWidget(v) and v ~= pOwner then
                if v.button == targetBtn or v.frame == targetBtn or v[1] == targetBtn then
                    AddCand(v, v.panelInfo or pOwner)
                elseif depth < 2 and (type(v.buttons) == "table" or v == tbl.buttons or v == tbl.buttonGroups or v == tbl.groups) then
                    ScanContainerForBtn(v, pOwner, depth + 1)
                end
            end
        end
    end

    if #cands == 0 then
        for _, p in ipairs(panels) do
            ScanContainerForBtn(p, p, 0)
            if type(p.buttons) == "table" then ScanContainerForBtn(p.buttons, p, 1) end
            if type(p.buttonGroups) == "table" then ScanContainerForBtn(p.buttonGroups, p, 1) end
        end
    end

    return cands, candPanels, panels
end

local function TryFocusSmartNavButton(targetBtn, prevBtn, captureTrace)
    if not targetBtn then return false, nil end
    local sn = _G.SmartNavigation
    if not sn then return false, nil end

    local function IsFocusedNow()
        return SafeNavCall(sn.GetCurrentButton, sn) == targetBtn
    end
    if IsFocusedNow() then return true, nil end

    local trace = captureTrace and {} or nil
    local function TryCall(label, fn, ...)
        if type(fn) ~= "function" then return false end
        local ok, r1 = pcall(fn, ...)
        local nowBtn = SafeNavCall(sn.GetCurrentButton, sn)
        if trace then
            trace[#trace + 1] = string.format("%s=>ok=%s,ret=%s,cur=%s", label, tostring(ok), tostring(r1), InspectObjShallow(nowBtn))
        end
        return nowBtn == targetBtn
    end

    local activeFrame = SafeNavCall(sn.GetActiveFrame, sn)

    if cachedSnStrategy and not captureTrace then
        local s = cachedSnStrategy
        if s.kind == "CALL_FIND_1" and type(sn[s.method]) == "function" then
            local hb = (type(sn.hookedButtons) == "table") and sn.hookedButtons[targetBtn]
            local cand = (type(hb) == "table" and not IsFrameWidget(hb)) and hb or nil
            if not cand then
                local ok, r1, r2 = SafeNavCallMulti(sn.FindButton, sn, targetBtn)
                if ok then
                    cand = (type(r1) == "table" and not IsPanelInfoLike(r1) and not IsFrameWidget(r1) and r1)
                        or (type(r2) == "table" and not IsPanelInfoLike(r2) and not IsFrameWidget(r2) and r2)
                end
            end
            if cand and TryCall(s.method, sn[s.method], sn, cand) then
                if s.updatePos then SafeNavCall(sn.UpdateCursorPosition, sn) end
                return true, nil
            end
        elseif s.kind == "TARGET_FRAME" and type(sn.SetTargetButtonForFrame) == "function" then
            local fr = (targetBtn.GetParent and targetBtn:GetParent()) == GamepadBagBar and GamepadBagBar or (activeFrame or ContainerFrameCombinedBags)
            pcall(sn.SetTargetButtonForFrame, sn, fr, targetBtn)
            if s.reselect then SafeNavCall(sn.ReselectCurrentButton, sn) end
            if IsFocusedNow() then
                SafeNavCall(sn.UpdateCursorPosition, sn)
                return true, nil
            end
        end
    end

    local cands, candPanels, panels = ResolveSmartNavButtonCandidates(sn, targetBtn, activeFrame)
    if trace then
        trace[#trace + 1] = string.format("meta:cands=%d,panels=%d,valid=%s,inGrp=%s",
            #cands, #panels, tostring(SafeNavCall(sn.IsButtonValid, sn, targetBtn)),
            tostring(SafeNavCall(sn.IsButtonInCurrentFocusGroup, sn, targetBtn)))
    end

    -- Tier 1: TrySelectButton / SelectButton with resolved buttonInfo candidates
    for idx, cand in ipairs(cands) do
        local pInfo = candPanels[cand] or sn.activeInfo
        if TryCall("TrySelInfo[" .. idx .. "]", sn.TrySelectButton, sn, cand) then
            cachedSnStrategy = { kind = "CALL_FIND_1", method = "TrySelectButton" }
            return true, nil
        end
        if TryCall("SelInfo[" .. idx .. "]", sn.SelectButton, sn, cand) then
            cachedSnStrategy = { kind = "CALL_FIND_1", method = "SelectButton", updatePos = true }
            SafeNavCall(sn.UpdateCursorPosition, sn)
            return true, nil
        end
        if TryCall("TrySelInfoTrue[" .. idx .. "]", sn.TrySelectButton, sn, cand, true) then
            return true, nil
        end
        if TryCall("SelInfoTrue[" .. idx .. "]", sn.SelectButton, sn, cand, true) then
            SafeNavCall(sn.UpdateCursorPosition, sn)
            return true, nil
        end
        if pInfo then
            if TryCall("TrySelPInfo[" .. idx .. "]", sn.TrySelectButton, sn, pInfo, cand) then
                return true, nil
            end
            if TryCall("SelPInfo[" .. idx .. "]", sn.SelectButton, sn, pInfo, cand) then
                SafeNavCall(sn.UpdateCursorPosition, sn)
                return true, nil
            end
        end
    end

    -- Tier 2: 2-arg SetTargetButtonForFrame(frame, button) (+ optional ReselectCurrentButton)
    local targetParent = (targetBtn.GetParent and targetBtn:GetParent())
    local framesToTry, seenFrames = {}, {}
    for _, fr in ipairs({ targetParent, activeFrame, ContainerFrameCombinedBags, GamepadBagBar }) do
        if fr and not seenFrames[fr] then
            seenFrames[fr] = true
            framesToTry[#framesToTry + 1] = fr
        end
    end
    for i, fr in ipairs(framesToTry) do
        if TryCall("SetTgtFrame[" .. i .. "]", sn.SetTargetButtonForFrame, sn, fr, targetBtn) then
            cachedSnStrategy = { kind = "TARGET_FRAME", reselect = false }
            SafeNavCall(sn.UpdateCursorPosition, sn)
            return true, nil
        end
        SafeNavCall(sn.ReselectCurrentButton, sn)
        if IsFocusedNow() then
            cachedSnStrategy = { kind = "TARGET_FRAME", reselect = true }
            SafeNavCall(sn.UpdateCursorPosition, sn)
            return true, nil
        end
    end

    -- Tier 3: Cross-panel switch if candidate belongs to GamepadBagBar / ContainerFrameCombinedBags
    for idx, cand in ipairs(cands) do
        local cp = candPanels[cand]
        if cp and cp ~= sn.activeInfo and IsFrameWidget(cp.frame)
            and (cp.frame == ContainerFrameCombinedBags or cp.frame == GamepadBagBar) then
            SafeNavCall(sn.SetActiveFrame, sn, cp.frame)
            if TryCall("CrossTrySel[" .. idx .. "]", sn.TrySelectButton, sn, cand)
                or TryCall("CrossSel[" .. idx .. "]", sn.SelectButton, sn, cand) then
                SafeNavCall(sn.UpdateCursorPosition, sn)
                return true, nil
            end
        end
    end

    -- Tier 4: SetLastButtonForPanelInfo + ReselectCurrentButton
    for pi, pInfo in ipairs(panels) do
        for ci, cand in ipairs(cands) do
            SafeNavCall(sn.SetLastButtonForPanelInfo, sn, pInfo, cand)
            SafeNavCall(sn.ReselectCurrentButton, sn)
            if IsFocusedNow() then
                SafeNavCall(sn.UpdateCursorPosition, sn)
                return true, nil
            end
            if ci == 1 and pi == 1 and trace then
                trace[#trace + 1] = "SetLastCand=>cur=" .. InspectObjShallow(SafeNavCall(sn.GetCurrentButton, sn))
            end
        end
        SafeNavCall(sn.SetLastButtonForPanelInfo, sn, pInfo, targetBtn)
        SafeNavCall(sn.ReselectCurrentButton, sn)
        if IsFocusedNow() then
            SafeNavCall(sn.UpdateCursorPosition, sn)
            return true, nil
        end
    end

    -- Tier 5: Direct raw targetBtn fallbacks
    for _, mName in ipairs({ "TrySelectButton", "SelectButton" }) do
        if TryCall(mName .. "(raw)", sn[mName], sn, targetBtn)
            or TryCall(mName .. "(raw,true)", sn[mName], sn, targetBtn, true) then
            SafeNavCall(sn.UpdateCursorPosition, sn)
            return true, nil
        end
    end
    if sn.activeInfo then
        if TryCall("TrySel(aInfo,raw)", sn.TrySelectButton, sn, sn.activeInfo, targetBtn)
            or TryCall("Sel(aInfo,raw)", sn.SelectButton, sn, sn.activeInfo, targetBtn) then
            SafeNavCall(sn.UpdateCursorPosition, sn)
            return true, nil
        end
    end

    -- Restore activeFrame if cross-panel probe touched it without focusing
    if activeFrame and SafeNavCall(sn.GetActiveFrame, sn) ~= activeFrame then
        SafeNavCall(sn.SetActiveFrame, sn, activeFrame)
    end

    return false, trace
end

local function RowMinMaxCols(rowTbl, maxCols)
    if not rowTbl then return nil, nil end
    local minC, maxC
    for c = 1, maxCols do
        if rowTbl[c] then
            if not minC then minC = c end
            maxC = c
        end
    end
    return minC, maxC
end

local function FindClosestBagInRow(bagRowTbl, targetCol)
    if not bagRowTbl or #bagRowTbl == 0 then return nil end
    local bestEntry, bestDist
    for _, entry in ipairs(bagRowTbl) do
        local d = math.abs(entry.colPos - targetCol)
        if not bestDist or d < bestDist then
            bestDist = d
            bestEntry = entry
        end
    end
    return bestEntry and bestEntry.button or nil
end

local function ComputeDualZoneTarget(info, dirKey, edgeMode)
    if not info then return nil end
    edgeMode = edgeMode or "STOP"
    local cols = dualZoneData.columns or 0
    local itemRows = dualZoneData.itemRows or 0
    local bagRows = dualZoneData.bagRows or 0
    local itemGrid = dualZoneData.itemGrid
    local bagGrid = dualZoneData.bagGrid
    if cols < 1 then return nil end

    if info.zone == "ITEMS" then
        local r, c = info.row, info.col
        local rowTbl = itemGrid[r]
        if not rowTbl then return nil end

        if dirKey == "PADDLEFT" then
            for tc = c - 1, 1, -1 do
                if rowTbl[tc] then return rowTbl[tc] end
            end
            local _, maxC = RowMinMaxCols(rowTbl, cols)
            if edgeMode == "WRAP_ROW" then
                return (maxC and maxC ~= c) and rowTbl[maxC] or nil
            elseif edgeMode == "WRAP_FLOW" then
                for tr = r + 1, itemRows - 1 do
                    local _, rMax = RowMinMaxCols(itemGrid[tr], cols)
                    if rMax then return itemGrid[tr][rMax] end
                end
                local _, bMax = RowMinMaxCols(itemGrid[0], cols)
                if bMax and itemGrid[0][bMax] ~= rowTbl[c] then return itemGrid[0][bMax] end
            end
            return nil
        elseif dirKey == "PADDRIGHT" then
            for tc = c + 1, cols do
                if rowTbl[tc] then return rowTbl[tc] end
            end
            local minC, _ = RowMinMaxCols(rowTbl, cols)
            if edgeMode == "WRAP_ROW" then
                return (minC and minC ~= c) and rowTbl[minC] or nil
            elseif edgeMode == "WRAP_FLOW" then
                for tr = r - 1, 0, -1 do
                    local rMin, _ = RowMinMaxCols(itemGrid[tr], cols)
                    if rMin then return itemGrid[tr][rMin] end
                end
                for tr = itemRows - 1, 0, -1 do
                    local tMin, _ = RowMinMaxCols(itemGrid[tr], cols)
                    if tMin and itemGrid[tr][tMin] ~= rowTbl[c] then return itemGrid[tr][tMin] end
                end
            end
            return nil
        elseif dirKey == "PADDDOWN" then
            for tr = r - 1, 0, -1 do
                if itemGrid[tr] and itemGrid[tr][c] then
                    return itemGrid[tr][c]
                end
            end
            return nil
        elseif dirKey == "PADDUP" then
            for tr = r + 1, itemRows - 1 do
                if itemGrid[tr] and itemGrid[tr][c] then
                    return itemGrid[tr][c]
                end
            end
            -- Topmost item in column c -> enter Zone 2 (Bag Strip) at same or closest column
            if bagRows > 0 and bagGrid[bagRows - 1] then
                return FindClosestBagInRow(bagGrid[bagRows - 1], c)
            end
            return nil
        end
    elseif info.zone == "BAGS" then
        local br, idx, colPos = info.row, info.idx, info.colPos
        local bagRowTbl = bagGrid[br]
        if not bagRowTbl or #bagRowTbl == 0 then return nil end

        if dirKey == "PADDLEFT" then
            if idx > 1 then
                return bagRowTbl[idx - 1].button
            end
            if (edgeMode == "WRAP_ROW" or edgeMode == "WRAP_FLOW") and #bagRowTbl > 1 then
                return bagRowTbl[#bagRowTbl].button
            end
            return nil
        elseif dirKey == "PADDRIGHT" then
            if idx < #bagRowTbl then
                return bagRowTbl[idx + 1].button
            end
            if (edgeMode == "WRAP_ROW" or edgeMode == "WRAP_FLOW") and #bagRowTbl > 1 then
                return bagRowTbl[1].button
            end
            return nil
        elseif dirKey == "PADDUP" then
            if br > 0 and bagGrid[br - 1] then
                return FindClosestBagInRow(bagGrid[br - 1], colPos)
            end
            return nil
        elseif dirKey == "PADDDOWN" then
            if br < bagRows - 1 and bagGrid[br + 1] then
                return FindClosestBagInRow(bagGrid[br + 1], colPos)
            end
            -- Drop directly onto the topmost populated item in this column
            local targetCol = math.max(1, math.min(cols, math.floor(colPos + 0.5)))
            for tr = itemRows - 1, 0, -1 do
                if itemGrid[tr] and itemGrid[tr][targetCol] then
                    return itemGrid[tr][targetCol]
                end
            end
            -- Fallback if column has no items (e.g. partial tiny bag): nearest column in highest row
            for tr = itemRows - 1, 0, -1 do
                local bestBtn, bestDist
                if itemGrid[tr] then
                    for tc = 1, cols do
                        if itemGrid[tr][tc] then
                            local d = math.abs(tc - targetCol)
                            if not bestDist or d < bestDist then
                                bestDist = d
                                bestBtn = itemGrid[tr][tc]
                            end
                        end
                    end
                end
                if bestBtn then return bestBtn end
            end
            return nil
        end
    end

    return nil
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

local function CaptureSmartNavProbe(curBtn, targetBtn, trace)
    local sn = _G.SmartNavigation
    if not sn then return { "SmartNavigation=nil" } end
    local out = {}
    local activeFrame = SafeNavCall(sn.GetActiveFrame, sn)
    local fPanel = ContainerFrameCombinedBags and SafeNavCall(sn.GetPanelInfo, sn, ContainerFrameCombinedBags)
    local bPanel = GamepadBagBar and SafeNavCall(sn.GetPanelInfo, sn, GamepadBagBar)

    out[#out + 1] = string.format("Active=%s | Cur=%s | Tgt=%s",
        InspectObjShallow(activeFrame), InspectObjShallow(curBtn), InspectObjShallow(targetBtn))
    out[#out + 1] = "sn.currentButton=" .. InspectObjShallow(sn.currentButton)
    out[#out + 1] = "sn.activeInfo=" .. InspectObjShallow(sn.activeInfo)
    if sn.activeInfo and type(sn.activeInfo.buttons) == "table" then
        out[#out + 1] = "activeInfo.buttons=" .. InspectObjShallow(sn.activeInfo.buttons, 10)
    end
    out[#out + 1] = "fPanel=" .. InspectObjShallow(fPanel) .. " | bPanel=" .. InspectObjShallow(bPanel)

    if type(sn.FindButton) == "function" then
        local okC, c1, c2 = SafeNavCallMulti(sn.FindButton, sn, curBtn)
        local okT, t1, t2 = SafeNavCallMulti(sn.FindButton, sn, targetBtn)
        out[#out + 1] = string.format("FindCur(ok=%s): r1=%s r2=%s", tostring(okC), InspectObjShallow(c1), InspectObjShallow(c2))
        out[#out + 1] = string.format("FindTgt(ok=%s): r1=%s r2=%s", tostring(okT), InspectObjShallow(t1), InspectObjShallow(t2))
    end
    if type(sn.hookedButtons) == "table" then
        out[#out + 1] = "hookedCur=" .. InspectObjShallow(sn.hookedButtons[curBtn])
            .. " | hookedTgt=" .. InspectObjShallow(sn.hookedButtons[targetBtn])
    end
    if type(trace) == "table" and #trace > 0 then
        out[#out + 1] = "Attempts: " .. table.concat(trace, " ; ")
    end
    return out
end

local function ExecuteDualZoneMove(key)
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled or db.controllerBagStrip == false or db.dualZoneControllerNav == false then
        ClearDualZoneBindings()
        return false
    end
    local sn = _G.SmartNavigation
    local curBtn = sn and SafeNavCall(sn.GetCurrentButton, sn)
    local info = curBtn and dualZoneData.btnMap[curBtn]
    if not info then
        SyncDualZoneBindings()
        return false
    end

    local targetBtn = ComputeDualZoneTarget(info, key, db.navEdgeBehavior or "STOP")
    if not targetBtn or targetBtn == curBtn then
        dualZoneRepeat.key = nil
        return false
    end

    local focused = TryFocusSmartNavButton(targetBtn, curBtn, false)
    if not focused then
        local _, trace = TryFocusSmartNavButton(targetBtn, curBtn, true)
        dualZoneProbeFailed = true
        db._lastDualZoneProbe = CaptureSmartNavProbe(curBtn, targetBtn, trace)
        ClearDualZoneBindings()
        print("|cffffd100YRG BetterBags:|r SmartNavigation did not expose a direct focus setter; reverted to native D-pad navigation. Run /yrgbagdebug watch or inspect SavedVariables.")
        return false
    end
    return true
end

SyncDualZoneBindings = function()
    if InCombatLockdown and InCombatLockdown() then
        dualZoneRepeat.key = nil
        return
    end

    local db = YRG:GetModuleDB("BetterBagsModule")
    local f, bar = ContainerFrameCombinedBags, GamepadBagBar
    local sn = _G.SmartNavigation
    local searchFocused = BagItemSearchBox and type(BagItemSearchBox.HasFocus) == "function" and BagItemSearchBox:HasFocus()
    local activeFrame = sn and SafeNavCall(sn.GetActiveFrame, sn)
    local isBagActiveFrame = (activeFrame == f) or (bar ~= nil and activeFrame == bar)

    local activeOk = db and db.enabled
        and db.controllerBagStrip ~= false
        and db.dualZoneControllerNav ~= false
        and not dualZoneProbeFailed
        and not dualZoneBlockedByClient
        and IsControllerUIActive()
        and f and f:IsShown()
        and not searchFocused
        and sn and SafeNavCall(sn.IsShown, sn)
        and isBagActiveFrame
        and dualZoneData.columns > 0

    local curBtn = activeOk and SafeNavCall(sn.GetCurrentButton, sn) or nil
    local inManagedZones = activeOk and curBtn ~= nil and dualZoneData.btnMap[curBtn] ~= nil

    if inManagedZones then
        dualZonePendingClear = false
        EnsureDualZoneFrames()
        if (not dualZoneBindingsArmed or dualZoneNeedsRearm) and dualZoneBindingOwner and dualZoneNavSink then
            dualZoneNeedsRearm = false
            settingDualZoneBindingsNow = true
            pcall(ClearOverrideBindings, dualZoneBindingOwner)
            for _, key in ipairs({ "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }) do
                pcall(SetOverrideBindingClick, dualZoneBindingOwner, true, key, dualZoneNavSink:GetName(), key)
            end
            settingDualZoneBindingsNow = false
            if not dualZoneBlockedByClient then
                dualZoneBindingsArmed = true
            else
                ClearDualZoneBindings()
            end
        end
    else
        dualZoneRepeat.key = nil
        dualZoneNeedsRearm = false
        if dualZoneBindingsArmed and dualZoneBindingOwner and type(ClearOverrideBindings) == "function" then
            settingDualZoneBindingsNow = true
            pcall(ClearOverrideBindings, dualZoneBindingOwner)
            settingDualZoneBindingsNow = false
            dualZoneBindingsArmed = false
        end
    end
end

local function InitDualZoneHandlers()
    EnsureDualZoneFrames()
    local sn = _G.SmartNavigation
    if sn and not dualZoneSnHooked then
        dualZoneSnHooked = true
        for _, mName in ipairs({ "ActivateBinding", "HandlePanelOpen", "SetActiveFrame", "RefreshButtonGroups" }) do
            if type(sn[mName]) == "function" then
                hooksecurefunc(sn, mName, function()
                    if dualZoneBindingsArmed and ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                        dualZoneNeedsRearm = true
                    end
                end)
            end
        end
    end
    if not dualZoneNavSink._yrgInit then
        dualZoneNavSink._yrgInit = true
        dualZoneNavSink:SetScript("OnClick", function(_, key, down)
            if down == false then
                dualZoneLastMoveAt[key] = nil
                if dualZoneRepeat.key == key then
                    dualZoneRepeat.key = nil
                end
                return
            end
            if InCombatLockdown and InCombatLockdown() then
                dualZoneRepeat.key = nil
                return
            end
            local now = (type(GetTime) == "function") and GetTime() or 0
            if dualZoneLastMoveAt[key] and (now - dualZoneLastMoveAt[key]) < 0.06 then
                return
            end
            dualZoneLastMoveAt[key] = now

            local moved = ExecuteDualZoneMove(key)
            if moved and down == true then
                local canPoll = false
                if type(IsKeyDown) == "function" then
                    local okKd, kd = pcall(IsKeyDown, key)
                    canPoll = (okKd and kd == true)
                end
                dualZoneRepeat.key = key
                dualZoneRepeat.nextAt = now + 0.30
                dualZoneRepeat.canPollKeyDown = canPoll
            elseif not moved then
                dualZoneRepeat.key = nil
            end
        end)
    end
    if not dualZoneSyncFrame._yrgInit then
        dualZoneSyncFrame._yrgInit = true
        dualZoneSyncFrame:SetScript("OnUpdate", function()
            if not (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
                ClearDualZoneBindings()
                return
            end
            SyncDualZoneBindings()
            local repKey = dualZoneRepeat.key
            if repKey and dualZoneBindingsArmed and not (InCombatLockdown and InCombatLockdown()) then
                if dualZoneRepeat.canPollKeyDown and type(IsKeyDown) == "function" then
                    local okKd, kd = pcall(IsKeyDown, repKey)
                    if okKd and not kd then
                        dualZoneRepeat.key = nil
                        return
                    end
                end
                local now = (type(GetTime) == "function") and GetTime() or 0
                if now >= dualZoneRepeat.nextAt then
                    local moved = ExecuteDualZoneMove(repKey)
                    if moved then
                        dualZoneRepeat.nextAt = now + 0.075
                    else
                        dualZoneRepeat.key = nil
                    end
                end
            end
        end)
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
        ResetDualZoneNavState()
        ResetControllerBagButtonScales()
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
            local baseCols = ContainerFrameCombinedBags.GetColumns and ContainerFrameCombinedBags:GetColumns() or 10
            local geom = nativeBagGeom[ContainerFrameCombinedBags]
            if geom and geom.baseWidth then
                ApplyCombinedBagWidth(ContainerFrameCombinedBags, baseCols, baseCols, geom.stepX or 42)
            end
        end
        return
    end

    local frame, bar = ContainerFrameCombinedBags, GamepadBagBar
    if not frame or not bar or not frame:IsShown() then
        HideDividerOverlay()
        ResetDualZoneNavState()
        return
    end
    if not IsControllerUIActive() then
        HideDividerOverlay()
        ResetDualZoneNavState()
        ResetControllerBagButtonScales()
        return
    end
    if IsFrameProtectedOrForbidden(frame) or IsFrameProtectedOrForbidden(bar) then
        HideDividerOverlay()
        ResetDualZoneNavState()
        return
    end

    local columns = frame:GetColumns()
    if not frame.itemButtonPool or type(frame.itemButtonPool.GetTemplate) ~= "function" then
        HideDividerOverlay()
        ResetDualZoneNavState()
        return
    end
    local template = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(frame.itemButtonPool:GetTemplate())
    if not template or not template.width or not template.height then
        HideDividerOverlay()
        ResetDualZoneNavState()
        return
    end

    local anchor = frame.MoneyFrame
    if not anchor or IsFrameProtectedOrForbidden(anchor) or columns < 1 then
        HideDividerOverlay()
        ResetDualZoneNavState()
        return
    end

    local bags = CollectControllerBagButtons(bar, false)
    if not bags or #bags == 0 then
        HideDividerOverlay()
        ResetDualZoneNavState()
        return
    end

    local items, ammoEntries, stdEntries = {}, {}, {}
    local sepAmmo = (db.separateAmmoBagRow == true)
    local itemW, itemH = template.width, template.height
    for _, button in frame:EnumerateValidItems() do
        if IsFrameProtectedOrForbidden(button) then
            HideDividerOverlay()
            ResetDualZoneNavState()
            return
        end
        if type(button.IsShown) ~= "function" or button:IsShown() then
            local bID = button:GetBagID()
            local bag = bar:GetBagButton(bID)
            if not bag or bag.isCollapsed ~= true then
                local point, relativeTo, relativePoint, x, y = button:GetPoint(1)
                if point ~= "BOTTOMRIGHT" or relativeTo ~= anchor
                    or relativePoint ~= "TOPRIGHT"
                    or type(x) ~= "number" or type(y) ~= "number" then
                    HideDividerOverlay()
                    ResetDualZoneNavState()
                    return
                end
                local entry = { button = button, x = x, y = y }
                items[#items + 1] = entry
                if sepAmmo and IsAmmoOrQuiverBag(bID) then
                    ammoEntries[#ammoEntries + 1] = entry
                else
                    stdEntries[#stdEntries + 1] = entry
                end
            end
        end
    end

    local baseX, baseY, stepX, stepY = MeasureAndSortItemEntries(items, frame, itemW, itemH)
    SortItemEntriesByGrid(ammoEntries, stepY)
    SortItemEntriesByGrid(stdEntries, stepY)

    local baseCols = columns
    local emptyMode = GetEmptyCellMode(db)
    local hasAmmoSection = sepAmmo and #ammoEntries > 0
    local effCols = (emptyMode == "DYNAMIC" and #items > 0)
        and ChooseDynamicColumns(baseCols, #stdEntries, hasAmmoSection and #ammoEntries or 0)
        or baseCols
    local columns = effCols

    local gap = db.rowGap or 8
    local pinAlign = db.bagPinAlignment or "RIGHT"
    local ammoGap = hasAmmoSection and 16 or 0
    local ammoBottomPad = hasAmmoSection and 6 or 0
    if nativeBagGeom[frame] then
        nativeBagGeom[frame].padOffset = ammoBottomPad
    end
    local ammoBaseY = baseY + ammoBottomPad
    local ammoRows = hasAmmoSection and math.ceil(#ammoEntries / columns) or 0
    local stdRows = math.ceil(#stdEntries / columns)
    local itemRows = ammoRows + stdRows
    local bagRows = math.ceil(#bags / columns)
    local ammoOffset = (hasAmmoSection and emptyMode ~= "TOP_LEFT")
        and ((ammoRows * columns) - #ammoEntries)
        or 0
    local stdOffset = (emptyMode ~= "TOP_LEFT" and #stdEntries > 0)
        and ((stdRows * columns) - #stdEntries)
        or 0
    local height = frame:CalculateHeight()
        + (itemRows + bagRows - frame:GetRows()) * stepY + gap + ammoGap + ammoBottomPad

    local newItemGrid, newBagGrid, newBtnMap = {}, {}, {}

    local ok = RunWithApplyingGuard(function()
        ApplyCombinedBagWidth(frame, baseCols, columns, stepX)
        if hasAmmoSection then
            PlaceItemSectionGrid(ammoEntries, anchor, baseX, ammoBaseY, stepX, stepY, columns, ammoOffset, "ITEMS", newItemGrid, newBtnMap, 0)
        end
        local stdBaseY = ammoBaseY + ammoRows * stepY + ammoGap
        PlaceItemSectionGrid(stdEntries, anchor, baseX, stdBaseY, stepX, stepY, columns, stdOffset, "ITEMS", newItemGrid, newBtnMap, ammoRows)

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

        local shrinkBagsToFit = (db.shrinkBagButtonsToFit == true)
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

            -- Optional Steamdeck / 1280x800 sizing fix (off by default to keep native button scales on PC)
            if shrinkBagsToFit then
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
            else
                if type(button.SetScale) == "function" then
                    local curSelfScale = YRG.SafeNumber(button.GetScale and button:GetScale(), 1)
                    if math.abs(curSelfScale - 1) >= 0.005 then
                        button:SetScale(1)
                    end
                end
            end

            -- Center bag button horizontally & vertically inside its column cell in anchor space,
            -- then scale to bag button space so Gamepad directional focus never drifts diagonally.
            local cellCenterX = baseX - colFromRight * stepX - (itemW / 2)
            local cellCenterY = ammoBaseY + (itemRows + bagRows - 1 - rowIdx) * stepY + gap + ammoGap + (itemH / 2)
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

            if not newBagGrid[rowIdx] then newBagGrid[rowIdx] = {} end
            local colPos = columns - colFromRight
            table.insert(newBagGrid[rowIdx], { button = button, colPos = colPos })
        end

        for br = 0, bagRows - 1 do
            local bagRowTbl = newBagGrid[br]
            if bagRowTbl then
                table.sort(bagRowTbl, function(a, b) return a.colPos < b.colPos end)
                for k, entry in ipairs(bagRowTbl) do
                    newBtnMap[entry.button] = { zone = "BAGS", row = br, idx = k, colPos = entry.colPos }
                end
            end
        end

        dualZoneData.columns = columns
        dualZoneData.itemRows = itemRows
        dualZoneData.bagRows = bagRows
        dualZoneData.itemGrid = newItemGrid
        dualZoneData.bagGrid = newBagGrid
        dualZoneData.btnMap = newBtnMap

        local curH = YRG.SafeNumber(frame.GetHeight and frame:GetHeight(), 0)
        if math.abs(curH - height) >= 0.4 then
            frame:SetHeight(height)
        end

        if db.showDivider ~= false and itemRows > 0 then
            local bagDivY = ammoBaseY + itemRows * stepY + ammoGap + (gap - (stepY - itemH)) / 2
            UpdateSectionDividerOverlay("bagBar", frame, anchor, frameLevel, baseX, bagDivY, (columns - 1) * stepX + itemW, 0.50)
        else
            HideSectionDivider("bagBar")
        end

        if hasAmmoSection then
            local divY = ammoBaseY + (ammoRows - 1) * stepY + itemH + (ammoGap + (stepY - itemH)) / 2
            UpdateSectionDividerOverlay(true, frame, anchor, frameLevel, baseX, divY, (columns - 1) * stepX + itemW, 0.50)
        else
            HideAmmoOverlay()
        end
    end)

    -- Never override/mutate Blizzard's SmartNavigation from insecure addon code,
    -- which taints Gamepad PromptedBinding -> UseContainerItem() (ADDON_ACTION_FORBIDDEN).
    ResetDualZoneNavState(true)

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

local function HasBagSlotItem(bagID, slot)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        return type(info) == "table" and info.iconFileID ~= nil
    elseif type(GetContainerItemInfo) == "function" then
        local icon = GetContainerItemInfo(bagID, slot)
        return icon ~= nil
    end
    return false
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
        -- Plain OVERLAY Texture strictly inside the cell interior (zero frame hit-testing, native quality border intact)
        local fill = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        fill:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
        fill:SetColorTexture(0.34, 0.16, 0.56, 0.14)
        btn._yrgPurpleTint = fill
    end
    btn._yrgPurpleTint:SetShown(not hasItem)
end

local ExecuteBagSort
local TriggerAutoSortIfEnabled
local ScheduleClamOpen

local function IsTransferFrameOpenForReagents()
    if IsModifierKeyDown and IsModifierKeyDown() then return true end
    if InRepairMode and InRepairMode() then return true end
    local frames = {
        _G.MerchantFrame,
        _G.BankFrame,
        _G.MailFrame,
        _G.SendMailFrame,
        _G.TradeFrame,
        _G.AuctionFrame,
        _G.AuctionHouseFrame,
        _G.ItemSocketingFrame,
        _G.GuildBankFrame,
        _G.VoidStorageFrame,
        _G.ItemUpgradeFrame,
        _G.ScrappingMachineFrame,
    }
    for _, f in ipairs(frames) do
        if f and type(f.IsShown) == "function" and f:IsShown() then
            return true
        end
    end
    return false
end

local function SetAttrIfChanged(btn, attr, val)
    if btn:GetAttribute(attr) ~= val then
        btn:SetAttribute(attr, val)
    end
end

local function GetContainerItemInfoSafe(bagID, slot)
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
                info.isBound and true or false,
                YRG.SafeString(info.itemName, nil)
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
                isBound and true or false,
                nil
        end
    end
    return nil
end

local function DoesCustomItemMatchSearch(itemLink, itemID, itemName, query)
    if not query or query == "" then return true end
    local label = YRG.SafeString(itemName, nil)
    if not label and itemLink then
        label = YRG.SafeString(itemLink:match("%[(.-)%]"), nil)
    end
    if not label and (itemLink or itemID) then
        local infoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if type(infoFn) == "function" then
            local okN, nm = pcall(infoFn, itemLink or itemID)
            if okN then
                label = YRG.SafeString(nm, nil)
            end
        end
    end
    if not label then return false end
    return label:lower():find(query, 1, true) ~= nil
end

function customBags:GetEmptySlotAlphas()
    if self.emptyIconAlpha and self.emptyNormAlpha then
        return self.emptyIconAlpha, self.emptyNormAlpha
    end
    local iconAlpha, normAlpha = nil, nil
    local function ProbeBtn(b)
        if not b or b.hasItem then return false end
        local ic = b.icon or b.Icon
        local nt = (type(b.GetNormalTexture) == "function" and b:GetNormalTexture()) or b.NormalTexture
        local ia = ic and type(ic.GetAlpha) == "function" and YRG.SafeNumber(ic:GetAlpha(), 1) or 1
        local na = nt and type(nt.GetAlpha) == "function" and YRG.SafeNumber(nt:GetAlpha(), 1) or 1
        if ia > 0.05 and ia < 0.99 then
            iconAlpha = ia
        end
        if na > 0.05 and na < 0.99 then
            normAlpha = na
        end
        return iconAlpha ~= nil or normAlpha ~= nil
    end
    if ContainerFrameCombinedBags and type(ContainerFrameCombinedBags.EnumerateValidItems) == "function" then
        pcall(function()
            for k, v in ContainerFrameCombinedBags:EnumerateValidItems() do
                local b = (type(v) == "table" and v) or (type(k) == "table" and k) or nil
                if b and ProbeBtn(b) then
                    break
                end
            end
        end)
    end
    if not iconAlpha and not normAlpha then
        for i = 1, 36 do
            local b = _G["ContainerFrame1Item" .. i]
            if b and ProbeBtn(b) then break end
        end
    end
    if iconAlpha or normAlpha then
        self.emptyIconAlpha = iconAlpha or 0.45
        self.emptyNormAlpha = normAlpha or 0.50
        return self.emptyIconAlpha, self.emptyNormAlpha
    end
    return 0.45, 0.50
end

local greyWashOverlays = setmetatable({}, { __mode = "k" })
local nativeGreyAppliedBtns = setmetatable({}, { __mode = "k" })
local nativeGreyHookedFrames = setmetatable({}, { __mode = "k" })

local function ApplyPoorItemVisualStyle(btn, isPoorGrey, restoreIconAlpha, forceLockedDesat)
    if not btn or IsFrameProtectedOrForbidden(btn) then return end
    local iconTex = btn.icon or btn.Icon
    local wash = greyWashOverlays[btn]

    if isPoorGrey then
        if iconTex then
            if type(iconTex.SetDesaturated) == "function" then
                pcall(iconTex.SetDesaturated, iconTex, true)
            end
            if type(iconTex.SetVertexColor) == "function" then
                pcall(iconTex.SetVertexColor, iconTex, 0.72, 0.72, 0.72)
            end
            if type(iconTex.SetAlpha) == "function" then
                pcall(iconTex.SetAlpha, iconTex, 0.95)
            end
        end
        if not wash then
            wash = btn:CreateTexture(nil, "ARTWORK", nil, 2)
            if iconTex then
                wash:SetAllPoints(iconTex)
            else
                wash:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
                wash:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            end
            wash:SetColorTexture(0.45, 0.45, 0.45, 0.22)
            greyWashOverlays[btn] = wash
        end
        wash:SetAlpha(0.95)
        wash:Show()
        if btn.IconBorder and type(btn.IconBorder.SetAlpha) == "function" then
            pcall(btn.IconBorder.SetAlpha, btn.IconBorder, 0.70)
        end
    else
        if wash then
            wash:Hide()
        end
        if iconTex then
            if forceLockedDesat ~= nil and type(iconTex.SetDesaturated) == "function" then
                pcall(iconTex.SetDesaturated, iconTex, forceLockedDesat)
            end
            if type(iconTex.SetVertexColor) == "function" then
                pcall(iconTex.SetVertexColor, iconTex, 1, 1, 1)
            end
            if restoreIconAlpha ~= nil and type(iconTex.SetAlpha) == "function" then
                pcall(iconTex.SetAlpha, iconTex, restoreIconAlpha)
            end
        end
        if btn.IconBorder and type(btn.IconBorder.SetAlpha) == "function" then
            pcall(btn.IconBorder.SetAlpha, btn.IconBorder, 1)
        end
    end
end

local function ApplyGreyVisualsToNativeFrame(frame, enabled)
    if not frame or IsFrameProtectedOrForbidden(frame)
        or (type(frame.IsShown) == "function" and not frame:IsShown())
        or type(frame.EnumerateValidItems) ~= "function" then
        return
    end
    local poorQuality = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
    for _, btn in frame:EnumerateValidItems() do
        if btn and not IsFrameProtectedOrForbidden(btn)
            and (type(btn.IsShown) ~= "function" or btn:IsShown()) then
            local okB, bID = pcall(btn.GetBagID, btn)
            local okS, sl = pcall(btn.GetID, btn)
            bID = okB and bID or btn.bagID
            sl = okS and sl or nil
            local icon, _, locked, quality = nil, nil, false, nil
            if bID ~= nil and sl ~= nil then
                icon, _, locked, quality = GetContainerItemInfoSafe(bID, sl)
            end
            local hasItem = (icon ~= nil)
            local isPoorGrey = enabled and hasItem and (quality == poorQuality)
            if isPoorGrey then
                ApplyPoorItemVisualStyle(btn, true)
                nativeGreyAppliedBtns[btn] = true
            elseif nativeGreyAppliedBtns[btn] then
                nativeGreyAppliedBtns[btn] = nil
                ApplyPoorItemVisualStyle(btn, false, hasItem and 1 or nil, locked and true or false)
            end
        end
    end
end

local function RefreshNativeBagGreyItems(forceOff)
    local db = YRG:GetModuleDB("BetterBagsModule")
    local enabled = (not forceOff) and db and db.enabled and (db.dimGreyItems ~= false) and true or false
    if ContainerFrameCombinedBags then
        ApplyGreyVisualsToNativeFrame(ContainerFrameCombinedBags, enabled)
    end
    for i = 1, 13 do
        local cf = _G["ContainerFrame" .. i]
        if cf and cf.IsShown and cf:IsShown() then
            ApplyGreyVisualsToNativeFrame(cf, enabled)
        end
    end
end

local function UpdateContainerSlotButton(btn, bagID, slot, tintPurple, searchQuery)
    if not btn or (type(btn.IsForbidden) == "function" and btn:IsForbidden()) then return false end

    local icon, count, locked, quality, isReadable, _, itemLink, isFiltered, itemID, isBound, itemName = GetContainerItemInfoSafe(bagID, slot)
    local hasItem = (icon ~= nil or itemLink ~= nil or itemID ~= nil)

    local queryMiss = false
    if hasItem and searchQuery and searchQuery ~= "" then
        queryMiss = not DoesCustomItemMatchSearch(itemLink, itemID, itemName, searchQuery)
    end
    local dimmed = hasItem and (isFiltered or queryMiss) or false
    local modDB = YRG:GetModuleDB("BetterBagsModule")
    local poorQuality = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
    local isPoorGrey = hasItem and (not dimmed) and (modDB == nil or modDB.dimGreyItems ~= false) and (quality == poorQuality)
    local nowT = GetTime and GetTime() or 0
    local sortSuppressed = customBags.suppressSortNewUntil and nowT <= customBags.suppressSortNewUntil
    local isNew = hasItem and (not sortSuppressed)
        and (C_NewItems and type(C_NewItems.IsNewItem) == "function" and C_NewItems.IsNewItem(bagID, slot))
        and true or false

    local stateKey
    if not hasItem then
        stateKey = string.format("0:%d:%d:%s", bagID, slot, tintPurple and "P" or "")
    else
        stateKey = string.format("1:%d:%d:%s:%s:%s:%s:%s:%s:%s:%s:%s",
            bagID, slot,
            tostring(itemID or 0),
            tostring(count or 1),
            tostring(quality or -1),
            locked and "L" or "",
            dimmed and "D" or "",
            isBound and "B" or "",
            tintPurple and "P" or "",
            isNew and "N" or "",
            isPoorGrey and "G" or "")
    end

    if btn._yrgLastState == stateKey and btn._yrgLastIcon == icon then
        if hasItem then
            if btn.Cooldown and type(CooldownFrame_Set) == "function" then
                local start, duration, enable = 0, 0, 0
                if C_Container and type(C_Container.GetContainerItemCooldown) == "function" then
                    start, duration, enable = C_Container.GetContainerItemCooldown(bagID, slot)
                elseif type(GetContainerItemCooldown) == "function" then
                    start, duration, enable = GetContainerItemCooldown(bagID, slot)
                end
                CooldownFrame_Set(btn.Cooldown, YRG.SafeNumber(start, 0), YRG.SafeNumber(duration, 0), enable)
            elseif type(btn.UpdateCooldown) == "function" then
                pcall(btn.UpdateCooldown, btn, bagID)
            end
        end
        if GameTooltip and type(GameTooltip.IsOwned) == "function" and GameTooltip:IsOwned(btn) then
            if type(btn.UpdateTooltip) == "function" then
                pcall(btn.UpdateTooltip, btn)
            elseif type(GameTooltip.SetBagItem) == "function" then
                pcall(GameTooltip.SetBagItem, GameTooltip, bagID, slot)
            end
        end
        return hasItem
    end

    btn._yrgLastState = stateKey
    btn._yrgLastIcon = icon
    if not InCombatLockdown() then
        if btn:GetID() ~= slot then
            btn:SetID(slot)
        end
        if type(btn.SetBagID) == "function" and (not btn.GetBagID or btn:GetBagID() ~= bagID) then
            pcall(btn.SetBagID, btn, bagID)
        end
    end
    btn.bagID = bagID
    if not (customBags.secureProxy and customBags.secureProxy:IsShown() and customBags.secureProxy._targetBtn == btn) then
        if type(btn.SetHighlightLocked) == "function" then
            pcall(btn.SetHighlightLocked, btn, false)
        end
        if type(btn.UnlockHighlight) == "function" then
            pcall(btn.UnlockHighlight, btn)
        end
    end

    if type(SetItemButtonTexture) == "function" then
        SetItemButtonTexture(btn, icon)
    end
    local iconTex = btn.icon or btn.Icon
    if iconTex then
        if icon then
            iconTex:SetTexture(icon)
            iconTex:Show()
        elseif type(SetItemButtonTexture) ~= "function" then
            iconTex:SetTexture(nil)
            iconTex:Hide()
        end
    end
    if type(SetItemButtonCount) == "function" then
        SetItemButtonCount(btn, hasItem and count or 0)
    end

    if type(SetItemButtonDesaturated) == "function" then
        SetItemButtonDesaturated(btn, hasItem and (locked or dimmed) or false)
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
        if btn.flash then btn.flash:Hide() end
        if btn.newitemglowAnim and type(btn.newitemglowAnim.Stop) == "function" then
            pcall(btn.newitemglowAnim.Stop, btn.newitemglowAnim)
        end
        if btn.flashAnim and type(btn.flashAnim.Stop) == "function" then
            pcall(btn.flashAnim.Stop, btn.flashAnim)
        end
        if btn.Cooldown then btn.Cooldown:Hide() end
    else
        if btn.Cooldown and type(CooldownFrame_Set) == "function" then
            local start, duration, enable = 0, 0, 0
            if C_Container and type(C_Container.GetContainerItemCooldown) == "function" then
                start, duration, enable = C_Container.GetContainerItemCooldown(bagID, slot)
            elseif type(GetContainerItemCooldown) == "function" then
                start, duration, enable = GetContainerItemCooldown(bagID, slot)
            end
            CooldownFrame_Set(btn.Cooldown, YRG.SafeNumber(start, 0), YRG.SafeNumber(duration, 0), enable)
        elseif type(btn.UpdateCooldown) == "function" then
            pcall(btn.UpdateCooldown, btn, bagID)
        end

        if isNew then
            if type(btn.UpdateNewItem) == "function" then
                pcall(btn.UpdateNewItem, btn, quality)
            elseif btn.NewItemTexture then
                btn.NewItemTexture:SetShown(true)
            end
        else
            if btn.NewItemTexture then btn.NewItemTexture:Hide() end
            if btn.flash then btn.flash:Hide() end
            if btn.newitemglowAnim and type(btn.newitemglowAnim.Stop) == "function" then
                pcall(btn.newitemglowAnim.Stop, btn.newitemglowAnim)
            end
            if btn.flashAnim and type(btn.flashAnim.Stop) == "function" then
                pcall(btn.flashAnim.Stop, btn.flashAnim)
            end
        end
        if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide() end
        if type(btn.UpdateItemContextMatching) == "function" then
            pcall(btn.UpdateItemContextMatching, btn)
        end
    end

    if type(btn.SetMatchesSearch) == "function" then
        pcall(btn.SetMatchesSearch, btn, not dimmed)
    elseif btn.searchOverlay then
        btn.searchOverlay:SetShown(dimmed)
    end

    ApplyButtonPurpleTint(btn, tintPurple, hasItem)

    local eIconAlpha, eNormAlpha = customBags:GetEmptySlotAlphas()
    if isPoorGrey then
        ApplyPoorItemVisualStyle(btn, true)
    else
        ApplyPoorItemVisualStyle(btn, false, hasItem and 1 or eIconAlpha, hasItem and (locked or dimmed) or false)
    end
    local normTex = (type(btn.GetNormalTexture) == "function" and btn:GetNormalTexture()) or btn.NormalTexture
    if normTex and type(normTex.SetAlpha) == "function" then
        normTex:SetAlpha(hasItem and (isPoorGrey and 0.95 or 1) or eNormAlpha)
    end

    if GameTooltip and type(GameTooltip.IsOwned) == "function" and GameTooltip:IsOwned(btn) then
        if type(btn.UpdateTooltip) == "function" then
            pcall(btn.UpdateTooltip, btn)
        elseif type(GameTooltip.SetBagItem) == "function" then
            pcall(GameTooltip.SetBagItem, GameTooltip, bagID, slot)
        end
    end
    return hasItem
end

function customBags:ClearProxyHoverState(proxy)
    if not proxy then return end
    local t = proxy._targetBtn
    proxy._targetBtn = nil
    if t then
        if type(t.UnlockHighlight) == "function" then
            pcall(t.UnlockHighlight, t)
        end
        if type(t.GetScript) == "function" then
            local onLeave = t:GetScript("OnLeave")
            if type(onLeave) == "function" then
                pcall(onLeave, t)
            end
        end
    end
    if GameTooltip and type(GameTooltip.IsShown) == "function" and GameTooltip:IsShown()
        and type(GameTooltip.GetOwner) == "function" then
        local okOwn, owner = pcall(GameTooltip.GetOwner, GameTooltip)
        if okOwn and (owner == proxy or (t and owner == t)) then
            pcall(GameTooltip.Hide, GameTooltip)
        end
    end
end

function customBags:HideSecureProxy()
    local proxy = self.secureProxy
    if not proxy then return end
    self:ClearProxyHoverState(proxy)
    if not InCombatLockdown() then
        proxy:ClearAllPoints()
        proxy:Hide()
    end
end

function customBags:EnsureSecureProxy()
    if self.secureProxy then return self.secureProxy end
    local ok, proxy = pcall(CreateFrame, "Button", "YRGCustomBagSecureProxy", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    if ok and proxy then
        proxy:SetAttribute("_onstate-yrgcombat", [[
            if newstate == "hide" then
                self:Hide()
            end
        ]])
        if type(RegisterStateDriver) == "function" then
            pcall(RegisterStateDriver, proxy, "yrgcombat", "[combat] hide; stay")
        end
    else
        ok, proxy = pcall(CreateFrame, "Button", "YRGCustomBagSecureProxy", UIParent, "SecureActionButtonTemplate")
    end
    if not ok or not proxy then return nil end

    proxy:Hide()
    proxy:EnableMouse(true)
    pcall(proxy.RegisterForClicks, proxy, "RightButtonUp")
    pcall(proxy.RegisterForDrag, proxy)
    pcall(proxy.SetAttribute, proxy, "useOnKeyDown", false)
    if type(proxy.SetPassThroughButtons) == "function" then
        pcall(proxy.SetPassThroughButtons, proxy, "LeftButton")
    end

    proxy:SetScript("OnEnter", function(selfProxy)
        local t = selfProxy._targetBtn
        if not t or not t:IsVisible() then return end
        customBags.replayingEnter = true
        if type(t.GetScript) == "function" then
            local onEnter = t:GetScript("OnEnter")
            if type(onEnter) == "function" then
                pcall(onEnter, t)
            end
        end
        customBags.replayingEnter = false
        if type(t.LockHighlight) == "function" then
            pcall(t.LockHighlight, t)
        end
    end)

    proxy:SetScript("OnLeave", function(selfProxy)
        customBags:ClearProxyHoverState(selfProxy)
        if not InCombatLockdown() then
            selfProxy:ClearAllPoints()
            selfProxy:Hide()
        end
    end)

    proxy:SetScript("OnHide", function(selfProxy)
        customBags:ClearProxyHoverState(selfProxy)
    end)

    proxy:SetScript("OnReceiveDrag", function(selfProxy)
        local t = selfProxy._targetBtn
        if not t then return end
        if C_Container and type(C_Container.PickupContainerItem) == "function" then
            pcall(C_Container.PickupContainerItem, t:GetBagID(), t:GetID())
        elseif type(PickupContainerItem) == "function" then
            pcall(PickupContainerItem, t:GetBagID(), t:GetID())
        elseif type(ContainerFrameItemButton_OnClick) == "function" then
            pcall(ContainerFrameItemButton_OnClick, t, "LeftButton")
        elseif type(t.GetScript) == "function" then
            local onClick = t:GetScript("OnClick")
            if type(onClick) == "function" then
                pcall(onClick, t, "LeftButton")
            end
        end
    end)

    if type(proxy.HasScript) == "function" and proxy:HasScript("PreClick") then
        proxy:HookScript("PreClick", function(selfProxy, mouseBtn, down)
            if down or InCombatLockdown() then return end
            local targeting = (type(SpellIsTargeting) == "function" and SpellIsTargeting()) and true or false
            if mouseBtn == "RightButton" then
                if targeting then
                    selfProxy._yrgCancelTargetingOnRight = true
                    selfProxy._yrgFallbackRight = false
                    SetAttrIfChanged(selfProxy, "type2", nil)
                else
                    selfProxy._yrgCancelTargetingOnRight = false
                    local transferOpen = IsTransferFrameOpenForReagents()
                    selfProxy._yrgFallbackRight = transferOpen
                    SetAttrIfChanged(selfProxy, "type2", transferOpen and nil or "item")
                end
            elseif mouseBtn == "LeftButton" then
                if targeting then
                    local t = selfProxy._targetBtn
                    if t and t._yrgCustomBagID ~= nil and t._yrgCustomSlot ~= nil then
                        SetAttrIfChanged(selfProxy, "bag", nil)
                        SetAttrIfChanged(selfProxy, "slot", nil)
                        SetAttrIfChanged(selfProxy, "item", nil)
                        SetAttrIfChanged(selfProxy, "bag1", nil)
                        SetAttrIfChanged(selfProxy, "slot1", nil)
                        SetAttrIfChanged(selfProxy, "item1", nil)
                        SetAttrIfChanged(selfProxy, "clickbutton", nil)
                        SetAttrIfChanged(selfProxy, "clickbutton1", nil)
                        SetAttrIfChanged(selfProxy, "unit1", "none")
                        SetAttrIfChanged(selfProxy, "target-bag1", t._yrgCustomBagID)
                        SetAttrIfChanged(selfProxy, "target-slot1", t._yrgCustomSlot)
                        SetAttrIfChanged(selfProxy, "type1", "click")
                    end
                else
                    SetAttrIfChanged(selfProxy, "type1", nil)
                end
            end
        end)
    end
    if type(proxy.HasScript) == "function" and proxy:HasScript("PostClick") then
        proxy:HookScript("PostClick", function(selfProxy, mouseBtn, down)
            if down then return end
            if mouseBtn == "RightButton" then
                if selfProxy._yrgCancelTargetingOnRight then
                    selfProxy._yrgCancelTargetingOnRight = false
                    if type(SpellIsTargeting) == "function" and SpellIsTargeting() and type(SpellStopTargeting) == "function" then
                        pcall(SpellStopTargeting)
                    end
                elseif (selfProxy._yrgFallbackRight or (IsModifierKeyDown and IsModifierKeyDown()))
                    and not (type(SpellIsTargeting) == "function" and SpellIsTargeting()) then
                    selfProxy._yrgFallbackRight = false
                    local t = selfProxy._targetBtn
                    if t then
                        local onClick = type(t.GetScript) == "function" and t:GetScript("OnClick") or nil
                        if type(onClick) == "function" then
                            pcall(onClick, t, "RightButton")
                        elseif type(ContainerFrameItemButton_OnClick) == "function" then
                            pcall(ContainerFrameItemButton_OnClick, t, "RightButton")
                        end
                    end
                end
            end
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function() customBags:SyncHoveredSecureProxy() end)
            end
        end)
    end

    proxy._yrgTargetingMode = false
    self.secureProxy = proxy
    return proxy
end

function customBags:AttachSecureProxy(btn)
    if self.replayingEnter or InCombatLockdown() then return end
    local f = self.frame
    if IsControllerUIActive() or not f or not f:IsShown() or not btn or not btn:IsShown() then
        self:HideSecureProxy()
        return
    end
    local bagID = btn._yrgCustomBagID
    local slot = btn._yrgCustomSlot
    local cursorHolding = (type(CursorHasItem) == "function" and CursorHasItem()) and true or false
    local targeting = (type(SpellIsTargeting) == "function" and SpellIsTargeting()) and true or false
    if bagID == nil or slot == nil or not btn.hasItem or cursorHolding or ((not targeting) and IsTransferFrameOpenForReagents()) then
        self:HideSecureProxy()
        return
    end

    local proxy = self:EnsureSecureProxy()
    if not proxy then return end

    if proxy._yrgTargetingMode ~= targeting then
        proxy._yrgTargetingMode = targeting
        if targeting then
            if type(proxy.SetPassThroughButtons) == "function" then
                pcall(proxy.SetPassThroughButtons, proxy)
            end
            pcall(proxy.RegisterForClicks, proxy, "LeftButtonUp", "RightButtonUp")
        else
            pcall(proxy.RegisterForClicks, proxy, "RightButtonUp")
            if type(proxy.SetPassThroughButtons) == "function" then
                pcall(proxy.SetPassThroughButtons, proxy, "LeftButton")
            end
        end
    end

    local itemCoord = tostring(bagID) .. " " .. tostring(slot)
    proxy._yrgFallbackRight = false
    proxy._yrgCancelTargetingOnRight = false
    if targeting then
        SetAttrIfChanged(proxy, "bag", nil)
        SetAttrIfChanged(proxy, "slot", nil)
        SetAttrIfChanged(proxy, "item", nil)
        SetAttrIfChanged(proxy, "bag1", nil)
        SetAttrIfChanged(proxy, "slot1", nil)
        SetAttrIfChanged(proxy, "item1", nil)
        SetAttrIfChanged(proxy, "clickbutton", nil)
        SetAttrIfChanged(proxy, "clickbutton1", nil)
        SetAttrIfChanged(proxy, "unit1", "none")
        SetAttrIfChanged(proxy, "target-bag1", bagID)
        SetAttrIfChanged(proxy, "target-slot1", slot)
        SetAttrIfChanged(proxy, "shift-type1", nil)
        SetAttrIfChanged(proxy, "ctrl-type1", nil)
        SetAttrIfChanged(proxy, "alt-type1", nil)
        SetAttrIfChanged(proxy, "type1", "click")
        SetAttrIfChanged(proxy, "bag2", nil)
        SetAttrIfChanged(proxy, "slot2", nil)
        SetAttrIfChanged(proxy, "item2", nil)
        SetAttrIfChanged(proxy, "type2", nil)
    else
        SetAttrIfChanged(proxy, "target-bag1", nil)
        SetAttrIfChanged(proxy, "target-slot1", nil)
        SetAttrIfChanged(proxy, "unit1", nil)
        SetAttrIfChanged(proxy, "clickbutton", nil)
        SetAttrIfChanged(proxy, "clickbutton1", nil)
        SetAttrIfChanged(proxy, "bag1", nil)
        SetAttrIfChanged(proxy, "slot1", nil)
        SetAttrIfChanged(proxy, "item1", nil)
        SetAttrIfChanged(proxy, "type1", nil)
        SetAttrIfChanged(proxy, "bag", bagID)
        SetAttrIfChanged(proxy, "slot", slot)
        SetAttrIfChanged(proxy, "item", itemCoord)
        SetAttrIfChanged(proxy, "bag2", bagID)
        SetAttrIfChanged(proxy, "slot2", slot)
        SetAttrIfChanged(proxy, "item2", itemCoord)
        SetAttrIfChanged(proxy, "shift-type2", "")
        SetAttrIfChanged(proxy, "ctrl-type2", "")
        SetAttrIfChanged(proxy, "alt-type2", "")
        SetAttrIfChanged(proxy, "type2", "item")
    end

    if not proxy:IsShown() or proxy._targetBtn ~= btn then
        local fScale = YRG.SafeNumber(f.GetEffectiveScale and f:GetEffectiveScale(), 1)
        local uiScale = math.max(YRG.SafeNumber(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale(), 1), 0.01)
        local bLeft = YRG.SafeNumber(btn.GetLeft and btn:GetLeft(), nil)
        local bBottom = YRG.SafeNumber(btn.GetBottom and btn:GetBottom(), nil)
        local bW = YRG.SafeNumber(btn.GetWidth and btn:GetWidth(), 37)
        local bH = YRG.SafeNumber(btn.GetHeight and btn:GetHeight(), 37)
        if bLeft and bBottom then
            proxy:SetScale(fScale / uiScale)
            proxy:SetSize(bW, bH)
            proxy:SetFrameStrata((btn.GetFrameStrata and btn:GetFrameStrata()) or (f.GetFrameStrata and f:GetFrameStrata()) or "MEDIUM")
            proxy:SetFrameLevel(math.max((btn.GetFrameLevel and btn:GetFrameLevel() or 1) + 5, 10))
            proxy:ClearAllPoints()
            proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bLeft, bBottom)
            proxy._targetBtn = btn
            proxy:Show()
        end
    end
end

function customBags:SyncHoveredSecureProxy()
    if InCombatLockdown() then return end
    local f = self.frame
    if IsControllerUIActive() or not f or not f:IsShown() then
        self:HideSecureProxy()
        return
    end
    local cursorHolding = (type(CursorHasItem) == "function" and CursorHasItem()) and true or false
    local targeting = (type(SpellIsTargeting) == "function" and SpellIsTargeting()) and true or false
    if cursorHolding or ((not targeting) and IsTransferFrameOpenForReagents()) then
        self:HideSecureProxy()
        return
    end
    local proxy = self.secureProxy
    if proxy and proxy:IsShown() then
        local target = proxy._targetBtn
        if target and target:IsShown() then
            local okOver, isOver = pcall(target.IsMouseOver, target)
            if okOver and isOver and target.hasItem then
                self:AttachSecureProxy(target)
                return
            end
        end
        self:HideSecureProxy()
        return
    end
    for _, btn in ipairs(self.buttons) do
        if btn and btn:IsShown() and btn.hasItem then
            local okOver, isOver = pcall(btn.IsMouseOver, btn)
            if okOver and isOver then
                self:AttachSecureProxy(btn)
                return
            end
        end
    end
end

local function ShouldUseCustomReagentCombinedFrame(db)
    if not db or not db.enabled then return false end
    if IsControllerUIActive() then return false end
    if db.includeReagentBagInCombined == false then return false end
    if GetBagNumSlotsSafe(GetReagentBagID()) <= 0 then return false end
    if type(GetCVarBool) == "function" then
        local ok, cb = pcall(GetCVarBool, "combinedBags")
        if ok and cb == false then
            return false
        end
    end
    return true
end

local function CanSafelyModifyFrame(cf)
    if not cf or IsFrameProtectedOrForbidden(cf) then return false end
    if InCombatLockdown() then
        if type(cf.CanChangeProtectedState) == "function" then
            local okC, canC = pcall(cf.CanChangeProtectedState, cf)
            if okC and not canC then return false end
        end
        if type(cf.IsProtected) == "function" then
            local okP, isP = pcall(cf.IsProtected, cf)
            if okP and isP then return false end
        end
    end
    return true
end

local function SyncBlizzardBagParentSuppression(suppress)
    -- Never reparent ContainerFrameCombinedBags via SetParent; doing so taints its
    -- secure/gamepad container state across Mouse <-> Controller transitions.
    if InCombatLockdown() then return end
    if suppress and not IsControllerUIActive() then
        local cfb = ContainerFrameCombinedBags
        if cfb and cfb:IsShown() and CanSafelyModifyFrame(cfb) then
            pcall(cfb.Hide, cfb)
        end
    end
end

local function HideBlizzardBagsForCustomMode()
    if customBags.hidingBlizzard or IsControllerUIActive() then return end
    customBags.hidingBlizzard = true
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        if CanSafelyModifyFrame(ContainerFrameCombinedBags) and not InCombatLockdown() then
            pcall(ContainerFrameCombinedBags.Hide, ContainerFrameCombinedBags)
        end
    end
    local rBagID = GetReagentBagID()
    for i = 1, 13 do
        local cf = _G["ContainerFrame" .. i]
        if cf and cf.IsShown and cf:IsShown() and CanSafelyModifyFrame(cf) and not InCombatLockdown() then
            local cid = (type(cf.GetBagID) == "function" and cf:GetBagID())
                or cf.bagID
                or (type(cf.GetID) == "function" and cf:GetID())
            if type(cid) == "number" and cid >= 0 and cid <= rBagID then
                pcall(cf.Hide, cf)
            end
        end
    end
    customBags.hidingBlizzard = false
end

local function HideReagentOverlays()
    HideSectionDivider("customAmmo")
    HideSectionDivider("customReag")
end

local function FormatMoneySafe()
    local copper = YRG.SafeNumber(GetMoney and GetMoney(), 0)
    local coinFn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if type(coinFn) == "function" then
        local okC, str = pcall(coinFn, copper)
        if okC and type(str) == "string" and str ~= "" then
            return str
        end
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("|cffffd100%dg|r |cffc7c7cf%02ds|r |cffeda55f%02dc|r", g, s, c)
    elseif s > 0 then
        return string.format("|cffc7c7cf%ds|r |cffeda55f%02dc|r", s, c)
    end
    return string.format("|cffeda55f%dc|r", c)
end

local function GetFreeSlotsByBagSafe(bagID)
    local fn = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if type(fn) ~= "function" then return 0, 0 end
    local ok, free, family = pcall(fn, bagID)
    if not ok then return 0, 0 end
    return YRG.SafeNumber(free, 0), YRG.SafeNumber(family, 0)
end

function customBags:UpdateFooter()
    if not self.frame then return end
    if self.moneyText then
        self.moneyText:SetText(FormatMoneySafe())
    end
    if self.freeText then
        local db = YRG:GetModuleDB("BetterBagsModule")
        local sepAmmo = (db and db.separateAmmoBagRow == true)
        local rBagID = GetReagentBagID()
        local stdFree, ammoFree, reagFree = 0, 0, 0
        for bag = (BACKPACK_CONTAINER or 0), (NUM_BAG_SLOTS or 4) do
            local fCount = GetFreeSlotsByBagSafe(bag)
            local okAmmo, isAmmo = pcall(IsAmmoOrQuiverBag, bag)
            if sepAmmo and okAmmo and isAmmo then
                ammoFree = ammoFree + fCount
            else
                stdFree = stdFree + fCount
            end
        end
        reagFree = GetFreeSlotsByBagSafe(rBagID)
        local text = string.format("|cffd8d8d8%d Free|r", stdFree)
        if ammoFree > 0 then
            text = text .. string.format("  |cffffd100+%d Ammo|r", ammoFree)
        end
        text = text .. string.format("  |cffc084fc+%d Reag|r", reagFree)
        self.freeText:SetText(text)
    end
end

local function HasProtectedChildOrSelf(obj)
    if IsFrameProtectedOrForbidden(obj) then return true end
    if type(obj.GetChildren) == "function" then
        for _, child in ipairs({ obj:GetChildren() }) do
            if HasProtectedChildOrSelf(child) then
                return true
            end
        end
    end
    return false
end

local function CloneTextureRegions(src, dst, fallbackFillAll)
    if not src or not dst or type(src.GetRegions) ~= "function" then return 0 end
    local count = 0
    for _, r in ipairs({ src:GetRegions() }) do
        if r and type(r.IsObjectType) == "function" and r:IsObjectType("Texture")
            and (type(r.IsShown) ~= "function" or r:IsShown()) then
            local atlas = type(r.GetAtlas) == "function" and r:GetAtlas() or nil
            local tex = type(r.GetTexture) == "function" and r:GetTexture() or nil
            if (type(atlas) == "string" and atlas ~= "") or tex then
                local layer, subLayer = "BORDER", 0
                if type(r.GetDrawLayer) == "function" then
                    local okL, l, sl = pcall(r.GetDrawLayer, r)
                    if okL and l then
                        layer = l
                        subLayer = tonumber(sl) or 0
                    end
                end
                local t = dst:CreateTexture(nil, layer, nil, subLayer)
                local applied = false
                if type(atlas) == "string" and atlas ~= "" and type(t.SetAtlas) == "function" then
                    applied = pcall(t.SetAtlas, t, atlas, false)
                end
                if not applied and tex then
                    t:SetTexture(tex)
                    if type(r.GetTexCoord) == "function" then
                        local okTC, x1, y1, x2, y2, x3, y3, x4, y4 = pcall(r.GetTexCoord, r)
                        if okTC and type(x1) == "number" then
                            pcall(t.SetTexCoord, t, x1, y1, x2, y2, x3, y3, x4, y4)
                        end
                    end
                    applied = true
                end
                if applied then
                    if type(r.GetVertexColor) == "function" then
                        local okC, cr, cg, cb, ca = pcall(r.GetVertexColor, r)
                        if okC and type(cr) == "number" then
                            t:SetVertexColor(cr, cg or 1, cb or 1, ca or 1)
                        end
                    end
                    if type(r.GetAlpha) == "function" then
                        t:SetAlpha(YRG.SafeNumber(r:GetAlpha(), 1))
                    end
                    local w = type(r.GetWidth) == "function" and YRG.SafeNumber(r:GetWidth(), 0) or 0
                    local h = type(r.GetHeight) == "function" and YRG.SafeNumber(r:GetHeight(), 0) or 0
                    if w > 0 and h > 0 then
                        t:SetSize(w, h)
                    elseif w > 0 then
                        t:SetWidth(w)
                    elseif h > 0 then
                        t:SetHeight(h)
                    end
                    local placedPts = 0
                    local nPts = type(r.GetNumPoints) == "function" and r:GetNumPoints() or 0
                    local srcParent = type(src.GetParent) == "function" and src:GetParent() or nil
                    for pIdx = 1, nPts do
                        local pt, relTo, relPt, px, py = r:GetPoint(pIdx)
                        if pt then
                            local mappedRel = (relTo == src or relTo == srcParent or relTo == nil) and dst or nil
                            if mappedRel then
                                pcall(t.SetPoint, t, pt, mappedRel, relPt or pt, YRG.SafeNumber(px, 0), YRG.SafeNumber(py, 0))
                                placedPts = placedPts + 1
                            end
                        end
                    end
                    if placedPts == 0 then
                        if fallbackFillAll then
                            t:SetAllPoints(dst)
                            count = count + 1
                        else
                            t:Hide()
                        end
                    else
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

local function CopyCloseButtonVisuals(srcBtn, dstBtn)
    local copiedAny = false
    if srcBtn then
        local setters = {
            { get = "GetNormalTexture", set = "SetNormalTexture", atlasSet = "SetNormalAtlas" },
            { get = "GetPushedTexture", set = "SetPushedTexture", atlasSet = "SetPushedAtlas" },
            { get = "GetHighlightTexture", set = "SetHighlightTexture", atlasSet = "SetHighlightAtlas" },
            { get = "GetDisabledTexture", set = "SetDisabledTexture", atlasSet = "SetDisabledAtlas" },
        }
        for _, entry in ipairs(setters) do
            if type(srcBtn[entry.get]) == "function" then
                local okT, sr = pcall(srcBtn[entry.get], srcBtn)
                if okT and sr then
                    local atlas = type(sr.GetAtlas) == "function" and sr:GetAtlas() or nil
                    local tex = type(sr.GetTexture) == "function" and sr:GetTexture() or nil
                    if type(atlas) == "string" and atlas ~= "" and type(dstBtn[entry.atlasSet]) == "function" then
                        if pcall(dstBtn[entry.atlasSet], dstBtn, atlas) then
                            copiedAny = true
                        end
                    elseif tex and type(dstBtn[entry.set]) == "function" then
                        local t = dstBtn:CreateTexture(nil, entry.get == "GetHighlightTexture" and "HIGHLIGHT" or "ARTWORK")
                        t:SetAllPoints(dstBtn)
                        t:SetTexture(tex)
                        if type(sr.GetTexCoord) == "function" then
                            local okTC, x1, y1, x2, y2, x3, y3, x4, y4 = pcall(sr.GetTexCoord, sr)
                            if okTC and type(x1) == "number" then pcall(t.SetTexCoord, t, x1, y1, x2, y2, x3, y3, x4, y4) end
                        end
                        if entry.get == "GetHighlightTexture" then
                            pcall(dstBtn.SetHighlightTexture, dstBtn, t, "ADD")
                        else
                            pcall(dstBtn[entry.set], dstBtn, t)
                        end
                        copiedAny = true
                    end
                end
            end
        end
    end
    if not copiedAny then
        dstBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        dstBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        dstBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    end
end

function customBags:EnsureFrame()
    if self.frame then return self.frame end

    -- Always create the custom frame from a bare Frame so it NEVER inherits protected XML state.
    local f = CreateFrame("Frame", "YRGCombinedBagsFrame", UIParent)
    f:Hide()
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(12)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    if type(f.SetDontSavePosition) == "function" then pcall(f.SetDontSavePosition, f, true) end
    f:SetSize(437, 460)
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -32, 110)

    local cfb = ContainerFrameCombinedBags
    local cNine = cfb and cfb.NineSlice
    local cBg = cfb and (cfb.Bg or cfb.Background)

    -- 1. Panel background (matching ContainerFrameCombinedBags warm translucent tone)
    local bgFrame = CreateFrame("Frame", nil, f)
    bgFrame:SetFrameLevel(math.max(f:GetFrameLevel(), 1))
    bgFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -22)
    bgFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    bgFrame:EnableMouse(false)
    if bgFrame.SetMouseClickEnabled then bgFrame:SetMouseClickEnabled(false) end
    if bgFrame.SetMouseMotionEnabled then bgFrame:SetMouseMotionEnabled(false) end

    local bgApplied = false
    local okFlat, flatProbe = pcall(CreateFrame, "Frame", nil, nil, "FlatPanelBackgroundTemplate")
    if okFlat and flatProbe then
        if not HasProtectedChildOrSelf(flatProbe) then
            flatProbe:SetParent(f)
            flatProbe:SetFrameLevel(math.max(f:GetFrameLevel(), 1))
            flatProbe:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -22)
            flatProbe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
            if cBg and type(cBg.GetAlpha) == "function" and type(flatProbe.SetAlpha) == "function" then
                local cAlpha = YRG.SafeNumber(cBg:GetAlpha(), 1)
                if cAlpha > 0 then pcall(flatProbe.SetAlpha, flatProbe, cAlpha) end
            end
            self.innerBg = flatProbe
            self.bgTpl = "FlatPanelBackgroundTemplate(Unprot)"
            bgApplied = true
            bgFrame:Hide()
        else
            flatProbe:Hide()
        end
    end
    if not bgApplied then
        local clonedBg = CloneTextureRegions(cBg, bgFrame, true)
        if clonedBg == 0 and cBg and type(cBg.GetChildren) == "function" then
            for _, ch in ipairs({ cBg:GetChildren() }) do
                clonedBg = clonedBg + CloneTextureRegions(ch, bgFrame, true)
            end
        end
        if clonedBg > 0 then
            if type(cBg.GetAlpha) == "function" then
                bgFrame:SetAlpha(YRG.SafeNumber(cBg:GetAlpha(), 1))
            end
            self.bgTpl = "CloneCBg:" .. tostring(clonedBg)
            bgApplied = true
        else
            local innerBg = bgFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
            innerBg:SetAllPoints(bgFrame)
            innerBg:SetColorTexture(0.11, 0.08, 0.06, 0.72)
            self.bgTpl = "WarmBrownFallback"
        end
        self.innerBg = bgFrame
    end

    -- 2. Portrait (TOPLEFT circular bag icon)
    local portraitCont = CreateFrame("Frame", nil, f)
    portraitCont:SetFrameLevel(f:GetFrameLevel() + 1)
    portraitCont:EnableMouse(false)
    if portraitCont.SetMouseClickEnabled then portraitCont:SetMouseClickEnabled(false) end
    if portraitCont.SetMouseMotionEnabled then portraitCont:SetMouseMotionEnabled(false) end
    local cPort = cfb and cfb.PortraitContainer
    local pW = cPort and cPort.GetWidth and YRG.SafeNumber(cPort:GetWidth(), 0) or 0
    local pH = cPort and cPort.GetHeight and YRG.SafeNumber(cPort:GetHeight(), 0) or 0
    portraitCont:SetSize(pW > 10 and pW or 60, pH > 10 and pH or 60)
    portraitCont:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 7)

    local portraitTex = portraitCont:CreateTexture(nil, "ARTWORK")
    portraitTex:SetAllPoints(portraitCont)
    if type(portraitCont.CreateMaskTexture) == "function" and type(portraitTex.AddMaskTexture) == "function" then
        local mask = portraitCont:CreateMaskTexture()
        mask:SetAllPoints(portraitTex)
        local maskAtlas = cPort and cPort.CircleMask and type(cPort.CircleMask.GetAtlas) == "function" and cPort.CircleMask:GetAtlas()
        if type(maskAtlas) == "string" and maskAtlas ~= "" and type(mask.SetAtlas) == "function" then
            pcall(mask.SetAtlas, mask, maskAtlas)
        else
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        portraitTex:AddMaskTexture(mask)
    end
    if type(SetPortraitToAsset) == "function" then
        pcall(SetPortraitToAsset, portraitTex, "Interface\\Icons\\INV_Misc_Bag_08")
    else
        portraitTex:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    end

    -- 3. NineSlice golden frame border + portrait ring
    local nsFrame = CreateFrame("Frame", nil, f)
    nsFrame:SetAllPoints(f)
    nsFrame:SetFrameLevel(f:GetFrameLevel() + 2)
    nsFrame:EnableMouse(false)
    if nsFrame.SetMouseClickEnabled then nsFrame:SetMouseClickEnabled(false) end
    if nsFrame.SetMouseMotionEnabled then nsFrame:SetMouseMotionEnabled(false) end

    local nsApplied = false
    if NineSliceUtil and type(NineSliceUtil.ApplyLayoutByName) == "function" then
        local nsLayout = (cNine and cNine.layoutType) or "PortraitFrameTemplate"
        local nsKit = cNine and cNine.layoutTextureKit
        local okNS = pcall(NineSliceUtil.ApplyLayoutByName, nsFrame, nsLayout, nsKit)
        if okNS and not HasProtectedChildOrSelf(nsFrame) and (nsFrame:GetNumRegions() or 0) > 0 then
            if nsFrame.Center then nsFrame.Center:Hide() end
            nsApplied = true
            self.nsTpl = "NineSliceUtil:" .. tostring(nsLayout)
        end
    end
    if not nsApplied then
        local clonedNS = CloneTextureRegions(cNine, nsFrame, false)
        self.nsTpl = "CloneNineSlice:" .. tostring(clonedNS)
        if clonedNS == 0 then
            local pRing = portraitCont:CreateTexture(nil, "OVERLAY")
            pRing:SetSize(64, 64)
            pRing:SetPoint("CENTER", portraitCont, "CENTER", 0, 0)
            pRing:SetTexture("Interface\\FrameGeneral\\UI-Frame")
        end
    end

    -- 4. Draggable Title bar & "Bags" label
    local titleCont = CreateFrame("Frame", nil, f)
    titleCont:SetFrameLevel(f:GetFrameLevel() + 7)
    titleCont:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -1)
    titleCont:SetPoint("TOPRIGHT", f, "TOPRIGHT", -26, -1)
    titleCont:SetHeight(24)
    titleCont:EnableMouse(true)
    f.TitleContainer = titleCont

    local titleText = titleCont:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("CENTER", titleCont, "CENTER", -12, 0)
    titleText:SetText("Bags")
    titleCont.TitleText = titleText

    -- 5. Close Button (plain Button cloned from Blizzard CloseButton)
    local closeBtn = CreateFrame("Button", "YRGCombinedBagsCloseBtn", f)
    closeBtn:SetSize(24, 24)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 8)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    CopyCloseButtonVisuals(cfb and cfb.CloseButton, closeBtn)
    closeBtn:SetScript("OnClick", function()
        customBags:Close()
    end)
    f.CloseButton = closeBtn

    -- 6. Search Box (probe SearchBoxTemplate detached first; fallback to clean unprotected EditBox)
    local sb = nil
    local okS, sbProbe = pcall(CreateFrame, "EditBox", nil, nil, "SearchBoxTemplate")
    if okS and sbProbe and not HasProtectedChildOrSelf(sbProbe) then
        sbProbe:SetParent(f)
        if HasProtectedChildOrSelf(f) then
            sbProbe:SetParent(nil)
            sbProbe:Hide()
        else
            sb = sbProbe
            self.sbTpl = "SearchBoxTemplate(Unprot)"
        end
    elseif sbProbe and type(sbProbe.Hide) == "function" then
        sbProbe:Hide()
    end
    if not sb then
        sb = CreateFrame("EditBox", "YRGCombinedBagsSearchBox", f)
        sb:SetAutoFocus(false)
        sb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        sb:SetTextInsets(22, 18, 0, 0)
        local sbBg = sb:CreateTexture(nil, "BACKGROUND")
        sbBg:SetAllPoints(sb)
        sbBg:SetColorTexture(0.05, 0.04, 0.03, 0.65)
        local sbBorder = sb:CreateTexture(nil, "BORDER")
        sbBorder:SetPoint("TOPLEFT", sb, "TOPLEFT", -1, 1)
        sbBorder:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 1, -1)
        sbBorder:SetColorTexture(0.45, 0.38, 0.28, 0.55)
        sbBorder:SetDrawLayer("BACKGROUND", -1)
        local sbIcon = sb:CreateTexture(nil, "OVERLAY")
        sbIcon:SetSize(13, 13)
        sbIcon:SetPoint("LEFT", sb, "LEFT", 5, 0)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-search-magnifyingglass") and sbIcon.SetAtlas then
            pcall(sbIcon.SetAtlas, sbIcon, "common-search-magnifyingglass")
        else
            sbIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
        end
        local placeholder = sb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        placeholder:SetPoint("LEFT", sb, "LEFT", 22, 0)
        placeholder:SetText("Search")
        local clrBtn = CreateFrame("Button", nil, sb)
        clrBtn:SetSize(14, 14)
        clrBtn:SetPoint("RIGHT", sb, "RIGHT", -3, 0)
        local clrTex = clrBtn:CreateTexture(nil, "OVERLAY")
        clrTex:SetAllPoints(clrBtn)
        clrTex:SetTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
        clrBtn:Hide()
        clrBtn:SetScript("OnClick", function()
            sb:SetText("")
            sb:ClearFocus()
        end)
        sb:HookScript("OnTextChanged", function(box)
            local empty = (box:GetText() or "") == ""
            placeholder:SetShown(empty and not box:HasFocus())
            clrBtn:SetShown(not empty)
        end)
        sb:HookScript("OnEditFocusGained", function()
            placeholder:Hide()
        end)
        sb:HookScript("OnEditFocusLost", function(box)
            placeholder:SetShown((box:GetText() or "") == "")
        end)
        self.sbTpl = "PlainSearchEditBox"
    end
    sb:SetFrameLevel(f:GetFrameLevel() + 7)
    sb:SetSize(180, 20)
    sb:SetPoint("TOPLEFT", f, "TOPLEFT", 64, -33)
    sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -44, -33)
    sb:SetAutoFocus(false)
    sb:HookScript("OnTextChanged", function(box)
        local raw = box:GetText() or ""
        local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", "")
        customBags.searchQuery = trimmed:lower()
        if C_Container and type(C_Container.SetItemSearch) == "function" then
            pcall(C_Container.SetItemSearch, trimmed)
        end
        customBags:RefreshSlots()
    end)
    sb:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
    end)
    sb:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
    end)
    self.searchBox = sb

    -- Auto-Sort broom button matching Blizzard's BagItemAutoSortButton
    local sortBtn = CreateFrame("Button", "YRGCombinedBagsSortBtn", f)
    sortBtn:SetSize(26, 26)
    sortBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -30)
    local sortNorm = sortBtn:CreateTexture(nil, "ARTWORK")
    sortNorm:SetAllPoints(sortBtn)
    local hasUpAtlas = C_Texture and type(C_Texture.GetAtlasInfo) == "function" and C_Texture.GetAtlasInfo("bags-button-autosort-up")
    if hasUpAtlas and sortNorm.SetAtlas then
        pcall(sortNorm.SetAtlas, sortNorm, "bags-button-autosort-up")
    else
        sortNorm:SetTexture("Interface\\Icons\\INV_Misc_Broom_01")
        sortNorm:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    sortBtn:SetNormalTexture(sortNorm)
    local hasDownAtlas = C_Texture and type(C_Texture.GetAtlasInfo) == "function" and C_Texture.GetAtlasInfo("bags-button-autosort-down")
    if hasDownAtlas then
        local sortPush = sortBtn:CreateTexture(nil, "ARTWORK")
        sortPush:SetAllPoints(sortBtn)
        if sortPush.SetAtlas and pcall(sortPush.SetAtlas, sortPush, "bags-button-autosort-down") then
            sortBtn:SetPushedTexture(sortPush)
        end
    end
    sortBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    sortBtn:SetScript("OnClick", function()
        if ExecuteBagSort then
            ExecuteBagSort()
        end
    end)
    sortBtn:SetScript("OnEnter", function(btn)
        if GameTooltip then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText("Clean Up Bags")
            GameTooltip:Show()
        end
    end)
    sortBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    self.sortBtn = sortBtn

    -- Bottom Money pill (with Blizzard currency ring/border) + Free Slots label
    local moneyBg = CreateFrame("Frame", nil, f)
    moneyBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 7)
    moneyBg:SetSize(172, 22)
    moneyBg:SetFrameLevel(f:GetFrameLevel() + 4)

    -- Draw a single subtle translucent warm fill inside the pill border (matching Search box transparency)
    local mInner = moneyBg:CreateTexture(nil, "BACKGROUND", nil, -2)
    mInner:SetPoint("TOPLEFT", moneyBg, "TOPLEFT", 4, -3)
    mInner:SetPoint("BOTTOMRIGHT", moneyBg, "BOTTOMRIGHT", -4, 3)
    mInner:SetColorTexture(0.05, 0.04, 0.03, 0.25)

    local cMf = cfb and (cfb.MoneyFrame or _G.ContainerFrameCombinedBagsMoneyFrame)
    local cBorder = cMf and (cMf.Border or cMf.Background or cMf.NineSlice)
    local moneyBorderApplied = false

    -- 1. Try Blizzard NineSlice layout from cBorder if available
    if cBorder and cBorder.layoutType and NineSliceUtil and type(NineSliceUtil.ApplyLayoutByName) == "function" then
        local mNs = CreateFrame("Frame", nil, moneyBg)
        mNs:SetAllPoints(moneyBg)
        mNs:SetFrameLevel(moneyBg:GetFrameLevel())
        local okMNS = pcall(NineSliceUtil.ApplyLayoutByName, mNs, cBorder.layoutType, cBorder.layoutTextureKit)
        if okMNS and not HasProtectedChildOrSelf(mNs) and (mNs:GetNumRegions() or 0) >= 3 then
            if mNs.Center then mNs.Center:Hide() end
            moneyBorderApplied = true
            self.moneyTpl = "NineSlice:" .. tostring(cBorder.layoutType)
        else
            mNs:Hide()
        end
    end

    -- 2. Try Blizzard Dragonflight 3-slice pill border atlases
    if not moneyBorderApplied and C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
        local aL = C_Texture.GetAtlasInfo("common-search-border-left")
        local aM = C_Texture.GetAtlasInfo("common-search-border-middle")
        local aR = C_Texture.GetAtlasInfo("common-search-border-right")
        if aL and aM and aR then
            local bL = moneyBg:CreateTexture(nil, "BORDER")
            bL:SetAtlas("common-search-border-left", false)
            bL:SetPoint("TOPLEFT", moneyBg, "TOPLEFT", 0, 0)
            bL:SetPoint("BOTTOMLEFT", moneyBg, "BOTTOMLEFT", 0, 0)
            bL:SetWidth(8)
            local bR = moneyBg:CreateTexture(nil, "BORDER")
            bR:SetAtlas("common-search-border-right", false)
            bR:SetPoint("TOPRIGHT", moneyBg, "TOPRIGHT", 0, 0)
            bR:SetPoint("BOTTOMRIGHT", moneyBg, "BOTTOMRIGHT", 0, 0)
            bR:SetWidth(8)
            local bM = moneyBg:CreateTexture(nil, "BORDER")
            bM:SetAtlas("common-search-border-middle", false)
            bM:SetPoint("TOPLEFT", bL, "TOPRIGHT", 0, 0)
            bM:SetPoint("BOTTOMRIGHT", bR, "BOTTOMLEFT", 0, 0)
            mInner:Hide()
            moneyBorderApplied = true
            self.moneyTpl = "AtlasSearchBorder3Slice"
        end
    end

    -- 3. Fallback: probe ContainerFrameCurrencyBorderTemplate with pre-applied size (require >= 3 regions)
    if not moneyBorderApplied then
        local okCB, cbProbe = pcall(CreateFrame, "Frame", nil, nil, "ContainerFrameCurrencyBorderTemplate")
        if okCB and cbProbe then
            cbProbe:SetSize(172, 22)
            local regCount = 0
            for _, r in ipairs({ cbProbe:GetRegions() }) do
                if r and r.IsObjectType and r:IsObjectType("Texture") and ((r.GetAtlas and r:GetAtlas()) or (r.GetTexture and r:GetTexture())) then
                    regCount = regCount + 1
                end
            end
            if regCount >= 3 and not HasProtectedChildOrSelf(cbProbe) then
                cbProbe:SetParent(moneyBg)
                cbProbe:SetFrameLevel(moneyBg:GetFrameLevel())
                cbProbe:SetAllPoints(moneyBg)
                if not HasProtectedChildOrSelf(f) then
                    mInner:Hide()
                    moneyBorderApplied = true
                    self.moneyTpl = "CurrencyBorderTpl:" .. regCount
                else
                    cbProbe:SetParent(nil)
                    cbProbe:Hide()
                end
            else
                cbProbe:Hide()
            end
        end
    end

    -- 4. Fallback: clone cBorder / cMf border textures (require >= 3 textures)
    if not moneyBorderApplied and cMf then
        local clonedM = 0
        if cBorder then
            clonedM = CloneTextureRegions(cBorder, moneyBg, false)
            if clonedM < 2 and type(cBorder.GetChildren) == "function" then
                for _, ch in ipairs({ cBorder:GetChildren() }) do
                    clonedM = clonedM + CloneTextureRegions(ch, moneyBg, false)
                end
            end
        end
        if clonedM >= 3 then
            moneyBorderApplied = true
            self.moneyTpl = "CloneCMf:" .. tostring(clonedM)
        end
    end

    -- 5. Guaranteed crisp metallic bronze/gold rim bezel
    if not moneyBorderApplied then
        local rimT = moneyBg:CreateTexture(nil, "BORDER")
        rimT:SetPoint("TOPLEFT", moneyBg, "TOPLEFT", 1, 0)
        rimT:SetPoint("TOPRIGHT", moneyBg, "TOPRIGHT", -1, 0)
        rimT:SetHeight(1)
        rimT:SetColorTexture(0.68, 0.56, 0.36, 0.85)
        local rimB = moneyBg:CreateTexture(nil, "BORDER")
        rimB:SetPoint("BOTTOMLEFT", moneyBg, "BOTTOMLEFT", 1, 0)
        rimB:SetPoint("BOTTOMRIGHT", moneyBg, "BOTTOMRIGHT", -1, 0)
        rimB:SetHeight(1)
        rimB:SetColorTexture(0.46, 0.38, 0.24, 0.85)
        local rimL = moneyBg:CreateTexture(nil, "BORDER")
        rimL:SetPoint("TOPLEFT", moneyBg, "TOPLEFT", 0, -1)
        rimL:SetPoint("BOTTOMLEFT", moneyBg, "BOTTOMLEFT", 0, 1)
        rimL:SetWidth(1)
        rimL:SetColorTexture(0.58, 0.48, 0.30, 0.85)
        local rimR = moneyBg:CreateTexture(nil, "BORDER")
        rimR:SetPoint("TOPRIGHT", moneyBg, "TOPRIGHT", 0, -1)
        rimR:SetPoint("BOTTOMRIGHT", moneyBg, "BOTTOMRIGHT", 0, 1)
        rimR:SetWidth(1)
        rimR:SetColorTexture(0.58, 0.48, 0.30, 0.85)
        self.moneyTpl = "CrispBronzeBezel"
    end
    local moneyText = moneyBg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moneyText:SetPoint("RIGHT", moneyBg, "RIGHT", -8, 0)
    moneyText:SetJustifyH("RIGHT")
    self.moneyText = moneyText

    local freeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    freeText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 11)
    freeText:SetPoint("RIGHT", moneyBg, "LEFT", -6, 0)
    freeText:SetJustifyH("LEFT")
    self.freeText = freeText

    local gridAnchor = CreateFrame("Frame", nil, f)
    gridAnchor:SetSize(1, 1)
    gridAnchor:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -11, 38)
    self.gridAnchor = gridAnchor

    local holder = CreateFrame("Frame", "YRGCustomBagHolder", f)
    holder:EnableMouse(false)
    if holder.SetMouseClickEnabled then holder:SetMouseClickEnabled(false) end
    if holder.SetMouseMotionEnabled then holder:SetMouseMotionEnabled(false) end
    holder:SetAllPoints(f)
    holder.GetBagID = function() return 0 end
    holder.MatchesBagID = function(_, id) return type(id) == "number" and id >= 0 and id <= GetReagentBagID() end
    holder.IsBagOpen = function() return customBags.frame and customBags.frame:IsShown() or false end
    holder.IsCombinedBagContainer = function() return true end
    holder.GetBagSize = function(_, id) return GetBagNumSlotsSafe(id or 0) end
    holder.IsPlusTwoBag = function() return false end
    holder.GetPaddingWidth = function() return 0 end
    holder.GetPaddingHeight = function() return 0 end
    holder.SetItemsMatchingBagHighlighted = function() end
    holder.OnBagSlotEnter = function() end
    holder.OnBagSlotLeave = function() end
    self.holder = holder

    f:HookScript("OnShow", function()
        customBags.isOpen = true
        customBags:UpdateFooter()
        if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then
            pcall(PlaySound, SOUNDKIT.IG_BACKPACK_OPEN)
        end
    end)
    f:HookScript("OnHide", function()
        customBags.isOpen = false
        customBags:HideSecureProxy()
        if GameTooltip and type(GameTooltip.IsShown) == "function" and GameTooltip:IsShown()
            and type(GameTooltip.GetOwner) == "function" then
            local okOwn, owner = pcall(GameTooltip.GetOwner, GameTooltip)
            if okOwn and owner then
                if owner == f or owner == customBags.secureProxy or owner == customBags.sortBtn then
                    pcall(GameTooltip.Hide, GameTooltip)
                elseif type(owner.GetParent) == "function" then
                    local p1 = owner:GetParent()
                    local p2 = p1 and type(p1.GetParent) == "function" and p1:GetParent() or nil
                    if p1 == f or p2 == f then
                        pcall(GameTooltip.Hide, GameTooltip)
                    end
                end
            end
        end
        if C_NewItems and type(C_NewItems.ClearAll) == "function" then
            pcall(C_NewItems.ClearAll)
        end
        for _, slotBtn in ipairs(customBags.buttons) do
            if slotBtn then
                if slotBtn.NewItemTexture then slotBtn.NewItemTexture:Hide() end
                if slotBtn.BattlepayItemTexture then slotBtn.BattlepayItemTexture:Hide() end
                if slotBtn.flash then slotBtn.flash:Hide() end
                if slotBtn.newitemglowAnim and type(slotBtn.newitemglowAnim.Stop) == "function" then
                    pcall(slotBtn.newitemglowAnim.Stop, slotBtn.newitemglowAnim)
                end
                if slotBtn.flashAnim and type(slotBtn.flashAnim.Stop) == "function" then
                    pcall(slotBtn.flashAnim.Stop, slotBtn.flashAnim)
                end
                slotBtn._yrgLastState = nil
            end
        end
        if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then
            pcall(PlaySound, SOUNDKIT.IG_BACKPACK_CLOSE)
        end
        if bagDragState.dragging then
            pcall(f.StopMovingOrSizing, f)
            bagDragState.dragging = false
        end
        if customBags.searchBox and customBags.searchBox:GetText() ~= "" then
            customBags.searchBox:SetText("")
        end
        customBags.searchQuery = ""
        if C_Container and type(C_Container.SetItemSearch) == "function" then
            pcall(C_Container.SetItemSearch, "")
        end
    end)

    nativeBagGeom[f] = {
        nativePoint = { pt = "BOTTOMRIGHT", relTo = UIParent, relPt = "BOTTOMRIGHT", x = -32, y = 110 }
    }
    if _G.UISpecialFrames then
        local found = false
        for _, nm in ipairs(_G.UISpecialFrames) do
            if nm == "YRGCombinedBagsFrame" then
                found = true
                break
            end
        end
        if not found then
            table.insert(_G.UISpecialFrames, "YRGCombinedBagsFrame")
        end
    end

    self.frame = f
    return f
end

function customBags:GetOrCreateSlotButton(index, frameLevel, itemW, itemH)
    local btn = self.buttons[index]
    if not btn then
        local tpl = (ContainerFrameCombinedBags and ContainerFrameCombinedBags.itemButtonPool
            and type(ContainerFrameCombinedBags.itemButtonPool.GetTemplate) == "function"
            and ContainerFrameCombinedBags.itemButtonPool:GetTemplate())
            or "ContainerFrameItemButtonTemplate"
        local ok, created = pcall(CreateFrame, "ItemButton", "YRGCustomBagSlot" .. index, self.holder, tpl)
        if not ok or not created then
            created = CreateFrame("ItemButton", "YRGCustomBagSlot" .. index, self.holder, "ContainerFrameItemButtonTemplate")
        end
        btn = created
        btn:SetSize(itemW, itemH)
        if not btn:GetScript("OnDragStart") then
            btn:SetScript("OnDragStart", function(selfBtn)
                if C_Container and type(C_Container.PickupContainerItem) == "function" then
                    C_Container.PickupContainerItem(selfBtn:GetBagID(), selfBtn:GetID())
                elseif type(PickupContainerItem) == "function" then
                    PickupContainerItem(selfBtn:GetBagID(), selfBtn:GetID())
                end
            end)
        end
        if not btn:GetScript("OnReceiveDrag") then
            btn:SetScript("OnReceiveDrag", function(selfBtn)
                if C_Container and type(C_Container.PickupContainerItem) == "function" then
                    C_Container.PickupContainerItem(selfBtn:GetBagID(), selfBtn:GetID())
                elseif type(PickupContainerItem) == "function" then
                    PickupContainerItem(selfBtn:GetBagID(), selfBtn:GetID())
                end
            end)
        end
        if not btn.SplitStack then
            btn.SplitStack = function(selfBtn, split)
                if split and split > 0 then
                    if C_Container and type(C_Container.SplitContainerItem) == "function" then
                        C_Container.SplitContainerItem(selfBtn:GetBagID(), selfBtn:GetID(), split)
                    elseif type(SplitContainerItem) == "function" then
                        SplitContainerItem(selfBtn:GetBagID(), selfBtn:GetID(), split)
                    end
                end
            end
        end
        local origOnClick = btn:GetScript("OnClick")
        if type(origOnClick) == "function" then
            btn:SetScript("OnClick", function(selfBtn, mouseBtn, down)
                if mouseBtn == "LeftButton" and type(SpellIsTargeting) == "function" and SpellIsTargeting() then
                    if not InCombatLockdown() then
                        customBags:AttachSecureProxy(selfBtn)
                    end
                    return
                end
                if mouseBtn == "RightButton" and InCombatLockdown() then
                    if selfBtn.hasItem and UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
                        UIErrorsFrame:AddMessage("Right-clicking bag items is disabled in combat.", 1.0, 0.3, 0.2)
                    end
                    return
                end
                return origOnClick(selfBtn, mouseBtn, down)
            end)
        end
        if type(btn.HookScript) == "function" then
            btn:HookScript("OnEnter", function(selfBtn)
                customBags:AttachSecureProxy(selfBtn)
            end)
            btn:HookScript("OnShow", function(selfBtn)
                local nowT = GetTime and GetTime() or 0
                local bID, sl = selfBtn._yrgCustomBagID, selfBtn._yrgCustomSlot
                local allowNew = bID and sl
                    and not (customBags.suppressSortNewUntil and nowT <= customBags.suppressSortNewUntil)
                    and (C_NewItems and type(C_NewItems.IsNewItem) == "function" and C_NewItems.IsNewItem(bID, sl))
                if not allowNew then
                    if selfBtn.NewItemTexture then selfBtn.NewItemTexture:Hide() end
                    if selfBtn.BattlepayItemTexture then selfBtn.BattlepayItemTexture:Hide() end
                    if selfBtn.flash then selfBtn.flash:Hide() end
                    if selfBtn.newitemglowAnim and type(selfBtn.newitemglowAnim.Stop) == "function" then
                        pcall(selfBtn.newitemglowAnim.Stop, selfBtn.newitemglowAnim)
                    end
                    if selfBtn.flashAnim and type(selfBtn.flashAnim.Stop) == "function" then
                        pcall(selfBtn.flashAnim.Stop, selfBtn.flashAnim)
                    end
                end
            end)
        end
        btn.GetBagID = function(selfBtn)
            return selfBtn.bagID or 0
        end
        self.buttons[index] = btn
    end
    btn:SetFrameStrata(self.frame:GetFrameStrata() or "MEDIUM")
    btn:SetFrameLevel(frameLevel + 3)
    btn:SetSize(itemW, itemH)
    btn:Show()
    return btn
end

function customBags:RefreshSlots()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local db = YRG:GetModuleDB("BetterBagsModule")
    local reagentBagID = GetReagentBagID()
    local tintReagent = (not db or db.reagentBagTintPurple ~= false)
    local query = self.searchQuery or ""

    for _, btn in ipairs(self.buttons) do
        if btn and btn:IsShown() and btn._yrgCustomBagID ~= nil and btn._yrgCustomSlot ~= nil then
            local bID = btn._yrgCustomBagID
            UpdateContainerSlotButton(btn, bID, btn._yrgCustomSlot, tintReagent and (bID == reagentBagID), query)
        end
    end
    self:UpdateFooter()
    self:SyncHoveredSecureProxy()
end

function customBags:ScheduleRefreshSlots()
    if not self.frame or not self.frame:IsShown() then return end
    if self.refreshScheduled then return end
    if C_Timer and type(C_Timer.After) == "function" then
        self.refreshScheduled = true
        C_Timer.After(0, function()
            customBags.refreshScheduled = false
            if customBags.frame and customBags.frame:IsShown() then
                customBags:RefreshSlots()
            end
        end)
    else
        self:RefreshSlots()
    end
end

function customBags:ComputeLayoutKey(db)
    local emptyMode = GetEmptyCellMode(db)
    local sepAmmo = (db and db.separateAmmoBagRow == true) and "1" or "0"
    local tintReagent = (not db or db.reagentBagTintPurple ~= false) and "1" or "0"
    local cScale = YRG.SafeNumber(ContainerFrameCombinedBags and ContainerFrameCombinedBags.GetScale and ContainerFrameCombinedBags:GetScale(), 1)
    local parts = { emptyMode, sepAmmo, tintReagent, string.format("%.2f", cScale) }
    local rBag = GetReagentBagID()
    for bagID = (BACKPACK_CONTAINER or 0), rBag do
        parts[#parts + 1] = tostring(GetBagNumSlotsSafe(bagID))
    end
    return table.concat(parts, "|")
end

function customBags:ApplyLayout(keepHidden)
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not ShouldUseCustomReagentCombinedFrame(db) then
        SyncBlizzardBagParentSuppression(false)
        if self.frame and self.frame:IsShown() and not InCombatLockdown() then
            self.frame:Hide()
        end
        return
    end

    if InCombatLockdown() then
        self.pendingLayout = true
        self:RefreshSlots()
        return
    end

    SyncBlizzardBagParentSuppression(true)
    self.pendingLayout = false
    local f = self:EnsureFrame()
    if ContainerFrameCombinedBags and type(ContainerFrameCombinedBags.GetScale) == "function" then
        local cScale = YRG.SafeNumber(ContainerFrameCombinedBags:GetScale(), 1)
        if cScale > 0.1 and math.abs(YRG.SafeNumber(f:GetScale(), 1) - cScale) >= 0.01 then
            f:SetScale(cScale)
        end
    end

    local reagentBagID = GetReagentBagID()
    local emptyMode = GetEmptyCellMode(db)
    local sepAmmo = (db.separateAmmoBagRow == true)
    local tintReagent = (db.reagentBagTintPurple ~= false)

    local stdList, ammoList, reagList = {}, {}, {}
    for bagID = (NUM_BAG_SLOTS or 4), (BACKPACK_CONTAINER or 0), -1 do
        local nSlots = GetBagNumSlotsSafe(bagID)
        if nSlots > 0 then
            local okAmmo, isAmmo = false, false
            if sepAmmo then
                okAmmo, isAmmo = pcall(IsAmmoOrQuiverBag, bagID)
            end
            local dest = (okAmmo and isAmmo) and ammoList or stdList
            for slot = nSlots, 1, -1 do
                dest[#dest + 1] = { bagID = bagID, slot = slot }
            end
        end
    end
    local nReag = GetBagNumSlotsSafe(reagentBagID)
    for slot = nReag, 1, -1 do
        reagList[#reagList + 1] = { bagID = reagentBagID, slot = slot }
    end

    local hasAmmoSection = sepAmmo and #ammoList > 0
    local hasReagentSection = #reagList > 0
    local effCols = (emptyMode == "DYNAMIC")
        and ChooseDynamicColumns(10, #stdList, hasAmmoSection and #ammoList or 0, #reagList)
        or 10

    local itemW, itemH, stepX, stepY = 37, 37, 42, 42
    local reagentGap = hasReagentSection and 16 or 0
    local ammoGap = hasAmmoSection and 16 or 0
    local reagentRows = hasReagentSection and math.ceil(#reagList / effCols) or 0
    local ammoRows = hasAmmoSection and math.ceil(#ammoList / effCols) or 0
    local stdRows = (#stdList > 0) and math.ceil(#stdList / effCols) or 0

    local reagentOffset = (hasReagentSection and emptyMode ~= "TOP_LEFT") and ((reagentRows * effCols) - #reagList) or 0
    local ammoOffset = (hasAmmoSection and emptyMode ~= "TOP_LEFT") and ((ammoRows * effCols) - #ammoList) or 0
    local stdOffset = (emptyMode ~= "TOP_LEFT" and #stdList > 0) and ((stdRows * effCols) - #stdList) or 0

    local ammoBaseY = (reagentRows * stepY) + reagentGap
    local stdBaseY = ammoBaseY + (ammoRows * stepY) + ammoGap
    local totalGridH = ((reagentRows + ammoRows + stdRows) > 0)
        and ((stdBaseY + (stdRows > 0 and ((stdRows - 1) * stepY + itemH) or -ammoGap)))
        or itemH
    if stdRows == 0 and ammoRows > 0 then
        totalGridH = ammoBaseY + (ammoRows - 1) * stepY + itemH
    elseif stdRows == 0 and ammoRows == 0 and reagentRows > 0 then
        totalGridH = (reagentRows - 1) * stepY + itemH
    end

    local gridW = (effCols - 1) * stepX + itemW
    local targetW = gridW + 22
    local targetH = totalGridH + 66 + 40
    f:SetSize(targetW, targetH)
    local frameLevel = math.max((f.GetFrameLevel and f:GetFrameLevel() or 12), 1)
    self.holder:SetFrameStrata(f:GetFrameStrata() or "MEDIUM")
    self.holder:SetFrameLevel(frameLevel + 2)

    local query = self.searchQuery or ""
    local btnIdx = 0
    local stdEntries, ammoEntries, reagentEntries = {}, {}, {}

    local function BindSection(list, outEntries, isReagentSec)
        for _, item in ipairs(list) do
            btnIdx = btnIdx + 1
            local btn = self:GetOrCreateSlotButton(btnIdx, frameLevel, itemW, itemH)
            btn._yrgCustomBagID = item.bagID
            btn._yrgCustomSlot = item.slot
            UpdateContainerSlotButton(btn, item.bagID, item.slot, isReagentSec and tintReagent, query)
            outEntries[#outEntries + 1] = { button = btn }
        end
    end

    BindSection(stdList, stdEntries, false)
    BindSection(ammoList, ammoEntries, false)
    BindSection(reagList, reagentEntries, true)

    for i = btnIdx + 1, #self.buttons do
        local btn = self.buttons[i]
        if btn then
            btn._yrgCustomBagID = nil
            btn._yrgCustomSlot = nil
            btn._yrgLastState = nil
            btn._yrgLastIcon = nil
            if self.secureProxy and self.secureProxy._targetBtn == btn then
                self:HideSecureProxy()
            end
            btn:Hide()
        end
    end

    if #stdEntries > 0 then
        PlaceItemSectionGrid(stdEntries, self.gridAnchor, 0, stdBaseY, stepX, stepY, effCols, stdOffset)
    end
    if hasAmmoSection then
        PlaceItemSectionGrid(ammoEntries, self.gridAnchor, 0, ammoBaseY, stepX, stepY, effCols, ammoOffset)
        local ammoDivY = ammoBaseY + (ammoRows - 1) * stepY + itemH + (ammoGap + (stepY - itemH)) / 2
        UpdateSectionDividerOverlay("customAmmo", f, self.gridAnchor, frameLevel, 0, ammoDivY, gridW, 0.50)
    else
        HideSectionDivider("customAmmo")
    end
    if hasReagentSection then
        PlaceItemSectionGrid(reagentEntries, self.gridAnchor, 0, 0, stepX, stepY, effCols, reagentOffset)
        local reagDivY = (reagentRows - 1) * stepY + itemH + (reagentGap + (stepY - itemH)) / 2
        UpdateSectionDividerOverlay("customReag", f, self.gridAnchor, frameLevel, 0, reagDivY, gridW, 0.50)
    else
        HideSectionDivider("customReag")
    end

    self.lastLayoutKey = self:ComputeLayoutKey(db)
    self:UpdateFooter()
    if not keepHidden and not f:IsShown() then
        f:Show()
    end
    if not keepHidden then
        self:SyncHoveredSecureProxy()
        if not self._diagCapturedOnce then
            self._diagCapturedOnce = true
            pcall(function()
                local filledSample, emptySample = nil, nil
                local function InspectSlot(btn)
                    local iconTex = btn.icon or btn.Icon
                    local regs = {}
                    if type(btn.GetRegions) == "function" then
                        for _, r in ipairs({ btn:GetRegions() }) do
                            if r and r.IsShown and r:IsShown() then
                                local pk = (r.GetParentKey and r:GetParentKey()) or "?"
                                local lay = (r.GetDrawLayer and r:GetDrawLayer()) or "?"
                                local tx = (r.GetTexture and r:GetTexture()) or ""
                                local alp = (r.GetAlpha and r:GetAlpha()) or -1
                                regs[#regs + 1] = string.format("%s(%s:%.2f=%s)", tostring(pk), tostring(lay), YRG.SafeNumber(alp, -1), tostring(tx))
                            end
                        end
                    end
                    return {
                        bag = btn._yrgCustomBagID,
                        slot = btn._yrgCustomSlot,
                        getBag = btn:GetBagID(),
                        getID = btn:GetID(),
                        hasItem = btn.hasItem and true or false,
                        iconObj = iconTex ~= nil,
                        iconSh = iconTex and iconTex:IsShown() or false,
                        iconTex = iconTex and tostring(iconTex:GetTexture()) or "nil",
                        btnProt = (btn.IsProtected and btn:IsProtected()) and true or false,
                        proxySh = (self.secureProxy and self.secureProxy:IsShown()) and true or false,
                        regs = table.concat(regs, "; "),
                    }
                end
                for i = 1, btnIdx do
                    local b = self.buttons[i]
                    if b then
                        if b.hasItem and not filledSample then
                            filledSample = InspectSlot(b)
                        elseif not b.hasItem and not emptySample then
                            emptySample = InspectSlot(b)
                        end
                        if filledSample and emptySample then break end
                    end
                end
                local protKids = {}
                for _, ch in ipairs({ f:GetChildren() }) do
                    if ch and ch.IsProtected and ch:IsProtected() then
                        protKids[#protKids + 1] = (type(ch.GetDebugName) == "function" and ch:GetDebugName())
                            or (type(ch.GetName) == "function" and ch:GetName())
                            or tostring(ch)
                    end
                end
                local cMfInfo = {}
                local cMf = ContainerFrameCombinedBags and (ContainerFrameCombinedBags.MoneyFrame or _G.ContainerFrameCombinedBagsMoneyFrame)
                if cMf then
                    for _, ch in ipairs({ cMf:GetChildren() }) do
                        local n = (type(ch.GetName) == "function" and ch:GetName()) or tostring(ch)
                        local rc = (type(ch.GetNumRegions) == "function" and ch:GetNumRegions()) or 0
                        local lt = ch.layoutType or ""
                        cMfInfo[#cMfInfo + 1] = string.format("%s(r=%s,lt=%s)", tostring(n), tostring(rc), tostring(lt))
                    end
                end
                db._lastCustomDiag = {
                    w = YRG.SafeNumber(f:GetWidth(), 0),
                    h = YRG.SafeNumber(f:GetHeight(), 0),
                    sc = YRG.SafeNumber(f:GetScale(), 1),
                    bgTpl = self.bgTpl,
                    nsTpl = self.nsTpl,
                    sbTpl = self.sbTpl,
                    moneyTpl = self.moneyTpl,
                    cMfInfo = table.concat(cMfInfo, "; "),
                    frameProt = (f.IsProtected and f:IsProtected()) and true or false,
                    protKids = (#protKids > 0) and table.concat(protKids, ",") or nil,
                    btnCount = btnIdx,
                    std = #stdList,
                    ammo = #ammoList,
                    reag = #reagList,
                    filled = filledSample,
                    empty = emptySample,
                }
            end)
        end
    end
    ApplyNonControllerBagUnlock(f)
end

function customBags:Open()
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not ShouldUseCustomReagentCombinedFrame(db) then return end
    if InCombatLockdown() then
        local f = self.frame
        local diag = {
            hasFrame = f ~= nil,
            isProt = f and f.IsProtected and (select(1, f:IsProtected())) or false,
            wasShown = f and f.IsShown and f:IsShown() or false,
        }
        if f then
            if not f:IsShown() then
                local okS, errS = pcall(f.Show, f)
                diag.okShow = okS and true or false
                diag.errShow = (not okS) and tostring(errS) or nil
            end
            diag.nowShown = f:IsShown()
            self.pendingLayout = true
            self:RefreshSlots()
        end
        db._lastCombatOpenDiag = diag
        return
    end
    local curKey = self:ComputeLayoutKey(db)
    if self.frame and not self.pendingLayout and self.lastLayoutKey == curKey then
        SyncBlizzardBagParentSuppression(true)
        if not self.frame:IsShown() then
            self.frame:Show()
        end
        ApplyNonControllerBagUnlock(self.frame)
        self:RefreshSlots()
    else
        self:ApplyLayout(false)
    end
    if TriggerAutoSortIfEnabled then
        TriggerAutoSortIfEnabled()
    end
    ScheduleClamOpen(0.20)
end

function customBags:Close()
    self:HideSecureProxy()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    end
    self.isOpen = false
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not InCombatLockdown() and ShouldUseCustomReagentCombinedFrame(db) then
        HideBlizzardBagsForCustomMode()
    end
end

function customBags:PrepareHidden()
    if InCombatLockdown() then return end
    local db = YRG:GetModuleDB("BetterBagsModule")
    if ShouldUseCustomReagentCombinedFrame(db) then
        SyncBlizzardBagParentSuppression(true)
        self:ApplyLayout(true)
    else
        if self.frame and self.frame:IsShown() then
            self:Close()
        end
        SyncBlizzardBagParentSuppression(false)
    end
end

local function RestoreCombinedBagsFromMerge(frame)
    HideReagentOverlays()
    HideAmmoOverlay()
    if InCombatLockdown() or not frame or IsFrameProtectedOrForbidden(frame) then return end
    if type(frame.IsShown) ~= "function" or not frame:IsShown() then return end

    local baseCols = (type(frame.GetColumns) == "function" and frame:GetColumns()) or 10
    local anchor = frame.MoneyFrame
    if not anchor or IsFrameProtectedOrForbidden(anchor) then return end

    local itemW, itemH = 37, 37
    if frame.itemButtonPool and type(frame.itemButtonPool.GetTemplate) == "function" then
        local tpl = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(frame.itemButtonPool:GetTemplate())
        if tpl and tpl.width and tpl.height then
            itemW, itemH = tpl.width, tpl.height
        end
    end

    local includeAll = IsControllerUIActive()
    local reagentBagID = GetReagentBagID()
    local stdEntries = {}
    if type(frame.EnumerateValidItems) == "function" then
        for _, btn in frame:EnumerateValidItems() do
            if not IsFrameProtectedOrForbidden(btn)
                and (type(btn.IsShown) ~= "function" or btn:IsShown())
                and (includeAll or btn:GetBagID() ~= reagentBagID) then
                local pt, relTo, relPt, x, y = btn:GetPoint(1)
                if pt == "BOTTOMRIGHT" and relTo == anchor and relPt == "TOPRIGHT"
                    and type(x) == "number" and type(y) == "number" then
                    stdEntries[#stdEntries + 1] = { button = btn, x = x, y = y }
                end
            end
        end
    end

    RunWithApplyingGuard(function()
        if #stdEntries > 0 then
            local baseX, baseY, stepX, stepY = MeasureAndSortItemEntries(stdEntries, frame, itemW, itemH)
            ApplyCombinedBagWidth(frame, baseCols, baseCols, stepX)
            PlaceItemSectionGrid(stdEntries, anchor, baseX, baseY, stepX, stepY, baseCols, 0)
        else
            local geom = nativeBagGeom[frame]
            ApplyCombinedBagWidth(frame, baseCols, baseCols, (geom and geom.stepX) or (itemW + 5))
        end
        if type(frame.CalculateHeight) == "function" then
            local calcH = YRG.SafeNumber(frame:CalculateHeight(), 0)
            local curH = YRG.SafeNumber(frame.GetHeight and frame:GetHeight(), 0)
            if calcH > 0 and math.abs(curH - calcH) >= 0.4 then
                frame:SetHeight(calcH)
            end
        end
        ApplyNonControllerBagUnlock(frame)
    end)
end

local function ApplyNonControllerReagentMerge()
    local db = YRG:GetModuleDB("BetterBagsModule")
    if ShouldUseCustomReagentCombinedFrame(db) then
        SyncBlizzardBagParentSuppression(true)
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
            HideBlizzardBagsForCustomMode()
            if not customBags.isOpen then
                customBags.openedInThisCall = true
                customBags:Open()
                if C_Timer and type(C_Timer.After) == "function" then
                    C_Timer.After(0, function() customBags.openedInThisCall = false end)
                else
                    customBags.openedInThisCall = false
                end
            end
        end
        if BetterBags._statusText then
            BetterBags:UpdateStatusText()
        end
        return
    end

    SyncBlizzardBagParentSuppression(false)
    if customBags.frame and customBags.frame:IsShown() and not InCombatLockdown() then
        customBags:Close()
    end

    if applying then return end
    if InCombatLockdown() then
        pending = true
        return
    end

    local frame = ContainerFrameCombinedBags
    if not db or not db.enabled or IsControllerUIActive()
        or not frame or not frame:IsShown()
        or IsFrameProtectedOrForbidden(frame) then
        RestoreCombinedBagsFromMerge(frame)
        return
    end

    local emptyMode = GetEmptyCellMode(db)
    local sepAmmo = (db.separateAmmoBagRow == true)
    if emptyMode == "TOP_LEFT" and not sepAmmo then
        RestoreCombinedBagsFromMerge(frame)
        return
    end

    local baseCols = frame.GetColumns and frame:GetColumns() or 10
    if not baseCols or baseCols < 1 or not frame.itemButtonPool or type(frame.itemButtonPool.GetTemplate) ~= "function" then
        HideReagentOverlays()
        HideAmmoOverlay()
        return
    end
    local templateName = frame.itemButtonPool:GetTemplate()
    local template = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(templateName)
    if not template or not template.width or not template.height then
        HideReagentOverlays()
        HideAmmoOverlay()
        return
    end
    local anchor = frame.MoneyFrame
    if not anchor or IsFrameProtectedOrForbidden(anchor) then
        HideReagentOverlays()
        HideAmmoOverlay()
        return
    end

    -- Collect regular combined bag items and optionally separate Quiver / Ammo Pouch items
    local reagentBagID = GetReagentBagID()
    local itemW, itemH = template.width, template.height
    local allEntries, ammoEntries, stdEntries = {}, {}, {}
    for _, btn in frame:EnumerateValidItems() do
        if IsFrameProtectedOrForbidden(btn) then return end
        local okBag, bID = pcall(btn.GetBagID, btn)
        bID = okBag and bID or btn.bagID
        if (type(btn.IsShown) ~= "function" or btn:IsShown()) and bID ~= reagentBagID then
            local pt, relTo, relPt, x, y = btn:GetPoint(1)
            if not pt then
                ScheduleUnifiedBagLayout()
                return
            end
            if pt ~= "BOTTOMRIGHT" or relTo ~= anchor or relPt ~= "TOPRIGHT"
                or type(x) ~= "number" or type(y) ~= "number" then
                HideReagentOverlays()
                HideAmmoOverlay()
                return
            end
            local entry = { button = btn, x = x, y = y }
            allEntries[#allEntries + 1] = entry
            local okAmmo, isAmmo = false, false
            if sepAmmo then
                okAmmo, isAmmo = pcall(IsAmmoOrQuiverBag, bID)
            end
            if okAmmo and isAmmo then
                ammoEntries[#ammoEntries + 1] = entry
            else
                stdEntries[#stdEntries + 1] = entry
            end
        end
    end

    local hasAmmoSection = sepAmmo and #ammoEntries > 0
    if #allEntries == 0 then
        HideReagentOverlays()
        HideAmmoOverlay()
        return
    end
    if not hasAmmoSection and emptyMode == "TOP_LEFT" then
        RestoreCombinedBagsFromMerge(frame)
        return
    end

    local baseX, baseY, stepX, stepY = MeasureAndSortItemEntries(allEntries, frame, itemW, itemH)
    SortItemEntriesByGrid(ammoEntries, stepY)
    SortItemEntriesByGrid(stdEntries, stepY)

    local effCols = (emptyMode == "DYNAMIC")
        and ChooseDynamicColumns(baseCols, #stdEntries, hasAmmoSection and #ammoEntries or 0, 0)
        or baseCols
    local ammoGap = hasAmmoSection and 16 or 0
    local ammoBottomPad = hasAmmoSection and 6 or 0
    if nativeBagGeom[frame] then
        nativeBagGeom[frame].padOffset = ammoBottomPad
    end
    local ammoBaseY = baseY + ammoBottomPad
    local ammoRows = hasAmmoSection and math.ceil(#ammoEntries / effCols) or 0
    local stdRows = (#stdEntries > 0) and math.ceil(#stdEntries / effCols) or 0

    local ammoOffset = (hasAmmoSection and emptyMode ~= "TOP_LEFT") and ((ammoRows * effCols) - #ammoEntries) or 0
    local stdOffset = (emptyMode ~= "TOP_LEFT" and #stdEntries > 0) and ((stdRows * effCols) - #stdEntries) or 0

    local stdBaseY = ammoBaseY + (ammoRows * stepY) + ammoGap
    local frameRows = (type(frame.GetRows) == "function" and YRG.SafeNumber(frame:GetRows(), 0)) or 0
    local calcHeight = (type(frame.CalculateHeight) == "function" and YRG.SafeNumber(frame:CalculateHeight(), 0)) or 0
    local targetHeight = calcHeight + ((stdRows + ammoRows) - frameRows) * stepY + ammoGap + ammoBottomPad

    RunWithApplyingGuard(function()
        ApplyNonControllerBagUnlock(frame)
        ApplyCombinedBagWidth(frame, baseCols, effCols, stepX)

        local frameLevel = math.max((frame.GetFrameLevel and frame:GetFrameLevel() or 1), 1)
        local curH = YRG.SafeNumber(frame.GetHeight and frame:GetHeight(), 0)
        if targetHeight > 0 and math.abs(curH - targetHeight) >= 0.4 then
            frame:SetHeight(targetHeight)
        end

        if #stdEntries > 0 then
            PlaceItemSectionGrid(stdEntries, anchor, baseX, stdBaseY, stepX, stepY, effCols, stdOffset)
        end

        if hasAmmoSection then
            PlaceItemSectionGrid(ammoEntries, anchor, baseX, ammoBaseY, stepX, stepY, effCols, ammoOffset)
            local ammoDivY = ammoBaseY + (ammoRows - 1) * stepY + itemH + (ammoGap + (stepY - itemH)) / 2
            UpdateSectionDividerOverlay(true, frame, anchor, frameLevel, baseX, ammoDivY, (effCols - 1) * stepX + itemW, 0.50)
        else
            HideAmmoOverlay()
        end
    end)

    if BetterBags._statusText then
        BetterBags:UpdateStatusText()
    end
end

ApplyUnifiedBagLayout = function()
    if customBags.hidingBlizzard then return end
    if IsControllerUIActive() then
        bagDragState.dragging = false
        customBags:Close()
        HideReagentOverlays()
        ApplyControllerBagStripLayout()
        RefreshNativeBagGreyItems()
    else
        HideDividerOverlay()
        ResetDualZoneNavState()
        ResetControllerBagButtonScales()
        ApplyNonControllerReagentMerge()
        RefreshNativeBagGreyItems()
    end
end

-- =========================================================================
-- ALL-MODE BAG AUTOMATION (Works in Keyboard/Mouse AND Controller Mode)
-- =========================================================================
ExecuteBagSort = function()
    if InCombatLockdown() then return end
    customBags.suppressSortNewUntil = (GetTime and GetTime() or 0) + 1.5
    if C_Container and type(C_Container.SortBags) == "function" then
        C_Container.SortBags()
    elseif type(SortBags) == "function" then
        SortBags()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.35, function()
            if not isLootingWindowOpen and C_NewItems and type(C_NewItems.ClearAll) == "function" then
                pcall(C_NewItems.ClearAll)
            end
            if customBags.frame and customBags.frame:IsShown() then
                customBags:ScheduleRefreshSlots()
            end
        end)
    end
end

TriggerAutoSortIfEnabled = function()
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

local waylaid = {
    nameCache = {},
    altKeysByID = {},
    indexTicker = nil,
    loadTicker = nil,
    indexDone = false,
    indexedCount = 0,
    hookInstalled = false,
    decorating = false,
    pendingTooltip = nil,
    refreshTimer = nil,
    measureFrame = nil,
    measureFS = nil,
}

local function StripTooltipTags(str)
    if type(str) ~= "string" then return "" end
    local s = str:gsub("|cn[^:]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("|H.-|h%[(.-)%]|h", "%1")
    return s
end

local function IsAuctionatorAPIAvailable()
    return _G.Auctionator ~= nil
        and type(_G.Auctionator.API) == "table"
        and type(_G.Auctionator.API.v1) == "table"
        and type(_G.Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

function waylaid:StopTicker()
    if self.indexTicker and type(self.indexTicker.Cancel) == "function" then
        self.indexTicker:Cancel()
    end
    self.indexTicker = nil
    if self.loadTicker and type(self.loadTicker.Cancel) == "function" then
        self.loadTicker:Cancel()
    end
    self.loadTicker = nil
end

function waylaid:CacheItemIDName(itemID, itemName)
    if type(itemID) ~= "number" or itemID <= 0 or type(itemName) ~= "string" or itemName == "" then return end
    local norm = itemName:gsub("%s+", " "):lower()
    if not self.nameCache[norm] then
        self.indexedCount = (self.indexedCount or 0) + 1
    end
    self.nameCache[norm] = itemID
end

function waylaid:NotifyItemLoaded()
    if not self.pendingTooltip or self.refreshTimer then return end
    if not (C_Timer and type(C_Timer.After) == "function") then return end
    self.refreshTimer = true
    C_Timer.After(0.15, function()
        self.refreshTimer = nil
        local tip = self.pendingTooltip
        if tip and not self.decorating and type(tip.IsShown) == "function" and tip:IsShown() then
            self:DecorateTooltip(tip)
        end
    end)
end

function waylaid:MeasureMaxLineWidth(text, templateFS)
    if type(text) ~= "string" or text == "" then return 0 end
    if not self.measureFrame and CreateFrame and UIParent then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(1, 1)
        f:Hide()
        local fs = f:CreateFontString(nil, "ARTWORK", "GameTooltipText")
        if type(fs.SetWordWrap) == "function" then
            pcall(fs.SetWordWrap, fs, false)
        end
        self.measureFrame = f
        self.measureFS = fs
    end
    local fs = self.measureFS
    if not fs then
        return #StripTooltipTags(text) * 7
    end
    if templateFS and type(templateFS.GetFont) == "function" and type(fs.SetFont) == "function" then
        local fontPath, fontSize, fontFlags = templateFS:GetFont()
        if fontPath and fontSize then
            pcall(fs.SetFont, fs, fontPath, fontSize, fontFlags)
        end
    end
    local maxW = 0
    local startPos = 1
    while true do
        local nl = text:find("\n", startPos, true)
        local sub = nl and text:sub(startPos, nl - 1) or text:sub(startPos)
        if sub ~= "" then
            fs:SetText(sub)
            local w = 0
            if type(fs.GetUnboundedStringWidth) == "function" then
                w = YRG.SafeNumber(fs:GetUnboundedStringWidth(), 0)
            end
            if w <= 0 and type(fs.GetStringWidth) == "function" then
                w = YRG.SafeNumber(fs:GetStringWidth(), 0)
            end
            local _, texCount = sub:gsub("|T", "")
            local totalW = w + (texCount * 5)
            if totalW > maxW then
                maxW = totalW
            end
        end
        if not nl then break end
        startPos = nl + 1
    end
    return maxW
end

local function StripLeadingBullets(str)
    if type(str) ~= "string" then return "" end
    local prev
    local s = str
    repeat
        prev = s
        s = s:gsub("^[%s%-%*]+", "")
        s = s:gsub("^•", ""):gsub("^·", "")
    until s == prev
    return s
end

function waylaid:EnsureNameIndex(rescan)
    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled or db.waylaidCrateCosts == false then return end
    if type(db.waylaidNameIDMap) == "table" then
        for nmLow, savedID in pairs(db.waylaidNameIDMap) do
            if type(nmLow) == "string" and type(savedID) == "number" and savedID > 0 and not self.nameCache[nmLow] then
                self.nameCache[nmLow] = savedID
            end
        end
    end
    if not (_G.Auctionator and _G.Auctionator.Database and type(_G.Auctionator.Database.db) == "table") then return end
    if rescan then
        self:StopTicker()
        self.indexDone = false
    end
    if self.indexDone or self.indexTicker then return end

    local tier1Keys = {}
    local tier2Keys = {}
    local tier3Keys = {}
    local seenIDs = {}
    self.altKeysByID = {}
    local getInstant = C_Item and type(C_Item.GetItemInfoInstant) == "function" and C_Item.GetItemInfoInstant or GetItemInfoInstant
    for k in pairs(_G.Auctionator.Database.db) do
        local idNum = nil
        local isSuffix = false
        if type(k) == "number" then
            idNum = k
        elseif type(k) == "string" then
            local plainStr = k:match("^(%d+)$")
            if plainStr then
                idNum = tonumber(plainStr)
            else
                local grStr = k:match("^gr?:(%d+):")
                if grStr then
                    idNum = tonumber(grStr)
                    isSuffix = true
                    local list = self.altKeysByID[idNum]
                    if not list then
                        list = {}
                        self.altKeysByID[idNum] = list
                    end
                    list[#list + 1] = k
                else
                    idNum = tonumber(k:match("^(%d+):"))
                end
            end
        end
        if idNum and idNum > 0 and not seenIDs[idNum] then
            seenIDs[idNum] = true
            if isSuffix then
                tier3Keys[#tier3Keys + 1] = idNum
            else
                local classID = nil
                if type(getInstant) == "function" then
                    local okI, _, _, _, _, _, cID = pcall(getInstant, idNum)
                    if okI then classID = cID end
                end
                if classID == 7 or classID == 0 then
                    tier1Keys[#tier1Keys + 1] = idNum
                elseif classID == 1 or classID == 2 or classID == 4 or classID == 5 or classID == 6 or classID == nil then
                    tier2Keys[#tier2Keys + 1] = idNum
                else
                    tier3Keys[#tier3Keys + 1] = idNum
                end
            end
        end
    end

    local keys = {}
    for i = 1, #tier1Keys do keys[#keys + 1] = tier1Keys[i] end
    for i = 1, #tier2Keys do keys[#keys + 1] = tier2Keys[i] end
    for i = 1, #tier3Keys do keys[#keys + 1] = tier3Keys[i] end

    if #keys == 0 then
        self.indexDone = true
        return
    end

    local idx = 1
    local uncached = {}
    local getNameByID = C_Item and type(C_Item.GetItemNameByID) == "function" and C_Item.GetItemNameByID or nil
    local isCachedByID = C_Item and type(C_Item.IsItemDataCachedByID) == "function" and C_Item.IsItemDataCachedByID or nil
    local reqLoadByID = C_Item and type(C_Item.RequestLoadItemDataByID) == "function" and C_Item.RequestLoadItemDataByID or nil
    local hasItemMixin = (_G.Item and type(_G.Item.CreateFromItemID) == "function") and true or false

    local function FinishScan()
        self:StopTicker()
        self.indexDone = true
        if #uncached > 0 and C_Timer and type(C_Timer.NewTicker) == "function" then
            local uIdx = 1
            self.loadTicker = C_Timer.NewTicker(0.04, function()
                local stopU = math.min(uIdx + 29, #uncached)
                for i = uIdx, stopU do
                    local idNum = uncached[i]
                    local nm = (getNameByID and getNameByID(idNum)) or SafeGetItemInfo(idNum)
                    if type(nm) == "string" and nm ~= "" then
                        self:CacheItemIDName(idNum, nm)
                        self:NotifyItemLoaded()
                    elseif hasItemMixin then
                        local okCreate, itemObj = pcall(_G.Item.CreateFromItemID, _G.Item, idNum)
                        if okCreate and itemObj and type(itemObj.ContinueOnItemLoad) == "function" then
                            pcall(itemObj.ContinueOnItemLoad, itemObj, function()
                                local loadedName = (getNameByID and getNameByID(idNum)) or SafeGetItemInfo(idNum)
                                if type(loadedName) == "string" and loadedName ~= "" then
                                    self:CacheItemIDName(idNum, loadedName)
                                    self:NotifyItemLoaded()
                                end
                            end)
                        elseif reqLoadByID then
                            pcall(reqLoadByID, idNum)
                        end
                    elseif reqLoadByID then
                        pcall(reqLoadByID, idNum)
                    end
                end
                uIdx = stopU + 1
                if uIdx > #uncached then
                    if self.loadTicker and type(self.loadTicker.Cancel) == "function" then
                        self.loadTicker:Cancel()
                    end
                    self.loadTicker = nil
                end
            end)
        end
    end

    local function StepBatch()
        local stopAt = math.min(idx + 999, #keys)
        for i = idx, stopAt do
            local idNum = keys[i]
            local nm = getNameByID and getNameByID(idNum)
            if (not nm or nm == "") and (not isCachedByID or isCachedByID(idNum)) then
                nm = SafeGetItemInfo(idNum)
            end
            if type(nm) == "string" and nm ~= "" then
                self:CacheItemIDName(idNum, nm)
            else
                uncached[#uncached + 1] = idNum
            end
        end
        idx = stopAt + 1
        if idx > #keys then
            FinishScan()
        end
    end

    if C_Timer and type(C_Timer.NewTicker) == "function" then
        self.indexTicker = C_Timer.NewTicker(0.02, StepBatch)
    else
        while idx <= #keys do
            StepBatch()
        end
    end
end

function waylaid:LookupItemAndPrice(rawName, embeddedID)
    if not IsAuctionatorAPIAvailable() then return nil, nil end
    local itemID = tonumber(embeddedID)
    local itemLink = nil

    if itemID and itemID > 0 then
        local nm, lk = SafeGetItemInfo(itemID)
        if nm then self:CacheItemIDName(itemID, nm) end
        itemLink = lk
    else
        local clean = StripLeadingBullets(StripTooltipTags(rawName or "")):gsub("[%s%.,;:]+$", "")
        clean = clean:gsub("^%[(.-)%]$", "%1"):gsub("%s+", " ")
        if clean == "" or #clean < 3 then return nil, nil end

        local cands = { clean }
        local seenC = { [clean:lower()] = true }
        local function AddCand(s)
            if type(s) == "string" and s ~= "" then
                local k = s:lower()
                if not seenC[k] then
                    seenC[k] = true
                    cands[#cands + 1] = s
                end
            end
        end

        local low = clean:lower()
        if #clean > 4 and low:sub(-3) == "ies" then
            AddCand(clean:sub(1, -4) .. "y")
        elseif #clean > 3 and low:sub(-2) == "es" then
            AddCand(clean:sub(1, -3))
        elseif #clean > 2 and low:sub(-1) == "s" then
            AddCand(clean:sub(1, -2))
        end
        -- Plural first noun in "...s of ..." (e.g. "Bolts of Linen Cloth", "Elixirs of Firepower")
        AddCand((clean:gsub("^([^%s]+)ies%s+([oO][fF]%s+)", "%1y %2")))
        AddCand((clean:gsub("^([^%s]+)[sS]%s+([oO][fF]%s+)", "%1 %2")))

        local db = YRG:GetModuleDB("BetterBagsModule")
        local savedMap = db and db.waylaidNameIDMap or nil
        for _, cand in ipairs(cands) do
            local cLow = cand:lower()
            local cachedID = self.nameCache[cLow]
            if not cachedID and savedMap and type(savedMap[cLow]) == "number" and savedMap[cLow] > 0 then
                cachedID = savedMap[cLow]
                self.nameCache[cLow] = cachedID
            end
            if cachedID then
                itemID = cachedID
                local _, lk = SafeGetItemInfo(cachedID)
                itemLink = lk
                break
            end
            local nm, lk = SafeGetItemInfo(cand)
            if nm and lk then
                local parsed = tonumber(lk:match("item:(%d+)"))
                if parsed then
                    itemID = parsed
                    itemLink = lk
                    self:CacheItemIDName(parsed, nm)
                    break
                end
            end
        end
        if itemID and itemID > 0 and db then
            db.waylaidNameIDMap = db.waylaidNameIDMap or {}
            db.waylaidNameIDMap[clean:lower()] = itemID
        end
    end

    if not itemID or itemID <= 0 then return nil, nil end

    local unitPrice = nil
    if itemLink and type(_G.Auctionator.API.v1.GetAuctionPriceByItemLink) == "function" then
        local okL, pL = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemLink, "YRG", itemLink)
        if okL then
            unitPrice = YRG.SafeOptionalNumber(pL)
        end
    end
    if unitPrice == nil then
        local okI, pI = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID, "YRG", itemID)
        if okI then
            unitPrice = YRG.SafeOptionalNumber(pI)
        end
    end
    if unitPrice == nil and self.altKeysByID[itemID]
        and _G.Auctionator.Database and type(_G.Auctionator.Database.GetPrice) == "function" then
        for _, altKey in ipairs(self.altKeysByID[itemID]) do
            local okA, pA = pcall(_G.Auctionator.Database.GetPrice, _G.Auctionator.Database, altKey)
            local nA = okA and YRG.SafeOptionalNumber(pA) or nil
            if nA and (unitPrice == nil or nA < unitPrice) then
                unitPrice = nA
            end
        end
    end
    return itemID, unitPrice
end

local WAYLAID_IGNORE_PREFIXES = {
    "^requires level",
    "^item level",
    "^sell price",
    "^soulbound",
    "^binds ",
    "^unique",
    "^classes:",
    "^races:",
    "^merchant's favor",
    "^deliver to ",
}

local function ShouldIgnoreChoiceText(lowText)
    for _, pat in ipairs(WAYLAID_IGNORE_PREFIXES) do
        if lowText:find(pat) then
            return true
        end
    end
    return false
end

function waylaid:MatchChoiceSegment(seg)
    if type(seg) ~= "string" or seg == "" then return nil end
    if seg:find("|cff40ff40[", 1, true) or seg:find("|cffffe066[", 1, true) then
        return nil
    end

    local embeddedID = tonumber(seg:match("|Hitem:(%d+)"))
    local plain = StripTooltipTags(seg)
    local core = StripLeadingBullets(plain)
    local leadLen = #plain - #core
    local coreTrimmed, trailPunct = core:match("^(.-)([%s%.,;:]*)$")
    if not coreTrimmed or coreTrimmed == "" then return nil end
    if ShouldIgnoreChoiceText(coreTrimmed:lower()) then return nil end
    -- Strip optional trailing progress like "(0/20)" before count extraction
    local baseTrimmed, progMax = coreTrimmed:match("^(.-)%s*%(%s*%d+%s*/%s*(%d+)%s*%)$")
    if baseTrimmed and progMax then
        coreTrimmed = baseTrimmed
    end

    local count, itemName = nil, nil
    -- Pattern 0: "0/20 Peacebloom"
    local pHave, pNeed, n0 = coreTrimmed:match("^(%d+)%s*/%s*(%d+)%s+(.+)$")
    if pHave and pNeed and n0 then
        count, itemName = tonumber(pNeed), n0
    end
    -- Pattern 1: "20x Peacebloom", "20 x Peacebloom", "20 Peacebloom", "x20 Peacebloom"
    if not itemName then
        local c1, n1 = coreTrimmed:match("^(%d+)%s*[xX]?%s+(.+)$")
        if c1 and n1 then
            count, itemName = tonumber(c1), n1
        else
            local c1b, n1b = coreTrimmed:match("^[xX]?(%d+)[xX]%s*(.+)$")
            if c1b and n1b then
                count, itemName = tonumber(c1b), n1b
            end
        end
    end
    -- Pattern 2: "Peacebloom x20", "Peacebloom (20)", "Peacebloom (x20)"
    if not itemName then
        local n2, c2 = coreTrimmed:match("^(.-)%s+[xX]%s*(%d+)$")
        if n2 and c2 then
            itemName, count = n2, tonumber(c2)
        else
            local n2b, c2b = coreTrimmed:match("^(.-)%s*%([xX]?%s*(%d+)%)$")
            if n2b and c2b then
                itemName, count = n2b, tonumber(c2b)
            end
        end
    end
    -- Pattern 3: Standalone unnumbered bullet/progressed item (e.g. "- Ornate Spyglass")
    if not itemName and (leadLen > 0 or embeddedID or progMax) and #coreTrimmed >= 4 then
        itemName, count = coreTrimmed, tonumber(progMax) or 1
    end

    if not itemName or not count or count < 1 then return nil end
    local itemID, unitPrice = self:LookupItemAndPrice(itemName, embeddedID)
    if not itemID then return nil end

    return {
        itemID = itemID,
        count = count,
        unitPrice = unitPrice,
        totalPrice = unitPrice and math.floor(unitPrice * count + 0.5) or nil,
        trailPunct = trailPunct or "",
    }
end

local function FormatWaylaidMoney(copper)
    local val = math.max(0, math.floor((tonumber(copper) or 0) + 0.5))
    local coinFn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if type(coinFn) == "function" then
        local okC, s = pcall(coinFn, val, 11)
        if (not okC) or type(s) ~= "string" or s == "" then
            okC, s = pcall(coinFn, val)
        end
        if okC and type(s) == "string" and s ~= "" then
            return s
        end
    end
    local g = math.floor(val / 10000)
    local sil = math.floor((val % 10000) / 100)
    local cop = val % 100
    if g > 0 then
        return string.format("%dg %02ds %02dc", g, sil, cop)
    elseif sil > 0 then
        return string.format("%ds %02dc", sil, cop)
    end
    return string.format("%dc", cop)
end

local function InjectBracketBeforeTrailingTags(segment, bracketText)
    local i = #segment
    while i >= 1 do
        local c = segment:sub(i, i)
        if c == " " or c == "\t" or c == "\r" or c == "." or c == "," or c == ";" or c == ":" then
            i = i - 1
        elseif i >= 2 and segment:sub(i - 1, i) == "|r" then
            i = i - 2
        else
            break
        end
    end
    local body = segment:sub(1, i)
    local endTags = segment:sub(i + 1)
    if body == "" then
        return segment .. " " .. bracketText
    end
    return body .. " " .. bracketText .. endTags
end

local function WrapProseLine(text, maxChars)
    maxChars = maxChars or 44
    if type(text) ~= "string" or #StripTooltipTags(text) <= maxChars then
        return text
    end
    if text:find("|H", 1, true) or text:find("|T", 1, true) or text:find("|A", 1, true) then
        return text
    end
    local out = {}
    local cur = ""
    local curVis = 0
    for word in text:gmatch("%S+") do
        local wVis = #StripTooltipTags(word)
        if cur == "" then
            cur = word
            curVis = wVis
        elseif curVis + 1 + wVis <= maxChars then
            cur = cur .. " " .. word
            curVis = curVis + 1 + wVis
        else
            out[#out + 1] = cur
            cur = word
            curVis = wVis
        end
    end
    if cur ~= "" then
        out[#out + 1] = cur
    end
    return (#out > 0) and table.concat(out, "\n") or text
end

function waylaid:SplitProseClauses(subLine)
    -- First handle leading "Use: ...:" or "... with 20x Item..." prose prefix if present
    local prefix = ""
    local work = subLine
    local colonPos = subLine:find(":", 1, true)
    if colonPos then
        local headLow = StripTooltipTags(subLine:sub(1, colonPos)):lower()
        if headLow:find("use") or headLow:find("deliver") or headLow:find("fill")
            or headLow:find("requires") or headLow:find("missing")
            or headLow:find("contents") or headLow:find("following") then
            local afterColon = subLine:sub(colonPos + 1)
            local ws = afterColon:match("^(%s*)") or ""
            prefix = subLine:sub(1, colonPos) .. ws
            work = afterColon:sub(#ws + 1)
        end
    end
    if not work:match("^%s*%d") then
        local pHead, pRest = work:match("^(.-%s+with%s+)(%d.*)$")
        if not pHead then
            pHead, pRest = work:match("^([Dd]eliver%s+)(%d.*)$")
        end
        if not pHead then
            pHead, pRest = work:match("^([Rr]equires%s+)(%d.*)$")
        end
        if pHead and pRest then
            prefix = prefix .. pHead
            work = pRest
        end
    end

    -- Check if the whole remainder already matches a single item choice
    if self:MatchChoiceSegment(work) then
        return { { kind = "prefix", text = prefix }, { kind = "clause", text = work } }
    end

    -- Otherwise split inline lists on ",", ";", ", or ", " or "
    local parts = {}
    if prefix ~= "" then
        parts[#parts + 1] = { kind = "prefix", text = prefix }
    end
    local pos = 1
    local len = #work
    while pos <= len do
        local s1, e1 = work:find(",%s+[oO][rR]%s+", pos)
        local s2, e2 = work:find("%s+[oO][rR]%s+", pos)
        local s3, e3 = work:find("[,;]%s*", pos)
        local bestS, bestE = nil, nil
        for _, cand in ipairs({ { s1, e1 }, { s2, e2 }, { s3, e3 } }) do
            if cand[1] and (not bestS or cand[1] < bestS) then
                bestS, bestE = cand[1], cand[2]
            end
        end
        if bestS then
            local seg = work:sub(pos, bestS - 1)
            if seg ~= "" then
                parts[#parts + 1] = { kind = "clause", text = seg }
            end
            parts[#parts + 1] = { kind = "sep", text = work:sub(bestS, bestE) }
            pos = bestE + 1
        else
            parts[#parts + 1] = { kind = "clause", text = work:sub(pos) }
            break
        end
    end
    return parts
end

function waylaid:DecorateTooltip(tooltip)
    if self.decorating or not tooltip then return end
    if type(tooltip.IsForbidden) == "function" and tooltip:IsForbidden() then return end
    local tName = type(tooltip.GetName) == "function" and tooltip:GetName() or nil
    if not tName then return end

    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled or db.waylaidCrateCosts == false then return end
    if not IsAuctionatorAPIAvailable() then return end

    local left1 = _G[tName .. "TextLeft1"]
    local titleText = left1 and type(left1.GetText) == "function" and YRG.SafeString(left1:GetText(), nil)
    if not titleText then return end
    local titleLow = StripTooltipTags(titleText):lower()
    if not titleLow:find("waylaid crate", 1, true) and not titleLow:find("waylaid supplies", 1, true) then
        return
    end

    self:EnsureNameIndex(false)

    local numLines = YRG.SafeNumber(tooltip.NumLines and tooltip:NumLines(), 0)
    if numLines < 2 then return end

    local lineRecords = {}
    local minCost = nil
    local rawLinesDiag = {}

    for lineIdx = 2, numLines do
        local leftFS = _G[tName .. "TextLeft" .. lineIdx]
        local rightFS = _G[tName .. "TextRight" .. lineIdx]
        local rightTxt = rightFS and type(rightFS.GetText) == "function" and YRG.SafeString(rightFS:GetText(), nil)
        local txt = leftFS and type(leftFS.GetText) == "function" and YRG.SafeString(leftFS:GetText(), nil)
        if txt and txt ~= "" and (not rightTxt or rightTxt == "") then
            local cleanTxt = txt:gsub("\r\n", "\n"):gsub("\r", "")
            rawLinesDiag[#rawLinesDiag + 1] = StripTooltipTags(cleanTxt)
            local subLines = {}
            local startPos = 1
            while true do
                local nl = cleanTxt:find("\n", startPos, true)
                if nl then
                    subLines[#subLines + 1] = cleanTxt:sub(startPos, nl - 1)
                    startPos = nl + 1
                else
                    subLines[#subLines + 1] = cleanTxt:sub(startPos)
                    break
                end
            end

            local subRecords = {}
            local lineHasMatch = false
            for _, sub in ipairs(subLines) do
                local parts = self:SplitProseClauses(sub)
                for _, part in ipairs(parts) do
                    if part.kind == "clause" then
                        local match = self:MatchChoiceSegment(part.text)
                        if match then
                            part.match = match
                            lineHasMatch = true
                            if match.totalPrice ~= nil and (minCost == nil or match.totalPrice < minCost) then
                                minCost = match.totalPrice
                            end
                        end
                    end
                end
                subRecords[#subRecords + 1] = parts
            end

            if lineHasMatch then
                lineRecords[#lineRecords + 1] = {
                    fs = leftFS,
                    subRecords = subRecords,
                }
            end
        end
    end

    local matchedCount = 0
    local pricedCount = 0
    local unmatchedBullet = false
    if #lineRecords > 0 then
        self.decorating = true
        local widenedAny = false
        local targetMinW = 0
        local checkFSList = {}
        for _, rec in ipairs(lineRecords) do
            local linePriced = false
            local rebuiltSubs = {}
            for _, parts in ipairs(rec.subRecords) do
                local buf = {}
                local subHasPriced = false
                for _, part in ipairs(parts) do
                    if part.match then
                        matchedCount = matchedCount + 1
                        local m = part.match
                        if m.totalPrice ~= nil then
                            pricedCount = pricedCount + 1
                            linePriced = true
                            subHasPriced = true
                            local color = (minCost ~= nil and m.totalPrice == minCost) and "|cff40ff40" or "|cffffe066"
                            local bracket = color .. "[" .. FormatWaylaidMoney(m.totalPrice) .. "]|r"
                            buf[#buf + 1] = InjectBracketBeforeTrailingTags(part.text, bracket)
                        else
                            buf[#buf + 1] = part.text
                        end
                    else
                        if part.kind == "clause" and type(part.text) == "string" then
                            local trimmed = StripLeadingBullets(StripTooltipTags(part.text))
                            if trimmed:match("^%d+%s+") or trimmed:match("^[xX]?%d+[xX]%s+") then
                                unmatchedBullet = true
                            end
                        end
                        buf[#buf + 1] = part.text
                    end
                end
                local joinedSub = table.concat(buf)
                local alreadyBracketed = joinedSub:find("|cff40ff40[", 1, true) or joinedSub:find("|cffffe066[", 1, true)
                if not subHasPriced and not alreadyBracketed then
                    joinedSub = WrapProseLine(joinedSub, 40)
                end
                rebuiltSubs[#rebuiltSubs + 1] = joinedSub
            end
            if linePriced then
                local finalText = table.concat(rebuiltSubs, "\n")
                local maxLineW = self:MeasureMaxLineWidth(finalText, rec.fs)
                local neededFSW = math.min(math.ceil(maxLineW + 22), 460)
                rec.fs:SetText(finalText)
                widenedAny = true
                if neededFSW > 0 then
                    if type(rec.fs.SetWidth) == "function" then
                        pcall(rec.fs.SetWidth, rec.fs, neededFSW)
                    end
                    targetMinW = math.max(targetMinW, math.ceil(neededFSW + 30))
                    checkFSList[#checkFSList + 1] = { fs = rec.fs, neededW = neededFSW }
                end
            end
        end
        if widenedAny then
            if targetMinW > 0 and type(tooltip.SetMinimumWidth) == "function" then
                tooltip._yrgWaylaidWidened = true
                pcall(tooltip.SetMinimumWidth, tooltip, targetMinW)
            end
            pcall(tooltip.Show, tooltip)
            if targetMinW > 0 and #checkFSList > 0 and type(tooltip.SetMinimumWidth) == "function" then
                local maxDeficit = 0
                for _, item in ipairs(checkFSList) do
                    local actualW = (type(item.fs.GetWidth) == "function" and YRG.SafeNumber(item.fs:GetWidth(), 0)) or 0
                    if actualW > 0 and actualW < item.neededW then
                        local diff = math.ceil(item.neededW - actualW + 4)
                        if diff > maxDeficit then
                            maxDeficit = diff
                        end
                    end
                end
                if maxDeficit > 0 then
                    pcall(tooltip.SetMinimumWidth, tooltip, targetMinW + maxDeficit)
                    for _, item in ipairs(checkFSList) do
                        if type(item.fs.SetWidth) == "function" then
                            pcall(item.fs.SetWidth, item.fs, item.neededW)
                        end
                    end
                    pcall(tooltip.Show, tooltip)
                end
            end
        end
        self.decorating = false
    else
        for _, lineFSIdx in ipairs({ 2, 3, 4, 5 }) do
            local fs = _G[tName .. "TextLeft" .. lineFSIdx]
            local txt = fs and type(fs.GetText) == "function" and YRG.SafeString(fs:GetText(), nil)
            if txt and txt:find("%d+%s+[%a]") and not txt:find("|cff40ff40[", 1, true) and not txt:find("|cffffe066[", 1, true) then
                unmatchedBullet = true
                break
            end
        end
    end

    if unmatchedBullet and (self.indexTicker ~= nil or self.loadTicker ~= nil) then
        self.pendingTooltip = tooltip
    elseif self.pendingTooltip == tooltip and not unmatchedBullet then
        self.pendingTooltip = nil
    end

    db._lastWaylaidDiag = {
        title = StripTooltipTags(titleText),
        matched = matchedCount,
        priced = pricedCount,
        cacheCount = self.indexedCount,
        lines = rawLinesDiag,
    }
end

local function IsSupportedWaylaidTooltip(tooltip)
    if not tooltip or (type(tooltip.IsForbidden) == "function" and tooltip:IsForbidden()) then
        return false
    end
    if tooltip == GameTooltip or tooltip == GameTooltipTooltip or tooltip == ItemRefTooltip
        or tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2 then
        return true
    end
    return false
end

local function ResetWaylaidTooltipWidth(tip)
    if tip and tip == waylaid.pendingTooltip then
        waylaid.pendingTooltip = nil
    end
    if tip and tip._yrgWaylaidWidened then
        tip._yrgWaylaidWidened = nil
        if type(tip.SetMinimumWidth) == "function" then
            pcall(tip.SetMinimumWidth, tip, 0)
        end
        return true
    end
    return false
end

local function InstallWaylaidTooltipHooks()
    if waylaid.hookInstalled then return end
    waylaid.hookInstalled = true

    for _, tip in ipairs({ GameTooltip, ItemRefTooltip, GameTooltipTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if tip and type(tip.HasScript) == "function" and type(tip.HookScript) == "function" then
            if tip:HasScript("OnTooltipCleared") then
                tip:HookScript("OnTooltipCleared", ResetWaylaidTooltipWidth)
            end
            if tip:HasScript("OnHide") then
                tip:HookScript("OnHide", ResetWaylaidTooltipWidth)
            end
        end
    end

    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item ~= nil then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if IsSupportedWaylaidTooltip(tooltip) then
                local wasWidened = false
                if not waylaid.decorating then
                    wasWidened = ResetWaylaidTooltipWidth(tooltip)
                end
                waylaid:DecorateTooltip(tooltip)
                if wasWidened and not tooltip._yrgWaylaidWidened and not waylaid.decorating then
                    pcall(tooltip.Show, tooltip)
                end
            end
        end)
    else
        if GameTooltip and type(GameTooltip.HasScript) == "function" and GameTooltip:HasScript("OnTooltipSetItem") then
            GameTooltip:HookScript("OnTooltipSetItem", function(tip)
                if IsSupportedWaylaidTooltip(tip) then
                    local wasWidened = false
                    if not waylaid.decorating then
                        wasWidened = ResetWaylaidTooltipWidth(tip)
                    end
                    waylaid:DecorateTooltip(tip)
                    if wasWidened and not tip._yrgWaylaidWidened and not waylaid.decorating then
                        pcall(tip.Show, tip)
                    end
                end
            end)
        end
        if ItemRefTooltip and type(ItemRefTooltip.HasScript) == "function" and ItemRefTooltip:HasScript("OnTooltipSetItem") then
            ItemRefTooltip:HookScript("OnTooltipSetItem", function(tip)
                if IsSupportedWaylaidTooltip(tip) then
                    local wasWidened = false
                    if not waylaid.decorating then
                        wasWidened = ResetWaylaidTooltipWidth(tip)
                    end
                    waylaid:DecorateTooltip(tip)
                    if wasWidened and not tip._yrgWaylaidWidened and not waylaid.decorating then
                        pcall(tip.Show, tip)
                    end
                end
            end)
        end
    end
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
        SyncBlizzardBagParentSuppression(false)
        customBags:Close()
        HideDividerOverlay()
        ResetControllerBagButtonScales()
        RestoreCombinedBagsFromMerge(ContainerFrameCombinedBags)
        return
    end
    if InstallControllerStripHooks then InstallControllerStripHooks() end
    if ShouldUseCustomReagentCombinedFrame(db) then
        SyncBlizzardBagParentSuppression(true)
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
            HideBlizzardBagsForCustomMode()
            customBags:Open()
            return
        elseif customBags.frame and customBags.frame:IsShown() then
            customBags:ApplyLayout(false)
            return
        end
    else
        SyncBlizzardBagParentSuppression(false)
        local wasCustomOpen = customBags.frame and customBags.frame:IsShown() or false
        customBags:Close()
        if wasCustomOpen and not IsControllerUIActive() and ContainerFrameCombinedBags and not InCombatLockdown() then
            ContainerFrameCombinedBags:Show()
            return
        end
    end
    ApplyUnifiedBagLayout()
end

local function InstallAutomationHooks()
    if autoSortHooked then return end
    autoSortHooked = true

    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", function()
            local db = YRG:GetModuleDB("BetterBagsModule")
            if ShouldUseCustomReagentCombinedFrame(db) then
                HideBlizzardBagsForCustomMode()
                return
            end
            TriggerAutoSortIfEnabled()
        end)
    end
    for i = 1, 13 do
        local cf = _G["ContainerFrame" .. i]
        if cf then
            cf:HookScript("OnShow", function(selfCf)
                local db = YRG:GetModuleDB("BetterBagsModule")
                if ShouldUseCustomReagentCombinedFrame(db) and selfCf and not IsFrameProtectedOrForbidden(selfCf) then
                    local cid = (type(selfCf.GetBagID) == "function" and selfCf:GetBagID())
                        or selfCf.bagID
                        or (type(selfCf.GetID) == "function" and selfCf:GetID())
                    if type(cid) == "number" and cid >= 0 and cid <= GetReagentBagID() then
                        pcall(selfCf.Hide, selfCf)
                        return
                    end
                end
                TriggerAutoSortIfEnabled()
                RefreshNativeBagGreyItems()
            end)
            if not nativeGreyHookedFrames[cf] and type(cf.UpdateItems) == "function" then
                nativeGreyHookedFrames[cf] = true
                hooksecurefunc(cf, "UpdateItems", RefreshNativeBagGreyItems)
            end
        end
    end
    local function MarkSuppressToggle()
        customBags.suppressToggleThisFrame = true
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                customBags.suppressToggleThisFrame = false
            end)
        end
    end

    local function EnsureBlizzardBagsUnsuppressed()
        if customBags.frame and customBags.frame:IsShown() and not InCombatLockdown() then
            customBags:Close()
        end
        if customBags.savedBlizzParent or (ContainerFrameCombinedBags and customBags.hiddenBagParent and ContainerFrameCombinedBags:GetParent() == customBags.hiddenBagParent) then
            SyncBlizzardBagParentSuppression(false)
        end
    end

    local function HandleToggleCustomBags()
        local db = YRG:GetModuleDB("BetterBagsModule")
        if ShouldUseCustomReagentCombinedFrame(db) then
            if customBags.suppressToggleThisFrame or customBags.openedInThisCall then
                customBags.suppressToggleThisFrame = false
                customBags.openedInThisCall = false
            elseif customBags.isOpen then
                customBags:Close()
                MarkSuppressToggle()
            else
                HideBlizzardBagsForCustomMode()
                customBags:Open()
                MarkSuppressToggle()
            end
            return true
        end
        EnsureBlizzardBagsUnsuppressed()
        return false
    end

    if type(ToggleAllBags) == "function" then
        hooksecurefunc("ToggleAllBags", function()
            if HandleToggleCustomBags() then return end
            if (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown())
                or (ContainerFrame1 and ContainerFrame1:IsShown()) then
                TriggerAutoSortIfEnabled()
            end
        end)
    end
    if type(ToggleBackpack) == "function" then
        hooksecurefunc("ToggleBackpack", function()
            HandleToggleCustomBags()
        end)
    end
    if type(OpenAllBags) == "function" then
        hooksecurefunc("OpenAllBags", function()
            local db = YRG:GetModuleDB("BetterBagsModule")
            if ShouldUseCustomReagentCombinedFrame(db) then
                HideBlizzardBagsForCustomMode()
                if not customBags.isOpen then
                    customBags:Open()
                    MarkSuppressToggle()
                end
                return
            end
            EnsureBlizzardBagsUnsuppressed()
            TriggerAutoSortIfEnabled()
        end)
    end
    if type(OpenBackpack) == "function" then
        hooksecurefunc("OpenBackpack", function()
            local db = YRG:GetModuleDB("BetterBagsModule")
            if ShouldUseCustomReagentCombinedFrame(db) then
                HideBlizzardBagsForCustomMode()
                if not customBags.isOpen then
                    customBags:Open()
                    MarkSuppressToggle()
                end
                return
            end
            EnsureBlizzardBagsUnsuppressed()
            TriggerAutoSortIfEnabled()
        end)
    end
    if type(CloseAllBags) == "function" then
        hooksecurefunc("CloseAllBags", function()
            local db = YRG:GetModuleDB("BetterBagsModule")
            if ShouldUseCustomReagentCombinedFrame(db) then
                if customBags.isOpen then
                    customBags:Close()
                    MarkSuppressToggle()
                end
            else
                customBags:Close()
            end
        end)
    end
    if type(CloseBackpack) == "function" then
        hooksecurefunc("CloseBackpack", function()
            local db = YRG:GetModuleDB("BetterBagsModule")
            if ShouldUseCustomReagentCombinedFrame(db) then
                if customBags.isOpen then
                    customBags:Close()
                    MarkSuppressToggle()
                end
            else
                customBags:Close()
            end
        end)
    end
    if type(ToggleBag) == "function" then
        hooksecurefunc("ToggleBag", function(bagID)
            local db = YRG:GetModuleDB("BetterBagsModule")
            if not ShouldUseCustomReagentCombinedFrame(db) then return end
            if type(bagID) == "number" and bagID == GetReagentBagID() then
                HandleToggleCustomBags()
            end
        end)
    end
end

ScheduleUnifiedBagLayout = function()
    if deferredPassPending then return end
    if C_Timer and type(C_Timer.After) == "function" then
        deferredPassPending = true
        C_Timer.After(0, function()
            deferredPassPending = false
            local db = YRG:GetModuleDB("BetterBagsModule")
            if ShouldUseCustomReagentCombinedFrame(db) then
                if customBags.isOpen or (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) then
                    ApplyUnifiedBagLayout()
                end
            elseif ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                ApplyUnifiedBagLayout()
            end
        end)
    end
end

ApplyAndScheduleUnifiedBagLayout = function()
    ApplyUnifiedBagLayout()
    ScheduleUnifiedBagLayout()
end

InstallControllerStripHooks = function()
    if not reagentSearchHooked and BagItemSearchBox and type(BagItemSearchBox.HookScript) == "function" then
        reagentSearchHooked = true
        BagItemSearchBox:HookScript("OnTextChanged", function()
            if customBags.frame and customBags.frame:IsShown() then
                customBags:RefreshSlots()
            end
        end)
    end

    local db = YRG:GetModuleDB("BetterBagsModule")
    if not db or not db.enabled then return end

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
            if bagDragState.dragging and ContainerFrameCombinedBags then
                pcall(ContainerFrameCombinedBags.StopMovingOrSizing, ContainerFrameCombinedBags)
                bagDragState.dragging = false
            end
            HideDividerOverlay()
            if not ShouldUseCustomReagentCombinedFrame(YRG:GetModuleDB("BetterBagsModule")) then
                HideReagentOverlays()
            end
            ResetDualZoneNavState()
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
        if ShouldUseCustomReagentCombinedFrame(db) then
            return "Desktop Mode: YRG Combined Bags Frame (Reagent Merged) + Bag Automation Active."
        end
        local rMsg = (db.includeReagentBagInCombined ~= false) and "Reagent Bag Merge Standby (No Reagent Bag)" or "Native Combined Bags (Reagent Separate)"
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
    if db.navEdgeBehavior ~= "STOP" and db.navEdgeBehavior ~= "WRAP_ROW" and db.navEdgeBehavior ~= "WRAP_FLOW" then
        db.navEdgeBehavior = "STOP"
    end
    if db.emptyCellLocation ~= "BOTTOM_RIGHT" and db.emptyCellLocation ~= "DYNAMIC" then
        db.emptyCellLocation = "TOP_LEFT"
    end
    db._lastReagentDebug = nil
    db._lastReagentOpenDebug = nil
    db._lastDropDebug = nil

    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("PLAYER_LOGIN")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "INPUT_DEVICE_INTERFACE_TRANSITION")
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
    self.eventFrame:RegisterEvent("PLAYER_MONEY")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "CURSOR_CHANGED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "CURRENT_SPELL_CAST_CHANGED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "AUCTION_HOUSE_CLOSED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "GET_ITEM_INFO_RECEIVED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "ADDON_ACTION_BLOCKED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "ADDON_ACTION_FORBIDDEN")
    self.eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        if not autoSortHooked then InstallAutomationHooks() end
        if not controllerStripHooked or not gamepadBagBarHooked then InstallControllerStripHooks() end
        if event == "MERCHANT_SHOW" then
            customBags:SyncHoveredSecureProxy()
            HandleMerchantShow()
        elseif event == "MERCHANT_CLOSED" then
            customBags:SyncHoveredSecureProxy()
            StopSellTicker()
        elseif event == "LOOT_OPENED" then
            isLootingWindowOpen = true
        elseif event == "LOOT_CLOSED" then
            isLootingWindowOpen = false
            ScheduleClamOpen(0.15)
        elseif event == "BAG_OPEN" then
            TriggerAutoSortIfEnabled()
            ScheduleClamOpen(0.20)
        elseif event == "PLAYER_MONEY" then
            if customBags.frame and customBags.frame:IsShown() then
                customBags:UpdateFooter()
            end
        elseif event == "BAG_UPDATE" then
            clamLastAttempt = nil
            if customBags.frame and customBags.frame:IsShown() then
                customBags:ScheduleRefreshSlots()
            end
            RefreshNativeBagGreyItems()
        elseif event == "ITEM_LOCK_CHANGED" or event == "CURSOR_CHANGED" or event == "CURRENT_SPELL_CAST_CHANGED"
            or event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE_COOLDOWN"
            or event == "BAG_NEW_ITEMS_UPDATED" or event == "INVENTORY_SEARCH_UPDATE" then
            if event == "CURSOR_CHANGED" or event == "CURRENT_SPELL_CAST_CHANGED" then
                if type(CursorHasItem) == "function" and CursorHasItem() then
                    customBags:HideSecureProxy()
                elseif C_Timer and type(C_Timer.After) == "function" then
                    if not customBags.proxySyncPending then
                        customBags.proxySyncPending = true
                        C_Timer.After(0, function()
                            customBags.proxySyncPending = false
                            customBags:SyncHoveredSecureProxy()
                        end)
                    end
                else
                    customBags:SyncHoveredSecureProxy()
                end
            elseif event == "ITEM_LOCK_CHANGED" and type(CursorHasItem) == "function" and CursorHasItem() then
                customBags:HideSecureProxy()
            end
            if customBags.frame and customBags.frame:IsShown() then
                customBags:ScheduleRefreshSlots()
            end
            RefreshNativeBagGreyItems()
            if event == "BAG_UPDATE_DELAYED" then
                if not customBags.frame then
                    customBags:PrepareHidden()
                end
                ScheduleClamOpen(0.15)
            end
        elseif event == "BAG_CONTAINER_UPDATE" then
            customBags:PrepareHidden()
            ApplyAndScheduleUnifiedBagLayout()
        elseif event == "PLAYER_REGEN_DISABLED" then
            ClearDualZoneBindings()
        elseif event == "PLAYER_REGEN_ENABLED" then
            SyncBlizzardBagParentSuppression(ShouldUseCustomReagentCombinedFrame(YRG:GetModuleDB("BetterBagsModule")))
            if pending or customBags.pendingLayout then
                pending = false
                customBags.pendingLayout = false
                ApplyAndScheduleUnifiedBagLayout()
            end
            SyncDualZoneBindings()
            ScheduleClamOpen(0.15)
        elseif event == "PLAYER_ENTERING_WORLD" then
            customBags:PrepareHidden()
            ScheduleClamOpen(0.25)
            waylaid:EnsureNameIndex(false)
        elseif event == "PLAYER_LOGIN" or event == "GAME_PAD_ACTIVE_CHANGED" or event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
            customBags:PrepareHidden()
            ApplyAndScheduleUnifiedBagLayout()
            waylaid:EnsureNameIndex(false)
            if (event == "GAME_PAD_ACTIVE_CHANGED" or event == "INPUT_DEVICE_INTERFACE_TRANSITION")
                and C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function()
                    customBags:PrepareHidden()
                    RefreshBlizzardBagLayout()
                    self:UpdateStatusText()
                end)
            end
        elseif event == "AUCTION_HOUSE_CLOSED" then
            waylaid:EnsureNameIndex(true)
        elseif event == "GET_ITEM_INFO_RECEIVED" and arg2 and type(arg1) == "number" then
            local nm = SafeGetItemInfo(arg1)
            if nm then
                waylaid:CacheItemIDName(arg1, nm)
                waylaid:NotifyItemLoaded()
            end
        elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            local addonTag = type(arg1) == "string" and arg1 or tostring(arg1)
            local blockedFn = type(arg2) == "string" and arg2 or tostring(arg2)
            if addonTag:find("YRG", 1, true) then
                pcall(function()
                    local mdb = YRG:GetModuleDB("BetterBagsModule")
                    if not mdb then return end
                    mdb._lastBlockedLog = mdb._lastBlockedLog or {}
                    local sn = _G.SmartNavigation
                    local curBtn = sn and SafeNavCall(sn.GetCurrentButton, sn)
                    mdb._lastBlockedLog[#mdb._lastBlockedLog + 1] = {
                        event = event,
                        addon = addonTag,
                        fn = blockedFn,
                        combat = (InCombatLockdown and InCombatLockdown()) and true or false,
                        bagsShown = (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) and true or false,
                        dzArmed = dualZoneBindingsArmed and true or false,
                        dzStrategy = cachedSnStrategy and (tostring(cachedSnStrategy.kind) .. ":" .. tostring(cachedSnStrategy.method or "")) or "none",
                        curBtn = InspectObjShallow(curBtn),
                        stack = (type(debugstack) == "function") and debugstack(2, 6, 4) or "",
                    }
                    while #mdb._lastBlockedLog > 10 do
                        table.remove(mdb._lastBlockedLog, 1)
                    end
                end)
            end
            if event == "ADDON_ACTION_BLOCKED" and isOpeningClamNow then
                isOpeningClamNow = false
                clamBlockedByClient = true
                if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                    local fnLabel = (type(arg2) == "string" and arg2 ~= "") and (" (" .. arg2 .. ")") or ""
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100YRG:|r Auto-open clams was blocked by the client" .. fnLabel .. " and paused for this session.")
                end
            elseif settingDualZoneBindingsNow then
                settingDualZoneBindingsNow = false
                dualZoneBlockedByClient = true
                ScheduleClearDualZoneBindings()
            end
        end
        self:UpdateStatusText()
    end)
    InstallAutomationHooks()
    InstallControllerStripHooks()
    InstallWaylaidTooltipHooks()
end

function BetterBags:OnEnable(db)
    dualZoneProbeFailed = false
    dualZoneBlockedByClient = false
    cachedSnStrategy = nil
    InstallAutomationHooks()
    InstallControllerStripHooks()
    InstallWaylaidTooltipHooks()
    waylaid:EnsureNameIndex(false)
    customBags:PrepareHidden()
    RefreshBlizzardBagLayout()
    ScheduleClamOpen(0.25)
    self:UpdateStatusText()
end

function BetterBags:OnDisable(db)
    waylaid:StopTicker()
    if clamOpenTimer then
        clamOpenTimer:Cancel()
        clamOpenTimer = nil
    end
    isLootingWindowOpen = false
    isOpeningClamNow = false
    clamLastAttempt = nil
    SyncBlizzardBagParentSuppression(false)
    customBags:Close()
    HideDividerOverlay()
    ResetDualZoneNavState(true)
    ResetControllerBagButtonScales()
    RestoreCombinedBagsFromMerge(ContainerFrameCombinedBags)
    RefreshNativeBagGreyItems(true)
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

    self._statusInitializer = ctx:AddButton({
        name = "Status: " .. self:GetStatusMessage(),
        buttonText = "Check Status",
        tooltip = "Refreshes and prints the current BetterBagsModule Controller / Automation status to chat.",
        onClick = function()
            self:UpdateStatusText()
            print("|cffffd100YRG BetterBagsModule:|r " .. self:GetStatusMessage())
        end,
    })

    ctx:AddHeader(
        "Combined Bags Grid Layout (All Modes)",
        "Controls column sizing and unused slot placement in Combined Bags for both Controller and Non-Controller modes."
    )

    ctx:AddDropdown({
        key = "emptyCellLocation",
        name = "Empty Cell Location",
        tooltip = "Controls where unused bag slots appear in Combined Bags (applies to both Controller and Non-Controller modes, including merged Reagent Bag). Dynamic picks 10, 9, or 8 columns to minimize empty slots while favoring Bottom-Right.",
        defaultValue = "TOP_LEFT",
        options = EMPTY_CELL_OPTIONS,
        get = function()
            return GetEmptyCellMode(GetDB())
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.emptyCellLocation = (val == "BOTTOM_RIGHT" or val == "DYNAMIC") and val or "TOP_LEFT"
            end
            RefreshBlizzardBagLayout()
            self:UpdateStatusText()
        end,
    })

    ctx:AddCheckbox({
        key = "separateAmmoBagRow",
        name = "Separate Quiver / Ammo Pouch Row",
        tooltip = "Starts your equipped Quiver or Ammo Pouch on its own bottom section separated by a horizontal divider line in Combined Bags (works in both Controller and Non-Controller modes).",
        defaultValue = false,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.separateAmmoBagRow == true) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.separateAmmoBagRow = val and true or false end
            RefreshBlizzardBagLayout()
            self:UpdateStatusText()
        end,
    })

    ctx:AddCheckbox({
        key = "dimGreyItems",
        name = "Wash Out Grey (Poor Quality) Items",
        tooltip = "Desaturates grey (Poor quality) item icons to greyscale at 95% opacity with softer contrast so junk items fade back visually in both Desktop and Controller bags.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.dimGreyItems ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.dimGreyItems = val and true or false end
            if customBags.frame and customBags.frame:IsShown() then
                customBags:RefreshSlots()
            end
            RefreshNativeBagGreyItems()
        end,
    })

    -- =========================================================================
    -- SECTION 1: Controller Mode Exclusive — Separate Bag Strip
    -- =========================================================================
    ctx:AddHeader(
        "1. Controller Mode Exclusive: Separate Bag Strip",
        "Controls the detached bag slot strip docked above bags in Controller/Gamepad UI mode."
    )

    local stripDepVars = {
        "YRG_BetterBagsModule_showDivider",
        "YRG_BetterBagsModule_bagPinAlignment",
        "YRG_BetterBagsModule_rowGap",
        "YRG_BetterBagsModule_shrinkBagButtonsToFit",
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

    ctx:AddCheckbox({
        key = "shrinkBagButtonsToFit",
        name = "Scale Bag Buttons to Fit Column Width (Steamdeck Fix)",
        tooltip = "Optional Steamdeck / 1280x800 sizing fix: scales down GamepadBagBar buttons to match your bag grid width and fit cleanly inside each column cell. Leave Off (default) to keep Blizzard's native bag button scale.",
        defaultValue = false,
        canModify = IsControllerStripEnabled,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.shrinkBagButtonsToFit == true) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.shrinkBagButtonsToFit = val and true or false end
            ApplyControllerBagStripLayout()
        end,
    })

    -- =========================================================================
    -- SECTION 2: Non-Controller All-in-One Bags (Frame Movement & Reagent Bag)
    -- =========================================================================
    ctx:AddHeader(
        "2. All-in-One Bags: Frame Movement & Reagent Bag (Non-Controller)",
        "Unlocks Combined Bags movement and merges your separate Reagent Bag window into Blizzard's Combined Bags frame in Keyboard/Mouse mode."
    )

    ctx:AddCheckbox({
        key = "unlockBagFrame",
        name = "Unlock Combined Bags Frame to Move (Non-Controller)",
        tooltip = "Allows dragging Blizzard's Combined Bags window by its title bar or empty border in Keyboard/Mouse mode and saves its screen position across reloads. Controller Mode keeps default anchoring.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.unlockBagFrame ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.unlockBagFrame = val and true or false end
            RefreshBlizzardBagLayout()
            self:UpdateStatusText()
        end,
    })

    ctx:AddButton({
        name = "Reset Combined Bags Position",
        buttonText = "Reset Position",
        tooltip = "Clears your saved Combined Bags screen position and restores Blizzard's default corner anchor in Keyboard/Mouse mode.",
        onClick = function()
            local mdb = GetDB()
            if mdb then mdb.bagFramePos = nil end
            if not IsControllerUIActive() and ContainerFrameCombinedBags then
                RestoreNativeBagPoint(ContainerFrameCombinedBags)
            end
            print("|cffffd100YRG BetterBagsModule:|r Combined Bags position reset to default.")
        end,
    })

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
        key = "waylaidCrateCosts",
        name = "Show Waylaid Crate Auctionator Costs in Tooltip",
        tooltip = "When Auctionator is installed, appends the estimated total Auction House cost in brackets beside each item choice inside Waylaid Crate tooltips.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return (mdb == nil or mdb.waylaidCrateCosts ~= false) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.waylaidCrateCosts = val and true or false
            end
            if val then
                waylaid:EnsureNameIndex(false)
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

local function FmtPt(frame)
    if not frame or type(frame.GetPoint) ~= "function" then return "n/a" end
    local pt, relTo, relPt, x, y = frame:GetPoint(1)
    local rn = (type(relTo) == "table" and relTo.GetName and relTo:GetName()) or (relTo and "anon") or "nil"
    return string.format("%s->%s.%s(%.1f,%.1f)", tostring(pt), tostring(rn), tostring(relPt), tonumber(x) or 0, tonumber(y) or 0)
end

do
    local watchFrame = nil
    local watchDeadline = 0
    local capturedOpenSnapshot = false
    local lastWatchedBtn = nil
    local lastDpadHeld = nil
    local movedDuringHold = false
    local navTrace = {}

    local function SafeCall(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, res = pcall(fn, ...)
        if ok then return res end
        return nil
    end

    local function SafeFrameName(obj)
        if not obj then return "nil" end
        if type(obj) ~= "table" then return tostring(obj) end
        local nm = YRG.SafeString(SafeCall(obj.GetName, obj), nil)
        if nm then return nm end
        local dn = YRG.SafeString(SafeCall(obj.GetDebugName, obj), nil)
        if dn then return dn end
        return tostring(obj)
    end

    local function DescribeBtn(btn)
        if not btn or type(btn) ~= "table" then return tostring(btn) end
        local nm = SafeFrameName(btn)
        local bagID = SafeCall(btn.GetBagID, btn)
        local slotID = SafeCall(btn.GetID, btn)
        local okC, cx, cy = pcall(function() return btn.GetCenter and btn:GetCenter() end)
        local okR, rl, rb, rw, rh = pcall(function() return btn.GetRect and btn:GetRect() end)
        local s = SafeCall(btn.GetScale, btn)
        local eff = SafeCall(btn.GetEffectiveScale, btn)
        local parentNm = SafeFrameName(SafeCall(btn.GetParent, btn))
        local rectStr = (okR and rl) and string.format("%.0f..%.0f,%.0f..%.0f", rl, rl + (rw or 0), rb, rb + (rh or 0)) or "n/a"
        return string.format("%s(p=%s,bag=%s,id=%s,s=%.2f,eff=%.2f,ctr=%.1f,%.1f,rect=%s)",
            nm, parentNm, tostring(bagID), tostring(slotID),
            YRG.SafeNumber(s, 1), YRG.SafeNumber(eff, -1),
            YRG.SafeNumber(okC and cx, -1), YRG.SafeNumber(okC and cy, -1), rectStr)
    end

    local function SummarizeValue(v, depth)
        if YRG.IsSecret and YRG.IsSecret(v) then
            return "<secret>"
        end
        local tv = type(v)
        if tv ~= "table" then
            if tv == "function" then return "fn" end
            local okS, s = pcall(tostring, v)
            return okS and s or "<userdata>"
        end
        local okObj, objFn = pcall(function() return v.GetObjectType end)
        if okObj and type(objFn) == "function" then
            return "<" .. SafeFrameName(v) .. ">"
        end
        local parts = {}
        local n = 0
        local okLoop, loopErr = pcall(function()
            for k, sub in pairs(v) do
                n = n + 1
                if n <= 10 then
                    local subStr
                    if depth and depth > 1 and type(sub) == "table" then
                        local okSubObj, subObjFn = pcall(function() return sub.GetObjectType end)
                        if not (okSubObj and type(subObjFn) == "function") then
                            local subCount = 0
                            for _ in pairs(sub) do subCount = subCount + 1 end
                            subStr = "{#" .. subCount .. "}"
                        else
                            subStr = SummarizeValue(sub, 1)
                        end
                    else
                        subStr = SummarizeValue(sub, 1)
                    end
                    local okK, ks = pcall(tostring, k)
                    parts[#parts + 1] = (okK and ks or "?") .. "=" .. tostring(subStr)
                end
            end
        end)
        if not okLoop then
            return "<err:" .. tostring(loopErr) .. ">"
        end
        if n > 10 then
            parts[#parts + 1] = "...(+" .. (n - 10) .. ")"
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end

    local function CollectMatchingFieldValues(tbl, pattern, out)
        if type(tbl) ~= "table" then return end
        pcall(function()
            for k, v in pairs(tbl) do
                if type(k) == "string" and (pattern == "" or k:lower():find(pattern)) and type(v) ~= "function" and k ~= "0" then
                    out[#out + 1] = k .. "=" .. SummarizeValue(v, 2)
                end
            end
        end)
    end

    local function CaptureBagDebug(saveKey, quiet, verbose)
        local f, b = ContainerFrameCombinedBags, GamepadBagBar
        local db = YRG:GetModuleDB("BetterBagsModule")
        local lines = {}
        local function Emit(s, saveOnly)
            lines[#lines + 1] = s
            if db then
                db[saveKey or "_lastDebug"] = lines
            end
            if not quiet and (verbose or not saveOnly) then
                print("|cffffd100[BagDbg]|r " .. s)
            end
        end

        local okDbg, dbgErr = xpcall(function()

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
        local bSelfScale = b and b.GetScale and b:GetScale() or 1
        local bStrata = (b and b.GetFrameStrata and b:GetFrameStrata()) or "?"
        local bLvl = (b and b.GetFrameLevel and b:GetFrameLevel()) or -1
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or -1
        local physW, physH = 0, 0
        if type(GetPhysicalScreenSize) == "function" then
            physW, physH = GetPhysicalScreenSize()
        end
        local combCVar = GetCVar and GetCVar("combinedBags")
        Emit(string.format("F:sh=%s strip=%s gp=%s pin=%s gap=%s cols=%d rows=%d calcH=%.0f curH=%.0f fSc=%.2f(s=%.2f) fZ=%s:%d Bar:sh=%s m=%s sc=%.2f(s=%.2f) bZ=%s:%d pt=%s",
            tostring(f:IsShown()), tostring(db and db.controllerBagStrip), tostring(IsControllerUIActive()),
            tostring(db and db.bagPinAlignment), tostring(db and db.rowGap),
            cols, rows, calcH, curH, fScale, fSelfScale, tostring(fStrata), fLvl,
            tostring(bShown), tostring(bMouse), bScale, bSelfScale, tostring(bStrata), bLvl, FmtPt(b)))
        Emit(string.format("Env: phys=%dx%d uiSc=%.2f combinedBags=%s fRect=%s",
            tonumber(physW) or 0, tonumber(physH) or 0, uiScale, tostring(combCVar),
            (f.GetRect and f:GetRect()) and string.format("%.0f,%.0f,%.0f,%.0f", f:GetRect()) or "n/a"))

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
        Emit("KeysF=[" .. table.concat(fKeys, ",") .. "]", true)
        Emit("KeysB=[" .. table.concat(bKeys, ",") .. "]", true)

        local fVals, bVals = {}, {}
        CollectMatchingFieldValues(f, "nav", fVals)
        CollectMatchingFieldValues(f, "focus", fVals)
        CollectMatchingFieldValues(f, "pad", fVals)
        CollectMatchingFieldValues(b, "nav", bVals)
        CollectMatchingFieldValues(b, "focus", bVals)
        CollectMatchingFieldValues(b, "pad", bVals)
        CollectMatchingFieldValues(b, "bagbutton", bVals)
        if #fVals > 0 then Emit("ValsF: " .. table.concat(fVals, " | "), true) end
        if #bVals > 0 then Emit("ValsB: " .. table.concat(bVals, " | "), true) end

        local scNames = { "OnGamePadButtonDown", "OnKeyDown", "OnUpdate" }
        local fSc, bSc = {}, {}
        for _, sn in ipairs(scNames) do
            if f.GetScript and f:GetScript(sn) then fSc[#fSc + 1] = sn end
            if b and b.GetScript and b:GetScript(sn) then bSc[#bSc + 1] = sn end
        end
        Emit("ScriptsF=[" .. table.concat(fSc, ",") .. "] ScriptsB=[" .. table.concat(bSc, ",") .. "]", true)

        -- SmartNavigation global inspection
        local sn = _G.SmartNavigation
        if sn then
            local snShown = SafeCall(sn.IsShown, sn)
            local snActive = SafeCall(sn.GetActiveFrame, sn)
            local snCur = SafeCall(sn.GetCurrentButton, sn)
            local snKeys, snSeen, snVals = {}, {}, {}
            local mtS = getmetatable(sn)
            CollectKeysMatching(sn, "", snKeys, snSeen)
            if type(mtS) == "table" and type(mtS.__index) == "table" then
                CollectKeysMatching(mtS.__index, "", snKeys, snSeen)
            end
            CollectMatchingFieldValues(sn, "", snVals)
            Emit(string.format("SmartNav: sh=%s active=%s cur=%s",
                tostring(snShown), SafeFrameName(snActive), DescribeBtn(snCur)), true)
            local curDz = snCur and dualZoneData.btnMap[snCur]
            Emit(string.format("DualZone: armed=%s probeFailed=%s blocked=%s cols=%d iRows=%d bRows=%d curDz=%s",
                tostring(dualZoneBindingsArmed), tostring(dualZoneProbeFailed), tostring(dualZoneBlockedByClient),
                dualZoneData.columns or 0, dualZoneData.itemRows or 0, dualZoneData.bagRows or 0,
                curDz and (tostring(curDz.zone) .. " r=" .. tostring(curDz.row)) or "nil"), true)
            Emit("SmartNavKeys=[" .. table.concat(snKeys, ",") .. "]", true)
            if #snVals > 0 then
                Emit("SmartNavVals: " .. table.concat(snVals, " | "), true)
            end
        else
            Emit("SmartNav=nil", true)
        end

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
                local nm = SafeFrameName(child)
                local me = (child.IsMouseEnabled and child:IsMouseEnabled()) and "M" or "-"
                local cx, cy = child:GetCenter()
                extraKids[#extraKids + 1] = string.format("%s(%s:%.0f,%.0f)", nm, me, tonumber(cx) or -1, tonumber(cy) or -1)
            end
        end
        if b then
            for _, child in ipairs({ b:GetChildren() }) do
                if type(child.IsShown) == "function" and child:IsShown() then
                    local nm = SafeFrameName(child)
                    local me = (child.IsMouseEnabled and child:IsMouseEnabled()) and "M" or "-"
                    local cx, cy = child:GetCenter()
                    extraKids[#extraKids + 1] = string.format("B:%s(%s:%.0f,%.0f)", nm, me, tonumber(cx) or -1, tonumber(cy) or -1)
                end
            end
        end
        Emit("Items=" .. #itemList .. " NonItems(" .. #extraKids .. "): " .. table.concat(extraKids, "; "), true)

        -- Print key item samples across cols 1, 4, 5, 10 (bottom row & top rows)
        local cCount = (cols > 0) and cols or 10
        local sampleIdx = {
            1,
            math.max(1, cCount - 4), -- col 5 if 10 cols
            math.max(1, cCount - 3), -- col 4 if 10 cols
            math.min(cCount, #itemList), -- col 1
            math.min(cCount + 1, #itemList),
            math.max(1, #itemList - cCount + 1),
            #itemList,
        }
        local seenIdx = {}
        for _, idx in ipairs(sampleIdx) do
            local btn = itemList[idx]
            if btn and not seenIdx[idx] then
                seenIdx[idx] = true
                Emit(string.format("I[%d] %s pt=%s", idx, DescribeBtn(btn), FmtPt(btn)))
            end
        end
        if itemList[1] then
            local iVals = {}
            CollectMatchingFieldValues(itemList[1], "", iVals)
            if #iVals > 0 then Emit("ItemBtnFields: " .. table.concat(iVals, " | "), true) end
        end

        local rBagID = GetReagentBagID()
        local openCFs = {}
        for i = 1, 13 do
            local cf = _G["ContainerFrame" .. i]
            if cf and (cf:IsShown() or ((cf.GetID and cf:GetID()) == rBagID) or cf.bagID == rBagID) then
                local cid = (cf.GetID and cf:GetID()) or cf.bagID
                openCFs[#openCFs + 1] = string.format("CF%d(id=%s,sh=%s,sz=%s,lvl=%s)", i, tostring(cid), tostring(cf:IsShown()), tostring(cf.size), tostring(cf:GetFrameLevel()))
            end
        end
        Emit("OpenCFs=[" .. table.concat(openCFs, "; ") .. "]")
        Emit(string.format("CustomBag: sh=%s frame=%s fProt=%s b1Prot=%s size=%.0fx%.0f slot1=%s sh1=%s proxySh=%s ammoDiv=%s reagDiv=%s",
            tostring(customBags.frame and customBags.frame:IsShown()),
            tostring(customBags.frame ~= nil),
            tostring(customBags.frame and customBags.frame.IsProtected and customBags.frame:IsProtected() or false),
            tostring(customBags.buttons[1] and customBags.buttons[1].IsProtected and customBags.buttons[1]:IsProtected() or false),
            YRG.SafeNumber(customBags.frame and customBags.frame:GetWidth(), 0),
            YRG.SafeNumber(customBags.frame and customBags.frame:GetHeight(), 0),
            FmtPt(customBags.buttons[1]),
            tostring(customBags.buttons[1] and customBags.buttons[1]:IsShown()),
            tostring(customBags.secureProxy and customBags.secureProxy:IsShown()),
            tostring(sectionDividers.customAmmo and sectionDividers.customAmmo.frame and sectionDividers.customAmmo.frame:IsShown()),
            tostring(sectionDividers.customReag and sectionDividers.customReag.frame and sectionDividers.customReag.frame:IsShown())))
        if db and db._lastMergeDiag then
            local md = db._lastMergeDiag
            Emit(string.format("MergeDiag: reason=%s char=%s eff=%s std=%s ammo=%s reag=%s guardOk=%s err=%s",
                tostring(md.reason), tostring(md.char), tostring(md.effCols),
                tostring(md.stdCount), tostring(md.ammoCount), tostring(md.numReagentSlots),
                tostring(md.guardOk), tostring(md.guardErr or md.reagentErr or md.ammoErr or md.ptInfo or "")))
        end
        if db and type(db._lastMergeHistory) == "table" and #db._lastMergeHistory > 0 then
            local startIdx = math.max(1, #db._lastMergeHistory - 4)
            Emit("MergeHist: " .. table.concat(db._lastMergeHistory, " || ", startIdx, #db._lastMergeHistory))
        end

        if b and type(b.GetBagButton) == "function" then
            local maxBagID = math.max((ENDING_BAG_INDEX or 4), rBagID or 5)
            local dumpedBagFields = false
            for id = (KEYRING_CONTAINER or -2), maxBagID do
                local btn = b:GetBagButton(id)
                if btn then
                    Emit(string.format("Bag[%d] sh=%s col=%s m=%s pt=%s %s",
                        id, tostring(btn:IsShown()), tostring(btn.isCollapsed),
                        tostring(btn.IsMouseEnabled and btn:IsMouseEnabled()),
                        FmtPt(btn), DescribeBtn(btn)), true)
                    if not dumpedBagFields and btn:IsShown() then
                        dumpedBagFields = true
                        local bgVals = {}
                        CollectMatchingFieldValues(btn, "", bgVals)
                        if #bgVals > 0 then Emit("BagBtnFields[" .. id .. "]: " .. table.concat(bgVals, " | "), true) end
                    end
                end
            end
        end

        local cAuto = GetCVar and GetCVar("GamePadCursorAutoEnable")
        local cCtr = GetCVar and GetCVar("GamePadCursorCentering")
        local cTgt = GetCVar and GetCVar("GamePadCursorForTargeting")
        local cStk = GetCVar and GetCVar("GamePadCursorAutoDisableSticks")
        Emit(string.format("CVars: AutoEnable=%s Centering=%s Targeting=%s Sticks=%s SoftCursor=%s",
            tostring(cAuto), tostring(cCtr), tostring(cTgt), tostring(cStk),
            tostring(SoftCursor and SoftCursor.IsShown and SoftCursor:IsShown())), true)
        end, function(e) return tostring(e) end)

        if not okDbg then
            Emit("CaptureBagDebugErr: " .. tostring(dbgErr))
        end

        if db then
            db[saveKey or "_lastDebug"] = lines
        end
    end

    local function StopWatch(reason)
        if watchFrame then
            watchFrame:SetScript("OnUpdate", nil)
        end
        local db = YRG:GetModuleDB("BetterBagsModule")
        if db then
            db._lastNavTrace = navTrace
        end
        print("|cffffd100YRG BetterBagsModule:|r Debug watch ended (" .. tostring(reason) .. ", transitions=" .. tostring(#navTrace) .. "). /reload or log out to flush SavedVariables.")
    end

    SLASH_YRGBAGDEBUG1 = "/yrgbagdebug"
    SlashCmdList.YRGBAGDEBUG = function(msg)
        local cmd = (type(msg) == "string") and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if cmd == "stop" then
            StopWatch("manual")
            return
        elseif cmd == "reset" then
            dualZoneProbeFailed = false
            dualZoneBlockedByClient = false
            cachedSnStrategy = nil
            ApplyUnifiedBagLayout()
            print("|cffffd100YRG BetterBagsModule:|r Dual-Zone state reset and re-applied.")
            return
        elseif cmd == "watch" then
            if not watchFrame then
                watchFrame = CreateFrame("Frame")
            end
            navTrace = {}
            capturedOpenSnapshot = false
            lastWatchedBtn = nil
            lastDpadHeld = nil
            movedDuringHold = false
            watchDeadline = (GetTime and GetTime() or 0) + 60
            watchFrame:SetScript("OnUpdate", function()
                local now = GetTime and GetTime() or 0
                if now >= watchDeadline or #navTrace >= 25 then
                    StopWatch(#navTrace >= 25 and "25 transitions" or "60s timeout")
                    return
                end
                if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() and IsControllerUIActive() then
                    if not capturedOpenSnapshot then
                        capturedOpenSnapshot = true
                        if C_Timer and type(C_Timer.After) == "function" then
                            C_Timer.After(0.25, function()
                                CaptureBagDebug("_lastControllerDebug", true)
                            end)
                        else
                            CaptureBagDebug("_lastControllerDebug", true)
                        end
                    end
                    local heldKey = nil
                    if type(IsKeyDown) == "function" then
                        for _, k in ipairs({ "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }) do
                            local ok, down = pcall(IsKeyDown, k)
                            if ok and down then
                                heldKey = k
                                break
                            end
                        end
                    end
                    if heldKey and heldKey ~= lastDpadHeld then
                        lastDpadHeld = heldKey
                        movedDuringHold = false
                    elseif not heldKey and lastDpadHeld then
                        if not movedDuringHold then
                            navTrace[#navTrace + 1] = string.format("[%.2f] key=%s -> NO_CHANGE (cur=%s)",
                                now, tostring(lastDpadHeld), lastWatchedBtn and SafeFrameName(lastWatchedBtn) or "nil")
                        end
                        lastDpadHeld = nil
                        movedDuringHold = false
                    end
                    local sn = _G.SmartNavigation
                    local cur = sn and SafeCall(sn.GetCurrentButton, sn)
                    if cur and cur ~= lastWatchedBtn then
                        navTrace[#navTrace + 1] = string.format("[%.2f] key=%s -> %s (prev=%s)",
                            now, tostring(lastDpadHeld or "?"), DescribeBtn(cur),
                            lastWatchedBtn and SafeFrameName(lastWatchedBtn) or "nil")
                        lastWatchedBtn = cur
                        movedDuringHold = true
                    end
                end
            end)
            print("|cffffd100YRG BetterBagsModule:|r Controller bag watch armed for 60s. Open bags in Controller Mode and navigate across Cols 4..10; type '/yrgbagdebug stop' when done.")
            return
        end
        CaptureBagDebug("_lastDebug", false, cmd == "full")
    end
end

YRG:RegisterModule("BetterBagsModule", BetterBags)
