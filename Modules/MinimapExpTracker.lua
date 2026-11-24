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

local COORD_NUDGE_DIR_OPTIONS = {
    { value = "UP",   label = "Up (Above EXP Ring Rim, Default)" },
    { value = "DOWN", label = "Down (Below % Badge)" },
}

local MUI = YRG.MinimapUI or {}
YRG.MinimapUI = MUI

local ExpTracker = {
    name = "Minimap EXP Tracker",
    description = "Radial EXP & Rested ring with a bottom-fixed EXP badge and minimap header enhancements.",
    defaultEnabled = true,
    defaults = {
        enabled = true,
        masterScale = 1.0,
        mapScale = 1.0,
        fillStyle = "conduit",
        bubbleOverlay = "bevel",
        bubbleOverlayOpacityPct = 85,
        colorScheme = "blue",
        showRestedBar = true,
        hideAtMaxLevel = false,
        hideDefaultExpBar = true,
        alwaysShowLocalTime = true,
        hideAddonButtons = true,
        centerMinimapHeader = true,
        matchPlacardWidth = true,

        -- Bottom-Fixed EXP Percentage Placard
        showDecimals = true,
        expTextSize = 16,
        nudgeBuiltInCoords = true,
        nudgeBuiltInCoordsDir = "UP",
    }
}

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
MUI.ApplyHeaderNineSliceStyle = ApplyHeaderNineSliceStyle

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

local function SafeRegionCenterY(region)
    if not region or type(region.GetCenter) ~= "function" then return nil end
    local ok, _, y = pcall(region.GetCenter, region)
    if not ok then return nil end
    return YRG.SafeOptionalNumber(y)
end

local function SafeRegionTop(region)
    if not region or type(region.GetTop) ~= "function" then return nil end
    local ok, t = pcall(region.GetTop, region)
    if not ok then return nil end
    return YRG.SafeOptionalNumber(t)
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

MUI.SafeRegionCenterY = SafeRegionCenterY
MUI.SafeRegionTop = SafeRegionTop
MUI.SafeRegionBottom = SafeRegionBottom
MUI.SafeRegionScale = SafeRegionScale
MUI.SafeRegionCenterX = SafeRegionCenterX

local headerCenteringGuard = false
local hookedHeaderAnchorFrames = setmetatable({}, { __mode = "k" })

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
    local infoFrame = MUI.infoFrame
    if infoFrame and infoFrame.IsShown and infoFrame:IsShown() then
        local w = SafeRegionWidth(infoFrame)
        local s = SafeRegionScale(infoFrame, 1)
        if w and s > 0 then
            return w * s, s
        end
    end
    local infoDB = YRG:GetModuleDB("DynamicInfoPlacard")
    local clusterScale = SafeRegionScale(MinimapCluster or Minimap, 1)
    if infoDB and infoDB.enabled then
        local fallbackW = YRG.SafeNumber(infoDB.infoPlacardWidth, YRG.SafeNumber(db and db.infoPlacardWidth, 254))
        if clusterScale > 0 and fallbackW > 0 then
            return fallbackW * clusterScale, clusterScale
        end
    end
    return nil, clusterScale
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

local function IsInfoPlacardTitleAnchored()
    local infoDB = YRG:GetModuleDB("DynamicInfoPlacard")
    if not infoDB or not infoDB.enabled then
        return false
    end
    return (infoDB.placardAnchorPoint or "ZONE_TITLE") == "ZONE_TITLE"
end

local function GetZoneTitleAnchorFrame()
    local mc = MinimapCluster
    local candidates = {
        (mc and mc.BorderTop) or false,
        _G["MinimapBorderTop"] or false,
        (mc and mc.ZoneTextButton) or false,
        _G["MinimapZoneTextButton"] or false,
        (mc and mc.HeaderFrame) or false,
    }
    for _, f in ipairs(candidates) do
        if f and (not f.IsShown or f:IsShown()) then
            local top = SafeRegionTop(f)
            local bot = SafeRegionBottom(f)
            if top and bot and top > bot then
                return f
            end
        end
    end
    return nil
end
MUI.GetZoneTitleAnchorFrame = GetZoneTitleAnchorFrame

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

    local infoShown = (MUI.infoFrame and MUI.infoFrame.IsShown and MUI.infoFrame:IsShown()) and true or false
    local shouldStretch = IsInfoPlacardTitleAnchored() and infoShown
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

local mapScaleAnchorGuard = false

local function GetMinimapScaleUnitTarget()
    if MinimapCluster and MinimapCluster.MinimapContainer and Minimap
        and type(Minimap.GetParent) == "function" and Minimap:GetParent() == MinimapCluster.MinimapContainer then
        local prot = type(MinimapCluster.MinimapContainer.IsProtected) == "function"
            and MinimapCluster.MinimapContainer:IsProtected()
        if not prot then
            return MinimapCluster.MinimapContainer
        end
    end
    if Minimap and not (type(Minimap.IsProtected) == "function" and Minimap:IsProtected()) then
        return Minimap
    end
    return nil
end

local function IsMinimapHeaderOnBottom()
    if MinimapCluster then
        if type(MinimapCluster.IsHeaderUnderneath) == "function" then
            local ok, v = pcall(MinimapCluster.IsHeaderUnderneath, MinimapCluster)
            if ok and v ~= nil then return v and true or false end
        end
        if MinimapCluster.headerUnderneath ~= nil then
            return MinimapCluster.headerUnderneath and true or false
        end
    end
    local hdr = GetZoneTitleAnchorFrame()
    local hy = SafeRegionCenterY(hdr)
    local hScale = SafeRegionScale(hdr, 1)
    local my = SafeRegionCenterY(Minimap)
    local mScale = SafeRegionScale(Minimap, 1)
    if hy and my then
        return (hy * hScale) < (my * mScale)
    end
    return false
end

local function GetMinimapVisualScreenBoundsY()
    local visBot, visTop = nil, nil
    local function Expand(f, topInsetRatio, botInsetRatio)
        if not f or (type(f.IsShown) == "function" and not f:IsShown()) then return end
        local b = SafeRegionBottom(f)
        local t = SafeRegionTop(f)
        local sc = SafeRegionScale(f, 0)
        if not (b and t and t > b and sc and sc > 0) then return end
        local h = t - b
        local sb = (b + h * (botInsetRatio or 0)) * sc
        local st = (t - h * (topInsetRatio or 0)) * sc
        visBot = visBot and math.min(visBot, sb) or sb
        visTop = visTop and math.max(visTop, st) or st
    end
    if Minimap then Expand(Minimap, 0, 0) end
    if ExpTracker.container then Expand(ExpTracker.container, 42 / 512, 56 / 512) end
    if ExpTracker.expFrame then Expand(ExpTracker.expFrame, 0, 0) end
    return visBot, visTop
end

local function GetHeaderVisualScreenBoundsY(roots)
    local hBot, hTop = nil, nil
    local seen = {}
    local function Expand(f)
        if not f or seen[f] or (type(f.IsShown) == "function" and not f:IsShown()) then return end
        seen[f] = true
        local b = SafeRegionBottom(f)
        local t = SafeRegionTop(f)
        local sc = SafeRegionScale(f, 0)
        if b and t and t > b and sc and sc > 0 then
            hBot = hBot and math.min(hBot, b * sc) or (b * sc)
            hTop = hTop and math.max(hTop, t * sc) or (t * sc)
        end
    end
    for _, entry in ipairs(roots or {}) do
        Expand(entry.frame)
    end
    if MinimapCluster then
        Expand(MinimapCluster.BorderTop)
        Expand(MinimapCluster.ZoneTextButton)
    end
    Expand(_G["MinimapBorderTop"])
    Expand(_G["MinimapZoneTextButton"])
    return hBot, hTop
end

local function ApplyMinimapHeaderCenter(db)
    if headerCenteringGuard then return end
    if InCombatLockdown() then
        ExpTracker._pendingHeaderCenter = true
        return
    end

    local roots = GetMinimapHeaderAnchors()
    if not roots then return end

    for _, entry in ipairs(roots) do
        local f = entry.frame
        if not hookedHeaderAnchorFrames[f] and type(f.SetPoint) == "function" then
            hookedHeaderAnchorFrames[f] = true
            pcall(hooksecurefunc, f, "SetPoint", function(frame)
                if headerCenteringGuard then return end
                frame._yrgPreShiftPoints = nil
                frame._yrgCenterApplied = nil
            end)
        end
    end

    local shouldCenter = IsInfoPlacardTitleAnchored() or (db and db.enabled and (db.centerMinimapHeader ~= false)) or false
    local mapUnit = GetMinimapScaleUnitTarget()
    local mapUnitScale = (db and db.enabled and db.mapScale) or 1.0
    local headerOnBottom = IsMinimapHeaderOnBottom()
    local headerAnchoredToMap = false
    if mapUnit then
        local mapSet = { [mapUnit] = true }
        if Minimap then mapSet[Minimap] = true end
        for _, entry in ipairs(roots) do
            if IsFramePointAnchoredToAny(entry.frame, mapSet) then
                headerAnchoredToMap = true
                break
            end
        end
    end

    local mcScale = SafeRegionScale((mapUnit and mapUnit.GetParent and mapUnit:GetParent()) or MinimapCluster, 1)
    local mapVisBotScreen, mapVisTopScreen = GetMinimapVisualScreenBoundsY()
    local hdrCurBotScreen, hdrCurTopScreen = GetHeaderVisualScreenBoundsY(roots)

    local desiredShiftScreenY = 0
    if db and db.enabled and headerOnBottom and (not headerAnchoredToMap) and mapUnit and math.abs(mapUnitScale - 1.0) > 0.001 then
        local targetH = (type(mapUnit.GetHeight) == "function" and YRG.SafeNumber(mapUnit:GetHeight(), 0)) or 140
        if targetH <= 0 then targetH = 140 end
        local unitSpan = targetH
        local tTop = SafeRegionTop(mapUnit)
        local tScale = SafeRegionScale(mapUnit, mcScale * mapUnitScale)
        if tTop and mapVisBotScreen and tScale > 0 and (tTop * tScale) > mapVisBotScreen then
            unitSpan = ((tTop * tScale) - mapVisBotScreen) / tScale
        end
        desiredShiftScreenY = unitSpan * (1 - mapUnitScale) * mcScale
    end

    if db and db.enabled and (not headerAnchoredToMap) and hdrCurBotScreen and hdrCurTopScreen then
        local refEntry = roots[1]
        local refF = refEntry and refEntry.frame
        local refBase = refF and (refF._yrgPreShiftPoints or refEntry.pts)
        local refScale = refF and SafeRegionScale(refF, mcScale) or mcScale
        if refEntry and refBase and refBase[1] and refEntry.pts and refEntry.pts[1] and refScale > 0 then
            local appliedCurY = (refEntry.pts[1].y - refBase[1].y) * refScale
            local baseHdrTopScreen = hdrCurTopScreen - appliedCurY
            local baseHdrBotScreen = hdrCurBotScreen - appliedCurY
            local minGap = 4 * mcScale
            if headerOnBottom and mapVisBotScreen then
                local maxAllowedTop = mapVisBotScreen - minGap
                if (baseHdrTopScreen + desiredShiftScreenY) > maxAllowedTop then
                    desiredShiftScreenY = maxAllowedTop - baseHdrTopScreen
                end
            elseif (not headerOnBottom) and mapVisTopScreen then
                local minAllowedBot = mapVisTopScreen + minGap
                if (baseHdrBotScreen + desiredShiftScreenY) < minAllowedBot then
                    desiredShiftScreenY = minAllowedBot - baseHdrBotScreen
                end
            end
        end
    end

    if (not shouldCenter) and math.abs(desiredShiftScreenY) < 0.35 then
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
    local deltaScreenX = 0
    if shouldCenter and mapX and visScreenX and mapScale > 0 then
        deltaScreenX = (mapX * mapScale) - visScreenX
    end

    local needShiftY = false
    for _, entry in ipairs(roots) do
        local f = entry.frame
        local fScale = SafeRegionScale(f, 1)
        local basePts = f._yrgPreShiftPoints or entry.pts
        if fScale > 0 and basePts and basePts[1] and entry.pts and entry.pts[1] then
            local wantY = basePts[1].y + (desiredShiftScreenY / fScale)
            if math.abs(entry.pts[1].y - wantY) >= 0.35 then
                needShiftY = true
                break
            end
        end
    end

    if math.abs(deltaScreenX) < 0.35 and not needShiftY then
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
            local basePts = f._yrgPreShiftPoints or entry.pts
            local shiftLocalX = deltaScreenX / fScale
            local shiftLocalY = desiredShiftScreenY / fScale
            local ok = false
            if #entry.pts == 1 then
                local p = entry.pts[1]
                local bp = basePts[1] or p
                ok = pcall(f.SetPoint, f, p.pt, p.relTo, p.relPt, p.x + shiftLocalX, bp.y + shiftLocalY)
            elseif type(f.ClearAllPoints) == "function" then
                ok = pcall(function()
                    f:ClearAllPoints()
                    for idx, p in ipairs(entry.pts) do
                        local bp = basePts[idx] or p
                        f:SetPoint(p.pt, p.relTo, p.relPt, p.x + shiftLocalX, bp.y + shiftLocalY)
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

local WELL_RESTED_SPELL_ID = 1225478
local LEGACY_TREE_SYSTEM_ID = 45
local RESTED_BASE_CAP_RATIO = 1.5           -- 150% of current level
local RESTED_BASE_RATE_PER_HOUR = 0.05 / 8  -- 5% of a level per 8 hours while resting (0.625%/hr)
local WELL_RESTED_PER_RANK_BONUS = 0.04     -- +4% max cap & recovery rate per Legacy rank

local function IsMatchingWellRestedName(rawName)
    local clean = YRG.SafeString(rawName, nil)
    if not clean then return false end
    local low = clean:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return low == "well rested" or low == "well-rested"
end

local function IsWellRestedDefinition(defInfo)
    if type(defInfo) ~= "table" then return false end
    local defSpellID = YRG.SafeOptionalNumber(defInfo.spellID)
    if defSpellID == WELL_RESTED_SPELL_ID then
        return true
    end
    if IsMatchingWellRestedName(defInfo.overrideName) then
        return true
    end
    if defSpellID then
        local spellName = nil
        if C_Spell and type(C_Spell.GetSpellName) == "function" then
            local okName, sName = pcall(C_Spell.GetSpellName, defSpellID)
            spellName = okName and sName or nil
        elseif type(GetSpellInfo) == "function" then
            local okName, sName = pcall(GetSpellInfo, defSpellID)
            spellName = okName and sName or nil
        end
        if IsMatchingWellRestedName(spellName) then
            return true
        end
    end
    return false
end

local function GetWellRestedLegacyRanks()
    if not C_Traits or type(C_Traits.GetConfigIDBySystemID) ~= "function" then
        return 0
    end
    local okCfg, configID = pcall(C_Traits.GetConfigIDBySystemID, LEGACY_TREE_SYSTEM_ID)
    configID = okCfg and YRG.SafeOptionalNumber(configID) or nil
    if not configID then
        return 0
    end

    local okInfo, configInfo = pcall(C_Traits.GetConfigInfo, configID)
    if not okInfo or type(configInfo) ~= "table" or type(configInfo.treeIDs) ~= "table" then
        return 0
    end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if okNodes and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local okNode, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                if okNode and type(nodeInfo) == "table" then
                    local entryList = (type(nodeInfo.entryIDs) == "table" and #nodeInfo.entryIDs > 0) and nodeInfo.entryIDs or nil
                    if not entryList and type(nodeInfo.activeEntry) == "table" and nodeInfo.activeEntry.entryID then
                        entryList = { nodeInfo.activeEntry.entryID }
                    end
                    if entryList then
                        for _, entryID in ipairs(entryList) do
                            local okEntry, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
                            if okEntry and type(entryInfo) == "table" and entryInfo.definitionID then
                                local okDef, defInfo = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
                                if okDef and IsWellRestedDefinition(defInfo) then
                                    local rank = YRG.SafeOptionalNumber(nodeInfo.currentRank)
                                    if rank == nil then
                                        rank = YRG.SafeOptionalNumber(nodeInfo.activeRank) or YRG.SafeOptionalNumber(nodeInfo.ranksPurchased) or 0
                                    end
                                    return math.max(0, rank)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return 0
end

local function FormatRestedDuration(seconds)
    if seconds == nil or seconds <= 0 then
        return "Full"
    end
    if seconds < 60 then
        return string.format("%ds", math.max(1, math.ceil(seconds)))
    end
    local totalMins = math.max(1, math.floor((seconds / 60) + 0.5))
    local days = math.floor(totalMins / 1440)
    local remMins = totalMins % 1440
    local hours = math.floor(remMins / 60)
    local mins = remMins % 60
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, mins)
    end
    return string.format("%dm", mins)
end

local function ShowExpTooltip(ownerFrame)
    local curXP = YRG.SafeNumber(UnitXP("player"), 0)
    local maxXP = math.max(YRG.SafeNumber(UnitXPMax("player"), 1), 1)
    local restedXP = YRG.SafeNumber(GetXPExhaustion(), 0)
    local remXP = math.max(maxXP - curXP, 0)
    local pct = (curXP / maxXP) * 100
    local restedPct = (restedXP / maxXP) * 100

    local level = YRG.SafeNumber(UnitLevel("player"), 1)
    local maxLevel = (GetMaxPlayerLevel and YRG.SafeNumber(GetMaxPlayerLevel(), 60)) or 60
    local wellRestedRanks = GetWellRestedLegacyRanks()
    local wellRestedMult = 1 + (WELL_RESTED_PER_RANK_BONUS * wellRestedRanks)
    local maxRestedCapPct = (RESTED_BASE_CAP_RATIO * 100) * wellRestedMult
    local maxRestedXP = maxXP * RESTED_BASE_CAP_RATIO * wellRestedMult
    local remRestedXP = math.max(0, maxRestedXP - restedXP)
    local remRestedPct = math.max(0, maxRestedCapPct - restedPct)
    local restedXPPerSec = (maxXP * RESTED_BASE_RATE_PER_HOUR * wellRestedMult) / 3600
    local estSecondsToFull = (restedXPPerSec > 0) and (remRestedXP / restedXPPerSec) or 0

    GameTooltip:SetOwner(ownerFrame, "ANCHOR_BOTTOM")
    GameTooltip:SetText("YRG Minimap EXP Tracker", 1.0, 0.82, 0.0)
    GameTooltip:AddDoubleLine("Current XP:", string.format("%d / %d (%.1f%%)", curXP, maxXP, pct), 0.9, 0.9, 0.9, 1, 1, 1)
    GameTooltip:AddDoubleLine("Remaining XP:", tostring(remXP), 0.9, 0.9, 0.9, 1, 0.82, 0)
    if restedXP > 0 then
        GameTooltip:AddDoubleLine("Rested Bonus:", string.format("%d (%.1f%%)", restedXP, restedPct), 0.4, 0.75, 1.0, 0.4, 0.75, 1.0)
    else
        GameTooltip:AddDoubleLine("Rested Bonus:", "None (0%)", 0.4, 0.75, 1.0, 0.65, 0.65, 0.65)
    end
    if level < maxLevel or restedXP > 0 then
        local restedLabel = wellRestedRanks > 0
            and string.format("Est. Time to Full (Well Rested %d):", wellRestedRanks)
            or "Est. Time to Full:"
        local restedRight = remRestedXP <= 0
            and "Full (0.0% remaining)"
            or string.format("%s (%.1f%% remaining)", FormatRestedDuration(estSecondsToFull), remRestedPct)
        GameTooltip:AddDoubleLine(restedLabel, restedRight, 0.78, 0.45, 1.0, 0.78, 0.45, 1.0)
    end

    if type(MUI.AppendKillPaceTooltipLines) == "function" then
        MUI.AppendKillPaceTooltipLines(remXP)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-Click: Open EXP Tracker Settings", 0.65, 0.65, 0.65)
    if type(MUI.ResetSessionTrackers) == "function" then
        GameTooltip:AddLine("Right-Click: Reset Kill Pace Trackers", 0.65, 0.65, 0.65)
    end
    GameTooltip:Show()
end

local function OnExpPlacardMouseUp(frame, button)
    if button == "LeftButton" then
        YRG:OpenSettings("MinimapExpTracker")
    elseif button == "RightButton" and type(MUI.ResetSessionTrackers) == "function" then
        MUI.ResetSessionTrackers()
        if GameTooltip and GameTooltip:IsOwned(frame) then
            ShowExpTooltip(frame)
        end
    end
end

function MUI.GetExpAnchorInfo()
    local db = YRG:GetModuleDB("MinimapExpTracker")
    if not db or not db.enabled then return nil end
    if not ExpTracker.container or not ExpTracker.container:IsShown() then return nil end
    if not ExpTracker.expFrame or not ExpTracker.expFrame:IsShown() then return nil end
    local mapWidth = (Minimap and Minimap:GetWidth()) or 140
    local baseRingSize = mapWidth * (512 / 368)
    local ringBottomRimY = baseRingSize * (56 / 512)
    local ringTopRimY = -baseRingSize * (42 / 512)
    local expH = (ExpTracker.expFrame.GetHeight and YRG.SafeNumber(ExpTracker.expFrame:GetHeight(), 20)) or 20
    return {
        container = ExpTracker.container,
        expFrame = ExpTracker.expFrame,
        ringBottomRimY = ringBottomRimY,
        ringTopRimY = ringTopRimY,
        expH = expH,
    }
end

local coordNudgeGuard = false
local coordNudgeScheduled = false
local hookedCoordFrames = setmetatable({}, { __mode = "k" })

local function IsPlacardShowingCoords()
    if MUI.placardShowingCoords ~= nil then
        return MUI.placardShowingCoords and true or false
    end
    local infoDB = YRG:GetModuleDB("DynamicInfoPlacard")
    if not infoDB or not infoDB.enabled then
        return false
    end
    local mode = infoDB.row1LeftMode
    if mode == nil and infoDB.showCoordinates == false then
        mode = "none"
    end
    return mode == "coords"
end

local function GetBuiltInCoordFrames()
    local frames = {}
    local seen = {}
    local function TryAdd(frame)
        if type(frame) ~= "table" or seen[frame] or type(frame.SetPoint) ~= "function" then
            return
        end
        local cur = frame
        for _ = 1, 6 do
            local okP, par = pcall(cur.GetParent, cur)
            if not okP or not par then break end
            if seen[par] then return end
            cur = par
        end
        seen[frame] = true
        table.insert(frames, frame)
    end
    TryAdd(MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.PlayerCoords)
    TryAdd(MinimapCluster and MinimapCluster.PlayerCoords)
    TryAdd(Minimap and Minimap.PlayerCoords)
    TryAdd(_G["MinimapCoordinates"])
    TryAdd(Minimap and Minimap.CoordinateFrame)
    TryAdd(Minimap and Minimap.Coordinates)
    TryAdd(_G["MinimapCoordinatesText"])
    return frames
end

local function ShouldNudgeBuiltInCoords(db)
    if not db or not db.enabled or db.nudgeBuiltInCoords == false then
        return false
    end
    if not (ExpTracker.container and ExpTracker.container.IsShown and ExpTracker.container:IsShown()) then
        return false
    end
    if not (ExpTracker.expFrame and ExpTracker.expFrame.IsShown and ExpTracker.expFrame:IsShown()) then
        return false
    end
    return not IsPlacardShowingCoords()
end

local function UpdateBuiltInCoordsNudge()
    if coordNudgeGuard then return end
    local db = YRG:GetModuleDB("MinimapExpTracker")
    local coordFrames = GetBuiltInCoordFrames()
    if #coordFrames == 0 then return end

    local shouldNudge = ShouldNudgeBuiltInCoords(db)

    for _, frame in ipairs(coordFrames) do
        if not hookedCoordFrames[frame] then
            hookedCoordFrames[frame] = true
            pcall(hooksecurefunc, frame, "SetPoint", function(f)
                if coordNudgeGuard then return end
                f._yrgOrigCoordPts = nil
                f._yrgOrigCoordCenterDX = nil
                f._yrgCoordNudgeApplied = nil
                if not coordNudgeScheduled and C_Timer and type(C_Timer.After) == "function" then
                    coordNudgeScheduled = true
                    C_Timer.After(0, function()
                        coordNudgeScheduled = false
                        UpdateBuiltInCoordsNudge()
                    end)
                end
            end)
            if type(frame.HookScript) == "function" then
                pcall(frame.HookScript, frame, "OnShow", function()
                    if coordNudgeGuard then return end
                    if not coordNudgeScheduled and C_Timer and type(C_Timer.After) == "function" then
                        coordNudgeScheduled = true
                        C_Timer.After(0, function()
                            coordNudgeScheduled = false
                            UpdateBuiltInCoordsNudge()
                        end)
                    end
                end)
            end
        end

        local okProt, isProt = pcall(function()
            return type(frame.IsProtected) == "function" and frame:IsProtected()
        end)
        local locked = InCombatLockdown() and okProt and isProt

        if not shouldNudge then
            if frame._yrgCoordNudgeApplied then
                if locked then
                    ExpTracker._pendingCoordNudge = true
                else
                    local savedPts = frame._yrgOrigCoordPts
                    coordNudgeGuard = true
                    if savedPts and #savedPts > 0 then
                        pcall(function()
                            if type(frame.ClearAllPoints) == "function" then
                                frame:ClearAllPoints()
                            end
                            for _, p in ipairs(savedPts) do
                                frame:SetPoint(p.pt, p.relTo, p.relPt, p.x, p.y)
                            end
                        end)
                    end
                    frame._yrgCoordNudgeApplied = nil
                    frame._yrgOrigCoordPts = nil
                    frame._yrgOrigCoordCenterDX = nil
                    coordNudgeGuard = false
                end
            end
        else
            if locked then
                ExpTracker._pendingCoordNudge = true
            else
                local frameScale = SafeRegionScale(frame, 1)
                if not frame._yrgOrigCoordPts and not frame._yrgCoordNudgeApplied
                    and type(frame.GetNumPoints) == "function" and type(frame.GetPoint) == "function" then
                    local pts = {}
                    local n = YRG.SafeNumber(frame:GetNumPoints(), 0)
                    for i = 1, n do
                        local okP, pt, relTo, relPt, x, y = pcall(frame.GetPoint, frame, i)
                        if okP and pt then
                            table.insert(pts, {
                                pt = pt,
                                relTo = relTo,
                                relPt = relPt or pt,
                                x = YRG.SafeNumber(x, 0),
                                y = YRG.SafeNumber(y, 0),
                            })
                        end
                    end
                    if #pts > 0 then
                        frame._yrgOrigCoordPts = pts
                    end
                    local fCX = SafeRegionCenterX(frame)
                    local mCX = SafeRegionCenterX(Minimap)
                    local mScale = SafeRegionScale(Minimap, frameScale)
                    if fCX and mCX then
                        local dxScreen = (fCX * frameScale) - (mCX * mScale)
                        frame._yrgOrigCoordCenterDX = (math.abs(dxScreen) <= (6 * mScale)) and 0 or dxScreen
                    else
                        frame._yrgOrigCoordCenterDX = 0
                    end
                end

                local expFrame = ExpTracker.expFrame
                local expScale = SafeRegionScale(expFrame, frameScale)
                local mapScale = SafeRegionScale(Minimap, frameScale)
                local xOff = (frame._yrgOrigCoordCenterDX or 0) / math.max(frameScale, 0.01)
                local dir = (db and db.nudgeBuiltInCoordsDir == "DOWN") and "DOWN" or "UP"

                local wantPt, wantRel, wantRelPt, wantX, wantY
                if dir == "UP" then
                    local mapBot = SafeRegionBottom(Minimap)
                    local expTop = SafeRegionTop(expFrame)
                    if mapBot and expTop then
                        local clearAboveExp = (expTop * expScale) - (mapBot * mapScale) + (2 * expScale)
                        local screenDeltaY = math.max(14 * mapScale, clearAboveExp)
                        wantPt, wantRel, wantRelPt = "BOTTOM", Minimap, "BOTTOM"
                        wantX, wantY = xOff, screenDeltaY / math.max(frameScale, 0.01)
                    else
                        wantPt, wantRel, wantRelPt = "BOTTOM", expFrame, "TOP"
                        wantX, wantY = xOff, (2 * expScale) / math.max(frameScale, 0.01)
                    end
                else
                    wantPt, wantRel, wantRelPt = "TOP", expFrame, "BOTTOM"
                    wantX, wantY = xOff, -(2 * expScale) / math.max(frameScale, 0.01)
                end

                local alreadyPlaced = false
                if frame._yrgCoordNudgeApplied and type(frame.GetNumPoints) == "function"
                    and YRG.SafeNumber(frame:GetNumPoints(), 0) == 1 and type(frame.GetPoint) == "function" then
                    local okP, pt, relTo, relPt, cx, cy = pcall(frame.GetPoint, frame, 1)
                    if okP and pt == wantPt and relTo == wantRel and relPt == wantRelPt
                        and math.abs(YRG.SafeNumber(cx, 0) - wantX) < 0.35
                        and math.abs(YRG.SafeNumber(cy, 0) - wantY) < 0.35 then
                        alreadyPlaced = true
                    end
                end

                if not alreadyPlaced then
                    coordNudgeGuard = true
                    pcall(function()
                        if type(frame.ClearAllPoints) == "function" then
                            frame:ClearAllPoints()
                        end
                        frame:SetPoint(wantPt, wantRel, wantRelPt, wantX, wantY)
                    end)
                    frame._yrgCoordNudgeApplied = true
                    coordNudgeGuard = false
                end
            end
        end
    end
end

MUI.UpdateBuiltInCoordinatesNudge = UpdateBuiltInCoordsNudge

local STRATA_RANK = {
    BACKGROUND = 1,
    LOW = 2,
    MEDIUM = 3,
    HIGH = 4,
    DIALOG = 5,
    FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8,
}

local function GetMinimapOverlayBaseLayer()
    local bestStrata = "LOW"
    local bestRank = 0
    local maxLvl = 1
    for _, ref in ipairs({
        Minimap or false,
        MinimapCluster or false,
        (MinimapCluster and MinimapCluster.BorderTop) or false,
        (MinimapCluster and MinimapCluster.ZoneTextButton) or false,
    }) do
        if ref then
            local st = ref.GetFrameStrata and ref:GetFrameStrata()
            local rk = st and STRATA_RANK[st] or 0
            if rk > bestRank then
                bestRank = rk
                bestStrata = st
            end
            local lvl = ref.GetFrameLevel and YRG.SafeNumber(ref:GetFrameLevel(), 0) or 0
            if lvl > maxLvl then
                maxLvl = lvl
            end
        end
    end
    return bestStrata, maxLvl
end
MUI.GetMinimapOverlayBaseLayer = GetMinimapOverlayBaseLayer

local function ApplyExpHitBoxLayering(hitFrame)
    if not hitFrame then return end
    local bestStrata, maxLvl = GetMinimapOverlayBaseLayer()
    hitFrame:SetFrameStrata(bestStrata)
    hitFrame:SetFrameLevel(maxLvl + 2)
end

function ExpTracker:EnsureFrames()
    if self.container then return end

    local container = CreateFrame("Frame", "YRGMinimapExpContainer", Minimap)
    container:SetFrameStrata("BACKGROUND")
    container:SetFrameLevel(math.max((Minimap:GetFrameLevel() or 1) - 1, 0))
    container:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    container:EnableMouse(false)
    self.container = container
    MUI.ringContainer = container

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

    -- Bottom-Fixed EXP Percentage Placard tucked cleanly between Minimap & EXP Ring (BACKGROUND strata)
    local expFrame = CreateFrame("Frame", "YRGMinimapExpPlacard", borderFrame, "BackdropTemplate")
    expFrame:SetFrameLevel(borderFrame:GetFrameLevel() + 4)
    expFrame:EnableMouse(true)
    expFrame:SetScript("OnEnter", ShowExpTooltip)
    expFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    expFrame:SetScript("OnMouseUp", OnExpPlacardMouseUp)
    self.expFrame = expFrame
    MUI.expFrame = expFrame

    -- Invisible interactive hitbox over the exposed badge area below Minimap so hover/clicks
    -- trigger tooltips cleanly without pulling the visual EXP badge above Minimap borders.
    local expHitFrame = CreateFrame("Frame", "YRGMinimapExpHitBox", expFrame)
    ApplyExpHitBoxLayering(expHitFrame)
    expHitFrame:EnableMouse(true)
    if type(expHitFrame.SetMouseMotionEnabled) == "function" then expHitFrame:SetMouseMotionEnabled(true) end
    if type(expHitFrame.SetMouseClickEnabled) == "function" then expHitFrame:SetMouseClickEnabled(true) end
    expHitFrame:SetScript("OnEnter", function() ShowExpTooltip(expFrame) end)
    expHitFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    expHitFrame:SetScript("OnMouseUp", function(_, btn) OnExpPlacardMouseUp(expFrame, btn) end)
    self.expHitFrame = expHitFrame

    local pctText = expFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pctText:SetPoint("CENTER", expFrame, "CENTER", 0, 0)
    pctText:SetTextColor(1.0, 0.84, 0.35, 1.0)
    pctText:SetShadowColor(0, 0, 0, 1)
    pctText:SetShadowOffset(1, -1)
    self.pctText = pctText
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
local hookedClusterClamp = false
local savedClusterClampInsets = nil
local clampInsetsModified = false
local settingMinimapClampGuard = false
local lastClampInsets = nil
local hookedMapUnitFrames = setmetatable({}, { __mode = "k" })

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

local function ComputeMinimapVisualBounds(db)
    if not MinimapCluster then return nil end

    local hasRing = (db and db.enabled and ExpTracker.container and ExpTracker.container:IsShown()) and true or false
    local infoF = MUI.infoFrame
    local hasInfo = (infoF and type(infoF.IsShown) == "function" and infoF:IsShown()) and true or false
    local hasAny = hasRing or hasInfo

    local cL = YRG.SafeOptionalNumber(MinimapCluster.GetLeft and MinimapCluster:GetLeft())
    local cR = YRG.SafeOptionalNumber(MinimapCluster.GetRight and MinimapCluster:GetRight())
    local cB = YRG.SafeOptionalNumber(MinimapCluster.GetBottom and MinimapCluster:GetBottom())
    local cT = YRG.SafeOptionalNumber(MinimapCluster.GetTop and MinimapCluster:GetTop())
    local cScale = YRG.SafeOptionalNumber(MinimapCluster.GetEffectiveScale and MinimapCluster:GetEffectiveScale())
    if not (cL and cR and cB and cT and cScale and cScale > 0) then
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, hasAny
    end

    local uLeft, uRight, uBottom, uTop = nil, nil, nil, nil

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

        uLeft = uLeft and math.min(uLeft, fL * fScale) or (fL * fScale)
        uRight = uRight and math.max(uRight, fR * fScale) or (fR * fScale)
        uBottom = uBottom and math.min(uBottom, fB * fScale) or (fB * fScale)
        uTop = uTop and math.max(uTop, fT * fScale) or (fT * fScale)
    end

    if Minimap and (not Minimap.IsShown or Minimap:IsShown()) then
        ExpandWithFrame(Minimap, 0, 0, 0, 0)
    end
    -- Ring texture uses 512x512 canvas with ~48px side, 42px top, 56px bottom transparent margin
    if ExpTracker.container and ExpTracker.container:IsShown() then
        ExpandWithFrame(ExpTracker.container, 48 / 512, 48 / 512, 42 / 512, 56 / 512)
    end
    if ExpTracker.expFrame and ExpTracker.expFrame:IsShown() then
        ExpandWithFrame(ExpTracker.expFrame, 0, 0, 0, 0)
    end
    if MUI.infoFrame and MUI.infoFrame:IsShown() then
        ExpandWithFrame(MUI.infoFrame, 0, 0, 0, 0)
    end
    for _, hdrPart in ipairs({
        (MinimapCluster and MinimapCluster.BorderTop) or false,
        (MinimapCluster and MinimapCluster.ZoneTextButton) or false,
        _G["MinimapBorderTop"] or false,
        _G["MinimapZoneTextButton"] or false,
        (MinimapCluster and MinimapCluster.Tracking) or false,
        _G["TimeManagerClockButton"] or false,
        _G["GameTimeFrame"] or false,
    }) do
        if hdrPart then
            ExpandWithFrame(hdrPart, 0, 0, 0, 0)
        end
    end
    if not (uLeft and uRight and uBottom and uTop) then
        uLeft = cL * cScale
        uRight = cR * cScale
        uBottom = cB * cScale
        uTop = cT * cScale
    end

    return uLeft, uRight, uBottom, uTop, cL, cR, cB, cT, cScale, hasAny
end

local function RestoreMinimapClampRectInsets()
    if not clampInsetsModified or settingMinimapClampGuard or InCombatLockdown() or not MinimapCluster then return end
    local isProtected = type(MinimapCluster.IsProtected) == "function" and MinimapCluster:IsProtected()
    if isProtected or type(MinimapCluster.SetClampRectInsets) ~= "function" then return end

    local ins = savedClusterClampInsets or { 0, 0, 0, 0 }
    settingMinimapClampGuard = true
    pcall(MinimapCluster.SetClampRectInsets, MinimapCluster, ins[1] or 0, ins[2] or 0, ins[3] or 0, ins[4] or 0)
    settingMinimapClampGuard = false
    clampInsetsModified = false
    lastClampInsets = nil
end

local ApplyMinimapClampRectInsets
ApplyMinimapClampRectInsets = function(forceReapply)
    if settingMinimapClampGuard or InCombatLockdown() or not MinimapCluster then return end
    local isProtected = type(MinimapCluster.IsProtected) == "function" and MinimapCluster:IsProtected()
    if isProtected or type(MinimapCluster.SetClampRectInsets) ~= "function" then return end

    if not hookedClusterClamp and type(MinimapCluster) == "table" then
        hookedClusterClamp = true
        if not savedClusterClampInsets and type(MinimapCluster.GetClampRectInsets) == "function" then
            local okG, l, r, t, b = pcall(MinimapCluster.GetClampRectInsets, MinimapCluster)
            if okG and l ~= nil then
                savedClusterClampInsets = {
                    YRG.SafeNumber(l, 0),
                    YRG.SafeNumber(r, 0),
                    YRG.SafeNumber(t, 0),
                    YRG.SafeNumber(b, 0),
                }
            end
        end
        pcall(hooksecurefunc, MinimapCluster, "SetClampRectInsets", function(_, l, r, t, b)
            if settingMinimapClampGuard then return end
            savedClusterClampInsets = {
                YRG.SafeNumber(l, 0),
                YRG.SafeNumber(r, 0),
                YRG.SafeNumber(t, 0),
                YRG.SafeNumber(b, 0),
            }
            lastClampInsets = nil
            if not InCombatLockdown() then
                ApplyMinimapClampRectInsets(true)
            end
        end)
    end

    local db = YRG:GetModuleDB("MinimapExpTracker")
    local uLeft, uRight, uBottom, uTop, cL, cR, cB, cT, cScale, hasAny = ComputeMinimapVisualBounds(db)
    if not hasAny then
        RestoreMinimapClampRectInsets()
        return
    end
    if not (uLeft and uRight and uBottom and uTop and cL and cR and cB and cT and cScale and cScale > 0) then
        return
    end

    local uScale = YRG.SafeOptionalNumber(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or cScale
    local topPaddingLocal = (10 * uScale) / cScale

    local clampL = (uLeft - (cL * cScale)) / cScale
    local clampR = (uRight - (cR * cScale)) / cScale
    local clampT = ((uTop - (cT * cScale)) / cScale) + topPaddingLocal
    local clampB = (uBottom - (cB * cScale)) / cScale

    if not forceReapply and clampInsetsModified and lastClampInsets then
        if math.abs(lastClampInsets[1] - clampL) < 0.2
            and math.abs(lastClampInsets[2] - clampR) < 0.2
            and math.abs(lastClampInsets[3] - clampT) < 0.2
            and math.abs(lastClampInsets[4] - clampB) < 0.2 then
            return
        end
    end

    settingMinimapClampGuard = true
    local ok = pcall(MinimapCluster.SetClampRectInsets, MinimapCluster, clampL, clampR, clampT, clampB)
    settingMinimapClampGuard = false
    if ok then
        clampInsetsModified = true
        lastClampInsets = { clampL, clampR, clampT, clampB }
    end
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

    ApplyMinimapClampRectInsets(forceReapply)

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

    local uLeft, uRight, uBottom, uTop, cL, cR, cB, cT, cScale, hasAny = ComputeMinimapVisualBounds(db)
    if (not hasAny) or not IsEditModeActive() then
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

    local sScale = YRG.SafeOptionalNumber(sel.GetEffectiveScale and sel:GetEffectiveScale()) or cScale
    if not (uLeft and uRight and uBottom and uTop and cL and cR and cB and cT and cScale and sScale and cScale > 0 and sScale > 0) then
        return
    end

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

MUI.UpdateEditModeSelection = UpdateEditModeMinimapSelection
MUI.RestoreEditModeSelection = RestoreEditModeMinimapSelection

local function ApplyMinimapUnitScale(unitScale, resetCachedPts)
    local target = GetMinimapScaleUnitTarget()
    if not target or type(target.SetScale) ~= "function" then return end
    if InCombatLockdown() then return end

    if not hookedMapUnitFrames[target] and type(target) == "table" and type(target.SetPoint) == "function" then
        hookedMapUnitFrames[target] = true
        pcall(hooksecurefunc, target, "SetPoint", function(frame)
            if mapScaleAnchorGuard then return end
            frame._yrgOrigMapPts = nil
            frame._yrgMapOffsetApplied = nil
        end)
    end

    local desired = math.max(0.50, math.min(1.80, YRG.SafeNumber(unitScale, 1.0)))
    if resetCachedPts and not mapScaleAnchorGuard and not target._yrgMapOffsetApplied then
        target._yrgOrigMapPts = nil
    end

    if not target._yrgOrigMapPts and type(target.GetNumPoints) == "function" and type(target.GetPoint) == "function" then
        local pts = {}
        local n = YRG.SafeNumber(target:GetNumPoints(), 0)
        for i = 1, n do
            local ok, pt, relTo, relPt, x, y = pcall(target.GetPoint, target, i)
            if ok and pt then
                table.insert(pts, {
                    pt = pt,
                    relTo = relTo,
                    relPt = relPt or pt,
                    x = YRG.SafeNumber(x, 0),
                    y = YRG.SafeNumber(y, 0),
                })
            end
        end
        if #pts > 0 then
            target._yrgOrigMapPts = pts
        end
    end

    local curScale = (type(target.GetScale) == "function") and YRG.SafeNumber(target:GetScale(), 1.0) or 1.0
    if math.abs(curScale - desired) > 0.001 then
        pcall(target.SetScale, target, desired)
    end

    local origPts = target._yrgOrigMapPts
    if origPts and #origPts > 0 and type(target.SetPoint) == "function" then
        mapScaleAnchorGuard = true
        if math.abs(desired - 1.0) <= 0.001 then
            if target._yrgMapOffsetApplied then
                pcall(function()
                    if #origPts > 1 and type(target.ClearAllPoints) == "function" then
                        target:ClearAllPoints()
                    end
                    for _, p in ipairs(origPts) do
                        target:SetPoint(p.pt, p.relTo, p.relPt, p.x, p.y)
                    end
                end)
                target._yrgMapOffsetApplied = nil
            end
        else
            local targetH = (type(target.GetHeight) == "function" and YRG.SafeNumber(target:GetHeight(), 0)) or 140
            if targetH <= 0 then targetH = 140 end
            local halfH = targetH * 0.5
            pcall(function()
                if #origPts > 1 and type(target.ClearAllPoints) == "function" then
                    target:ClearAllPoints()
                end
                for _, p in ipairs(origPts) do
                    local nx = p.x / desired
                    local ny = p.y / desired
                    if p.pt:find("BOTTOM", 1, true) then
                        ny = (p.y + targetH * (1 - desired)) / desired
                    elseif not p.pt:find("TOP", 1, true) then
                        ny = (p.y + halfH * (1 - desired)) / desired
                    end
                    target:SetPoint(p.pt, p.relTo, p.relPt, nx, ny)
                end
            end)
            target._yrgMapOffsetApplied = true
        end
        mapScaleAnchorGuard = false
    end
end

local headerSyncGuard = false

function MUI.SyncHeaderAndEditMode()
    if headerSyncGuard then return end
    headerSyncGuard = true
    local db = YRG:GetModuleDB("MinimapExpTracker")
    ApplyMinimapHeaderWidth(db)
    if db and db.enabled then
        ApplyMinimapUnitScale(db.mapScale or 1.0, false)
    end
    ApplyMinimapHeaderCenter(db)
    if type(MUI.onInfoPlacardReposition) == "function" then
        pcall(MUI.onInfoPlacardReposition)
    end
    if type(MUI.UpdateBuiltInCoordinatesNudge) == "function" then
        MUI.UpdateBuiltInCoordinatesNudge()
    end
    if ExpTracker.expHitFrame then
        ApplyExpHitBoxLayering(ExpTracker.expHitFrame)
    end
    UpdateEditModeMinimapSelection()
    headerSyncGuard = false
end

function MUI.NotifyInfoPlacardLayout()
    if type(MUI.onInfoPlacardLayout) == "function" then
        MUI.onInfoPlacardLayout()
    end
end

function ExpTracker:LayoutPlacardsImpl()
    if not self.container then return end
    local db = YRG:GetModuleDB("MinimapExpTracker")

    ApplyHeaderNineSliceStyle(self.expFrame)
    ApplyMinimapHeaderDarkness(db)
    ApplyLocalTimeSetting(db)

    local mapWidth = Minimap:GetWidth() or 140
    local mapHeight = Minimap:GetHeight() or mapWidth
    local baseRingSize = mapWidth * (512 / 368)
    local ringBottomRimY = baseRingSize * (56 / 512)

    -- Bottom-Fixed EXP Percentage Placard (always visible when ring is active)
    local expTSize = db.expTextSize or 16
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

    if self.expHitFrame then
        ApplyExpHitBoxLayering(self.expHitFrame)
        local expCenterRelMapBottom = ringBottomRimY - ((baseRingSize - mapHeight) * 0.5)
        local visibleH = math.min(expH, math.max(12, -(expCenterRelMapBottom - (expH * 0.5))))
        self.expHitFrame:ClearAllPoints()
        self.expHitFrame:SetPoint("BOTTOMLEFT", self.expFrame, "BOTTOMLEFT", 0, 0)
        self.expHitFrame:SetPoint("BOTTOMRIGHT", self.expFrame, "BOTTOMRIGHT", 0, 0)
        self.expHitFrame:SetHeight(visibleH)
        self.expHitFrame:Show()
    end
end

function ExpTracker:LayoutPlacards()
    self:LayoutPlacardsImpl()
    MUI.NotifyInfoPlacardLayout()
    MUI.SyncHeaderAndEditMode()
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

    ApplyMinimapUnitScale(db.mapScale or 1.0, false)

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
    MUI.SyncHeaderAndEditMode()

    pcall(function()
        local mapUnit = GetMinimapScaleUnitTarget()
        local hdr = GetZoneTitleAnchorFrame()
        local _, _, _, uTop, _, _, _, _, cScale = ComputeMinimapVisualBounds(db)
        local ptsDesc = ""
        if mapUnit and mapUnit._yrgOrigMapPts then
            local segs = {}
            for _, p in ipairs(mapUnit._yrgOrigMapPts) do
                local rn = (p.relTo and p.relTo.GetName and p.relTo:GetName()) or tostring(p.relTo)
                segs[#segs + 1] = string.format("%s->%s:%s(%.1f,%.1f)", tostring(p.pt), tostring(rn), tostring(p.relPt), p.x, p.y)
            end
            ptsDesc = table.concat(segs, ";")
        end
        db._lastMapScaleDiag = {
            masterScale = db.masterScale,
            mapScale = db.mapScale,
            target = (mapUnit and mapUnit.GetName and mapUnit:GetName()) or ((MinimapCluster and mapUnit == MinimapCluster.MinimapContainer) and "MinimapContainer") or tostring(mapUnit),
            hdrBottom = IsMinimapHeaderOnBottom(),
            mcTop = MinimapCluster and MinimapCluster.GetTop and YRG.SafeOptionalNumber(MinimapCluster:GetTop()),
            tTop = mapUnit and mapUnit.GetTop and YRG.SafeOptionalNumber(mapUnit:GetTop()),
            visTop = (uTop and cScale and cScale > 0) and (uTop / cScale) or nil,
            clampT = lastClampInsets and lastClampInsets[3] or nil,
            clampR = lastClampInsets and lastClampInsets[2] or nil,
            hdrTop = hdr and hdr.GetTop and YRG.SafeOptionalNumber(hdr:GetTop()),
            hdrBot = hdr and hdr.GetBottom and YRG.SafeOptionalNumber(hdr:GetBottom()),
            origPts = ptsDesc,
        }
    end)
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

function ExpTracker:UpdateXP()
    if not self.container then return end
    local db = YRG:GetModuleDB("MinimapExpTracker")
    if not db or not db.enabled then
        self.container:Hide()
        ApplyMinimapHeaderWidth(db)
        ApplyMinimapHeaderCenter(db)
        ApplyMinimapHeaderDarkness(db)
        MUI.UpdateBuiltInCoordinatesNudge()
        MUI.NotifyInfoPlacardLayout()
        UpdateEditModeMinimapSelection()
        return
    end

    local level = YRG.SafeNumber(UnitLevel("player"), 1)
    local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if db.hideAtMaxLevel and level >= maxLevel then
        self.container:Hide()
        MUI.UpdateBuiltInCoordinatesNudge()
        MUI.NotifyInfoPlacardLayout()
        UpdateEditModeMinimapSelection()
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

    self:LayoutPlacards()
end

function ExpTracker:OnInitialize(db)
    if not db.fillStyle or not FILL_TEXTURES[db.fillStyle] then
        db.fillStyle = "conduit"
    end
    if not db.bubbleOverlay or (db.bubbleOverlay ~= "none" and not BUBBLE_OVERLAY_TEXTURES[db.bubbleOverlay]) then
        db.bubbleOverlay = "bevel"
    end
    if not db.colorScheme or not COLOR_SCHEMES[db.colorScheme] then
        db.colorScheme = "blue"
    end
    if db.mapScale == nil then
        db.mapScale = 1.0
    end
    if db.nudgeBuiltInCoords == nil then
        db.nudgeBuiltInCoords = true
    end
    if db.nudgeBuiltInCoordsDir ~= "UP" and db.nudgeBuiltInCoordsDir ~= "DOWN" then
        db.nudgeBuiltInCoordsDir = "UP"
    end
    db.headerOffsetX = nil
    db.expColor = nil
    db.restedColor = nil
    db._fixedColorPickerAlphaV1 = nil

    self:EnsureFrames()
    self.eventFrame = CreateFrame("Frame")

    self.eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if self._pendingHeaderCenter then
                self._pendingHeaderCenter = nil
                local modDB = YRG:GetModuleDB("MinimapExpTracker")
                if modDB then
                    ApplyMinimapHeaderWidth(modDB)
                    ApplyMinimapHeaderCenter(modDB)
                    self:LayoutPlacards()
                end
            end
            if self._pendingCoordNudge then
                self._pendingCoordNudge = nil
                MUI.UpdateBuiltInCoordinatesNudge()
            end
        else
            self:UpdateXP()
        end
    end)

    local function OnAnyMinimapLayoutChange()
        local modDB = YRG:GetModuleDB("MinimapExpTracker")
        if modDB and modDB.enabled then
            self:ApplyVisualSettings()
        else
            MUI.NotifyInfoPlacardLayout()
            MUI.SyncHeaderAndEditMode()
        end
    end

    if not MUI.hooksRegistered then
        MUI.hooksRegistered = true
        Minimap:HookScript("OnSizeChanged", OnAnyMinimapLayoutChange)

        local syncingHeader = false
        local function SyncMinimapHeaderLayout()
            if syncingHeader or headerWidthGuard or headerCenteringGuard or mapScaleAnchorGuard or coordNudgeGuard then return end
            syncingHeader = true
            local modDB = YRG:GetModuleDB("MinimapExpTracker")
            if modDB and modDB.enabled then
                ApplyMinimapUnitScale(modDB.mapScale or 1.0, false)
                self:LayoutPlacards()
            else
                MUI.NotifyInfoPlacardLayout()
                MUI.SyncHeaderAndEditMode()
            end
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(0, function()
                    local mdb = YRG:GetModuleDB("MinimapExpTracker")
                    if mdb and mdb.enabled then
                        ApplyMinimapUnitScale(mdb.mapScale or 1.0, false)
                    end
                    MUI.SyncHeaderAndEditMode()
                end)
            end
            syncingHeader = false
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
            local modDB = YRG:GetModuleDB("MinimapExpTracker")
            if modDB and modDB.enabled then
                self:LayoutPlacards()
            else
                MUI.NotifyInfoPlacardLayout()
            end
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
                local modDB = YRG:GetModuleDB("MinimapExpTracker")
                if modDB and modDB.enabled then
                    self:LayoutPlacards()
                else
                    MUI.NotifyInfoPlacardLayout()
                end
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
end

function ExpTracker:OnEnable(db)
    self:EnsureFrames()
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
    self.eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
    self.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
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
            MUI.NotifyInfoPlacardLayout()
            MUI.SyncHeaderAndEditMode()
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
    self._pendingHeaderCenter = nil
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    if self.container then
        self.container:Hide()
    end
    ApplyMinimapHeaderCenter(db)
    ApplyMinimapHeaderWidth(db)
    ApplyMinimapHeaderDarkness(db)
    if self.ApplyHideAddonButtonsSetting then
        self:ApplyHideAddonButtonsSetting(db)
    end
    ApplyMinimapUnitScale(1.0, false)
    local scaleTarget = MinimapCluster or Minimap
    if scaleTarget and type(scaleTarget.SetScale) == "function" then
        local curScale = (type(scaleTarget.GetScale) == "function") and YRG.SafeNumber(scaleTarget:GetScale(), 1.0) or 1.0
        local isProtected = type(scaleTarget.IsProtected) == "function" and scaleTarget:IsProtected()
        if not InCombatLockdown() and not isProtected and math.abs(curScale - 1.0) > 0.001 then
            pcall(scaleTarget.SetScale, scaleTarget, 1.0)
        end
    end
    self:ApplyDefaultExpBarVisibility(db)
    MUI.UpdateBuiltInCoordinatesNudge()
    MUI.NotifyInfoPlacardLayout()
    UpdateEditModeMinimapSelection()
end

function ExpTracker:BuildConfigUI(ctx, db)
    local function GetDB()
        return YRG:GetModuleDB("MinimapExpTracker")
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
        defaultValue = true,
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
        tooltip = "Overall scale factor applied to the entire minimap cluster (including the title bar, Info Placard, and minimap unit).",
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

    ctx:AddSlider({
        key = "mapScale",
        name = "Minimap & EXP Ring Scale",
        tooltip = "Independent scale factor applied to the minimap, radial EXP ring, and bottom EXP placard as one unit, separate from the title bar and Info Placard.",
        min = 0.60, max = 1.50, step = 0.02, defaultValue = 1.0,
        format = function(v) return string.format("%.2f", v) end,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.mapScale) or 1.0
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.mapScale = val end
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
        defaultValue = true,
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
        min = 8, max = 20, step = 1, defaultValue = 16,
        format = function(v) return string.format("%d px", v) end,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.expTextSize) or 16
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.expTextSize = val end
            self:ApplyVisualSettings()
        end,
    })

    ctx:AddCheckbox({
        key = "nudgeBuiltInCoords",
        name = "Auto-Nudge Minimap Coordinates",
        tooltip = "Automatically repositions Blizzard's built-in minimap coordinates clear of the EXP ring and % badge whenever the EXP ring is visible and the Info Placard is not showing coordinates.",
        defaultValue = true,
        notifies = { "YRG_MinimapExpTracker_nudgeBuiltInCoordsDir" },
        get = function()
            local mdb = GetDB()
            return mdb == nil or mdb.nudgeBuiltInCoords ~= false
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.nudgeBuiltInCoords = val and true or false end
            MUI.UpdateBuiltInCoordinatesNudge()
        end,
    })

    ctx:AddDropdown({
        key = "nudgeBuiltInCoordsDir",
        name = "Minimap Coordinates Nudge Position",
        tooltip = "Places Blizzard's built-in minimap coordinates up above the bottom ring rim (default) or down below the EXP % badge.",
        defaultValue = "UP",
        options = COORD_NUDGE_DIR_OPTIONS,
        canModify = function()
            local mdb = GetDB()
            return mdb == nil or mdb.nudgeBuiltInCoords ~= false
        end,
        get = function()
            local mdb = GetDB()
            return (mdb and mdb.nudgeBuiltInCoordsDir == "DOWN") and "DOWN" or "UP"
        end,
        set = function(val)
            local mdb = GetDB()
            if mdb then mdb.nudgeBuiltInCoordsDir = (val == "DOWN") and "DOWN" or "UP" end
            MUI.UpdateBuiltInCoordinatesNudge()
        end,
    })
end

YRG:RegisterModule("MinimapExpTracker", ExpTracker)
