local M = {}

---@param keys string
---@return string[]
function M.split_keys(keys)
  local key_list = {}
  local idx = 1

  while idx <= #keys do
    local next_idx = vim.fn.byteidx(keys, vim.fn.charidx(keys, idx - 1) + 1)
    if next_idx < 0 then
      next_idx = #keys
    end

    key_list[#key_list + 1] = keys:sub(idx, next_idx)
    idx = next_idx + 1
  end

  return key_list
end

---@param alphabet_size number
---@param target_count number
---@return number
local function expansion_count(alphabet_size, target_count)
  return math.ceil(target_count / (alphabet_size - 1))
end

---@param keys string
---@param n number
---@return string[]
function M.prefix_labels(keys, n)
  if n <= 0 then
    return {}
  end

  local key_list = M.split_keys(keys)
  if #key_list == 0 then
    error('hop.opts.keys must contain at least one key')
  end

  if #key_list < 2 and n > 1 then
    error('hop.opts.keys must contain at least two keys to label multiple targets')
  end

  local labels = {}
  local frontier = vim.list_slice(key_list)
  local remaining = n

  while remaining > 0 do
    if remaining <= #frontier then
      for i = 1, remaining do
        labels[#labels + 1] = frontier[i]
      end
      break
    end

    local expand = math.min(expansion_count(#key_list, remaining - #frontier), #frontier)
    local emit = #frontier - expand

    for i = 1, emit do
      labels[#labels + 1] = frontier[i]
    end

    remaining = remaining - emit

    local next_frontier = {}
    for i = emit + 1, #frontier do
      local prefix = frontier[i]
      for _, key in ipairs(key_list) do
        next_frontier[#next_frontier + 1] = prefix .. key
      end
    end

    frontier = next_frontier
  end

  return labels
end

return M
