-- @noindex
---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local Utils = {}

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

-- Parses the extension's tab-separated key=value state strings into a table.
function Utils.ParseKeyValues(raw)
    local t = {}
    for pair in (raw or ''):gmatch('[^\t]+') do
        local k, v = pair:match('^(.-)=(.*)$')
        if k then t[k] = v end
    end
    return t
end

function Utils.with_undo(description, func)
    r.Undo_BeginBlock()
    func()
    r.Undo_EndBlock(description, -1)
end

-- After a drag in the widget ended outside it: the keyboard focus back to REAPER, in the context it had
-- (FIP_ContextReturnFocus), on the next tick.
function Utils.DeferReturnFocus()
    r.defer(function()
        if r.APIExists('FIP_ContextReturnFocus') then r.FIP_ContextReturnFocus('', 0) end
    end)
end

function Utils.ReturnFocusOnDeactivation(ctx)
    local deactivated = r.ImGui_IsItemDeactivated(ctx)
    if deactivated then
        local hovered = r.ImGui_IsWindowHovered(ctx)
        if not hovered then
            Utils.DeferReturnFocus()
        end
    end
    return deactivated
end

return Utils
