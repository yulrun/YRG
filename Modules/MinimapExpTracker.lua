local _, YRG = ...

local TEX_RING       = "Interface\\AddOns\\YRG\\Textures\\MinimapFrameRing"
local TEX_FILL       = "Interface\\AddOns\\YRG\\Textures\\MinimapExpFill"
local TEX_MASK       = "Interface\\AddOns\\YRG\\Textures\\RadialHalfMask"
local TEX_HEADER_BOX = "Interface\\AddOns\\YRG\\Textures\\MinimapHeaderNineSlice"

local FILL_TEXTURES = {
    default = "Interface\\AddOns\\YRG\\Textures\\MinimapExpFill",
    crystal = "Interface\\AddOns\\YRG\\Textures\\MinimapExpFill_Crystal",
    conduit = "Interface\\AddOns\\YRG\\Textures\\MinimapExpFill_Conduit",
    runic   = "Interface\\AddOns\\YRG\\Textures\\MinimapExpFill_Runic",
    flat    = "Interface\\AddOns\\YRG\\Textures\\MinimapExpFill_Flat",
}

local FILL_TEXTURE_OPTIONS = {
    { value = "conduit", label = "Conduit Core (Default)" },
    { value = "default", label = "Classic Gloss" },
    { value = "crystal", label = "Faceted Crystal" },
    { value = "runic",   label = "Arcane Runeweave" },
    { value = "flat",    label = "Flat Matte Modern" },
}

local BUBBLE_OVERLAY_TEXTURES = {
    simple = "Interface\\AddOns\\YRG\\Textures\\MinimapExpOverlay_Simple",
    glass  = "Interface\\AddOns\\YRG\\Textures\\MinimapExpOverlay_Glass",
    bevel  = "Interface\\AddOns\\YRG\\Textures\\MinimapExpOverlay_Bevel",
    glow   = "Interface\\AddOns\\YRG\\Textures\\MinimapExpOverlay_Pins",
}

local BUBBLE_OVERLAY_OPTIONS = {
    { value = "bevel",  label = "Brass Frame Clasps (Default)" },
    { value = "simple", label = "Simple Notches (20 Bubbles)" },
    { value = "glass",  label = "Glass Capsules (Gloss)" },
    { value = "glow",   label = "Luminous Pips" },
    { value = "none",   label = "None" },
}

local COLOR_SCHEMES = {
    blue   = { exp = { r = 0.25, g = 0.72, b = 1.00, a = 1.0 }, rested = { r = 0.08, g = 0.28, b = 0.62, a = 0.92 } },
    gold   = { exp = { r = 1.00, g = 0.84, b = 0.22, a = 1.0 }, rested = { r = 0.56, g = 0.36, b = 0.04, a = 0.92 } },
    purple = { exp = { r = 0.78, g = 0.42, b = 1.00, a = 1.0 }, rested = { r = 0.34, g = 0.12, b = 0.56, a = 0.92 } },
    green  = { exp = { r = 0.28, g = 0.95, b = 0.42, a = 1.0 }, rested = { r = 0.07, g = 0.42, b = 0.16, a = 0.92 } },
    red    = { exp = { r = 1.00, g = 0.28, b = 0.28, a = 1.0 }, rested = { r = 0.52, g = 0.07, b = 0.09, a = 0.92 } },
}

local COLOR_SCHEME_OPTIONS = {
    { value = "blue",   label = "Blue (Default)" },
    { value = "gold",   label = "Gold" },
    { value = "purple", label = "Purple" },
    { value = "green",  label = "Green" },
    { value = "red",    label = "Red" },
}

local ROW1_LEFT_OPTIONS = {
    { value = "coords", label = "Coordinates (Default)" },
    { value = "gold",   label = "Current Gold" },
    { value = "none",   label = "None (Hidden)" },
}

local function GetRow1LeftMode(db)
    if not db then return "coords" end
    if db.row1LeftMode == "coords" or db.row1LeftMode == "gold" or db.row1LeftMode == "none" then
        return db.row1LeftMode
    end
    if db.showCoordinates == false then
        return "none"
    end
    return "coords"
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

local ExpTracker = {
    name = "Minimap EXP Tracker",
    description = "Radial EXP & Rested ring with a bottom-fixed EXP badge and a dynamic session info placard.",
    defaultEnabled = true,
    defaults = {
        enabled = true,
        masterScale = 1.0,
        fillStyle = "conduit",
        bubbleOverlay = "bevel",
        bubbleOverlayOpacityPct = 85,
        colorScheme = "blue",
        showRestedBar = true,
        hideAtMaxLevel = false,
        hideDefaultExpBar = false,
        alwaysShowLocalTime = true,
        hideAddonButtons = true,
        centerMinimapHeader = true,
        matchPlacardWidth = false,

        -- Placard 1: Bottom-Fixed EXP Percentage Placard (always visible)
        showDecimals = false,
        expTextSize = 14,

        -- Placard 2: Dynamic Session & Map Info Placard
        showInfoPlacard = true,
        followMapOrientation = true,
        infoPlacardOffsetY = 0,
        infoPlacardWidth = 200,
        rowDividerOpacityPct = 60,
        rowExtraPadding = 4,
        row1LeftMode = "coords",
        showBagSlots = true,
        showArrowsRemaining = true,
        showSoulShards = true,
        showFarmingRow = true,
        bagWarnThreshold = 3,
        ammoWarnThreshold = 200,
        bagRaidWarnings = false,
        cellPadding = 10,
        row1TextSize = 12,
        row2TextSize = 12,
    }
}

local sessionKillsData = {}
local sessionStartTime = 0

local ICON_SKULL  = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local ICON_WATCH  = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local ICON_MAP    = "Interface\\Icons\\INV_Misc_Map_01"
local ICON_BAG    = "Interface\\Icons\\INV_Misc_Bag_08"
local ICON_ARROW  = 132382 -- INV_Ammo_Arrow_01
local ICON_BULLET = 132384 -- INV_Ammo_Bullet_01
local ICON_SHARD  = 134075 -- INV_Misc_Gem_Amethyst_02
local SOUL_SHARD_ITEM_ID = 6265

local QUAD_INFO = {
    [1] = { point = "BOTTOMLEFT",  u1 = 0.0, u2 = 0.5, v1 = 0.5, v2 = 1.0 },
    [2] = { point = "TOPLEFT",     u1 = 0.0, u2 = 0.5, v1 = 0.0, v2 = 0.5 },
    [3] = { point = "TOPRIGHT",    u1 = 0.5, u2 = 1.0, v1 = 0.0, v2 = 0.5 },
    [4] = { point = "BOTTOMRIGHT", u1 = 0.5, u2 = 1.0, v1 = 0.5, v2 = 1.0 },
}

-- =========================================================================
-- MINIMAP HEADER 9-SLICE CLONER (1px-STRIP CENTER SPLIT) & SHARED BG OPACITY
-- =========================================================================
local function GetMinimapHeaderBorderSources()
    local sources = {}
    if MinimapCluster then
        if MinimapCluster.BorderTop then
            if MinimapCluster.BorderTop.NineSlice then
                table.insert(sources, MinimapCluster.BorderTop.NineSlice)
            end
            table.insert(sources, MinimapCluster.BorderTop)
        end
        if MinimapCluster.ZoneTextButton and MinimapCluster.ZoneTextButton.StateTexture then
            table.insert(sources, MinimapCluster.ZoneTextButton.StateTexture)
        end
        if MinimapCluster.HeaderFrame then
            if MinimapCluster.HeaderFrame.Border then
                table.insert(sources, MinimapCluster.HeaderFrame.Border)
            end
            table.insert(sources, MinimapCluster.HeaderFrame)
        end
    end
    if _G["MinimapBorderTop"] then
        table.insert(sources, _G["MinimapBorderTop"])
    end
    return sources
end

local function EnsureNineSlicePieces(frame)
    if frame._yrgCustomNineSlice then
        return frame._yrgCustomNineSlice
    end
    local function MakePiece(layer, sub)
        return frame:CreateTexture(nil, layer, nil, sub)
    end
    local ns = {
        TL = MakePiece("BORDER", 2),
        TR = MakePiece("BORDER", 2),
        BL = MakePiece("BORDER", 2),
        BR = MakePiece("BORDER", 2),
        T  = MakePiece("BORDER", 1),
        B  = MakePiece("BORDER", 1),
        L  = MakePiece("BORDER", 1),
        R  = MakePiece("BORDER", 1),
        C  = MakePiece("BACKGROUND", 0),
    }

    ns.TL:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    ns.TR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    ns.BL:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    ns.BR:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    ns.T:SetPoint("TOPLEFT", ns.TL, "TOPRIGHT", 0, 0)
    ns.T:SetPoint("BOTTOMRIGHT", ns.TR, "BOTTOMLEFT", 0, 0)

    ns.B:SetPoint("TOPLEFT", ns.BL, "TOPRIGHT", 0, 0)
    ns.B:SetPoint("BOTTOMRIGHT", ns.BR, "BOTTOMLEFT", 0, 0)

    ns.L:SetPoint("TOPLEFT", ns.TL, "BOTTOMLEFT", 0, 0)
    ns.L:SetPoint("BOTTOMRIGHT", ns.BL, "TOPRIGHT", 0, 0)

    ns.R:SetPoint("TOPLEFT", ns.TR, "BOTTOMLEFT", 0, 0)
    ns.R:SetPoint("BOTTOMRIGHT", ns.BR, "TOPRIGHT", 0, 0)

    ns.C:SetPoint("TOPLEFT", ns.TL, "BOTTOMRIGHT", 0, 0)
    ns.C:SetPoint("BOTTOMRIGHT", ns.BR, "TOPLEFT", 0, 0)

    frame._yrgCustomNineSlice = ns
    return ns
end

local function GetTextureMediaInfo(srcTex, isRegionScan)
    if not srcTex then return nil end
    local isTex = false
    pcall(function()
        if srcTex.IsObjectType then
            isTex = srcTex:IsObjectType("Texture")
        elseif srcTex.GetObjectType then
            isTex = (srcTex:GetObjectType() == "Texture")
        end
    end)
    if not isTex then return nil end

    if srcTex.IsShown and not srcTex:IsShown() then
        return nil
    end

    if isRegionScan then
        if srcTex.GetDrawLayer then
            local okL, layer = pcall(srcTex.GetDrawLayer, srcTex)
            if okL and layer == "HIGHLIGHT" then
                return nil
            end
        end
        local alpha = YRG.SafeNumber(srcTex.GetAlpha and srcTex:GetAlpha(), 1)
        if alpha <= 0.05 then
            return nil
        end
    end

    local atlas = srcTex.GetAtlas and srcTex:GetAtlas() or nil
    local tex = srcTex.GetTexture and srcTex:GetTexture() or nil
    local atlasInfo = (atlas and atlas ~= "" and C_Texture and C_Texture.GetAtlasInfo) and C_Texture.GetAtlasInfo(atlas) or nil
    if (not atlasInfo or not atlasInfo.file) and (not tex or tex == "") and (not atlas or atlas == "") then
        return nil
    end

    local rawW = YRG.SafeNumber(srcTex.GetWidth and srcTex:GetWidth(), 0)
    local rawH = YRG.SafeNumber(srcTex.GetHeight and srcTex:GetHeight(), 0)
    if rawW <= 0 or rawH <= 0 then
        return nil
    end

    local ulx, uly, llx, lly, urx, ury, lrx, lry = 0, 0, 0, 1, 1, 0, 1, 1
    if srcTex.GetTexCoord then
        local ok, a1, a2, a3, a4, a5, a6, a7, a8 = pcall(srcTex.GetTexCoord, srcTex)
        if ok and type(a1) == "number" and type(a8) == "number" then
            ulx, uly, llx, lly, urx, ury, lrx, lry = a1, a2, a3, a4, a5, a6, a7, a8
        elseif ok and type(a1) == "number" and type(a4) == "number" then
            ulx, uly, llx, lly, urx, ury, lrx, lry = a1, a3, a1, a4, a2, a3, a2, a4
        end
    end

    local isRotated = (math.abs(uly - ury) > 1e-4) or (math.abs(ulx - llx) > 1e-4)
    if not isRotated and atlasInfo and atlasInfo.leftTexCoord and atlasInfo.rightTexCoord
        and atlasInfo.topTexCoord and atlasInfo.bottomTexCoord then
        ulx = atlasInfo.leftTexCoord
        llx = atlasInfo.leftTexCoord
        urx = atlasInfo.rightTexCoord
        lrx = atlasInfo.rightTexCoord
        uly = atlasInfo.topTexCoord
        ury = atlasInfo.topTexCoord
        lly = atlasInfo.bottomTexCoord
        lry = atlasInfo.bottomTexCoord
    end

    local vr, vg, vb, va = 1, 1, 1, 1
    if srcTex.GetVertexColor then
        local ok, r, g, b, a = pcall(srcTex.GetVertexColor, srcTex)
        if ok and type(r) == "number" then
            vr, vg, vb = r, g, b
            va = (type(a) == "number" and a > 0.05) and a or 1
        end
    end

    local leftPos = YRG.SafeNumber(srcTex.GetLeft and srcTex:GetLeft(), 0)

    return {
        srcTex = srcTex,
        atlas = (atlas and atlas ~= "") and atlas or nil,
        tex = tex,
        atlasInfo = atlasInfo,
        rawW = rawW,
        rawH = rawH,
        leftPos = leftPos,
        uv = { ulx, uly, llx, lly, urx, ury, lrx, lry },
        color = { vr, vg, vb, va },
    }
end

local function ApplySubUVToPiece(piece, mediaInfo, u0, u1, v0, v1, extraAlpha)
    if piece.SetTextureSliceMargins then
        pcall(piece.SetTextureSliceMargins, piece, 0, 0, 0, 0)
    end

    if mediaInfo.atlasInfo and mediaInfo.atlasInfo.file then
        piece:SetTexture(mediaInfo.atlasInfo.file)
    elseif mediaInfo.tex and mediaInfo.tex ~= "" then
        piece:SetTexture(mediaInfo.tex)
    elseif mediaInfo.atlas then
        piece:SetAtlas(mediaInfo.atlas, false)
    end

    local c = mediaInfo.uv
    local ulx, uly, llx, lly, urx, ury, lrx, lry = c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8]
    local function SampleUV(u, v)
        local tx = ulx + (urx - ulx) * u
        local ty = uly + (ury - uly) * u
        local bx = llx + (lrx - llx) * u
        local by = lly + (lry - lly) * u
        return tx + (bx - tx) * v, ty + (by - ty) * v
    end

    local p_ulx, p_uly = SampleUV(u0, v0)
    local p_llx, p_lly = SampleUV(u0, v1)
    local p_urx, p_ury = SampleUV(u1, v0)
    local p_lrx, p_lry = SampleUV(u1, v1)

    piece:SetHorizTile(false)
    piece:SetVertTile(false)
    piece:SetTexCoord(p_ulx, p_uly, p_llx, p_lly, p_urx, p_ury, p_lrx, p_lry)
    if piece.SetSnapToPixelGrid then
        pcall(piece.SetSnapToPixelGrid, piece, false)
    end
    if piece.SetTexelSnappingBias then
        pcall(piece.SetTexelSnappingBias, piece, 0)
    end
    local col = mediaInfo.color
    piece:SetVertexColor(col[1], col[2], col[3], (col[4] or 1) * (extraAlpha or 1))
    piece:Show()
end

local function SetCornerSizes(ns, cL, cR, cTopH, cBotH)
    ns.TL:SetSize(cL, cTopH)
    ns.TR:SetSize(cR, cTopH)
    ns.BL:SetSize(cL, cBotH)
    ns.BR:SetSize(cR, cBotH)
    ns.T:SetHeight(cTopH)
    ns.B:SetHeight(cBotH)
    ns.L:SetWidth(cL)
    ns.R:SetWidth(cR)
end

local function ValidAtlasDim(val, fallback)
    if type(val) == "number" and val > 4 then
        return val
    end
    return fallback
end

local function ConfigureNativeNineSlice(frame, ns, src)
    if not src then return false end

    local dstEffScale = YRG.SafeNumber(frame.GetEffectiveScale and frame:GetEffectiveScale(), 1)
    local srcParent = (src.GetParent and src:GetParent()) or nil
    local rawSrcScale = (src.GetEffectiveScale and src:GetEffectiveScale())
        or (srcParent and srcParent.GetEffectiveScale and srcParent:GetEffectiveScale())
    local srcEffScale = YRG.SafeNumber(rawSrcScale, dstEffScale)
    if dstEffScale <= 0 then dstEffScale = 1 end
    if srcEffScale <= 0 then srcEffScale = dstEffScale end
    local relScale = srcEffScale / dstEffScale

    -- Path 1: Blizzard NineSlice frame with 4 explicit corners
    if type(src) == "table" and src.TopLeftCorner and src.TopRightCorner and src.BottomLeftCorner and src.BottomRightCorner then
        local tlInfo = GetTextureMediaInfo(src.TopLeftCorner, false)
        local trInfo = GetTextureMediaInfo(src.TopRightCorner, false)
        local blInfo = GetTextureMediaInfo(src.BottomLeftCorner, false)
        local brInfo = GetTextureMediaInfo(src.BottomRightCorner, false)
        local tInfo  = GetTextureMediaInfo(src.TopEdge, false)
        local bInfo  = GetTextureMediaInfo(src.BottomEdge, false)
        local lInfo  = GetTextureMediaInfo(src.LeftEdge, false)
        local rInfo  = GetTextureMediaInfo(src.RightEdge, false)
        local cInfo  = GetTextureMediaInfo(src.Center, false)

        if tlInfo and trInfo and blInfo and brInfo and tInfo and bInfo and lInfo and rInfo then
            local cL = math.max(2, tlInfo.rawW * relScale)
            local cR = math.max(2, trInfo.rawW * relScale)
            local cTopH = math.max(2, tlInfo.rawH * relScale)
            local cBotH = math.max(2, blInfo.rawH * relScale)

            ApplySubUVToPiece(ns.TL, tlInfo, 0, 1, 0, 1)
            ApplySubUVToPiece(ns.TR, trInfo, 0, 1, 0, 1)
            ApplySubUVToPiece(ns.BL, blInfo, 0, 1, 0, 1)
            ApplySubUVToPiece(ns.BR, brInfo, 0, 1, 0, 1)

            local tW = ValidAtlasDim(tInfo.atlasInfo and tInfo.atlasInfo.width, math.max(8, math.floor(tInfo.rawW * relScale * 2 + 0.5)))
            local bW = ValidAtlasDim(bInfo.atlasInfo and bInfo.atlasInfo.width, math.max(8, math.floor(bInfo.rawW * relScale * 2 + 0.5)))
            local lH = ValidAtlasDim(lInfo.atlasInfo and lInfo.atlasInfo.height, math.max(8, math.floor(lInfo.rawH * relScale * 2 + 0.5)))
            local rH = ValidAtlasDim(rInfo.atlasInfo and rInfo.atlasInfo.height, math.max(8, math.floor(rInfo.rawH * relScale * 2 + 0.5)))

            local tu0 = (math.floor(tW * 0.5) + 0.25) / tW
            local tu1 = (math.floor(tW * 0.5) + 0.75) / tW
            local bu0 = (math.floor(bW * 0.5) + 0.25) / bW
            local bu1 = (math.floor(bW * 0.5) + 0.75) / bW
            local lv0 = (math.floor(lH * 0.5) + 0.25) / lH
            local lv1 = (math.floor(lH * 0.5) + 0.75) / lH
            local rv0 = (math.floor(rH * 0.5) + 0.25) / rH
            local rv1 = (math.floor(rH * 0.5) + 0.75) / rH

            ApplySubUVToPiece(ns.T, tInfo, tu0, tu1, 0, 1)
            ApplySubUVToPiece(ns.B, bInfo, bu0, bu1, 0, 1)
            ApplySubUVToPiece(ns.L, lInfo, 0, 1, lv0, lv1)
            ApplySubUVToPiece(ns.R, rInfo, 0, 1, rv0, rv1)

            if cInfo then
                local cW = ValidAtlasDim(cInfo.atlasInfo and cInfo.atlasInfo.width, math.max(8, math.floor(cInfo.rawW * relScale * 2 + 0.5)))
                local cH = ValidAtlasDim(cInfo.atlasInfo and cInfo.atlasInfo.height, math.max(8, math.floor(cInfo.rawH * relScale * 2 + 0.5)))
                local cu0 = (math.floor(cW * 0.5) + 0.25) / cW
                local cu1 = (math.floor(cW * 0.5) + 0.75) / cW
                local cv0 = (math.floor(cH * 0.5) + 0.25) / cH
                local cv1 = (math.floor(cH * 0.5) + 0.75) / cH
                ApplySubUVToPiece(ns.C, cInfo, cu0, cu1, cv0, cv1)
            else
                ns.C:Hide()
            end

            SetCornerSizes(ns, cL, cR, cTopH, cBotH)
            frame._yrgNineSliceMinW = math.ceil(cL + cR + 2)
            frame._yrgNineSliceMinH = math.ceil(cTopH + cBotH + 2)
            frame._yrgNineSliceSig = string.format("9s:%.2f:%.2f:%.2f:%.2f", cL, cR, cTopH, cBotH)
            return true
        end
    end

    -- Collect Texture region(s) from src (direct, regions, or 1-level child regions)
    local regions = {}
    local directInfo = GetTextureMediaInfo(src, false)
    if directInfo then
        regions[1] = directInfo
    else
        local function CollectFromFrame(f)
            if f and f.GetRegions then
                local ok, regs = pcall(function() return { f:GetRegions() } end)
                if ok and regs then
                    for _, reg in ipairs(regs) do
                        local mi = GetTextureMediaInfo(reg, true)
                        if mi then
                            table.insert(regions, mi)
                        end
                    end
                end
            end
        end
        CollectFromFrame(src)
        if #regions == 0 and src.GetChildren then
            local okC, children = pcall(function() return { src:GetChildren() } end)
            if okC and children then
                for _, ch in ipairs(children) do
                    CollectFromFrame(ch)
                end
            end
        end
    end

    if #regions == 0 then
        return false
    end

    -- Path 2: Horizontal 3-Slice (Left cap, Center strip, Right cap) split vertically around center 1px
    if #regions >= 3 and not (type(src) == "table" and (src.TopLeftCorner or src.BottomLeftCorner)) then
        local leftInfo = GetTextureMediaInfo(src.LeftEdge or src.Left or src.left, false)
        local centerInfo = GetTextureMediaInfo(src.Center or src.Middle or src.center, false)
        local rightInfo = GetTextureMediaInfo(src.RightEdge or src.Right or src.right, false)

        if not (leftInfo and centerInfo and rightInfo) and #regions == 3 then
            local sorted = { regions[1], regions[2], regions[3] }
            table.sort(sorted, function(a, b) return a.leftPos < b.leftPos end)
            if sorted[1].leftPos + 4 < sorted[3].leftPos then
                leftInfo, centerInfo, rightInfo = sorted[1], sorted[2], sorted[3]
            end
        end

        if leftInfo and centerInfo and rightInfo then
            local dispH = math.max(leftInfo.rawH, centerInfo.rawH, rightInfo.rawH) * relScale
            if dispH > 4 then
                local cL = math.max(2, leftInfo.rawW * relScale)
                local cR = math.max(2, rightInfo.rawW * relScale)
                local nTexH = ValidAtlasDim(centerInfo.atlasInfo and centerInfo.atlasInfo.height,
                    ValidAtlasDim(leftInfo.atlasInfo and leftInfo.atlasInfo.height, math.max(16, math.floor(dispH * 2 + 0.5))))
                local nTexW_C = ValidAtlasDim(centerInfo.atlasInfo and centerInfo.atlasInfo.width,
                    math.max(16, math.floor(centerInfo.rawW * relScale * 2 + 0.5)))

                local rowMid = math.floor(nTexH * 0.5)
                local colMid = math.floor(nTexW_C * 0.5)

                local vTopEnd = rowMid / nTexH
                local vMid0   = (rowMid + 0.25) / nTexH
                local vMid1   = (rowMid + 0.75) / nTexH
                local vBotBeg = (rowMid + 1) / nTexH

                local uMid0   = (colMid + 0.25) / nTexW_C
                local uMid1   = (colMid + 0.75) / nTexW_C

                local cTopH = math.max(2, dispH * (rowMid / nTexH))
                local cBotH = math.max(2, dispH * ((nTexH - rowMid - 1) / nTexH))

                ApplySubUVToPiece(ns.TL, leftInfo,   0, 1, 0, vTopEnd)
                ApplySubUVToPiece(ns.BL, leftInfo,   0, 1, vBotBeg, 1)
                ApplySubUVToPiece(ns.L,  leftInfo,   0, 1, vMid0, vMid1)

                ApplySubUVToPiece(ns.TR, rightInfo,  0, 1, 0, vTopEnd)
                ApplySubUVToPiece(ns.BR, rightInfo,  0, 1, vBotBeg, 1)
                ApplySubUVToPiece(ns.R,  rightInfo,  0, 1, vMid0, vMid1)

                ApplySubUVToPiece(ns.T,  centerInfo, uMid0, uMid1, 0, vTopEnd)
                ApplySubUVToPiece(ns.B,  centerInfo, uMid0, uMid1, vBotBeg, 1)
                ApplySubUVToPiece(ns.C,  centerInfo, uMid0, uMid1, vMid0, vMid1)

                SetCornerSizes(ns, cL, cR, cTopH, cBotH)
                frame._yrgNineSliceMinW = math.ceil(cL + cR + 2)
                frame._yrgNineSliceMinH = math.ceil(cTopH + cBotH + 2)
                frame._yrgNineSliceSig = string.format("3s:%.2f:%.2f:%.2f", cL, cR, dispH)
                return true
            end
        end
    end

    -- Path 3: Single unified Texture (3-slice or sliced atlas) split into corners + 1px strips + 1x1px center
    table.sort(regions, function(a, b)
        return (a.rawW * a.rawH) > (b.rawW * b.rawH)
    end)
    local main = regions[1]
    local dispW = main.rawW * relScale
    local dispH = main.rawH * relScale
    if dispH <= 4 or dispW <= 8 then
        return false
    end

    local nTexW = ValidAtlasDim(main.atlasInfo and main.atlasInfo.width, math.max(32, math.floor(dispW * 2 + 0.5)))
    local nTexH = ValidAtlasDim(main.atlasInfo and main.atlasInfo.height, math.max(16, math.floor(dispH * 2 + 0.5)))

    local lM, tM, rM, bM = 0, 0, 0, 0
    if main.srcTex.GetTextureSliceMargins then
        local ok, ml, mt, mr, mb = pcall(main.srcTex.GetTextureSliceMargins, main.srcTex)
        if ok and ml then
            lM, tM, rM, bM = YRG.SafeNumber(ml, 0), YRG.SafeNumber(mt, 0), YRG.SafeNumber(mr, 0), YRG.SafeNumber(mb, 0)
        end
    end

    local uiPerTexel = dispH / nTexH
    local colMid = math.floor(nTexW * 0.5)
    local rowMid = math.floor(nTexH * 0.5)

    local defaultCapTex = math.max(4, math.floor(math.min(nTexH * 0.55, (nTexW - 3) * 0.42)))
    local hasHMargins = (lM >= 4 and rM >= 4 and (lM + rM) < (nTexW - 4))
    local capLeftTex = hasHMargins and lM or defaultCapTex
    local capRightTex = hasHMargins and rM or defaultCapTex

    local hasVMargins = (tM >= 4 and bM >= 4 and (tM + bM) < (nTexH - 4))
    local topCutTex = hasVMargins and tM or rowMid
    local botCutTex = hasVMargins and bM or (nTexH - rowMid - 1)

    local uLeftEnd  = capLeftTex / nTexW
    local uMid0     = (colMid + 0.25) / nTexW
    local uMid1     = (colMid + 0.75) / nTexW
    local uRightBeg = (nTexW - capRightTex) / nTexW

    local vTopEnd   = topCutTex / nTexH
    local vMid0     = (rowMid + 0.25) / nTexH
    local vMid1     = (rowMid + 0.75) / nTexH
    local vBotBeg   = (nTexH - botCutTex) / nTexH

    local cL    = math.max(2, capLeftTex * uiPerTexel)
    local cR    = math.max(2, capRightTex * uiPerTexel)
    local cTopH = math.max(2, topCutTex * uiPerTexel)
    local cBotH = math.max(2, botCutTex * uiPerTexel)

    ApplySubUVToPiece(ns.TL, main, 0,         uLeftEnd,  0,       vTopEnd)
    ApplySubUVToPiece(ns.TR, main, uRightBeg, 1,         0,       vTopEnd)
    ApplySubUVToPiece(ns.BL, main, 0,         uLeftEnd,  vBotBeg, 1)
    ApplySubUVToPiece(ns.BR, main, uRightBeg, 1,         vBotBeg, 1)

    ApplySubUVToPiece(ns.T,  main, uMid0,     uMid1,     0,       vTopEnd)
    ApplySubUVToPiece(ns.B,  main, uMid0,     uMid1,     vBotBeg, 1)
    ApplySubUVToPiece(ns.L,  main, 0,         uLeftEnd,  vMid0,   vMid1)
    ApplySubUVToPiece(ns.R,  main, uRightBeg, 1,         vMid0,   vMid1)
    ApplySubUVToPiece(ns.C,  main, uMid0,     uMid1,     vMid0,   vMid1)

    SetCornerSizes(ns, cL, cR, cTopH, cBotH)
    frame._yrgNineSliceMinW = math.ceil(cL + cR + 2)
    frame._yrgNineSliceMinH = math.ceil(cTopH + cBotH + 2)
    frame._yrgNineSliceSig = string.format("1t:%s:%.2f:%.2f:%.2f:%.2f", tostring(main.atlas or main.tex), cL, cR, cTopH, cBotH)
    return true
end

local function ConfigureFallbackNineSlice(frame, ns, texPath)
    if frame._yrgNineSliceSourceType == "fallback" and frame._yrgNineSliceSig == "fallback64" then
        return
    end
    local fallbackInfo = {
        tex = texPath,
        uv = { 0, 0, 0, 1, 1, 0, 1, 1 },
        color = { 1, 1, 1, 1 },
    }
    local cSize = 6
    local u1, u2 = 12 / 64, 52 / 64
    local uMid0, uMid1 = 31.25 / 64, 31.75 / 64

    ApplySubUVToPiece(ns.TL, fallbackInfo, 0,     u1,    0,     u1)
    ApplySubUVToPiece(ns.TR, fallbackInfo, u2,    1,     0,     u1)
    ApplySubUVToPiece(ns.BL, fallbackInfo, 0,     u1,    u2,    1)
    ApplySubUVToPiece(ns.BR, fallbackInfo, u2,    1,     u2,    1)
    ApplySubUVToPiece(ns.T,  fallbackInfo, uMid0, uMid1, 0,     u1)
    ApplySubUVToPiece(ns.B,  fallbackInfo, uMid0, uMid1, u2,    1)
    ApplySubUVToPiece(ns.L,  fallbackInfo, 0,     u1,    uMid0, uMid1)
    ApplySubUVToPiece(ns.R,  fallbackInfo, u2,    1,     uMid0, uMid1)
    ApplySubUVToPiece(ns.C,  fallbackInfo, uMid0, uMid1, uMid0, uMid1)

    SetCornerSizes(ns, cSize, cSize, cSize, cSize)
    frame._yrgNineSliceMinW = cSize * 2 + 2
    frame._yrgNineSliceMinH = cSize * 2 + 2
    frame._yrgNineSliceSourceType = "fallback"
    frame._yrgNineSliceSig = "fallback64"
end

local function ApplyHeaderNineSliceStyle(frame)
    if not frame then return end
    if frame.SetBackdrop then
        frame:SetBackdrop(nil)
    end

    local alpha = 1.0
    local ns = EnsureNineSlicePieces(frame)

    local usedNative = false
    for _, src in ipairs(GetMinimapHeaderBorderSources()) do
        if ConfigureNativeNineSlice(frame, ns, src) then
            usedNative = true
            break
        end
    end

    if usedNative then
        frame._yrgNineSliceSourceType = "native"
    else
        ConfigureFallbackNineSlice(frame, ns, TEX_HEADER_BOX)
    end

    if not frame._yrgBgFill then
        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
        fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
        frame._yrgBgFill = fill
    end
    frame._yrgBgFill:SetColorTexture(0.04, 0.03, 0.02, alpha * 0.45)

    if ns.C then
        ns.C:SetAlpha(alpha)
    end
end

-- Darkens the native Minimap Header background cleanly at locked 1.0 placard opacity
local function ApplyMinimapHeaderDarkness(db)
    local hdr = (MinimapCluster and (MinimapCluster.BorderTop
        or (MinimapCluster.ZoneTextButton and MinimapCluster.ZoneTextButton.StateTexture)
        or MinimapCluster.ZoneTextButton))
        or _G["MinimapBorderTop"]
    if not hdr then return end

    local enabled = db and db.enabled
    local underlayAlpha = enabled and 0.45 or 0

    local hdrParent = (hdr.GetParent and hdr:GetParent()) or nil
    local parentFrame = (type(hdr.CreateTexture) == "function" and hdr)
        or (hdrParent and type(hdrParent.CreateTexture) == "function" and hdrParent)
        or (MinimapCluster and MinimapCluster.HeaderFrame)
        or MinimapCluster
    if not parentFrame or type(parentFrame.CreateTexture) ~= "function" then return end

    if not parentFrame._yrgHeaderDarkenBg then
        local darkTex = parentFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
        darkTex:SetPoint("TOPLEFT", hdr, "TOPLEFT", 3, -3)
        darkTex:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", -3, 3)
        parentFrame._yrgHeaderDarkenBg = darkTex
    end

    if enabled and underlayAlpha > 0 then
        parentFrame._yrgHeaderDarkenBg:SetColorTexture(0.04, 0.03, 0.02, underlayAlpha)
        parentFrame._yrgHeaderDarkenBg:Show()
    else
        parentFrame._yrgHeaderDarkenBg:Hide()
    end
end

-- =========================================================================
-- LOCAL TIME ENFORCEMENT ON MINIMAP HEADER CLOCK
-- =========================================================================
local function ApplyLocalTimeSetting(db)
    if not db or not db.enabled or not db.alwaysShowLocalTime then return end
    if type(SetCVar) == "function" then
        pcall(SetCVar, "timeMgrUseLocalTime", "1")
    end
    if TimeManagerClockButton and type(TimeManager_UpdateTimeTicker) == "function" then
        pcall(TimeManager_UpdateTimeTicker)
    elseif TimeManagerClockTicker and type(GameTime_GetLocalTime) == "function" then
        pcall(function()
            TimeManagerClockTicker:SetText(GameTime_GetLocalTime(true))
        end)
    end
end

-- Dynamic top padding formula based on font size:
-- Font size 8 -> 2, Font size 14 -> 10, Font size 20 -> 16
local function CalculateDynamicExpTopPadding(fontSize)
    local s = fontSize or 14
    local x = (s - 8) / 6
    local pad = 2 + (9 * x) - (x * x)
    return math.max(0, math.floor(pad + 0.5))
end

local function CreateRadialRingLayer(parent, subLevel)
    local ring = {
        parent = parent,
        quads = {},
        r = 1, g = 1, b = 1, a = 1,
    }

    for i = 1, 4 do
        local qi = QUAD_INFO[i]
        local qFrame = CreateFrame("Frame", nil, parent)
        qFrame:SetFrameLevel(parent:GetFrameLevel() + (subLevel or 1))

        local tex = qFrame:CreateTexture(nil, "ARTWORK", nil, subLevel or 1)
        tex:SetAllPoints(qFrame)
        tex:SetTexture(TEX_FILL)
        tex:SetTexCoord(qi.u1, qi.u2, qi.v1, qi.v2)

        local mask = qFrame:CreateMaskTexture(nil, "ARTWORK")
        mask:SetTexture(TEX_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("CENTER", parent, "CENTER", 0, 0)
        tex:AddMaskTexture(mask)

        ring.quads[i] = {
            frame = qFrame,
            tex = tex,
            mask = mask,
            point = qi.point,
            u1 = qi.u1, u2 = qi.u2, v1 = qi.v1, v2 = qi.v2,
        }
    end

    function ring:SetTexturePath(path)
        local texPath = path or TEX_FILL
        for i = 1, 4 do
            local q = self.quads[i]
            q.tex:SetTexture(texPath)
            q.tex:SetTexCoord(q.u1, q.u2, q.v1, q.v2)
        end
    end

    function ring:UpdateSizes(fullSize)
        local half = fullSize * 0.5
        local maskSize = fullSize * 1.45
        for i = 1, 4 do
            local q = self.quads[i]
            q.frame:ClearAllPoints()
            q.frame:SetPoint(q.point, parent, q.point, 0, 0)
            q.frame:SetSize(half, half)
            q.mask:SetSize(maskSize, maskSize)
        end
    end

    function ring:SetColor(r, g, b, a)
        self.r, self.g, self.b, self.a = r or 1, g or 1, b or 1, a or 1
        for i = 1, 4 do
            self.quads[i].tex:SetVertexColor(self.r, self.g, self.b, self.a)
        end
    end

    function ring:SetProgress(pct)
        pct = math.max(0, math.min(1, pct or 0))
        for i = 1, 4 do
            local q = self.quads[i]
            local qStart = (i - 1) * 0.25
            local qEnd   = i * 0.25

            if pct <= qStart then
                q.frame:Hide()
            elseif pct >= qEnd then
                q.mask:SetRotation(-(qEnd * 2 * math.pi))
                q.frame:Show()
            else
                local theta = pct * 2 * math.pi
                q.mask:SetRotation(-theta)
                q.frame:Show()
            end
        end
    end

    return ring
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

local function SafeRegionCenterY(region)
    if not region or type(region.GetCenter) ~= "function" then return nil end
    local ok, _, y = pcall(region.GetCenter, region)
    if not ok then return nil end
    return YRG.SafeOptionalNumber(y)
end

local function SafeRegionBottom(region)
    if not region or type(region.GetBottom) ~= "function" then return nil end
    local ok, b = pcall(region.GetBottom, region)
    if not ok then return nil end
    return YRG.SafeOptionalNumber(b)
end

local function SafeRegionScale(region, fallback)
    if not region or type(region.GetEffectiveScale) ~= "function" then return fallback or 1 end
    local ok, s = pcall(region.GetEffectiveScale, region)
    local num = ok and YRG.SafeOptionalNumber(s) or nil
    if not num or num <= 0 then return fallback or 1 end
    return num
end

local function SafeRegionCenterX(region)
    if not region or type(region.GetCenter) ~= "function" then return nil end
    local ok, x = pcall(region.GetCenter, region)
    if not ok then return nil end
    return YRG.SafeOptionalNumber(x)
end

local headerCenteringGuard = false

local function IsFramePointAnchoredToAny(frame, targetSet, visited)
    if not frame or type(frame.GetNumPoints) ~= "function" then return false end
    visited = visited or {}
    if visited[frame] then return false end
    visited[frame] = true

    local okN, numPts = pcall(frame.GetNumPoints, frame)
    if okN and numPts and numPts > 0 then
        for i = 1, numPts do
            local okP, _, relTo = pcall(frame.GetPoint, frame, i)
            if okP and relTo and relTo ~= frame then
                if targetSet[relTo] or IsFramePointAnchoredToAny(relTo, targetSet, visited) then
                    return true
                end
            end
        end
    end
    return false
end

local function GetMinimapHeaderAnchors()
    if not MinimapCluster then return nil end
    local rawCandidates = {
        MinimapCluster.HeaderFrame or false,
        MinimapCluster.BorderTop or false,
        MinimapCluster.ZoneTextButton or false,
        _G["MinimapZoneTextButton"] or false,
        _G["MinimapBorderTop"] or false,
    }

    local eligible = {}
    local eligibleSet = {}
    for _, f in ipairs(rawCandidates) do
        if f and not eligibleSet[f]
            and type(f.GetNumPoints) == "function"
            and type(f.GetPoint) == "function"
            and type(f.GetEffectiveScale) == "function"
            and (not f.IsShown or f:IsShown()) then
            local w = YRG.SafeNumber(f.GetWidth and f:GetWidth(), 0)
            local okN, numPts = pcall(f.GetNumPoints, f)
            local isStretchedContainer = (f == MinimapCluster.HeaderFrame) and (okN and numPts and numPts >= 2)
            if okN and numPts and numPts >= 1 and w > 20 and not isStretchedContainer then
                local pts = {}
                local validPts = true
                local sharedRelTo = nil
                for i = 1, numPts do
                    local okP, pt, relTo, relPt, x, y = pcall(f.GetPoint, f, i)
                    if not okP or not pt then
                        validPts = false
                        break
                    end
                    if i == 1 then
                        sharedRelTo = relTo
                    elseif relTo ~= sharedRelTo then
                        validPts = false
                        break
                    end
                    table.insert(pts, {
                        pt = pt,
                        relTo = relTo or MinimapCluster,
                        relPt = relPt or pt,
                        x = YRG.SafeNumber(x, 0),
                        y = YRG.SafeNumber(y, 0),
                    })
                end
                if validPts and #pts > 0 then
                    eligibleSet[f] = true
                    table.insert(eligible, { frame = f, pts = pts })
                end
            end
        end
    end

    if #eligible == 0 then
        return nil
    end

    local roots = {}
    for _, item in ipairs(eligible) do
        if not IsFramePointAnchoredToAny(item.frame, eligibleSet) then
            table.insert(roots, item)
        end
    end
    return (#roots > 0) and roots or eligible
end

local function SafeRegionLeft(region)
    if not region or type(region.GetLeft) ~= "function" then return nil end
    local ok, l = pcall(region.GetLeft, region)
    return ok and YRG.SafeOptionalNumber(l) or nil
end

local function SafeRegionRight(region)
    if not region or type(region.GetRight) ~= "function" then return nil end
    local ok, r = pcall(region.GetRight, region)
    return ok and YRG.SafeOptionalNumber(r) or nil
end

local function GetCombinedVisualHeaderBoundsX(roots)
    local zoneBtn = MinimapCluster and MinimapCluster.ZoneTextButton
    local borderTop = MinimapCluster and MinimapCluster.BorderTop
    local refFrame = (zoneBtn and (not zoneBtn.IsShown or zoneBtn:IsShown()) and zoneBtn)
        or (borderTop and (not borderTop.IsShown or borderTop:IsShown()) and borderTop)
        or (roots and roots[1] and roots[1].frame)
    if not refFrame then return nil, nil, nil end

    local refScale = SafeRegionScale(refFrame, 1)
    local refY = SafeRegionCenterY(refFrame)
    if not refY or refScale <= 0 then return nil, nil, nil end
    local refScreenY = refY * refScale

    local visLeft, visRight = nil, nil
    local function ExpandBounds(region, explicitScale)
        if not region or (region.IsShown and not region:IsShown()) then return end
        local sc = explicitScale or SafeRegionScale(region, refScale)
        if sc <= 0 then return end
        local l = SafeRegionLeft(region)
        local r = SafeRegionRight(region)
        if l and r and r > l then
            local sl = l * sc
            local sr = r * sc
            visLeft = visLeft and math.min(visLeft, sl) or sl
            visRight = visRight and math.max(visRight, sr) or sr
        end
    end

    ExpandBounds(borderTop)
    ExpandBounds(zoneBtn)
    if zoneBtn and zoneBtn.StateTexture then
        ExpandBounds(zoneBtn.StateTexture, SafeRegionScale(zoneBtn, refScale))
    end

    -- Include inline accessory buttons anchored in the same rigid assembly (e.g. Tracking on left)
    local leftHasAccessory = false
    local rightHasAccessory = false
    if visLeft and visRight then
        local pillLeft, pillRight = visLeft, visRight
        local rootSet = {}
        for _, entry in ipairs(roots or {}) do
            rootSet[entry.frame] = true
        end
        if borderTop then rootSet[borderTop] = true end
        if zoneBtn then rootSet[zoneBtn] = true end

        local calendarBtn = _G["GameTimeFrame"]
        local accessories = {
            (MinimapCluster and MinimapCluster.Tracking) or false,
            _G["TimeManagerClockButton"] or false,
            calendarBtn or false,
        }
        for _, acc in ipairs(accessories) do
            if acc and (not acc.IsShown or acc:IsShown()) and IsFramePointAnchoredToAny(acc, rootSet) then
                local accScale = SafeRegionScale(acc, refScale)
                local accY = SafeRegionCenterY(acc)
                local accL = SafeRegionLeft(acc)
                local accR = SafeRegionRight(acc)
                if accY and accL and accR and accR > accL and accScale > 0 then
                    local sameBandY = math.abs((accY * accScale) - refScreenY) <= (16 * refScale)
                    local accSL = accL * accScale
                    local accSR = accR * accScale
                    local nearPillX = accSR >= (visLeft - 48 * refScale)
                        and accSL <= (visRight + 48 * refScale)
                    if sameBandY and nearPillX then
                        -- GameTimeFrame's drawn calendar border is ~1.5px more inset than Tracking's bezel
                        if acc == calendarBtn and (accSR - accSL) > (4 * accScale) then
                            accSR = accSR - (1.5 * accScale)
                        end
                        if accSL < (pillLeft - 1) then
                            leftHasAccessory = true
                        end
                        if accSR > (pillRight + 1) then
                            rightHasAccessory = true
                        end
                        visLeft = math.min(visLeft, accSL)
                        visRight = math.max(visRight, accSR)
                    end
                end
            end
        end
    end

    if not (visLeft and visRight) then
        return nil, nil, nil, false, false
    end
    return (visLeft + visRight) * 0.5, visLeft, visRight, leftHasAccessory, rightHasAccessory
end

local headerWidthGuard = false

local function SafeRegionWidth(region)
    if not region or type(region.GetWidth) ~= "function" then return nil end
    local ok, w = pcall(region.GetWidth, region)
    if not ok then return nil end
    local num = YRG.SafeNumber(w, 0)
    return (num > 0) and num or nil
end

local function HasHorizontalTwoPointStretch(region)
    if not region or type(region.GetNumPoints) ~= "function" or type(region.GetPoint) ~= "function" then
        return false
    end
    local n = YRG.SafeNumber(region:GetNumPoints(), 0)
    local hasLeft, hasRight = false, false
    for i = 1, n do
        local ok, pt = pcall(region.GetPoint, region, i)
        if ok and type(pt) == "string" then
            if pt:find("LEFT", 1, true) then hasLeft = true end
            if pt:find("RIGHT", 1, true) then hasRight = true end
        end
    end
    return hasLeft and hasRight
end

local function GetTargetPlacardScreenWidth(db)
    for _, placard in ipairs({ ExpTracker.infoFrame or false, ExpTracker.expFrame or false }) do
        if placard and placard.IsShown and placard:IsShown() then
            local w = SafeRegionWidth(placard)
            local s = SafeRegionScale(placard, 1)
            if w and s > 0 then
                return w * s, s
            end
        end
    end
    local mapScale = SafeRegionScale(Minimap, 1)
    local fallbackW = YRG.SafeNumber(db and db.infoPlacardWidth, 200)
    if mapScale > 0 and fallbackW > 0 then
        return fallbackW * mapScale, mapScale
    end
    return nil, mapScale
end

local function ApplyWidthDelta(region, deltaW, minW)
    if not region or type(region) ~= "table" or HasHorizontalTwoPointStretch(region) then
        return
    end
    if type(region.SetWidth) ~= "function" then return end
    local curW = SafeRegionWidth(region)
    if not curW then return end
    if not region._yrgWidthApplied then
        region._yrgOrigWidth = curW
    end
    if not region._yrgOrigWidth then return end
    local targetW = math.max(minW or 10, region._yrgOrigWidth + deltaW)
    if (not region._yrgWidthApplied) or math.abs(curW - targetW) >= 0.4 then
        if pcall(region.SetWidth, region, targetW) then
            region._yrgWidthApplied = true
        end
    end
end

local function ApplyMinimapHeaderWidth(db)
    if headerWidthGuard then return end
    if InCombatLockdown() then
        ExpTracker._pendingHeaderCenter = true
        return
    end

    local mc = MinimapCluster
    local zoneBtn = (mc and mc.ZoneTextButton) or _G["MinimapZoneTextButton"]
    local borderTop = mc and mc.BorderTop
    if not zoneBtn then return end

    local shouldStretch = db and db.enabled and db.matchPlacardWidth and true or false
    if not shouldStretch then
        local candidates = {
            zoneBtn,
            (borderTop and borderTop ~= zoneBtn) and borderTop or false,
            zoneBtn.StateTexture or false,
            zoneBtn.AddTexture or false,
        }
        local hadApplied = false
        headerWidthGuard = true
        for _, f in ipairs(candidates) do
            if f and f._yrgWidthApplied then
                hadApplied = true
                f._yrgWidthApplied = nil
                if f._yrgOrigWidth and f._yrgOrigWidth > 0 and type(f.SetWidth) == "function" then
                    pcall(f.SetWidth, f, f._yrgOrigWidth)
                end
                f._yrgOrigWidth = nil
            end
        end
        if hadApplied and mc and type(mc.Layout) == "function" then
            local prevGuard = headerCenteringGuard
            headerCenteringGuard = true
            pcall(mc.Layout, mc)
            headerCenteringGuard = prevGuard
            -- Reset cached shift points so re-centering captures fresh post-Layout defaults
            local roots = GetMinimapHeaderAnchors()
            if roots then
                for _, entry in ipairs(roots) do
                    entry.frame._yrgCenterApplied = nil
                    entry.frame._yrgPreShiftPoints = nil
                end
            end
        end
        headerWidthGuard = false
        return
    end

    local roots = GetMinimapHeaderAnchors()
    if not roots then return end

    local primary = (not HasHorizontalTwoPointStretch(zoneBtn)) and zoneBtn
        or (borderTop and not HasHorizontalTwoPointStretch(borderTop) and borderTop)
        or nil
    if not primary or type(primary.SetWidth) ~= "function" then return end

    local targetScreenW, placardScale = GetTargetPlacardScreenWidth(db)
    local primaryScale = SafeRegionScale(primary, 1)
    local primaryL = SafeRegionLeft(primary)
    local primaryR = SafeRegionRight(primary)
    local curPrimaryW = SafeRegionWidth(primary)
    if not (targetScreenW and primaryScale > 0 and primaryL and primaryR and curPrimaryW) then
        return
    end

    local _, visLeft, visRight, leftHasAcc, rightHasAcc = GetCombinedVisualHeaderBoundsX(roots)
    if not (visLeft and visRight) then return end

    -- Compensate for the placard 9-slice outer shadow apron (~4px per side) when crisp icon buttons flank the pill
    local edgePad = 4 * ((placardScale and placardScale > 0) and placardScale or primaryScale)
    local leftTrim = leftHasAcc and edgePad or 0
    local rightTrim = rightHasAcc and edgePad or 0

    local leftExtra = math.max(0, (primaryL * primaryScale) - visLeft)
    local rightExtra = math.max(0, visRight - (primaryR * primaryScale))
    local effectiveTargetW = math.max(80 * primaryScale, targetScreenW - leftTrim - rightTrim)
    local targetPrimaryW = math.max(80, (effectiveTargetW - leftExtra - rightExtra) / primaryScale)

    if not primary._yrgWidthApplied then
        primary._yrgOrigWidth = curPrimaryW
    end
    local origPrimaryW = primary._yrgOrigWidth
    if not origPrimaryW then return end

    local deltaW = targetPrimaryW - origPrimaryW
    headerWidthGuard = true
    if (not primary._yrgWidthApplied) or math.abs(curPrimaryW - targetPrimaryW) >= 0.4 then
        if pcall(primary.SetWidth, primary, targetPrimaryW) then
            primary._yrgWidthApplied = true
        end
    end

    local secondary = (primary == zoneBtn) and borderTop or zoneBtn
    if secondary and secondary ~= primary and not HasHorizontalTwoPointStretch(secondary) then
        local secW = SafeRegionWidth(secondary)
        local baseSecW = secondary._yrgOrigWidth or secW
        if baseSecW and math.abs(baseSecW - origPrimaryW) <= 80 then
            ApplyWidthDelta(secondary, deltaW, 80)
        end
    end

    ApplyWidthDelta(zoneBtn.StateTexture, deltaW, 10)
    ApplyWidthDelta(zoneBtn.AddTexture, deltaW, 10)
    headerWidthGuard = false
end

local function ApplyMinimapHeaderCenter(db)
    if headerCenteringGuard then return end
    if InCombatLockdown() then
        ExpTracker._pendingHeaderCenter = true
        return
    end

    local roots = GetMinimapHeaderAnchors()
    if not roots then return end

    local shouldCenter = db and db.enabled and (db.centerMinimapHeader ~= false)
    if not shouldCenter then
        local hadApplied = false
        for _, entry in ipairs(roots) do
            if entry.frame._yrgCenterApplied then
                hadApplied = true
                break
            end
        end
        if hadApplied then
            headerCenteringGuard = true
            for _, entry in ipairs(roots) do
                local f = entry.frame
                f._yrgCenterApplied = nil
                local savedPts = f._yrgPreShiftPoints
                if savedPts and #savedPts > 0 and type(f.SetPoint) == "function" then
                    if #savedPts > 1 and type(f.ClearAllPoints) == "function" then
                        pcall(f.ClearAllPoints, f)
                    end
                    for _, p in ipairs(savedPts) do
                        pcall(f.SetPoint, f, p.pt, p.relTo, p.relPt, p.x, p.y)
                    end
                end
                f._yrgPreShiftPoints = nil
            end
            if MinimapCluster and type(MinimapCluster.Layout) == "function" then
                pcall(MinimapCluster.Layout, MinimapCluster)
            end
            headerCenteringGuard = false
        end
        return
    end

    local mapX = SafeRegionCenterX(Minimap)
    local mapScale = SafeRegionScale(Minimap, 1)
    local visScreenX = GetCombinedVisualHeaderBoundsX(roots)
    if not (mapX and visScreenX and mapScale > 0) then
        return
    end

    local deltaScreenX = (mapX * mapScale) - visScreenX
    if math.abs(deltaScreenX) < 0.35 then
        return
    end

    headerCenteringGuard = true
    for _, entry in ipairs(roots) do
        local f = entry.frame
        local fScale = SafeRegionScale(f, 1)
        if fScale > 0 then
            if not f._yrgCenterApplied then
                f._yrgPreShiftPoints = entry.pts
            end
            local shiftLocal = deltaScreenX / fScale
            local ok = false
            if #entry.pts == 1 then
                local p = entry.pts[1]
                ok = pcall(f.SetPoint, f, p.pt, p.relTo, p.relPt, p.x + shiftLocal, p.y)
            elseif type(f.ClearAllPoints) == "function" then
                ok = pcall(function()
                    f:ClearAllPoints()
                    for _, p in ipairs(entry.pts) do
                        f:SetPoint(p.pt, p.relTo, p.relPt, p.x + shiftLocal, p.y)
                    end
                end)
            end
            if ok then
                f._yrgCenterApplied = true
            end
        end
    end
    headerCenteringGuard = false
end

local function IsMinimapHeaderOnBottom()
    if MinimapCluster then
        if type(MinimapCluster.IsHeaderUnderneath) == "function" then
            local ok, val = pcall(MinimapCluster.IsHeaderUnderneath, MinimapCluster)
            if ok and val then
                return true
            end
        end
        if MinimapCluster.headerUnderneath == true then
            return true
        end
        if Enum and Enum.EditModeMinimapSetting and Enum.EditModeMinimapSetting.HeaderUnderneath
            and type(MinimapCluster.GetSettingValueBool) == "function" then
            local ok, val = pcall(MinimapCluster.GetSettingValueBool, MinimapCluster, Enum.EditModeMinimapSetting.HeaderUnderneath)
            if ok and val then
                return true
            end
        end
    end

    local mapY = SafeRegionCenterY(Minimap)
    if mapY then
        local mapScreenY = mapY * SafeRegionScale(Minimap, 1)
        local headerCandidates = {
            (MinimapCluster and MinimapCluster.HeaderFrame) or false,
            (MinimapCluster and MinimapCluster.ZoneTextButton) or false,
            _G["MinimapZoneTextButton"] or false,
            (MinimapCluster and MinimapCluster.BorderTop) or false,
            _G["MinimapBorderTop"] or false,
            _G["TimeManagerClockButton"] or false,
        }
        for _, hdr in ipairs(headerCandidates) do
            if hdr and (not hdr.IsShown or hdr:IsShown()) then
                local hdrY = SafeRegionCenterY(hdr)
                if hdrY then
                    local hdrScreenY = hdrY * SafeRegionScale(hdr, 1)
                    if hdrScreenY < mapScreenY - 4 then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function GetBottomMinimapHeaderFrame()
    local mapY = SafeRegionCenterY(Minimap)
    if not mapY then return nil, nil end
    local mapScreenY = mapY * SafeRegionScale(Minimap, 1)

    local candidates = {
        (MinimapCluster and MinimapCluster.ZoneTextButton) or false,
        _G["MinimapZoneTextButton"] or false,
        (MinimapCluster and MinimapCluster.HeaderFrame) or false,
        (MinimapCluster and MinimapCluster.BorderTop) or false,
        _G["MinimapBorderTop"] or false,
    }

    local bestFrame = nil
    local lowestBottomScreen = nil
    for _, hdr in ipairs(candidates) do
        if hdr and (not hdr.IsShown or hdr:IsShown()) then
            local hdrW = hdr.GetWidth and YRG.SafeNumber(hdr:GetWidth(), 0) or 0
            local hdrH = hdr.GetHeight and YRG.SafeNumber(hdr:GetHeight(), 0) or 0
            local hdrY = SafeRegionCenterY(hdr)
            local hdrBottom = SafeRegionBottom(hdr)
            if hdrW > 12 and hdrH > 6 and hdrY and hdrBottom then
                local hdrScale = SafeRegionScale(hdr, 1)
                if (hdrY * hdrScale) < (mapScreenY - 4) then
                    local bScreen = hdrBottom * hdrScale
                    if not lowestBottomScreen or bScreen < lowestBottomScreen then
                        lowestBottomScreen = bScreen
                        bestFrame = hdr
                    end
                end
            end
        end
    end
    return bestFrame, lowestBottomScreen
end

local function GetBottomHeaderExtraOffset()
    local extraOffset = -24
    local hdr = (MinimapCluster and (MinimapCluster.ZoneTextButton or MinimapCluster.HeaderFrame or MinimapCluster.BorderTop)) or _G["MinimapBorderTop"]
    if hdr and type(hdr.GetHeight) == "function" then
        local h = YRG.SafeNumber(hdr:GetHeight(), 0)
        if h > 10 then
            extraOffset = -(math.floor(h + 0.5) + 4)
        end
    end
    return extraOffset
end

local function GetKillPaceMetrics(remXP)
    local count = #sessionKillsData
    if count == 0 then
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
    if count >= 2 and type(sessionKillsData[1]) == "table" and type(sessionKillsData[count]) == "table" then
        local totalDt = 0
        local dtCount = 0
        for i = 2, count do
            local prevEntry = sessionKillsData[i - 1]
            local curEntry = sessionKillsData[i]
            if type(prevEntry) == "table" and type(curEntry) == "table" then
                local dt = curEntry.t - prevEntry.t
                if dt > 0 and dt <= 300 then
                    totalDt = totalDt + dt
                    dtCount = dtCount + 1
                end
            end
        end
        if dtCount > 0 then
            avgInterval = totalDt / dtCount
        else
            local span = sessionKillsData[count].t - sessionKillsData[1].t
            if span > 0 then
                avgInterval = span / (count - 1)
            end
        end
    elseif count == 1 and type(sessionKillsData[1]) == "table" and sessionStartTime > 0 then
        local elapsed = sessionKillsData[1].t - sessionStartTime
        if elapsed > 0 and elapsed <= 300 then
            avgInterval = elapsed
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

    -- Gate 1: Only classes that can equip Bows, Crossbows, or Guns
    local _, playerClass = UnitClass("player")
    if not (playerClass and AMMO_CAPABLE_CLASSES[playerClass]) then
        return freeNormalSlots, false, 0, ICON_ARROW
    end

    -- Gate 2: Require an equipped Bow, Crossbow, or Gun in INVSLOT_RANGED (excludes Thrown, Wands, empty)
    local rangedSlot = INVSLOT_RANGED or 18
    local rangedID = GetInventoryItemID and GetInventoryItemID("player", rangedSlot) or nil
    if type(rangedID) ~= "number" or rangedID <= 0 then
        return freeNormalSlots, false, 0, ICON_ARROW
    end

    local hasCapableWeapon, rangedUsesBullets = ClassifyCapableRangedWeapon(rangedID)
    if not hasCapableWeapon then
        return freeNormalSlots, false, 0, ICON_ARROW
    end

    -- Gate 3: Check INVSLOT_AMMO via GetInventoryItemID > 0 (prevents empty-slot phantom 1);
    -- if empty while Bow/Crossbow/Gun is equipped, report 0 so red flashing warning triggers.
    local ammoSlot = INVSLOT_AMMO or 0
    local equippedAmmoID = GetInventoryItemID and GetInventoryItemID("player", ammoSlot) or nil
    if type(equippedAmmoID) ~= "number" or equippedAmmoID <= 0 then
        return freeNormalSlots, true, 0, (rangedUsesBullets and ICON_BULLET or ICON_ARROW)
    end

    local ammoCount = (GetInventoryItemCount and YRG.SafeNumber(GetInventoryItemCount("player", ammoSlot), 0)) or 0
    local ammoIcon = GetInventoryItemTexture and GetInventoryItemTexture("player", ammoSlot) or nil
    if not ammoIcon then
        ammoIcon = rangedUsesBullets and ICON_BULLET or ICON_ARROW
    end

    return freeNormalSlots, true, ammoCount, ammoIcon
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

local MASK_CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TEX_FALLBACK_RING = "Interface\\Minimap\\MiniMap-TrackingBorder"

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

local function ShowTrackerTooltip(ownerFrame)
    local curXP = YRG.SafeNumber(UnitXP("player"), 0)
    local maxXP = math.max(YRG.SafeNumber(UnitXPMax("player"), 1), 1)
    local restedXP = YRG.SafeNumber(GetXPExhaustion(), 0)
    local remXP = math.max(maxXP - curXP, 0)
    local pct = (curXP / maxXP) * 100
    local restedPct = (restedXP / maxXP) * 100

    GameTooltip:SetOwner(ownerFrame, "ANCHOR_BOTTOM")
    GameTooltip:SetText("YRG Experience & Session Tracker", 1.0, 0.82, 0.0)
    GameTooltip:AddDoubleLine("Current XP:", string.format("%d / %d (%.1f%%)", curXP, maxXP, pct), 0.9, 0.9, 0.9, 1, 1, 1)
    GameTooltip:AddDoubleLine("Remaining XP:", tostring(remXP), 0.9, 0.9, 0.9, 1, 0.82, 0)
    if restedXP > 0 then
        GameTooltip:AddDoubleLine("Rested Bonus:", string.format("%d (%.1f%%)", restedXP, restedPct), 0.4, 0.75, 1.0, 0.4, 0.75, 1.0)
    end

    local estKills, avgXP, avgInterval, estSeconds = GetKillPaceMetrics(remXP)
    if estKills and avgXP then
        GameTooltip:AddDoubleLine("Est. Kills to Level (Last 10):", string.format("%d (Avg %d XP/kill)", estKills, math.floor(avgXP)), 0.7, 0.9, 1.0, 1, 1, 1)
    end
    if estSeconds then
        local paceStr = avgInterval and string.format("%s (%.1fs/kill)", FormatTimeEstimate(estSeconds), avgInterval) or FormatTimeEstimate(estSeconds)
        GameTooltip:AddDoubleLine("Est. Time to Level:", paceStr, 0.7, 0.9, 1.0, 1, 1, 1)
    end
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

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-Click: Open YRG Settings", 0.65, 0.65, 0.65)
    GameTooltip:AddLine("Right-Click: Reset Kill Pace Trackers", 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

function ExpTracker:ResetSessionTrackers()
    sessionKillsData = {}
    sessionStartTime = GetTime()
    self.lastKnownXP = YRG.SafeNumber(UnitXP("player"), 0)
    self:UpdateXP()
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100YRG:|r Session Kills & Time-to-Level trackers have been reset.")
    end
end

local function OnPlacardMouseUp(frame, button)
    if button == "LeftButton" then
        YRG:OpenSettings("MinimapExpTracker")
    elseif button == "RightButton" then
        ExpTracker:ResetSessionTrackers()
        if GameTooltip and GameTooltip:IsOwned(frame) then
            ShowTrackerTooltip(frame)
        end
    end
end

function ExpTracker:EnsureFrames()
    if self.container then return end

    local container = CreateFrame("Frame", "YRGMinimapExpContainer", Minimap)
    container:SetFrameStrata("BACKGROUND")
    container:SetFrameLevel(math.max((Minimap:GetFrameLevel() or 1) - 1, 0))
    container:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    container:EnableMouse(false)
    self.container = container

    local trackBg = container:CreateTexture(nil, "BACKGROUND", nil, 1)
    trackBg:SetAllPoints(container)
    trackBg:SetTexture(TEX_FILL)
    trackBg:SetVertexColor(0.08, 0.06, 0.06, 0.92)
    self.trackBg = trackBg

    self.restedRing = CreateRadialRingLayer(container, 1)
    self.expRing = CreateRadialRingLayer(container, 2)

    local borderFrame = CreateFrame("Frame", nil, container)
    borderFrame:SetAllPoints(container)
    borderFrame:SetFrameLevel(container:GetFrameLevel() + 5)
    borderFrame:EnableMouse(false)
    self.borderFrame = borderFrame

    local bubbleOverlay = borderFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    bubbleOverlay:SetAllPoints(borderFrame)
    bubbleOverlay:Hide()
    self.bubbleOverlay = bubbleOverlay

    local ringBorder = borderFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    ringBorder:SetAllPoints(borderFrame)
    ringBorder:SetTexture(TEX_RING)
    self.ringBorder = ringBorder

    -- PLACARD 1: Separate Bottom-Fixed EXP Percentage Placard (Minimap Header 9-Slice)
    local expFrame = CreateFrame("Frame", "YRGMinimapExpPlacard", borderFrame, "BackdropTemplate")
    expFrame:SetFrameLevel(borderFrame:GetFrameLevel() + 4)
    expFrame:EnableMouse(true)
    expFrame:SetScript("OnEnter", ShowTrackerTooltip)
    expFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    expFrame:SetScript("OnMouseUp", OnPlacardMouseUp)
    self.expFrame = expFrame

    local pctText = expFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pctText:SetPoint("CENTER", expFrame, "CENTER", 0, 0)
    pctText:SetTextColor(1.0, 0.84, 0.35, 1.0)
    pctText:SetShadowColor(0, 0, 0, 1)
    pctText:SetShadowOffset(1, -1)
    self.pctText = pctText

    -- PLACARD 2: Dynamic Session & Map Info Placard (Minimap Header 9-Slice)
    local infoFrame = CreateFrame("Frame", "YRGMinimapInfoPlacard", borderFrame, "BackdropTemplate")
    infoFrame:SetFrameLevel(borderFrame:GetFrameLevel() + 2)
    infoFrame:EnableMouse(true)
    infoFrame:SetScript("OnEnter", ShowTrackerTooltip)
    infoFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    infoFrame:SetScript("OnMouseUp", OnPlacardMouseUp)
    self.infoFrame = infoFrame
    self.shieldFrame = infoFrame

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

local suppressDefaultExpGuard = false
local hookedExpBars = setmetatable({}, { __mode = "k" })

local function SetRegionMouseEnabled(region, enabled)
    if not region or InCombatLockdown() or (type(region.IsProtected) == "function" and region:IsProtected()) then
        return
    end
    if type(region.SetMouseMotionEnabled) == "function" then
        pcall(region.SetMouseMotionEnabled, region, enabled)
    elseif type(region.EnableMouse) == "function" then
        pcall(region.EnableMouse, region, enabled)
    end
    if type(region.SetMouseClickEnabled) == "function" then
        pcall(region.SetMouseClickEnabled, region, enabled)
    end
end

local function SuppressExpBarViaAlpha(bar, shouldHide)
    if not bar then return end
    if not hookedExpBars[bar] then
        hookedExpBars[bar] = true
        if type(bar.SetAlpha) == "function" then
            pcall(hooksecurefunc, bar, "SetAlpha", function(self, a)
                if suppressDefaultExpGuard then return end
                local mdb = YRG:GetModuleDB("MinimapExpTracker")
                if mdb and mdb.enabled and mdb.hideDefaultExpBar and a and a > 0 then
                    suppressDefaultExpGuard = true
                    pcall(self.SetAlpha, self, 0)
                    suppressDefaultExpGuard = false
                end
            end)
        end
        if type(bar.HookScript) == "function" then
            pcall(bar.HookScript, bar, "OnShow", function(self)
                local mdb = YRG:GetModuleDB("MinimapExpTracker")
                if mdb and mdb.enabled and mdb.hideDefaultExpBar then
                    suppressDefaultExpGuard = true
                    pcall(self.SetAlpha, self, 0)
                    suppressDefaultExpGuard = false
                end
            end)
        end
    end

    suppressDefaultExpGuard = true
    if type(bar.SetAlpha) == "function" then
        pcall(bar.SetAlpha, bar, shouldHide and 0 or 1)
    end
    suppressDefaultExpGuard = false

    -- Avoid Hide()/Show() on StatusTrackingBarManager / MainMenuExpBar so EditMode bottom action bar layout never taints
    SetRegionMouseEnabled(bar, not shouldHide)
    if type(bar.GetChildren) == "function" and not InCombatLockdown() then
        local okCh, children = pcall(function() return { bar:GetChildren() } end)
        if okCh and type(children) == "table" then
            for _, ch in ipairs(children) do
                SetRegionMouseEnabled(ch, not shouldHide)
            end
        end
    end
end

function ExpTracker:ApplyDefaultExpBarVisibility(db)
    local shouldHide = (db and db.enabled and db.hideDefaultExpBar) and true or false
    SuppressExpBarViaAlpha(MainMenuExpBar, shouldHide)
    SuppressExpBarViaAlpha(StatusTrackingBarManager, shouldHide)
end

local savedSelectionPoints = nil
local selectionBoundsModified = false
local updatingSelectionBounds = false
local lastSelectionOffsets = nil

local function IsEditModeActive()
    if EditModeManagerFrame then
        if EditModeManagerFrame.editModeActive then
            return true
        end
        if type(EditModeManagerFrame.IsShown) == "function" and EditModeManagerFrame:IsShown() then
            return true
        end
    end
    local sel = MinimapCluster and MinimapCluster.Selection
    if sel and type(sel.IsShown) == "function" and sel:IsShown() then
        return true
    end
    return false
end

local function RestoreEditModeMinimapSelection()
    if not selectionBoundsModified or InCombatLockdown() then return end
    local sel = MinimapCluster and MinimapCluster.Selection
    if not sel then return end

    updatingSelectionBounds = true
    pcall(function()
        sel:ClearAllPoints()
        if savedSelectionPoints and #savedSelectionPoints > 0 then
            for _, pt in ipairs(savedSelectionPoints) do
                sel:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        else
            sel:SetAllPoints(MinimapCluster)
        end
    end)
    selectionBoundsModified = false
    lastSelectionOffsets = nil
    updatingSelectionBounds = false
end

local function UpdateEditModeMinimapSelection(forceReapply)
    if updatingSelectionBounds then return end
    if InCombatLockdown() then return end

    local db = YRG:GetModuleDB("MinimapExpTracker")
    local sel = MinimapCluster and MinimapCluster.Selection
    if not sel or not MinimapCluster then return end

    if not sel._yrgSelectionHooked and type(sel.HookScript) == "function" then
        sel._yrgSelectionHooked = true
        pcall(sel.HookScript, sel, "OnShow", function()
            if updatingSelectionBounds then return end
            UpdateEditModeMinimapSelection(true)
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function()
                    UpdateEditModeMinimapSelection(true)
                end)
            end
        end)
    end

    if not db or not db.enabled or not ExpTracker.container or not ExpTracker.container:IsShown() or not IsEditModeActive() then
        RestoreEditModeMinimapSelection()
        return
    end

    if not savedSelectionPoints and type(sel.GetNumPoints) == "function" and type(sel.GetPoint) == "function" then
        local pts = {}
        local n = sel:GetNumPoints() or 0
        for i = 1, n do
            local ok, p, relTo, relP, x, y = pcall(sel.GetPoint, sel, i)
            if ok and p then
                table.insert(pts, { p, relTo or MinimapCluster, relP or p, x or 0, y or 0 })
            end
        end
        if #pts > 0 then
            savedSelectionPoints = pts
        end
    end

    local cL = YRG.SafeOptionalNumber(MinimapCluster.GetLeft and MinimapCluster:GetLeft())
    local cR = YRG.SafeOptionalNumber(MinimapCluster.GetRight and MinimapCluster:GetRight())
    local cB = YRG.SafeOptionalNumber(MinimapCluster.GetBottom and MinimapCluster:GetBottom())
    local cT = YRG.SafeOptionalNumber(MinimapCluster.GetTop and MinimapCluster:GetTop())
    local cScale = YRG.SafeOptionalNumber(MinimapCluster.GetEffectiveScale and MinimapCluster:GetEffectiveScale())
    local sScale = YRG.SafeOptionalNumber(sel.GetEffectiveScale and sel:GetEffectiveScale()) or cScale
    if not (cL and cR and cB and cT and cScale and sScale and cScale > 0 and sScale > 0) then
        return
    end

    local uLeft = cL * cScale
    local uRight = cR * cScale
    local uBottom = cB * cScale
    local uTop = cT * cScale

    local function ExpandWithFrame(f, insetRatioL, insetRatioR, insetRatioT, insetRatioB)
        if not f or (type(f.IsShown) == "function" and not f:IsShown()) then return end
        local fL = YRG.SafeOptionalNumber(f.GetLeft and f:GetLeft())
        local fR = YRG.SafeOptionalNumber(f.GetRight and f:GetRight())
        local fB = YRG.SafeOptionalNumber(f.GetBottom and f:GetBottom())
        local fT = YRG.SafeOptionalNumber(f.GetTop and f:GetTop())
        local fScale = YRG.SafeOptionalNumber(f.GetEffectiveScale and f:GetEffectiveScale()) or cScale
        if not (fL and fR and fB and fT and fScale and fScale > 0) then return end

        local fw = fR - fL
        local fh = fT - fB
        fL = fL + fw * (insetRatioL or 0)
        fR = fR - fw * (insetRatioR or 0)
        fT = fT - fh * (insetRatioT or 0)
        fB = fB + fh * (insetRatioB or 0)

        uLeft = math.min(uLeft, fL * fScale)
        uRight = math.max(uRight, fR * fScale)
        uBottom = math.min(uBottom, fB * fScale)
        uTop = math.max(uTop, fT * fScale)
    end

    -- Ring texture uses 512x512 canvas with ~48px side, 42px top, 56px bottom transparent margin
    ExpandWithFrame(ExpTracker.container, 48 / 512, 48 / 512, 42 / 512, 56 / 512)
    ExpandWithFrame(ExpTracker.expFrame, 0, 0, 0, 0)
    ExpandWithFrame(ExpTracker.infoFrame, 0, 0, 0, 0)

    local offLeft = (uLeft - (cL * cScale)) / sScale
    local offRight = (uRight - (cR * cScale)) / sScale
    local offTop = (uTop - (cT * cScale)) / sScale
    local offBottom = (uBottom - (cB * cScale)) / sScale

    if not forceReapply and selectionBoundsModified and lastSelectionOffsets then
        if math.abs(lastSelectionOffsets[1] - offLeft) < 0.2
            and math.abs(lastSelectionOffsets[2] - offRight) < 0.2
            and math.abs(lastSelectionOffsets[3] - offTop) < 0.2
            and math.abs(lastSelectionOffsets[4] - offBottom) < 0.2 then
            return
        end
    end

    updatingSelectionBounds = true
    local ok = pcall(function()
        sel:ClearAllPoints()
        sel:SetPoint("TOPLEFT", MinimapCluster, "TOPLEFT", offLeft, offTop)
        sel:SetPoint("BOTTOMRIGHT", MinimapCluster, "BOTTOMRIGHT", offRight, offBottom)
    end)
    if ok then
        selectionBoundsModified = true
        lastSelectionOffsets = { offLeft, offRight, offTop, offBottom }
    end
    updatingSelectionBounds = false
end

function ExpTracker:LayoutPlacardsImpl()
    if not self.container then return end
    local db = YRG:GetModuleDB("MinimapExpTracker")

    ApplyHeaderNineSliceStyle(self.expFrame)
    ApplyHeaderNineSliceStyle(self.infoFrame)
    ApplyMinimapHeaderDarkness(db)
    ApplyLocalTimeSetting(db)

    local mapWidth = Minimap:GetWidth() or 140
    local baseRingSize = mapWidth * (512 / 368)
    local ringBottomRimY = baseRingSize * (56 / 512)
    local ringTopRimY = -baseRingSize * (42 / 512)

    -- 1. Bottom-Fixed EXP Percentage Placard (always visible, font size configurable)
    local expTSize = db.expTextSize or 14
    local expTopPad = CalculateDynamicExpTopPadding(expTSize)
    self.pctText:SetFont(STANDARD_TEXT_FONT, expTSize, "OUTLINE")

    local pctW = math.max(self.pctText:GetStringWidth() or 28, 28)
    local minExpW = self.expFrame._yrgNineSliceMinW or 28
    local minExpH = self.expFrame._yrgNineSliceMinH or 20
    local expW = math.max(pctW + 16, minExpW)
    local expH = math.max(expTSize + 10 + expTopPad, minExpH)
    self.expFrame:SetSize(expW, expH)
    self.expFrame:ClearAllPoints()
    self.expFrame:SetPoint("CENTER", self.container, "BOTTOM", 0, ringBottomRimY)
    self.pctText:ClearAllPoints()
    self.pctText:SetPoint("TOP", self.expFrame, "TOP", 0, -(5 + expTopPad))
    self.expFrame:Show()

    -- 2. Dynamic Session & Map Info Placard
    -- Row 1: Col 1 (Coords/Gold left-justified) | Col 2 (Bags/Ammo/Shards right-justified expanding left)
    -- Row 2: Col 1 (Time to Level left-justified) | Col 2 (Est. Mob Kills right-justified)
    local row1TSize = YRG.SafeNumber(db.row1TextSize or db.textSize, 12)
    local row2TSize = YRG.SafeNumber(db.row2TextSize or db.textSize, 12)
    local pad = db.cellPadding or 10
    local userOffsetY = YRG.SafeNumber(db.infoPlacardOffsetY, 0)
    local fixedWidth = YRG.SafeNumber(db.infoPlacardWidth, 200)
    local dividerAlpha = math.max(0, math.min(1, (YRG.SafeNumber(db.rowDividerOpacityPct, 60)) / 100.0))
    local extraRowPad = math.max(0, YRG.SafeNumber(db.rowExtraPadding, 4))

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

    -- Row 1 Column 1 (Left-Justified Coordinates or Current Gold)
    local row1LeftMode = GetRow1LeftMode(db)
    local hasRow1Col1 = (row1LeftMode ~= "none" and self.coordBadge) and true or false

    -- Row 1 Column 2 (Right-Justified Bag Trackers expanding leftward: Inventory first on far right, then alt trackers)
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

    -- Row 2 (2 Columns: Time to Level left-justified | Est. Mob Kills right-justified)
    local hasRow2 = (db.showFarmingRow ~= false) and ((self.timeBadge or self.killBadge) and true or false)

    local hasRow1 = hasRow1Col1 or (#activeRow1Col2 > 0)

    if db.showInfoPlacard == false or (not hasRow1 and not hasRow2) then
        self.infoFrame:Hide()
        HandleBuiltInCoordinates(false)
        UpdateEditModeMinimapSelection()
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

    -- Horizontal line divider centered between Row 1 and Row 2 when both rows are active
    if hasRow1 and hasRow2 and self.rowDivider and dividerAlpha > 0 then
        local divInset = math.max(8, math.floor(sidePad * 0.6))
        self.rowDivider:SetColorTexture(0.65, 0.52, 0.25, dividerAlpha)
        self.rowDivider:SetPoint("LEFT", self.infoFrame, "LEFT", divInset, dividerY)
        self.rowDivider:SetPoint("RIGHT", self.infoFrame, "RIGHT", -divInset, dividerY)
        self.rowDivider:Show()
    end

    -- Place Row 1 Col 1 (Coordinates/Gold left-justified)
    if hasRow1Col1 then
        self.coordBadge:SetPoint("LEFT", self.infoFrame, "LEFT", sidePad, row1Y)
        self.coordBadge:Show()
    end

    -- Place Row 1 Col 2 (Inventory always full right; alt badges expand to the left)
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

    -- Place Row 2 (2 Columns: Time to Level left-justified | Est. Mob Kills right-justified)
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

    self.infoFrame:SetSize(finalInfoW, finalInfoH)
    self.infoFrame:ClearAllPoints()

    local isHeaderBottom = IsMinimapHeaderOnBottom()
    if isHeaderBottom and db.followMapOrientation then
        self.infoFrame:SetPoint("BOTTOM", self.container, "TOP", 0, ringTopRimY + 2 + userOffsetY)
    elseif isHeaderBottom and not db.followMapOrientation then
        local titleHdr, titleBottomScreen = GetBottomMinimapHeaderFrame()
        local cBottom = SafeRegionBottom(self.container)
        local cScale = SafeRegionScale(self.container, 1)
        local expBottomRelContainer = ringBottomRimY - (expH * 0.5)

        if titleHdr and titleBottomScreen and cBottom then
            local titleBottomRelContainer = (titleBottomScreen - (cBottom * cScale)) / cScale
            local anchorBottomRel = math.min(titleBottomRelContainer, expBottomRelContainer)
            self.infoFrame:SetPoint("TOP", self.container, "BOTTOM", 0, anchorBottomRel - 2 + userOffsetY)
        else
            self.infoFrame:SetPoint("TOP", self.expFrame, "BOTTOM", 0, GetBottomHeaderExtraOffset() + 3 + userOffsetY)
        end
    else
        -- Default (title bar on top): anchored directly below the EXP Placard
        self.infoFrame:SetPoint("TOP", self.expFrame, "BOTTOM", 0, 3 + userOffsetY)
    end

    self.infoFrame:Show()
    UpdateEditModeMinimapSelection()
end

function ExpTracker:LayoutPlacards()
    self:LayoutPlacardsImpl()
    if not self.container then return end
    local db = YRG:GetModuleDB("MinimapExpTracker")
    ApplyMinimapHeaderWidth(db)
    ApplyMinimapHeaderCenter(db)
end

function ExpTracker:ApplyVisualSettings()
    if not self.container then return end
    local db = YRG:GetModuleDB("MinimapExpTracker")

    local scaleMultiplier = db.masterScale or 1.0

    local scaleTarget = MinimapCluster or Minimap
    if scaleTarget and type(scaleTarget.SetScale) == "function" then
        local curScale = (type(scaleTarget.GetScale) == "function") and YRG.SafeNumber(scaleTarget:GetScale(), 1.0) or 1.0
        local isProtected = type(scaleTarget.IsProtected) == "function" and scaleTarget:IsProtected()
        if not InCombatLockdown() and not isProtected and math.abs(curScale - scaleMultiplier) > 0.001 then
            pcall(scaleTarget.SetScale, scaleTarget, scaleMultiplier)
        end
    end

    local mapWidth = Minimap:GetWidth() or 140
    local baseRingSize = mapWidth * (512 / 368)

    self.container:SetSize(baseRingSize, baseRingSize)
    self.restedRing:UpdateSizes(baseRingSize)
    self.expRing:UpdateSizes(baseRingSize)

    local fillPath = FILL_TEXTURES[db.fillStyle or "conduit"] or FILL_TEXTURES.conduit or TEX_FILL
    if self.expRing.SetTexturePath then
        self.expRing:SetTexturePath(fillPath)
    end
    if self.restedRing.SetTexturePath then
        self.restedRing:SetTexturePath(fillPath)
    end

    if self.bubbleOverlay then
        local ovPath = BUBBLE_OVERLAY_TEXTURES[db.bubbleOverlay or "bevel"]
        local ovAlpha = math.max(0, math.min(1, YRG.SafeNumber(db.bubbleOverlayOpacityPct, 85) / 100))
        if ovPath and ovAlpha > 0 then
            self.bubbleOverlay:SetTexture(ovPath)
            self.bubbleOverlay:SetAlpha(ovAlpha)
            self.bubbleOverlay:Show()
        else
            self.bubbleOverlay:Hide()
        end
    end

    local scheme = COLOR_SCHEMES[db.colorScheme or "blue"] or COLOR_SCHEMES.blue
    local ec = scheme.exp
    local rc = scheme.rested
    self.expRing:SetColor(ec.r, ec.g, ec.b, ec.a or 1.0)
    self.restedRing:SetColor(rc.r, rc.g, rc.b, rc.a or 0.92)

    self:ApplyDefaultExpBarVisibility(db)
    if self.ApplyHideAddonButtonsSetting then
        self:ApplyHideAddonButtonsSetting(db)
    end
    self:UpdateXP()
end

function ExpTracker:ApplyHideAddonButtonsSetting(db)
    local libDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not libDBIcon then return end

    local shouldHide = db and db.enabled and (db.hideAddonButtons ~= false) and true or false
    if type(libDBIcon.GetButtonList) == "function" and type(libDBIcon.ShowOnEnter) == "function" then
        local buttons = libDBIcon:GetButtonList()
        if type(buttons) == "table" then
            for _, btnName in ipairs(buttons) do
                pcall(libDBIcon.ShowOnEnter, libDBIcon, btnName, shouldHide)
            end
        end
    end

    if not self._libDBIconCallbackRegistered and type(libDBIcon.RegisterCallback) == "function" then
        self._libDBIconCallbackRegistered = true
        self._libDBIconCallbackOwner = self._libDBIconCallbackOwner or {}
        pcall(libDBIcon.RegisterCallback, self._libDBIconCallbackOwner, "LibDBIcon_IconCreated", function(_, _, name)
            local modDB = YRG:GetModuleDB("MinimapExpTracker")
            local hideNow = modDB and modDB.enabled and (modDB.hideAddonButtons ~= false) and true or false
            local lib = LibStub and LibStub("LibDBIcon-1.0", true)
            if lib and type(lib.ShowOnEnter) == "function" then
                pcall(lib.ShowOnEnter, lib, name, hideNow)
            end
        end)
    end
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

function ExpTracker:CheckRaidWarningTransition(stateKey, newState, warnMsg, critMsg)
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

function ExpTracker:UpdateXP()
    if not self.container then return end
    local db = YRG:GetModuleDB("MinimapExpTracker")
    if not db or not db.enabled then
        self.container:Hide()
        HandleBuiltInCoordinates(false)
        ApplyMinimapHeaderCenter(db)
        ApplyMinimapHeaderDarkness(db)
        RestoreEditModeMinimapSelection()
        return
    end

    local level = YRG.SafeNumber(UnitLevel("player"), 1)
    local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if db.hideAtMaxLevel and level >= maxLevel then
        self.container:Hide()
        HandleBuiltInCoordinates(false)
        RestoreEditModeMinimapSelection()
        return
    end
    self.container:Show()

    local curXP = YRG.SafeNumber(UnitXP("player"), 0)
    local maxXP = math.max(YRG.SafeNumber(UnitXPMax("player"), 1), 1)
    local restedXP = YRG.SafeNumber(GetXPExhaustion(), 0)

    local expRatio = math.max(0, math.min(1, curXP / maxXP))
    local restedRatio = 0
    if db.showRestedBar and restedXP > 0 then
        restedRatio = math.max(0, math.min(1, (curXP + restedXP) / maxXP))
    end

    self.expRing:SetProgress(expRatio)
    if restedRatio > expRatio then
        self.restedRing:SetProgress(restedRatio)
    else
        self.restedRing:SetProgress(0)
    end

    local pctVal = expRatio * 100
    if db.showDecimals then
        self.pctText:SetText(string.format("%.1f%%", pctVal))
    else
        self.pctText:SetText(string.format("%d%%", math.floor(pctVal + 0.5)))
    end

    local row1TSize = YRG.SafeNumber(db.row1TextSize or db.textSize, 12)
    local row2TSize = YRG.SafeNumber(db.row2TextSize or db.textSize, 12)
    local row1IconSz = math.max(10, row1TSize)
    local remXP = math.max(maxXP - curXP, 0)
    local estKills, _, _, estSeconds = GetKillPaceMetrics(remXP)

    if db.showFarmingRow ~= false then
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

    -- Row 1 Col 2 trackers: Free bag slots, Arrows/Ammo remaining, Warlock Soul Shards
    local tSize = row1TSize
    local freeSlots, hasAmmoSource, totalAmmoCount, ammoDisplayIcon = GetInventoryAndAmmoStatus()

    if db.showBagSlots ~= false and self.bagSlotsBadge then
        local bagThresh = math.max(0, YRG.SafeNumber(db.bagWarnThreshold, 3))
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
        local ammoThresh = math.max(0, YRG.SafeNumber(db.ammoWarnThreshold, 200))
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

    self:LayoutPlacards()
end

function ExpTracker:OnInitialize(db)
    if db.showEstimatedTime == false and db.showEstimatedKills == false then
        db.showFarmingRow = false
    end
    db.showEstimatedTime = nil
    db.showEstimatedKills = nil
    if db.infoPlacardExtraWidth ~= nil then
        if db.infoPlacardWidth == nil then
            db.infoPlacardWidth = math.min(360, math.max(100, 200 + YRG.SafeNumber(db.infoPlacardExtraWidth, 0)))
        end
        db.infoPlacardExtraWidth = nil
    end
    if not db.fillStyle or not FILL_TEXTURES[db.fillStyle] then
        db.fillStyle = "conduit"
    end
    if not db.bubbleOverlay or (db.bubbleOverlay ~= "none" and not BUBBLE_OVERLAY_TEXTURES[db.bubbleOverlay]) then
        db.bubbleOverlay = "bevel"
    end
    if not db.colorScheme or not COLOR_SCHEMES[db.colorScheme] then
        db.colorScheme = "blue"
    end
    db.headerOffsetX = nil
    db.expColor = nil
    db.restedColor = nil
    db._fixedColorPickerAlphaV1 = nil
    if db.row1LeftMode == nil then
        db.row1LeftMode = (db.showCoordinates == false) and "none" or "coords"
    elseif db.row1LeftMode ~= "coords" and db.row1LeftMode ~= "gold" and db.row1LeftMode ~= "none" then
        db.row1LeftMode = "coords"
    end
    db.showCoordinates = nil
    if db.row1TextSize == nil then
        db.row1TextSize = tonumber(db.textSize) or 12
    end
    if db.row2TextSize == nil then
        db.row2TextSize = tonumber(db.textSize) or 12
    end
    db.textSize = nil

    self:EnsureFrames()
    sessionStartTime = GetTime()
    self.eventFrame = CreateFrame("Frame")
    self.coordTimer = 0
    self.lastKnownXP = YRG.SafeNumber(UnitXP("player"), 0)

    self.eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_XP_UPDATE" then
            local newXP = YRG.SafeNumber(UnitXP("player"), 0)
            local diff = (self.lastKnownXP and newXP >= self.lastKnownXP) and (newXP - self.lastKnownXP) or 0
            self.lastKnownXP = newXP
            if diff > 0 then
                local now = GetTime()
                local lastEntry = sessionKillsData[#sessionKillsData]
                if type(lastEntry) == "table" and (now - lastEntry.t) > 300 then
                    sessionKillsData = {}
                end
                table.insert(sessionKillsData, { xp = diff, t = now })
                if #sessionKillsData > 10 then
                    table.remove(sessionKillsData, 1)
                end
            end
            self:UpdateXP()
        elseif event == "UNIT_INVENTORY_CHANGED" then
            if arg1 == "player" then
                self:UpdateXP()
            end
        elseif event == "BAG_UPDATE" then
            self:UpdateXP()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if self._pendingHeaderCenter then
                self._pendingHeaderCenter = nil
                local modDB = YRG:GetModuleDB("MinimapExpTracker")
                if modDB then
                    ApplyMinimapHeaderWidth(modDB)
                    ApplyMinimapHeaderCenter(modDB)
                    self:LayoutPlacards()
                end
            end
        else
            self.lastKnownXP = YRG.SafeNumber(UnitXP("player"), 0)
            self:UpdateXP()
        end
    end)

    self.eventFrame:SetScript("OnUpdate", function(frame, elapsed)
        frame.coordTimer = (frame.coordTimer or 0) + elapsed
        if frame.coordTimer >= 0.5 then
            frame.coordTimer = 0
            local modDB = YRG:GetModuleDB("MinimapExpTracker")
            if modDB and modDB.enabled then
                ExpTracker:UpdateXP()
            end
        end
    end)

    Minimap:HookScript("OnSizeChanged", function()
        self:ApplyVisualSettings()
        self:UpdateXP()
    end)

    local function SyncMinimapHeaderLayout()
        self:LayoutPlacards()
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                local modDB = YRG:GetModuleDB("MinimapExpTracker")
                if modDB and modDB.enabled then
                    ApplyMinimapHeaderWidth(modDB)
                    ApplyMinimapHeaderCenter(modDB)
                end
            end)
        end
    end

    if MinimapCluster then
        if type(MinimapCluster.SetHeaderUnderneath) == "function" then
            hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", SyncMinimapHeaderLayout)
        end
        if type(MinimapCluster.Layout) == "function" then
            hooksecurefunc(MinimapCluster, "Layout", SyncMinimapHeaderLayout)
        end
        if type(MinimapCluster.SetEditModeScale) == "function" then
            hooksecurefunc(MinimapCluster, "SetEditModeScale", SyncMinimapHeaderLayout)
        end
    end
    local function SyncEditModeSelection()
        self:LayoutPlacards()
        UpdateEditModeMinimapSelection(true)
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function()
                UpdateEditModeMinimapSelection(true)
            end)
        end
    end
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", SyncEditModeSelection)
        EditModeManagerFrame:HookScript("OnHide", function()
            self:LayoutPlacards()
            RestoreEditModeMinimapSelection()
        end)
        if type(EditModeManagerFrame.EnterEditMode) == "function" then
            pcall(hooksecurefunc, EditModeManagerFrame, "EnterEditMode", SyncEditModeSelection)
        end
        if type(EditModeManagerFrame.ExitEditMode) == "function" then
            pcall(hooksecurefunc, EditModeManagerFrame, "ExitEditMode", RestoreEditModeMinimapSelection)
        end
        if type(EditModeManagerFrame.UpdateSystems) == "function" then
            pcall(hooksecurefunc, EditModeManagerFrame, "UpdateSystems", SyncEditModeSelection)
        end
    end
    if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", SyncEditModeSelection, ExpTracker)
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", RestoreEditModeMinimapSelection, ExpTracker)
    end
end

function ExpTracker:OnEnable(db)
    self:EnsureFrames()
    if sessionStartTime == 0 then sessionStartTime = GetTime() end
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
    self.eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
    self.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    self.eventFrame:RegisterEvent("PLAYER_MONEY")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:ApplyVisualSettings()
    self:UpdateXP()
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            local modDB = YRG:GetModuleDB("MinimapExpTracker")
            if modDB and modDB.enabled then
                ApplyMinimapHeaderWidth(modDB)
                ApplyMinimapHeaderCenter(modDB)
            end
        end)
        C_Timer.After(1.0, function()
            local modDB = YRG:GetModuleDB("MinimapExpTracker")
            if modDB and modDB.enabled and self.ApplyHideAddonButtonsSetting then
                self:ApplyHideAddonButtonsSetting(modDB)
            end
        end)
    end
end

function ExpTracker:OnDisable(db)
    self._lastBagWarnState = nil
    self._lastAmmoWarnState = nil
    self._pendingHeaderCenter = nil
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    if self.container then
        self.container:Hide()
    end
    RestoreEditModeMinimapSelection()
    HandleBuiltInCoordinates(false)
    ApplyMinimapHeaderCenter(db)
    ApplyMinimapHeaderWidth(db)
    ApplyMinimapHeaderDarkness(db)
    if self.ApplyHideAddonButtonsSetting then
        self:ApplyHideAddonButtonsSetting(db)
    end
    local scaleTarget = MinimapCluster or Minimap
    if scaleTarget and type(scaleTarget.SetScale) == "function" then
        local curScale = (type(scaleTarget.GetScale) == "function") and YRG.SafeNumber(scaleTarget:GetScale(), 1.0) or 1.0
        local isProtected = type(scaleTarget.IsProtected) == "function" and scaleTarget:IsProtected()
        if not InCombatLockdown() and not isProtected and math.abs(curScale - 1.0) > 0.001 then
            pcall(scaleTarget.SetScale, scaleTarget, 1.0)
        end
    end
    self:ApplyDefaultExpBarVisibility(db)
end

function ExpTracker:BuildConfigUI(ctx, db)
    local function GetDB()
        return YRG:GetModuleDB("MinimapExpTracker")
    end

    local function IsPlacardEnabled()
        local mdb = GetDB()
        return mdb == nil or mdb.showInfoPlacard ~= false
    end

    -- =========================================================================
    -- SECTION 1: Radial Ring & Minimap Header Settings
    -- =========================================================================
    ctx:AddHeader(
        "1. Radial Ring & Minimap Header Settings",
        "Controls the 4-quadrant EXP/Rested ring around your minimap, colors, minimap clock, addon button visibility, and scale."
    )

    ctx:AddCheckbox({
        key = "showRestedBar",
        name = "Show Extended Rested EXP Fill",
        tooltip = "Extends the radial bar clockwise in your Rested color past current EXP.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showRestedBar ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showRestedBar = val end
            self:UpdateXP()
        end,
    })

    ctx:AddCheckbox({
        key = "hideDefaultExpBar",
        name = "Hide Default Blizzard EXP Bar",
        tooltip = "Hides the standard MainMenuExpBar while the Minimap EXP Tracker is enabled.",
        defaultValue = false,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.hideDefaultExpBar) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.hideDefaultExpBar = val end
            self:ApplyDefaultExpBarVisibility(mdb)
        end,
    })

    ctx:AddCheckbox({
        key = "alwaysShowLocalTime",
        name = "Always Show Local Time on Minimap Header",
        tooltip = "Forces the minimap header clock to display your local computer time instead of realm server time.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.alwaysShowLocalTime ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.alwaysShowLocalTime = val end
            if type(SetCVar) == "function" then
                pcall(SetCVar, "timeMgrUseLocalTime", val and "1" or "0")
            end
            if type(TimeManager_UpdateTimeTicker) == "function" then
                pcall(TimeManager_UpdateTimeTicker)
            end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddCheckbox({
        key = "hideAddonButtons",
        name = "Hide Addon Buttons Until Hover",
        tooltip = "Hides LibDBIcon addon buttons around the minimap until your cursor hovers over the minimap (modeled after Leatrix Plus).",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.hideAddonButtons ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.hideAddonButtons = val end
            self:ApplyHideAddonButtonsSetting(mdb)
        end,
    })

    ctx:AddCheckbox({
        key = "centerMinimapHeader",
        name = "Center Minimap Title Bar",
        tooltip = "Aligns Blizzard's native minimap title bar assembly horizontally over the minimap center.",
        defaultValue = true,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.centerMinimapHeader ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.centerMinimapHeader = val end
            ApplyMinimapHeaderCenter(mdb)
            self:LayoutPlacards()
        end,
    })

    ctx:AddCheckbox({
        key = "matchPlacardWidth",
        name = "Stretch Title Bar to Match Placard Width",
        tooltip = "Resizes Blizzard's minimap title bar so the combined header assembly (including Tracking and Calendar icons when visible) matches your placard width.",
        defaultValue = false,
        get = function()
            local mdb = GetDB()
            return mdb and mdb.matchPlacardWidth == true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.matchPlacardWidth = val end
            ApplyMinimapHeaderWidth(mdb)
            self:LayoutPlacards()
        end,
    })

    ctx:AddDropdown({
        key = "colorScheme",
        name = "EXP Bar Color Theme",
        tooltip = "Choose the color pair for Current EXP (brighter shade) and extended Rested EXP (darker shade).",
        defaultValue = "blue",
        options = COLOR_SCHEME_OPTIONS,
        get = function()
            local mdb = GetDB()
            local scheme = mdb and mdb.colorScheme
            return (scheme and COLOR_SCHEMES[scheme]) and scheme or "blue"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.colorScheme = COLOR_SCHEMES[val] and val or "blue"
            end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddDropdown({
        key = "fillStyle",
        name = "Radial Bar Fill Texture",
        tooltip = "Select the visual pattern style used for the radial EXP and Rested EXP fill bars around the minimap.",
        defaultValue = "conduit",
        options = FILL_TEXTURE_OPTIONS,
        get = function()
            local mdb = GetDB()
            local style = mdb and mdb.fillStyle
            return (style and FILL_TEXTURES[style]) and style or "conduit"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.fillStyle = FILL_TEXTURES[val] and val or "conduit"
            end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddDropdown({
        key = "bubbleOverlay",
        name = "20-Bubble Overlay Style",
        tooltip = "Overlays 20 EXP bubble dividers/capsules across the entire ring channel (visible on filled, rested, and empty sections).",
        defaultValue = "bevel",
        options = BUBBLE_OVERLAY_OPTIONS,
        notifies = { "YRG_MinimapExpTracker_bubbleOverlayOpacityPct" },
        get = function()
            local mdb = GetDB()
            local ov = mdb and mdb.bubbleOverlay
            return (ov and (ov == "none" or BUBBLE_OVERLAY_TEXTURES[ov])) and ov or "bevel"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.bubbleOverlay = (val == "none" or BUBBLE_OVERLAY_TEXTURES[val]) and val or "bevel"
            end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddSlider({
        key = "bubbleOverlayOpacityPct",
        name = "20-Bubble Overlay Opacity (%)",
        tooltip = "Transparency of the 20-bubble overlay texture across the radial bar (85% = default, 100% = fully opaque).",
        min = 0, max = 100, step = 5, defaultValue = 85,
        format = function(v) return string.format("%d%%", v) end,
        canModify = function()
            local mdb = GetDB()
            local ov = (mdb and mdb.bubbleOverlay) or "bevel"
            return ov ~= "none"
        end,
        get = function()
            local mdb = GetDB()
            return math.max(0, math.min(100, YRG.SafeNumber(mdb and mdb.bubbleOverlayOpacityPct, 85)))
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.bubbleOverlayOpacityPct = math.floor(val + 0.5) end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddSlider({
        key = "masterScale",
        name = "Minimap Master Scale",
        tooltip = "Overall scale factor applied to the minimap cluster and attached YRG placards.",
        min = 0.70, max = 1.40, step = 0.02, defaultValue = 1.0,
        format = function(v) return string.format("%.2f", v) end,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.masterScale) or 1.0
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.masterScale = val end
            self:ApplyVisualSettings()
        end,
    })

    -- =========================================================================
    -- SECTION 2: Bottom-Fixed EXP Percentage Placard
    -- =========================================================================
    ctx:AddHeader("2. EXP Percentage Placard (Bottom Fixed)")

    ctx:AddCheckbox({
        key = "showDecimals",
        name = "Show Decimal Percentage (e.g. 40.5%)",
        tooltip = "Toggles between whole percentages (40%) and one decimal place (40.5%).",
        defaultValue = false,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.showDecimals) and true or false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showDecimals = val end
            self:UpdateXP()
        end,
    })

    ctx:AddSlider({
        key = "expTextSize",
        name = "EXP Badge Font Size",
        tooltip = "Font size in points for the bottom-fixed EXP percentage badge.",
        min = 8, max = 20, step = 1, defaultValue = 14,
        format = function(v) return string.format("%d px", v) end,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.expTextSize) or 14
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.expTextSize = val end
            self:ApplyVisualSettings()
        end,
    })

    -- =========================================================================
    -- SECTION 3: Dynamic Session & Map Info Placard
    -- =========================================================================
    ctx:AddHeader("3. Dynamic Info Placard")

    local placardChildVars = {
        "YRG_MinimapExpTracker_followMapOrientation",
        "YRG_MinimapExpTracker_infoPlacardWidth",
        "YRG_MinimapExpTracker_cellPadding",
        "YRG_MinimapExpTracker_infoPlacardOffsetY",
        "YRG_MinimapExpTracker_rowDividerOpacityPct",
        "YRG_MinimapExpTracker_rowExtraPadding",
        "YRG_MinimapExpTracker_row1LeftMode",
        "YRG_MinimapExpTracker_row1TextSize",
        "YRG_MinimapExpTracker_showBagSlots",
        "YRG_MinimapExpTracker_showArrowsRemaining",
        "YRG_MinimapExpTracker_showSoulShards",
        "YRG_MinimapExpTracker_bagWarnThreshold",
        "YRG_MinimapExpTracker_ammoWarnThreshold",
        "YRG_MinimapExpTracker_bagRaidWarnings",
        "YRG_MinimapExpTracker_showFarmingRow",
        "YRG_MinimapExpTracker_row2TextSize",
    }

    ctx:AddCheckbox({
        key = "showInfoPlacard",
        name = "Enable Dynamic Info Placard",
        tooltip = "Toggles the secondary dynamic-fit info placard displaying coordinates, bag/ammo counts, and farming stats.",
        defaultValue = true,
        notifies = placardChildVars,
        get = IsPlacardEnabled,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showInfoPlacard = val end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddCheckbox({
        key = "followMapOrientation",
        name = "Follow Map Header Orientation (Flip to Top)",
        tooltip = "When checked, stays anchored below the EXP Placard if the minimap title is on top, and flips to the top if the title is moved to the bottom in Edit Mode.",
        defaultValue = true,
        canModify = IsPlacardEnabled,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.followMapOrientation ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.followMapOrientation = val end
            self:ApplyVisualSettings()
        end,
    })

    local function AddPlacardSlider(key, name, tooltip, minVal, maxVal, step, defaultVal, formatFn)
        ctx:AddSlider({
            key = key,
            name = name,
            tooltip = tooltip,
            min = minVal, max = maxVal, step = step, defaultValue = defaultVal,
            format = formatFn,
            canModify = IsPlacardEnabled,
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
                self:ApplyVisualSettings()
            end,
        })
    end

    AddPlacardSlider("infoPlacardWidth", "Info Placard Width", "Fixed width in pixels of the Dynamic Info Placard.", 100, 360, 2, 200, function(v) return string.format("%d px", v) end)
    AddPlacardSlider("cellPadding", "Info Cell Padding", "Inner padding around placard content in pixels.", 2, 20, 1, 10, function(v) return string.format("%d px", v) end)
    AddPlacardSlider("infoPlacardOffsetY", "Info Placard Vertical Offset", "Fine vertical offset adjustment for the Dynamic Info Placard.", -30, 30, 1, 0, function(v) return string.format("%d px", v) end)
    AddPlacardSlider("rowDividerOpacityPct", "Row Divider Line Opacity (%)", "Opacity of the horizontal divider line between Row 1 and Row 2.", 0, 100, 5, 60, function(v) return string.format("%d%%", v) end)
    AddPlacardSlider("rowExtraPadding", "Row 2 Vertical Padding", "Extra spacing between Row 1 and Row 2 inside the Dynamic Info Placard.", 0, 20, 1, 4, function(v) return string.format("%d px", v) end)

    -- =========================================================================
    -- SUB-SECTION 3A: Row 1 — Trackers & Bags
    -- =========================================================================
    ctx:AddHeader("3A. Row 1 — Trackers & Bags")

    AddPlacardSlider("row1TextSize", "Row 1 Font Size", "Font and icon size used for Row 1 (Coordinates/Gold and Bag/Ammo trackers).", 8, 18, 1, 12, function(v) return string.format("%d px", v) end)

    ctx:AddDropdown({
        key = "row1LeftMode",
        name = "Row 1 Left Display",
        tooltip = "Choose what appears on the left side of Row 1: Coordinates (default, hides built-in minimap coordinates), Current Gold (with gold/silver/copper icons), or None.",
        defaultValue = "coords",
        options = ROW1_LEFT_OPTIONS,
        canModify = IsPlacardEnabled,
        get = function()
            return GetRow1LeftMode(GetDB())
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then
                mdb.row1LeftMode = (val == "gold" or val == "none") and val or "coords"
            end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddCheckbox({
        key = "showBagSlots",
        name = "Show Inventory Free Slots",
        tooltip = "Displays remaining free general bag slots far-right in Row 1 Column 2.",
        defaultValue = true,
        canModify = IsPlacardEnabled,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showBagSlots ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showBagSlots = val end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddCheckbox({
        key = "showArrowsRemaining",
        name = "Show Arrows / Ammo Remaining",
        tooltip = "Displays equipped arrows or bullets expanding left in Row 1 Column 2 for Hunters, Warriors, and Rogues with a Bow, Crossbow, or Gun equipped.",
        defaultValue = true,
        canModify = IsPlacardEnabled,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showArrowsRemaining ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showArrowsRemaining = val end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddCheckbox({
        key = "showSoulShards",
        name = "Show Soul Shards (Warlock)",
        tooltip = "Displays Soul Shards expanding left in Row 1 Column 2 (Warlock only).",
        defaultValue = true,
        canModify = IsPlacardEnabled,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showSoulShards ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showSoulShards = val end
            self:ApplyVisualSettings()
        end,
    })

    AddPlacardSlider("bagWarnThreshold", "Inventory Low Warning Threshold", "Free general bag slots threshold to trigger low-space warning highlight / raid warning (0 = Off).", 0, 20, 1, 3, function(v)
        return (v <= 0) and "Off" or string.format("%d", v)
    end)

    AddPlacardSlider("ammoWarnThreshold", "Ammo Low Warning Threshold", "Equipped arrow/bullet count threshold to trigger low-ammo warning highlight / raid warning (0 = Off).", 0, 1000, 10, 200, function(v)
        return (v <= 0) and "Off" or string.format("%d", v)
    end)

    ctx:AddCheckbox({
        key = "bagRaidWarnings",
        name = "Include Raid Warnings (Inventory & Ammo)",
        tooltip = "Shows a local center-screen Raid Warning once when bag space or ammo drops below the low threshold (orange) or hits 0 remaining (red).",
        defaultValue = false,
        canModify = IsPlacardEnabled,
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
            self:ApplyVisualSettings()
        end,
    })

    -- =========================================================================
    -- SUB-SECTION 3B: Row 2 — Farming Data
    -- =========================================================================
    ctx:AddHeader("3B. Row 2 — Farming Data")

    ctx:AddCheckbox({
        key = "showFarmingRow",
        name = "Enable Farming Data Row (Time to Level & Kills)",
        tooltip = "Displays the 2-column Row 2 farming bar (Estimated Time to Level left-justified, Estimated Mob Kills right-justified).",
        defaultValue = true,
        canModify = IsPlacardEnabled,
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.showFarmingRow ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.showFarmingRow = val end
            self:ApplyVisualSettings()
        end,
    })

    AddPlacardSlider("row2TextSize", "Row 2 Font Size", "Font and icon size used for Row 2 (Estimated Time to Level and Mob Kills).", 8, 18, 1, 12, function(v) return string.format("%d px", v) end)
end

YRG:RegisterModule("MinimapExpTracker", ExpTracker)
