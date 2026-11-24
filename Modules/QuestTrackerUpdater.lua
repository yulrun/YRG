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
    description = "Controls quest sorting order, Questie chain quest & turn-in XP % indicators, automatic tracking of newly accepted quests, and optional Auto Accept Quests.",
    defaultEnabled = true,
    defaults = {
        enabled = true,
        sortOrder = "LEVEL_ASC", -- "NONE", "LEVEL_ASC", "LEVEL_DESC"
        markChainQuests = true,
        chainQuestTooltip = true,
        showTurnInXPPercent = true,
        autoTrackQuests = true,
        autoAcceptQuests = false,
    }
}

local TEX_QUEST_CHAIN = "Interface\\AddOns\\YRG\\Textures\\QuestChainIcon"

local applyingOverride = false
local suppressNativeHooks = false
local overrideTimerPending = false
local pendingCombatUpdate = false
local questieSortHooked = false
local questieLineHooked = false
local hookedBlizzardObjects = {}
local hookedQuestieTitleLines = setmetatable({}, { __mode = "k" })

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
        local cleanFallback = fallbackTitleText:gsub("|T.-|t%s*", "")
        local lvlStr = cleanFallback:match("^%s*%[?(%d+)%]?")
        if lvlStr then
            level = tonumber(lvlStr)
        end
        title = title or cleanFallback
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
-- 1. QUESTIE CHAIN DETECTION, ICONS & TOOLTIP HELPERS
-- =========================================================================
local chainReverseMap = {}
local chainStatusCache = {}
local chainScanState = {
    started = false,
    finished = false,
    ids = nil,
    idx = 1,
    timerActive = false,
}
local chainTooltip = nil
local hoveredChainLine = nil

local function ImportQuestieModule(name)
    if not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then
        return nil
    end
    local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    if ok and type(mod) == "table" then
        return mod
    end
    return nil
end

local function IsQuestCompletedInQuestie(questId)
    if type(questId) ~= "number" or questId <= 0 then return false end
    local completed = Questie and Questie.db and Questie.db.char and Questie.db.char.complete
    if completed and completed[questId] then
        return true
    end
    if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function" then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questId)
        if ok and not YRG.IsSecret(done) and done then
            return true
        end
    end
    return false
end

local function IsFollowUpAccessible(qDB, qCorr, qPlayer, followId)
    if type(followId) ~= "number" or followId <= 0 then return false end
    if type(qDB.QuestPointers) == "table" and not qDB.QuestPointers[followId] then
        return false
    end
    if qCorr and type(qCorr.hiddenQuests) == "table" and qCorr.hiddenQuests[followId] then
        return false
    end
    if IsQuestCompletedInQuestie(followId) then
        return false
    end
    if type(qDB.QueryQuestSingle) ~= "function" then
        return false
    end

    local okR, reqRaces = pcall(qDB.QueryQuestSingle, followId, "requiredRaces")
    if okR and reqRaces and reqRaces ~= 0 and qPlayer and type(qPlayer.HasRequiredRace) == "function" then
        local okHR, hasRace = pcall(qPlayer.HasRequiredRace, reqRaces)
        if okHR and not hasRace then
            return false
        end
    end
    local okC, reqClasses = pcall(qDB.QueryQuestSingle, followId, "requiredClasses")
    if okC and reqClasses and reqClasses ~= 0 and qPlayer and type(qPlayer.HasRequiredClass) == "function" then
        local okHC, hasClass = pcall(qPlayer.HasRequiredClass, reqClasses)
        if okHC and not hasClass then
            return false
        end
    end
    local okEx, exclusiveTo = pcall(qDB.QueryQuestSingle, followId, "exclusiveTo")
    if okEx and type(exclusiveTo) == "table" then
        for _, exId in pairs(exclusiveTo) do
            if type(exId) == "number" and exId > 0 and IsQuestCompletedInQuestie(exId) then
                return false
            end
        end
    end
    return true
end

local function QuestExplicitlyRequiresPrereq(qDB, followId, prereqId)
    if type(qDB.QueryQuestSingle) ~= "function" then return false end
    local okG, grp = pcall(qDB.QueryQuestSingle, followId, "preQuestGroup")
    if okG and type(grp) == "table" then
        for _, pid in pairs(grp) do
            if type(pid) == "number" and math.abs(pid) == prereqId then
                return true
            end
        end
    end
    local okS, sng = pcall(qDB.QueryQuestSingle, followId, "preQuestSingle")
    if okS and type(sng) == "table" then
        for _, pid in pairs(sng) do
            if type(pid) == "number" and math.abs(pid) == prereqId then
                return true
            end
        end
    end
    local okA, avail = pcall(qDB.QueryQuestSingle, followId, "availableStartingWith")
    if okA and type(avail) == "number" and avail == prereqId then
        return true
    end
    return false
end

local function IsBreadcrumbOnlyTarget(qDB, questId, targetId)
    if type(qDB.QueryQuestSingle) ~= "function" then return false end
    local okB, crumbFor = pcall(qDB.QueryQuestSingle, questId, "breadcrumbForQuestId")
    if okB and type(crumbFor) == "number" and crumbFor == targetId then
        return not QuestExplicitlyRequiresPrereq(qDB, targetId, questId)
    end
    local okC, crumbs = pcall(qDB.QueryQuestSingle, targetId, "breadcrumbs")
    if okC and type(crumbs) == "table" then
        for _, cid in pairs(crumbs) do
            if cid == questId then
                return not QuestExplicitlyRequiresPrereq(qDB, targetId, questId)
            end
        end
    end
    return false
end

local function AddReverseDep(prereqId, depEntry)
    if type(prereqId) ~= "number" or prereqId <= 0 then return end
    local bucket = chainReverseMap[prereqId]
    if not bucket then
        bucket = {}
        chainReverseMap[prereqId] = bucket
    end
    bucket[#bucket + 1] = depEntry
end

local function ScheduleReverseChainScan()
    if chainScanState.finished or chainScanState.timerActive then return end
    local modDB = YRG:GetModuleDB("QuestTrackerUpdater")
    if not modDB or not modDB.enabled or modDB.markChainQuests == false then return end
    if not C_Timer or type(C_Timer.After) ~= "function" then return end

    chainScanState.timerActive = true
    local function StepScan()
        chainScanState.timerActive = false
        local dbNow = YRG:GetModuleDB("QuestTrackerUpdater")
        if not dbNow or not dbNow.enabled or dbNow.markChainQuests == false then
            return
        end
        local qDB = ImportQuestieModule("QuestieDB")
        local qCorr = ImportQuestieModule("QuestieCorrections")
        if not qDB or type(qDB.QuestPointers) ~= "table" or type(qDB.QueryQuestSingle) ~= "function"
            or (Questie and Questie.started == false) then
            chainScanState.timerActive = true
            C_Timer.After(0.75, StepScan)
            return
        end
        if not chainScanState.ids then
            local ids = {}
            local hidden = qCorr and qCorr.hiddenQuests
            for qid in pairs(qDB.QuestPointers) do
                if type(qid) == "number" and qid > 0 and not (hidden and hidden[qid]) then
                    ids[#ids + 1] = qid
                end
            end
            chainScanState.ids = ids
            chainScanState.idx = 1
            chainScanState.started = true
        end
        if InCombatLockdown() then
            return
        end

        local ids = chainScanState.ids
        local total = #ids
        local stopAt = math.min(total, chainScanState.idx + 79)
        for i = chainScanState.idx, stopAt do
            local qid = ids[i]
            local okG, grp = pcall(qDB.QueryQuestSingle, qid, "preQuestGroup")
            if okG and type(grp) == "table" then
                for _, preId in pairs(grp) do
                    if type(preId) == "number" and preId ~= 0 then
                        AddReverseDep(math.abs(preId), { id = qid, kind = "group" })
                    end
                end
            end
            local okS, sng = pcall(qDB.QueryQuestSingle, qid, "preQuestSingle")
            if okS and type(sng) == "table" then
                for _, preId in pairs(sng) do
                    if type(preId) == "number" and preId ~= 0 then
                        AddReverseDep(math.abs(preId), { id = qid, kind = "single", alts = sng })
                    end
                end
            end
            local okA, availStart = pcall(qDB.QueryQuestSingle, qid, "availableStartingWith")
            if okA and type(availStart) == "number" and availStart > 0 then
                AddReverseDep(availStart, { id = qid, kind = "avail" })
            end
        end
        chainScanState.idx = stopAt + 1

        if chainScanState.idx > total then
            chainScanState.finished = true
            wipe(chainStatusCache)
            QuestTracker:TriggerFullTrackerRefresh()
        else
            chainScanState.timerActive = true
            C_Timer.After(0.03, StepScan)
        end
    end

    C_Timer.After(1.0, StepScan)
end

local function CollectDirectFollowUps(questId, qDB, qCorr, qPlayer)
    local out = {}
    local seen = {}
    local function TryAdd(targetId)
        if type(targetId) ~= "number" or targetId <= 0 or targetId == questId or seen[targetId] then
            return
        end
        if IsBreadcrumbOnlyTarget(qDB, questId, targetId) then
            return
        end
        if IsFollowUpAccessible(qDB, qCorr, qPlayer, targetId) then
            seen[targetId] = true
            out[#out + 1] = targetId
        end
    end

    local okN, nextId = pcall(qDB.QueryQuestSingle, questId, "nextQuestInChain")
    if okN and type(nextId) == "number" and nextId > 0 then
        TryAdd(nextId)
    end

    local okC, childs = pcall(qDB.QueryQuestSingle, questId, "childQuests")
    if okC and type(childs) == "table" then
        for _, childId in pairs(childs) do
            TryAdd(childId)
        end
    end

    local revDeps = chainReverseMap[questId]
    if type(revDeps) == "table" then
        for _, dep in ipairs(revDeps) do
            local altDone = false
            if dep.kind == "single" and type(dep.alts) == "table" then
                for _, altId in pairs(dep.alts) do
                    local absAlt = type(altId) == "number" and math.abs(altId) or 0
                    if absAlt > 0 and absAlt ~= questId and IsQuestCompletedInQuestie(absAlt) then
                        altDone = true
                        break
                    end
                end
            end
            if not altDone then
                TryAdd(dep.id)
            end
        end
    end

    if #out > 1 then
        table.sort(out)
    end
    return out
end

local function GetQuestChainInfo(questId)
    if type(questId) ~= "number" or questId <= 0 then
        return nil
    end
    local cached = chainStatusCache[questId]
    if cached ~= nil then
        return cached
    end

    local qDB = ImportQuestieModule("QuestieDB")
    if not qDB or type(qDB.QueryQuestSingle) ~= "function" then
        return nil
    end
    if type(qDB.QuestPointers) == "table" and not qDB.QuestPointers[questId] then
        return nil
    end
    if Questie and Questie.started == false then
        return nil
    end

    ScheduleReverseChainScan()

    local qCorr = ImportQuestieModule("QuestieCorrections")
    local qPlayer = ImportQuestieModule("QuestiePlayer")
    local direct = CollectDirectFollowUps(questId, qDB, qCorr, qPlayer)
    local info = {
        required = #direct > 0,
        followUps = direct,
        trail = {},
    }

    if #direct > 0 then
        local qLib = ImportQuestieModule("QuestieLib")
        local visited = { [questId] = true }
        local curId = direct[1]
        for hop = 1, 4 do
            if not curId or visited[curId] then break end
            visited[curId] = true
            local name = YRG.SafeString(qDB.QueryQuestSingle(curId, "name"), nil) or ("Quest #" .. curId)
            local lvl = nil
            if qLib and type(qLib.GetEffectiveQuestLevel) == "function" then
                local okL, effLvl = pcall(qLib.GetEffectiveQuestLevel, curId)
                if okL and type(effLvl) == "number" and effLvl > 0 then
                    lvl = effLvl
                end
            end
            if not lvl then
                local okQL, qLvl = pcall(qDB.QueryQuestSingle, curId, "questLevel")
                if okQL and type(qLvl) == "number" and qLvl > 0 then
                    lvl = qLvl
                end
            end
            info.trail[#info.trail + 1] = {
                id = curId,
                level = lvl,
                name = name,
                branchCount = (hop == 1 and #direct > 1) and (#direct - 1) or 0,
            }
            local nextFollow = CollectDirectFollowUps(curId, qDB, qCorr, qPlayer)
            curId = nextFollow[1]
        end
    end

    chainStatusCache[questId] = info
    return info
end

local function IsQuestRequiredForChain(questId)
    local info = GetQuestChainInfo(questId)
    return (info and info.required) and true or false
end

local function GetChainIconPrefix(iconSize)
    local sz = math.max(10, math.min(20, math.floor((tonumber(iconSize) or 12) + 0.5)))
    return string.format("|T%s:%d:%d:0:0|t ", TEX_QUEST_CHAIN, sz, sz)
end

-- =========================================================================
-- 1A. QUESTIE TURN-IN XP PERCENTAGE HELPERS
-- =========================================================================
local xpTrackerState = {
    maxXP = nil,
    playerLevel = nil,
    questXP = {},
    appliedFS = setmetatable({}, { __mode = "k" }),
    lineAdj = setmetatable({}, { __mode = "k" }),
    blkAdj = setmetatable({}, { __mode = "k" }),
    blkShift = setmetatable({}, { __mode = "k" }),
    modAdj = setmetatable({}, { __mode = "k" }),
    retryPending = false,
    retryCount = 0,
}

local function StripWowTextFormatting(txt)
    if type(txt) ~= "string" then return "" end
    local s = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function IsQuestCompleteInLog(questId)
    if type(questId) ~= "number" or questId <= 0 then return false end
    if C_QuestLog and type(C_QuestLog.IsComplete) == "function" then
        local ok, done = pcall(C_QuestLog.IsComplete, questId)
        if ok and not YRG.IsSecret(done) then
            return done and true or false
        end
    end
    if type(GetQuestLogIndexByID) == "function" and type(GetQuestLogTitle) == "function" then
        local okIdx, logIdx = pcall(GetQuestLogIndexByID, questId)
        if okIdx and type(logIdx) == "number" and logIdx > 0 then
            local okT, _, _, _, _, _, isComplete = pcall(GetQuestLogTitle, logIdx)
            if okT and not YRG.IsSecret(isComplete) then
                return (isComplete == 1 or isComplete == true) and true or false
            end
        end
    end
    return false
end

local function IsTurnInObjectiveText(plainText, isQuestComplete, totalObjLines)
    if type(plainText) ~= "string" or plainText == "" then
        return false, false
    end
    local lower = string.lower(plainText):gsub("^[-*%s]+", "")
    local readyGlobal = type(QUEST_WATCH_QUEST_READY) == "string"
        and string.lower(StripWowTextFormatting(QUEST_WATCH_QUEST_READY)):gsub("^[-*%s]+", "")
        or nil
    local completeGlobal = type(QUEST_WATCH_QUEST_COMPLETE) == "string"
        and string.lower(StripWowTextFormatting(QUEST_WATCH_QUEST_COMPLETE)):gsub("^[-*%s]+", "")
        or nil

    local explicitMatch = (readyGlobal and readyGlobal ~= "" and lower == readyGlobal)
        or (completeGlobal and completeGlobal ~= "" and lower == completeGlobal)
        or lower == "ready for turn-in"
        or lower == "ready for turn in"
        or lower == "quest complete"
        or lower == "quest complete!"
    if explicitMatch then
        return true, true
    end

    if isQuestComplete and totalObjLines == 1 then
        if not lower:find("%d+%s*/%s*%d+")
            and not lower:find("time remaining")
            and not lower:match("^%d+:%d+") then
            return true, false
        end
    end
    return false, false
end

local function ScheduleQuestieXPRefresh()
    if xpTrackerState.retryPending or xpTrackerState.retryCount >= 6 then return end
    if not C_Timer or type(C_Timer.After) ~= "function" then return end
    local modDB = YRG:GetModuleDB("QuestTrackerUpdater")
    if not modDB or not modDB.enabled or modDB.showTurnInXPPercent == false then return end

    xpTrackerState.retryPending = true
    xpTrackerState.retryCount = xpTrackerState.retryCount + 1
    C_Timer.After(0.75, function()
        xpTrackerState.retryPending = false
        local dbNow = YRG:GetModuleDB("QuestTrackerUpdater")
        if not dbNow or not dbNow.enabled or dbNow.showTurnInXPPercent == false then return end
        local qXP = ImportQuestieModule("QuestXP")
        if qXP and type(qXP.db) == "table" and (not Questie or Questie.started ~= false) then
            QuestTracker:TriggerFullTrackerRefresh()
        elseif Questie and Questie.started == false then
            ScheduleQuestieXPRefresh()
        end
    end)
end

local function GetQuestTurnInXPBracketText(questId)
    if type(questId) ~= "number" or questId <= 0 then
        return nil
    end

    local rawLvl = type(UnitLevel) == "function" and UnitLevel("player") or nil
    local playerLevel = (rawLvl ~= nil and not YRG.IsSecret(rawLvl)) and YRG.SafeNumber(rawLvl, 0) or xpTrackerState.playerLevel
    if rawLvl ~= nil and not YRG.IsSecret(rawLvl) and playerLevel > 0 then
        xpTrackerState.playerLevel = playerLevel
    end

    local rawMaxLvl = type(GetMaxPlayerLevel) == "function" and GetMaxPlayerLevel() or nil
    local maxLevel = (rawMaxLvl ~= nil and not YRG.IsSecret(rawMaxLvl)) and YRG.SafeNumber(rawMaxLvl, 0) or 60
    if playerLevel and maxLevel > 0 and playerLevel >= maxLevel then
        return nil
    end

    local rawMaxXP = type(UnitXPMax) == "function" and UnitXPMax("player") or nil
    local maxXP = (rawMaxXP ~= nil and not YRG.IsSecret(rawMaxXP)) and YRG.SafeNumber(rawMaxXP, 0) or xpTrackerState.maxXP
    if rawMaxXP ~= nil and not YRG.IsSecret(rawMaxXP) and maxXP > 0 then
        xpTrackerState.maxXP = maxXP
    end
    if not maxXP or maxXP <= 0 then
        return nil
    end

    local qXP = ImportQuestieModule("QuestXP")
    if not qXP or type(qXP.db) ~= "table" or type(qXP.GetQuestLogRewardXP) ~= "function" then
        if Questie then
            ScheduleQuestieXPRefresh()
        end
        return nil
    end
    if Questie and Questie.started == false then
        ScheduleQuestieXPRefresh()
        return nil
    end

    local okXP, rawXP = pcall(qXP.GetQuestLogRewardXP, qXP, questId, false)
    local xp = (okXP and rawXP ~= nil and not YRG.IsSecret(rawXP)) and YRG.SafeNumber(rawXP, 0) or nil
    if xp == nil then
        xp = xpTrackerState.questXP[questId]
    else
        xpTrackerState.questXP[questId] = xp
    end
    if not xp or xp <= 0 then
        return nil
    end

    local pct = (xp / maxXP) * 100
    if pct <= 0 then
        return nil
    end
    local pctStr = (pct < 0.05) and "<0.1%" or (string.format("%.1f", pct):gsub("%.0$", "") .. "%")
    return string.format(" |cffffd100[%s]|r", pctStr)
end

local function HideChainTooltip(line)
    if line and hoveredChainLine and hoveredChainLine ~= line then
        return
    end
    hoveredChainLine = nil
    if chainTooltip then
        chainTooltip:Hide()
    end
end

local function AppendChainTooltipLines(tt, info)
    if not tt or not info or not info.required then return end
    tt:AddLine(GetChainIconPrefix(14) .. "Chain Quest Prerequisite", 1.0, 0.82, 0.20)
    for i, node in ipairs(info.trail) do
        local lvlPrefix = node.level and string.format("[%d] ", node.level) or ""
        local branchSuffix = (node.branchCount and node.branchCount > 0) and string.format(" (+%d more)", node.branchCount) or ""
        local prefix = (i == 1) and "Leads to: " or "   -> "
        tt:AddLine(prefix .. lvlPrefix .. node.name .. branchSuffix, (i == 1) and 1.0 or 0.82, (i == 1) and 1.0 or 0.82, (i == 1) and 1.0 or 0.82, true)
    end
    tt:AddLine("Dropping this quest may block follow-up quests.", 0.68, 0.68, 0.68, true)
end

local function ShowChainTooltipForLine(line)
    if not line then return end
    local modDB = YRG:GetModuleDB("QuestTrackerUpdater")
    if not modDB or not modDB.enabled or modDB.markChainQuests == false or modDB.chainQuestTooltip == false then
        HideChainTooltip()
        return
    end
    if line.mode ~= "quest" or not line.Quest or type(line.Quest.Id) ~= "number" then
        HideChainTooltip()
        return
    end
    local info = GetQuestChainInfo(line.Quest.Id)
    if not info or not info.required or #info.trail == 0 then
        HideChainTooltip()
        return
    end

    local qTip = _G["QuestieTrackerQuestTooltip"]
    if not chainTooltip then
        chainTooltip = CreateFrame("GameTooltip", "YRGQuestChainTooltip", UIParent, "GameTooltipTemplate")
        chainTooltip:SetClampedToScreen(true)
        chainTooltip:Hide()
    end
    hoveredChainLine = line
    chainTooltip:SetOwner(line, "ANCHOR_NONE")
    chainTooltip:ClearAllPoints()
    if qTip and qTip:IsShown() then
        chainTooltip:SetPoint("BOTTOMLEFT", qTip, "TOPLEFT", 0, 2)
    else
        chainTooltip:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 0, 4)
    end
    chainTooltip:ClearLines()
    AppendChainTooltipLines(chainTooltip, info)
    chainTooltip:Show()
end

local function HookQuestieTitleLineHover(line)
    if not line or hookedQuestieTitleLines[line] or type(line.HookScript) ~= "function" then
        return
    end
    hookedQuestieTitleLines[line] = true
    line:HookScript("OnEnter", function(selfLine)
        ShowChainTooltipForLine(selfLine)
    end)
    line:HookScript("OnLeave", function(selfLine)
        HideChainTooltip(selfLine)
    end)
    line:HookScript("OnHide", function(selfLine)
        HideChainTooltip(selfLine)
    end)
end

-- =========================================================================
-- 1B. QUESTIE DETECTION & NATIVE SORT / TITLE ICON HOOKS
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
    if not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then
        return
    end

    if not questieSortHooked then
        local tUtils = ImportQuestieModule("TrackerUtils")
        if tUtils and type(tUtils.GetSortedQuestIds) == "function" then
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
    end

    if not questieLineHooked then
        local lBuilder = ImportQuestieModule("LineBuilder")
        if lBuilder and type(lBuilder.AddTitle) == "function" then
            if not lBuilder._yrgChainHooked then
                lBuilder._yrgChainHooked = true
                local origAddTitle = lBuilder.AddTitle
                lBuilder.AddTitle = function(options)
                    local modDB = YRG:GetModuleDB("QuestTrackerUpdater")
                    local origText = type(options) == "table" and options.text or nil
                    local modified = false
                    if modDB and modDB.enabled and modDB.markChainQuests ~= false
                        and type(options) == "table" and options.clickMode == "quest"
                        and type(options.target) == "table" and type(options.target.Id) == "number"
                        and type(origText) == "string" and not origText:find(TEX_QUEST_CHAIN, 1, true) then
                        if IsQuestRequiredForChain(options.target.Id) then
                            local fontSz = (Questie and Questie.db and Questie.db.profile and Questie.db.profile.trackerFontSizeQuest) or 12
                            options.text = GetChainIconPrefix(fontSz) .. origText
                            modified = true
                        end
                    end

                    local line, collapsed = origAddTitle(options)
                    if modified and type(options) == "table" then
                        options.text = origText
                    end
                    if line and type(options) == "table" and options.clickMode == "quest" then
                        HookQuestieTitleLineHover(line)
                    end
                    return line, collapsed
                end
            end
            if not lBuilder._yrgTurnInXpHooked and type(lBuilder.AddObjective) == "function" then
                lBuilder._yrgTurnInXpHooked = true
                local origAddObjective = lBuilder.AddObjective
                lBuilder.AddObjective = function(options)
                    local modDB = YRG:GetModuleDB("QuestTrackerUpdater")
                    local origText = type(options) == "table" and options.text or nil
                    local modified = false
                    if modDB and modDB.enabled and modDB.showTurnInXPPercent ~= false
                        and type(options) == "table" and options.clickMode == "quest"
                        and options.objective == nil
                        and type(options.target) == "table" and type(options.target.Id) == "number"
                        and type(origText) == "string" and origText ~= "" then
                        local complete = (type(options.target.IsComplete) == "function" and options.target:IsComplete())
                            or options.target.completionState
                        if complete ~= -1 and (complete == 1 or options.target.isComplete == true) then
                            local plain = StripWowTextFormatting(origText)
                            if IsTurnInObjectiveText(plain, true, 1) then
                                local tag = GetQuestTurnInXPBracketText(options.target.Id)
                                if tag then
                                    options.text = origText .. tag
                                    modified = true
                                end
                            end
                        end
                    end

                    local line = origAddObjective(options)
                    if modified and type(options) == "table" then
                        options.text = origText
                    end
                    return line
                end
            end
            questieLineHooked = true
        end
    end
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
    local accExtra = 0
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
            xpTrackerState.blkShift[blk] = (accExtra > 0) and {
                extraShift = accExtra,
                setY = curY,
            } or nil
        end
        local bAdj = xpTrackerState.blkAdj[blk]
        if bAdj and type(bAdj.extra) == "number" and bAdj.extra > 0 then
            accExtra = accExtra + bAdj.extra
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

local function CollectBlockObjectiveFontStrings(blk)
    local list = {}
    local seenFS = {}
    local seenObj = {}

    local function AddFS(fs)
        if type(fs) ~= "table" or seenFS[fs] or fs == blk.HeaderText then
            return
        end
        if type(fs.IsForbidden) == "function" and fs:IsForbidden() then
            return
        end
        if type(fs.GetText) ~= "function" or type(fs.SetText) ~= "function" then
            return
        end
        if type(fs.IsShown) == "function" and not fs:IsShown() then
            return
        end
        seenFS[fs] = true
        list[#list + 1] = fs
    end

    local function InspectLineContainer(obj)
        if type(obj) ~= "table" or seenObj[obj] then return end
        seenObj[obj] = true
        if type(obj.IsForbidden) == "function" and obj:IsForbidden() then
            return
        end
        if type(obj.IsObjectType) == "function" and obj:IsObjectType("FontString") then
            AddFS(obj)
            return
        end
        if type(obj.IsShown) == "function" and not obj:IsShown() then
            return
        end
        if obj.Text then AddFS(obj.Text) end
        if obj.text then AddFS(obj.text) end
        if not obj.Text and not obj.text then
            for _, childVal in pairs(obj) do
                if type(childVal) == "table" and childVal ~= obj and (childVal.Text or childVal.text) then
                    InspectLineContainer(childVal)
                end
            end
        end
    end

    if type(blk.usedLines) == "table" then
        InspectLineContainer(blk.usedLines)
        for _, v in pairs(blk.usedLines) do
            InspectLineContainer(v)
        end
    end
    if type(blk.lines) == "table" then
        for _, v in pairs(blk.lines) do
            InspectLineContainer(v)
        end
    end
    if blk.currentLine then
        InspectLineContainer(blk.currentLine)
    end
    if type(blk.GetChildren) == "function" then
        for _, ch in ipairs({ blk:GetChildren() }) do
            InspectLineContainer(ch)
        end
    end
    return list
end

local function CanSafelyResizeTrackerObj(obj)
    if type(obj) ~= "table" or InCombatLockdown() then return false end
    if type(obj.IsForbidden) == "function" and obj:IsForbidden() then return false end
    if type(obj.IsProtected) == "function" then
        local okP, prot = pcall(obj.IsProtected, obj)
        if okP and prot then return false end
    end
    return true
end

local function ShiftPointsRelativeToParent(frame, targetParent1, targetParent2, deltaY)
    if not CanSafelyResizeTrackerObj(frame) or math.abs(deltaY) < 0.1 then return false end
    if type(frame.GetNumPoints) ~= "function" or type(frame.GetPoint) ~= "function" then return false end
    local numPts = frame:GetNumPoints()
    if numPts <= 0 then return false end
    local saved = {}
    local changed = false
    for p = 1, numPts do
        local okPt, pt, relTo, relPt, x, y = pcall(frame.GetPoint, frame, p)
        if not okPt or not pt then return false end
        if (relTo == targetParent1 or (targetParent2 and relTo == targetParent2)) and type(y) == "number" then
            y = y - deltaY
            changed = true
        end
        saved[p] = { pt, relTo, relPt, x, y }
    end
    if not changed then return false end
    frame:ClearAllPoints()
    for _, ptInfo in ipairs(saved) do
        frame:SetPoint(ptInfo[1], ptInfo[2], ptInfo[3], ptInfo[4], ptInfo[5])
    end
    return true
end

local function ApplyTurnInXpToBlock(blk, qid, showTurnInXP)
    local fsList = CollectBlockObjectiveFontStrings(blk)
    if #fsList == 0 then
        local bRec = xpTrackerState.blkAdj[blk]
        if bRec and CanSafelyResizeTrackerObj(blk) and type(blk.GetHeight) == "function" then
            local curBlkH = YRG.SafeNumber(blk:GetHeight(), 0)
            if math.abs(curBlkH - bRec.setH) < 0.4 and bRec.extra > 0 then
                local baseH = math.max(1, curBlkH - bRec.extra)
                pcall(blk.SetHeight, blk, baseH)
                if type(blk.height) == "number" then
                    blk.height = math.max(1, blk.height - bRec.extra)
                end
            end
        end
        xpTrackerState.blkAdj[blk] = nil
        return 0
    end

    local isComplete = showTurnInXP and IsQuestCompleteInLog(qid) or false
    local newTag = nil
    local tagComputed = false
    local objCount = #fsList
    local lineExtrasByObj = {}
    local blkNewExtra = 0

    local function EnsureLineFontStringRoom(fs, lineObj)
        if not lineObj or lineObj == blk or InCombatLockdown() then return nil end
        if type(fs.GetNumPoints) ~= "function" or fs:GetNumPoints() ~= 1 then return nil end
        if type(fs.GetWidth) ~= "function" or type(fs.SetWidth) ~= "function" then return nil end
        local fsLeft = YRG.SafeOptionalNumber(fs.GetLeft and fs:GetLeft())
        local lineRight = YRG.SafeOptionalNumber(lineObj.GetRight and lineObj:GetRight())
        if not (fsLeft and lineRight) then return nil end
        local curW = YRG.SafeNumber(fs:GetWidth(), 0)
        local availW = math.floor(lineRight - fsLeft - 2)
        if curW > 0 and availW > (curW + 16) then
            pcall(fs.SetWidth, fs, availW)
            return curW, availW
        end
        return nil
    end

    local function RestoreFS(fs, curTxt, rec)
        if rec then
            if curTxt == rec.lastFullText then
                pcall(fs.SetText, fs, rec.baseText)
            end
            if rec.origW and rec.adjW and not InCombatLockdown() and type(fs.GetWidth) == "function" then
                if math.abs(YRG.SafeNumber(fs:GetWidth(), 0) - rec.adjW) < 1 then
                    pcall(fs.SetWidth, fs, rec.origW)
                end
            end
        end
        xpTrackerState.appliedFS[fs] = nil
    end

    for _, fs in ipairs(fsList) do
        local lineObj = (type(fs.GetParent) == "function" and fs:GetParent()) or nil
        if lineObj == blk then lineObj = nil end
        local curTxt = YRG.SafeString(fs:GetText(), nil)
        if curTxt and curTxt ~= "" then
            local rec = xpTrackerState.appliedFS[fs]
            local isSameApplied = (rec and curTxt == rec.lastFullText)
            local baseText = isSameApplied and rec.baseText or curTxt
            local textExtraH = 0

            if showTurnInXP then
                local plain = StripWowTextFormatting(baseText)
                local matches, explicit = IsTurnInObjectiveText(plain, isComplete, objCount)
                if matches and (isComplete or explicit) then
                    if not tagComputed then
                        tagComputed = true
                        newTag = GetQuestTurnInXPBracketText(qid)
                    end
                    if newTag then
                        local fullText = baseText .. newTag
                        local origW, adjW = rec and rec.origW or nil, rec and rec.adjW or nil
                        local baseStrH
                        if isSameApplied then
                            baseStrH = rec.baseStrH
                        else
                            baseStrH = YRG.SafeNumber(fs.GetStringHeight and fs:GetStringHeight(), 0)
                            local newOrigW, newAdjW = EnsureLineFontStringRoom(fs, lineObj)
                            if newOrigW then
                                origW, adjW = newOrigW, newAdjW
                            end
                        end
                        if curTxt ~= fullText then
                            pcall(fs.SetText, fs, fullText)
                            local newStrH = YRG.SafeNumber(fs.GetStringHeight and fs:GetStringHeight(), baseStrH)
                            textExtraH = math.max(0, newStrH - baseStrH)
                            if textExtraH < 1 then textExtraH = 0 end
                        else
                            textExtraH = rec and rec.extraH or 0
                        end
                        xpTrackerState.appliedFS[fs] = {
                            baseText = baseText,
                            lastFullText = fullText,
                            tag = newTag,
                            baseStrH = baseStrH,
                            extraH = textExtraH,
                            origW = origW,
                            adjW = adjW,
                        }
                    else
                        RestoreFS(fs, curTxt, rec)
                    end
                else
                    RestoreFS(fs, curTxt, rec)
                end
            else
                RestoreFS(fs, curTxt, rec)
            end

            if lineObj and textExtraH > 0 then
                lineExtrasByObj[lineObj] = (lineExtrasByObj[lineObj] or 0) + textExtraH
            end
            blkNewExtra = blkNewExtra + textExtraH
        end
    end

    local lineAdjList = {}
    for _, fs in ipairs(fsList) do
        local lineObj = (type(fs.GetParent) == "function" and fs:GetParent()) or nil
        if lineObj and lineObj ~= blk and not lineAdjList[lineObj] then
            lineAdjList[lineObj] = true
            local newLineExtra = lineExtrasByObj[lineObj] or 0
            local lRec = xpTrackerState.lineAdj[lineObj]
            local curLineH = YRG.SafeNumber(lineObj.GetHeight and lineObj:GetHeight(), 0)
            local prevLineExtra = (lRec and math.abs(curLineH - lRec.setH) < 0.4) and lRec.extra or 0
            local lineDelta = newLineExtra - prevLineExtra
            if math.abs(lineDelta) >= 0.4 then
                if CanSafelyResizeTrackerObj(lineObj) and curLineH > 0 then
                    local baseLineH = curLineH - prevLineExtra
                    local targetLineH = math.max(1, baseLineH + newLineExtra)
                    pcall(lineObj.SetHeight, lineObj, targetLineH)
                    if type(lineObj.height) == "number" then
                        lineObj.height = math.max(1, (lineObj.height - prevLineExtra) + newLineExtra)
                    end
                    local lineBottom = YRG.SafeOptionalNumber(lineObj.GetBottom and lineObj:GetBottom())
                    if lineBottom and type(blk.GetChildren) == "function" then
                        for _, ch in ipairs({ blk:GetChildren() }) do
                            if ch ~= lineObj and (type(ch.IsShown) ~= "function" or ch:IsShown()) then
                                local chTop = YRG.SafeOptionalNumber(ch.GetTop and ch:GetTop())
                                if chTop and chTop < (lineBottom + 2) then
                                    ShiftPointsRelativeToParent(ch, blk, nil, lineDelta)
                                end
                            end
                        end
                    end
                    xpTrackerState.lineAdj[lineObj] = (newLineExtra > 0) and {
                        extra = newLineExtra,
                        setH = YRG.SafeNumber(lineObj:GetHeight(), targetLineH),
                    } or nil
                elseif InCombatLockdown() then
                    pendingCombatUpdate = true
                end
            end
        end
    end

    local bRec = xpTrackerState.blkAdj[blk]
    local curBlkH = YRG.SafeNumber(blk.GetHeight and blk:GetHeight(), 0)
    local prevBlkExtra = (bRec and math.abs(curBlkH - bRec.setH) < 0.4) and bRec.extra or 0
    local blkDelta = blkNewExtra - prevBlkExtra
    if math.abs(blkDelta) >= 0.4 then
        if CanSafelyResizeTrackerObj(blk) and curBlkH > 0 then
            local baseBlkH = curBlkH - prevBlkExtra
            local targetBlkH = math.max(1, baseBlkH + blkNewExtra)
            pcall(blk.SetHeight, blk, targetBlkH)
            if type(blk.height) == "number" then
                blk.height = math.max(1, (blk.height - prevBlkExtra) + blkNewExtra)
            end
            xpTrackerState.blkAdj[blk] = (blkNewExtra > 0) and {
                extra = blkNewExtra,
                setH = YRG.SafeNumber(blk:GetHeight(), targetBlkH),
            } or nil
        elseif InCombatLockdown() then
            pendingCombatUpdate = true
        end
    end

    return blkNewExtra
end

local function ReflowModuleAfterVisualChanges(mod, contents, modBlocks, blkNewExtraMap)
    if InCombatLockdown() then
        for _, extra in pairs(blkNewExtraMap) do
            if extra > 0 then
                pendingCombatUpdate = true
                break
            end
        end
        return 0
    end

    table.sort(modBlocks, function(a, b)
        local topA = YRG.SafeNumber(a.GetTop and a:GetTop(), 0)
        local topB = YRG.SafeNumber(b.GetTop and b:GetTop(), 0)
        if math.abs(topA - topB) > 0.4 then
            return topA > topB
        end
        return false
    end)

    local accAboveExtra = 0
    for _, blk in ipairs(modBlocks) do
        local okPt, _, relTo, _, _, y = pcall(blk.GetPoint, blk, 1)
        if okPt and (relTo == contents or relTo == mod) and type(y) == "number" then
            local sRec = xpTrackerState.blkShift[blk]
            local prevShift = (sRec and math.abs(y - sRec.setY) < 0.4) and sRec.extraShift or 0
            local shiftDelta = accAboveExtra - prevShift
            if math.abs(shiftDelta) >= 0.4 and CanSafelyResizeTrackerObj(blk) then
                if ShiftPointsRelativeToParent(blk, contents, mod, shiftDelta) then
                    local okNew, _, _, _, _, newY = pcall(blk.GetPoint, blk, 1)
                    xpTrackerState.blkShift[blk] = (accAboveExtra > 0 and okNew and type(newY) == "number") and {
                        extraShift = accAboveExtra,
                        setY = newY,
                    } or nil
                end
            elseif accAboveExtra == 0 then
                xpTrackerState.blkShift[blk] = nil
            end
        else
            xpTrackerState.blkShift[blk] = nil
        end
        accAboveExtra = accAboveExtra + (blkNewExtraMap[blk] or 0)
    end

    local modNewExtra = accAboveExtra
    local mRec = xpTrackerState.modAdj[mod]
    local curContH = YRG.SafeNumber(contents.GetHeight and contents:GetHeight(), 0)
    local prevModExtra = (mRec and math.abs(curContH - mRec.setContH) < 0.4) and mRec.extra or 0
    local modDelta = modNewExtra - prevModExtra
    if math.abs(modDelta) >= 0.4 and CanSafelyResizeTrackerObj(contents) and curContH > 0 then
        local targetContH = math.max(1, (curContH - prevModExtra) + modNewExtra)
        pcall(contents.SetHeight, contents, targetContH)
        local targetModH = targetContH
        if mod ~= contents and CanSafelyResizeTrackerObj(mod) and type(mod.GetHeight) == "function" then
            local curModH = YRG.SafeNumber(mod:GetHeight(), 0)
            if curModH > 0 then
                targetModH = math.max(1, (curModH - prevModExtra) + modNewExtra)
                pcall(mod.SetHeight, mod, targetModH)
            end
        end
        xpTrackerState.modAdj[mod] = (modNewExtra > 0) and {
            extra = modNewExtra,
            setContH = YRG.SafeNumber(contents:GetHeight(), targetContH),
            setModH = (mod ~= contents and mod.GetHeight) and YRG.SafeNumber(mod:GetHeight(), targetModH) or targetContH,
        } or nil
    elseif modNewExtra == 0 then
        xpTrackerState.modAdj[mod] = nil
    end
    return modNewExtra
end

local function UpdateBlizzardTrackerVisuals(markEnabled, showTurnInXP)
    local tracker = _G["ObjectiveTrackerFrame"] or _G["WatchFrame"]
    if not tracker or not tracker:IsShown() then return end

    local prefix = markEnabled and GetChainIconPrefix(12) or nil
    local function StripIcon(txt)
        return txt:gsub("|TInterface\\AddOns\\YRG\\Textures\\QuestChainIcon:%d+:%d+:[^|]*|t%s*", "")
    end

    local seenBlks = {}
    for _, mod in ipairs(GetQuestTrackerModules(tracker)) do
        if mod and mod:IsShown() then
            local contents = mod.ContentsFrame or mod
            local modBlocks = {}
            local blkNewExtraMap = {}
            local function UpdateBlk(blk)
                if type(blk) ~= "table" or seenBlks[blk] then
                    return
                end
                if type(blk.IsForbidden) == "function" and blk:IsForbidden() then
                    return
                end
                if type(blk.IsShown) == "function" and not blk:IsShown() then
                    return
                end
                local qid = (type(blk.questID) == "number" and blk.questID)
                    or (type(blk.id) == "number" and blk.id)
                    or nil
                if not qid or qid <= 0 then
                    return
                end
                seenBlks[blk] = true
                modBlocks[#modBlocks + 1] = blk

                if blk.HeaderText and type(blk.HeaderText.GetText) == "function" then
                    local curTxt = YRG.SafeString(blk.HeaderText:GetText(), nil)
                    if curTxt and curTxt ~= "" then
                        local hasIcon = curTxt:find(TEX_QUEST_CHAIN, 1, true) ~= nil
                        local wantIcon = markEnabled and IsQuestRequiredForChain(qid)
                        if wantIcon and not hasIcon then
                            pcall(blk.HeaderText.SetText, blk.HeaderText, prefix .. curTxt)
                        elseif (not wantIcon) and hasIcon then
                            pcall(blk.HeaderText.SetText, blk.HeaderText, StripIcon(curTxt))
                        end
                    end
                end

                blkNewExtraMap[blk] = ApplyTurnInXpToBlock(blk, qid, showTurnInXP)
            end

            if type(mod.usedBlocks) == "table" then
                for _, v in pairs(mod.usedBlocks) do
                    if type(v) == "table" then
                        if v.HeaderText or v.usedLines or v.lines or v.id ~= nil or v.questID ~= nil then
                            UpdateBlk(v)
                        else
                            for _, blk in pairs(v) do
                                UpdateBlk(blk)
                            end
                        end
                    end
                end
            end
            if contents and type(contents.GetChildren) == "function" then
                for _, ch in ipairs({ contents:GetChildren() }) do
                    UpdateBlk(ch)
                end
            end

            if #modBlocks > 0 then
                ReflowModuleAfterVisualChanges(mod, contents, modBlocks, blkNewExtraMap)
            end
        end
    end
end

function QuestTracker:ApplyOverrides()
    if applyingOverride or suppressNativeHooks then return end
    local db = YRG:GetModuleDB("QuestTrackerUpdater")
    if not db or not db.enabled then
        UpdateBlizzardTrackerVisuals(false, false)
        if self._statusText then
            self:UpdateStatusText()
        end
        return
    end

    local mode = GetNormalizedSortMode(db)
    if not IsQuestieTrackerActive() then
        UpdateBlizzardTrackerVisuals(db.markChainQuests ~= false, db.showTurnInXPPercent ~= false)
        if mode ~= "NONE" then
            applyingOverride = true
            ApplyBlizzardSortOverride(db)
            applyingOverride = false
        end
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
    if db.markChainQuests == nil then
        db.markChainQuests = true
    end
    if db.chainQuestTooltip == nil then
        db.chainQuestTooltip = true
    end
    if db.showTurnInXPPercent == nil then
        db.showTurnInXPPercent = true
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
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "PLAYER_LEVEL_UP")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "QUEST_TURNED_IN")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "QUEST_ACCEPTED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "QUEST_REMOVED")
    pcall(self.eventFrame.RegisterEvent, self.eventFrame, "QUEST_WATCH_LIST_CHANGED")

    self.eventFrame:SetScript("OnEvent", function(_, event)
        InstallQuestieHooks()
        InstallBlizzardHooks()
        if event == "PLAYER_LEVEL_UP" then
            wipe(xpTrackerState.questXP)
            xpTrackerState.maxXP = nil
            xpTrackerState.playerLevel = nil
            self:TriggerFullTrackerRefresh()
        elseif event == "QUEST_TURNED_IN" or event == "QUEST_ACCEPTED"
            or event == "QUEST_REMOVED" or event == "QUEST_WATCH_LIST_CHANGED" then
            wipe(chainStatusCache)
            wipe(xpTrackerState.questXP)
            ScheduleReverseChainScan()
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:SyncAutoTrackSettings()
            ScheduleReverseChainScan()
            if pendingCombatUpdate then
                pendingCombatUpdate = false
                self:ScheduleOverridePass()
            end
        elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            self:SyncAutoTrackSettings()
            ScheduleReverseChainScan()
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0.5, function()
                    InstallQuestieHooks()
                    InstallBlizzardHooks()
                    ScheduleReverseChainScan()
                    self:ScheduleOverridePass()
                end)
            else
                self:ScheduleOverridePass()
            end
        end
    end)

    self.xpAuraFrame = CreateFrame("Frame")
    self.xpAuraFrame:SetScript("OnEvent", function()
        local modDB = YRG:GetModuleDB("QuestTrackerUpdater")
        if not modDB or not modDB.enabled or modDB.showTurnInXPPercent == false then return end
        wipe(xpTrackerState.questXP)
        if IsQuestieTrackerActive() then
            if not InCombatLockdown() and not xpTrackerState.auraRefreshPending
                and C_Timer and type(C_Timer.After) == "function" then
                xpTrackerState.auraRefreshPending = true
                C_Timer.After(0.25, function()
                    xpTrackerState.auraRefreshPending = false
                    local dbNow = YRG:GetModuleDB("QuestTrackerUpdater")
                    if dbNow and dbNow.enabled and dbNow.showTurnInXPPercent ~= false and IsQuestieTrackerActive() then
                        self:TriggerFullTrackerRefresh()
                    end
                end)
            end
        else
            self:ScheduleOverridePass()
        end
    end)

    InstallQuestieHooks()
    InstallBlizzardHooks()
end

function QuestTracker:OnEnable(db)
    InstallQuestieHooks()
    InstallBlizzardHooks()
    ScheduleReverseChainScan()
    if self.xpAuraFrame then
        pcall(self.xpAuraFrame.RegisterUnitEvent, self.xpAuraFrame, "UNIT_AURA", "player")
    end
    self:SyncAutoTrackSettings()
    self:UpdateAutoAcceptEvents()
    self:TriggerFullTrackerRefresh()
    self:UpdateStatusText()
end

function QuestTracker:OnDisable(db)
    HideChainTooltip()
    if self.xpAuraFrame then
        self.xpAuraFrame:UnregisterAllEvents()
    end
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

    ctx:AddHeader(
        "3. Questie Chain & XP Indicators",
        "Uses Questie quest data to flag prerequisite chain quests and show estimated turn-in XP percentages in the tracker."
    )

    ctx:AddCheckbox({
        key = "markChainQuests",
        name = "Mark Required Chain Quests in Tracker",
        tooltip = "Requires Questie. Shows a chain link icon to the left of quest names in the tracker when the quest unlocks follow-up quests, helping prevent accidentally dropping out-leveled prerequisites.",
        defaultValue = true,
        notifies = { "YRG_QuestTrackerUpdater_chainQuestTooltip" },
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.markChainQuests ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.markChainQuests = val and true or false
            end
            if val then
                ScheduleReverseChainScan()
            else
                HideChainTooltip()
            end
            self:TriggerFullTrackerRefresh()
        end,
    })

    ctx:AddCheckbox({
        key = "chainQuestTooltip",
        name = "Show Follow-Up Quests on Tracker Hover",
        tooltip = "When hovering a chain quest in the tracker, displays a small tooltip listing which follow-up quest(s) it leads into.",
        defaultValue = true,
        canModify = function()
            local mdb = GetDB()
            return mdb == nil or mdb.markChainQuests ~= false
        end,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.chainQuestTooltip ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.chainQuestTooltip = val and true or false
            end
            if not val then
                HideChainTooltip()
            end
        end,
    })

    ctx:AddCheckbox({
        key = "showTurnInXPPercent",
        name = "Show Estimated Turn-In XP %",
        tooltip = "Requires Questie. Appends the estimated XP % (e.g. [12.5%]) in brackets beside 'Ready for Turn-in' on completed quests.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showTurnInXPPercent ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.showTurnInXPPercent = val and true or false
            end
            self:TriggerFullTrackerRefresh()
        end,
    })
end

YRG:RegisterModule("QuestTrackerUpdater", QuestTracker)
