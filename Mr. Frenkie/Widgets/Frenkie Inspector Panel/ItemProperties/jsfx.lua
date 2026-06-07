-- @noindex

local JSFX = {}

JSFX.MIDI_TRANSPOSE_UTILITY_JSFX = [[desc:MIDI Transpose and Monitor
//tags: MIDI processing utility
//author: Mr. Frenkie (Modified)

slider1:0<-48,48,1>Transpose (Semitones)
options:no_meter

@init

function find_substr(hay, needle)
local(hlen, nlen, i, j, ok, ret)
(
  hlen = strlen(hay);
  nlen = strlen(needle);
  ret = -1;
  (nlen <= 0 || hlen < nlen) ? ret : (
    i = 0;
    while (i <= hlen - nlen && ret < 0) (
      ok = 1;
      j = 0;
      while (j < nlen && ok) (
        str_getchar(hay, i + j, 'c') != str_getchar(needle, j, 'c') ? ok = 0;
        j += 1;
      );
      ok ? ret = i;
      i += 1;
    );
    ret;
  );
);

function mem_to_str(mem_ptr, out_str)
local(o, c)
(
  o = 0;
  c = mem_ptr[];
  while (c) (
    str_setchar(out_str, o, c, 'c');
    o += 1;
    mem_ptr += 1;
    c = mem_ptr[];
  );
  str_setchar(out_str, o, 0, 'c');
);

function str_to_mem(in_str, mem_ptr)
local(i, c, len)
(
  i = 0;
  len = strlen(in_str);
  while (i < len) (
    c = str_getchar(in_str, i, 'c');
    mem_ptr[] = c;
    mem_ptr += 1;
    i += 1;
  );
  mem_ptr[] = 0;
  mem_ptr + 1;
);

function find_char(in_str, ch)
local(i, c, ret)
(
  ret = -1;
  i = 0;
  while ((c = str_getchar(in_str, i, 'c')) && ret < 0) (
    c == ch ? ret = i;
    i += 1;
  );
  ret;
);

function split_at_index(in_str, split_pos, out_a, out_b)
local(i, c, a_i, b_i)
(
  a_i = 0;
  i = 0;
  while (i < split_pos) (
    c = str_getchar(in_str, i, 'c');
    c ? (str_setchar(out_a, a_i, c, 'c'); a_i += 1;);
    i += 1;
  );
  str_setchar(out_a, a_i, 0, 'c');

  b_i = 0;
  i = split_pos;
  while ((c = str_getchar(in_str, i, 'c'))) (
    str_setchar(out_b, b_i, c, 'c');
    b_i += 1;
    i += 1;
  );
  str_setchar(out_b, b_i, 0, 'c');
);

function pitch_to_name(pitch, out_str)
local(pc)
(
  pc = pitch % 12;
  pc == 0 ? sprintf(out_str, "C") :
  pc == 1 ? sprintf(out_str, "C#") :
  pc == 2 ? sprintf(out_str, "D") :
  pc == 3 ? sprintf(out_str, "D#") :
  pc == 4 ? sprintf(out_str, "E") :
  pc == 5 ? sprintf(out_str, "F") :
  pc == 6 ? sprintf(out_str, "F#") :
  pc == 7 ? sprintf(out_str, "G") :
  pc == 8 ? sprintf(out_str, "G#") :
  pc == 9 ? sprintf(out_str, "A") :
  pc == 10 ? sprintf(out_str, "A#") :
  sprintf(out_str, "B");
);

function prefer_flats_for_root(root_name)
local(prefer)
(
  prefer = 0;
  find_substr(root_name, "#") >= 0 ? prefer = 0;
  str_getchar(root_name, 0, 'c') == 'F' ? prefer = 1;
  prefer;
);

function pitch_to_name_pref(pitch, prefer_flats, out_str)
local(pc)
(
  pc = pitch % 12;
  prefer_flats ? (
    pc == 0 ? sprintf(out_str, "C") :
    pc == 1 ? sprintf(out_str, "Db") :
    pc == 2 ? sprintf(out_str, "D") :
    pc == 3 ? sprintf(out_str, "Eb") :
    pc == 4 ? sprintf(out_str, "E") :
    pc == 5 ? sprintf(out_str, "F") :
    pc == 6 ? sprintf(out_str, "Gb") :
    pc == 7 ? sprintf(out_str, "G") :
    pc == 8 ? sprintf(out_str, "Ab") :
    pc == 9 ? sprintf(out_str, "A") :
    pc == 10 ? sprintf(out_str, "Bb") :
    sprintf(out_str, "B")
  ) : pitch_to_name(pitch, out_str);
);

function chord_bass_name(root_name, root_pitch, bass_pitch, out_str)
local(pref)
(
  pref = prefer_flats_for_root(root_name);
  pitch_to_name_pref(bass_pitch, pref, out_str);
);

function make_chord_display(root_name, label_ptr, chord_root, min_note, note_count, out_str)
local(tmp_label, tmp_bass)
(
  tmp_label = #;
  tmp_bass = #;
  mem_to_str(label_ptr, tmp_label);
  (note_count > 1 && min_note != chord_root) ? (
    chord_bass_name(root_name, chord_root, min_note, tmp_bass);
    sprintf(out_str, "%s%s/%s", root_name, tmp_label, tmp_bass);
  ) : (
    sprintf(out_str, "%s%s", root_name, tmp_label);
  );
  out_str;
);
function intervals_to_str(mask, out_str)
local(first)
(
  sprintf(out_str, "[");
  first = 1;

  (mask & (1<<1)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "b2"););
  (mask & (1<<2)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "2"););
  (mask & (1<<3)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "b3"););
  (mask & (1<<4)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "3"););
  (mask & (1<<5)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "4"););
  (mask & (1<<6)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "#4"););
  (mask & (1<<7)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "5"););
  (mask & (1<<8)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "b6"););
  (mask & (1<<9)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "6"););
  (mask & (1<<10)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "b7"););
  (mask & (1<<11)) ? (first ? first = 0 : strcat(out_str, " "); strcat(out_str, "7"););

  strcat(out_str, "]");
);

function register_chord(key_str, label_str)
local(i, c, num, in_num, num_cnt, max_num, has_gt12, mask, diff, label_ptr)
(
  num = 0;
  in_num = 0;
  num_cnt = 0;
  max_num = 0;
  has_gt12 = 0;
  mask = 0;

  i = 0;
  while ((c = str_getchar(key_str, i, 'c'))) (
    (c >= '0' && c <= '9') ? (
      in_num = 1;
      num = num * 10 + (c - '0');
    ) : in_num ? (
      num_cnt += 1;
      num > max_num ? max_num = num;
      num > 12 ? has_gt12 = 1 : mask |= (1 << ((num - 1) % 12));
      num = 0;
      in_num = 0;
    );
    i += 1;
  );

  in_num ? (
    num_cnt += 1;
    num > max_num ? max_num = num;
    num > 12 ? has_gt12 = 1 : mask |= (1 << ((num - 1) % 12));
  );

  label_ptr = label_mem_pos;
  label_mem_pos = str_to_mem(label_str, label_mem_pos);

  !has_gt12 ? (
    mask_label[mask] = label_ptr;
  ) : (num_cnt == 2 && max_num > 12) ? (
    diff = max_num - 1;
    diff >= 0 && diff < 24 ? comp_label[diff] = label_ptr;
  );
);

function parse_chord_line(line_str)
local(prefix_pos, compact_pos, i, c, p, num, in_num, num_cnt, max_num, has_gt12, mask, label_quote, label_end, key_start, key_end)
(
  parsed_ok = 0;
  parsed_mask = -1;
  parsed_diff = -1;

  prefix_pos = find_substr(line_str, chord_prefix);
  prefix_pos >= 0 ? (
    key_start = prefix_pos + chord_prefix_len;
    i = 0;
    p = key_start;
    c = str_getchar(line_str, p, 'c');
    while (c && c != '\'' && i < 120) (
      str_setchar(chord_key_tmp, i, c, 'c');
      i += 1;
      p += 1;
      c = str_getchar(line_str, p, 'c');
    );
    str_setchar(chord_key_tmp, i, 0, 'c');

    compact_pos = find_substr(line_str, chord_compact);
    compact_pos >= 0 ? (
      p = compact_pos;
      c = str_getchar(line_str, p, 'c');
      while (c && c != '\'' && p < compact_pos + 120) (
        p += 1;
        c = str_getchar(line_str, p, 'c');
      );
      c == '\'' ? (
        label_quote = p + 1;
        i = 0;
        p = label_quote;
        c = str_getchar(line_str, p, 'c');
        while (c && c != '\'' && i < 120) (
          str_setchar(chord_label_tmp, i, c, 'c');
          i += 1;
          p += 1;
          c = str_getchar(line_str, p, 'c');
        );
        str_setchar(chord_label_tmp, i, 0, 'c');

        num = 0;
        in_num = 0;
        num_cnt = 0;
        max_num = 0;
        has_gt12 = 0;
        mask = 0;
        i = 0;
        c = str_getchar(chord_key_tmp, i, 'c');
        while (c) (
          (c >= '0' && c <= '9') ? (
            in_num = 1;
            num = num * 10 + (c - '0');
          ) : in_num ? (
            num_cnt += 1;
            num > max_num ? max_num = num;
            num > 12 ? has_gt12 = 1 : mask |= (1 << ((num - 1) % 12));
            num = 0;
            in_num = 0;
          );
          i += 1;
          c = str_getchar(chord_key_tmp, i, 'c');
        );
        in_num ? (
          num_cnt += 1;
          num > max_num ? max_num = num;
          num > 12 ? has_gt12 = 1 : mask |= (1 << ((num - 1) % 12));
        );

        !has_gt12 ? (
          parsed_mask = mask;
          parsed_ok = 1;
        ) : (num_cnt == 2 && max_num > 12) ? (
          parsed_diff = max_num - 1;
          parsed_ok = 1;
        );
      );
    );
  );

  parsed_ok;
);
gfx_ext_retina == 0 ? gfx_ext_retina = 1;
gfx_ext_flags |= 0x100 | 0x200;
gate_count = 0;
gate_vel_max = 0;

// Chordbox detection
chordbox_found = 0;
chord_db_loaded = 0;
display_hold_until = 0;

gate_note_vel = 0;
active_notes = 128;
mask_label = 256;
comp_label = mask_label + 4096;
label_mem = comp_label + 24;
label_mem_pos = label_mem;

memset(gate_note_vel, 0, 128);
memset(active_notes, 0, 128);
memset(mask_label, 0, 4096);
memset(comp_label, 0, 24);

chord_prefix = #chord_prefix;
chord_compact = #chord_compact;
chord_key_tmp = #chord_key_tmp;
chord_label_tmp = #chord_label_tmp;
sprintf(chord_prefix, "chord_names['");
sprintf(chord_compact, "expanded");
chord_prefix_len = strlen(chord_prefix);

label_mem_pos = label_mem;
memset(mask_label, 0, 4096);
memset(comp_label, 0, 24);

register_chord("1 2", " minor 2nd");
register_chord("1 3", " major 2nd");
register_chord("1 4", " minor 3rd");
register_chord("1 5", " major 3rd");
register_chord("1 6", " perfect 4th");
register_chord("1 7", " tritone");
register_chord("1 8", " perfect 5th");
register_chord("1 9", " minor 6th");
register_chord("1 10", " major 6th");
register_chord("1 11", " minor 7th");
register_chord("1 12", " major 7th");

register_chord("1 14", " minor 9th");
register_chord("1 15", " major 9th");
register_chord("1 16", " minor 10th");
register_chord("1 17", " major 10th");
register_chord("1 18", " perfect 11th");
register_chord("1 20", " perfect 12th");
register_chord("1 21", " minor 13th");
register_chord("1 22", " major 13th");
register_chord("1 23", " minor 14th");
register_chord("1 24", " major 14th");

register_chord("1 8", "5");

register_chord("1 5 8", "maj");
register_chord("1 4 8", "m");
register_chord("1 4 7", "dim");
register_chord("1 5 9", "aug");
register_chord("1 6 8", "sus4");
register_chord("1 3 8", "sus2");
register_chord("1 6 8 9", "sus4(b5)");
register_chord("1 3 8 9", "sus2(b5)");

register_chord("1 5 8 12", "maj7");
register_chord("1 5 8 11", "7");
register_chord("1 4 8 11", "m7");
register_chord("1 4 8 12", "mMaj7");
register_chord("1 4 7 11", "m7b5");
register_chord("1 4 7 10", "dim7");
register_chord("1 5 9 11", "aug7");
register_chord("1 5 9 12", "augMaj7");
register_chord("1 5 7 11", "7b5");
register_chord("1 5 9 11", "7#5");
register_chord("1 4 7 12", "dimMaj7");

register_chord("1 5 8 10", "6");
register_chord("1 4 8 10", "m6");
register_chord("1 5 8 10 12", "maj13(no9)");
register_chord("1 4 8 10 11", "m13(no9)");

register_chord("1 3 5 8", "add9");
register_chord("1 3 4 8", "madd9");
register_chord("1 5 6 8", "add11");
register_chord("1 4 6 8", "madd11");
register_chord("1 5 10 11", "7add13");
register_chord("1 5 10 12", "maj7add13");
register_chord("1 4 10 11", "m7add13");

register_chord("1 3 5 8 12", "maj9");
register_chord("1 3 5 8 11", "9");
register_chord("1 3 4 8 11", "m9");
register_chord("1 3 4 8 12", "mMaj9");

register_chord("1 6 8 11", "7sus4");
register_chord("1 6 11", "7sus4(no5)");
register_chord("1 3 6 11", "11");
register_chord("1 6 8 11", "11(no9)");
register_chord("1 3 6 8 11", "11");

register_chord("1 3 5 6 11", "11(no5)");
register_chord("1 5 6 8 11", "11(no9)");
register_chord("1 3 5 6 8 11", "11");

register_chord("1 3 5 6 12", "maj11(no5)");
register_chord("1 5 6 8 12", "maj11(no9)");
register_chord("1 3 5 6 8 12", "maj11");

register_chord("1 3 4 6 11", "m11(no5)");
register_chord("1 4 6 8 11", "m11(no9)");
register_chord("1 3 4 6 8 11", "m11");

register_chord("1 3 5 8 10", "6/9");
register_chord("1 3 4 8 10", "m6/9");

register_chord("1 3 5 8 10 11", "13");
register_chord("1 3 5 8 10 12", "maj13");
register_chord("1 3 4 8 10 11", "m13");
register_chord("1 3 4 8 10 12", "mMaj13");

register_chord("1 5 8 10 12", "maj13(no9)");
register_chord("1 5 8 10 11", "13(no9)");
register_chord("1 4 8 10 11", "m13(no9)");

register_chord("1 5 8 12", "maj7");
register_chord("1 8 12", "maj7(no3)");
register_chord("1 5 12", "maj7(no5)");
register_chord("1 5 11", "7(no5)");
register_chord("1 8 11", "7(no3)");
register_chord("1 4 11", "m7(no5)");

register_chord("1 2 5 8 11", "7b9");
register_chord("1 4 5 8 11", "7#9");
register_chord("1 2 5 7 8 11", "7b9#11");
register_chord("1 4 5 7 8 11", "7#9#11");
register_chord("1 2 5 11", "7b9(no5)");
register_chord("1 4 5 11", "7#9(no5)");

register_chord("1 5 7 8 11", "7#11");
register_chord("1 3 5 7 8 11", "9#11");

register_chord("1 2 5 8 10 11", "13b9");
register_chord("1 3 5 7 8 10 11", "13#11");
register_chord("1 3 5 7 10 11", "13(no5)");
register_chord("1 5 8 10 11", "13(no9)");

register_chord("1 2 4 8 11", "m7b9");
register_chord("1 2 4 7 11", "m7b5b9");
register_chord("1 2 4 11", "m7b9(no5)");
register_chord("1 3 4 7 11", "m9b5");
register_chord("1 3 4 6 7 11", "m11b5");
register_chord("1 3 5 7 10 11", "13b5");

register_chord("1 4 12", "mMaj7(no5)");
register_chord("1 4 8 12", "mMaj7");

register_chord("1 2 5 8 10 11", "13b9");
register_chord("1 3 5 7 8 10 11", "13#11");

register_chord("1 2 5 7 11", "7b9b5");
register_chord("1 2 5 9 11", "7b9#5");
register_chord("1 4 5 7 11", "7#9b5");
register_chord("1 4 5 9 11", "7#9#5");
register_chord("1 3 5 7 11", "9b5");
register_chord("1 3 5 9 11", "9#5");
register_chord("1 2 5 8 9 11", "7b9b13");

register_chord("1 5 7 12", "maj7b5");
register_chord("1 5 7 8 12", "maj7#11");
register_chord("1 3 5 7 8 12", "maj9#11");
register_chord("1 3 5 7 8 10 12", "maj13#11");

register_chord("1 4 7 8 11", "m7#11");
register_chord("1 3 4 7 8 11", "m9#11");
register_chord("1 3 4 6 7 8 11", "m11#11");
register_chord("1 3 4 7 8 10 11", "m13#11");

register_chord("1 2 6 8 11", "7sus4b9");
register_chord("1 4 6 8 11", "7sus4#9");
register_chord("1 3 6 8 11", "9sus4");
register_chord("1 3 6 8 10 11", "13sus4");

chordbox_found = 1;
chord_db_loaded = 1;

sprintf(#chord_display, "");
sprintf(#debug_line, "");
sprintf(#last_inv_name, "");
last_is_inv = 0;

@block
t = time_precise();
note_changed = 0;
while (midirecv(offset, msg1, msg2, msg3)) (
  status = msg1 & 0xF0;

  is_note = (status == 0x80 || status == 0x90 || status == 0xA0);
  note_out = msg2;
  is_note ? (
    note_out = msg2 + slider1;
    note_out < 0 ? note_out = 0;
    note_out > 127 ? note_out = 127;
  );

  (status == 0x90 && msg3 > 0) ? (
    active_notes[note_out] == 0 ? note_changed = 1;
    active_notes[note_out] += 1;

    gate_count += 1;
    gate_note_vel[note_out] < msg3 ? gate_note_vel[note_out] = msg3;
    msg3 > gate_vel_max ? gate_vel_max = msg3;
  ) : (status == 0x80 || (status == 0x90 && msg3 == 0)) ? (
    active_notes[note_out] > 0 ? (
      active_notes[note_out] -= 1;
      active_notes[note_out] == 0 ? note_changed = 1;
    );

    gate_count -= 1;
    gate_count < 0 ? gate_count = 0;
    active_notes[note_out] == 0 ? gate_note_vel[note_out] = 0;

    i = 0;
    gate_vel_max = 0;
    while (i < 128) (
      v = gate_note_vel[i];
      v > gate_vel_max ? gate_vel_max = v;
      i += 1;
    );
  );

  midisend(offset, msg1, note_out, msg3);
);

note_changed ? (
  note_count = 0;
  min_note = 128;
  max_note = 0;
  i = 0;
  while (i < 128) (
    active_notes[i] ? (
      note_count += 1;
      i < min_note ? min_note = i;
      i > max_note ? max_note = i;
    );
    i += 1;
  );

  note_count == 0 ? (
    display_hold_until = t + 2;
  ) : (
    rel_mask = 0;
    abs_mask = 0;
    i = 0;
    while (i < 128) (
      active_notes[i] ? (
        rel_mask |= (1 << ((i - min_note) % 12));
        abs_mask |= (1 << (i % 12));
      );
      i += 1;
    );

    label_ptr = mask_label[rel_mask];
    chord_root = min_note;
    inv_root = -1;

    label_ptr <= 0 ? (
      rot = 1;
      while (rot < 12 && label_ptr <= 0) (
        (rel_mask & (1 << rot)) ? (
          new_mask = 0;
          j = 0;
          while (j < 12) (
            (rel_mask & (1 << j)) ? new_mask |= (1 << ((j - rot + 12) % 12));
            j += 1;
          );
          label_ptr = mask_label[new_mask];
          label_ptr > 0 ? (chord_root = min_note + rot; inv_root = min_note;);
        );
        rot += 1;
      );
    );

    (label_ptr <= 0 && note_count == 2) ? (
      diff = max_note - min_note;
      (diff >= 12 && diff < 24) ? (
        comp_ptr = comp_label[diff];
        comp_ptr > 0 ? (label_ptr = comp_ptr; chord_root = min_note; inv_root = -1;);
      );
    );

    label_ptr > 0 ? (
      pitch_to_name(chord_root, #root_name);
      make_chord_display(#root_name, label_ptr, chord_root, min_note, note_count, #chord_display);
      (note_count > 1 && min_note != chord_root) ? (
        chord_bass_name(#root_name, chord_root, min_note, #inv_name);
        strcpy(#last_inv_name, #inv_name);
        last_is_inv = 1;
        sprintf(#debug_line, "INV root=%s rp=%d min=%d cnt=%d bass=%s disp=%s", #root_name, chord_root, min_note, note_count, #inv_name, #chord_display);
      ) : (
        sprintf(#debug_line, "NOINV root=%s rp=%d min=%d cnt=%d disp=%s", #root_name, chord_root, min_note, note_count, #chord_display);
        sprintf(#last_inv_name, "");
        last_is_inv = 0;
      );
    ) : (
      (note_count == 1) ? (
        pitch_to_name(min_note, #note_tmp);
        oct = min_note / 12;
        oct -= 1;
        sprintf(#chord_display, "%s%d", #note_tmp, oct);
      ) : (
        sprintf(#chord_display, "");
        n = 0;
        pc = 0;
        while (pc < 12) (
          (abs_mask & (1 << pc)) ? (
            pitch_to_name(pc, #note_tmp);
            n > 0 ? strcat(#chord_display, " ");
            strcat(#chord_display, #note_tmp);
            n += 1;
          );
          pc += 1;
        );
      );
    );
    display_hold_until = t + 2;
  );
);

@gfx 150 70

gfx_clear = 0x1a1a1a;

// Draw Transpose Amount (Line 1)
slider1 > 0 ? sprintf(#transpose_str, "+%d st", slider1) : sprintf(#transpose_str, "%d st", slider1);

embedded = gfx_ext_flags & 1;

pad_top = embedded ? 6 : 10;
pad_gap = embedded ? 6 : 10;
transpose_font_sz = embedded ? 24 : 24;
chord_base_font_sz = embedded ? 24 : 34;
chord_line2_gap = embedded ? 22 : 30;

gfx_setfont(1, "Arial", transpose_font_sz, 'b');
gfx_a = 1;

slider1 < 0 ? (
  gfx_r = 1.0; gfx_g = 0.55; gfx_b = 0.0; // Dark Orange
) : slider1 > 0 ? (
  gfx_r = 0.25; gfx_g = 0.88; gfx_b = 0.82; // Turquoise
) : (
  gfx_r = 1; gfx_g = 1; gfx_b = 1; // White for 0
);

gfx_measurestr(#transpose_str, str_w, str_h);
gfx_x = (gfx_w - str_w) / 2;
gfx_y = pad_top;
gfx_drawstr(#transpose_str);

// Draw Chord Monitor or Warning (Line 2)
gfx_x = 10;
gfx_y = pad_top + str_h + pad_gap;

!chordbox_found ? (
  gfx_r = 1; gfx_g = 0.2; gfx_b = 0.2; // Red warning
  gfx_setfont(2, "Arial", 22);
  gfx_drawstr("Please install 'Lil Chordbox'");
  gfx_x = 10; gfx_y += 26;
  gfx_drawstr("by FeedTheCat");
) : !chord_db_loaded ? (
  gfx_r = 1; gfx_g = 0.2; gfx_b = 0.2;
  gfx_setfont(2, "Arial", 22);
  gfx_drawstr("Chord DB not loaded");
) : (
  t = time_precise();
  (gate_count == 0 && t > display_hold_until) ? (
    #chord_display = "";
    #debug_line = "";
  );
  chord_full = #chord_display;
  chord_line_a = #chord_display;
  chord_line_b = #chord_line_b;
  sprintf(chord_line_b, "");

  chord_type = 0;

  idx = find_substr(chord_line_a, "dim");
  idx >= 0 ? chord_type = 3;

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "aug");
    idx >= 0 ? chord_type = 3;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "m7b5");
    idx >= 0 ? chord_type = 3;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "m9b5");
    idx >= 0 ? chord_type = 3;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "m11b5");
    idx >= 0 ? chord_type = 3;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "mMaj");
    idx >= 0 ? chord_type = 3;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "maj");
    idx >= 0 ? chord_type = 1;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "m");
    idx >= 0 ? chord_type = 2;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "7");
    idx >= 0 ? chord_type = 3;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "9");
    idx >= 0 ? chord_type = 3;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "11");
    idx >= 0 ? chord_type = 3;
  );

  chord_type == 0 ? (
    idx = find_substr(chord_line_a, "13");
    idx >= 0 ? chord_type = 3;
  );

  chord_type == 1 ? (
    gfx_r = 0.9; gfx_g = 0.5; gfx_b = 0.0;
  ) : chord_type == 2 ? (
    gfx_r = 0.2; gfx_g = 0.8; gfx_b = 0.9;
  ) : chord_type == 3 ? (
    gfx_r = 0.95; gfx_g = 0.25; gfx_b = 0.25;
  ) : (
    gfx_r = 0.8; gfx_g = 0.8; gfx_b = 0.8;
  );

  // First, check if we need to add bass for measurement
  slash_pos = find_char(chord_line_a, '/');
  will_add_bass = (slash_pos < 0 && strlen(chord_line_a) > 0 && last_is_inv);
  
  // Measure total width (chord + optional bass)
  font_sz = chord_base_font_sz;
  gfx_setfont(2, "Arial", font_sz);
  gfx_measurestr(chord_line_a, cw_chord, ch);
  will_add_bass ? (
    gfx_measurestr("/", cw_slash, ch);
    gfx_measurestr(#last_inv_name, cw_bass, ch);
    cw = cw_chord + cw_slash + cw_bass;
  ) : (
    cw = cw_chord;
  );
  
  // Adjust font size based on TOTAL width
  cw > gfx_w - 16 ? (
    font_sz = 30; gfx_setfont(2, "Arial", font_sz);
    gfx_measurestr(chord_line_a, cw_chord, ch);
    will_add_bass ? (gfx_measurestr("/", cw_slash, ch); gfx_measurestr(#last_inv_name, cw_bass, ch); cw = cw_chord + cw_slash + cw_bass;) : (cw = cw_chord;);
  );
  cw > gfx_w - 16 ? (
    font_sz = 26; gfx_setfont(2, "Arial", font_sz);
    gfx_measurestr(chord_line_a, cw_chord, ch);
    will_add_bass ? (gfx_measurestr("/", cw_slash, ch); gfx_measurestr(#last_inv_name, cw_bass, ch); cw = cw_chord + cw_slash + cw_bass;) : (cw = cw_chord;);
  );
  cw > gfx_w - 16 ? (
    font_sz = 22; gfx_setfont(2, "Arial", font_sz);
    gfx_measurestr(chord_line_a, cw_chord, ch);
    will_add_bass ? (gfx_measurestr("/", cw_slash, ch); gfx_measurestr(#last_inv_name, cw_bass, ch); cw = cw_chord + cw_slash + cw_bass;) : (cw = cw_chord;);
  );
  cw > gfx_w - 16 ? (
    font_sz = 20; gfx_setfont(2, "Arial", font_sz);
    gfx_measurestr(chord_line_a, cw_chord, ch);
    will_add_bass ? (gfx_measurestr("/", cw_slash, ch); gfx_measurestr(#last_inv_name, cw_bass, ch); cw = cw_chord + cw_slash + cw_bass;) : (cw = cw_chord;);
  );
  cw > gfx_w - 16 ? (
    font_sz = 18; gfx_setfont(2, "Arial", font_sz);
    gfx_measurestr(chord_line_a, cw_chord, ch);
    will_add_bass ? (gfx_measurestr("/", cw_slash, ch); gfx_measurestr(#last_inv_name, cw_bass, ch); cw = cw_chord + cw_slash + cw_bass;) : (cw = cw_chord;);
  );
  cw > gfx_w - 16 ? (
    font_sz = 16; gfx_setfont(2, "Arial", font_sz);
    gfx_measurestr(chord_line_a, cw_chord, ch);
    will_add_bass ? (gfx_measurestr("/", cw_slash, ch); gfx_measurestr(#last_inv_name, cw_bass, ch); cw = cw_chord + cw_slash + cw_bass;) : (cw = cw_chord;);
  );
  cw > gfx_w - 16 ? (
    font_sz = 14; gfx_setfont(2, "Arial", font_sz);
    gfx_measurestr(chord_line_a, cw_chord, ch);
    will_add_bass ? (gfx_measurestr("/", cw_slash, ch); gfx_measurestr(#last_inv_name, cw_bass, ch); cw = cw_chord + cw_slash + cw_bass;) : (cw = cw_chord;);
  );

  // Center based on TOTAL width
  gfx_x = (gfx_w - cw) / 2;
  
  // Draw exactly as before (multiple calls)
  gfx_drawstr(chord_line_a);
  will_add_bass ? (
    gfx_drawstr("/");
    gfx_drawstr(#last_inv_name);
  );

  // Debug line (optional - uncomment if needed)
  // gfx_setfont(2, "Arial", 12);
  // gfx_r = 0.7; gfx_g = 0.7; gfx_b = 0.7;
  // gfx_x = 10;
  // gfx_y = pad_top + str_h + pad_gap + chord_line2_gap;
  // gfx_drawstr(#debug_line);


);

// Indicator Square
sq_w = embedded ? 12 : 16; sq_h = sq_w;
sq_x = (gfx_w - str_w) / 2 - 12 - sq_w; // Relative to top text
sq_y = pad_top + (str_h - sq_h) / 2;

(gate_count > 0) ? (
  t = gate_vel_max / 127;
  t < 0 ? t = 0;
  t > 1 ? t = 1;
  gfx_a = 0.2 + 0.8 * t;
  gfx_r = 1; gfx_g = 1; gfx_b = 0;
  gfx_rect(sq_x, sq_y, sq_w, sq_h);
);]]

JSFX.MIDI_TRANSPOSE_UTILITY_PRESET_INI = [[[General]
NbPresets=1

[Preset0]
Data=30202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D20225472616E73706F757365205574696C69747920666F72204974656D2050726F706572746965732232
Len=168
Name=Transpouse Utility for Item Properties
]]

JSFX.LOW_CUT_24DB_JSFX = [[desc:Mr. Frenkie/Low Cut 24 dB/oct
options:no_meter
in_pin:Left
in_pin:Right
out_pin:Left
out_pin:Right

slider1:20<20,20000,1:log>Cutoff (Hz)
slider2:1<0,1,1>Slope

@init
gfx_ext_retina == 0 ? gfx_ext_retina = 1;
gfx_ext_flags |= 0x100 | 0x200;
q1_24 = 0.54119610;
q2_24 = 1.30656296;
q_12 = 0.70710678;
prev_sr = srate;
function clamp_freq(f)
(
  f = f < 20 ? 20 : f;
  fmax = srate*0.499;
  f = f > fmax ? fmax : f;
);
function hp_coeffs_1(f, q)
local(w0, cw, sw, alpha, a0)
(
  f = clamp_freq(f);
  w0 = 2*$pi*f/srate;
  cw = cos(w0);
  sw = sin(w0);
  alpha = sw/(2*q);
  a0 = 1 + alpha;
  b0_1 = (1 + cw)/2/a0;
  b1_1 = -(1 + cw)/a0;
  b2_1 = (1 + cw)/2/a0;
  a1_1 = -2*cw/a0;
  a2_1 = (1 - alpha)/a0;
);
function hp_coeffs_2(f)
local(w0, cw, sw, alpha, a0)
(
  f = clamp_freq(f);
  w0 = 2*$pi*f/srate;
  cw = cos(w0);
  sw = sin(w0);
  alpha = sw/(2*q2_24);
  a0 = 1 + alpha;
  b0_2 = (1 + cw)/2/a0;
  b1_2 = -(1 + cw)/a0;
  b2_2 = (1 + cw)/2/a0;
  a1_2 = -2*cw/a0;
  a2_2 = (1 - alpha)/a0;
);
function hp_update(f)
(
  slider2 >= 0.5 ? (
    hp_coeffs_1(f, q1_24);
    hp_coeffs_2(f);
  ) : (
    hp_coeffs_1(f, q_12);
  );
);
// slider1 is Hz directly
freq_cut = clamp_freq(slider1);
hp_update(freq_cut);
x1L1 = 0; x2L1 = 0; y1L1 = 0; y2L1 = 0;
x1L2 = 0; x2L2 = 0; y1L2 = 0; y2L2 = 0;
x1R1 = 0; x2R1 = 0; y1R1 = 0; y2R1 = 0;
x1R2 = 0; x2R2 = 0; y1R2 = 0; y2R2 = 0;
drag_active = 0;
drag_prev_x = 0;
gfx_setfont(1, "Arial", 24);

@slider
// slider1 is Hz directly
freq_cut = clamp_freq(slider1);
hp_update(freq_cut);

@block
prev_sr != srate ? (
  prev_sr = srate;
  freq_cut = clamp_freq(slider1);
  hp_update(freq_cut);
);

@sample
inL = spl0;
inR = spl1;
slider1 <= 20 ? (
  spl0 = inL;
  spl1 = inR;
  x1L1 = 0; x2L1 = 0; y1L1 = 0; y2L1 = 0;
  x1L2 = 0; x2L2 = 0; y1L2 = 0; y2L2 = 0;
  x1R1 = 0; x2R1 = 0; y1R1 = 0; y2R1 = 0;
  x1R2 = 0; x2R2 = 0; y1R2 = 0; y2R2 = 0;
) : (
  o1L = b0_1*inL + b1_1*x1L1 + b2_1*x2L1 - a1_1*y1L1 - a2_1*y2L1;
  x2L1 = x1L1;
  x1L1 = inL;
  y2L1 = y1L1;
  y1L1 = o1L;
  slider2 >= 0.5 ? (
    o2L = b0_2*o1L + b1_2*x1L2 + b2_2*x2L2 - a1_2*y1L2 - a2_2*y2L2;
    x2L2 = x1L2;
    x1L2 = o1L;
    y2L2 = y1L2;
    y1L2 = o2L;
  );
  spl0 = slider2 >= 0.5 ? o2L : o1L;

  o1R = b0_1*inR + b1_1*x1R1 + b2_1*x2R1 - a1_1*y1R1 - a2_1*y2R1;
  x2R1 = x1R1;
  x1R1 = inR;
  y2R1 = y1R1;
  y1R1 = o1R;
  slider2 >= 0.5 ? (
    o2R = b0_2*o1R + b1_2*x1R2 + b2_2*x2R2 - a1_2*y1R2 - a2_2*y2R2;
    x2R2 = x1R2;
    x1R2 = o1R;
    y2R2 = y1R2;
    y1R2 = o2R;
  );
  spl1 = slider2 >= 0.5 ? o2R : o1R;
);

@gfx 150 40
embedded = gfx_ext_flags & 1;
gfx_clear = 0x1a1a1a;
gfx_setfont(1, "Arial", 24);
// slider1 is Hz directly
cur_f = clamp_freq(slider1);
slope_24 = slider2 >= 0.5;
embedded ? (
  sprintf(#hp_str, "HP");
  slope_24 ? sprintf(#order_str, "4") : sprintf(#order_str, "2");
  sprintf(#colon_str, ": ");
  cur_f >= 1000 ? (
    sprintf(#freq_str, "%.1f kHz", cur_f/1000);
  ) : (
    sprintf(#freq_str, "%d Hz", cur_f);
  );
) : (
  sprintf(#prefix_str, "Low Cut: ");
  cur_f >= 1000 ? (
    slope_24 ? sprintf(#freq_str, "%.1f kHz 24dB", cur_f/1000) : sprintf(#freq_str, "%.1f kHz 12dB", cur_f/1000);
  ) : (
    slope_24 ? sprintf(#freq_str, "%d Hz 24dB", cur_f) : sprintf(#freq_str, "%d Hz 12dB", cur_f);
  );
);
pad_left = 8;
pad_gap = 0;
embedded ? (
  gfx_measurestr(#hp_str, hp_w, str_h);
  gfx_measurestr(#order_str, order_w, str_h);
  gfx_measurestr(#colon_str, colon_w, str_h);
  gfx_measurestr(#freq_str, freq_w, str_h);
  freq_zone_left = pad_left + hp_w + order_w + colon_w + pad_gap;
) : (
  gfx_measurestr(#prefix_str, prefix_w, str_h);
  gfx_measurestr(#freq_str, freq_w, str_h);
  freq_zone_left = pad_left + prefix_w + pad_gap;
);
gfx_y = (gfx_h - str_h) * 0.5;
gfx_x = pad_left;
embedded ? (
  gfx_r = 1; gfx_g = 1; gfx_b = 1; gfx_a = 1;
  gfx_drawstr(#hp_str);
  gfx_x = pad_left + hp_w;
  gfx_r = 0.88; gfx_g = 0.88; gfx_b = 0.88; gfx_a = 1;
  gfx_drawstr(#order_str);
  gfx_x = pad_left + hp_w + order_w;
  gfx_r = 1; gfx_g = 1; gfx_b = 1; gfx_a = 1;
  gfx_drawstr(#colon_str);
) : (
  gfx_r = 1; gfx_g = 1; gfx_b = 1; gfx_a = 1;
  gfx_drawstr(#prefix_str);
);
freq_zone_width = gfx_w - freq_zone_left;
// Convert Hz to norm for color: norm = log(Hz/20) / log(1000)
freq_norm = log(cur_f / 20) / log(1000);
hue = freq_norm * 0.78;
hsl_L = 0.75;
hsl_S = 1;
hsl_q = hsl_L < 0.5 ? hsl_L * (1 + hsl_S) : hsl_L + hsl_S - hsl_L * hsl_S;
hsl_p = 2 * hsl_L - hsl_q;
function hue2rgb(p, q, t)
(
  t = t < 0 ? t + 1 : t;
  t = t > 1 ? t - 1 : t;
  t < 0.166667 ? (p + (q - p) * 6 * t) : (
  t < 0.5 ? q : (
  t < 0.666667 ? (p + (q - p) * (0.666667 - t) * 6) : p));
);
gfx_r = hue2rgb(hsl_p, hsl_q, hue + 0.333333);
gfx_g = hue2rgb(hsl_p, hsl_q, hue);
gfx_b = hue2rgb(hsl_p, hsl_q, hue - 0.333333);
gfx_a = 1;
gfx_x = freq_zone_left;
gfx_drawstr(#freq_str);
!embedded ? (
  mouse_wheel != 0 ? (
    // slider1 is Hz with native log, convert to norm for smooth control
    norm = log(slider1 / 20) / log(1000);
    norm = norm + mouse_wheel * 0.0008;
    norm = norm < 0 ? 0 : norm;
    norm = norm > 1 ? 1 : norm;
    slider1 = 20 * (1000 ^ norm);
    slider_automate(slider1);
    mouse_wheel = 0;
  );
  (gfx_mouse_cap & 1) ? (
    drag_active == 0 ? (
      drag_active = 1;
      drag_prev_x = gfx_mouse_x;
    );
    dx = gfx_mouse_x - drag_prev_x;
    drag_prev_x = gfx_mouse_x;
    // slider1 is Hz with native log, convert to norm for smooth control
    norm = log(slider1 / 20) / log(1000);
    norm = norm + dx / (gfx_w > 0 ? gfx_w : 150);
    norm = norm < 0 ? 0 : norm;
    norm = norm > 1 ? 1 : norm;
    slider1 = 20 * (1000 ^ norm);
    slider_automate(slider1);
  ) : (
    drag_active = 0;
  );
);
]]

JSFX.HIGH_CUT_24DB_JSFX = [[desc:Mr. Frenkie/High Cut 24 dB/oct
options:no_meter
in_pin:Left
in_pin:Right
out_pin:Left
out_pin:Right

slider1:20000<20,20000,1:log>Cutoff (Hz)
slider2:1<0,1,1>Slope

@init
gfx_ext_retina == 0 ? gfx_ext_retina = 1;
gfx_ext_flags |= 0x100 | 0x200;
q1_24 = 0.54119610;
q2_24 = 1.30656296;
q_12 = 0.70710678;
prev_sr = srate;
function clamp_freq(f)
(
  f = f < 20 ? 20 : f;
  fmax = srate*0.499;
  f = f > fmax ? fmax : f;
);
function lp_coeffs_1(f, q)
local(w0, cw, sw, alpha, a0)
(
  f = clamp_freq(f);
  w0 = 2*$pi*f/srate;
  cw = cos(w0);
  sw = sin(w0);
  alpha = sw/(2*q);
  a0 = 1 + alpha;
  b0_1 = (1 - cw)/2/a0;
  b1_1 = (1 - cw)/a0;
  b2_1 = (1 - cw)/2/a0;
  a1_1 = -2*cw/a0;
  a2_1 = (1 - alpha)/a0;
);
function lp_coeffs_2(f)
local(w0, cw, sw, alpha, a0)
(
  f = clamp_freq(f);
  w0 = 2*$pi*f/srate;
  cw = cos(w0);
  sw = sin(w0);
  alpha = sw/(2*q2_24);
  a0 = 1 + alpha;
  b0_2 = (1 - cw)/2/a0;
  b1_2 = (1 - cw)/a0;
  b2_2 = (1 - cw)/2/a0;
  a1_2 = -2*cw/a0;
  a2_2 = (1 - alpha)/a0;
);
function lp_update(f)
(
  slider2 >= 0.5 ? (
    lp_coeffs_1(f, q1_24);
    lp_coeffs_2(f);
  ) : (
    lp_coeffs_1(f, q_12);
  );
);
// slider1 is norm (0-1), convert to Hz using standard DSP log
freq_cut = clamp_freq(slider1);
lp_update(freq_cut);
x1L1 = 0; x2L1 = 0; y1L1 = 0; y2L1 = 0;
x1L2 = 0; x2L2 = 0; y1L2 = 0; y2L2 = 0;
x1R1 = 0; x2R1 = 0; y1R1 = 0; y2R1 = 0;
x1R2 = 0; x2R2 = 0; y1R2 = 0; y2R2 = 0;
drag_active = 0;
drag_prev_x = 0;
gfx_setfont(1, "Arial", 24);

@slider
freq_cut = clamp_freq(slider1);
lp_update(freq_cut);

@block
prev_sr != srate ? (
  prev_sr = srate;
  freq_cut = clamp_freq(slider1);
  lp_update(freq_cut);
);

@sample
inL = spl0;
inR = spl1;
slider1 >= 20000 ? (
  spl0 = inL;
  spl1 = inR;
  x1L1 = 0; x2L1 = 0; y1L1 = 0; y2L1 = 0;
  x1L2 = 0; x2L2 = 0; y1L2 = 0; y2L2 = 0;
  x1R1 = 0; x2R1 = 0; y1R1 = 0; y2R1 = 0;
  x1R2 = 0; x2R2 = 0; y1R2 = 0; y2R2 = 0;
) : (
  o1L = b0_1*inL + b1_1*x1L1 + b2_1*x2L1 - a1_1*y1L1 - a2_1*y2L1;
  x2L1 = x1L1;
  x1L1 = inL;
  y2L1 = y1L1;
  y1L1 = o1L;
  slider2 >= 0.5 ? (
    o2L = b0_2*o1L + b1_2*x1L2 + b2_2*x2L2 - a1_2*y1L2 - a2_2*y2L2;
    x2L2 = x1L2;
    x1L2 = o1L;
    y2L2 = y1L2;
    y1L2 = o2L;
  );
  spl0 = slider2 >= 0.5 ? o2L : o1L;

  o1R = b0_1*inR + b1_1*x1R1 + b2_1*x2R1 - a1_1*y1R1 - a2_1*y2R1;
  x2R1 = x1R1;
  x1R1 = inR;
  y2R1 = y1R1;
  y1R1 = o1R;
  slider2 >= 0.5 ? (
    o2R = b0_2*o1R + b1_2*x1R2 + b2_2*x2R2 - a1_2*y1R2 - a2_2*y2R2;
    x2R2 = x1R2;
    x1R2 = o1R;
    y2R2 = y1R2;
    y1R2 = o2R;
  );
  spl1 = slider2 >= 0.5 ? o2R : o1R;
);

@gfx 150 40
embedded = gfx_ext_flags & 1;
gfx_clear = 0x1a1a1a;
gfx_setfont(1, "Arial", 24);
cur_f = clamp_freq(slider1);
slope_24 = slider2 >= 0.5;
embedded ? (
  sprintf(#lp_str, "LP");
  slope_24 ? sprintf(#order_str, "4") : sprintf(#order_str, "2");
  sprintf(#colon_str, ": ");
  cur_f >= 1000 ? (
    sprintf(#freq_str, "%.1f kHz", cur_f/1000);
  ) : (
    sprintf(#freq_str, "%d Hz", cur_f);
  );
) : (
  sprintf(#prefix_str, "High Cut: ");
  cur_f >= 1000 ? (
    slope_24 ? sprintf(#freq_str, "%.1f kHz 24dB", cur_f/1000) : sprintf(#freq_str, "%.1f kHz 12dB", cur_f/1000);
  ) : (
    slope_24 ? sprintf(#freq_str, "%d Hz 24dB", cur_f) : sprintf(#freq_str, "%d Hz 12dB", cur_f);
  );
);
pad_left = 8;
pad_gap = 0;
embedded ? (
  gfx_measurestr(#lp_str, lp_w, str_h);
  gfx_measurestr(#order_str, order_w, str_h);
  gfx_measurestr(#colon_str, colon_w, str_h);
  gfx_measurestr(#freq_str, freq_w, str_h);
  freq_zone_left = pad_left + lp_w + order_w + colon_w + pad_gap;
) : (
  gfx_measurestr(#prefix_str, prefix_w, str_h);
  gfx_measurestr(#freq_str, freq_w, str_h);
  freq_zone_left = pad_left + prefix_w + pad_gap;
);
gfx_y = (gfx_h - str_h) * 0.5;
gfx_x = pad_left;
embedded ? (
  gfx_r = 1; gfx_g = 1; gfx_b = 1; gfx_a = 1;
  gfx_drawstr(#lp_str);
  gfx_x = pad_left + lp_w;
  gfx_r = 0.88; gfx_g = 0.88; gfx_b = 0.88; gfx_a = 1;
  gfx_drawstr(#order_str);
  gfx_x = pad_left + lp_w + order_w;
  gfx_r = 1; gfx_g = 1; gfx_b = 1; gfx_a = 1;
  gfx_drawstr(#colon_str);
) : (
  gfx_r = 1; gfx_g = 1; gfx_b = 1; gfx_a = 1;
  gfx_drawstr(#prefix_str);
);
freq_zone_width = gfx_w - freq_zone_left;
freq_norm = log(cur_f / 20) / log(1000);
hue = freq_norm * 0.78;
hsl_L = 0.75;
hsl_S = 1;
hsl_q = hsl_L < 0.5 ? hsl_L * (1 + hsl_S) : hsl_L + hsl_S - hsl_L * hsl_S;
hsl_p = 2 * hsl_L - hsl_q;
function hue2rgb(p, q, t)
(
  t = t < 0 ? t + 1 : t;
  t = t > 1 ? t - 1 : t;
  t < 0.166667 ? (p + (q - p) * 6 * t) : (
  t < 0.5 ? q : (
  t < 0.666667 ? (p + (q - p) * (0.666667 - t) * 6) : p));
);
gfx_r = hue2rgb(hsl_p, hsl_q, hue + 0.333333);
gfx_g = hue2rgb(hsl_p, hsl_q, hue);
gfx_b = hue2rgb(hsl_p, hsl_q, hue - 0.333333);
gfx_a = 1;
gfx_x = freq_zone_left;
gfx_drawstr(#freq_str);
!embedded ? (
  mouse_wheel != 0 ? (
    norm = log(slider1 / 20) / log(1000);
    norm = norm + mouse_wheel * 0.0008;
    norm = norm < 0 ? 0 : norm;
    norm = norm > 1 ? 1 : norm;
    slider1 = 20 * (1000 ^ norm);
    slider_automate(slider1);
    mouse_wheel = 0;
  );
  (gfx_mouse_cap & 1) ? (
    drag_active == 0 ? (
      drag_active = 1;
      drag_prev_x = gfx_mouse_x;
    );
    dx = gfx_mouse_x - drag_prev_x;
    drag_prev_x = gfx_mouse_x;
    norm = log(slider1 / 20) / log(1000);
    norm = norm + dx / (gfx_w > 0 ? gfx_w : 150);
    norm = norm < 0 ? 0 : norm;
    norm = norm > 1 ? 1 : norm;
    slider1 = 20 * (1000 ^ norm);
    slider_automate(slider1);
  ) : (
    drag_active = 0;
  );
);
]]

JSFX.PRESET_LOW_CUT_24_EMBEDDED = [[[General]
NbPresets=1

[Preset0]
Data=32302031202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202244656661756C74204850223A
Len=141
Name=Default HP

]]

JSFX.PRESET_HIGH_CUT_24_EMBEDDED = [[[General]
NbPresets=2

[Preset0]
Data=32303030302030202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202244656661756C7420554922CF
Len=144
Name=Default UI

[Preset1]
Data=32303030302030202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202244656661756C74204C5022CD
Len=144
Name=Default LP

]]

return JSFX
