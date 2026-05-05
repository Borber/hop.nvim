local hop = require('hop')
local eq = assert.are.same

local test_count = 0

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
    local hint = require('hop.hint')

    hop.setup({ keys = 'ab', dim_unmatched = false, jump_on_sole_occurrence = false })
    local jump_targets = {}
    for i = 1, 4 do
      jump_targets[i] = {
        window = vim.api.nvim_get_current_win(),
        buffer = vim.api.nvim_get_current_buf(),
        cursor = { row = 1, col = i - 1 },
        length = 1,
      }
    end

    local hints = hint.create_hints(jump_targets, nil, hop.opts)
    local jumped_to = nil
    local hint_state = hint.create_hint_state(hop.opts)
    hint_state.hints = hints
    hint_state.active_hints = hints
    hint_state.prefix = ''
    hint_state.prefix_length = 0
    hint_state.hint_index = hint.create_hint_index(hints)

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
end)
