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
local L = LibStub("AceLocale-3.0"):GetLocale("MagicTargetsTheme")
local mod = MagicTargets
mod.labelThemes = {
   default = {
      width = function(f)
		 local l = f.labels
		 return l[1]:GetWidth() + l[2]:GetWidth() + l[4]:GetWidth() + f.bar:GetWidth() + f.icon:GetWidth() + 20
	      end,
      height = function(f) return mod.db.profile.height end,
      name = "Magic Targets 2", 
      -- # Unit Name @ [======    cc] xx%.
      icon = {
	 visible = true,
	 anchor = "LEFT",
	 anchorFrame = 2,
	 anchorTo = "RIGHT",
	 offsetx = 3,
      },
      bar = {
	 anchor = "LEFT",
	 anchorFrame = "icon",
	 anchorTo = "RIGHT",
	 offsetx = 3,
      },
      labels = {
	 {
	    name = L["Left Label #1"], 
	    text = "[count]",
	    anchor = "LEFT",
	    anchorTo = "LEFT",
	    anchorFrame = "frame",
	    xoffset = 0,
	    width = 20,
	    justifyH = "RIGHT",
	    justifyV = "CENTER", 
	 },
	 {
	    name = L["Left Label #2"], 
	    text = "[name]",
	    anchor = "LEFT",
	    anchorTo = "RIGHT", 
	    anchorFrame = 1,
	    xoffset = 5,
	    width = 95, 
	    justifyH = "LEFT",
	    justifyV = "CENTER",
	 },
	 {
	    name = L["Bar Label"], 
	    text = "[cc]",
	    anchor = "TOPRIGHT",
	    anchorTo = "TOPRIGHT",
	    anchorFrame = "bar",
	    anchor2 = "BOTTOMLEFT",
	    anchorTo2 = "BOTTOMLEFT",
	    anchorFrame2 = "bar",
	    xoffset = -7,
	    xoffset2 = 3,
	    justifyH = "RIGHT",
	    justifyV = "CENTER", 
	 },
	 {
	    name = L["Right Label"], 
	    text = "[%]%",
	    anchor = "LEFT",
	    anchorTo = "RIGHT",
	    anchorFrame = "bar",
	    anchor2 = "RIGHT",
	    anchorTo2 = "RIGHT",
	    anchorFrame2 = "frame",	    
	    xoffset = 3,
	    xoffset2 = -3,
	    width = 25,
	    justifyH = "RIGHT",
	    justifyV = "CENTER",
	 }
      }
   },
   classic = {
      -- @[=Unit=Name===   #cc] xx%.
      width = function(f)
		 local l = f.labels
		 return l[3]:GetWidth() + f.bar:GetWidth() + f.icon:GetWidth() + 10
	      end,
      height = function(f) return mod.db.profile.height end,
      name = "Classic Magic Targets", 
      icon = {
	 visible = true,
	 anchor = "LEFT",
	 anchorFrame = "frame",
	 anchorTo = "LEFT",
	 offsetx = 0,
      },
      bar = {
	 anchor = "LEFT",
	 anchorFrame = "icon",
	 anchorTo = "RIGHT",
	 offsetx = 3,
      },
      labels = {
	 {
	    name = L["Left Bar Label"], 
	    text = "[name]",
	    anchor = "RIGHT",
	    anchorTo = "RIGHT",
	    anchorFrame = "bar",
	    anchor2 = "LEFT",
	    anchorTo2 = "LEFT",
	    anchorFrame2 = "bar",
	    xoffset = -7,
	    xoffset2 = 3,
	    justifyH = "LEFT",
	    justifyV = "CENTER", 
	 },
	 {
	    name = L["Right Bar Label"], 
	    text = "[count][cc]",
	    anchor = "RIGHT",
	    anchorTo = "RIGHT",
	    anchorFrame = "bar",
	    anchor2 = "LEFT",
	    anchorTo2 = "LEFT",
	    anchorFrame2 = "bar",
	    xoffset = -7,
	    xoffset2 = 3,
	    justifyH = "RIGHT",
	    justifyV = "CENTER", 
	 },
	 {
	    name = L["Right Label"], 
	    text = "[%]%",
	    anchor = "LEFT",
	    anchorTo = "RIGHT",
	    anchorFrame = "bar",
	    anchor2 = "RIGHT",
	    anchorTo2 = "RIGHT",
	    anchorFrame2 = "frame",	    
	    xoffset = 5,
	    xoffset2 = -3,
	    width = 32,
	    justifyH = "RIGHT",
	    justifyV = "CENTER",
	 }
      }
   },
}

