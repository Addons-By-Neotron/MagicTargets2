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


if not LibStub:GetLibrary("LibBars-1.0", true) then
   LoadAddOn("LibBars-1.0") -- hrm..
end

MagicTargets = LibStub("AceAddon-3.0"):NewAddon("MagicTargets", "AceEvent-3.0", "LibMagicUtil-1.0", 
						"AceTimer-3.0", "AceConsole-3.0", "LibSimpleBar-1.0")

-- Silently fail embedding if it doesn't exist
local LibStub = LibStub
local LDB = LibStub:GetLibrary("LibDataBroker-1.1")

local Logger = LibStub("LibLogger-1.0", true)
if Logger then
   Logger:Embed(MagicTargets)
end

local C = LibStub("AceConfigDialog-3.0")
local DBOpt = LibStub("AceDBOptions-3.0")
local media = LibStub("LibSharedMedia-3.0")
local mod = MagicTargets
local comm = LibStub("MagicComm-1.0")

local GetItemInfo = GetItemInfo
local GetSpellInfo = GetSpellInfo
local GetInventoryItemLink = GetInventoryItemLink
local UnitClassification = UnitClassification
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
local strlen = strlen
local fmt = string.format
local rnd = math.random
local ceil = math.ceil
local tinsert = table.insert
local tconcat = table.concat
local tremove = table.remove
local tsort = table.sort
local time = time
local type = type
local ipairs = ipairs
local max = max
local gsub = gsub
local CreateFrame = CreateFrame
local UIParent = UIParent
local pairs = pairs
local min = min
local tostring = tostring
local tonumber = tonumber
local next = next
local sort = sort
local select = select
local unpack = unpack

local addonEnabled = false
local ccspells = {}
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
local focusIcon, targetIcon 

local tableStore = {}

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
      showDuration = true,
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
	 backgroundColor = { 0, 0, 0, 0.5},
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
   if not db.colors then  db.colors = colors end
   mod:FixLabelThemes()
   
   self.ldb =
      LDB:NewDataObject("Magic Targets",
			{
			   type =  "launcher", 
			   label = "Magic Targets",
			   icon = [[Interface\AddOns\MagicTargets\target.tga]],
			   tooltiptext = ("|cffffff00Left click|r to open the configuration screen.\n"..
					  "|cffffff00Right click|r to toggle the Magic Target window lock."), 
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

   for i = 1,8 do
      raidicons[i] = iconPath:format(i)
   end
   for id,duration in pairs(comm.spellIdToDuration) do
      local icon = select(3, GetSpellInfo(id))
      ccspells[id] = { duration, icon }
   end

   mod.recycledFrames = {}
   mod.unitbars = {}
   mod.bars = {}
   mod:CreateFrame()
end

-- Sort first by Magic Marker priority, then by health and lastly by guid.
local function BarSortFunc(a, b)
   local amm = mmtargets[a.name]
   local bmm = mmtargets[b.name]
   local av = 0
   local bv = 0
   if amm then av = 1000+(amm.val or 0)+(amm.cc == "Tank" and 100 or 0) else av = a.value end
   if bmm then bv = 1000+(bmm.val or 0)+(bmm.cc == "Tank" and 100 or 0) else bv = b.value end
   if av == bv then return a.name > b.name else return av > bv end
end

function mod:OnEnable()
   self:ApplyProfile()
   if self.SetLogLevel then
      self:SetLogLevel(self.logLevels.TRACE)
   end
   self:RegisterEvent("RAID_ROSTER_UPDATE", "ScheduleGroupScan")
   self:RegisterEvent("PARTY_MEMBERS_CHANGED", "ScheduleGroupScan")
   self:ScheduleGroupScan(true)
end


local function GetRaidIcon(id)
   if id and id > 0 and id <= 8 then return raidicons[id] end
end 

function mod:SetIcon(bar, mark)
   if not mark then
      bar.icon:SetTexture(nil)
   elseif bar.mark ~= mark then
      bar.icon:SetTexture(GetRaidIcon(mark))
   end
   bar.mark = mark
end
	 

function mod:IterateBars(func, ...)
   for _,frame in pairs(mod.bars) do
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
   self:UnregisterEvent("RAID_ROSTER_UPDATE")
   self:UnregisterEvent("PARTY_MEMBERS_CHANGED")
end

local unitTanks = {}

local function hasShieldEquipped(unit) 
      local shieldLink = GetInventoryItemLink("target", 17)
      if shieldLink then
	 return select(9, GetItemInfo(shieldLink)) == "INVTYPE_SHIELD"
      else
	 return false
      end
   end
do
   local tankAura = {
      PALADIN = { [GetSpellInfo(25780)] = true }, 
      WARRIOR = hasShieldEquipped, 
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
--      if mod.debug then mod:debug("Tank check: Class = %s,auras = %s, type(auras) = %s",
--				  class, tostring(auras), type(auras))
--      end
      if not auras then
--	 mod:debug("Found no auras for class %s", class)
	 unitTanks[name] = false
	 return false
      end

      if type(auras) == "function" then
	 unitTanks[name] = auras(unit)
--	 mod:debug("Found that %s [%s] is %s", name, unit, tostring(auras(unit)))
	 return unitTanks[name]
      else 
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
      end
      return false
   end
end

do
   local groupScanTimer
   function mod:ScheduleGroupScan(fast)
      if groupScanTimer then self:CancelTimer(groupScanTimer, true) end
      if fast == true then
	 groupScanTimer = self:ScheduleTimer("ScanGroupMembers", 0.1)
      else
	 groupScanTimer = self:ScheduleTimer("ScanGroupMembers", 5)
      end
   end

   function mod:ScanGroupMembers()
      mod.clear(ingroup)
      if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then
	 isInGroup = true
      else
	 mod.clear(coloredNames)
	 isInGroup = false
	 mod:OnCommResetV2() -- make sure the magic marker bars are gone
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

function mod:UpdateTarget(target, norefresh)
   if mod.testBars then return end
   local icon = target == "focus" and focusIcon or targetIcon
   if icon then icon:Hide() end

   self:UpdateBar(target, UnitName("player"))

   if UnitExists(target) then
      local frame = mod.unitbars[UnitGUID(target)]
      if frame then
	 self:MoveIconTo(icon, frame, target)
	 mod:SetBarStrings(frame)
      end
   end
   if norefresh ~= true then
      mod:SortBars()
   end
end

local function Noop() end

function mod:RemoveBar(id)
   local frame = mod.unitbars[id] or mod.bars[id]
   if frame then
      mod.unitbars[frame.guid] = nil
      frame.mark = nil
      frame.guid = nil
      seen[id] = nil
      mod.del(tooltipInfo, id)
      frame:SetScript("OnEnter", nil)
      frame:SetScript("OnLeave", nil)
      frame:EnableMouse(false)
      if frame.tooltipShowing then
	 frame.tooltipShowing = nil
	 GameTooltip:Hide()
      end
      frame:Hide()
      mod.recycledFrames[#mod.recycledFrames+1] = frame
      
      for id,data in pairs(mod.bars) do
	 if frame == data then
	    tremove(mod.bars, id)
	    break
	 end
      end
   end
end


function mod:RemoveAllBars(removeAll)
   if mod.testBars then return end
   for id in pairs(mod.unitbars) do 
      if removeAll or not mmtargets[id] then
	 mod:RemoveBar(id)
      end
   end
   mod:SortBars()
end

local updated = {}
local tanked  = {}

local lvlFmt = "Level %d %s"
local colorToText = {
   CC = "Crowd Controlled",
   Tank = "Tanked",
   Notank = "Untanked",
}

local function Bar_UpdateTooltip(self, tooltip)
   tooltip:ClearLines()
   local tti = tooltipInfo[self.guid]
   if tti and tti.name then
      tooltip:AddLine(tti.name, 0.85, 0.85, 0.1)
      tooltip:AddLine(fmt(lvlFmt, tti.level, tti.type), 1, 1, 1)
      tooltip:AddLine(" ")
      tooltip:AddDoubleLine("Health:", fmt("%.0f%%", 100*self.bar.value/self.bar.maxValue), nil, nil, nil, 1, 1, 1)
      if tti.target then
	 tooltip:AddDoubleLine("Target:", tti.target, nil, nil, nil, 1, 1, 1)
      end
      if self.color and colorToText[self.color] and InCombatLockdown() then
	 local c = db.colors[self.color]
	 tooltip:AddDoubleLine("Status:", colorToText[self.color], nil, nil, nil, c[1], c[2], c[3])
      else
	 local c = db.colors.Normal
	 tooltip:AddDoubleLine("Status:", "Idle", nil, nil, nil, c[1], c[2], c[3])
      end
      if mmtargets[self.guid] then
	 tooltip:AddDoubleLine("MagicMarker Assigment:", mmtargets[self.guid].cc, nil, nil, nil, 1, 1, 1)
      end
      if tti.cc then
	 tooltip:AddDoubleLine("Crowd Control:", tti.cc, nil, nil, nil, 1, 1, 1)
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
      if tti.name then
	 tooltip:AddLine(tti.name, 0.85, 0.85, 0.1)	 
	 tooltip:AddLine(" ")
      end
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


function mod:UpdateBar(target, targetedBy)
   if not UnitExists(target) or mod.testbars then return end
   if target == "mouseover" then targetedBy = nil end
   local guid = UnitGUID(target)

   -- Add to the people targeting this particular unit
   if updated[guid] then
      if targetedBy then
	 local tti = tooltipInfo[guid]
	 if tti and not tti.targets[targetedBy] then
	    tti.targets[targetedBy] = true
	    updated[guid] = updated[guid] + 1
	 end
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
      local frame = mod.unitbars[guid]
      local mark = GetRaidTargetIndex(target)
      local uh, uhm = UnitHealth(target), UnitHealthMax(target)
      if not frame then
	 frame = self:CreateBar(guid, uh, uhm)
	 frame:SetColor("Normal")
      else
	 frame.bar:SetValue(uh, uhm)
      end
      mod:SetIcon(frame, mark)
      local targettarget = target.."target"
      
      if UnitExists(targettarget) and not UnitCanAttack("player", targettarget) and
	 not UnitIsDead(targettarget) and UnitIsPlayer(targettarget) then
	 tanked[guid] = mod:IsTank(targettarget)
      end

      if mmtargets[guid] then
	 if not inCombat then
	    frame:SetColor(mmtargets[guid].cc)
	 end
	 mmtargets[guid].mark = mark
      end

      local tti = tooltipInfo[guid] or mod.get()
      tooltipInfo[guid] = tti

      if tti.targets then
	 mod.clear(tti.targets)
      else
	 tti.targets = mod.get()
      end

      if targetedBy then
	 updated[guid] = 1
	 tti.targets[targetedBy] = true
      else
	 updated[guid] = 0
      end

      local tn = UnitName(targettarget) 
      tti.name = unitname
      tti.target = tn and db.coloredNames and coloredNames[tn] or tn
      tti.type = type
      tti.level = UnitLevel(target)
      tti.health = uh
      tti.maxhealth = uhm
      tti["%"] = ceil(100*uh / uhm)
      
      seen[guid] = time()+4
      if target == "mouseover" then
	 mod:SortBars()
	 mod:SetBarStrings(frame)
      end
   end
end

function mod:UpdateBars()
   local tt = time()
   if mod.testBars then return end
   inCombat = InCombatLockdown()

   mod.clear(updated)
   mod.clear(unitTanks)
   mod.clear(tanked)

   -- Make bars for MagicMarker assignments
   for id,data in pairs(mmtargets) do
      if not died[id] then
	 local bar = mod.unitbars[id] or self:CreateBar(id, 100, 100)
	 mod:SetIcon(bar, data.mark)
      end
   end
   -- Update raid targeting information, adding bars as necessary
   self:IterateRaid(self.UpdateBar, true)
   -- If we have a pet, let's see what he's targeting
   self:UpdateBar("pettarget")
   
   if next(mod.unitbars) then
      -- This updates the list of "seen" mobs. Bars for mobs not seen for a while
      -- are removed.
      for id, seenTime in pairs(seen) do
	 if seenTime < tt then
	    local frame = mod.unitbars[id]
	    if frame and mmtargets[id] then
	       if not inCombat then 
		  frame.bar:SetValue(frame.bar.maxValue or 100)
		  frame:SetColor(mmtargets[id].cc)
		  seen[id] = nil
	       end
	    elseif not mobspells[id] or not inCombat then
	       seen[id] = nil -- only remove them if not in combat or if not cc'd
	    end
	 end
      end

      -- Update crowd control info, recycle non-needed bars etc
      for id,frame in pairs(mod.unitbars) do
	 if  updated[id] or mmtargets[id] or seen[id] then -- We're keeping this one
	    if mobspells[id] then
	       -- Build crowd control info for this mob
	       if db.showDuration then
		  ccstrings[id] = nil
	       end
	       if not ccstrings[id] then
		  local str = " "
		  local timeLeft = 0
		  for _,tex in pairs(mobspells[id]) do
		     local spellTimeLeft = tex.expiration-tt
		     if spellTimeLeft > timeLeft then
			timeLeft = spellTimeLeft
		      end
		     str = fmt("%s|T%s:0|t", tostring(str), tostring(tex.icon))
		  end
		  if timeLeft > 0 and db.showDuration then 
		     str = fmt("%s %.0f", str, timeLeft)
		  end
		  ccstrings[id] = str
	       end
	       frame:SetColor("CC") 
	    elseif inCombat then
	       -- Update bar colors based on mob status
	       if isInGroup then
		  if tanked[id] == nil then
		     frame:SetColor("Normal")
		  elseif tanked[id] then
		     frame:SetColor("Tank")
		  else 
		     frame:SetColor("Notank")
		  end
	       else
		  frame:SetColor("Tank")
	       end
	    end

	    -- This unit had no raid members targeting it
	    if tooltipInfo[id] and not updated[id] then	       
	       mod.clear(tooltipInfo[id].targets)
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
   if not icon then return end
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

function mod:AddTooltipData(id, name)
   local tti = tooltipInfo[id] or mod.get()
   tooltipInfo[id] = tti
   tti.targets = tti.targets or mod.get()
   tti.name = name
   tti.level = tti.level or 0
   tti.type = tti.type or "Unknown"
   tti["%"] = tti["%"] or 100      
   mod:SetBarStrings(mod.unitbars[id])
end

function mod:OnAssignData(data)
   mmtargets = data
   self:UpdateBars()
   for id,data in pairs(mmtargets) do
      if mod.unitbars[id] then
	 mod.unitbars[id]:SetColor(data.cc)
	 mod:AddTooltipData(id, data.name)
      end
   end
end

function mod:OnCommMarkV2(mark, guid, _, name)
   if not name then return end
   if not mmtargets[guid] then
      mmtargets[guid] = mod.get()
      mod:AddTooltipData(guid, name)
   end
   for id, frame in pairs(mod.unitbars) do
      if id ~= guid and frame.mark == mark then
	 mod:SetIcon(frame.bar)
	 if mmtargets[id] then
	    mmtargets[id].mark = nil
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
      repeatTimer = self:ScheduleRepeatingTimer("UpdateBars", 5)
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
local COMBATLOG_OBJECT_AFFILIATION_MINE, 
COMBATLOG_OBJECT_AFFILIATION_PARTY, 
COMBATLOG_OBJECT_AFFILIATION_RAID,
COMBATLOG_OBJECT_REACTION_FRIENDLY,
COMBATLOG_OBJECT_TYPE_GUARDIAN,
COMBATLOG_OBJECT_TYPE_NPC,
COMBATLOG_OBJECT_TYPE_PET,
COMBATLOG_OBJECT_TYPE_PLAYER = COMBATLOG_OBJECT_AFFILIATION_MINE, 
COMBATLOG_OBJECT_AFFILIATION_PARTY, 
COMBATLOG_OBJECT_AFFILIATION_RAID,
COMBATLOG_OBJECT_REACTION_FRIENDLY,
COMBATLOG_OBJECT_TYPE_GUARDIAN,
COMBATLOG_OBJECT_TYPE_NPC,
COMBATLOG_OBJECT_TYPE_PET,
COMBATLOG_OBJECT_TYPE_PLAYER



local function GetFlagInfo(flags)
   return
   bit_band(flags, COMBATLOG_OBJECT_AFFILIATION_MINE+COMBATLOG_OBJECT_AFFILIATION_PARTY+COMBATLOG_OBJECT_AFFILIATION_RAID)~=0, -- in group
   bit_band(flags, COMBATLOG_OBJECT_TYPE_PLAYER)==COMBATLOG_OBJECT_TYPE_PLAYER, -- is player
   bit_band(flags, COMBATLOG_OBJECT_REACTION_FRIENDLY) ~= 0 -- is friendly
end

function mod:COMBAT_LOG_EVENT_UNFILTERED(_, tt, event, sguid, sname, sflags,
					 tguid, tname, tflags, spellid, spellname)
--   mod:debug("EVENT: %s\n", event)
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
   elseif event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
      -- record crowd control
      local spellData = ccspells[spellid]
      if spellData then
	 local cc = mobspells[tguid] or mod.get()
	 cc[spellid] = cc[spellid] or mod.get()
	 mobspells[tguid] = cc
	 ccstrings[tguid] = nil
	 --	 if mod.debug then mod: debug("Spell %d has duration %s and will expire at %d\n",
	 --				      spellid, tostring(spellData[1]),
	 --				      tonumber(spellData[1])+tonumber(tt)) end
	 cc[spellid].expiration = tt+spellData[1]-1
	 cc[spellid].icon = spellData[2]
      end
   elseif event == "SPELL_AURA_REMOVED" or event == "SPELL_AURA_BROKEN" then
      local cc = mobspells[tguid]
      if cc and cc[spellid] then
	 cc[spellid] = nil
	 ccstrings[tguid] = nil
	 if not next(cc) then
	    mod.del(mobspells, tguid)
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
   if not db.colors then db.colors = colors end
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
   InterfaceOptionsFrame_OpenToCategory(mod.text)
   InterfaceOptionsFrame_OpenToCategory(mod.main)
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
   if locked == nil then
      mod:info("The bars are now %s.", db.locked and "locked" or "unlocked")
   end
end


function mod:OnOptionChanged(var, val)
   if var == "maxbars"  or var == "spacing" or var == "padding" then
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
      name = "General",
      order = 1,
      handler = mod,
      get = "GetOption",
      set = "SetOption", 
      args = {
	 showTooltip = {
	    type = "toggle",
	    width = "full",
	    name = "Show mouseover tooltip",
	    desc = "If enabled a tooltip with information about the targets will be shown when you mouse over the bars. If disabled, MagicTargets bars will only intercept mouse clicks when they are unlocked.", 
	    set = function(_, val) db.showTooltip = val mod:ToggleLocked(db.locked) end,
	 },
	 showDuration = {
	    type = "toggle",
	    width = "full",
	    name = "Show crowd control duration on bars",
	    desc = "When enabled, the estimated duration of crowd control spells will be shown on the bars. Note that due to lack of REFRESH events, the addon will not notice if a crowd control spell is reapplied before the previous one expires.",
	 },
	 focus = {
	    type = "toggle",
	    name = "Show Focus Marker",
	    desc = "Show a blue triangle indicating your current focus target.",
	    set = function(_, val) db.focus = val mod:UpdateTarget("focus") end,
	    order = 1
	 },
	 target = {
	    type = "toggle",
	    name = "Show Target Marker",
	    desc = "Show a green triangle indicating your current target.",
	    set = function(_, val) db.target = val mod:UpdateTarget("target") end,
	    order = 2
	 },
	 locked = {
	    type = "toggle",
	    name = "Lock Magic Targets bar positions.",
	    width = "full",
	    set = function(_, val) mod:ToggleLocked() end,
	 },
	 coloredNames = {
	    type = "toggle",
	    name = "Use class colors in tooltip.",
	    width = "full",
	    hidden = function() return not db.showTooltip end
	 },
	 growup = {
	    type = "toggle",
	    name = "Grow bars upwards.",
	    width = "full",
	    set = function(_, value)
		     db.growup = value
		     mod:info("Growing bars %s.", db.growup and "up" or "down")
		     mod:SetHandlePoints()
		     mod:SortBars()
		  end,
	 },
	 eliteonly = {
	    type = "toggle",
	    name = "Filter out all non-elite mobs.",
	    width = "full",
	 },
	 fadebars = {
	    type = "toggle",
	    name = "Fade bars as health decreases.",
	    width = "full",
	 },
	 hideanchor = {
	    type = "toggle",
	    name = "Hide anchor when bars are locked.",
	    width = "full",
	    set = function(_, val)
		     db.hideanchor = val
		     mod:FixAnchorVisibility()
		     mod:info("The anchor will be %s when the bars are locked.", db.hideanchor and "hidden" or "shown")
		  end,
	 },
	 mmlisten = {
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
	 },
	 outsidegroup = {
	    type = "toggle",
	    name = "Enable Magic Targets when not in a group.",
	    width = "full",
	    set = function()
		     db.outsidegroup = not db.outsidegroup
		     mod:ScheduleGroupScan()
		     mod:info("MagicTargets will be %s when solo.", db.outsidegroup and "enabled" or "disabled")
		  end,
	 },
      },
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
   looks = {
      type = "group",
      name = "Font and Texture",
      handler = mod,
      get = "GetOption",
      order = 3,
      args = {
	 texture = {
	    type = "select",
	    dialogControl = "LSM30_Statusbar",
	    name = "Texture",
	    desc = "The background texture used for the bars.",
	    values = AceGUIWidgetLSMlists.statusbar, 
	    set = function(_,val) db.texture = val mod:SetTexture() end,
	    order = 3
	 },
	 font = {
	    type = "select",
	    dialogControl = "LSM30_Font",
	    name = "Font",
	    desc = "Font used on the bars",
	    values = AceGUIWidgetLSMlists.font, 
	    set = function(_,key) db.font = key  mod:SetFont() end,
	    order = 1,
	 },
	 fontsize = {
	    order = 1, 
	    type = "range",
	    name = "Font size",
	    min = 1, max = 30, step = 1,
	    set = function(_,val) db.fontsize = val mod:SetFont() end,
	    order = 2
	 },
      },
   },
   labels = {
      type = "group",
      name = "Labels",
      handler = mod,
      get = "GetLabelOption", 
      set = "SetLabelOption", 
      order = 4,
      args = {
	 help = {
	    type = "description",
	    order = 1, 
	    name =
	       "These fields are used to set the text on and next to the bars. The following tokens will be replaced with relevant data:\n\n"..
	       "[name] - the name of the unit.\n"..
	       "[level] - the level of the unit.\n"..
	       "[%] - health percentage of the unit.\n"..
	       "[health] - absolute health of the unit.\n"..
	       "[maxhealth] - the units maximum health.\n"..
	       "[target] - the name of the units target.\n"..
	       "[type] - unit type (beast, elemental etc).\n"..
	       "[cc] - information indicating type and duration of active crowd control methods on the unit.\n"..
	       "[count] - number of players targeting the unit.",
	 },
	 labelTheme = {
	    type = "select",
	    order = 2,
	    name = "Label Layout",
	    desc = "The label layout is used to select which basic set of labels you want. You can then configure the individual labels below.",
	    get = "GetOption",
	    values = function() return mod.labelSelect end, 
	    set = "ChangeLabelTheme", 
	 }
      },
      plugins = {}
   },
   labelOptions = {
      text = {
	 type = "input",
	 name = "Label Text",
	 desc = "The text for this label. Tokens are replaced as per the description above.",
	 order = 1,
	 width = "full",
      }, 
      width = {
	 type = "range",
	 name = "Label Width",
	 desc = "The width of the label.",
	 min = 0, max = 500, step = 1, 
	 order = 2, 
	 width = "full",
	 hidden = "NoWidthLabel", 
      },
      justifyV = {
	 type = "select",
	 name = "Vertical Justification",
	 values = {
	    TOP = "Top",
	    CENTER = "Middle",
	    BOTTOM = "Bottom"
	 }
      }, 
      justifyH = {
	 type = "select",
	 name = "Horizontal Justification",
	 values = {
	    LEFT = "Left",
	    CENTER = "Center",
	    RIGHT = "Right"
	 }
      }
   }
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

function mod:NoWidthLabel(info)
   local var, parent = info[#info], tonumber(info[#info-1])
   return db.labels[db.labelTheme].labels[tonumber(parent)].width == nil
end

function mod:GetLabelOption(info)
   local var, parent = info[#info], info[#info-1]
   if parent == "labels" then
      return db[var]
   else
      return db.labels[db.labelTheme].labels[tonumber(parent)][var]
   end
end

function mod:SetLabelOption(info, val)
   local var, parent = info[#info], info[#info-1]
   if parent == "labels" then
      db[var] = val
   else
      db.labels[db.labelTheme].labels[tonumber(parent)][var]  = val
      if var == "text" then
	 for _,frame in pairs(mod.bars) do
	    mod:SetBarStrings(frame)
	 end
      elseif var == "justifyH" or var == "justifyV" then
	 for _,frame in pairs(mod.bars) do
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
   for _,frame in pairs(mod.bars) do
      mod:SetupBarLabels(frame)
      mod:SetBarStrings(frame)
   end
   mod:SortBars()
   mod:BuildLabelOptions() 
end

function mod:SetupOptions()
   local testbars = {
      type = "toggle",
      name = "Enable Test Bars",
      desc = "Enable display of test bars. This allows you to configure the looks without actively targeting something. Note that when test bars are enabled, normal bars are not shown.", 
      width = "full",
      order = 0,
      set = function() mod:ToggleTestBars() end, 
      get = function() return mod.testBars end,
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
   mod:OptReg(": bar sizing", mod.options.sizing, "Bar Sizing")
   mod:OptReg(": bar colors", mod.options.colors, "Bar Colors")
   mod:OptReg(": bar labels", mod.options.labels, "Bar Labels")
   mod:OptReg(": frame backdrop", mod.options.backgroundFrame, "Background Frame")
   mod:OptReg(": Font & Texture", mod.options.looks, "Font & Texture")
   mod.text = mod:OptReg(": Profiles", mod.options.profile, "Profiles")
   

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
   local w, h = 0,0
   local anchor
   local lbs = mod:GetLabelData()
   tsort(mod.bars, function(f1, f2) local a, b = (f1.bar.value/f1.bar.maxValue),  (f2.bar.value/f2.bar.maxValue) if a == b then return f1.guid > f2.guid else return a > b end end)
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

	 if fw > w then w = fw end
	 h = h + fh + db.spacing

	 if db.growup then
	    if anchor then
	       frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, db.spacing)
	       frame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, db.spacing)
	    else
	       frame:SetPoint("BOTTOMLEFT", mod.frame, "BOTTOMLEFT", db.padding, db.padding)
	       frame:SetPoint("BOTTOMRIGHT", mod.frame, "BOTTOMRIGHT", -db.padding, db.padding)
	    end
	 else
	    if anchor then
	       frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -db.spacing)
	       frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -db.spacing)
	    else
	       frame:SetPoint("TOPLEFT", mod.frame, "TOPLEFT", db.padding, -db.padding)
	       frame:SetPoint("TOPRIGHT", mod.frame, "TOPRIGHT", -db.padding, -db.padding)
	    end
	 end
	 anchor = frame
	 frame:Show()
      end
   end

   if h > 0 then
      local p2 = db.padding*2
      w = w+p2
      db.lastWidth = w
      mod.frame:SetWidth(w)
      mod.frame:SetHeight(h+p2)
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
   mod.frame = CreateFrame("Frame", nil, UIParent)
   mod.frame:SetMovable(true)
   mod.frame:SetWidth(db.lastWidth or 220)
   mod.frame:SetHeight(10)
   local handle = CreateFrame("Frame", nil, UIParent)
   mod.handle = handle
   
   handle:RegisterForDrag("LeftButton")
   handle:EnableMouse(not db.locked)
   handle:SetScript("OnDragStart", mod.OnDragStart)
   handle:SetScript("OnDragStop", mod.OnDragStop)

   mod:SetHandlePoints()

   handle.label = handle:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   handle.label:SetAllPoints()
   handle.label:SetText("Raid Targets")
   handle:SetBackdrop( {
			 bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			 edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			 inset = 4,
			 edgeSize = 8,
			 tile = true,
			 insets = {left = 2, right = 2, top = 2, bottom = 2}
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
   focusIcon:SetVertexColor(0, 0.84, 1 ,1)
   focusIcon:Hide()
   
   targetIcon = mod.frame:CreateTexture(nil, "OVERLAY")
   targetIcon:SetTexture([[Interface\Addons\MagicTargets\Textures\triangle.tga]])
   targetIcon:SetHeight(ih)
   targetIcon:SetWidth(ih)
   targetIcon:SetVertexColor(0, 1, 0.4 ,1)
   targetIcon:Hide()
end

function mod:SavePosition()
   local f = mod.frame
   local s = f:GetEffectiveScale()
   local shown = f:IsShown()
   local l = f:GetLeft()
   if not shown then f:Show() end
   if l then
      if db.growup then
	 db.posy = f:GetBottom() * s
	 db.anchor = "BOTTOMLEFT"
      else
	 db.posy =  f:GetTop() * s - UIParent:GetHeight()*UIParent:GetEffectiveScale()
	 db.anchor = "TOPLEFT"
      end
      db.posx = l * s
      db.point = nil
   end
   if not shown then f:Hide() end
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
	 if not anchor then  anchor = "TOPLEFT" end
	 f:SetPoint(anchor, posx/s, posy/s)
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
      mod.handle:SetHeight(mod.handle.label:GetHeight()+10)
   end
   
   local function SetBarFont(frame)
      local font = media:Fetch("font", db.font)
      for _,label in pairs(frame.labels) do 
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
	    mod:Print("Invalid anchor frame for label", id, ". Check the settings.")
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
	 label:SetJustifyV(data.justifyV)
      end

      frame.icon:SetPoint(lbs.icon.anchor,mod:FindAnchorFrame(frame, lbs.icon.anchorFrame, "[icon]"), lbs.icon.anchorTo, lbs.icon.offsetx, 0)
      frame.bar:SetPoint(lbs.bar.anchor,mod:FindAnchorFrame(frame, lbs.bar.anchorFrame, "[bar]"), lbs.bar.anchorTo, lbs.bar.offsetx, 0)

      frame:SetBarFont()
      frame:Resize(lbs)
   end

   local function GetSize(frame)
      local lbs = mod:GetLabelData()
      return lbs.width(frame), lbs.height(frame)
   end
   
   local function ResizeBar(frame, lbs)
      frame:SetHeight(lbs.height(frame))
      frame:SetWidth(lbs.width(frame))
      frame.bar:SetLength(db.width)
      frame.bar:SetThickness(db.height)
      frame.icon:SetHeight(db.height)
      frame.icon:SetWidth(db.height)
      for id = 1, #lbs.labels do
	 local label = frame.labels[id]
	 local lw = lbs.labels[id].width
	 label:SetHeight(db.height)
	 if lw then 
	    label:SetWidth(lw)
	 end
      end
   end
   
   function mod:OnDragStart()
      if db.locked then return end
      mod.frame:StartMoving()
   end
   
   function mod:OnDragStop()
      mod:SavePosition()      
      mod.frame:StopMovingOrSizing()
   end
   
   local function SetColor(frame,cc)
      local bar = frame.bar
      if not bar or not cc then return end
      local color = db.colors[cc] or db.colors["CC"]
      if db.fadebars then
	 local fade = 0.5 + 0.5 * (bar.value / bar.maxValue)
	 bar:SetColor(color[1]*fade, color[2]*fade, color[3]*fade, color[4])
      else
	 bar:SetColor(color[1], color[2], color[3], color[4])
      end
      frame.color = cc
   end
   

   function mod:CreateBar(guid, current, maxVal)
      local lbs = mod:GetLabelData()
      local frame = tremove(mod.recycledFrames) or CreateFrame("Frame", nil, mod.frame)
      if frame.bar then
	 frame.bar:SetValue(current, maxVal)
      else
	 frame.bar = frame.bar or mod:NewSimpleBar(frame, current, maxVal, db.width, db.height)
      end
      
      frame:SetHeight(db.height)
      frame:SetWidth(db.width*2)

      frame.icon = frame.icon or frame:CreateTexture(nil, "OVERLAY")
      frame.icon:SetWidth(db.height)
      frame.icon:SetHeight(db.height)

      frame.SetBarFont   = SetBarFont      
      frame.GetSize = GetSize
      frame.Resize = ResizeBar
      frame.SetColor = SetColor 

      frame:SetScript("OnEnter", Bar_OnEnter);
      frame:SetScript("OnLeave", Bar_OnLeave);
      frame:SetScript("OnDragStart", mod.OnDragStart)
      frame:SetScript("OnDragStop", mod.OnDragStop)
      frame:RegisterForDrag("LeftButton")
      frame:EnableMouse(not db.locked or db.showTooltip)
    
      frame.guid = guid

      mod.bars[#mod.bars+1] = frame
      mod.unitbars[guid] = frame


      mod:SetupBarLabels(frame)
      mod:SetTexture(frame)
      mod:SortBars()
      frame:SetColor("Normal")      
      return frame
   end
end

do
   local tokens = {
      "%", "health", "target", "name", "type", "maxhealth", "cc", "count", "level"
   }
   local function tokenize(str, values)
      if strlen(str) > 2 then 
	 for _, k in ipairs(tokens) do
	    str = gsub(str, "%["..k.."%]", values[k] or "")
	 end
      end
      return str
   end

   function mod:SetBarStrings(frame)
      local tti = tooltipInfo[frame.guid]
      if tti then
	 if not mod.testBars then
	    local count = updated[frame.guid]
	    tti.count =  count and count > 0 and count or nil
	 end
	 for id, data in ipairs(mod:GetLabelData().labels) do
	    frame.labels[id]:SetText(tokenize(data.text, tti))
	 end
      end
   end
end

do
   local testNames = {
      "Elder Black Bear", "Young Brown Bear", "Big Hairy Spider", "Evil Gnoll", "Round Blob of Ooze"
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
	 if rnd(3) == 1 then
	    tti.count = rnd(12)
	 end
	 tti.targets = mod.get()
	 if rnd(3) == 1 then
	    tti.target = UnitName("player")
	 end	 
	 tti.maxhealth = tti.level * 99 + rnd(500)
	 tti.health = ceil(tti.maxhealth * (10+rnd(90))/100)
	 tti["%"] = ceil(100*tti.health/tti.maxhealth)
	 tooltipInfo[tostring(id)] = tti
	 if rnd(5) == 1 then
	    tti.cc = "<SH> 10"
	 end
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

