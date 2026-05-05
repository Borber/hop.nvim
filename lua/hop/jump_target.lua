-- Generate jump locations within windows according to hop options
---@alias Generator fun(opts:Options, win_ctxs:WindowContext[]|nil):Locations

-- Jump targets are locations in buffers where users might jump to. They are wrapped in a table and provide the
-- required information so that Hop can associate label and display the hints.
---@class Locations
---@field jump_targets JumpTarget[]
---@field indirect_jump_targets IndirectJumpTarget[]

-- A single jump target is simply a location in a given buffer at a window.
---@class JumpTarget
---@field window number
---@field buffer number
---@field cursor CursorPos
---@field length number Jump target column length

-- Indirect jump targets are encoded as a flat list-table of pairs (index, score). This table allows to quickly score
-- and sort jump targets. The `index` field gives the index in the `jump_targets` list. The `score` is any number. The
-- rule is that the lower the score is, the less prioritized the jump target will be.
---@class IndirectJumpTarget
---@field index number
---@field score number

---@class JumpContext
---@field win_ctx WindowContext
---@field line_ctx LineContext
---@field regex Regex

---@class Regex
---@field oneshot boolean
---@field match fun(s:string, jctx:JumpContext, opts:Options):ColumnRange
---@field match_line? fun(bufnr:integer, row:WindowRow, start_col:WindowCol, end_col:WindowCol|nil, jctx:JumpContext, opts:Options):ColumnRange

local hint = require('hop.hint')
local window = require('hop.window')
local api = vim.api

---@class JumpTargetModule
local M = {}

---@param pat string
---@return Regex
local function regex_by_searching(pat)
  local regex = vim.regex(pat)

  return {
    oneshot = false,
    match = function(s)
      return regex:match_str(s)
    end,
    match_line = function(bufnr, row, start_col, end_col)
      return regex:match_line(bufnr, row - 1, start_col, end_col)
    end,
  }
end

---@return Regex
local function regex_by_word_start()
  return regex_by_searching('\\k\\+')
end

---@return Regex
local function regex_by_camel_case()
  local camel = '\\u\\l\\+'
  local acronyms = '\\u\\+\\ze\\u\\l'
  local upper = '\\u\\+'
  local lower = '\\l\\+'
  local rgb = '#\\x\\+\\>'
  local ox = '\\<0[xX]\\x\\+\\>'
  local oo = '\\<0[oO][0-7]\\+\\>'
  local ob = '\\<0[bB][01]\\+\\>'
  local num = '\\d\\+'
  local parts = { camel, acronyms, upper, lower, rgb, ox, oo, ob, num, '\\~', '!', '@', '#', '$' }

  return regex_by_searching('\\%(\\%(' .. table.concat(parts, '\\)\\|\\%(') .. '\\)\\)')
end

---@return Regex
local function regex_by_vertical()
  return {
    oneshot = true,
    match = function(s, jctx, opts)
      if window.is_cursor_line(jctx.win_ctx, jctx.line_ctx) then
        if window.is_active_window(jctx.win_ctx) then
          return
        end

        if opts.direction == hint.HintDirection.AFTER_CURSOR then
          return 0, 1
        end
      end

      local idx = window.cell2char(s, jctx.win_ctx.col_first)
      local col = vim.fn.byteidx(s, idx)
      if -1 < col and col < #s then
        return col, col + 1
      end

      return #s - 1, #s
    end,
  }
end

---@return Regex
local function regex_by_anywhere()
  return regex_by_searching('\\v(<.|^$)|(.>|^$)|(\\l)\\zs(\\u)|(_\\zs.)|(#\\zs.)')
end

---@param jump_ctx JumpContext
---@param jump_target JumpTarget
---@param locations Locations
---@param opts Options
---@param win_bias integer
local function push_scored_jump_target(jump_ctx, jump_target, locations, opts, win_bias)
  local score = opts.distance_method(jump_ctx.win_ctx.cursor, jump_target.cursor, opts.x_bias) + win_bias
  if score ~= 0 then
    locations.jump_targets[#locations.jump_targets + 1] = jump_target
    locations.indirect_jump_targets[#locations.indirect_jump_targets + 1] = {
      index = #locations.jump_targets,
      score = score,
    }
  end
end

-- Create jump targets within line
---@param jump_ctx JumpContext
---@param opts Options
---@return JumpTarget[]
local function create_line_jump_targets(jump_ctx, opts)
  local wctx = jump_ctx.win_ctx
  local lctx = jump_ctx.line_ctx

  ---@type JumpTarget[]
  local jump_targets = {}

  -- No possible position to place target
  if lctx.line == '' and wctx.col_offset > 0 then
    return jump_targets
  end

  local idx = 1 -- 1-based index for lua string
  while true do
    local s = lctx.line:sub(idx)
    ---@type ColumnRange
    local b, e = jump_ctx.regex.match(s, jump_ctx, opts)
    if b == nil then
      break
    end
    -- Preview need a length to highlight the matched string. Zero means nothing to highlight.
    local matched_length = e - b
    -- As the make for jump target must be placed at a cell (but some pattern like '^' is
    -- placed between cells), we should make sure e > b
    if b == e then
      e = e + 1
    end

    ---@type WindowCol
    local col = idx + b
    if opts.hint_position == hint.HintPosition.MIDDLE then
      col = idx + math.floor((b + e) / 2)
    elseif opts.hint_position == hint.HintPosition.END then
      col = idx + e - 1
    end
    col = col - 1 -- Convert 1-based lua string index to WindowCol
    jump_targets[#jump_targets + 1] = {
      window = wctx.win_handle,
      buffer = wctx.buf_handle,
      cursor = {
        row = lctx.row,
        col = math.max(0, col + lctx.col_bias),
      },
      length = math.max(0, matched_length),
    }
    idx = idx + e

    -- Do not search further if regex is oneshot or if there is nothing more to search
    if idx > #lctx.line or s == '' or jump_ctx.regex.oneshot then
      break
    end
  end

  return jump_targets
end

---@param jump_ctx JumpContext
---@param opts Options
---@return JumpTarget[]|nil
local function create_buffer_line_jump_targets(jump_ctx, opts)
  if jump_ctx.regex.match_line == nil then
    return nil
  end

  local wctx = jump_ctx.win_ctx
  local lctx = jump_ctx.line_ctx

  if lctx.original_line == nil then
    return nil
  end

  if lctx.original_line == '' and wctx.col_offset > 0 then
    return {}
  end

  ---@type JumpTarget[]
  local jump_targets = {}
  local line_end = lctx.line_end or #lctx.original_line
  local start_col = lctx.col_bias

  while start_col <= line_end do
    ---@type ColumnRange
    local b, e = jump_ctx.regex.match_line(wctx.buf_handle, lctx.row, start_col, line_end, jump_ctx, opts)
    if b == nil then
      break
    end

    local matched_length = e - b
    if b == e then
      e = e + 1
    end

    ---@type WindowCol
    local col = start_col + b
    if opts.hint_position == hint.HintPosition.MIDDLE then
      col = start_col + math.floor((b + e) / 2)
    elseif opts.hint_position == hint.HintPosition.END then
      col = start_col + e - 1
    end

    jump_targets[#jump_targets + 1] = {
      window = wctx.win_handle,
      buffer = wctx.buf_handle,
      cursor = {
        row = lctx.row,
        col = math.max(0, col),
      },
      length = math.max(0, matched_length),
    }

    start_col = start_col + e

    if start_col > line_end or jump_ctx.regex.oneshot then
      break
    end
  end

  return jump_targets
end

-- Create indirect jump targets within line
---@param jump_ctx JumpContext
---@param locations Locations used later to sort jump targets by score and create hints.
---@param opts Options
local function create_line_indirect_jump_targets(jump_ctx, locations, opts)
  -- First, create the jump targets for the ith line
  local line_jump_targets = create_buffer_line_jump_targets(jump_ctx, opts) or create_line_jump_targets(jump_ctx, opts)
  local win_bias = math.abs(vim.api.nvim_get_current_win() - jump_ctx.win_ctx.win_handle) * 1000

  -- then, append those to the input jump target list and create the indexed jump targets
  for _, jump_target in pairs(line_jump_targets) do
    push_scored_jump_target(jump_ctx, jump_target, locations, opts, win_bias)
  end
end

-- Apply a score function based on the Manhattan distance to indirect jump targets.
---@param indirect_jump_targets IndirectJumpTarget[]
---@param opts Options
function M.sort_indirect_jump_targets(indirect_jump_targets, opts)
  local score_comparison = function(a, b)
    return a.score < b.score
  end
  if opts.reverse_distribution then
    score_comparison = function(a, b)
      return a.score > b.score
    end
  end

  table.sort(indirect_jump_targets, score_comparison)
end

-- Apply an offset on jump target
-- Always offset in row first, then in cell
---@param jt JumpTarget
---@param offset_row WindowRow|nil
---@param offset_cell WindowCell|nil
function M.move_jump_target(jt, offset_row, offset_cell)
  local drow = offset_row or 0
  local dcell = offset_cell or 0

  if drow ~= 0 then
    ---@type WindowRow
    local new_row = jt.cursor.row + drow
    local max_row = vim.api.nvim_buf_line_count(jt.buffer)
    if new_row > max_row then
      jt.cursor.row = max_row
    elseif new_row < 1 then
      jt.cursor.row = 1
    else
      jt.cursor.row = new_row
    end
  end

  if dcell ~= 0 then
    local line = vim.api.nvim_buf_get_lines(jt.buffer, jt.cursor.row - 1, jt.cursor.row, false)[1]
    local line_cells = vim.fn.strdisplaywidth(line)
    ---@type WindowCell
    local new_cell = vim.fn.strdisplaywidth(line:sub(1, jt.cursor.col)) + dcell
    if new_cell >= line_cells then
      new_cell = line_cells
    elseif new_cell < 0 then
      new_cell = 0
    end
    jt.cursor.col = vim.fn.byteidx(line, window.cell2char(line, new_cell))
  end
end

-- Create jump targets by scanning windows and lines
--
-- This function takes a regex argument, which is an object containing a match function that must return the span
-- (inclusive beginning, exclusive end) of the match item, or nil when no more match is possible. This object also
-- contains the `oneshot` field, a boolean stating whether only the first match of a line should be taken into account.
--
-- This function returns the lined jump targets (an array of N lines, where N is the number of currently visible lines).
-- Lines without jump targets are assigned an empty table ({}). For lines with jump targets, a list-table contains the
-- jump targets as pair of { line, col }.
--
-- This function returns the total number of jump targets (i.e. this is the same thing as
-- traversing the lined jump targets and summing the number of jump targets for all lines) as a courtesy, plus «
-- indirect jump targets. » Indirect jump targets are encoded as a flat list-table containing three values: i, for the
-- ith line, j, for the rank of the jump target, and dist, the score distance of the associated jump target. This list
-- is sorted according to that last dist parameter in order to know how to distribute the jump targets over the buffer.
---@param regex Regex
---@param win_ctxs WindowContext[]|nil
---@return Generator
function M.jump_target_generator(regex, win_ctxs)
  ---@type Generator
  return function(opts, runtime_win_ctxs)
    local all_win_ctxs = runtime_win_ctxs or win_ctxs or window.get_windows_context(opts)
    if opts.current_line_only then
      all_win_ctxs = { all_win_ctxs[1] }
    end

    ---@type Locations
    local locations = {
      jump_targets = {},
      indirect_jump_targets = {},
    }

    -- Iterate all window then line contexts
    for _, wctx in ipairs(all_win_ctxs) do
      window.clip_window_context(wctx, opts)

      local all_line_ctxs = window.get_lines_context(wctx)
      for _, lctx in ipairs(all_line_ctxs) do
        window.clip_line_context(wctx, lctx, opts)

        ---@type JumpContext
        local jump_ctx = { win_ctx = wctx, line_ctx = lctx, regex = regex }
        create_line_indirect_jump_targets(jump_ctx, locations, opts)
      end
    end

    M.sort_indirect_jump_targets(locations.indirect_jump_targets, opts)

    return locations
  end
end

---@return Generator
function M.word_start_generator()
  return M.jump_target_generator(regex_by_word_start())
end

---@return Generator
function M.camel_case_generator()
  return M.jump_target_generator(regex_by_camel_case())
end

---@return Generator
function M.vertical_generator()
  return M.jump_target_generator(regex_by_vertical())
end

---@return Generator
function M.anywhere_generator()
  return M.jump_target_generator(regex_by_anywhere())
end

---@param skip_whitespace boolean
---@return Generator
function M.line_start_generator(skip_whitespace)
  ---@type Generator
  return function(opts, runtime_win_ctxs)
    local all_win_ctxs = runtime_win_ctxs or window.get_windows_context(opts)
    if opts.current_line_only then
      all_win_ctxs = { all_win_ctxs[1] }
    end

    ---@type Locations
    local locations = {
      jump_targets = {},
      indirect_jump_targets = {},
    }

    for _, wctx in ipairs(all_win_ctxs) do
      window.clip_window_context(wctx, opts)
      local win_bias = math.abs(vim.api.nvim_get_current_win() - wctx.win_handle) * 1000

      local lnr = wctx.line_range[1]
      while lnr <= wctx.line_range[2] do
        local target_row = lnr
        local fold_end = api.nvim_win_call(wctx.win_handle, function()
          return vim.fn.foldclosedend(lnr)
        end)

        local line = nil
        local target_col = nil
        if fold_end == -1 then
          if not window.is_active_line(wctx, { row = lnr }) then
            line = api.nvim_buf_get_lines(wctx.buf_handle, lnr - 1, lnr, false)[1]
            if line ~= '' or wctx.col_offset == 0 then
              target_col = 0

              if skip_whitespace then
                local end_cell = vim.fn.strdisplaywidth(line)
                if wctx.win_width ~= nil then
                  end_cell = wctx.col_offset + wctx.win_width
                end

                local left_idx = window.cell2char(line, wctx.col_offset)
                local right_idx = window.cell2char(line, end_cell)
                local visible_line = vim.fn.strcharpart(line, left_idx, right_idx - left_idx)
                local b = visible_line:find('%S')
                if b ~= nil then
                  target_col = vim.fn.byteidx(line, left_idx + vim.fn.charidx(visible_line, b - 1))
                else
                  target_col = nil
                end
              elseif wctx.col_offset > 0 then
                target_col = vim.fn.byteidx(line, window.cell2char(line, wctx.col_offset))
                if target_col < 0 then
                  target_col = #line
                end
              end
            end
          end
        else
          if not window.is_active_line(wctx, { row = lnr }) and wctx.col_offset == 0 and not skip_whitespace then
            target_col = 0
          end
          lnr = fold_end
        end

        if target_col ~= nil then
          ---@type JumpContext
          local jump_ctx = {
            win_ctx = wctx,
            line_ctx = { row = target_row, line = line or '', col_bias = 0 },
          }
          push_scored_jump_target(jump_ctx, {
            window = wctx.win_handle,
            buffer = wctx.buf_handle,
            cursor = {
              row = target_row,
              col = target_col,
            },
            length = 1,
          }, locations, opts, win_bias)
        end

        lnr = lnr + 1
      end
    end

    M.sort_indirect_jump_targets(locations.indirect_jump_targets, opts)

    return locations
  end
end

return M
