-- @noindex

---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local Utils = {}

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

function Utils.vol_to_db(vol)
    return vol <= 0 and -math.huge or 20 * math.log(vol, 10)
end

function Utils.db_to_vol(db)
    return 10^(db/20)
end

function Utils.with_undo(description, func)
    r.Undo_BeginBlock()
    func()
    r.Undo_EndBlock(description, -1)
end

function Utils.shallow_equal(t1, t2)
    if #t1 ~= #t2 then return false end
    for k, v in pairs(t1) do
        if v ~= t2[k] then return false end
    end
    return true
end

function Utils.DeferClearCursorContext()
    r.defer(function() r.SetCursorContext(0, nil) end)
end

function Utils.ClearCursorContextOnDeactivation(ctx)
    local deactivated = r.ImGui_IsItemDeactivated(ctx)
    if deactivated then
        local hovered = r.ImGui_IsWindowHovered(ctx)
        if not hovered then
            Utils.DeferClearCursorContext()
        end
    end
    return deactivated
end

function Utils.GetScriptDir()
    return script_dir
end

return Utils
