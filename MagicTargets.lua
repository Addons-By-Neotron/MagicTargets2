--[[
**********************************************************************
MagicTargets - Show the targets of the raid / party members.
**********************************************************************
This file is part of MagicTargets, a World of Warcraft Addon

MagicTargets is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MagicTargets is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MagicTargets.  If not, see <http://www.gnu.org/licenses/>.

**********************************************************************
]]
-- 10:50 <@vhaarr> local ae = {}; AceLibrary("AceEvent-2.0"):embed(ae); ae:RegisterEvent("oRA_MainTankUpdate", function() --[[ update tanks ]] end)
-- 10:50 <@vhaarr> NeoTron: or even AceLibrary("AceEvent-2.0"):RegisterEvent("oRA_MainTankUpdate", function() ... end)

MagicTargets = LibStub("AceAddon-3.0"):NewAddon("MagicTargets", "AceEvent-3.0", "LibMagicUtil-1.0",
        "AceTimer-3.0", "AceConsole-3.0", "LibSimpleBar-2.0")

--LoadAddOn("LibGroupTalents-1.0")
-- Silently fail embedding if it doesn't exist
local LibStub = LibStub
local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
local LGT = LibStub:GetLibrary("LibGroupTalents-1.0", true)
local Logger = LibStub("LibLogger-1.0", true)
if Logger then
    Logger:Embed(MagicTargets)
end
local L = LibStub("AceLocale-3.0"):GetLocale("MagicTargets")
local DBOpt = LibStub("AceDBOptions-3.0")
local media = LibStub("LibSharedMedia-3.0")
local mod = MagicTargets
local CreateFrame = CreateFrame
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local GetRaidRosterInfo = GetRaidRosterInfo
local GetRaidTargetIndex = GetRaidTargetIndex
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local UnitCanAttack = UnitCanAttack
local UnitClass = UnitClass
local UnitClassification = UnitClassification
local UnitCreatureType = UnitCreatureType
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsDead = UnitIsDead
local UnitIsPlayer = UnitIsPlayer
local UnitLevel = UnitLevel
local UnitName = UnitName
local UnitPlayerControlled = UnitPlayerControlled
local ceil = math.ceil
local fmt = string.format
local ipairs = ipairs
local max = max
local min = min
local next = next
local pairs = pairs
local rnd = math.random
local sort = sort
local strlen = strlen
local tconcat = table.concat
local time = time
local tinsert = table.insert
local tonumber = tonumber
local tostring = tostring
local tremove = table.remove
local tsort = table.sort
local type = type
local unpack = unpack
local addonEnabled = false
local db, isInGroup, inCombat
local tooltipInfo = {}
local died = {}
local seen = {}
local raidicons = {}
local ingroup = {}
local trivial = {}
local focusIcon, targetIcon
local tableStore = {}

local classColors = {}

local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100 or true

local UnitHealthPercent = UnitHealthPercent or function(target)
    return 100.0 * UnitHealth(target) / UnitHealthMax(target)
end

if UnitGroupRolesAssigned == nil then
    function UnitGroupRolesAssigned() return false end
end

for k, v in pairs(RAID_CLASS_COLORS) do
    classColors[k] = ("|cff%02x%02x%02x"):format(v.r * 255, v.g * 255, v.b * 255)
end

-- Helper table to cache colored player names.
local coloredNames = setmetatable({}, { __index = function(self, key)
    if type(key) == "nil" then
        return nil
    end
    local _, class = UnitClass(key)
    if class then
        self[key] = classColors[class] .. key .. "|r"
        return self[key]
    else
        return key
    end
end
})

local colors = {
    Tank   = { [1] = 0, [2] = 1, [3] = 0.2, [4] = 1 },
    CC     = { [1] = 0, [2] = 0.7, [3] = 0.9, [4] = 1 },
    Notank = { [1] = 1, [2] = 0, [3] = 0, [4] = 1 },
    Normal = { [1] = 1, [2] = 1, [3] = 0.5, [4] = 1 }
}

function mod.clear(tbl)
    if type(tbl) == "table" then
        for id, data in pairs(tbl) do
            if type(data) == "table" then
                mod.del(data)
            end
            tbl[id] = nil
        end
    end
end

function mod.get()
    return tremove(tableStore) or {}
end

function mod.del(tbl, index)
    local todel = tbl
    if index then
        todel = tbl[index]
    end
    if type(todel) ~= "table" then
        return
    end
    mod.clear(todel)
    tinsert(tableStore, todel)
    if index then
        tbl[index] = nil
    end
end

local function SetColorOpt(arg, r, g, b, a)
    local color = arg[#arg]
    db.colors[color][1] = r
    db.colors[color][2] = g
    db.colors[color][3] = b
    db.colors[color][4] = a
end

function mod:SetBarColors()
    for _, frame in pairs(mod.bars) do
        frame:SetColor(frame.color)
    end
end

local function GetColorOpt(arg)
    return unpack(db.colors[arg[#arg]])
end

local iconPath = [[Interface\AddOns\MagicTargets\Textures\%d.tga]]

local defaults = {
    profile = {
        showNotTargetedBy = false,
        focus = true,
        coloredNames = true,
        target = true,
        eliteonly = false,
        growup = false,
        font = "Friz Quadrata TT",
        locked = false,
        hideanchor = true,
        outsidegroup = true,
        texture = "Minimalist",
        maxbars = 20,
        fontsize = 8,
        width = 150,
        height = 12,
        spacing = 2,
        fadebars = false,
        HideMinimapButton = false,
        showTooltip = true,
        scale = 1.0,
        labelTheme = "default",

        -- frame background
        edgeSize = 16,
        padding = 2,
        backdropColors = {
            backgroundColor = { 0, 0, 0, 0.5 },
            borderColor = { 0.88, 0.88, 0.88, 0.8 },
        },
        background = "Solid",
        border = "None",
        tile = false,
        tileSize = 32,
    },
}

function mod:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("MagicTargetsDB", defaults, "Default")
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    db = self.db.profile
    if not db.colors then
        db.colors = colors
    end
    mod:FixLabelThemes()

    self.ldb = LDB:NewDataObject("Magic Targets",
            {
                type = "launcher",
                label = "Magic Targets",
                icon = [[Interface\AddOns\MagicTargets\target.tga]],
                tooltiptext = (L["|cffffff00Left click|r to open the configuration screen.\n"] ..
                        L["|cffffff00Right click|r to toggle the Magic Target window lock."]),
                OnClick = function(clickedframe, button)
                    if button == "LeftButton" then
                        mod:ToggleConfigDialog()
                    elseif button == "RightButton" then
                        mod:ToggleLocked()
                    end
                end,
            })

    mod.options.profile = DBOpt:GetOptionsTable(self.db)

    mod:SetupOptions()

    for i = 1, 8 do
        raidicons[i] = iconPath:format(i)
    end

    mod.recycledFrames = {}
    mod.unitbars = {}
    mod.bars = {}
    mod:CreateFrame()
end

function mod:OnEnable()
    self:ApplyProfile()
    if self.SetLogLevel then
        self:SetLogLevel(self.logLevels.TRACE)
    end
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "ScheduleGroupScan")
    self:ScheduleGroupScan(true)
end

local function GetRaidIcon(id)
    if id and id > 0 and id <= 8 then
        return raidicons[id]
    end
end

function mod:SetIcon(bar, mark)
    -- Disabled: mark is a secret value in Midnight, can't do boolean operations with it
    -- TODO: Re-enable when Blizzard provides a non-secret way to get raid target indices
    bar.icon:SetTexture(nil)
    bar.mark = nil
end

function mod:IterateBars(func, ...)
    for _, frame in pairs(mod.bars) do
        if frame[func] then
            frame[func](frame, ...)
        elseif frame.bar[func] then
            frame.bar[func](frame.bar, ...)
        end
    end
end

function mod:SetTexture(frame)
    local t = media:Fetch("statusbar", db.texture)
    if frame then
        frame.bar:SetTexture(t)
    else
        mod:IterateBars("SetTexture", t)
    end
end

function mod:SetFont()
    mod:IterateBars("SetBarFont")
    mod:SetHandleFont()
end

function mod:OnDisable()
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")
end

-- Check if a unit is assigned as a tank
function mod:IsTank(unit)
    -- Check if unit has TANK role assigned
    local role = UnitGroupRolesAssigned(unit)
    if not issecretvalue(role) and role == "TANK" then
        return true
    end

    -- Check if unit is assigned as main tank in raid
    local isMainTank = GetPartyAssignment("MAINTANK", unit)
    if not issecretvalue(isMainTank) and isMainTank then
        return true
    end

    return false
end

-- Check if a unit is being tanked (its target is a tank or pet)
function mod:IsTanked(unit)
    local targetUnit = unit .. "target"

    -- Check if target is a player who is a tank
    if  mod:IsTank(targetUnit) then
        return true
    end

    -- Check if target is a pet (also considered tanked)
    if UnitPlayerControlled(targetUnit) then
        return true
    end

    return false
end

function mod:UnitRole(unit, specOnly)
    if not specOnly and mod:IsTank(unit) then
        return "tank"
    end
    local role = UnitGroupRolesAssigned(unit)
    if not issecretvalue(role) and role == "TANK" then
        return "tank"
    elseif not issecretvalue(role) and role == "HEALER" then
        return "healer"
    else
        if LGT then
            return LGT:GetUnitRole(unit)
        else
            return "dps"
        end
    end
end

do
    local raidtarget, partytarget

    -- Iterator function for raid/party members and optionally their targets
    function mod:IterateRaid(callback, target, ...)
        local id, name, class, map
        if IsInRaid() then
            if target then
                if not raidtarget then
                    raidtarget = mod.get()
                end
                map = raidtarget
            end
            for id = 1, GetNumGroupMembers() do
                local name = GetRaidRosterInfo(id)
                if target then
                    if not map[id] then
                        map[id] = "raid" .. id .. (target and "target" or "")
                    end
                    callback(self, map[id], name, ...)
                else
                    callback(self, name, name, ...)
                end
            end
        else
            if GetNumGroupMembers() > 0 then
                if not partytarget then
                    partytarget = mod.get()
                end
                map = partytarget
                for id = 1, GetNumGroupMembers() - 1 do
                    if not map[id] then
                        map[id] = "party" .. id
                    end
                    local name = UnitName(map[id])
                    callback(self, (target and (map[id] .. "target")) or name, name, ...)
                end
            end
            local name = UnitName("player")
            callback(self, target and "target" or name, name, ...);
        end
    end

    local groupScanTimer
    function mod:ScheduleGroupScan(fast)
        if groupScanTimer then
            self:CancelTimer(groupScanTimer, true)
        end
        if fast == true then
            groupScanTimer = self:ScheduleTimer("ScanGroupMembers", 0.1)
        else
            groupScanTimer = self:ScheduleTimer("ScanGroupMembers", 5)
        end
    end

    function mod:ScanGroupMembers()
        mod.clear(ingroup)
        if GetNumGroupMembers() > 0 then
            isInGroup = true
            -- Populate ingroup table with unit name -> unit token mapping
            mod:IterateRaid(function(self, unittarget, unitname)
                if unitname then
                    ingroup[unitname] = unittarget
                end
            end, true)
        else
            mod.clear(coloredNames)
            isInGroup = false
        end
        if isInGroup or db.outsidegroup then
            if not addonEnabled then
                addonEnabled = true
                self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateTarget", "target")
                self:RegisterEvent("PLAYER_FOCUS_CHANGED", "UpdateTarget", "focus")
                self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "UpdateBar", "mouseover")
                self:RegisterEvent("UNIT_HEALTH")
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
                self:RegisterEvent("PLAYER_REGEN_DISABLED")
                self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
                self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
                self:ClearCombatData()
                if InCombatLockdown() then
                    self:PLAYER_REGEN_DISABLED()
                else
                    self:PLAYER_REGEN_ENABLED()
                end
            end
        else
            if addonEnabled then
                addonEnabled = false
                self:UnregisterEvent("UNIT_HEALTH")
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                self:UnregisterEvent("PLAYER_REGEN_DISABLED")
                self:UnregisterEvent("PLAYER_TARGET_CHANGED")
                self:UnregisterEvent("PLAYER_FOCUS_CHANGED")
                self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
                self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
                self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
                self:PLAYER_REGEN_ENABLED()
            end
            self:ClearCombatData()
            self:RemoveAllBars(true)
        end
    end
end

function mod:UpdateTarget(target, norefresh)
    if mod.testBars then
        return
    end
    local icon = target == "focus" and focusIcon or targetIcon
    if icon then
        icon:Hide()
    end

    -- Find the nameplate that matches this focus/target instead of creating a separate bar
    if UnitExists(target) then
        local frame = nil
        -- Search through existing bars to find the one that matches
        for unitToken, bar in pairs(mod.unitbars) do
            if string.match(unitToken, "^nameplate") and UnitIsUnit(unitToken, target) then
                frame = bar
                break
            end
        end

        if frame then
            self:MoveIconTo(icon, frame, target)
            mod:SetBarStrings(frame)
        end
    end
    if norefresh ~= true then
        mod:SortBars()
    end
end

local function Noop()
end

function mod:RemoveBar(unitToken)
    local frame = mod.unitbars[unitToken] or mod.bars[unitToken]
    if frame then
        mod.unitbars[frame.unitToken] = nil
        frame.mark = nil
        frame.unitToken = nil
        seen[unitToken] = nil
        mod.del(tooltipInfo, unitToken)
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
        frame:EnableMouse(false)
        if frame.tooltipShowing then
            frame.tooltipShowing = nil
            GameTooltip:Hide()
        end
        frame:Hide()
        mod.recycledFrames[#mod.recycledFrames + 1] = frame

        for id, data in pairs(mod.bars) do
            if frame == data then
                tremove(mod.bars, id)
                break
            end
        end
    end
end

function mod:RemoveAllBars(removeAll)
    if mod.testBars then
        return
    end
    for id in pairs(mod.unitbars) do
        mod:RemoveBar(id)
    end
    mod:SortBars()
end

local tanked = {}
local crowdControlled = {}

local lvlFmt = L["Level %d %s"]
local colorToText = {
    CC = L["Crowd Controlled"],
    Tank = L["Tanked"],
    Notank = L["Untanked"],
}

local function Bar_UpdateTooltip(self, tooltip)
    tooltip:ClearLines()
    local tti = tooltipInfo[self.unitToken]
    if tti and type(tti.name) ~= "nil" then
        tooltip:AddLine(tti.name, 0.85, 0.85, 0.1)
        tooltip:AddLine(fmt(lvlFmt, tti.level, tti.type), 1, 1, 1)
        tooltip:AddLine(" ")
        tooltip:AddDoubleLine(L["Health:"], tti["%"], nil, nil, nil, 1, 1, 1)
        if type(tti.target) ~= "nil" then
            tooltip:AddDoubleLine(L["Target:"], tti.target, nil, nil, nil, 1, 1, 1)
        end
        if self.color and colorToText[self.color] and InCombatLockdown() then
            local c = db.colors[self.color]
            tooltip:AddDoubleLine(L["Status:"], colorToText[self.color], nil, nil, nil, c[1], c[2], c[3])
        else
            local c = db.colors.Normal
            tooltip:AddDoubleLine(L["Status:"], L["Idle"], nil, nil, nil, c[1], c[2], c[3])
        end
        tooltip:AddLine(" ")
    else
        if tti and tti.name then
            tooltip:AddLine(tti.name, 0.85, 0.85, 0.1)
            tooltip:AddLine(" ")
        end
        tooltip:AddLine(L["Not targeted by anyone."]);
    end
    tooltip:Show()
end

local function Bar_OnEnter(frame)
    if not db.showTooltip then
        return
    end
    local tooltip = GameTooltip
    tooltip:SetOwner(frame, "ANCHOR_CURSOR")
    Bar_UpdateTooltip(frame, tooltip)
    frame.tooltipShowing = true
end

local function Bar_OnLeave(frame)
    if not db.showTooltip then
        return
    end
    GameTooltip:Hide()
    frame.tooltipShowing = nil
end

function mod:UNIT_HEALTH(event, unit)
    local frame = mod.unitbars[unit]
    if not frame then
        return
    end
    local tti = tooltipInfo[unit]
    local uh, uhm = UnitHealth(unit), UnitHealthMax(unit)

    if tti then
        tti.health = uh
        tti.maxhealth = uhm
        tti["%"] = fmt("%.0f", UnitHealthPercent(unit, false, ScaleTo100))
    end

    frame.bar:SetValue(uh, uhm)
    mod:SetBarStrings(frame)
end

function mod:NAME_PLATE_UNIT_ADDED(event, unitToken)
    if UnitExists(unitToken) then
        self:UpdateBar(unitToken)
    end
end

function mod:NAME_PLATE_UNIT_REMOVED(event, unitToken)
    if UnitExists(unitToken) then
        seen[unitToken] = time()
    end
end

function mod:UpdateBar(target, targetedBy)
    if not UnitExists(target) or mod.testBars then
        return
    end

    if trivial[target] or died[target] then
        return
    end

    local type = UnitCreatureType(target)
    local unitname = UnitName(target)
    -- Can't use unitname as table key since it's a secret value
    -- Instead check if target is player-controlled or a player
    -- Only show nameplates that are in combat (but always show focus and target)
    local isNameplate = string.match(target, "^nameplate")
    local isMyTarget = isNameplate and UnitIsUnit("target", target)
    local isMyFocus = isNameplate and UnitIsUnit("focus", target)
    local showUnit = not isNameplate or UnitAffectingCombat(target) or isMyTarget or isMyFocus
    if UnitCanAttack("player", target) and not UnitIsDead(target) and not UnitIsPlayer(target) and not UnitPlayerControlled(target) and showUnit then
        if UnitIsTrivial(target) or (db.eliteonly and UnitClassification(target) == "normal") then
            trivial[target] = true
            self:RemoveBar(target)
            return
        end
        local frame = mod.unitbars[target]
        local mark = GetRaidTargetIndex(target)
        local uh, uhm = UnitHealth(target), UnitHealthMax(target)
        if not frame then
            frame = self:CreateBar(target, uh, uhm)
            frame:SetColor("Normal")
        else
            frame.bar:SetValue(uh, uhm)
        end
        mod:SetIcon(frame, mark)

        -- Check if this unit is being tanked
        tanked[target] = mod:IsTanked(target)

        local tti = tooltipInfo[target] or mod.get()
        tooltipInfo[target] = tti

        if not tti.targets then
            tti.targets = mod.get()
        end

        -- Get threat information - nameplates support UnitDetailedThreatSituation
        local isTanking, status, threatPct, rawPct = UnitDetailedThreatSituation("player", target)
        if threatPct then
            local ok, val = pcall(ceil, threatPct)
            tti.threat = ok and val or threatPct
        else
            tti.threat = 0
        end

        local targettarget = target .. "target"
        local tn = UnitName(targettarget)

        -- Check if this unit is crowd controlled (has no target and is in combat)
        if UnitAffectingCombat(target) and not UnitExists(targettarget) then
            crowdControlled[target] = true
        else
            crowdControlled[target] = false
        end
        tti.name = unitname
        tti.target = tn
        tti.type = type
        tti.level = UnitLevel(target)
        tti.health = uh
        tti.maxhealth = uhm
        tti["%"] = fmt("%.0f", UnitHealthPercent(target, false, ScaleTo100))

        seen[target] = time() + 4
        if target == "mouseover" then
            mod:SortBars()
            mod:SetBarStrings(frame)
        end
    end
end

function mod:UpdateBars()
    local tt = time()
    if mod.testBars then
        return
    end
    inCombat = InCombatLockdown()

    mod.clear(tanked)
    mod.clear(crowdControlled)

    -- Clear all targeting information before rebuilding
    for _, tti in pairs(tooltipInfo) do
        if tti.targets then
            mod.clear(tti.targets)
        end
    end

    -- Scan nameplates for enemy units
    local nameplates = C_NamePlate.GetNamePlates()
    for _, nameplateFrame in ipairs(nameplates) do
        local unitToken = nameplateFrame.unitToken
        if unitToken and UnitExists(unitToken) then
            self:UpdateBar(unitToken)
        end
    end

    if next(mod.unitbars) then
        -- This updates the list of "seen" mobs. Bars for mobs not seen for a while
        -- are removed.
        for id, seenTime in pairs(seen) do
            if seenTime < tt and not inCombat then
                seen[id] = nil
            end
        end

        -- Update bar colors and recycle non-needed bars
        for id, frame in pairs(mod.unitbars) do
            -- Check if unit still exists and is not dead
            local unitExists = UnitExists(id)
            local isDead = unitExists and UnitIsDead(id)

            -- Remove bar if unit is dead or doesn't exist
            if isDead or not unitExists then
                self:RemoveBar(id)
            elseif seen[id] then
                -- We're keeping this one
                if inCombat then
                    -- Update bar colors based on mob status
                    if isInGroup then
                        local unitName = UnitName(id)
                        -- Check CC status first (highest priority)
                        if crowdControlled[id] then
                            frame:SetColor("CC")
                        elseif tanked[id] == nil then
                            frame:SetColor("Normal")
                        elseif tanked[id] then
                            frame:SetColor("Tank")
                        else
                            frame:SetColor("Notank")
                        end
                    else
                        -- When solo, still check for CC
                        if crowdControlled[id] then
                            frame:SetColor("CC")
                        else
                            frame:SetColor("Tank")
                        end
                    end
                end

                if frame.tooltipShowing then
                    Bar_UpdateTooltip(frame, GameTooltip)
                end

                -- Update the text on the bar
                mod:SetBarStrings(frame)
            else
                self:RemoveBar(id) -- Remove it since it's not seen, updated or MagicMarker
            end
        end
    else
        mod.clear(seen)
    end
    self:UpdateTarget("target", true)
    self:UpdateTarget("focus", true)
    mod:SortBars()
end

--------------------------------------------------
-- Move the <| icon to the appropriate location --
--------------------------------------------------
function mod:MoveIconTo(icon, frame, target)
    if not icon then
        return
    end
    local parent = icon:GetParent()
    local othericon = target == "focus" and targetIcon or focusIcon
    local otherparent = db[target == "focus" and "target" or "focus"] and othericon:GetParent()

    if db[target] then
        icon:SetPoint("LEFT", frame.bar, "RIGHT", -6, 0)
        icon:SetParent(frame.bar)
        icon:Show()
    else
        icon:SetParent(mod.frame)
        icon:Hide()
    end
end

local repeatTimer

function mod:PLAYER_REGEN_ENABLED()
    if repeatTimer then
        self:CancelTimer(repeatTimer, true)
        repeatTimer = nil
        --      mod:debug("Unscheduling timer.")
    end
    mod:RemoveAllBars()
    self:ClearCombatData()
    if addonEnabled then
        repeatTimer = self:ScheduleRepeatingTimer("UpdateBars", 2.5)
        --      mod:debug("Scheduling 5 second repeating timer.")
    end
end

function mod:ClearCombatData()
    mod.clear(died)
    mod.clear(trivial)
end

function mod:PLAYER_REGEN_DISABLED()
    if repeatTimer then
        self:CancelTimer(repeatTimer, true)
        repeatTimer = nil
        --      mod:debug("Unscheduling timer.")
    end
    if addonEnabled then
        repeatTimer = self:ScheduleRepeatingTimer("UpdateBars", 0.5)
        --      mod:debug("Scheduling 0.5 second repeating timer.")
    end
end



-- Config option handling below

local function GetMediaList(type)
    local arrlist = media:List(type)
    local keylist = {}
    for _, val in pairs(arrlist) do
        keylist[val] = val
    end
    return keylist
end

function mod:ApplyProfile()
    -- configure based on saved data
    mod:SetTexture()
    mod:SetFont()
    mod:SetSize()
    mod:SetBarColors()
    mod:FixBackdrop()
    mod:FixAnchorVisibility()
    mod.frame:SetScale(db.scale)
    mod.handle:SetScale(db.scale)
    mod:ToggleLocked(db.locked)
    mod:SortBars()
    mod:LoadPosition()
    mod:SetHandlePoints()
end

function mod:SetSize()
    local lbs = mod:GetLabelData()
    for _, frame in ipairs(mod.bars) do
        frame:Resize(lbs)
    end
    local fw = mod.frame:GetWidth()
    mod:SortBars()
    focusIcon:SetWidth(db.height)
    focusIcon:SetHeight(db.height)
    targetIcon:SetWidth(db.height)
    targetIcon:SetHeight(db.height)
end

function mod:OnProfileChanged(event, newdb)
    db = self.db.profile
    -- set defaults if needed
    if not db.colors then
        db.colors = colors
    end
    mod:FixLabelThemes()
    self:ApplyProfile()
end

do
    local upgradeKeys = {
        anchor = true,
        anchor2 = true,
        anchorFrame = true,
        anchorFrame2 = true,
        anchorTo = true,
        anchorTo2 = true,
        name = true,
        xoffset = true,
        xoffset2 = true,
    }
    -- This method makes sure the label templates match the existing data.
    function mod:FixLabelThemes()
        local l = db.labels or mod.get()
        mod.labelSelect = {}
        db.labels = l
        for id, data in pairs(mod.labelThemes) do
            mod.labelSelect[id] = data.name
            if not l[id] then
                l[id] = data
            else
                for key, val in pairs(data) do
                    if key == "labels" then
                        for lk, lv in pairs(val) do
                            if not l[id][key][lk] then
                                l[id][key][lk] = lv
                            else
                                for labelKey, labelVal in pairs(lv) do
                                    if upgradeKeys[labelKey] then
                                        l[id][key][lk][labelKey] = labelVal
                                    elseif ((labelVal == nil and l[id][key][lk][labelKey] ~= nil) or
                                            (labelVal ~= nil and l[id][key][lk][labelKey] == nil)) then
                                        -- Always update if it has changed from nil to non-nil or vice versa
                                        l[id][key][lk][labelKey] = labelVal
                                    end
                                end
                            end
                        end
                    else
                        l[id][key] = val
                    end
                end
            end
        end
    end
end

function mod:ToggleConfigDialog()
    mod:InterfaceOptionsFrame_OpenToCategory(mod.text)
    mod:InterfaceOptionsFrame_OpenToCategory(mod.main)
end

function mod:FixAnchorVisibility()
    if db.locked and db.hideanchor then
        mod.handle:Hide()
    else
        mod.handle:Show()
    end
end

function mod:ToggleLocked(locked)
    if locked ~= nil then
        db.locked = locked
    else
        db.locked = not db.locked
    end
    mod:FixAnchorVisibility()
    if db.locked then
        mod.handle:EnableMouse(false)
        if not db.showTooltip then
            mod:IterateBars("EnableMouse", false)
        end
    else
        mod.handle:EnableMouse(true)
        mod:IterateBars("EnableMouse", true)
    end
    mod:SortBars()
    if locked == nil and mod.hasInfo then
        mod:info(L["The bars are now %s."], db.locked and "locked" or "unlocked")
    end
end

function mod:OnOptionChanged(var, val)
    if var == "maxbars" or var == "spacing" or var == "padding" then
        mod:SortBars()
    elseif var == "height" or var == "width" then
        mod:SetSize()
    elseif var == "scale" then
        mod.handle:SetScale(val)
        mod.frame:SetScale(val)
        mod:LoadPosition()
    end
end

function mod:SetBackgroundOpt(info, val)
    mod:SetOption(info, val)
    mod:FixBackdrop()
    mod:SortBars()
end

mod.options = {
    general = {
        type = "group",
        name = L["General"],
        order = 1,
        handler = mod,
        get = "GetOption",
        set = "SetOption",
        args = {
            showTooltip = {
                type = "toggle",
                width = "full",
                name = L["Show mouseover tooltip"],
                desc = L["If enabled a tooltip with information about the targets will be shown when you mouse over the bars. If disabled, MagicTargets bars will only intercept mouse clicks when they are unlocked."],
                set = function(_, val)
                    db.showTooltip = val
                    mod:ToggleLocked(db.locked)
                end,
                order = 100,
            },
            coloredNames = {
                type = "toggle",
                name = L["Use class colors in tooltip."],
                width = "full",
                disabled = function()
                    return not db.showTooltip
                end,
                order = 200,
            },
            focus = {
                type = "toggle",
                name = L["Show Focus Marker"],
                desc = L["Show a blue triangle indicating your current focus target."],
                set = function(_, val)
                    db.focus = val
                    mod:UpdateTarget("focus")
                end,
                order = 1
            },
            target = {
                type = "toggle",
                name = L["Show Target Marker"],
                desc = L["Show a green triangle indicating your current target."],
                set = function(_, val)
                    db.target = val
                    mod:UpdateTarget("target")
                end,
                order = 2
            },
            locked = {
                type = "toggle",
                name = L["Lock Magic Targets bar positions."],
                width = "full",
                set = function(_, val)
                    mod:ToggleLocked()
                end,
            },
            growup = {
                type = "toggle",
                name = L["Grow bars upwards."],
                width = "full",
                set = function(_, value)
                    db.growup = value
                    if mod.hasInfo then
                        mod:info(L["Growing bars %s."], db.growup and "up" or "down")
                    end
                    mod:SetHandlePoints()
                    mod:SortBars()
                end,
            },
            eliteonly = {
                type = "toggle",
                name = L["Filter out all non-elite mobs."],
                width = "full",
            },
--[[            fadebars = {
                type = "toggle",
                name = L["Fade bars as health decreases."],
                width = "full",
            },]]
            hideanchor = {
                type = "toggle",
                name = L["Hide anchor when bars are locked."],
                width = "full",
                set = function(_, val)
                    db.hideanchor = val
                    mod:FixAnchorVisibility()
                    if mod.hasInfo then
                        mod:info(L["The anchor will be %s when the bars are locked."], db.hideanchor and "hidden" or "shown")
                    end
                end,
            },
            outsidegroup = {
                type = "toggle",
                name = L["Enable Magic Targets when not in a group."],
                width = "full",
                set = function()
                    db.outsidegroup = not db.outsidegroup
                    mod:ScheduleGroupScan()
                    if mod.hasInfo then
                        mod:info(L["MagicTargets will be %s when solo."], db.outsidegroup and "enabled" or "disabled")
                    end
                end,
            },
        },
    },
    colors = {
        type = "group",
        name = L["Colors"],
        order = 9,
        set = SetColorOpt,
        get = GetColorOpt,
        args = {
            Tank = {
                type = "color",
                name = L["Tank"],
                desc = L["Color used to indicate tanked targets. This is also used while soloing."],
                hasAlpha = true,
            },
            Normal = {
                type = "color",
                name = L["Idle"],
                desc = L["Color used for inactive targets."],
                hasAlpha = true,
            },
            CC = {
                type = "color",
                name = L["Crowd Controlled"],
                desc = L["Color used for crowd controlled targets."],
                hasAlpha = true,
            },
            Notank = {
                type = "color",
                name = L["Untanked"],
                desc = L["Color used for targets that are currently not tanked or crowd controlled (aka the targets killing the DPS or healers)."],
                hasAlpha = true,
            }
        }
    },
    looks = {
        type = "group",
        name = L["Font and Texture"],
        handler = mod,
        get = "GetOption",
        order = 3,
        args = {
            texture = {
                type = "select",
                dialogControl = "LSM30_Statusbar",
                name = L["Texture"],
                desc = L["The background texture used for the bars."],
                values = AceGUIWidgetLSMlists.statusbar,
                set = function(_, val)
                    db.texture = val
                    mod:SetTexture()
                end,
                order = 3
            },
            font = {
                type = "select",
                dialogControl = "LSM30_Font",
                name = L["Font"],
                desc = L["Font used on the bars"],
                values = AceGUIWidgetLSMlists.font,
                set = function(_, key)
                    db.font = key
                    mod:SetFont()
                end,
                order = 1,
            },
            fontsize = {
                order = 1,
                type = "range",
                name = L["Font size"],
                min = 1, max = 30, step = 1,
                set = function(_, val)
                    db.fontsize = val
                    mod:SetFont()
                end,
                order = 2
            },
        },
    },
    labels = {
        type = "group",
        name = L["Labels"],
        handler = mod,
        get = "GetLabelOption",
        set = "SetLabelOption",
        order = 4,
        args = {
            help = {
                type = "description",
                order = 1,
                name = L["These fields are used to set the text on and next to the bars. The following tokens will be replaced with relevant data:\n\n"] ..
                        L["[name] - the name of the unit.\n"] ..
                        L["[level] - the level of the unit.\n"] ..
                        L["[%] - health percentage of the unit.\n"] ..
                        L["[health] - absolute health of the unit.\n"] ..
                        L["[maxhealth] - the units maximum health.\n"] ..
                        L["[target] - the name of the units target.\n"] ..
                        L["[type] - unit type (beast, elemental etc).\n"] ..
                        L["[threat] - unit threat level relative to you."]
            ,
            },
            labelTheme = {
                type = "select",
                order = 2,
                name = L["Label Layout"],
                desc = L["The label layout is used to select which basic set of labels you want. You can then configure the individual labels below."],
                get = "GetOption",
                values = function()
                    return mod.labelSelect
                end,
                set = "ChangeLabelTheme",
            }
        },
        plugins = {}
    },
    labelOptions = {
        text = {
            type = "input",
            name = L["Label Text"],
            desc = L["The text for this label. Tokens are replaced as per the description above."],
            order = 1,
            width = "full",
        },
        width = {
            type = "range",
            name = L["Label Width"],
            desc = L["The width of the label."],
            min = 0, max = 500, step = 1,
            order = 2,
            width = "full",
            hidden = "NoWidthLabel",
        },
        justifyV = {
            type = "select",
            name = L["Vertical Justification"],
            values = {
                TOP = L["Top"],
                CENTER = L["Middle"],
                BOTTOM = L["Bottom"]
            }
        },
        justifyH = {
            type = "select",
            name = L["Horizontal Justification"],
            values = {
                LEFT = L["Left"],
                CENTER = L["Center"],
                RIGHT = L["Right"]
            }
        }
    }
}

function mod:OptReg(optname, tbl, dispname, cmd)
    if dispname then
        optname = "Magic Targets" .. optname
        LibStub("AceConfig-3.0"):RegisterOptionsTable(optname, tbl, cmd)
        if not cmd then
            return LibStub("AceConfigDialog-3.0"):AddToBlizOptions(optname, dispname, "Magic Targets")
        end
    else
        LibStub("AceConfig-3.0"):RegisterOptionsTable(optname, tbl, cmd)
        if not cmd then
            return LibStub("AceConfigDialog-3.0"):AddToBlizOptions(optname, "Magic Targets")
        end
    end
end

function mod:NoWidthLabel(info)
    local var, parent = info[#info], tonumber(info[#info - 1])
    return db.labels[db.labelTheme].labels[tonumber(parent)].width == nil
end

function mod:GetLabelOption(info)
    local var, parent = info[#info], info[#info - 1]
    if parent == "labels" then
        return db[var]
    else
        return db.labels[db.labelTheme].labels[tonumber(parent)][var]
    end
end

function mod:SetLabelOption(info, val)
    local var, parent = info[#info], info[#info - 1]
    if parent == "labels" then
        db[var] = val
    else
        db.labels[db.labelTheme].labels[tonumber(parent)][var] = val
        if var == "text" then
            for _, frame in pairs(mod.bars) do
                mod:SetBarStrings(frame)
            end
        elseif var == "justifyH" or var == "justifyV" then
            for _, frame in pairs(mod.bars) do
                mod:SetupBarLabels(frame)
            end
        else
            mod:SetSize()
        end
    end
end

function mod:ChangeLabelTheme(_, val)
    db.labelTheme = val
    local lbl = mod:GetLabelData()
    for _, frame in pairs(mod.bars) do
        mod:SetupBarLabels(frame)
        mod:SetBarStrings(frame)
    end
    mod:SortBars()
    mod:BuildLabelOptions()
end

function mod:SetupOptions()
    local testbars = {
        type = "toggle",
        name = L["Enable Test Bars"],
        desc = L["Enable display of test bars. This allows you to configure the looks without actively targeting something. Note that when test bars are enabled, normal bars are not shown."],
        width = "full",
        order = 0,
        set = function()
            mod:ToggleTestBars()
        end,
        get = function()
            return mod.testBars
        end,
    }
    mod.options.backgroundFrame = mod:GetConfigTemplate("background")
    mod.options.sizing = mod:GetConfigTemplate("barsize")
    mod.options.sizing.order = 4
    mod.options.backgroundFrame.order = 10
    mod.options.sizing.args.testbars = testbars
    mod.options.colors.args.testbars = testbars
    mod.options.labels.args.testbars = testbars
    mod.options.looks.args.testbars = testbars
    mod.options.backgroundFrame.args.testbars = testbars

    mod:BuildLabelOptions()

    mod.main = mod:OptReg("Magic Targets", mod.options.general)
    mod:OptReg(": bar sizing", mod.options.sizing, L["Bar Sizing"])
    mod:OptReg(": bar colors", mod.options.colors, L["Bar Colors"])
    mod:OptReg(": bar labels", mod.options.labels, L["Bar Labels"])
    mod:OptReg(": frame backdrop", mod.options.backgroundFrame, L["Background Frame"])
    mod:OptReg(": Font & Texture", mod.options.looks, L["Font & Texture"])
    mod.text = mod:OptReg(": Profiles", mod.options.profile, L["Profiles"])

    mod:OptReg("Magic Targets CmdLine", {
        name = L["Command Line"],
        type = "group",
        args = {
            config = {
                type = "execute",
                name = L["Show configuration dialog"],
                func = function()
                    mod:ToggleConfigDialog()
                end,
                dialogHidden = true
            },
        }
    }, nil, { "magictargets", "mgt" })
end

function mod:BuildLabelOptions()
    local cfg = mod.options.labels.plugins
    local lbl = mod:GetLabelData()
    cfg.labels = cfg.labels or mod.get()
    for id, data in pairs(cfg.labels) do
        data.args = nil
    end
    mod.clear(cfg.labels)
    for id, data in pairs(lbl.labels) do
        local lc = mod.get()
        lc.name = data.name
        lc.type = "group"
        lc.order = id
        lc.args = mod.options.labelOptions
        cfg.labels[tostring(id)] = lc
    end
end

function mod:SortBars()
    local w, h = 0, 0
    local anchor
    local lbs = mod:GetLabelData()
    tsort(mod.bars, function(f1, f2)
        -- Sort by unitToken only - can't compare health percentages (secret values)
        return f1.unitToken > f2.unitToken
    end)
    local start = 0
    if #mod.bars > db.maxbars then
        start = #mod.bars - db.maxbars
    end
    for id, frame in pairs(mod.bars) do
        if id <= start then
            frame:Hide()
        else
            local fw, fh = lbs.width(frame), lbs.height(frame)
            frame:ClearAllPoints()

            if fw > w then
                w = fw
            end
            h = h + fh + db.spacing

            if db.growup then
                if anchor then
                    frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, db.spacing)
                else
                    frame:SetPoint("BOTTOMLEFT", mod.frame, "BOTTOMLEFT", db.padding, db.padding)
                end
            else
                if anchor then
                    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -db.spacing)
                else
                    frame:SetPoint("TOPLEFT", mod.frame, "TOPLEFT", db.padding, -db.padding)
                end
            end
            anchor = frame
            frame:Show()
        end
    end

    if h > 0 then
        local p2 = db.padding * 2
        w = w + p2
        db.lastWidth = w

        mod.frame:SetWidth(w)
        mod.frame:SetHeight(h + p2)
        if not mod.frame:IsShown() then
            mod.frame:Show()
        end
    elseif mod.frame:IsShown() then
        mod.frame:Hide()
    end
end

function mod:SetHandlePoints()
    mod.handle:ClearAllPoints()
    if db.growup then
        mod.handle:SetPoint("TOPLEFT", mod.frame, "BOTTOMLEFT")
        mod.handle:SetPoint("TOPRIGHT", mod.frame, "BOTTOMRIGHT")
    else
        mod.handle:SetPoint("BOTTOMLEFT", mod.frame, "TOPLEFT")
        mod.handle:SetPoint("BOTTOMRIGHT", mod.frame, "TOPRIGHT")
    end
    -- We change point from bottom to top and vice versa when changing
    -- growth direction
    mod:SavePosition()
    mod:LoadPosition()
end

function mod:CreateFrame()
    mod.frame = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
    mod.frame:SetMovable(true)
    mod.frame:SetWidth(db.lastWidth or 220)
    mod.frame:SetHeight(10)
    local handle = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
    mod.handle = handle

    handle:RegisterForDrag("LeftButton")
    handle:EnableMouse(not db.locked)
    handle:SetScript("OnDragStart", mod.OnDragStart)
    handle:SetScript("OnDragStop", mod.OnDragStop)

    mod:SetHandlePoints()

    handle.label = handle:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    handle.label:SetAllPoints()
    handle.label:SetText(L["Raid Targets"])
    handle:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        inset = 4,
        edgeSize = 8,
        tile = true,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    local c = db.backdropColors.backgroundColor
    mod.handle:SetBackdropColor(c[1], c[2], c[3], c[4] > 0.2 and c[4] or 0.7)
    c = db.backdropColors.borderColor
    mod.handle:SetBackdropBorderColor(c[1], c[2], c[3], c[4] > 0.2 and c[4] or 0.7)
    mod:SetHandleFont()

    -- The icons to indicate current target and focus target
    local ih = min(db.width, db.height)
    focusIcon = mod.frame:CreateTexture(nil, "OVERLAY")
    focusIcon:SetTexture([[Interface\Addons\MagicTargets\Textures\triangle.tga]])
    focusIcon:SetHeight(ih)
    focusIcon:SetWidth(ih)
    focusIcon:SetVertexColor(0, 0.84, 1, 1)
    focusIcon:Hide()

    targetIcon = mod.frame:CreateTexture(nil, "OVERLAY")
    targetIcon:SetTexture([[Interface\Addons\MagicTargets\Textures\triangle.tga]])
    targetIcon:SetHeight(ih)
    targetIcon:SetWidth(ih)
    targetIcon:SetVertexColor(0.3, 1, 0.6 ,1)
    targetIcon:Hide()
end

function mod:SavePosition()
    local f = mod.frame
    local s = f:GetEffectiveScale()
    local shown = f:IsShown()
    local l = f:GetLeft()
    if not shown then
        f:Show()
    end
    if l then
        if db.growup then
            db.posy = f:GetBottom() * s
            db.anchor = "BOTTOMLEFT"
        else
            db.posy = f:GetTop() * s - UIParent:GetHeight() * UIParent:GetEffectiveScale()
            db.anchor = "TOPLEFT"
        end
        db.posx = l * s
        db.point = nil
    end
    if not shown then
        f:Hide()
    end
end

function mod:LoadPosition()
    local f = mod.frame
    if db.point then
        -- Old position, set it and save new position
        db.point[2] = UIParent
        f:SetPoint(unpack(db.point))
        mod:SavePosition()
        mod:LoadPosition()
    else
        local posx = db.posx
        local posy = db.posy
        local s = f:GetEffectiveScale()
        if posx and posy then
            local anchor = db.anchor
            local f = mod.frame
            f:ClearAllPoints()
            if not anchor then
                anchor = "TOPLEFT"
            end
            f:SetPoint(anchor, posx / s, posy / s)
        else
            f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -300)
        end
    end
end

do
    local function SetLabelFont(label, newFont, newSize, newFlags)
        local font, size, flags = label:GetFont()
        label:SetFont(newFont or font, newSize or size, newFlags or flags)
    end

    function mod:SetHandleFont()
        local font = media:Fetch("font", db.font)
        SetLabelFont(mod.handle.label, font, db.fontsize)
        mod.handle:SetHeight(mod.handle.label:GetHeight() + 10)
    end

    local function SetBarFont(frame)
        local font = media:Fetch("font", db.font)
        for _, label in pairs(frame.labels) do
            SetLabelFont(label, font, db.fontsize)
        end
    end

    function mod:FindAnchorFrame(frame, anchor, id)
        if anchor == "bar" then
            return frame.bar
        elseif anchor == "icon" then
            return frame.icon
        elseif anchor == "frame" then
            return frame
        else
            anchor = frame.labels[anchor]
            if not anchor then
                mod:Print(L["Invalid anchor frame for label"], id, L[". Check the settings."])
                anchor = frame.bar
            end
            return anchor
        end
    end

    function mod:GetLabelData()
        local lbl = db.labels[db.labelTheme]
        return lbl
    end

    function mod:SetupBarLabels(frame)
        frame.labels = frame.labels or {}
        local lbs = mod:GetLabelData()
        -- Create if needed, reset anchors otherwise
        for id, data in pairs(lbs.labels) do
            local f = frame.labels[id]
            if f then
                f:ClearAllPoints()
                f:Hide()
            else
                frame.labels[id] = frame.bar:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
            end
        end
        frame.icon:ClearAllPoints()
        frame.bar:ClearAllPoints()

        -- Do the anchoring
        for id, data in pairs(lbs.labels) do
            local label = frame.labels[id]
            label:Show()
            label:SetHeight(db.height)
            if data.anchor then
                local anchor = mod:FindAnchorFrame(frame, data.anchorFrame, id)
                label:SetPoint(data.anchor, anchor, data.anchorTo, data.xoffset, 0)
            end
            if data.anchor2 then
                local anchor = mod:FindAnchorFrame(frame, data.anchorFrame2, id)
                label:SetPoint(data.anchor2, anchor, data.anchorTo2, data.xoffset2, 0)
            end
            if data.width then
                label:SetWidth(data.width)
            end
            label:SetJustifyH(data.justifyH)
            if data.justifyV == "CENTER" then data.justifyV = "MIDDLE" end
            label:SetJustifyV(data.justifyV)
        end

        frame.icon:SetPoint(lbs.icon.anchor, mod:FindAnchorFrame(frame, lbs.icon.anchorFrame, "[icon]"), lbs.icon.anchorTo, lbs.icon.offsetx, 0)
        frame.bar:SetPoint(lbs.bar.anchor, mod:FindAnchorFrame(frame, lbs.bar.anchorFrame, "[bar]"), lbs.bar.anchorTo, lbs.bar.offsetx, 0)

        frame:SetBarFont()
        frame:Resize(lbs)
    end

    local function GetSize(frame)
        local lbs = mod:GetLabelData()
        return lbs.width(frame), lbs.height(frame)
    end

    local function ResizeBar(frame, lbs)
        frame:ClearAllPoints()
        for id = 1, #lbs.labels do
            local label = frame.labels[id]
            local lw = lbs.labels[id].width
            label:SetHeight(db.height)
            if lw then
                label:SetWidth(lw)
            end
        end
        frame:SetHeight(lbs.height(frame))
        frame:SetWidth(lbs.width(frame))
        frame.bar:SetLength(db.width)
        frame.bar:SetThickness(db.height)
        frame.icon:SetHeight(db.height)
        frame.icon:SetWidth(db.height)
    end

    function mod:OnDragStart()
        if db.locked then
            return
        end
        mod.frame:StartMoving()
    end

    function mod:OnDragStop()
        mod.frame:StopMovingOrSizing()
        mod:SavePosition()
        mod:LoadPosition()
    end

    local function SetColor(frame, cc)
        local bar = frame.bar
        if not bar or not cc then
            return
        end
        local color = db.colors[cc] or db.colors["CC"]
        -- Fadebars disabled - can't do arithmetic with secret health values
        bar:SetColor(color[1], color[2], color[3], color[4])
        frame.color = cc
    end

    function mod:CreateBar(unitToken, current, maxVal)
        local lbs = mod:GetLabelData()
        local frame = tremove(mod.recycledFrames) or CreateFrame("Frame", nil, mod.frame)
        if frame.bar then
            frame.bar:SetValue(current, maxVal)
        else
            frame.bar = frame.bar or mod:NewSimpleBar(frame, current, maxVal, db.width, db.height)
        end

        frame:SetHeight(db.height)
        frame:SetWidth(db.width * 2)

        frame.icon = frame.icon or frame:CreateTexture(nil, "OVERLAY")
        frame.icon:SetWidth(db.height)
        frame.icon:SetHeight(db.height)

        frame.SetBarFont = SetBarFont
        frame.GetSize = GetSize
        frame.Resize = ResizeBar
        frame.SetColor = SetColor

        frame:SetScript("OnEnter", Bar_OnEnter);
        frame:SetScript("OnLeave", Bar_OnLeave);
        frame:SetScript("OnDragStart", mod.OnDragStart)
        frame:SetScript("OnDragStop", mod.OnDragStop)
        frame:RegisterForDrag("LeftButton")
        frame:EnableMouse(not db.locked or db.showTooltip)

        frame.unitToken = unitToken

        mod.bars[#mod.bars + 1] = frame
        mod.unitbars[unitToken] = frame

        mod:SetupBarLabels(frame)
        mod:SetTexture(frame)
        mod:SortBars()
        frame:SetColor("Normal")
        return frame
    end
end

do
    local tokens = {
        "%", "health", "target", "name", "type", "maxhealth", "level", "count", "threat"
    }
    local function tokenize(str, values)
        if strlen(str) <= 2 then
            return str
        end

        local result = ""
        local i = 1
        local len = strlen(str)

        while i <= len do
            if strsub(str, i, i) == "[" then
                -- Found potential token start
                local found = false
                for _, k in ipairs(tokens) do
                    local tokenStr = "[" .. k .. "]"
                    local tokenLen = strlen(tokenStr)
                    if i + tokenLen - 1 <= len and strsub(str, i, i + tokenLen - 1) == tokenStr then
                        -- Found matching token
                        local val = values[k]
                        if type(val) ~= "nil" then
                            -- Use pcall to safely handle secret values
                            local success, formatted = pcall(fmt, "%s", val)
                            if success then
                                result = result .. formatted
                            end
                            -- If pcall fails (secret value), skip this token silently
                        end
                        i = i + tokenLen
                        found = true
                        break
                    end
                end
                if not found then
                    -- Check if this is an unknown token [something]
                    -- If so, skip it entirely (replace with empty string)
                    local closeBracket = nil
                    for j = i + 1, len do
                        if strsub(str, j, j) == "]" then
                            closeBracket = j
                            break
                        elseif strsub(str, j, j) == "[" then
                            -- Found another [ before ], so this isn't a token
                            break
                        end
                    end

                    if closeBracket then
                        -- Found matching ], skip the entire unknown token
                        i = closeBracket + 1
                    else
                        -- Just a standalone [, keep it
                        result = result .. "["
                        i = i + 1
                    end
                end
            else
                -- Regular character
                result = result .. strsub(str, i, i)
                i = i + 1
            end
        end

        return result
    end

    function mod:SetBarStrings(frame)
        local tti = tooltipInfo[frame.unitToken]
        if tti then
            -- Calculate count of players targeting this unit
            if not mod.testBars then
                local count = 0
                if tti.targets then
                    for _ in pairs(tti.targets) do
                        count = count + 1
                    end
                end
                tti.count = count > 0 and count or nil
            end
            for id, data in ipairs(mod:GetLabelData().labels) do
                frame.labels[id]:SetText(tokenize(data.text, tti))
            end
        end
    end
end

do
    local testNames = {
        L["Elder Black Bear"], L["Young Brown Bear"], L["Big Hairy Spider"], L["Evil Gnoll"], L["Round Blob of Ooze"]
    }

    function mod:ToggleTestBars()
        mod.clear(tooltipInfo)

        if mod.testBars then
            mod.testBars = nil
            mod:RemoveAllBars(true)
            mod:ClearCombatData()
            return
        end

        mod.testBars = true
        for id = 1, max(20, db.maxbars) do
            local tti = mod.get()
            tti.name = testNames[rnd(#testNames)]
            tti.level = 10 + rnd(80)
            tti.type = "Animal"
            tti.targets = mod.get()
            if rnd(3) == 1 then
                tti.target = UnitName("player")
            end
            tti.maxhealth = tti.level * 99 + rnd(500)
            tti.health = ceil(tti.maxhealth * (10 + rnd(90)) / 100)
            tti.threat = ceil(10 + rnd(90))
            tti["%"] = ceil(100 * tti.health / tti.maxhealth)
            tooltipInfo[tostring(id)] = tti
            local frame = mod:CreateBar(tostring(id), tti.health, tti.maxhealth)
            mod:SetBarStrings(frame)
            if rnd(5) == 1 then
                mod:SetIcon(frame, rnd(8))
            end
        end
        mod:SortBars()
    end
end

mod.GetOption = mod._GetOption
mod.SetOption = mod._SetOption

