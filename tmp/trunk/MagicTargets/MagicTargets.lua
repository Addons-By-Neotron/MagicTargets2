--[[
**********************************************************************
MagicTargets - a raid loot and DKP tracker.
**********************************************************************
This file is part of MagicTargets, a World of Warcraft Addon

MagicTargets is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MagicTargets is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MagicTargets.  If not, see <http://www.gnu.org/licenses/>.
**********************************************************************
]]

MagicTargets = LibStub("AceAddon-3.0"):NewAddon("MagicTargets", "AceEvent-3.0", "LibBars-1.0",
						"AceTimer-3.0", "LibLogger-1.0", "AceConsole-3.0")

local media = LibStub("LibSharedMedia-3.0")
local mod = MagicTargets
local currentbars = {}
local comm = LibStub("MagicComm-1.0")

local UnitCreatureType = UnitCreatureType
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsDead = UnitIsDead
local UnitPlayerControlled = UnitPlayerControlled
local UnitIsPlayer = UnitIsPlayer
local UnitGUID = UnitGUID
local GetRaidTargetIndex = GetRaidTargetIndex
local fmt = string.format
local db
local playerInCombat = false
local died = {}
local seen = {}

local mmtargets = {}
local raidicons = {}
local bars 

local colors = {
    tank = { [0] = 0, [1] = 0.8, [2] = 0.3 },
    cc   = { [0] = 0, [1] = 0.7, [2] = 0.9 }
}
   
   

local iconPath = "Interface\\AddOns\\MagicTargets\\Textures\\%d.tga"

function mod:OnInitialize()
   MagicTargetsDB = MagicTargetsDB or {}
   db = MagicTargetsDB
   for i = 1,8 do
      raidicons[i] = iconPath:format(i)
   end
end

local function BarSortFunc(a, b)
   local amm = mmtargets[a.name]
   local bmm = mmtargets[b.name]
   local av = 0
   local bv = 0
   if amm then av = 1000+(amm.val or 0)+(amm.cc == 'Tank' and 100 or 0) else av = a.value end
   if bmm then bv = 1000+(bmm.val or 0)+(bmm.cc == 'Tank' and 100 or 0) else bv = b.value end
   if av == bv then return a.name > b.name else return av > bv end
end

function mod:OnEnable()
   if not bars then
      bars = self:NewBarGroup("Magic Targets",nil,  150, 12)
      bars:SetFont(nil, 8)
      bars:SetColorAt(1.00, 1, 1, 0, 1)
      bars:SetColorAt(0.00, 0.3, 0.1,0, 1)
      if db.point then
	 bars:SetPoint(unpack(db.point))
      else
	 bars:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -300)
      end
      bars.RegisterCallback(self, "AnchorClicked")
      bars:SetSortFunction(BarSortFunc)
   end
   local tex = media:Fetch("statusbar", "Minimalist")	
   bars:SetTexture(tex)
   comm:RegisterListener(self, "MM", true)
   self:SetLogLevel(self.logLevels.TRACE)
   self:RegisterEvent("PLAYER_REGEN_ENABLED")
   self:RegisterEvent("PLAYER_REGEN_DISABLED")
   if InCombatLockdown() then
      self:PLAYER_REGEN_DISABLED()
   end
end

function mod:OnDisable()
   comm:UnregisterListener(self, "MM")
   self:UnregisterEvent("PLAYER_REGEN_ENABLED")
   self:UnregisterEvent("PLAYER_REGEN_DISABLED")
   self:PLAYER_REGEN_ENABLED()
end

local updated = {}

local function GetRaidIcon(id)
   if id and id > 0 and id <= 8 then return raidicons[id] end
end 

local function SetBarColor(bar,cc)
   local fade = 0.3 + 0.7 * (bar.value / bar.maxValue)
   local color = cc == 'Tank' and colors.tank or colors.cc
   bar.texture:SetVertexColor(color[0]*fade, color[1]*fade, color[2]*fade,1)
end

function mod:UpdateBar(target)
   local guid = UnitGUID(target)
   if updated[guid] then
      updated[guid] = updated[guid] + 1
      return
   end
   local type = UnitCreatureType(target)
   if UnitExists(target) and UnitCanAttack("player", target)
      and type ~= "Critter" and type ~= "Totem" and not UnitIsDead(target)
      and not UnitPlayerControlled(target)  and not UnitIsPlayer(target) then
      local bar = currentbars[guid]
      local mark = GetRaidTargetIndex(target)
      if not bar then
	 bar = bars:NewCounterBar(guid, UnitName(target), UnitHealth(target), UnitHealthMax(target), GetRaidIcon(mark))
	 mark = mark
	 currentbars[guid] = bar
      else
	 bar:SetValue(UnitHealth(target))
	 if bar.mark ~= mark then
	    bar:SetIcon(GetRaidIcon(mark))
	    bar.mark = mark
	 end
      end
      
      if mmtargets[guid] and mmtargets[guid].cc then
	 SetBarColor(bar, mmtargets[guid].cc)
      end
      updated[guid] = 1
   end
end

function mod:UpdateBars()
   currentbars = bars:GetBars() or {}
   for id in pairs(updated) do updated[id] = nil end

   for id,data in pairs(mmtargets) do
      local bar = currentbars[id]
      if not bar then
	 local bar = bars:NewCounterBar(id, data.cc and fmt("%s (%s)", data.name, data.cc) or data.name, 100, 100, GetRaidIcon(data.mark))
	 bar.mark = data.mark
      else
	 if bar.mark ~= data.mark then
	    bar:SetIcon(GetRaidIcon(data.mark))
	    bar.mark = data.mark
	 end
	 bar.label:SetText(data.cc and fmt("%s (%s)", data.name, data.cc) or data.name)
      end
   end
   if playerInCombat then
      mod:IterateTargets(self.UpdateBar)
   end
   if next(currentbars) then
      for id in pairs(currentbars) do
	 if  updated[id] or mmtargets[id] or seen[id] then
	    currentbars[id].timerLabel:SetText(updated[id] and tostring(updated[id]) or "")
	 else
	    bars:RemoveBar(id)	
	 end
      end
   end
   bars:SortBars()
end

do
   local raidtarget, partytarget
   function mod:IterateTargets(callback, ...)
      local id, name, class
      if GetNumRaidMembers() > 0 then
	 if not raidtarget then raidtarget = {} end
	 for id = 1,GetNumRaidMembers() do
	    if not raidtarget[id] then raidtarget[id] = "raid"..id.."target" end
	    callback(self, raidtarget[id], ...)
	 end
      else
	 if GetNumPartyMembers() > 0 then
	    if not partytarget then partytarget = {} end
	    for id = 1,GetNumPartyMembers() do
	       if not partytarget[id] then partytarget[id] = "party"..id.."target" end
	       callback(self, partytarget[id], ...)
	    end
	 end
	 callback(self, "target", ...);
      end   
   end
end

function mod:OnCommResetV2()
   for id in pairs(mmtargets) do
      mmtargets[id] = nil
   end
   self:UpdateBars()
end

function mod:OnAssignData(data)
   mmtargets = data
   self:UpdateBars()
   for id,data in pairs(mmtargets) do
      if data.cc then
	 SetBarColor(bars:GetBar(id), data.cc)
      end
   end
end

function mod:OnCommMarkV2(mark, guid, _, name)
   if not name then return end
   if mmtargets[guid] then
      mmtargets[guid].name = name
      mmtargets[guid].mark = mark
   else
      mmtargets[guid] = { name = name, mark = mark }
   end
   self:UpdateBars()
end

function mod:OnCommUnmarkV2(guid, mark)
   if mmtargets[guid] then
      mmtargets[guid] = nil
   end
   self:UpdateBars()
end

function mod:AnchorClicked(cbk, group, button)
   db.point = {group:GetPoint()}
end


local repeatTimer

function mod:PLAYER_REGEN_ENABLED()
   if repeatTimer then
      self:CancelTimer(repeatTimer, true)
      repeatTimer = nil
   end
   self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
   currentbars = bars:GetBars()
   if currentbars then
      for guid in pairs(currentbars) do
	 if not mmtargets[guid] then
	    bars:RemoveBar(guid)
	 end
      end
   end
   for id in pairs(died) do
      died[id] = nil
   end
   for id in pairs(seen) do
      seen[id] = nil
   end
   playerInCombat = false
end

function mod:PLAYER_REGEN_DISABLED()
   if repeatTimer then
      self:CancelTimer(repeatTimer)
   end
   repeatTimer = self:ScheduleRepeatingTimer("UpdateBars", 0.5)
   self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
   playerInCombat = true
end

function mod:COMBAT_LOG_EVENT_UNFILTERED(_, _, event, _, _, _,
					 guid, name, _, spellid, spellname)
   if not seen[guid] then
      -- yes this is a it ugly but we keep track of mobs we've seen combat events from so we can show them
      seen[guid] = true
   end
   
   if event == "SPELL_AURA_APPLIED" then
      -- mark CC'd mobs
   elseif event == "UNIT_DIED" or event == "PARTY_KILL" or event == "UNIT_DESTROYED" then
      died[guid] = true
      seen[guid] = nil
      mmtargets[guid] = nil
   end
end
