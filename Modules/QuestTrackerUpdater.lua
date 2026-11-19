local _, YRG = ...

local SORT_OPTIONS = {
    { label = "None (Default Track Order)", value = "NONE" },
    { label = "By-Level (1 -> 60)",         value = "LEVEL_ASC" },
    { label = "By-Level (60 -> 1)",         value = "LEVEL_DESC" },
}

local VALID_SORT_MODES = {
    NONE = true,
    LEVEL_ASC = true,
    LEVEL_DESC = true,
}

local SORT_LABEL_BY_MODE = {
    NONE = "None (Default Track Order)",
    LEVEL_ASC = "By-Level (1 -> 60)",
    LEVEL_DESC = "By-Level (60 -> 1)",
}

local QuestTracker = {
    name = "QuestTrackerUpdater",
    description = "Controls quest sorting order, automatic tracking of newly accepted quests, and optional Auto Accept Quests.",
    defaultEnabled = true,
    defaults = {
        enabled = true,
        sortOrder = "LEVEL_ASC", -- "NONE", "LEVEL_ASC", "LEVEL_DESC"
        autoTrackQuests = true,
        autoAcceptQuests = false,
    }
}

local applyingOverride = false
local suppressNativeHooks = false
local overrideTimerPending = false
local pendingCombatUpdate = false
local questieSortHooked = false
local hookedBlizzardObjects = {}

local KNOWN_QUEST_TRACKER_NAMES = {
    "CampaignQuestObjectiveTracker",
    "QuestObjectiveTracker",
    "BonusObjectiveTracker",
    "WorldQuestObjectiveTracker",
}

-- =========================================================================
-- HELPERS: Sort Normalization, Level Lookup & Shared Comparator
-- =========================================================================
local function GetNormalizedSortMode(db)
    local mode = db and db.sortOrder
    if mode and VALID_SORT_MODES[mode] then
        return mode
    end
    return "LEVEL_ASC"
end

local function GetQuestLevelAndTitle(questID, fallbackTitleText)
    local level, title = nil, nil
    if type(questID) == "number" and questID > 0 then
        if C_QuestLog and type(C_QuestLog.GetLogIndexForQuestID) == "function" and type(C_QuestLog.GetInfo) == "function" then
            local okIdx, logIdx = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
            if okIdx and logIdx and logIdx > 0 then
                local okInfo, info = pcall(C_QuestLog.GetInfo, logIdx)
                if okInfo and type(info) == "table" then
                    level = info.level and YRG.SafeOptionalNumber(info.level) or nil
                    title = info.title and YRG.SafeString(info.title, nil) or nil
                end
            end
        end
        if not level and type(GetQuestLogIndexByID) == "function" and type(GetQuestLogTitle) == "function" then
            local okIdx, logIdx = pcall(GetQuestLogIndexByID, questID)
            if okIdx and logIdx and logIdx > 0 then
                local okTitle, qTitle, qLevel = pcall(GetQuestLogTitle, logIdx)
                if okTitle then
                    level = qLevel and YRG.SafeOptionalNumber(qLevel) or nil
                    title = title or (qTitle and YRG.SafeString(qTitle, nil) or nil)
                end
            end
        end
        if not level and QuestieLoader and type(QuestieLoader.ImportModule) == "function" then
            local okDB, qDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
            if okDB and qDB and type(qDB.GetQuest) == "function" then
                local okQ, q = pcall(qDB.GetQuest, questID)
                if okQ and type(q) == "table" then
                    level = q.level and YRG.SafeOptionalNumber(q.level) or nil
                    title = title or (q.name and YRG.SafeString(q.name, nil) or nil)
                end
            end
        end
    end

    if not level and type(fallbackTitleText) == "string" and fallbackTitleText ~= "" then
        local lvlStr = fallbackTitleText:match("^%s*%[?(%d+)%]?")
        if lvlStr then
            level = tonumber(lvlStr)
        end
        title = title or fallbackTitleText
    end

    return level, title or (type(fallbackTitleText) == "string" and fallbackTitleText or "")
end

local function CompareQuestEntries(lvlA, titleA, tieA, lvlB, titleB, tieB, isDesc)
    if lvlA and lvlB then
        if lvlA ~= lvlB then
            if isDesc then
                return lvlA > lvlB
            end
            return lvlA < lvlB
        end
    elseif lvlA and not lvlB then
        return true
    elseif not lvlA and lvlB then
        return false
    end

    local tA = titleA or ""
    local tB = titleB or ""
    if tA ~= tB then
        return tA < tB
    end
    return (tieA or 0) < (tieB or 0)
end

-- =========================================================================
-- 1. QUESTIE DETECTION & NATIVE SORT HOOK
-- =========================================================================
local function IsQuestieTrackerEnabled()
    if Questie and Questie.db and Questie.db.profile then
        return Questie.db.profile.trackerEnabled and true or false
    end
    local base = _G["Questie_BaseFrame"]
    return (base and base:IsShown()) and true or false
end

local function IsQuestieTrackerActive()
    if IsQuestieTrackerEnabled() then
        return true
    end
    local base = _G["Questie_BaseFrame"]
    return (base and base:IsShown()) and true or false
end

local function InstallQuestieHooks()
    if questieSortHooked or not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then
        return
    end

    local okU, tUtils = pcall(QuestieLoader.ImportModule, QuestieLoader, "TrackerUtils")
    if not okU or type(tUtils) ~= "table" or type(tUtils.GetSortedQuestIds) ~= "function" then
        return
    end

    if not tUtils._yrgSortedHooked then
        tUtils._yrgSortedHooked = true
        local origGetSortedQuestIds = tUtils.GetSortedQuestIds
        tUtils.GetSortedQuestIds = function(self, ...)
            local sortedQuestIds, questDetails = origGetSortedQuestIds(self, ...)
            local modDB = YRG:GetModuleDB("QuestTrackerUpdater")
            local mode = GetNormalizedSortMode(modDB)
            if modDB and modDB.enabled and mode ~= "NONE" and type(sortedQuestIds) == "table" and #sortedQuestIds > 1 then
                local isDesc = (mode == "LEVEL_DESC")
                table.sort(sortedQuestIds, function(idA, idB)
                    local dA = questDetails and questDetails[idA]
                    local dB = questDetails and questDetails[idB]
                    local qA = dA and dA.quest
                    local qB = dB and dB.quest

                    local lA = (qA and qA.level and YRG.SafeOptionalNumber(qA.level)) or nil
                    local tA = (qA and qA.name and YRG.SafeString(qA.name, nil)) or nil
                    if not lA then
                        local fL, fT = GetQuestLevelAndTitle(idA, tA)
                        lA = fL
                        tA = tA or fT
                    end

                    local lB = (qB and qB.level and YRG.SafeOptionalNumber(qB.level)) or nil
                    local tB = (qB and qB.name and YRG.SafeString(qB.name, nil)) or nil
                    if not lB then
                        local fL, fT = GetQuestLevelAndTitle(idB, tB)
                        lB = fL
                        tB = tB or fT
                    end

                    return CompareQuestEntries(lA, tA, tonumber(idA) or 0, lB, tB, tonumber(idB) or 0, isDesc)
                end)
            end
            return sortedQuestIds, questDetails
        end
    end

    questieSortHooked = true
end

-- =========================================================================
-- 2. BLIZZARD BUILT-IN TRACKER SORTING (No Orientation / Grow Changes)
-- =========================================================================
local function GetQuestTrackerModules(tracker)
    local modules = {}
    local seen = {}

    local function AddIfQuestModule(mod)
        if type(mod) ~= "table" or seen[mod] then return end
        local isQuestMod = false
        for _, name in ipairs(KNOWN_QUEST_TRACKER_NAMES) do
            if mod == _G[name] then
                isQuestMod = true
                break
            end
        end
        if not isQuestMod then
            local mName = (mod.GetName and mod:GetName()) or ""
            if type(mName) == "string" and mName:find("Quest") and not mName:find("Scenario") then
                isQuestMod = true
            end
        end
        if isQuestMod and type(mod.IsShown) == "function" then
            seen[mod] = true
            table.insert(modules, mod)
        end
    end

    if tracker and type(tracker.modules) == "table" then
        for _, mod in ipairs(tracker.modules) do
            AddIfQuestModule(mod)
        end
    end
    for _, name in ipairs(KNOWN_QUEST_TRACKER_NAMES) do
        AddIfQuestModule(_G[name])
    end
    return modules
end

local function SortClassicQuestWatchFrame(isDesc)
    if not QuestWatchFrame or not QuestWatchFrame:IsShown() then return end

    local lines = {}
    for i = 1, (MAX_QUESTWATCH_LINES or 30) do
        local line = _G["QuestWatchLine" .. i]
        if line and line:IsShown() and line:GetText() and line:GetText() ~= "" then
            table.insert(lines, line)
        end
    end
    if #lines <= 1 then return end

    local frameLeft = YRG.SafeOptionalNumber(QuestWatchFrame:GetLeft())
    local frameTop = YRG.SafeOptionalNumber(QuestWatchFrame:GetTop())
    local line1Left = YRG.SafeOptionalNumber(lines[1]:GetLeft())
    local line1Top = YRG.SafeOptionalNumber(lines[1]:GetTop())
    if not (frameLeft and frameTop and line1Left and line1Top) then return end

    local lineIndents = {}
    for _, ln in ipairs(lines) do
        local lx = YRG.SafeOptionalNumber(ln:GetLeft())
        lineIndents[ln] = lx and (lx - frameLeft) or 0
    end

    local blocks = {}
    local curBlock = nil
    for _, ln in ipairs(lines) do
        local txt = YRG.SafeString(ln:GetText(), "") or ""
        local isObj = txt:match("^%s*%-") or txt:match("^%s+")
        if not isObj or not curBlock then
            local lvl, title = GetQuestLevelAndTitle(nil, txt)
            curBlock = {
                lines = { ln },
                level = lvl,
                title = title,
                natural = #blocks + 1,
            }
            table.insert(blocks, curBlock)
        else
            table.insert(curBlock.lines, ln)
        end
    end

    if #blocks <= 1 then return end

    local sortedBlocks = {}
    for i, blk in ipairs(blocks) do
        sortedBlocks[i] = blk
    end
    table.sort(sortedBlocks, function(a, b)
        return CompareQuestEntries(a.level, a.title, a.natural, b.level, b.title, b.natural, isDesc)
    end)

    local alreadyOrdered = true
    for i = 1, #blocks do
        if sortedBlocks[i] ~= blocks[i] then
            alreadyOrdered = false
            break
        end
    end
    if alreadyOrdered then return end

    local firstX = lineIndents[lines[1]] or 0
    local firstY = line1Top - frameTop
    local prev = nil
    local prevX = firstX
    for _, blk in ipairs(sortedBlocks) do
        for _, ln in ipairs(blk.lines) do
            if not (type(ln.IsProtected) == "function" and ln:IsProtected()) then
                local lx = lineIndents[ln] or 0
                ln:ClearAllPoints()
                if not prev then
                    ln:SetPoint("TOPLEFT", QuestWatchFrame, "TOPLEFT", lx, firstY)
                else
                    ln:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", lx - prevX, -2)
                end
                prev = ln
                prevX = lx
            end
        end
    end
end

local function SortObjectiveModuleBlocks(mod, isDesc)
    if not mod or not mod:IsShown() then return end
    local contents = mod.ContentsFrame or mod
    if not contents or not contents:IsShown() then return end

    local collected = {}
    local seen = {}

    local function ConsiderBlock(blk)
        if type(blk) ~= "table" or seen[blk] then return end
        if blk == mod.Header or blk == contents then return end
        if type(blk.IsShown) == "function" and not blk:IsShown() then return end
        local qid = (type(blk.questID) == "number" and blk.questID)
            or (type(blk.id) == "number" and blk.id)
            or nil
        if not qid and not (blk.HeaderText or blk.usedLines or blk.lines) then return end
        local h = YRG.SafeNumber(blk.GetHeight and blk:GetHeight() or 0, 0)
        if h <= 1 then return end
        seen[blk] = true
        table.insert(collected, blk)
    end

    if type(mod.usedBlocks) == "table" then
        for _, v in pairs(mod.usedBlocks) do
            if type(v) == "table" then
                if v.HeaderText or v.usedLines or v.lines or v.id ~= nil or type(v.IsShown) == "function" then
                    ConsiderBlock(v)
                else
                    for _, blk in pairs(v) do
                        ConsiderBlock(blk)
                    end
                end
            end
        end
    end

    if type(contents.GetChildren) == "function" then
        local children = { contents:GetChildren() }
        for _, ch in ipairs(children) do
            ConsiderBlock(ch)
        end
    end

    if #collected <= 1 then return end

    local contentsLeft = YRG.SafeOptionalNumber(contents:GetLeft())
    local contentsRight = YRG.SafeOptionalNumber(contents:GetRight())
    local contentsTop = YRG.SafeOptionalNumber(contents:GetTop())
    if not (contentsLeft and contentsTop) then return end

    local nativeTopOrder = {}
    for idx, blk in ipairs(collected) do
        local top = YRG.SafeOptionalNumber(blk:GetTop())
        local left = YRG.SafeOptionalNumber(blk:GetLeft())
        if not (top and left) then return end
        local bottom = YRG.SafeOptionalNumber(blk:GetBottom()) or top
        local right = YRG.SafeOptionalNumber(blk:GetRight())
        local h = math.max(YRG.SafeNumber(blk.GetHeight and blk:GetHeight() or 0, 0), top - bottom)
        if h <= 1 then return end
        table.insert(nativeTopOrder, {
            blk = blk,
            top = top,
            left = left,
            right = right,
            bottom = bottom,
            height = h,
            idx = idx,
        })
    end

    table.sort(nativeTopOrder, function(a, b)
        if math.abs(a.top - b.top) > 0.5 then
            return a.top > b.top
        end
        return a.idx < b.idx
    end)

    local ordered = {}
    for i, entry in ipairs(nativeTopOrder) do
        local blk = entry.blk
        local qid = (type(blk.questID) == "number" and blk.questID)
            or (type(blk.id) == "number" and blk.id)
            or nil
        local rawTitle = ""
        if blk.HeaderText and type(blk.HeaderText.GetText) == "function" then
            rawTitle = YRG.SafeString(blk.HeaderText:GetText(), "") or ""
        end
        local level, title = GetQuestLevelAndTitle(qid, rawTitle)
        ordered[i] = {
            blk = blk,
            level = level,
            title = title,
            tie = qid or i,
            xOffset = entry.left - contentsLeft,
            rightOffset = (contentsRight and entry.right) and (entry.right - contentsRight) or nil,
            height = entry.height,
        }
    end

    table.sort(ordered, function(a, b)
        return CompareQuestEntries(a.level, a.title, a.tie, b.level, b.title, b.tie, isDesc)
    end)

    local alreadyOrdered = true
    for i = 1, #ordered do
        if ordered[i].blk ~= nativeTopOrder[i].blk then
            alreadyOrdered = false
            break
        end
    end
    if alreadyOrdered then return end

    if InCombatLockdown() then
        pendingCombatUpdate = true
        return
    end

    local gap = YRG.SafeOptionalNumber(mod.blockPadding)
    if not gap and #nativeTopOrder >= 2 then
        local measured = nativeTopOrder[1].bottom - nativeTopOrder[2].top
        if measured >= 2 and measured <= 16 then
            gap = measured
        end
    end
    gap = gap or 6

    -- Anchor every block directly to `contents` (never chained block-to-block), avoiding
    -- circular anchor dependencies when Blizzard updates blocks natively.
    local curY = nativeTopOrder[1].top - contentsTop
    for _, item in ipairs(ordered) do
        local blk = item.blk
        local isProt = type(blk.IsProtected) == "function" and blk:IsProtected()
        if not isProt then
            local hasRightPoint = false
            if type(blk.GetNumPoints) == "function" and type(blk.GetPoint) == "function" then
                for p = 1, blk:GetNumPoints() do
                    local okPt, pt = pcall(blk.GetPoint, blk, p)
                    if okPt and (pt == "TOPRIGHT" or pt == "RIGHT" or pt == "BOTTOMRIGHT") then
                        hasRightPoint = true
                        break
                    end
                end
            end

            blk:ClearAllPoints()
            blk:SetPoint("TOPLEFT", contents, "TOPLEFT", item.xOffset, curY)
            if hasRightPoint and item.rightOffset then
                blk:SetPoint("TOPRIGHT", contents, "TOPRIGHT", item.rightOffset, curY)
            end
        end
        curY = curY - item.height - gap
    end
end

local function ApplyBlizzardSortOverride(db)
    local mode = GetNormalizedSortMode(db)
    if mode == "NONE" then return end

    if InCombatLockdown() then
        pendingCombatUpdate = true
        return
    end

    local isDesc = (mode == "LEVEL_DESC")
    SortClassicQuestWatchFrame(isDesc)

    local tracker = _G["ObjectiveTrackerFrame"] or _G["WatchFrame"]
    if tracker and tracker:IsShown() then
        local modules = GetQuestTrackerModules(tracker)
        for _, mod in ipairs(modules) do
            SortObjectiveModuleBlocks(mod, isDesc)
        end
    end
end

-- =========================================================================
-- 3. HOOK INSTALLATION & REFRESH ORCHESTRATION
-- =========================================================================
local function HookTrackerModuleObject(mod)
    if type(mod) ~= "table" or hookedBlizzardObjects[mod] then return end
    hookedBlizzardObjects[mod] = true

    local function OnModulePostUpdate()
        if suppressNativeHooks or applyingOverride then return end
        QuestTracker:ApplyOverrides()
    end

    -- Hook only after mod:Update() (post-EndLayout), never inside LayoutContents() mid-pass.
    if type(mod.Update) == "function" then
        pcall(hooksecurefunc, mod, "Update", OnModulePostUpdate)
    end
end

local function InstallBlizzardHooks()
    if IsQuestieTrackerActive() then return end

    if type(QuestWatch_Update) == "function" and not hookedBlizzardObjects["QuestWatch_Update"] then
        hookedBlizzardObjects["QuestWatch_Update"] = true
        pcall(hooksecurefunc, "QuestWatch_Update", function()
            if suppressNativeHooks or applyingOverride then return end
            QuestTracker:ApplyOverrides()
        end)
    end
    if type(WatchFrame_Update) == "function" and not hookedBlizzardObjects["WatchFrame_Update"] then
        hookedBlizzardObjects["WatchFrame_Update"] = true
        pcall(hooksecurefunc, "WatchFrame_Update", function()
            if suppressNativeHooks or applyingOverride then return end
            QuestTracker:ApplyOverrides()
        end)
    end

    local tracker = _G["ObjectiveTrackerFrame"] or _G["WatchFrame"]
    if tracker then
        if not hookedBlizzardObjects[tracker] then
            hookedBlizzardObjects[tracker] = true
            local function OnTrackerPostLayout()
                if suppressNativeHooks or applyingOverride then return end
                QuestTracker:ApplyOverrides()
            end
            if type(tracker.Layout) == "function" then
                pcall(hooksecurefunc, tracker, "Layout", OnTrackerPostLayout)
            end
        end

        for _, mod in ipairs(GetQuestTrackerModules(tracker)) do
            HookTrackerModuleObject(mod)
        end
    end

    for _, qName in ipairs(KNOWN_QUEST_TRACKER_NAMES) do
        if _G[qName] then
            HookTrackerModuleObject(_G[qName])
        end
    end
end

function QuestTracker:ApplyOverrides()
    if applyingOverride or suppressNativeHooks then return end
    local db = YRG:GetModuleDB("QuestTrackerUpdater")
    if not db or not db.enabled then
        if self._statusText then
            self:UpdateStatusText()
        end
        return
    end

    local mode = GetNormalizedSortMode(db)
    if mode ~= "NONE" and not IsQuestieTrackerActive() then
        applyingOverride = true
        ApplyBlizzardSortOverride(db)
        applyingOverride = false
    end

    if self._statusText then
        self:UpdateStatusText()
    end
end

function QuestTracker:ScheduleOverridePass()
    if overrideTimerPending then return end
    if C_Timer and type(C_Timer.After) == "function" then
        overrideTimerPending = true
        C_Timer.After(0.05, function()
            overrideTimerPending = false
            self:ApplyOverrides()
        end)
    else
        self:ApplyOverrides()
    end
end

function QuestTracker:GetStatusMessage()
    local db = YRG:GetModuleDB("QuestTrackerUpdater")
    if not db or not db.enabled then
        return "Disabled in YRG module settings."
    end
    local target = IsQuestieTrackerActive() and "Questie Tracker" or "Blizzard Quest Tracker"
    local mode = GetNormalizedSortMode(db)
    return string.format("Superseding %s | Sort: %s", target, SORT_LABEL_BY_MODE[mode] or mode)
end

function QuestTracker:UpdateStatusText()
    if self._statusInitializer and self._statusInitializer.data then
        self._statusInitializer.data.name = "Status: " .. self:GetStatusMessage()
    end
end

function QuestTracker:TriggerFullTrackerRefresh()
    InstallQuestieHooks()
    InstallBlizzardHooks()

    if IsQuestieTrackerActive() then
        if QuestieLoader and type(QuestieLoader.ImportModule) == "function" then
            local ok, qTracker = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTracker")
            if ok and qTracker and qTracker.started and type(qTracker.Update) == "function" then
                pcall(qTracker.Update, qTracker)
            end
        end
    else
        -- Legacy Classic WatchFrame fallback only (never call ObjectiveTrackerFrame:Update() on Forever 1.60.1)
        if not _G["ObjectiveTrackerFrame"] and _G["QuestWatchFrame"] and _G["QuestWatchFrame"]:IsShown() and type(QuestWatch_Update) == "function" then
            suppressNativeHooks = true
            pcall(QuestWatch_Update)
            suppressNativeHooks = false
        end
        self:ApplyOverrides()
    end

    self:UpdateStatusText()
end

-- =========================================================================
-- 4. AUTO ACCEPT QUESTS (Modeled after Leatrix Plus)
-- =========================================================================
local function IsBypassKeyHeld()
    if type(IsOverrideKeyDown) == "function" then
        local ok, held = pcall(IsOverrideKeyDown)
        if ok and not YRG.IsSecret(held) and held then
            return true
        end
    end
    return (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) and true or false
end

local function ShouldAllowAutoAcceptQuest(frequency)
    -- Standard, daily, and weekly quest types when Auto Accept Quests is enabled
    return true
end

local function HandleAutoAcceptEvent(event)
    local db = YRG:GetModuleDB("QuestTrackerUpdater")
    if not db or not db.enabled or not db.autoAcceptQuests then
        return
    end
    if IsBypassKeyHeld() then
        return
    end

    if event == "QUEST_DETAIL" then
        if QuestGetAutoAccept and QuestGetAutoAccept() then
            if type(CloseQuest) == "function" then
                CloseQuest()
            end
        elseif type(AcceptQuest) == "function" then
            AcceptQuest()
        end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        if type(ConfirmAcceptQuest) == "function" then
            ConfirmAcceptQuest()
        end
        if type(StaticPopup_Hide) == "function" then
            StaticPopup_Hide("QUEST_ACCEPT")
        end
    elseif event == "QUEST_GREETING" then
        if type(GetNumAvailableQuests) == "function" and type(SelectAvailableQuest) == "function" then
            for i = 1, GetNumAvailableQuests() do
                local title, isComplete = nil, false
                if type(GetAvailableTitle) == "function" then
                    title, isComplete = GetAvailableTitle(i)
                end
                if title and not isComplete then
                    SelectAvailableQuest(i)
                    return
                end
            end
        end
    elseif event == "GOSSIP_SHOW" then
        if C_GossipInfo and type(C_GossipInfo.GetOptions) == "function" and type(C_GossipInfo.GetAvailableQuests) == "function" then
            if UnitExists("npc") or (QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown()) then
                -- Respect special color-coded skip-ahead gossip choices just like Leatrix Plus
                local options = C_GossipInfo.GetOptions()
                if type(options) == "table" then
                    for _, opt in ipairs(options) do
                        local nameText = YRG.SafeString(opt and opt.name, nil)
                        if nameText then
                            local upper = string.upper(nameText)
                            if (string.find(upper, "|C", 1, true) or string.find(upper, "<", 1, true))
                                and not string.find(nameText, "FF0008E8", 1, true) then
                                return
                            end
                        end
                    end
                end

                local available = C_GossipInfo.GetAvailableQuests()
                if type(available) == "table" then
                    for _, qInfo in ipairs(available) do
                        local qid = qInfo and qInfo.questID
                        if qid and ShouldAllowAutoAcceptQuest(qInfo.frequency) then
                            local reqMet = true
                            if type(DoesQuestHaveRequirementsMet) == "function" then
                                local okReq, met = pcall(DoesQuestHaveRequirementsMet, qid)
                                if okReq and not YRG.IsSecret(met) and not met then
                                    reqMet = false
                                end
                            end
                            if reqMet and type(C_GossipInfo.SelectAvailableQuest) == "function" then
                                C_GossipInfo.SelectAvailableQuest(qid)
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end

function QuestTracker:UpdateAutoAcceptEvents()
    if not self.autoAcceptFrame then
        self.autoAcceptFrame = CreateFrame("Frame")
        self.autoAcceptFrame:SetScript("OnEvent", function(_, event)
            HandleAutoAcceptEvent(event)
        end)
    end
    self.autoAcceptFrame:UnregisterAllEvents()
    local db = YRG:GetModuleDB("QuestTrackerUpdater")
    if db and db.enabled and db.autoAcceptQuests then
        self.autoAcceptFrame:RegisterEvent("QUEST_DETAIL")
        self.autoAcceptFrame:RegisterEvent("QUEST_ACCEPT_CONFIRM")
        self.autoAcceptFrame:RegisterEvent("QUEST_GREETING")
        self.autoAcceptFrame:RegisterEvent("GOSSIP_SHOW")
    end
end

-- =========================================================================
-- 4B. AUTO-TRACK NEWLY ACCEPTED QUESTS (Synced with autoQuestWatch CVar)
-- =========================================================================
local function SetAutoQuestWatchCVar(enabled)
    if InCombatLockdown() then return end
    local want = enabled and "1" or "0"
    local cur = (C_CVar and type(C_CVar.GetCVar) == "function" and C_CVar.GetCVar("autoQuestWatch"))
        or (type(GetCVar) == "function" and GetCVar("autoQuestWatch"))
    if cur ~= want then
        if C_CVar and type(C_CVar.SetCVar) == "function" then
            pcall(C_CVar.SetCVar, "autoQuestWatch", want)
        elseif type(SetCVar) == "function" then
            pcall(SetCVar, "autoQuestWatch", want)
        end
    end
end

local function ResolveAcceptedQuestID(arg1, arg2)
    if type(arg2) == "number" and arg2 > 0 then
        return arg2
    end
    if type(arg1) ~= "number" or arg1 <= 0 then
        return nil
    end
    if C_QuestLog and type(C_QuestLog.GetLogIndexForQuestID) == "function" then
        local okIdx, idx = pcall(C_QuestLog.GetLogIndexForQuestID, arg1)
        if okIdx and idx and idx > 0 then
            return arg1
        end
    end
    if C_QuestLog and type(C_QuestLog.GetInfo) == "function" then
        local okInfo, info = pcall(C_QuestLog.GetInfo, arg1)
        if okInfo and type(info) == "table" and type(info.questID) == "number" and info.questID > 0 then
            return info.questID
        end
    end
    return arg1
end

local function EnsureQuestTracked(questID)
    if type(questID) ~= "number" or questID <= 0 then return end
    local db = YRG:GetModuleDB("QuestTrackerUpdater")
    if not db or not db.enabled or db.autoTrackQuests == false then return end

    local logIdx = nil
    if C_QuestLog and type(C_QuestLog.GetLogIndexForQuestID) == "function" then
        local okIdx, idx = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if okIdx and idx and idx > 0 then
            logIdx = idx
            if type(C_QuestLog.GetInfo) == "function" then
                local okInfo, info = pcall(C_QuestLog.GetInfo, idx)
                if okInfo and type(info) == "table" and (info.isHeader or info.isHidden) then
                    return
                end
            end
        end
    elseif type(GetQuestLogIndexByID) == "function" then
        local okIdx, idx = pcall(GetQuestLogIndexByID, questID)
        if okIdx and idx and idx > 0 then
            logIdx = idx
        end
    end

    local alreadyWatched = false
    if C_QuestLog and type(C_QuestLog.GetQuestWatchType) == "function" then
        local okWatch, watchType = pcall(C_QuestLog.GetQuestWatchType, questID)
        if okWatch and watchType ~= nil then
            alreadyWatched = true
        end
    elseif logIdx and type(IsQuestWatched) == "function" then
        local okWatch, watched = pcall(IsQuestWatched, logIdx)
        if okWatch and watched then
            alreadyWatched = true
        end
    end

    if not alreadyWatched then
        if C_QuestLog and type(C_QuestLog.AddQuestWatch) == "function" then
            pcall(C_QuestLog.AddQuestWatch, questID)
        elseif logIdx and type(AddQuestWatch) == "function" then
            pcall(AddQuestWatch, logIdx)
        end
    end

    QuestTracker:ScheduleOverridePass()
end

function QuestTracker:SyncAutoTrackSettings()
    if not self.autoTrackFrame then
        self.autoTrackFrame = CreateFrame("Frame")
        self.autoTrackFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
            if event ~= "QUEST_ACCEPTED" then return end
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0.05, function()
                    local qid = ResolveAcceptedQuestID(arg1, arg2)
                    if qid then
                        EnsureQuestTracked(qid)
                    end
                end)
            else
                local qid = ResolveAcceptedQuestID(arg1, arg2)
                if qid then
                    EnsureQuestTracked(qid)
                end
            end
        end)
    end

    self.autoTrackFrame:UnregisterAllEvents()
    local db = YRG:GetModuleDB("QuestTrackerUpdater")
    if db and db.enabled then
        local wantAutoTrack = (db.autoTrackQuests ~= false)
        SetAutoQuestWatchCVar(wantAutoTrack)
        if wantAutoTrack then
            self.autoTrackFrame:RegisterEvent("QUEST_ACCEPTED")
        end
    end
end

-- =========================================================================
-- 5. LIFECYCLE & SETTINGS UI
-- =========================================================================
function QuestTracker:OnInitialize(db)
    if db.autoTrackQuests == nil then
        db.autoTrackQuests = true
    end
    if db.sortOrder == nil then
        if db.reverseSort == true then
            db.sortOrder = "LEVEL_DESC"
        else
            db.sortOrder = "LEVEL_ASC"
        end
    elseif not VALID_SORT_MODES[db.sortOrder] then
        db.sortOrder = "LEVEL_ASC"
    end
    db.layoutDirection = nil
    db.textOrientation = nil
    db.growDirection = nil
    db.reverseSort = nil

    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("PLAYER_LOGIN")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    self.eventFrame:SetScript("OnEvent", function(_, event)
        InstallQuestieHooks()
        InstallBlizzardHooks()
        if event == "PLAYER_REGEN_ENABLED" then
            self:SyncAutoTrackSettings()
            if pendingCombatUpdate then
                pendingCombatUpdate = false
                self:ScheduleOverridePass()
            end
        elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            self:SyncAutoTrackSettings()
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0.5, function()
                    InstallQuestieHooks()
                    InstallBlizzardHooks()
                    self:ScheduleOverridePass()
                end)
            else
                self:ScheduleOverridePass()
            end
        end
    end)

    InstallQuestieHooks()
    InstallBlizzardHooks()
end

function QuestTracker:OnEnable(db)
    InstallQuestieHooks()
    InstallBlizzardHooks()
    self:SyncAutoTrackSettings()
    self:UpdateAutoAcceptEvents()
    self:TriggerFullTrackerRefresh()
    self:UpdateStatusText()
end

function QuestTracker:OnDisable(db)
    self:SyncAutoTrackSettings()
    self:UpdateAutoAcceptEvents()
    self:TriggerFullTrackerRefresh()
    self:UpdateStatusText()
end

function QuestTracker:BuildConfigUI(ctx, db)
    local function GetDB()
        return YRG:GetModuleDB("QuestTrackerUpdater")
    end

    ctx:AddHeader(
        "1. Quest Sorting",
        "Controls quest sort order for Questie and Blizzard's built-in Quest Tracker while leaving orientation and grow direction untouched."
    )

    self._statusInitializer = ctx:AddButton({
        name = "Status: " .. self:GetStatusMessage(),
        buttonText = "Check Status",
        tooltip = "Refreshes and prints which tracker target and sort mode QuestTrackerUpdater is currently managing.",
        onClick = function()
            self:UpdateStatusText()
            print("|cffffd100YRG QuestTrackerUpdater:|r " .. self:GetStatusMessage())
        end,
    })

    ctx:AddDropdown({
        key = "sortOrder",
        name = "Quest Sort Order",
        tooltip = "Choose how tracked quests are ordered in Questie and built-in trackers.",
        defaultValue = "LEVEL_ASC",
        options = SORT_OPTIONS,
        get = function()
            return GetNormalizedSortMode(GetDB())
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.sortOrder = VALID_SORT_MODES[val] and val or "LEVEL_ASC"
            end
            self:TriggerFullTrackerRefresh()
            self:UpdateStatusText()
        end,
    })

    ctx:AddHeader("2. Quest Automation")

    ctx:AddCheckbox({
        key = "autoTrackQuests",
        name = "Auto-Track Newly Accepted Quests",
        tooltip = "Automatically tracks newly accepted quests in your quest tracker and enables Blizzard's autoQuestWatch setting.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.autoTrackQuests ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.autoTrackQuests = val
            end
            self:SyncAutoTrackSettings()
        end,
    })

    ctx:AddCheckbox({
        key = "autoAcceptQuests",
        name = "Auto Accept Quests (Hold Shift to Bypass)",
        tooltip = "Automatically accepts offered quests when speaking to NPCs (hold Shift while opening dialog to temporarily pause auto-accept). Modeled after Leatrix Plus.",
        defaultValue = false,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.autoAcceptQuests) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.autoAcceptQuests = val
            end
            self:UpdateAutoAcceptEvents()
        end,
    })
end

YRG:RegisterModule("QuestTrackerUpdater", QuestTracker)
