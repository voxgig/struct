-- Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
--
-- Voxgig Struct — RE2-subset regex engine, pure Lua (no external deps).
--
-- Lua's built-in string.match uses Lua patterns, which are intentionally
-- not regex (different metacharacters, no alternation, no {n,m}). This
-- module provides a real regex engine implementing the RE2 subset
-- documented in /REGEX.md so every port can share the same dialect.
--
-- Approach: Thompson-NFA matcher (same as c/src/regex.c). Patterns are
-- compiled to a sequence of opcodes; the matcher advances two state sets
-- per input char. Quantifier bounds {n,m} are unrolled at compile time.

local M = {}

-- Opcodes
local OP_CHAR  = 1
local OP_ANY   = 2
local OP_CLASS = 3
local OP_MATCH = 4
local OP_JMP   = 5
local OP_SPLIT = 6
local OP_SAVE  = 7
local OP_BOL   = 8
local OP_EOL   = 9
local OP_WB    = 10
local OP_NWB   = 11

-- ---------------------------------------------------------------------
-- Character class helpers
-- ---------------------------------------------------------------------

local function cc_new()
  local t = {}
  for i = 0, 255 do t[i] = false end
  return t
end

local function cc_set(cc, c) cc[c & 0xFF] = true end

local function cc_range(cc, lo, hi)
  if lo > hi then lo, hi = hi, lo end
  for c = lo, hi do cc[c] = true end
end

local function cc_negate(cc)
  for i = 0, 255 do cc[i] = not cc[i] end
end

local function cc_predef(cc, ch)
  if ch == 'd' then
    cc_range(cc, 0x30, 0x39)
  elseif ch == 'D' then
    for i = 0, 255 do cc[i] = true end
    cc_range(cc, 0x30, 0x39); for i = 0x30, 0x39 do cc[i] = false end
  elseif ch == 's' then
    cc[0x20] = true; cc[0x09] = true; cc[0x0A] = true
    cc[0x0D] = true; cc[0x0C] = true; cc[0x0B] = true
  elseif ch == 'S' then
    for i = 0, 255 do cc[i] = true end
    cc[0x20] = false; cc[0x09] = false; cc[0x0A] = false
    cc[0x0D] = false; cc[0x0C] = false; cc[0x0B] = false
  elseif ch == 'w' then
    cc_range(cc, 0x30, 0x39); cc_range(cc, 0x41, 0x5A); cc_range(cc, 0x61, 0x7A); cc[0x5F] = true
  elseif ch == 'W' then
    for i = 0, 255 do cc[i] = true end
    cc_range(cc, 0x30, 0x39); for i = 0x30, 0x39 do cc[i] = false end
    cc_range(cc, 0x41, 0x5A); for i = 0x41, 0x5A do cc[i] = false end
    cc_range(cc, 0x61, 0x7A); for i = 0x61, 0x7A do cc[i] = false end
    cc[0x5F] = false
  end
end

-- ---------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------

local function parse_error(p, msg)
  error("regex parse error at pos " .. p.pos .. ": " .. msg, 3)
end

local ESC_CHAR_MAP = {
  n = 10, t = 9, r = 13, f = 12, v = 11, a = 7, e = 27, ['0'] = 0,
}

local function parse_escape(p)
  if p.pos > #p.src then parse_error(p, "trailing backslash") end
  local c = p.src:sub(p.pos, p.pos)
  p.pos = p.pos + 1
  if ESC_CHAR_MAP[c] then return ESC_CHAR_MAP[c], nil end
  if c == 'x' then
    if p.pos + 1 > #p.src then parse_error(p, "bad \\xNN") end
    local h = p.src:sub(p.pos, p.pos + 1)
    p.pos = p.pos + 2
    local n = tonumber(h, 16)
    if not n then parse_error(p, "bad \\xNN") end
    return n, nil
  end
  if c == 'd' or c == 'D' or c == 's' or c == 'S' or c == 'w' or c == 'W' then
    return nil, c -- predefined class
  end
  if c == 'b' or c == 'B' then
    return nil, c -- word boundary marker
  end
  return c:byte(1), nil
end

local function parse_class(p)
  local cc = cc_new()
  local neg = false
  if p.pos <= #p.src and p.src:sub(p.pos, p.pos) == '^' then
    neg = true; p.pos = p.pos + 1
  end
  local first = true
  while p.pos <= #p.src and (first or p.src:sub(p.pos, p.pos) ~= ']') do
    first = false
    local cval
    if p.src:sub(p.pos, p.pos) == '\\' then
      p.pos = p.pos + 1
      local b, pre = parse_escape(p)
      if pre then
        if pre == 'b' or pre == 'B' then
          cval = 8 -- literal backspace inside class
        else
          local sub = cc_new(); cc_predef(sub, pre)
          for i = 0, 255 do if sub[i] then cc[i] = true end end
          goto continue
        end
      else
        cval = b
      end
    else
      cval = p.src:byte(p.pos); p.pos = p.pos + 1
    end
    -- range?
    if p.pos + 1 <= #p.src and p.src:sub(p.pos, p.pos) == '-' and p.src:sub(p.pos + 1, p.pos + 1) ~= ']' then
      p.pos = p.pos + 1
      local hi
      if p.src:sub(p.pos, p.pos) == '\\' then
        p.pos = p.pos + 1
        local b = parse_escape(p)
        hi = b or 45
      else
        hi = p.src:byte(p.pos); p.pos = p.pos + 1
      end
      cc_range(cc, cval, hi)
    else
      cc[cval] = true
    end
    ::continue::
  end
  if p.pos > #p.src or p.src:sub(p.pos, p.pos) ~= ']' then parse_error(p, "unclosed [") end
  p.pos = p.pos + 1
  if neg then cc_negate(cc) end
  return cc
end

-- Forward decls
local parse_alt

local function emit(p, op, data)
  p.code[#p.code + 1] = { op = op, data = data or {} }
  return #p.code
end

local function clone_range(p, from, to)
  local delta = #p.code - from + 1
  local start_ix = #p.code + 1
  for i = from, to - 1 do
    local insn = { op = p.code[i].op }
    local d = p.code[i].data
    insn.data = {}
    for k, v in pairs(d) do insn.data[k] = v end
    -- Patch jump targets that pointed within [from..to)
    if insn.op == OP_JMP and d.jmp >= from and d.jmp < to then
      insn.data.jmp = d.jmp + delta
    elseif insn.op == OP_SPLIT then
      if d.x >= from and d.x < to then insn.data.x = d.x + delta end
      if d.y >= from and d.y < to then insn.data.y = d.y + delta end
    end
    p.code[#p.code + 1] = insn
  end
  return start_ix
end

local function shift_one(p, at)
  -- Insert a placeholder at index `at` by shifting everything after it.
  local last = #p.code
  p.code[last + 1] = p.code[last]
  for i = last, at + 1, -1 do
    p.code[i] = p.code[i - 1]
  end
  p.code[at] = { op = OP_JMP, data = {} } -- placeholder
  -- Patch jumps/splits inside the moved region.
  for i = at + 1, #p.code do
    local insn = p.code[i]
    if insn.op == OP_JMP and insn.data.jmp >= at then
      insn.data.jmp = insn.data.jmp + 1
    elseif insn.op == OP_SPLIT then
      if insn.data.x >= at then insn.data.x = insn.data.x + 1 end
      if insn.data.y >= at then insn.data.y = insn.data.y + 1 end
    end
  end
end

local function parse_atom(p)
  local start = #p.code + 1
  if p.pos > #p.src then return start end
  local c = p.src:sub(p.pos, p.pos)
  if c == '(' then
    p.pos = p.pos + 1
    local capture = true
    local group = 0
    if p.pos + 1 <= #p.src and p.src:sub(p.pos, p.pos + 1) == '?:' then
      capture = false; p.pos = p.pos + 2
    elseif p.pos + 2 <= #p.src and p.src:sub(p.pos, p.pos + 2) == '?P<' then
      p.pos = p.pos + 3
      while p.pos <= #p.src and p.src:sub(p.pos, p.pos) ~= '>' do p.pos = p.pos + 1 end
      if p.pos <= #p.src then p.pos = p.pos + 1 end
    end
    if capture then
      group = p.next_group; p.next_group = p.next_group + 1
      emit(p, OP_SAVE, { slot = group * 2 })
    end
    parse_alt(p)
    if p.pos > #p.src or p.src:sub(p.pos, p.pos) ~= ')' then parse_error(p, "unclosed (") end
    p.pos = p.pos + 1
    if capture then
      emit(p, OP_SAVE, { slot = group * 2 + 1 })
    end
  elseif c == '[' then
    p.pos = p.pos + 1
    emit(p, OP_CLASS, { cc = parse_class(p) })
  elseif c == '.' then
    p.pos = p.pos + 1; emit(p, OP_ANY)
  elseif c == '^' then
    p.pos = p.pos + 1; emit(p, OP_BOL)
  elseif c == '$' then
    p.pos = p.pos + 1; emit(p, OP_EOL)
  elseif c == '\\' then
    p.pos = p.pos + 1
    local b, pre = parse_escape(p)
    if pre == 'b' then emit(p, OP_WB)
    elseif pre == 'B' then emit(p, OP_NWB)
    elseif pre then
      local cc = cc_new(); cc_predef(cc, pre); emit(p, OP_CLASS, { cc = cc })
    else
      emit(p, OP_CHAR, { c = b })
    end
  elseif c == ')' or c == '|' then
    return start
  else
    p.pos = p.pos + 1
    emit(p, OP_CHAR, { c = c:byte(1) })
  end
  return start
end

local function apply_quant(p, atom_start, q, n_lo, n_hi, lazy)
  local atom_end = #p.code + 1
  local alen = atom_end - atom_start
  if alen <= 0 then return end
  if q == '?' then
    shift_one(p, atom_start)
    local exit_ix = #p.code + 1
    p.code[atom_start] = { op = OP_SPLIT, data = {
      x = lazy and exit_ix or (atom_start + 1),
      y = lazy and (atom_start + 1) or exit_ix,
    } }
  elseif q == '*' then
    shift_one(p, atom_start)
    emit(p, OP_JMP, { jmp = atom_start })
    local exit_ix = #p.code + 1
    p.code[atom_start] = { op = OP_SPLIT, data = {
      x = lazy and exit_ix or (atom_start + 1),
      y = lazy and (atom_start + 1) or exit_ix,
    } }
  elseif q == '+' then
    -- After the atom, emit SPLIT pointing back to atom or forward to exit.
    -- The "forward" target is the slot AFTER this SPLIT, i.e. #p.code + 2
    -- at the time we compute it (one past the SPLIT we're about to add).
    local sp_ix = emit(p, OP_SPLIT, {})
    local exit_ix = sp_ix + 1
    p.code[sp_ix].data = {
      x = lazy and exit_ix or atom_start,
      y = lazy and atom_start or exit_ix,
    }
  elseif q == '{' then
    -- Mandatory n_lo copies (we have 1 already; clone n_lo-1 more)
    for _ = 2, n_lo do
      clone_range(p, atom_start, atom_end)
    end
    if n_hi == -1 then
      -- After mandatory, emit Kleene star of the atom
      local split_ix = emit(p, OP_SPLIT, {})
      local clone_start = clone_range(p, atom_start, atom_end)
      local jmp_ix = emit(p, OP_JMP, { jmp = split_ix })
      local exit_ix = #p.code + 1
      p.code[split_ix].data = {
        x = lazy and exit_ix or clone_start,
        y = lazy and clone_start or exit_ix,
      }
    elseif n_hi > n_lo then
      for _ = 1, n_hi - n_lo do
        local sp = emit(p, OP_SPLIT, {})
        local clone_start = clone_range(p, atom_start, atom_end)
        local exit_ix = #p.code + 1
        p.code[sp].data = {
          x = lazy and exit_ix or clone_start,
          y = lazy and clone_start or exit_ix,
        }
      end
    end
  end
end

local function parse_concat(p)
  local start = #p.code + 1
  while p.pos <= #p.src do
    local c = p.src:sub(p.pos, p.pos)
    if c == ')' or c == '|' then break end
    local atom_start = parse_atom(p)
    if p.pos <= #p.src then
      local q = p.src:sub(p.pos, p.pos)
      if q == '*' or q == '+' or q == '?' then
        p.pos = p.pos + 1
        local lazy = false
        if p.pos <= #p.src and p.src:sub(p.pos, p.pos) == '?' then
          lazy = true; p.pos = p.pos + 1
        end
        apply_quant(p, atom_start, q, 0, 0, lazy)
      elseif q == '{' then
        local save = p.pos
        p.pos = p.pos + 1
        local n_lo = nil
        while p.pos <= #p.src and p.src:sub(p.pos, p.pos):match("%d") do
          n_lo = (n_lo or 0) * 10 + tonumber(p.src:sub(p.pos, p.pos))
          p.pos = p.pos + 1
        end
        if n_lo == nil then
          p.pos = save
        else
          local n_hi = n_lo
          if p.pos <= #p.src and p.src:sub(p.pos, p.pos) == ',' then
            p.pos = p.pos + 1
            n_hi = -1
            local hi = nil
            while p.pos <= #p.src and p.src:sub(p.pos, p.pos):match("%d") do
              hi = (hi or 0) * 10 + tonumber(p.src:sub(p.pos, p.pos))
              p.pos = p.pos + 1
            end
            if hi then n_hi = hi end
          end
          if p.pos <= #p.src and p.src:sub(p.pos, p.pos) == '}' then
            p.pos = p.pos + 1
            local lazy = false
            if p.pos <= #p.src and p.src:sub(p.pos, p.pos) == '?' then
              lazy = true; p.pos = p.pos + 1
            end
            apply_quant(p, atom_start, '{', n_lo, n_hi, lazy)
          else
            parse_error(p, "bad {n,m}")
          end
        end
      end
    end
  end
  return start
end

parse_alt = function(p)
  local start = parse_concat(p)
  while p.pos <= #p.src and p.src:sub(p.pos, p.pos) == '|' do
    local branch1_end = #p.code + 1
    local jmp_ix = emit(p, OP_JMP, { jmp = -1 })
    local branch2_start = #p.code + 1
    shift_one(p, start)
    p.code[start] = { op = OP_SPLIT, data = { x = start + 1, y = branch2_start + 1 } }
    p.pos = p.pos + 1
    parse_concat(p)
    p.code[jmp_ix + 1].data.jmp = #p.code + 1
  end
  return start
end

-- ---------------------------------------------------------------------
-- Public compile
-- ---------------------------------------------------------------------

local Regex = {}
Regex.__index = Regex

function M.compile(pattern)
  if type(pattern) == 'table' and pattern.__is_regex then return pattern end
  if type(pattern) ~= 'string' then
    error("regex.compile: pattern must be a string", 2)
  end
  local p = {
    src = pattern,
    pos = 1,
    code = {},
    next_group = 1,
    anchored = pattern:sub(1, 1) == '^',
  }
  emit(p, OP_SAVE, { slot = 0 })
  parse_alt(p)
  if p.pos <= #p.src then
    parse_error(p, "unexpected " .. p.src:sub(p.pos, p.pos))
  end
  emit(p, OP_SAVE, { slot = 1 })
  emit(p, OP_MATCH)
  local re = setmetatable({
    code = p.code,
    ngroups = p.next_group,
    anchored = p.anchored,
    __is_regex = true,
  }, Regex)
  return re
end

-- ---------------------------------------------------------------------
-- Matcher
-- ---------------------------------------------------------------------

local function is_word(b) return (b >= 0x30 and b <= 0x39) or (b >= 0x41 and b <= 0x5A) or (b >= 0x61 and b <= 0x7A) or b == 0x5F end

local function add_thread(re, list, pc, slots, sp, input, ilen, visited)
  if pc < 1 or pc > #re.code then return end
  if visited[pc] then return end
  visited[pc] = true
  local insn = re.code[pc]
  local op = insn.op
  if op == OP_JMP then
    add_thread(re, list, insn.data.jmp, slots, sp, input, ilen, visited)
  elseif op == OP_SPLIT then
    add_thread(re, list, insn.data.x, slots, sp, input, ilen, visited)
    add_thread(re, list, insn.data.y, slots, sp, input, ilen, visited)
  elseif op == OP_SAVE then
    local ns = {}
    for i = 1, #slots do ns[i] = slots[i] end
    ns[insn.data.slot + 1] = sp
    add_thread(re, list, pc + 1, ns, sp, input, ilen, visited)
  elseif op == OP_BOL then
    if sp == 0 or input:byte(sp) == 10 then
      add_thread(re, list, pc + 1, slots, sp, input, ilen, visited)
    end
  elseif op == OP_EOL then
    if sp == ilen or input:byte(sp + 1) == 10 then
      add_thread(re, list, pc + 1, slots, sp, input, ilen, visited)
    end
  elseif op == OP_WB or op == OP_NWB then
    local left = sp > 0 and is_word(input:byte(sp))
    local right = sp < ilen and is_word(input:byte(sp + 1))
    local at_bd = left ~= right
    if (op == OP_WB) == at_bd then
      add_thread(re, list, pc + 1, slots, sp, input, ilen, visited)
    end
  else
    list[#list + 1] = { pc = pc, slots = slots }
  end
end

local function match_at(re, input, ilen, start)
  local nslots = re.ngroups * 2
  local init = {}
  for i = 1, nslots do init[i] = -1 end
  local cur = {}
  local nxt = {}
  add_thread(re, cur, 1, init, start, input, ilen, {})
  local sp = start
  local found = nil
  while #cur > 0 do
    local c = (sp < ilen) and input:byte(sp + 1) or -1
    local visited = {}
    for i = 1, #cur do
      local th = cur[i]
      local insn = re.code[th.pc]
      local op = insn.op
      if op == OP_CHAR then
        if c == insn.data.c then add_thread(re, nxt, th.pc + 1, th.slots, sp + 1, input, ilen, visited) end
      elseif op == OP_ANY then
        if c >= 0 and c ~= 10 then add_thread(re, nxt, th.pc + 1, th.slots, sp + 1, input, ilen, visited) end
      elseif op == OP_CLASS then
        if c >= 0 and insn.data.cc[c] then add_thread(re, nxt, th.pc + 1, th.slots, sp + 1, input, ilen, visited) end
      elseif op == OP_MATCH then
        if not found then found = th.slots end
        break
      end
    end
    cur, nxt = nxt, {}
    sp = sp + 1
    if #cur == 0 then break end
  end
  -- Drain remaining current threads for trailing MATCH.
  for i = 1, #cur do
    if re.code[cur[i].pc].op == OP_MATCH then
      if not found then found = cur[i].slots end
      break
    end
  end
  return found
end

function Regex:find(input)
  input = input or ""
  local ilen = #input
  for start = 0, ilen do
    local slots = match_at(self, input, ilen, start)
    if slots then return slots end
    if self.anchored then break end
  end
  return nil
end

function Regex:test(input)
  return self:find(input) ~= nil
end

function Regex:find_all(input)
  input = input or ""
  local ilen = #input
  local out = {}
  local pos = 0
  while pos <= ilen do
    local slots = nil
    local start
    for s = pos, ilen do
      slots = match_at(self, input, ilen, s)
      if slots then start = s; break end
      if self.anchored and s > pos then break end
    end
    if not slots then break end
    out[#out + 1] = slots
    local mend = slots[2]
    if mend == slots[1] then pos = mend + 1 else pos = mend end
  end
  return out
end

local function caps_to_strs(slots, input, ngroups)
  local out = {}
  for g = 0, ngroups - 1 do
    local s, e = slots[g * 2 + 1], slots[g * 2 + 2]
    if s < 0 or e < s then
      out[g + 1] = ""
    else
      out[g + 1] = input:sub(s + 1, e)
    end
  end
  return out
end

local function expand_replacement(repl, slots, input)
  local out = {}
  local i = 1
  while i <= #repl do
    local c = repl:sub(i, i)
    if c == '$' and i < #repl then
      local nc = repl:sub(i + 1, i + 1)
      if nc == '&' then
        local s, e = slots[1], slots[2]
        if s >= 0 and e >= s then out[#out + 1] = input:sub(s + 1, e) end
        i = i + 2
      elseif nc:match("[0-9]") then
        local g = tonumber(nc)
        local s, e = slots[g * 2 + 1], slots[g * 2 + 2]
        if s and e and s >= 0 and e >= s then out[#out + 1] = input:sub(s + 1, e) end
        i = i + 2
      elseif nc == '$' then
        out[#out + 1] = '$'
        i = i + 2
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

function Regex:replace(input, replacement)
  input = input or ""
  local ilen = #input
  local parts = {}
  local pos = 0
  while pos <= ilen do
    local slots = nil
    local start
    for s = pos, ilen do
      slots = match_at(self, input, ilen, s)
      if slots then start = s; break end
      if self.anchored and s > pos then break end
    end
    if not slots then
      parts[#parts + 1] = input:sub(pos + 1, ilen)
      break
    end
    parts[#parts + 1] = input:sub(pos + 1, start)
    if type(replacement) == 'function' then
      local strs = caps_to_strs(slots, input, self.ngroups)
      parts[#parts + 1] = replacement(strs)
    else
      parts[#parts + 1] = expand_replacement(replacement, slots, input)
    end
    local mend = slots[2]
    if mend == slots[1] then
      if mend < ilen then parts[#parts + 1] = input:sub(mend + 1, mend + 1) end
      pos = mend + 1
    else
      pos = mend
    end
  end
  return table.concat(parts)
end

-- ---------------------------------------------------------------------
-- Public uniform API (matches REGEX_API.md)
-- ---------------------------------------------------------------------

function M.re_compile(pattern) return M.compile(pattern) end

function M.re_test(pattern, input)
  return M.compile(pattern):test(input)
end

function M.re_find(pattern, input)
  local re = M.compile(pattern)
  local slots = re:find(input)
  if not slots then return nil end
  return caps_to_strs(slots, input or "", re.ngroups)
end

function M.re_find_all(pattern, input)
  local re = M.compile(pattern)
  local out = {}
  for _, slots in ipairs(re:find_all(input)) do
    out[#out + 1] = caps_to_strs(slots, input or "", re.ngroups)
  end
  return out
end

function M.re_replace(pattern, input, replacement)
  return M.compile(pattern):replace(input, replacement)
end

function M.re_escape(literal)
  local escaped = (literal or ""):gsub("[%.%*%+%?%^%$%{%}%(%)%|%[%]\\]", "\\%0")
  return escaped
end

return M
