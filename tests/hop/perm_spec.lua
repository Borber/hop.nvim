local perm = require('hop.perm')
local eq = assert.are.same

describe('Hop label generation:', function()
  it('splits keys by character', function()
    eq({ 'a', '测', 'b', '试' }, perm.split_keys('a测b试'))
  end)

  it('generates compact prefix labels', function()
    eq({ 'aa', 'ab', 'baa', 'bab', 'bba', 'bbb' }, perm.prefix_labels('ab', 6))
  end)

  it('keeps labels prefix-free', function()
    local labels = perm.prefix_labels('abc', 30)

    for i, label in ipairs(labels) do
      for j, other in ipairs(labels) do
        if i ~= j then
          assert.is_false(other:sub(1, #label) == label)
        end
      end
    end
  end)
end)
