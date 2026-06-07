-- @noindex

---@diagnostic disable: undefined-global, undefined-field
-- Frenkie Item Properties 2.6
-- Основной скрипт просто запускает UI модуль

-- Заменить абсолютные пути на:
local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""
local sep = package.config:sub(1, 1)

local r = reaper
local _, _, sectionID, cmdID = r.get_action_context()
if sectionID and cmdID ~= 0 then
    r.SetToggleCommandState(sectionID, cmdID, 1)
    r.RefreshToolbar2(sectionID, cmdID)
    r.atexit(function()
        r.SetToggleCommandState(sectionID, cmdID, 0)
        r.RefreshToolbar2(sectionID, cmdID)
    end)
end

dofile(script_dir .. "ItemProperties" .. sep .. "UI.lua")
