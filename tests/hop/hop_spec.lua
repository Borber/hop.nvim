local hop = require('hop')
local eq = assert.are.same

local test_count = 0

local function make_jump_targets(count)
  local jump_targets = {}
  for i = 1, count do
    jump_targets[i] = {
      window = vim.api.nvim_get_current_win(),
      buffer = vim.api.nvim_get_current_buf(),
      cursor = { row = 1, col = i - 1 },
      length = 1,
    }
  end

  return jump_targets
end

local function make_hint_state(jump_target_count)
  local hint = require('hop.hint')

  local hints = hint.create_hints(make_jump_targets(jump_target_count), nil, hop.opts)
  local hint_state = hint.create_hint_state(hop.opts)
  hint_state.hints = hints
  hint_state.active_hints = hints
  hint_state.prefix = ''
  hint_state.prefix_length = 0
  hint_state.hint_index = hint.create_hint_index(hints)

  return hint_state
end

describe('Hop movement is correct', function()
  before_each(function()
    vim.cmd.new(test_count .. 'test_file')
    test_count = test_count + 1
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxy',
    })
    hop.setup()
  end)

  it('Hop is initialized', function()
    eq(hop.initialized, true)
  end)

  it('HopWord targets words through the buffer scanner', function()
    local jump_target = require('hop.jump_target')

    hop.setup({ keys = 'ab', dim_unmatched = false, jump_on_sole_occurrence = false })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'one two three four five',
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local locations = jump_target.word_start_generator()(hop.opts)
    eq(4, #locations.jump_targets)
    eq({ row = 1, col = 4 }, locations.jump_targets[1].cursor)
    eq({ row = 1, col = 8 }, locations.jump_targets[2].cursor)
  end)

  it('HopLine uses direct line targets', function()
    local jump_target = require('hop.jump_target')

    hop.setup({ keys = 'ab', dim_unmatched = false, jump_on_sole_occurrence = false })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'one',
      'two',
      'three',
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local locations = jump_target.line_start_generator(false)(hop.opts)
    eq(2, #locations.jump_targets)
    eq({ row = 2, col = 0 }, locations.jump_targets[1].cursor)
    eq({ row = 3, col = 0 }, locations.jump_targets[2].cursor)
  end)

  it('refines hints through a prefix index', function()
    hop.setup({ keys = 'ab', dim_unmatched = false, jump_on_sole_occurrence = false })
    local jumped_to = nil
    local hint_state = make_hint_state(4)

    hop.refine_hints('b', hint_state, function(jt)
      jumped_to = jt
    end, hop.opts)
    eq(nil, jumped_to)
    eq(2, #hint_state.active_hints)

    hop.refine_hints('a', hint_state, function(jt)
      jumped_to = jt
    end, hop.opts)
    eq({ row = 1, col = 2 }, jumped_to.cursor)
  end)

  it('backtracks to the previous prefix', function()
    hop.setup({ keys = 'ab', dim_unmatched = false, jump_on_sole_occurrence = false })
    local jumped_to = nil
    local hint_state = make_hint_state(6)

    hop.refine_hints('b', hint_state, function(jt)
      jumped_to = jt
    end, hop.opts)
    eq(nil, jumped_to)
    eq('b', hint_state.prefix)
    eq(4, #hint_state.active_hints)

    eq(true, hop.backtrack_hints(hint_state, hop.opts))
    eq('', hint_state.prefix)
    eq(0, hint_state.prefix_length)
    eq(6, #hint_state.active_hints)

    hop.refine_hints('a', hint_state, function(jt)
      jumped_to = jt
    end, hop.opts)
    eq(nil, jumped_to)

    hop.refine_hints('a', hint_state, function(jt)
      jumped_to = jt
    end, hop.opts)
    eq({ row = 1, col = 0 }, jumped_to.cursor)
  end)

  it('uses backspace to backtrack during a hop session', function()
    local helper = require('hop_helpers')

    hop.setup({ keys = 'ab', dim_unmatched = false, jump_on_sole_occurrence = false })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'one two three four five',
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local backspace = vim.api.nvim_replace_termcodes('<BS>', true, false, true)
    helper.override_keyseq({ 'b', backspace, 'a', 'a' }, function()
      hop.hint_words({})
    end)

    eq({ 1, 4 }, vim.api.nvim_win_get_cursor(0))
  end)

  it('quits on backspace at the root prefix', function()
    local helper = require('hop_helpers')

    hop.setup({ keys = 'ab', dim_unmatched = false, jump_on_sole_occurrence = false })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'one two three four five',
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local backspace = vim.api.nvim_replace_termcodes('<BS>', true, false, true)
    helper.override_keyseq({ backspace, 'a', 'a' }, function()
      hop.hint_words({})
    end)

    eq({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
  end)
end)
