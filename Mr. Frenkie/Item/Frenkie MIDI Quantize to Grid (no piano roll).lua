-- @noindex

-- @author Mr. Frenkie
-- @version 2.2
-- @description Квантизация MIDI нот к сетке аранжировки 
-- Выставь сетку и свинг в аранжировке, выдели MIDI-айтемы и запусти скрипт.

local r = reaper

-- Чтение сетки как в cool_MK: GetSetProjectGrid(0, false) → _, division, swingmode, swingamt.
-- В формуле сдвига cool_MK использует сырое swingamt из API (не (x+1)/2): 0 = 50% в UI = 0 сдвиг, 1 = макс свинг.
local function get_arrange_grid()
  local _, division, swingmode, swingamt = r.GetSetProjectGrid(0, false)
  if not division or division <= 0 then return nil end
  if division < 0.0078125 then division = 0.0078125 end
  if swingamt == nil then swingamt = 0 end
  if swingamt > 1 then swingamt = swingamt / 100 end  -- UI 0–100 → 0–1
  -- Не делаем (x+1)/2 — в формуле нужен сырой API: 0 = 50% (ровно), 1 = макс, -1 = обратный свинг
  local swing_on = (swingmode == 1)
  return { division = division, swing_on = swing_on, swing_amt = swingamt }
end

-- Шаг сетки в QN: в cool_MK beatc() делает fullbeats + (division*4) — один шаг = division*4 quarter notes
local function grid_step_qn(division)
  return division * 4
end

-- Ближайшая линия сетки в QN по логике cool_MK:
-- Прямая сетка: линии на 0, step_qn, 2*step_qn, ...
-- Со свингом: вторую линию в паре сдвигаем на sw_shift сек. Сырой swingamt: 0 = 50% в UI (0 сдвиг), 1 = макс.
local function nearest_grid_qn(qn, grid)
  local division = grid.division
  local step_qn = grid_step_qn(division)
  local pair_qn = 2 * step_qn

  if not grid.swing_on or math.abs(grid.swing_amt) < 0.0001 then
    return math.floor(qn / step_qn + 0.5) * step_qn
  end

  local swingamt = grid.swing_amt  -- сырое из API: 0 = 50%, 1 = макс свинг
  local tempo_corr = 120 / r.Master_GetTempo()
  local shift_sec = swingamt * (1 - math.abs(division - 1)) * tempo_corr

  local pair_idx = math.floor(qn / pair_qn)
  local t0 = pair_idx * pair_qn
  local t_and_straight_qn = t0 + step_qn
  local t_and_time = r.TimeMap2_QNToTime(0, t_and_straight_qn)
  local t_and_time_swung = t_and_time + shift_sec
  local t_and_qn = r.TimeMap2_timeToQN(0, t_and_time_swung)
  local t2 = t0 + pair_qn

  if qn <= (t0 + t_and_qn) / 2 then
    return t0
  end
  if qn <= (t_and_qn + t2) / 2 then
    return t_and_qn
  end
  return t2
end

-- Квантизация одного take. Минимальная длина ноты после квантизации = полшага сетки (чтобы концы не «слипались»).
local function quantize_take(item, take, grid, strength, quantize_end)
  if not item or not take or not r.TakeIsMIDI(take) or not grid then return 0 end
  local ok, notecnt, _, _ = r.MIDI_CountEvts(take)
  if not ok or notecnt == 0 then return 0 end

  strength = (strength or 100) / 100
  strength = math.max(0, math.min(1, strength))
  quantize_end = (quantize_end == nil) and true or quantize_end

  local step_qn = grid_step_qn(grid.division)
  local min_duration_qn = step_qn * 0.5  -- минимум полшага сетки

  local changed = 0
  for i = 0, notecnt - 1 do
    local ok_n, sel, muted, startppq, endppq, chan, pitch, vel = r.MIDI_GetNote(take, i)
    if not ok_n then break end

    local start_qn = r.MIDI_GetProjQNFromPPQPos(take, startppq)
    local end_qn = r.MIDI_GetProjQNFromPPQPos(take, endppq)

    local q_start_qn = nearest_grid_qn(start_qn, grid)
    local q_end_qn = nearest_grid_qn(end_qn, grid)

    local new_start_qn = start_qn + (q_start_qn - start_qn) * strength
    local new_end_qn = quantize_end and (end_qn + (q_end_qn - end_qn) * strength) or end_qn

    local new_start_ppq = r.MIDI_GetPPQPosFromProjQN(take, new_start_qn)
    local new_end_ppq = r.MIDI_GetPPQPosFromProjQN(take, new_end_qn)

    new_start_ppq = math.floor(new_start_ppq + 0.5)
    new_end_ppq = math.floor(new_end_ppq + 0.5)

    local min_end_ppq = r.MIDI_GetPPQPosFromProjQN(take, new_start_qn + min_duration_qn)
    min_end_ppq = math.floor(min_end_ppq + 0.5)
    if new_end_ppq <= new_start_ppq or new_end_ppq < min_end_ppq then
      new_end_ppq = math.max(new_start_ppq + 1, min_end_ppq)
    end

    r.MIDI_SetNote(take, i, sel, muted, new_start_ppq, new_end_ppq, chan, pitch, vel, true)
    changed = changed + 1
  end

  if changed > 0 then
    r.MIDI_Sort(take)
    r.UpdateItemInProject(item)
  end
  return changed
end

local function main()
  local sel_count = r.CountSelectedMediaItems(0)
  if sel_count == 0 then return end

  local grid = get_arrange_grid()
  if not grid then return end

  r.Undo_BeginBlock2(0)
  r.PreventUIRefresh(1)

  local total_notes = 0
  local items_processed = 0

  for i = 0, sel_count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if item then
      local take = r.GetActiveTake(item)
      if take and r.TakeIsMIDI(take) then
        local n = quantize_take(item, take, grid, 100, true)
        if n > 0 then
          total_notes = total_notes + n
          items_processed = items_processed + 1
        end
      end
    end
  end

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(0, "MIDI Quantize to grid (no piano roll)", -1)
end

main()
