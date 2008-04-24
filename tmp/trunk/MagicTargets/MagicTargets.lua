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
-- 
MagicTargets = LibStub("AceAddon-3.0"):NewAddon("MagicTargets", "AceEvent-3.0", "LibBars-1.0", 
						"AceTimer-3.0", "LibLogger-1.0", "AceConsole-3.0")

local media = LibStub("LibSharedMedia-3.0")
local mod = MagicTargets
local currentbars
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
local tinsert = table.insert
local tremove = table.remove

local ccspells
local db
local playerInCombat = false
local ccstrings = {}
local  mobspells = {}
local died = {}
local seen = {}
local mmtargets = {}
local raidicons = {}
local ingroup   = {}
local trivial   = {}
local bars 

local tableStore = {}
local options

local colors = {
    tank = { [0] = 0, [1] = 0.8, [2] = 0.3 },
    cc   = { [0] = 0, [1] = 0.7, [2] = 0.9 }
}
   

local function get()
   return tremove(tableStore) or {}
end

local function del(tbl)
   if type(tbl) ~= "table" then return end
   for id,data in pairs(tbl) do
      if type(data) == "table" then
	 del(data)
      end
      tbl[id] = nil
   end
   tinsert(tableStore, tbl)
end

local iconPath = "Interface\\AddOns\\MagicTargets\\Textures\\%d.tga"

local defaults = {
   growup = false,
   locked = false,
   mmlisten = true,
   hideanchor = true,
   outsidegroup = true,
}
function mod:OnInitialize()
   self.db = LibStub("AceDB-3.0"):New("MagicTargetsDB", defaults, "Default")
   self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileDeleted","OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

   db = self.db.profile
   for i = 1,8 do
      raidicons[i] = iconPath:format(i)
   end
   ccspells = comm.spellIdToCCID
end

-- Sort first by Magic Marker priority, then by health and lastly by guid.
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
      bars.RegisterCallback(self, "AnchorClicked")
      bars:SetSortFunction(BarSortFunc)
   end

   self:ApplyProfile()

   local tex = media:Fetch("statusbar", "Minimalist")	
   bars:SetTexture(tex)
   self:SetLogLevel(self.logLevels.TRACE)
   self:RegisterEvent("RAID_ROSTER_UPDATE", "ScheduleGroupScan")
   self:RegisterEvent("PARTY_MEMBERS_CHANGED", "ScheduleGroupScan")
   self:ScheduleGroupScan()
end

function mod:OnDisable()
   self:UnregisterEvent("RAID_ROSTER_UPDATE")
   self:UnregisterEvent("PARTY_MEMBERS_CHANGED")
end

do
   local groupScanTimer, addonEnabled
   function mod:ScheduleGroupScan()
      if groupScanTimer then self:CancelTimer(groupScanTimer, true) end
      groupScanTimer = self:ScheduleTimer("ScanGroupMembers", 5)
   end

   function mod:ScanGroupMembers()
      for id in pairs(ingroup) do ingroup[id] = nil end
      if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 or db.outsidegroup then
	 mod:IterateRaid(function(self, unitname) ingroup[unitname] = true end)
	 if not addonEnabled then 
	    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	    self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateBar", "target")
	    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "UpdateBar", "mouseover")
	    self:RegisterEvent("PLAYER_REGEN_ENABLED")
	    self:RegisterEvent("PLAYER_REGEN_DISABLED")
	    if db.mmlisten then comm:RegisterListener(self, "MM", true) end
	    if InCombatLockdown() then
	       self:PLAYER_REGEN_DISABLED()
	    else
	       self:PLAYER_REGEN_ENABLED()
	    end
	 end
      elseif addonEnabled then
	 addonEnabled = false
	 self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	 self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	 self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	 self:UnregisterEvent("PLAYER_TARGET_CHANGED")
	 self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
	 comm:UnregisterListener(self, "MM")
	 self:PLAYER_REGEN_ENABLED()
      end
   end
end

local updated = {}

local function GetRaidIcon(id)
   if id and id > 0 and id <= 8 then return raidicons[id] end
end 

local function SetBarColor(bar,cc)
   if not bar then return end
   local fade = 0.3 + 0.7 * (bar.value / bar.maxValue)
   local color = cc == 'Tank' and colors.tank or colors.cc
   bar.texture:SetVertexColor(color[0]*fade, color[1]*fade, color[2]*fade,1)
end

function mod:UpdateBar(target)
   if not UnitExists(target) then return end
   local guid = UnitGUID(target)
   if updated[guid] then
      updated[guid] = updated[guid] + 1
      return
   elseif trivial[guid] or died[guid] then
      return
   end
   local type = UnitCreatureType(target)
   if UnitCanAttack("player", target) and not UnitIsDead(target)
      and not UnitPlayerControlled(target)  and not UnitIsPlayer(target) then
      if type == "Critter" or type == "Totem"  then
	 trivial[guid] = true
	 bars:RemoveBar(guid)
	 return
      end
      currentbars = currentbars or get()
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
   currentbars = bars:GetBars() or get()
   for id in pairs(updated) do updated[id] = nil end
   
   for id,data in pairs(mmtargets) do
      if not died[id] then
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
   end
   self:UpdateBar("focus")
--   if playerInCombat then
   mod:IterateRaid(self.UpdateBar, true)
--   end
   currentbars = bars:GetBars()
   if currentbars then
      -- uncomment this if the "seen" detection ever works correctly! >:-)
--      for id,name in pairs(seen) do
--	 if not currentbars[id] and not trivial[id] and not died[id] then
--	    currentbars[id] = bars:NewCounterBar(id, name, 100, 100)
--	 end
--      end
      if next(currentbars) then
	 for id in pairs(currentbars) do
	    if  updated[id] or mmtargets[id] or seen[id] then
	       if mobspells[id] and not ccstrings[id] then
		  local str = " "
		  for _,tex in pairs(mobspells[id]) do
		     str = fmt("%s|T%s:0|t", str, tex)
		  end
		  ccstrings[id] = str
	       end
	       currentbars[id].timerLabel:SetText(fmt("%s%s", updated[id] and tostring(updated[id]) or "", ccstrings[id] or ""))
	    else
	       bars:RemoveBar(id)	
	    end
	 end
      end
   end
   bars:SortBars()
end

do
   local raidtarget, partytarget
   function mod:IterateRaid(callback, target, ...)
      local id, name, class, map
      if GetNumRaidMembers() > 0 then
	 if target then 
	    if not raidtarget then raidtarget = get() end
	    map = raidtarget
	 end
	 for id = 1,GetNumRaidMembers() do
	    if target then
	       if not map[id] then map[id] = "raid"..id..(target and "target" or "") end
	       callback(self, map[id], ...)
	    else
	       callback(self, GetRaidRosterInfo(id), ...)
	    end
	 end
      else
	 if GetNumPartyMembers() > 0 then
	    if not partytarget then partytarget = get() end
	    map = partytarget
	    for id = 1,GetNumPartyMembers() do
	       if not map[id] then map[id] = "party"..id end
	       callback(self, target and (map[id].."target") or UnitName(map[id]), ...)
	    end
	 end
	 callback(self, target and "target" or UnitName("player"), ...);
      end   
   end
end

function mod:OnCommResetV2()
   for id in pairs(mmtargets) do
      mmtargets[id] = nil
      bars:RemoveBar(id)
   end
   if not InCombatLockdown() then
      currentBars = bars:GetBars()
      if currentBars then
	 for id in pairs(currentBars) do
	    bars:RemoveBar(id)
	 end
      end
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
   if not mmtargets[guid] then
      mmtargets[guid] = get()
   end
   mmtargets[guid].name = name
   mmtargets[guid].mark = mark
   self:UpdateBars()
end

function mod:OnCommUnmarkV2(guid, mark)
   if mmtargets[guid] then
      del(mmtargets[guid])
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
   currentbars = bars:GetBars()
   if currentbars then
      for guid in pairs(currentbars) do
	 if not mmtargets[guid] then
	    bars:RemoveBar(guid)
	 end
      end
   end
   for id in pairs(died) do died[id] = nil end
   for id in pairs(ccstrings) do ccstrings[id] = nil end
   for id,data in pairs(mobspells) do
      del(data)
      mobspells[id] = nil
   end
   for id in pairs(seen) do seen[id] = nil end
   for id in pairs(trivial) do trivial[id] = nil end
   playerInCombat = false
   if repeatTimer then self:CancelTimer(repeatTimer) end
   repeatTimer = self:ScheduleRepeatingTimer("UpdateBars", 5.0)
end

function mod:PLAYER_REGEN_DISABLED()
   if repeatTimer then self:CancelTimer(repeatTimer) end
   repeatTimer = self:ScheduleRepeatingTimer("UpdateBars", 0.5)
   playerInCombat = true
end

local bit_band = bit.band
local sub = string.sub

local function GetFlagInfo(flags)
   return
   bit_band(flags, COMBATLOG_OBJECT_AFFILIATION_MINE+COMBATLOG_OBJECT_AFFILIATION_PARTY+COMBATLOG_OBJECT_AFFILIATION_RAID)~=0, -- in group
   bit_band(flags, COMBATLOG_OBJECT_TYPE_PLAYER)==COMBATLOG_OBJECT_TYPE_PLAYER, -- is player
   bit_band(flags, COMBATLOG_OBJECT_REACTION_FRIENDLY) ~= 0 -- is friendly
end

function mod:COMBAT_LOG_EVENT_UNFILTERED(_, _, event, sguid, sname, sflags,
					 tguid, tname, tflags, spellid, spellname)
   local sinGroup, sisPlayer, sisFriend = GetFlagInfo(sflags)
   local tinGroup, tisPlayer, tisFriend = GetFlagInfo(tflags)

   local sispet = bit_band(sflags, COMBATLOG_OBJECT_TYPE_PET+COMBATLOG_OBJECT_TYPE_GUARDIAN)~=0
   local sisnpc = bit_band(sflags, COMBATLOG_OBJECT_TYPE_NPC) == COMBATLOG_OBJECT_TYPE_NPC

   local tispet = bit_band(tflags, COMBATLOG_OBJECT_TYPE_PET+COMBATLOG_OBJECT_TYPE_GUARDIAN)~=0
   local tisnpc = bit_band(tflags, COMBATLOG_OBJECT_TYPE_NPC) == COMBATLOG_OBJECT_TYPE_NPC

   local sisfriend = (sinGroup and not sispet) or (sisPlayer and sisFriend)
   local tisfriend = (tinGroup and not tispet) or (tisPlayer and tisFriend)


   -- This stuff here is meant to detect new mobs we're engaged with.
   if sisfriend and (tisnpc and not tispet) then
      if tguid and tname and not seen[tguid] and sname and ingroup[sname] then
--	 mod:trace("Recording %s as seen.", tname)
	 seen[tguid] = tname
      end
   elseif tisfriend and (sisnpc and not sispet) then
      if sguid and sname and not seen[sguid] and tname and ingroup[tname] then
--	 mod:trace("Recording %s as seen.", sname)
	 seen[sguid] = sname
      end
   end
   
   if not died[tguid] then
      -- This is on ze list of known npcs, and it's alive
      if event == "UNIT_DIED" or event == "PARTY_KILL" or event == "UNIT_DESTROYED" then
	 died[tguid] = true
	 bars:RemoveBar(tguid)
      end
   end
   if event == "SPELL_AURA_APPLIED" then
      -- record crowd control
      if ccspells[spellid] then
	 local cc = mobspells[tguid] or get()
	 if not cc[spellid] then 
	    cc[spellid] = select(3, GetSpellInfo(spellid))
	    mobspells[tguid] = cc
	    ccstrings[tguid] = nil
	 end
      end
   elseif event == "SPELL_AURA_REMOVED" then
      local cc = mobspells[tguid]
      if cc then
	 if cc[spellid] then
	    cc[spellid] = nil
	    ccstrings[tguid] = nil
	    if not next(cc) then
	       del(cc)
	       mobspells[tguid] = nil
	    end
	 end
      end
   end
end


-- Config option handling below
function mod:ApplyProfile()
   -- configure based on saved data
   if db.point then
      bars:SetPoint(unpack(db.point))
   else
      bars:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -300)
   end
   bars:ReverseGrowth(db.growup)
   if db.locked then bars:Lock() else bars:Unlock() end
   if db.hideanchor and db.locked then bars:HideAnchor() else bars:ShowAnchor() end
--      self:SetLogLevel(db.logLevel)
end

function mod:OnProfileChanged(event, newdb)
   if event ~= "OnProfileDeleted" then
      db = self.db.profile
      self:ApplyProfile()
   end
end


options = { 
   type = "group",
   name = "Magic Targets",
   handler = mod,
   args = {
      ["lock"] = {
	 type = "toggle",
	 name = "Lock or ulock the MT bars.",
	 set = function()
		  db.locked = not db.locked
		  if db.locked then
		     bars:Lock()
		  else
		     bars:Unlock()
		  end
		  if db.hideanchor then
		     -- Show anchor if we're unlocked but lock it again if we're locked
		     if db.locked then bars:HideAnchor() else bars:ShowAnchor() end
		  end
		  mod:info("The bars are now %s.", db.locked and "locked" or "unlocked")
	       end,
	 get = function() return db.locked end,
      },
      ["grow"] = {
	 type = "toggle",
	 name = "Grow bars upwards.",
	 set = function()
		  db.growup = not db.growup
		  bars:ReverseGrowth(db.growup)
		  mod:info("Growing bars %s.", db.growup and "up" or "down")
	       end,
	 get = function() return db.growup end
      },
      ["hideanchor"] = {
	 type = "toggle",
	 name = "Hide anchor when bars are locked.",
	 set = function()
		  db.hideanchor = not db.hideanchor
		  if db.locked and db.hideanchor then
		     bars:HideAnchor()
		  else
		     bars:ShowAnchor()
		  end
	       end,
	 get = function() return db.hideanchor end
      },
      ["mmlisten"] = {
	 type = "toggle",
	 name = "Listen to Magic Marker target assignments.",
	 set = function()
		  db.mmlisten = not db.mmlisten
		  if db.mmlisten then
		     comm:RegisterListener(self, "MM", true)
		  else
		     comm:UnregisterListener(self, "MM")
		  end
	       end,
	 get = function() return db.mmlisten end
      },
      ["outsidegroup"] = {
	 type = "toggle",
	 name = "Enable Magic Targets when not in a group.",
	 set = function()
		  db.outsidegroup = not db.outsidegroup
		  mod:ScheduleGroupScan()
	       end,
	 get = function() return db.outsidegroup end
      },
   }
}

LibStub("AceConfig-3.0"):RegisterOptionsTable("MagicTargets", options, "magictargets")
