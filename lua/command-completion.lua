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

local user_opts = {
  border = nil,
  max_col_num = 5,
  min_col_width = 20,
  use_matchfuzzy = true,
  highlight_selection = true,
  highlight_directories = true,
  tab_completion = true,
}

local current_completions = {}
local current_selection = 1
local debounce_timer
local cmdline_changed_disabled = false
local in_that_cursed_cmdwin = false
local enter_aucmd_id, leave_aucmd_id
local search_hl_nsid = n.create_namespace('__ccs_hls_namespace_search___')
local directory_hl_nsid = n.create_namespace('__ccs_hls_namespace_directory___')

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
    border = user_opts.border,
    style = 'minimal',
    width = vim.o.columns,
    height = height,
    row = vim.o.lines - 2,
    col = 0,
  })

  vim.cmd('redraw')
end

local function setup_handlers()
  debounce_timer = nil
  if in_that_cursed_cmdwin then
    return
  end

  local height = math.floor(vim.o.lines * 0.3)
  local col_width = calc_col_width()
  open_and_setup_win(height)

  local tbl = {}
  for _ = 0, height do
    tbl[#tbl + 1] = (' '):rep(vim.o.columns)
  end
  n.buf_set_lines(M.wbufnr, 0, height, false, tbl)

  local function autocmd_cb()
    if cmdline_changed_disabled then
      return
    end

    if not M.winid then
      open_and_setup_win(height)
    end

    -- Clear window
    n.buf_set_lines(M.wbufnr, 0, height, false, tbl)

    local input = f.getcmdline()
    local completions = f.getcompletion(input, 'cmdline')

    -- TODO(smolck): No clue if this really helps much if at all but we'll use it
    -- by default for now
    if user_opts.use_matchfuzzy and input ~= '' then
      local split = vim.split(input, ' ')
      local str_to_match = split[#split]

      completions = vim.fn.matchfuzzy(completions, str_to_match)
    end

    -- TODO(smolck): This *should* only apply to suggestions that are files, but
    -- I'm not totally sure if that's right so might need to be properly tested.
    -- (Or maybe find a better way of cutting down filepath suggestions to their tails?)
    completions = vim.tbl_map(function(c)
      local is_directory = vim.fn.isdirectory(f.fnamemodify(c, ':p')) == 1
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

      return { completion = ret, is_directory = is_directory, full_completion = c }
    end, completions)

    current_completions = {}
    current_selection = -1

    -- Don't show completion window if there are no completions.
    if vim.tbl_isempty(completions) then
      n.win_close(M.winid, true)
      M.winid = nil

      return
    end

    local i = 1
    for line = 0, height - 1 do
      for col = 0, math.floor(vim.o.columns / col_width) - 1 do
        if i > #completions then
          break
        end
        local end_col = col * col_width + string.len(completions[i].completion)
        if end_col > vim.o.columns then
          break
        end
        n.buf_set_text(M.wbufnr, line, col * col_width, line, end_col, { completions[i].completion })

        current_completions[i] = {
          start = { line, col * col_width },
          finish = { line, end_col },
          full_completion = completions[i].full_completion,
        }

        if i == current_selection and user_opts.highlight_selection then
          vim.highlight.range(M.wbufnr, search_hl_nsid, 'Search', { line, col * col_width }, { line, end_col }, {})
        end

        if completions[i].is_directory and user_opts.highlight_directories then
          vim.highlight.range(
            M.wbufnr,
            directory_hl_nsid,
            'Directory',
            { line, col * col_width },
            { line, end_col },
            {}
          )
        end

        i = i + 1
      end
    end
    n.win_set_height(M.winid, math.min(math.floor(#completions / (math.floor(vim.o.columns / col_width))), height))
    vim.cmd('redraw')
  end

  M.cmdline_changed_autocmd = n.create_autocmd({ 'CmdlineChanged' }, {
    callback = autocmd_cb,
  })

  -- Initial completions when cmdline is already open and empty
  autocmd_cb()
end

local function teardown_handlers()
  if M.cmdline_changed_autocmd then
    n.del_autocmd(M.cmdline_changed_autocmd)
    M.cmdline_changed_autocmd = nil
  end
  if M.winid then -- TODO(smolck): Check if n.win_is_valid(M.winid)?
    if in_that_cursed_cmdwin then
      n.win_hide(M.winid) -- Idk but it works (EDIT: NOT REALLY this is probably quite bad, so prepare for breakge
                          -- just gotta fix this upstream I guess by making cmdwin sane with float and stuff
                          -- TODO(smolck): come back once you've hopefully done that upstream)
    else
      n.win_close(M.winid, true)
    end
  end
  M.winid = nil
  current_selection = 1

  if M.wbufnr then
    n.buf_set_lines(M.wbufnr, 0, -1, true, {})
  end
end

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    user_opts[k] = v
  end

  if user_opts.tab_completion then
    vim.keymap.set('c', '<Tab>', function()
      if vim.tbl_isempty(current_completions) then
        current_selection = 1
        return
      end

      if current_selection == -1 then
        -- TODO(smolck): This comment might not *quite* be accurate.
        -- Means we just reset this back to the first completion from the CmdlineChanged autocmd
        current_selection = 1
      else
        current_selection = current_selection + 1 > #current_completions and 1 or current_selection + 1
      end

      n.buf_clear_namespace(M.wbufnr, search_hl_nsid, 0, -1)
      vim.highlight.range(
        M.wbufnr,
        search_hl_nsid,
        'Search',
        current_completions[current_selection].start,
        current_completions[current_selection].finish,
        {}
      )
      vim.cmd('redraw')

      -- TODO(smolck): Re-visit this when/if https://github.com/neovim/neovim/pull/18096 is merged.
      local cmdline = f.getcmdline()
      local last_word_len = vim.split(cmdline, ' ')
      last_word_len = string.len(last_word_len[#last_word_len])

      cmdline_changed_disabled = true
      vim.api.nvim_input(('<BS>'):rep(last_word_len) .. current_completions[current_selection].full_completion)

      -- This is necessary, from @gpanders on matrix:
      --
      -- """
      -- what's probably happening is you are ignoring CmdlineChanged, running your function, and then removing it before the event loop has a chance to turn
      -- so you should instead ignore the event, run your callback, let the event loop turn, and then remove it
      -- which is what vim.schedule is for
      -- """
      --
      -- Just :%s/ignoring CmdlineChanged/setting cmdline_changed_disabled etc.
      vim.schedule(function()
        cmdline_changed_disabled = false
      end)
    end)
  end

  n.create_autocmd({ 'CmdwinEnter' }, {
    callback = function()
      in_that_cursed_cmdwin = true

      -- Could also be entering cmdwin from cmdline so handle that
      if M.winid then
        teardown_handlers()
      end
    end,
  })
  n.create_autocmd({ 'CmdwinLeave' }, {
    callback = function()
      in_that_cursed_cmdwin = false
    end,
  })
  enter_aucmd_id = n.create_autocmd({ 'CmdlineEnter' }, {
    callback = function()
      if vim.v.event.cmdtype == ':' then
        debounce_timer = vim.defer_fn(setup_handlers, 100) -- TODO(smolck): Make this time configurable?
      end
    end,
  })
  leave_aucmd_id = n.create_autocmd({ 'CmdlineLeave' }, {
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

-- TODO(smolck): I don't even know if this is necessary, honestly. Or if it works.
function M.disable()
  if enter_aucmd_id then
    n.del_autocmd(enter_aucmd_id)
    enter_aucmd_id = nil
  end

  if leave_aucmd_id then
    n.del_autocmd(leave_aucmd_id)
    leave_aucmd_id = nil
  end

  vim.keymap.del('c', '<Tab>')
end

return M
