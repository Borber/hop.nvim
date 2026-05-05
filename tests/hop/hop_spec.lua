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
end)
