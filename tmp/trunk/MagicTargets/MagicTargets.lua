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

-- Silently fail embedding if it doesn't exist
local LibStub = LibStub

LibStub("AceAddon-3.0"):EmbedLibrary(MagicTargets, "LibFuBarPlugin-MT-3.0", true)
local C = LibStub("AceConfigDialog-3.0")
local DBOpt = LibStub("AceDBOptions-3.0")
local media = LibStub("LibSharedMedia-3.0")
local mod = MagicTargets
local currentbars
local comm = LibStub("MagicComm-1.0")

local GetSpellInfo = GetSpellInfo
local UnitBuff = UnitBuff
local UnitLevel = UnitLevel
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitCreatureType = UnitCreatureType
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsDead = UnitIsDead
local UnitPlayerControlled = UnitPlayerControlled
local UnitIsPlayer = UnitIsPlayer
local UnitGUID = UnitGUID
local UnitClass = UnitClass
local UnitName = UnitName
local GetNumPartyMembers = GetNumPartyMembers
local GetNumRaidMembers = GetNumRaidMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local InCombatLockdown = InCombatLockdown
local GetRaidTargetIndex = GetRaidTargetIndex
local fmt = string.format
local tinsert = table.insert
local tconcat = table.concat
local tremove = table.remove
local time = time
local type = type
local pairs = pairs
local min = min
local tostring = tostring
local next = next
local sort = sort
local select = select
local unpack = unpack

local addonEnabled = false
local ccspells
local db, isInGroup, inCombat
local ccstrings = {}
local mobspells = {}
local tooltipInfo = {}
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


local classColors = {}
for k, v in pairs(RAID_CLASS_COLORS) do
	classColors[k] = ("|cff%02x%02x%02x"):format(v.r * 255, v.g * 255, v.b * 255)
end

-- Helper table to cache colored player names.
local coloredNames = setmetatable({}, {__index =
	function(self, key)
		if type(key) == "nil" then return nil end
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
   Tank    = { [1] = 0, [2] = 1,   [3] = 0.2, [4] = 1 },
   CC      = { [1] = 0, [2] = 0.7, [3] = 0.9, [4] = 1 },
   Notank  = { [1] = 1, [2] = 0,   [3] = 0,   [4] = 1 },
   Normal  = { [1] = 1, [2] = 1,   [3] = 0.5, [4] = 1 }
}

function mod.clear(tbl)
   if type(tbl) == "table" then
      for id,data in pairs(tbl) do
	 if type(data) == "table" then mod.del(data) end
	 tbl[id] = nil
      end
   end
end   
   

function mod.get()
   return tremove(tableStore) or {}
end

function mod.del(tbl, index)
   local todel = tbl
   if index then todel = tbl[index] end
   if type(todel) ~= "table" then return end
   mod.clear(todel)
   tinsert(tableStore, todel)
   if index then tbl[index] = nil end
end

local function SetColorOpt(arg, r, g, b, a)
   local color = arg[#arg]
   db.colors[color][1] = r
   db.colors[color][2] = g
   db.colors[color][3] = b
   db.colors[color][4] = a
end

local function GetColorOpt(arg)
   return unpack(db.colors[arg[#arg]])
end


local iconPath = "Interface\\AddOns\\MagicTargets\\Textures\\%d.tga"

local defaults = {
   profile = {
      focus = true,
      coloredNames = true,
      target = true,
      eliteonly = false,
      growup = false,
      font = "Friz Quadrata TT",
      locked = false,
      mmlisten = true,
      hideanchor = true,
      outsidegroup = true,      
      texture =  "Minimalist",
      maxbars = 20,
      fontsize = 8,
      width = 150,
      height = 12,
      fadebars = false,
      HideMinimapButton = false,
      showTooltip = true,
      scale = 1.0,
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

   if not db.colors then  db.colors = colors end
   
   if LibStub:GetLibrary("LibFuBarPlugin-MT-3.0", true) then
      -- Create the FuBarPlugin bits.
      self:SetFuBarOption("tooltipType", "GameTooltip")
      self:SetFuBarOption("hasNoColor", true)
      self:SetFuBarOption("cannotDetachTooltip", true)
      self:SetFuBarOption("hideWithoutStandby", true)
      self:SetFuBarOption("iconPath", [[Interface\AddOns\MagicTargets\target.tga]])	
   end
   

   options.profile = DBOpt:GetOptionsTable(self.db)

   mod:SetupOptions()

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
--      bars:SetColorAt(1.00, 1, 1, 0, 1)
--      bars:SetColorAt(0.00, 0.5, 0.5,0, 1)
      bars.RegisterCallback(self, "AnchorMoved")
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
      local oRA = oRA
      if oRA and oRA.maintanktable then
	 for _,tname in pairs(oRA.maintanktable) do
	    if name == tname then
	       unitTanks[name] = true
	       return true
	    end
	 end
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
      mod.clear(ingroup)
      if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then
	 isInGroup = true
      else
	 mod.clear(coloredNames)
	 isInGroup = false
      end
      if isInGroup or db.outsidegroup then
	 mod:IterateRaid(function(self, unitname) if unitname then ingroup[unitname] = true end end)
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
   self:UpdateBar(target, UnitName("player"))

   if UnitExists(target) then
      local bar = bars:GetBar(UnitGUID(target))
      if bar then self:MoveIconTo(icon, bar, target) end
   end
end

local function Noop() end

function mod:RemoveBar(id)
   local bar = bars:GetBar(id)
   if bar then
      bar.mark = nil
      seen[id] = nil
      mod.del(tooltipInfo, id)
      bar:SetScript("OnEnter", Noop)
      bar:SetScript("OnLeave", Noop)
      bar:EnableMouse("false")
      if bar.tooltipShowing then
	 bar.tooltipShowing = nil
	 GameTooltip:Hide()
      end
      bars:RemoveBar(id)
   end
end


function mod:RemoveAllBars(removeAll)
   local currentBars = bars:GetBars()
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
   if not bar then
      _,bar = next(bars:GetBars())
   end
   if not bar or not cc then return end
   --   local fade = 0.5 + 0.5 * (bar.value / bar.maxValue)
   local color = db.colors[cc] or db.colors["CC"]
   bar:UnsetAllColors()
   bar:SetColorAt(1.0, color[1], color[2], color[3], color[4])
   if db.fadebars then
      bar:SetColorAt(0, color[1]*0.5, color[2]*0.5, color[3]*0.5, color[4])
   end
   bar.color = cc
end

local lvlFmt = "Level %d %s"
local colorToText = {
   CC = "Crowd Controlled",
   Tank = "Tanked",
   Notank = "Untanked",
}

local function Bar_UpdateTooltip(self, tooltip)
   tooltip:ClearLines()
   local tti = tooltipInfo[self.name]
   if tti and tti.name then
      tooltip:AddLine(tti.name, 0.85, 0.85, 0.1)
      tooltip:AddLine(fmt(lvlFmt, tti.level, tti.type), 1, 1, 1)
      tooltip:AddLine(" ")
      tooltip:AddDoubleLine("Health:", self.value.."%", nil, nil, nil, 1, 1, 1)
      if tti.target then
	 tooltip:AddDoubleLine("Target:", db.coloredNames and coloredNames[tti.target] or tti.target, nil, nil, nil, 1, 1, 1)
      end
      if self.color and colorToText[self.color] and InCombatLockdown() then
	 local c = db.colors[self.color]
	 tooltip:AddDoubleLine("Status:", colorToText[self.color], nil, nil, nil, c[1], c[2], c[3])
      else
	 local c = db.colors.Normal
	 tooltip:AddDoubleLine("Status:", "Idle", nil, nil, nil, c[1], c[2], c[3])
      end
      if mmtargets[self.name] then
	 tooltip:AddDoubleLine("MagicMarker Assigment:", mmtargets[self.name].cc, nil, nil, nil, 1, 1, 1)
      end
      tooltip:AddLine(" ")
      if next(tti.targets) then 
	 tooltip:AddLine("Currently targeted by:", 0.85, 0.85, 0.1);
	 local sorted = mod.get()
	 for id in pairs(tti.targets) do
	    sorted[#sorted+1] = id
	 end
	 sort(sorted)
	 if db.coloredNames then
	    for id,name in ipairs(sorted) do
	       sorted[id] = coloredNames[name]
	    end
	 end
	 tooltip:AddLine(tconcat(sorted, ", "), 1, 1, 1, 1)
	 mod.del(sorted)
      else
	 tooltip:AddLine("Not targeted by anyone.");
      end
   else
      tooltip:AddLine(self.label:GetText(), 0.85, 0.85, 0.1)
      tooltip:AddLine(" ")
      tooltip:AddLine("Not targeted by anyone.");
   end
   tooltip:Show()
end

local function Bar_OnEnter()
   if not db.showTooltip  then return end
   local tooltip = GameTooltip
   local self = this
   tooltip:SetOwner(self, "ANCHOR_CURSOR")
   Bar_UpdateTooltip(self, tooltip)
   this.tooltipShowing = true
end

local function Bar_OnLeave()
   if not db.showTooltip  then return end
   GameTooltip:Hide()
   this.tooltipShowing = nil
end


function mod:NewBar(guid, unitname, current, max, mark)
   local bar = bars:NewCounterBar(guid, unitname, current, max, GetRaidIcon(mark))
   bar.isTimer = nil
   SetBarColor(bar, "Normal")
   bar:SetScript("OnEnter", Bar_OnEnter);
   bar:SetScript("OnLeave", Bar_OnLeave);
   bar:EnableMouse(true)
   return bar
end

function mod:UpdateBar(target, targetedBy)
   if not UnitExists(target) then return end
   if target == "mouseover" then targetedBy = nil end
   local guid = UnitGUID(target)
   if updated[guid] then
      updated[guid] = updated[guid] + 1
      
      if targetedBy  and tooltipInfo[guid] then
	 if not tooltipInfo[guid].targets then
	    tooltipInfo[guid].targets = self.get()
	 end
	 tooltipInfo[guid].targets[targetedBy] = true
      end
      return
   elseif trivial[guid] or died[guid] then
      return
   end
   local type = UnitCreatureType(target)
   local unitname = UnitName(target)
   if UnitCanAttack("player", target) and not UnitIsDead(target)
      and not ingroup[unitname] and not UnitPlayerControlled(target) then
	 -- and not UnitIsPlayer(target) then
      if type == "Critter" or type == "Totem"  or (db.eliteonly and UnitClassification(target) == "normal") then
	 trivial[guid] = true
	 self:RemoveBar(guid)
	 return
      end
      currentbars = currentbars or mod.get()
      local bar = currentbars[guid]
      local mark = GetRaidTargetIndex(target)
      if not bar then
	 bar = self:NewBar(guid, unitname, UnitHealth(target), UnitHealthMax(target), mark)
	 
	 SetBarColor(bar, "Normal")
	 bar.mark = mark
	 bar.isTimer = false
	 currentbars[guid] = bar
      else
	 bar:SetValue(UnitHealth(target))
	 if bar.mark ~= mark then
	    bar:SetIcon(GetRaidIcon(mark))
	    bar.mark = mark
	 end
      end

      local targettarget = target.."target"
      
      if UnitExists(targettarget) and not UnitCanAttack("player", targettarget) and
	 not UnitIsDead(targettarget) and UnitIsPlayer(targettarget) then
	 tanked[guid] = mod:IsTank(targettarget)
      end

      if mmtargets[guid] then
	 if not inCombat then
	    SetBarColor(bar, mmtargets[guid].cc)
	 end
	 mmtargets[guid].mark = mark
      end
      updated[guid] = 1
      if not tooltipInfo[guid] then
	 tooltipInfo[guid] = mod.get()
	 tooltipInfo[guid].targets = mod.get()
      else
	 mod.clear(tooltipInfo[guid].targets)
      end

      if targetedBy then
	 tooltipInfo[guid].targets[targetedBy] = true
      end
      
      tooltipInfo[guid].name = unitname
      tooltipInfo[guid].target = UnitName(targettarget)
      tooltipInfo[guid].type = type
      tooltipInfo[guid].level = UnitLevel(target)
      
      seen[guid] = time()+4
   end
end

function mod:UpdateBars()
   local tt = time()
   inCombat = InCombatLockdown()
   currentbars = bars:GetBars() or mod.get()

   mod.clear(updated)
   mod.clear(unitTanks)
   mod.clear(tanked)
   
   for id,data in pairs(mmtargets) do
      if not died[id] then
	 local bar = currentbars[id]
	 if not bar then
	    local bar = self:NewBar(id, data.name, 100, 100, data.mark)
	    bar.mark = data.mark
	    bar.isTimer = false
	 else	    
	    if bar.mark ~= data.mark then
	       bar:SetIcon(GetRaidIcon(data.mark))
	       bar.mark = data.mark
	    end
	    if data.name then bar.label:SetText(data.name) end
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
	    elseif not mobspells[id] or not inCombat then
	       seen[id] = nil -- only remove them if not in combat or if not cc'd
	    end
	 end
      end
      for id,bar in pairs(currentbars) do
	 if  updated[id] or mmtargets[id] or seen[id] then
	    if mobspells[id] then
	       if not ccstrings[id] then
		  local str = " "
		  for _,tex in pairs(mobspells[id]) do
		     str = fmt("%s|T%s:0|t", tostring(str), tostring(tex)) 
		  end
		  ccstrings[id] = str
	       end
	       SetBarColor(bar, "CC") 
	    elseif inCombat then
	       if isInGroup then
		  if tanked[id] == nil then
		     SetBarColor(bar, "Normal")
		  elseif tanked[id] then
		     SetBarColor(bar, "Tank")
		  else 
		     SetBarColor(bar, "Notank")
		  end
	       else
		  SetBarColor(bar, "Tank")
	       end
	    end
	    if not updated[id] and tooltipInfo[id] then
	       mod.clear(tooltipInfo[id].targets)
	    end
	    bar.timerLabel:SetText(fmt("%s%s", updated[id] and tostring(updated[id]) or "", ccstrings[id] or ""))
	    if bar.tooltipShowing then
	       Bar_UpdateTooltip(bar, GameTooltip)
	    end
	 else
	    self:RemoveBar(id)	
	 end
      end
   else
      mod.clear(seen)
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
	    if not raidtarget then raidtarget = mod.get() end
	    map = raidtarget
	 end
	 for id = 1,GetNumRaidMembers() do
	    local name = GetRaidRosterInfo(id)
	    if target then 
	       if not map[id] then map[id] = "raid"..id..(target and "target" or "") end
	       callback(self, map[id], name,...)
	    else
	       callback(self, name, name, ...)
	    end
	 end
      else
	 if GetNumPartyMembers() > 0 then
	    if not partytarget then partytarget = mod.get() end
	    map = partytarget
	    for id = 1,GetNumPartyMembers() do
	       if not map[id] then map[id] = "party"..id end
	       local name = UnitName(map[id])
	       callback(self, (target and (map[id].."target")) or name, name, ...)
	    end
	 end
	 local name = UnitName("player")
	 callback(self, target and "target" or name, name, ...);
      end   
   end
end

function mod:OnCommResetV2()
   mod.clear(mmtargets) 
   if not InCombatLockdown() then
      self:RemoveAllBars(true)
   end
   self:UpdateBars()
end

function mod:OnAssignData(data)
   mmtargets = data
   self:UpdateBars()
   local currentBars = bars:GetBars()
   for id,data in pairs(mmtargets) do
--      self:debug("Got mark data for %s", data.name or id)
      SetBarColor(currentBars[id], data.cc)
   end
end

function mod:OnCommMarkV2(mark, guid, _, name)
   if not name then return end
   if not mmtargets[guid] then
      mmtargets[guid] = mod.get()
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
      mod.del(mmtargets, guid)
   end
   self:UpdateBars()
end

function mod:AnchorMoved(cbk, group, button)
   db.point = { group:GetPoint() }
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
   mod.clear(died)
   mod.clear(ccstrings)
   mod.clear(mobspells)
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
	 local cc = mobspells[tguid] or mod.get()
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
	       mod.del(mobspells, tguid)
	    end
	 end
      end
   end
end


-- Config option handling below

local function GetMediaList(type)
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
   bars:SetMaxBars(db.maxbars)
   bars:SetScale(db.scale)
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
      if not db.colors then db.colors = colors end -- set default if needed
      self:ApplyProfile()
   end
end

function mod:ToggleConfigDialog()
   InterfaceOptionsFrame_OpenToFrame(mod.text)
   InterfaceOptionsFrame_OpenToFrame(mod.main)
end

local function GetFuBarMinimapAttachedStatus(info)
   return mod:IsFuBarMinimapAttached() or db.HideMinimapButton
end

function mod:ToggleLocked()
   db.locked = not db.locked
   if db.locked then bars:Lock() else bars:Unlock() end
   if db.hideanchor then
      -- Show anchor if we're unlocked but lock it again if we're locked
      if db.locked then bars:HideAnchor() else bars:ShowAnchor() end
   end
   bars:SortBars()
   mod:info("The bars are now %s.", db.locked and "locked" or "unlocked")
end

options = { 
   general = {
      type = "group",
      name = "General",
      order = 1,
      args = {
	 ["showTooltip"] = {
	    type = "toggle",
	    width = "full",
	    name = "Show mouseover tooltip", 
	    get = function() return db.showTooltip end,
	    set = function() db.showTooltip = not db.showTooltip end,
	 },
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
	    name = "Lock Magic Targets bar positions.",
	    width = "full",
	    set = function() mod:ToggleLocked() end,
	    get = function() return db.locked end,
	 },
	 ["coloredNames"] = {
	    type = "toggle",
	    name = "Use class colors in tooltip.",
	    width = "full",
	    set = function() db.coloredNames = not db.coloredNames end,
	    get = function() return db.coloredNames end,
	    hidden = function() return not db.showTooltip end
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
	 ["eliteonly"] = {
	    type = "toggle",
	    name = "Filter out all non-elite mobs.",
	    width = "full",
	    set = function()
		     db.eliteonly = not db.eliteonly
		  end,
	    get = function() return db.eliteonly end
	 },
	 ["fadebars"] = {
	    type = "toggle",
	    name = "Fade bars as health decreases.",
	    width = "full",
	    set = function()
		     db.fadebars = not db.fadebars
		     mod:info("Bar fading is %s.", db.fadebars and "enabled" or "disabled")
		  end,
	    get = function() return db.fadebars end
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
	    name = "Select Texture",
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
   colors = {
      type = "group",
      name = "Colors",
      order = 9,
      set = SetColorOpt,
      get = GetColorOpt,
      args = {
	 Tank = {
	    type = "color",
	    name = "Tank",
	    desc = "Color used to indicate tanked targets. This is also used while soloing.",
	    hasAlpha = true, 
	 },
	 Normal = {
	    type = "color",
	    name = "Idle",
	    desc = "Color used for inactove targets.",
	    hasAlpha = true, 
	 },
	 CC = {
	    type = "color",
	    name = "Crowd Controlled",
	    desc = "Color used for crowd controlled targets.",
	    hasAlpha = true, 
	 },
	 Notank = {
	    type = "color",
	    name = "Untanked",
	    desc = "Color used for targets that are currently not tanked or crowd controlled (aka the targets killing the DPS or healers).",
	    hasAlpha = true, 
	 }
      }
   },
   sizing = {
      type = "group",
      name = "Bar Size",
      order = 4,
      args = {
	 ["maxbars"]  = {
	    type = "range",
	    min = 1, max = 100, step = 1,
	    name = "Maximum number of bars",
	    width="full",
	    order = 0,
	    set = function(var, val)
		     db.maxbars = val
		     bars:SetMaxBars(val)
		     bars:SortBars()
		  end,
	    get = function() return db.maxbars end
	 },
	 height = {
	    type = "range",
	    name = "Bar Height",
	    width = "full",
	    min = 1, max = 50, step = 1,
	    set = function(_,val) db.height = val mod:SetSize() end,
	    get = function() return db.height end
	 }, 
	 width = {
	    type = "range",
	    name = "Bar Width",
	    width = "full",
	    min = 1, max = 300, step = 1,
	    set = function(_,val) db.width = val mod:SetSize() end,
	    get = function() return db.width end
	 }, 
	 scale = {
	    type = "range",
	    name = "Scale Factor",
	    width = "full",
	    min = 0.01, max = 5, step = 0.05,
	    set = function(_,val) db.scale = val bars:SetScale(val) end,
	    get = function() return db.scale end
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
	    name = "Font Name",
	    values = GetMediaList("font"),
	    set = function(_,val, state)
		     if val ~= db.font and state then
			db.font = val
			mod:SetFont()
		     end
		  end,
	    get = function(_,key) return db.font == key end,
	    order = 2
	 },
	 ["fontsize"] = {
	    order = 1, 
	    type = "range",
	    name = "Font size",
	    min = 1, max = 30, step = 1,
	    set = function(_,val) db.fontsize = val mod:SetFont() end,
	    get = function() return db.fontsize end
	 },
      },
   },
   fubar = {
      type = "group",
      name = "FuBar options",
      disabled = function() return mod.IsFuBarMinimapAttached == nil end,
      args = {
	 attachMinimap = {
	    type = "toggle",
	    name = "Attach to minimap", 
	    width = "full", 
	    get = function(info)
		     return mod:IsFuBarMinimapAttached()
		  end,
	    set = function(info, v)
		     mod:ToggleFuBarMinimapAttached()
		     db.AttachMinimap = mod:IsFuBarMinimapAttached()
		  end
	 },
	 hideIcon = {
	    type = "toggle",
	    name = "Hide minimap/FuBar icon",
	    width = "full", 
	    get = function(info) return db.HideMinimapButton end,
	    set = function(info, v)
		     db.HideMinimapButton = v
		     if v then mod:Hide() else mod:Show() end
		  end
	 },
	 showIcon = {
	    width = "full", 
	    type = "toggle",
	    name = "Show icon", 
	    get = function(info) return mod:IsFuBarIconShown() end,
	    set = function(info, v) mod:ToggleFuBarIconShown() end,
	    disabled = GetFuBarMinimapAttachedStatus
	 },
	 showText = {
	    width = "full", 
	    type = "toggle",
	    name = "Show text",
	    get = function(info) return mod:IsFuBarTextShown() end,
	    set = function(info, v) mod:ToggleFuBarTextShown() end,
	    disabled = GetFuBarMinimapAttachedStatus
	 },
	 position = {
	    width = "full", 
	    type = "select",
	    name = "Position",
	    values = {LEFT = "Left", CENTER = "Center", RIGHT = "Right"},
	    get = function() return mod:GetPanel() and mod:GetPanel():GetPluginSide(mod) end,
	    set = function(info, val)
		     if mod:GetPanel() and mod:GetPanel().SetPluginSide then
			mod:GetPanel():SetPluginSide(mod, val)
		     end
		  end,
	    disabled = GetFuBarMinimapAttachedStatus
	 }
      }
   },

}


function mod:OptReg(optname, tbl, dispname, cmd)
   if dispname then
      optname = "Magic Targets"..optname
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

function mod:SetupOptions()
   mod.main = mod:OptReg("Magic Targets", options.general)
   mod:OptReg(": Profiles", options.profile, "Profiles")
   mod:OptReg(": FuBar", options.fubar, "FuBar Options")
   mod:OptReg(": Font", options.font, "Font")
   mod:OptReg(": bar sizing", options.sizing, "Bar Sizing")
   mod:OptReg(": bar colors", options.colors, "Bar Colors")
   mod.text = mod:OptReg(": Textures", options.texture, "Bar Texture")
   

   mod:OptReg("Magic Targets CmdLine", {
		 name = "Command Line",
		 type = "group",
		 args = {
		    config = {
		       type = "execute",
		       name = "Show configuration dialog",
		       func = function() mod:ToggleConfigDialog() end,
		       dialogHidden = true
		    },
		 }
	      }, nil,  { "magictargets", "mgt" })
end

function mod:OnUpdateFuBarTooltip()
   GameTooltip:AddLine("|cffffff00" .. "Click|r to toggle the Magic Target window lock")
   GameTooltip:AddLine("|cffffff00" .. "Right-click|r to open the configuration screen")
end

function mod:OnFuBarClick(button)
   mod:ToggleLocked()
end

function mod:OnFuBarMouseUp(button)
   if button == "RightButton" then
      mod:ToggleConfigDialog()
   end
end


