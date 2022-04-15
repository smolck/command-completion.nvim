local M = {}
local f = vim.fn

local user_opts = {
  border = false,
  max_col_num = 5,
  min_col_width = 20,
}

local debounce_timer

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

local function calc_col_width()
  local col_width
  for i = 1, user_opts.max_col_num do
    local test_width = math.floor(vim.o.columns / i)
    if test_width <= user_opts.min_col_width then
      return col_width
    else
      col_width = test_width
    end
  end

  return col_width
end

local function open_and_setup_win(height)
  if not M.wbufnr then
    M.wbufnr = n.create_buf(false, true)
  end

  M.winid = n.open_win(M.wbufnr, false, {
    relative = 'editor',
    border = user_opts.border and 'single' or nil,
    style = 'minimal',
    width = vim.o.columns,
    height = height,
    row = vim.o.lines - 2,
    col = 0,
  })

  vim.cmd([[ redraw ]])
end

local function setup_handlers()
  debounce_timer = nil

  local height = math.floor(vim.o.lines * 0.3)
  local col_width = calc_col_width()
  open_and_setup_win(height)

  local tbl = {}
  for _ = 0, height do
    tbl[#tbl + 1] = (' '):rep(vim.o.columns)
  end
  n.buf_set_lines(M.wbufnr, 0, height, false, tbl)

  M.cmdline_changed_autocmd = n.create_autocmd({ 'CmdlineChanged' }, {
    callback = function()
      if not M.winid then
        open_and_setup_win(height)
      end

      -- Clear window
      n.buf_set_lines(M.wbufnr, 0, height, false, tbl)

      local input = f.getcmdline()
      local completions = f.getcompletion(input, 'cmdline')

      -- TODO(smolck): This *should* only apply to suggestions that are files, but
      -- I'm not totally sure if that's right so might need to be properly tested.
      -- (Or maybe find a better way of cutting down filepath suggestions to their tails?)
      completions = vim.tbl_map(function(c)
        local f1 = f.fnamemodify(c, ':p:t')

        local ret
        if f1 == '' then
          -- This is for filepaths like '/Users/someuser/thing/', where if you get
          -- the tail it's just empty.
          ret = f.fnamemodify(c, ':p:h:t')
        else
          ret = f1
        end

        if string.len(ret) >= col_width then
          ret = string.sub(ret, 1, col_width - 5) .. '...'
        end

        return ret
      end, completions)

      -- Don't show completion window if there are no completions.
      if vim.tbl_isempty(completions) then
        n.win_close(M.winid, true)
        M.winid = nil

        return
      end

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
      n.win_set_height(M.winid, math.min(math.floor(#completions / (math.floor(vim.o.columns / col_width))), height))
      vim.cmd([[ redraw ]])
    end,
  })
end

local function teardown_handlers()
  n.del_autocmd(M.cmdline_changed_autocmd)
  n.win_close(M.winid, true)
  M.winid = nil

  n.buf_set_lines(M.wbufnr, 0, -1, true, {})
end

local enter_aucmd_id, leave_aucmd_id

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    user_opts[k] = v
  end

  enter_aucmd_id = n.create_autocmd({ 'CmdlineEnter' }, {
    callback = function()
      if vim.v.event.cmdtype == ':' then
        debounce_timer = vim.defer_fn(setup_handlers, 100) -- TODO(smolck): Make this time configurable?
      end
    end,
  })
  leave_aucmd_id = n.create_autocmd({ 'CmdlineLeave', 'CmdwinLeave' }, {
    callback = function()
      if vim.v.event.cmdtype == ':' then
        if debounce_timer then
          debounce_timer:stop()
          debounce_timer = nil
        else
          teardown_handlers()
        end
      end
    end,
  })
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
