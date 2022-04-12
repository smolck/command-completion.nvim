local M = {}
local f = vim.fn

local n = setmetatable({}, {
  __index = function(_, k)
    local maybe_thing = vim.api[k]
    if maybe_thing == nil then
      local thing_unless_typo = 'nvim_' .. k
      local maybe_thing_unless_typo = vim.api[thing_unless_typo]
      if maybe_thing_unless_typo == nil then
        error(thing_unless_typo .. ' is not a valid vim.api function')
      end

      return maybe_thing_unless_typo
    else
      return maybe_thing
    end
  end,
})

local debounce_timer

local function setup_handlers()
  debounce_timer = nil

  local height = math.floor(vim.o.lines * 0.3)
  local col_width = math.floor(vim.o.columns / 6)
  M.wbufnr = n.create_buf(false, true)
  M.winid = n.open_win(M.wbufnr, false, {
    relative = 'editor',
    border = 'single',
    style = 'minimal',
    width = vim.o.columns,
    height = height,
    row = vim.o.lines - 2,
    col = 0,
  })
  local tbl = {}
  for _ = 0, height do
    tbl[#tbl + 1] = (' '):rep(vim.o.columns)
  end
  n.buf_set_lines(M.wbufnr, 0, height, false, tbl)
  vim.cmd([[ redraw ]])

  M.cmdline_changed_autocmd = n.create_autocmd({ 'CmdlineChanged' }, { callback = function()
    n.buf_set_lines(M.wbufnr, 0, height, false, tbl)

    local input = f.getcmdline()
    local completions = f.getcompletion(input, 'cmdline')

    local i = 1
    for line = 0, height do
      for col = 0, math.floor(vim.o.columns / col_width) - 1 do
        if i > #completions then
          break
        end
        local end_col = col * col_width + string.len(completions[i])
        if end_col > vim.o.columns then
          break
        end
        n.buf_set_text(M.wbufnr, line, col * col_width, line, end_col, { completions[i] })

        i = i + 1
      end
    end
    vim.cmd([[ redraw ]])
  end})
end

local function teardown_handlers()
  n.del_autocmd(M.cmdline_changed_autocmd)
  n.win_close(M.winid, true)
  n.buf_set_lines(M.wbufnr, 0, -1, true, {})
end

local enter_aucmd_id, leave_aucmd_id

function M.setup()
  enter_aucmd_id = n.create_autocmd({ 'CmdlineEnter' }, { callback = function()
    debounce_timer = vim.defer_fn(setup_handlers, 100) -- TODO(smolck): Make this time configurable?
  end})
  leave_aucmd_id = n.create_autocmd({ 'CmdlineLeave', 'CmdwinLeave' }, { callback = function()
    if debounce_timer then
      debounce_timer:stop()
      debounce_timer = nil
    else
      teardown_handlers()
    end
  end})
end

function M.disable()
  if enter_aucmd_id then
    n.del_autocmd(enter_aucmd_id)
    enter_aucmd_id = nil
  end

  if leave_aucmd_id then
    n.del_autocmd(leave_aucmd_id)
    leave_aucmd_id = nil
  end
end

return M
