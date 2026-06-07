-- @noindex

---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local Theme = {}

-- Тема интерфейса: здесь собраны все цвета.
-- Меняйте значения по своему вкусу: каждое имя используется в конкретных местах UI.

-- Упаковка RGBA в native формат REAPER/ImGui
function Theme.rgba(r_val, g_val, b_val, a_val)
    a_val = a_val or 255
    local ok, u32 = pcall(r.ImGui_ColorConvertDouble4ToU32, r_val/255, g_val/255, b_val/255, a_val/255)
    if ok then return u32 end
    return (a_val << 24) | (b_val << 16) | (g_val << 8) | r_val
end

local function clamp255(v)
    v = math.floor((tonumber(v) or 0) + 0.5)
    if v < 0 then return 0 end
    if v > 255 then return 255 end
    return v
end

function Theme.getMainWindowTransportBackground()
    if not (r.GetThemeColor and r.ColorFromNative) then
        return Theme.get('gray_30')
    end

    local native = r.GetThemeColor('col_main_bg2', 0)
    if not native or native == -1 then
        return Theme.get('gray_30')
    end

    local rr, gg, bb = r.ColorFromNative(native)
    rr = clamp255((tonumber(rr) or 35) * 0.95)
    gg = clamp255((tonumber(gg) or 35) * 0.95)
    bb = clamp255((tonumber(bb) or 35) * 0.95)
    return Theme.rgba(rr, gg, bb, 255)
end

Theme.colors = {
    transparent = Theme.rgba(0, 0, 0, 0),           -- Прозрачный фон для скрытых/заблокированных элементов

    -- Основные серые тона (фон окна, поля, кнопки)
    gray_30 = Theme.rgba(35, 35, 35, 255),          -- Фон окна
    gray_42 = Theme.rgba(42, 42, 42, 255),          -- Фон полей ввода/слайдеров
    gray_45 = Theme.rgba(45, 45, 45, 255),          -- Заголовок окна (обычный)
    gray_58 = Theme.rgba(58, 58, 58, 255),          -- Поле при наведении
    gray_61 = Theme.rgba(61, 61, 61, 255),          -- Заголовок окна (активный)
    gray_64 = Theme.rgba(64, 64, 64, 255),          -- Базовый цвет кнопок и инпутов
    gray_74 = Theme.rgba(74, 74, 74, 255),          -- Поле при активном состоянии
    gray_80 = Theme.rgba(80, 80, 80, 255),          -- Кнопка при наведении
    gray_96 = Theme.rgba(96, 96, 96, 255),          -- Кнопка при активном состоянии

    -- Акцентные цвета
    green_accent = Theme.rgba(38, 166, 154, 255),   -- Акцент: изменённые параметры, чекмарки, FX
    blue_freeze = Theme.rgba(33, 150, 243, 255),    -- Акцент: кнопка Unfreeze

    -- Красные для Reset
    red_base = Theme.rgba(180, 70, 70, 255),        -- Кнопка Reset (база)
    red_hover = Theme.rgba(200, 90, 90, 255),       -- Кнопка Reset (hover)
    red_active = Theme.rgba(220, 100, 100, 255),    -- Кнопка Reset (active)

    yellow = Theme.rgba(255, 255, 0, 255),          -- Смешанное состояние чекбокса
    black = Theme.rgba(0, 0, 0, 255),
    beige_base = Theme.rgba(222, 203, 164, 255),
    beige_hover = Theme.rgba(230, 211, 174, 255),
    beige_active = Theme.rgba(238, 219, 184, 255),
    orange_dark = Theme.rgba(255, 140, 0, 255),
    turquoise = Theme.rgba(64, 224, 208, 255),

    text_gray = Theme.rgba(128, 128, 128, 255),     -- Отключённый текст
    text_gray_bright = Theme.rgba(180, 180, 180, 255),
    text_white_soft = Theme.rgba(220, 220, 220, 255),
    pipe_gray = Theme.rgba(96, 96, 96, 255),        -- Разделитель "|" и чекмарка в disabled
    frame_disabled = Theme.rgba(48, 48, 48, 255),   -- Фон контролов в disabled

    hover_white_32 = Theme.rgba(255, 255, 255, 32), -- Светлая подсветка hover для прозрачных кнопок
    active_white_64 = Theme.rgba(255, 255, 255, 64), -- Светлая подсветка active для прозрачных кнопок

    tooltip_bg = Theme.rgba(176, 176, 176, 217),
    tooltip_border = Theme.rgba(0, 0, 0, 0),
    tooltip_text = Theme.rgba(0, 0, 0, 255),
    tooltip_fx_bypass = Theme.rgba(180, 85, 0, 255),
    tooltip_fx_disabled = Theme.rgba(120, 38, 38, 255),
}

function Theme.get(name)
    return Theme.colors[name]
end

return Theme
