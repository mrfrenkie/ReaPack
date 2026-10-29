-- @noindex

-- @description Frenkie Chords Voicing
-- @author Mr. Frenkie
-- @version 2.0
-- @about
--   Раскладывает выделенную последовательность аккордов по голосам:
--   выбирает обращения и расположение так, чтобы голоса двигались плавно,
--   а вся фактура оставалась в том регистре, где она написана.
--   Работает без базы аккордов. Число нот в каждом аккорде сохраняется.
-- @changelog
--   v2.0 - Полностью новый движок: динамика по всей цепочке вместо жадного шага,
--          неподвижный якорь регистра, инерция, отказ от таблицы аккордов
-- @provides
--   [main=midi_editor] .

--------------------------------------------------------------------------------
-- НАСТРОЙКИ (менять можно, всё в полутонах и условных единицах цены)
--------------------------------------------------------------------------------

local W_MOVE          = 1.0   -- цена движения голоса за полутон
local W_MOVE_SQ       = 0.15  -- надбавка за большие скачки (один большой дороже нескольких мелких)
local W_TOP           = 1.4   -- верхний голос двигать дороже: бережём мелодию
local BONUS_COMMON    = 4.0   -- скидка за общий звук, оставшийся в том же голосе
local W_PARALLEL      = 6.0   -- мягкий штраф за параллельные квинты и октавы
local W_CORRIDOR      = 0.09  -- цена выхода за коридор регистра (растёт квадратично)
local W_INERTIA       = 0.8   -- скидка за неподвижность относительно написанного
local W_MUD           = 5.0   -- штраф за тесные интервалы между соседними голосами
local BASS_GAP_SOFT   = 16    -- бас спокойно отстоит от следующего голоса на дециму и дальше
local BASS_GAP_MAX    = 24    -- но не дальше двух октав
local W_BASS_GAP      = 0.8

-- Цена того, какая ступень аккорда оказалась в басу (интервал баса над основным тоном).
-- Основной тон внизу звучит устойчиво, терция — легко и нормально,
-- квинта — подвешенно, септима — слабо, надстройки внизу почти всегда звучат как ошибка.
local BASS_DEGREE_COST = {
  [0] = -6,   -- основной тон
  [4] = -1,   -- большая терция
  [3] = -1,   -- малая терция
  [7] = 5,    -- квинта
  [6] = 5,    -- уменьшённая квинта
  [8] = 5,    -- увеличенная квинта
  [10] = 4,   -- малая септима
  [11] = 4,   -- большая септима
  [1] = 7, [2] = 7, [5] = 7, [9] = 7,
}

-- Приличный минимальный интервал между соседними голосами зависит от регистра:
-- чем ниже, тем шире должно быть, иначе звук мутнеет.
local function min_gap_at(pitch)
  if pitch < 48 then return 7 end
  if pitch < 55 then return 5 end
  if pitch < 62 then return 3 end
  return 2
end

local FIRST_CHORD_ANCHOR = 2.5 -- насколько крепче держим первый аккорд за написанное

local MAX_CANDIDATES  = 64    -- потолок вариантов на аккорд (держит расчёт быстрым)
local MAX_PERMS       = 1500  -- потолок перестановок голосов на аккорд
local CORRIDOR_BASE   = 4.0   -- ширина коридора: BASE + PER_VOICE * число голосов
local CORRIDOR_PER_VOICE = 2.5

--------------------------------------------------------------------------------
-- ОПРЕДЕЛЕНИЕ ОСНОВНОГО ТОНА (без базы аккордов)
--------------------------------------------------------------------------------

-- Вес интервала от предполагаемого основного тона.
-- Аккорд складывается через один: прима, терция, квинта, септима — «свои» ступени.
-- Чем больше звуков аккорда попадает на них, тем вероятнее, что основной тон угадан.
local ROOT_WEIGHT = {
  [0] = 5,   -- прима
  [4] = 4,   -- большая терция
  [3] = 4,   -- малая терция
  [7] = 4,   -- чистая квинта
  [10] = 3,  -- малая септима
  [11] = 3,  -- большая септима
  [2] = 2,   -- нона
  [9] = 2,   -- секста / тринадцатая
  [5] = 1,   -- кварта / ундецима
  [6] = 1,   -- тритон
  [8] = 1,   -- увеличенная квинта
  [1] = 0,   -- малая секунда
}

-- Возвращает высотный класс основного тона (0..11) или nil, если уверенности нет.
-- Кластеры и квартовые созвучия честно возвращают nil — скрипт на этом не спотыкается,
-- просто не начисляет скидку за устойчивый бас.
-- Три и более звука подряд по полутонам — это кластер, а не аккорд.
-- У кластера нет основного тона, раскладывать его по голосам бессмысленно.
local function is_cluster(unique_pcs)
  local present = {}
  for _, pc in ipairs(unique_pcs) do present[pc] = true end
  for start = 0, 11 do
    if present[start] and present[(start + 1) % 12] and present[(start + 2) % 12] then
      return true
    end
  end
  return false
end

local function estimate_root(unique_pcs, written_bass_pc)
  if #unique_pcs == 0 then return nil end
  if #unique_pcs == 1 then return unique_pcs[1] end
  if is_cluster(unique_pcs) then return nil end

  local best_pc, best_score = nil, -1
  for _, root in ipairs(unique_pcs) do
    local score = 0
    for _, pc in ipairs(unique_pcs) do
      score = score + (ROOT_WEIGHT[(pc - root) % 12] or 0)
    end
    -- при равенстве очков предпочитаем тот тон, который ты сам положил в бас
    if root == written_bass_pc then score = score + 0.5 end
    if score > best_score then
      best_score, best_pc = score, root
    end
  end

  -- слишком слабое совпадение — значит это не аккорд в привычном смысле
  local max_possible = 5 + 4 * (#unique_pcs - 1)
  if best_score < max_possible * 0.45 then return nil end
  return best_pc
end

--------------------------------------------------------------------------------
-- ГЕНЕРАЦИЯ ВАРИАНТОВ РАСКЛАДКИ
--------------------------------------------------------------------------------

-- Все порядки голосов снизу вверх для данного набора звуков (с учётом удвоений).
local function gen_orders(unique_pcs, counts, n)
  local out, acc = {}, {}
  local overflow = false

  local function rec()
    if #acc == n then
      if #out >= MAX_PERMS then overflow = true return false end
      local copy = {}
      for i = 1, n do copy[i] = acc[i] end
      out[#out + 1] = copy
      return true
    end
    for i = 1, #unique_pcs do
      local pc = unique_pcs[i]
      if counts[pc] > 0 then
        counts[pc] = counts[pc] - 1
        acc[#acc + 1] = pc
        local ok = rec()
        acc[#acc] = nil
        counts[pc] = counts[pc] + 1
        if not ok then return false end
      end
    end
    return true
  end

  rec()
  return out, overflow
end

-- Раскладывает голоса снизу вверх по заданному порядку от заданной басовой ноты.
-- Ключевой момент: как только порядок голосов выбран, а дыры больше октавы запрещены,
-- все остальные высоты определяются однозначно. Отсюда и берётся дешевизна расчёта.
local function build_voicing(order, bass_pitch)
  local p = {bass_pitch}
  for i = 2, #order do
    local prev = p[i - 1]
    local step = (order[i] - prev) % 12
    if step == 0 then step = 12 end -- унисоны не делаем, удвоение уходит в октаву
    p[i] = prev + step
  end
  return p
end

--------------------------------------------------------------------------------
-- ЦЕНА ВАРИАНТА САМОГО ПО СЕБЕ
--------------------------------------------------------------------------------

-- anchor: множитель «держись написанного». Для первого аккорда он повышен —
-- первый аккорд задаёт тональность и регистр, его нельзя обращать ради удобства связи.
local function static_cost(pitches, lo, hi, orig, root_pc, anchor)
  local cost = 0
  local n = #pitches
  anchor = anchor or 1.0

  -- выход за коридор регистра: внутри бесплатно, снаружи дорожает быстро
  for i = 1, n do
    local p = pitches[i]
    if p < lo then
      local d = lo - p
      cost = cost + d * d * W_CORRIDOR
    elseif p > hi then
      local d = p - hi
      cost = cost + d * d * W_CORRIDOR
    end
  end

  -- тесные интервалы звучат мутно тем сильнее, чем ниже они расположены
  for i = 2, n do
    local gap = pitches[i] - pitches[i - 1]
    local need = min_gap_at(pitches[i - 1])
    if gap < need then
      cost = cost + (need - gap) * W_MUD
    end
  end

  -- басу позволено отстоять дальше остальных, но не бесконечно
  if n >= 2 then
    local bass_gap = pitches[2] - pitches[1]
    if bass_gap > BASS_GAP_SOFT then
      cost = cost + (bass_gap - BASS_GAP_SOFT) * W_BASS_GAP
    end
  end

  -- какая ступень аккорда лежит в басу
  if root_pc then
    cost = cost + (BASS_DEGREE_COST[(pitches[1] - root_pc) % 12] or 7) * anchor
  end

  -- инерция: если ты уже разложил хорошо, скрипт не должен всё перекладывать
  if orig then
    local m = math.min(n, #orig)
    for i = 1, m do
      cost = cost + math.abs(pitches[i] - orig[i]) * W_INERTIA * anchor
    end
  end

  return cost
end

--------------------------------------------------------------------------------
-- ЦЕНА ПЕРЕХОДА ОТ ПРЕДЫДУЩЕГО АККОРДА
--------------------------------------------------------------------------------

-- Параллельная квинта или октава в одной паре голосов.
-- Отдельной функцией и без временных таблиц: вызывается сотни тысяч раз.
local function is_parallel(prev, cur, i, j)
  local a_i, a_j = prev[i], prev[j]
  local b_i, b_j = cur[i], cur[j]
  local iv_prev = (a_j - a_i) % 12
  if iv_prev ~= 0 and iv_prev ~= 7 then return false end
  if (b_j - b_i) % 12 ~= iv_prev then return false end
  local mi, mj = b_i - a_i, b_j - a_j
  return (mi > 0 and mj > 0) or (mi < 0 and mj < 0)
end

local function transition_cost(prev, cur)
  local np, nc = #prev, #cur
  if np == 0 then return 0 end
  local n = np > nc and np or nc
  local cost = 0

  for i = 1, n do
    local a = prev[i < np and i or np]
    local b = cur[i < nc and i or nc]
    local d = a - b
    if d < 0 then d = -d end
    local step = d * W_MOVE + d * d * W_MOVE_SQ
    if i == n then step = step * W_TOP end
    cost = cost + step
    if d == 0 then cost = cost - (i == n and BONUS_COMMON * W_TOP or BONUS_COMMON) end
  end

  -- Параллельные квинты и октавы: смотрим соседние голоса и крайние.
  -- Штраф мягкий: в джазовой и электронной фактуре это приём, а не ошибка.
  local m = np < nc and np or nc
  for i = 1, m - 1 do
    if is_parallel(prev, cur, i, i + 1) then cost = cost + W_PARALLEL end
  end
  if m >= 3 and is_parallel(prev, cur, 1, m) then cost = cost + W_PARALLEL end

  return cost
end

--------------------------------------------------------------------------------
-- ОСНОВНАЯ ЛОГИКА
--------------------------------------------------------------------------------

local function group_into_chords(notes, tol)
  table.sort(notes, function(a, b)
    if a.startppqpos == b.startppqpos then return a.pitch < b.pitch end
    return a.startppqpos < b.startppqpos
  end)

  -- допуск на неровную игру: ноты, начавшиеся почти одновременно, считаем аккордом
  local chords, cur = {}, {notes[1]}
  for i = 2, #notes do
    if notes[i].startppqpos - cur[1].startppqpos <= tol then
      cur[#cur + 1] = notes[i]
    else
      chords[#chords + 1] = cur
      cur = {notes[i]}
    end
  end
  chords[#chords + 1] = cur

  for _, ch in ipairs(chords) do
    table.sort(ch, function(a, b) return a.pitch < b.pitch end)
  end
  return chords
end

local function make_candidates(chord, lo, hi, anchor)
  local n = #chord

  -- Один голос раскладывать нечем: у одной ноты нет расположения.
  -- Двигать её по октавам — значит переписать мелодию, чего делать нельзя.
  -- Соседним аккордам она при этом остаётся ориентиром при выборе связи.
  if n == 1 then
    return {{pitches = {chord[1].pitch}, cost = 0}}
  end
  local counts, unique_pcs = {}, {}
  local orig = {}
  for i, note in ipairs(chord) do
    orig[i] = note.pitch
    local pc = note.pitch % 12
    if not counts[pc] then
      counts[pc] = 0
      unique_pcs[#unique_pcs + 1] = pc
    end
    counts[pc] = counts[pc] + 1
  end
  table.sort(unique_pcs)

  local root_pc = estimate_root(unique_pcs, chord[1].pitch % 12)

  -- Основной тон не определился: это не аккорд в привычном смысле, а кластер
  -- или квартовое созвучие. Перекладывать такое по голосам бессмысленно —
  -- оставляем как написано, разрешая только сдвиг по октавам в коридор.
  if not root_pc then
    local cands = {}
    for oct = -2, 2 do
      local p, ok = {}, true
      for i = 1, n do
        p[i] = orig[i] + oct * 12
        if p[i] < 0 or p[i] > 127 then ok = false break end
      end
      if ok then
        cands[#cands + 1] = {pitches = p, cost = static_cost(p, lo, hi, orig, nil, anchor)}
      end
    end
    if #cands == 0 then cands[1] = {pitches = orig, cost = 0} end
    return cands
  end

  local orders = gen_orders(unique_pcs, counts, n)

  -- басовые позиции: только те октавы, что имеют отношение к коридору
  local bass_lo = math.max(0, math.floor(lo) - 14)
  local bass_hi = math.min(127, math.ceil(hi))

  local cands = {}
  for _, order in ipairs(orders) do
    local pc = order[1]
    local start = bass_lo + ((pc - bass_lo) % 12)
    for bass = start, bass_hi, 12 do
      -- обычная раскладка и вариант с басом на октаву ниже
      for _, drop in ipairs({0, 12}) do
        local base = build_voicing(order, bass)
        if drop > 0 then base[1] = base[1] - drop end
        local ok = true
        for i = 1, n do
          if base[i] < 0 or base[i] > 127 then ok = false break end
        end
        if ok and n >= 2 and (base[2] - base[1]) > BASS_GAP_MAX then ok = false end
        if ok and base[n] > hi + 20 then ok = false end
        if ok and base[1] < lo - 20 then ok = false end
        if ok then
          cands[#cands + 1] = {
            pitches = base,
            cost = static_cost(base, lo, hi, orig, root_pc, anchor),
          }
        end
        if n < 2 then break end
      end
    end
  end

  if #cands == 0 then
    cands[1] = {pitches = orig, cost = 0}
    return cands
  end

  table.sort(cands, function(a, b) return a.cost < b.cost end)
  while #cands > MAX_CANDIDATES do table.remove(cands) end
  return cands
end

-- Динамика по всей цепочке: ищем лучший путь целиком, а не лучший следующий шаг.
-- Именно это убирает дрейф — движок может пойти на чуть больший шаг сейчас,
-- чтобы через три аккорда не упереться в границу коридора.
local function solve(chord_candidates)
  local n = #chord_candidates
  local dp, back = {}, {}

  dp[1] = {}
  for j, c in ipairs(chord_candidates[1]) do dp[1][j] = c.cost end

  for i = 2, n do
    dp[i], back[i] = {}, {}
    local prev_cands, cur_cands = chord_candidates[i - 1], chord_candidates[i]
    for j, cj in ipairs(cur_cands) do
      local best, best_k = math.huge, 1
      for k, ck in ipairs(prev_cands) do
        local t = dp[i - 1][k] + transition_cost(ck.pitches, cj.pitches)
        if t < best then best, best_k = t, k end
      end
      dp[i][j] = best + cj.cost
      back[i][j] = best_k
    end
  end

  local best, best_j = math.huge, 1
  for j, v in ipairs(dp[n]) do
    if v < best then best, best_j = v, j end
  end

  local path = {}
  local j = best_j
  for i = n, 1, -1 do
    path[i] = chord_candidates[i][j].pitches
    if i > 1 then j = back[i][j] end
  end
  return path
end

function main()
  local hwnd = reaper.MIDIEditor_GetActive()
  if not hwnd then
    reaper.ShowMessageBox("Скрипт нужно запускать из MIDI-редактора.", "Ошибка", 0)
    return
  end
  local take = reaper.MIDIEditor_GetTake(hwnd)
  if not take or not reaper.TakeIsMIDI(take) then
    reaper.ShowMessageBox("MIDI-дорожка не найдена.", "Ошибка", 0)
    return
  end

  local _, notecnt = reaper.MIDI_CountEvts(take)
  local all_notes, selected = {}, {}
  for i = 0, notecnt - 1 do
    local _, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    local note = {
      index = i, pitch = pitch, vel = vel, chan = chan, muted = muted,
      startppqpos = sppq, endppqpos = eppq, selected = sel
    }
    all_notes[#all_notes + 1] = note
    if sel then selected[#selected + 1] = note end
  end

  -- есть выделение — работаем строго по нему, нет — по всему
  local src = (#selected >= 1) and selected or all_notes
  if #src < 1 then
    reaper.ShowMessageBox("Нет нот для обработки.", "Инфо", 0)
    return
  end

  -- допуск группировки привязан к сетке проекта, а не к абсолютному числу тиков:
  -- тридцать вторая. Сыгранные с клавиатуры аккорды не рассыплются на отдельные ноты.
  local ppq = 960
  if reaper.MIDI_GetPPQPosFromProjQN then
    local a = reaper.MIDI_GetPPQPosFromProjQN(take, 0)
    local b = reaper.MIDI_GetPPQPosFromProjQN(take, 1)
    if a and b and b > a then ppq = b - a end
  end
  local chords = group_into_chords(src, ppq / 8)

  -- одноголосие раскладывать нечем: говорим об этом, а не молчим
  local has_chord = false
  for _, ch in ipairs(chords) do
    if #ch >= 2 then has_chord = true break end
  end
  if not has_chord then
    reaper.ShowMessageBox(
      "В выделении только одноголосие — раскладывать нечего.\nВыделите аккорды (от двух нот одновременно).",
      "Frenkie Chords Voicing", 0)
    return
  end

  -- Якорь регистра: центр берём от материала, ширину — от числа голосов.
  -- Считается один раз и дальше не двигается, поэтому фактуре некуда уползать.
  local sum, max_voices = 0, 1
  for _, note in ipairs(src) do sum = sum + note.pitch end
  for _, ch in ipairs(chords) do
    if #ch > max_voices then max_voices = #ch end
  end
  local center = sum / #src
  local half = CORRIDOR_BASE + CORRIDOR_PER_VOICE * max_voices
  local lo, hi = center - half, center + half

  local chord_candidates = {}
  for i, ch in ipairs(chords) do
    -- первый аккорд держим за написанное крепче: он задаёт тональность и регистр
    chord_candidates[i] = make_candidates(ch, lo, hi, i == 1 and FIRST_CHORD_ANCHOR or 1.0)
  end

  local path = solve(chord_candidates)

  local proj = reaper.EnumProjects(-1, "")
  reaper.Undo_BeginBlock2(proj)
  reaper.PreventUIRefresh(1)

  for i, ch in ipairs(chords) do
    local pitches = path[i]
    for v, note in ipairs(ch) do
      local new_pitch = pitches[math.min(v, #pitches)]
      if new_pitch ~= note.pitch then
        reaper.MIDI_SetNote(take, note.index, note.selected, note.muted,
          note.startppqpos, note.endppqpos, note.chan, new_pitch, note.vel, true)
      end
    end
  end

  reaper.MIDI_Sort(take)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock2(proj, "Frenkie Chords Voicing", -1)
  reaper.UpdateArrange()
end

main()
