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

local C = LibStub("AceConfigDialog-3.0")
local DBOpt = LibStub("AceDBOptions-3.0")
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
local time = time

local addonEnabled = false
local ccspells
local db, isInGroup, inCombat
local ccstrings = {}
local mobspells = {}
local died = {}
local seen = {}
local mmtargets = {}
local raidicons = {}
local ingroup   = {}
local trivial   = {}
local bars  = nil
local focusIcon, targetIcon 


local tableStore = {}
local options

local colors = {
   Tank    = { [0] = 0, [1] = 0.8, [2] = 0.3 },
   CC      = { [0] = 0, [1] = 0.7, [2] = 0.9 },
   Notank  = { [0] = 1, [1] = 0,   [2] = 0   },
   Normal  = { [0] = 1, [1] = 1,   [2] = 0   }
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
   profile = {
      focus = true,
      target = true,
      growup = false,
      font = "Friz Quadrata TT",
      locked = false,
      mmlisten = true,
      hideanchor = true,
      outsidegroup = true, 
      texture =  "Minimalist",
      fontsize = 8,
      width = 150,
      height = 12,
   }
}

function mod:OnInitialize()
   self.db = LibStub("AceDB-3.0"):New("MagicTargetsDB", defaults, "Default")
   self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileDeleted","OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
   MagicTargetsDB.point = nil
   db = self.db.profile

   options.args.profile = DBOpt:GetOptionsTable(self.db)


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
      bars = self:NewBarGroup("Magic Targets",nil,  db.width, db.height)
      bars:SetColorAt(1.00, 1, 1, 0, 1)
      bars:SetColorAt(0.00, 0.5, 0.5,0, 1)
      bars.RegisterCallback(self, "AnchorClicked")
      bars:SetSortFunction(BarSortFunc)

      local ih = min(db.width, db.height)

      focusIcon = bars:CreateTexture(nil, "OVERLAY")
      focusIcon:SetTexture("Interface\\Addons\\MagicTargets\\Textures\\triangle.tga")
      focusIcon:SetHeight(ih)
      focusIcon:SetWidth(ih)
      focusIcon:SetVertexColor(0, 0.84, 1 ,1)
      focusIcon:Hide()
      
      targetIcon = bars:CreateTexture(nil, "OVERLAY")
      targetIcon:SetTexture("Interface\\Addons\\MagicTargets\\Textures\\triangle.tga")
      targetIcon:SetHeight(ih)
      targetIcon:SetWidth(ih)
      targetIcon:SetVertexColor(0, 1, 0.4 ,1)
      targetIcon:Hide()
   end

   self:ApplyProfile()
   self:SetLogLevel(self.logLevels.TRACE)
   self:RegisterEvent("RAID_ROSTER_UPDATE", "ScheduleGroupScan")
   self:RegisterEvent("PARTY_MEMBERS_CHANGED", "ScheduleGroupScan")
   self:ScheduleGroupScan()
end

function mod:SetTexture()
   bars:SetTexture(media:Fetch("statusbar", db.texture))
end

function mod:SetFont()
   bars:SetFont(media:Fetch("font", db.font), db.fontsize)
end

function mod:OnDisable()
   self:UnregisterEvent("RAID_ROSTER_UPDATE")
   self:UnregisterEvent("PARTY_MEMBERS_CHANGED")
end
local unitTanks = {}
do
   local tankAura = {
      PALADIN = { [GetSpellInfo(25780)] = true },
      WARRIOR = { [GetSpellInfo(71)] = true  },
      DRUID   = { [GetSpellInfo(5487)] = true, [GetSpellInfo(9634)] = true }
   }

   local UnitBuff = UnitBuff
   function mod:IsTank(unit)
      local name = UnitName(unit)
      if unitTanks[name] ~= nil then
	 return unitTanks[name]
      end
      local _,class = UnitClass(unit)
      local auras = tankAura[class]
      if not auras then
--	 mod:debug("Found no auras for class %s", class)
	 unitTanks[name] = false
	 return false
      end
      for i = 1,40 do
	 local buff = UnitBuff(unit, i) 
	 if not buff then break end
--	 mod:debug("Scanning: Found %s (%s)", buff, tostring(auras[buff]))
	 if auras[buff] then
	    unitTanks[name] = true
	    return true
	 end
      end
      unitTanks[name] = false
      return false
   end
end

do
   local groupScanTimer
   function mod:ScheduleGroupScan()
      if groupScanTimer then self:CancelTimer(groupScanTimer, true) end
      groupScanTimer = self:ScheduleTimer("ScanGroupMembers", 5)
   end

   function mod:ScanGroupMembers()
      for id in pairs(ingroup) do ingroup[id] = nil end
      if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then
	 isInGroup = true
      else
	 isInGroup = false
      end
      if isInGroup or db.outsidegroup then
	 mod:IterateRaid(function(self, unitname) ingroup[unitname] = true end)
	 if not addonEnabled then
	    addonEnabled = true
	    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	    self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateTarget", "target")
	    self:RegisterEvent("PLAYER_FOCUS_CHANGED", "UpdateTarget", "focus")
	    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "UpdateBar", "mouseover")
	    self:RegisterEvent("PLAYER_REGEN_ENABLED")
	    self:RegisterEvent("PLAYER_REGEN_DISABLED")
	    self:ClearCombatData()
	    if db.mmlisten then comm:RegisterListener(self, "MM", true) end
	    if InCombatLockdown() then
	       self:PLAYER_REGEN_DISABLED()
	    else
	       self:PLAYER_REGEN_ENABLED()
	    end
	 end
      else
	 if addonEnabled then
	    addonEnabled = false
	    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
	    self:UnregisterEvent("PLAYER_FOCUS_CHANGED")
	    self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
	    comm:UnregisterListener(self, "MM")
	    self:PLAYER_REGEN_ENABLED()
	 end
	 self:ClearCombatData()
	 self:RemoveAllBars(true)
      end
   end
end

function mod:UpdateTarget(target)
   local icon = target == "focus" and focusIcon or targetIcon
   icon:Hide()
   self:UpdateBar(target)

   if UnitExists(target) then
      local bar = bars:GetBar(UnitGUID(target))
      if bar then self:MoveIconTo(icon, bar, target) end
   end
end

function mod:RemoveBar(id)
   local bar = bars:GetBar(id)
   if bar then
      bar.mark = nil
      seen[id] = nil
      bars:RemoveBar(id)
   end
end


function mod:RemoveAllBars(removeAll)
   currentBars = bars:GetBars()
   if currentBars then
      for id,bar in pairs(currentBars) do
	 if removeAll or not mmtargets[id] then
	    mod:RemoveBar(id)
	 end
      end
   end
end

local updated = {}
local tanked  = {}
local function GetRaidIcon(id)
   if id and id > 0 and id <= 8 then return raidicons[id] end
end 

local function SetBarColor(bar,cc)
   if not bar or not cc then return end
   local fade = 0.5 + 0.5 * (bar.value / bar.maxValue)
   local color = colors[cc] or colors["CC"]
   mod:debug("Setting bar color to %s", cc)
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
      and not ingroup[unitname] and not UnitPlayerControlled(target) then
	 -- and not UnitIsPlayer(target) then
      if type == "Critter" or type == "Totem"  then
	 trivial[guid] = true
	 self:RemoveBar(guid)
	 return
      end
      currentbars = currentbars or get()
      local bar = currentbars[guid]
      local mark = GetRaidTargetIndex(target)
      if not bar then
	 bar = bars:NewCounterBar(guid, UnitName(target), UnitHealth(target), UnitHealthMax(target), GetRaidIcon(mark))
	 bar.mark = mark
	 currentbars[guid] = bar
      else
	 bar:SetValue(UnitHealth(target))
	 if bar.mark ~= mark then
	    bar:SetIcon(GetRaidIcon(mark))
	    bar.mark = mark
	 end
      end
      target = target.."target"
      
      if UnitExists(target) and not UnitCanAttack("player", target) and
	 not UnitIsDead(target) and UnitIsPlayer(target) then
	 tanked[guid] = mod:IsTank(target)
      end

      if mmtargets[guid] then
	 if not inCombat then
	    SetBarColor(bar, mmtargets[guid].cc)
	 end
	 mmtargets[guid].mark = mark
      end
      updated[guid] = 1
      seen[guid]    = time()+4
   end
end

function mod:UpdateBars()
   local tt = time()
   inCombat = InCombatLockdown()
   currentbars = bars:GetBars() or get()
   for id in pairs(updated) do updated[id] = nil end
   for id in pairs(unitTanks) do unitTanks[id] = nil end
   for id in pairs(tanked) do tanked[id] = nil end
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
	    if data.name then
	       bar.label:SetText(data.cc and fmt("%s (%s)", data.name, data.cc) or data.name)
	    end
	 end
      end
   end
   self:IterateRaid(self.UpdateBar, true)
   self:UpdateBar("pettarget")
   currentbars = bars:GetBars()
   if currentbars and next(currentbars) then
      for id,seenTime in pairs(seen) do
	 if seenTime < tt then
	    local bar = currentbars[id]
	    if bar and mmtargets[id] then
	       if not inCombat then 
		  bar:SetValue(100)
		  SetBarColor(bar, mmtargets[id].cc)
		  seen[id] = nil
	       end
	    else
	       seen[id] = nil
	    end
	 end
      end
      for id,bar in pairs(currentbars) do
	 if  updated[id] or mmtargets[id] or seen[id] then
	    if mobspells[id] then
	       if not ccstrings[id] then
		  local str = " "
		  for _,tex in pairs(mobspells[id]) do
		     str = fmt("%s|T%s:0|t", str, tex)
		  end
		  ccstrings[id] = str
	       end
	       SetBarColor(bar, "CC") 
	    elseif inCombat then
	       if inGroup then
		  if tanked[id] then
		     SetBarColor(bar, "Tank")
		  elseif tanked[id] == false then
		     SetBarColor(bar, "Notank")
		  else
		     SetBarColor(bar, "Normal")
		  end
	       else
		  SetBarColor(bar, "Tank")
	       end
	    end
	    bar.timerLabel:SetText(fmt("%s%s", updated[id] and tostring(updated[id]) or "", ccstrings[id] or ""))
	 else
	    self:RemoveBar(id)	
	 end
      end
   else
      for id in pairs(seen) do
	 seen[id] = nil -- no bars so reset this
      end
   end
   bars:SortBars()
   self:UpdateTarget("target")
   self:UpdateTarget("focus")
end

function mod:MoveIconTo(icon, bar, target)
   local parent = icon:GetParent()
   local othericon = target == "focus" and targetIcon or focusIcon
   local otherparent = db[target == "focus" and "target" or "focus"] and othericon:GetParent()
   
   if parent.timerLabel and parent ~= otherparent then
      parent.timerLabel:SetPoint("RIGHT", parent, "RIGHT", -3, 0)
   end
   if db[target] then
      bar.timerLabel:SetPoint("RIGHT", bar, "RIGHT", -7, 0)
      icon:SetPoint("LEFT", bar.timerLabel, "RIGHT", 1, 0)
      icon:SetParent(bar)
      icon:Show() 
   else 
      icon:SetParent(bars)
      if bar ~= otherparent then
	 bar.timerLabel:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
      end
  end
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
   end
   if not InCombatLockdown() then
      self:RemoveAllBars(true)
   end
   self:UpdateBars()
end

function mod:OnAssignData(data)
   mmtargets = data
   self:UpdateBars()
   for id,data in pairs(mmtargets) do
      local bar = bars:GetBar(id)
      SetBarColor(bar, data.cc)
   end
end

function mod:OnCommMarkV2(mark, guid, _, name)
   if not name then return end
   if not mmtargets[guid] then
      mmtargets[guid] = get()
   end
   currentbars = bars:GetBars()
   if currentbars then
      for id, bar in pairs(currentbars) do
	 if id ~=guid and bar.mark == mark then
	    bar:SetIcon(nil)
	    bar.mark = nil
	    if mmtargets[id] then
	       mmtargets[id].mark = nil
	    end
	 end
      end
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
--      mod:debug("Unscheduling timer.")
   end
   mod:RemoveAllBars()
   self:ClearCombatData()
   if addonEnabled then
      repeatTimer = self:ScheduleRepeatingTimer("UpdateBars", 5.0)
--      mod:debug("Scheduling 5 second repeating timer.")
   end
end

function mod:ClearCombatData()
   for id in pairs(died) do
      died[id] = nil
   end
   for id in pairs(ccstrings) do ccstrings[id] = nil end
   for id,data in pairs(mobspells) do
      del(data)
      mobspells[id] = nil
   end
--   for id in pairs(seen) do seen[id] = nil end
   for id in pairs(trivial) do trivial[id] = nil end
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

local bit_band = bit.band
local sub = string.sub

local function GetFlagInfo(flags)
   return
   bit_band(flags, COMBATLOG_OBJECT_AFFILIATION_MINE+COMBATLOG_OBJECT_AFFILIATION_PARTY+COMBATLOG_OBJECT_AFFILIATION_RAID)~=0, -- in group
   bit_band(flags, COMBATLOG_OBJECT_TYPE_PLAYER)==COMBATLOG_OBJECT_TYPE_PLAYER, -- is player
   bit_band(flags, COMBATLOG_OBJECT_REACTION_FRIENDLY) ~= 0 -- is friendly
end

function mod:COMBAT_LOG_EVENT_UNFILTERED(_, tt, event, sguid, sname, sflags,
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
      if tguid and tname and sname and ingroup[sname] then
	 seen[tguid] = tt+4
      end
   elseif tisfriend and (sisnpc and not sispet) then
      if sguid and sname and tname and ingroup[tname] then
	 seen[sguid] = tt+4
      end
   end
   
   if event == "UNIT_DIED" or event == "PARTY_KILL" or event == "UNIT_DESTROYED" then
      died[tguid] = true
      self:RemoveBar(tguid)
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

function GetMediaList(type)
   local arrlist = media:List(type)
   local keylist = {}
   for _,val in pairs(arrlist) do
      keylist[val] = val
   end
   return keylist
end

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
   self:SetTexture()
   self:SetFont()
   self:SetSize()
   bars:SortBars()
end

function mod:SetSize()
   local currentBars = bars:GetBars()
   bars:SetWidth(db.width)
   bars:SetHeight(db.height)
   bars.height = db.height
   bars.width = db.width
   if currentBars then
      for id, bar in pairs(currentbars) do
	 bar:SetHeight(db.height)
	 bar.icon:SetHeight(db.height)
	 bar.icon:SetWidth(db.height)
      end
      bars:SortBars()
   end
   focusIcon:SetWidth(db.height)
   focusIcon:SetHeight(db.height)

   targetIcon:SetWidth(db.height)
   targetIcon:SetHeight(db.height)
end

function mod:OnProfileChanged(event, newdb)
   if event ~= "OnProfileDeleted" then
      db = self.db.profile
      self:ApplyProfile()
   end
   self:SetStatusText(string.format("Active profile: %s", self.db:GetCurrentProfile()))
end

function mod:ToggleConfigDialog()
   if C.OpenFrames["Magic Targets"] then
      C:Close("Magic Targets")
   else
      C:Open("Magic Targets")
      self:SetStatusText(string.format("Active profile: %s", self.db:GetCurrentProfile()))
   end
end

do
   local updateStatusTimer
   function mod:SetStatusText(text, update)
      local frame = C.OpenFrames["Magic Targets"]
      if frame then
	 frame:SetStatusText(text)
	 if updateStatusTimer then self:CancelTimer(updateStatusTimer, true) end
	 if update then
	    updateStatustimer = self:ScheduleTimer("SetStatusText", 10, string.format("Active profile: %s", self.db:GetCurrentProfile()))
	 else
	    updateStatustimer = false 
	 end
      end
   end
end

options = { 
   type = "group",
   name = "Magic Targets",
   handler = mod,
   args = {
      config = {
	 type = "execute",
	 name = "Toggle configuration dialog",
	 func = "ToggleConfigDialog",
	 dialogHidden = true
      }, 
      general = {
	 type = "group",
	 name = "General",
	 order = 1,
	 args = {
	    ["focus"] = {
	       type = "toggle",
	       name = "Show Focus Marker",
	       desc = "Show a blue triangle indicating your current focus target.",
	       set = function() db.focus = not db.focus mod:UpdateTarget("focus") end,
	       get = function() return db.focus end,
	       order = 1
	    },
	    ["target"] = {
	       type = "toggle",
	       name = "Show Target Marker",
	       desc = "Show a green triangle indicating your current target.",
	       set = function() db.target = not db.target mod:UpdateTarget("target") end,
	       get = function() return db.target end,
	       order = 2
	    },
	    ["lock"] = {
	       type = "toggle",
	       name = "Lock or unlock the MT bars.",
	       width = "full",
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
	       width = "full",
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
	       width = "full",	
	       set = function()
			db.hideanchor = not db.hideanchor
			if db.locked and db.hideanchor then
			   bars:HideAnchor()
			else
			   bars:ShowAnchor()
			end
			mod:info("The anchor will be %s when the bars are locked.", db.hideanchor and "hidden" or "shown")
		     end,
	       get = function() return db.hideanchor end
	    },
	    ["mmlisten"] = {
	       type = "toggle",
	       name = "Listen to Magic Marker target assignments.",
	       width = "full",
	       set = function()
			db.mmlisten = not db.mmlisten
			if db.mmlisten then
			   comm:RegisterListener(mod, "MM", true)
			   mod:info("Listening to Magic Marker comm events.")
			else
			   mod:info("Not listening to Magic Marker comm events.")
			   comm:UnregisterListener(mod, "MM")
			end

		     end,
	       get = function() return db.mmlisten end
	    },
	    ["outsidegroup"] = {
	       type = "toggle",
	       name = "Enable Magic Targets when not in a group.",
	       width = "full",
	       set = function()
			db.outsidegroup = not db.outsidegroup
			mod:ScheduleGroupScan()
			mod:info("MagicTargets will be %s when solo.", db.outsidegroup and "enabled" or "disabled")
		     end,
	       get = function() return db.outsidegroup end
	    },
	 },
      },
      texture = {
	 type = "group",
	 name = "Texture",
	 order = 2,
	 args = {
	    ["texture"] = {
	       type = "multiselect",
	       name = "Texture",
	       values = GetMediaList("statusbar"),
	       set = function(_,val, state)
			if val ~= db.texture and state then
			   db.texture = val
			end
			mod:SetTexture()
		     end,
	       get = function(_,key) return db.texture == key end
	    },
	 }
      },
      sizing = {
	 type = "group",
	 name = "Bar Size",
	 order = 4,
	 args = {
	    height = {
	       type = "range",
	       name = "Height",
	       width = "full",
	       min = 1, max = 50, step = 1,
	       set = function(_,val) db.height = val mod:SetSize() end,
	       get = function() return db.height end
	    }, 
	    width = {
	       type = "range",
	       name = "Width",
	       width = "full",
	       min = 1, max = 300, step = 1,
	       set = function(_,val) db.width = val mod:SetSize() end,
	       get = function() return db.width end
	    }, 
	    maxbars = {
	       type = "range",
	       name = "Max number of bars",
	       min = 0, max = 30, step = 1,
	       set = function(_,val) db.maxbars = val mod:SetSize() end,
	       get = function() return db.maxbars end,
	       hidden = true,
	    }, 
	 }
      },
      font = {
	 type = "group",
	 name = "Font",
	 order = 3,
	 args = {
	    ["fontname"] = {
	       type = "multiselect",
	       name = "Font",
	       values = GetMediaList("font"),
	       set = function(_,val, state)
			if val ~= db.font and state then
			   db.font = val
			   mod:SetFont()
			end
		     end,
	       get = function(_,key) return db.font == key end
	    },
	    ["fontsize"] = {
	       type = "range",
	       name = "Font size",
	       min = 1, max = 30, step = 1,
	       set = function(_,val) db.fontsize = val mod:SetFont() end,
	       get = function() return db.fontsize end
	    },
	 },
      }
   }
}
LibStub("AceConfig-3.0"):RegisterOptionsTable("Magic Targets", options, {"magictargets", "mgt"})
mod.optFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Magic Targets", "Magic Targets")
