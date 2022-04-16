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

local has_07 = f.has('nvim-0.7') == 1

local user_opts = {
  border = nil,
  max_col_num = 5,
  min_col_width = 20,
  use_matchfuzzy = has_07,
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

local function create_autocmd_cb(height, tbl, col_width)
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
          line = line,
          col_start = col * col_width,
          col_end = end_col,
          full_completion = completions[i].full_completion,
        }

        if i == current_selection and user_opts.highlight_selection then
          n.buf_add_highlight(M.wbufnr, search_hl_nsid, 'Search', line, col * col_width, end_col)
        end

        if completions[i].is_directory and user_opts.highlight_directories then
          n.buf_add_highlight(M.wbufnr, directory_hl_nsid, 'Directory', line, col * col_width, end_col)
        end

        i = i + 1
      end
    end
    n.win_set_height(M.winid, math.min(math.floor(#completions / (math.floor(vim.o.columns / col_width))), height))
    vim.cmd('redraw')
  end

  return autocmd_cb
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

  local cb = create_autocmd_cb(height, tbl, col_width)
  if has_07 then
    M.cmdline_changed_autocmd = n.create_autocmd({ 'CmdlineChanged' }, {
      callback = cb,
    })

    -- Initial completions when cmdline is already open and empty
    cb()
  else
    M.cmdline_changed_handler = cb

    vim.cmd([[ augroup CommandCompletionAugroupTwo ]])
    vim.cmd([[ autocmd CmdlineChanged * lua require('command-completion').cmdline_changed_handler() ]])
    vim.cmd([[ augroup end ]])

    cb()
  end
end

local function teardown_handlers()
  if not has_07 then
    vim.cmd([[ aug! CommandCompletionAugroupTwo ]])
  else
    if M.cmdline_changed_autocmd then
      n.del_autocmd(M.cmdline_changed_autocmd)
      M.cmdline_changed_autocmd = nil
    end
  end

  if M.winid then -- TODO(smolck): Check if n.win_is_valid(M.winid)?
    if in_that_cursed_cmdwin then
      -- Idk but this "works" (EDIT: NOT REALLY this is probably quite bad, so prepare for breakge
      -- just gotta fix this upstream I guess by making cmdwin sane with float and stuff
      -- TODO(smolck): come back once you've hopefully done that upstream)
      n.win_hide(M.winid)
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

local function tab_cb()
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
  n.buf_add_highlight(
    M.wbufnr,
    search_hl_nsid,
    'Search',
    current_completions[current_selection].line,
    current_completions[current_selection].col_start,
    current_completions[current_selection].col_end
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
end

local function cmdwin_enter_cb()
  in_that_cursed_cmdwin = true

  -- Could also be entering cmdwin from cmdline so handle that
  if M.winid then
    teardown_handlers()
  end
end

local function cmdwin_leave_cb()
  in_that_cursed_cmdwin = false
end

local function cmdline_enter_cb()
  if vim.v.event.cmdtype == ':' then
    debounce_timer = vim.defer_fn(setup_handlers, 100) -- TODO(smolck): Make this time configurable?
  end
end

local function cmdline_leave_cb()
  if vim.v.event.cmdtype == ':' then
    if debounce_timer then
      debounce_timer:stop()
      debounce_timer = nil
    else
      teardown_handlers()
    end
  end
end

if f.has('nvim-0.7') ~= 1 then
  function M.tab_keymap_handler()
    tab_cb()
  end

  function M._cmdwin_enter_handler()
    cmdwin_enter_cb()
  end

  function M._cmdwin_leave_handler()
    cmdwin_leave_cb()
  end

  function M._cmdline_enter_handler()
    cmdline_enter_cb()
  end

  function M._cmdline_leave_handler()
    cmdline_leave_cb()
  end
end

function M.setup(opts)
  assert(f.has('nvim-0.6'), 'command-completion.nvim requires Neovim 0.6 or later')

  opts = opts or {}
  for k, v in pairs(opts) do
    if k == 'use_matchfuzzy' and not has_07 then
      print('[command-completion.nvim]: use_matchfuzzy is not supported in this version of Neovim, defaulting to false')
    end
    user_opts[k] = v
  end

  if user_opts.tab_completion then
    if has_07 then
      vim.keymap.set('c', '<Tab>', tab_cb)
    else
      n.nvim_set_keymap(
        'c',
        '<Tab>',
        '<cmd>lua require("command-completion").tab_keymap_handler()<cr>',
        { noremap = true, silent = true }
      )
    end
  end

  if has_07 then
    n.create_autocmd({ 'CmdwinEnter' }, { callback = cmdwin_enter_cb })
    n.create_autocmd({ 'CmdwinLeave' }, { callback = cmdwin_leave_cb })
    enter_aucmd_id = n.create_autocmd({ 'CmdlineEnter' }, { callback = cmdline_enter_cb })
    leave_aucmd_id = n.create_autocmd({ 'CmdlineLeave' }, { callback = cmdline_leave_cb })
  else
    vim.cmd([[ augroup CommandCompletionAugroup ]])
    vim.cmd([[ autocmd CmdwinEnter * lua require('command-completion')._cmdwin_enter_handler() ]])
    vim.cmd([[ autocmd CmdwinLeave * lua require('command-completion')._cmdwin_leave_handler() ]])
    vim.cmd([[ autocmd CmdlineEnter * lua require('command-completion')._cmdline_enter_handler() ]])
    vim.cmd([[ autocmd CmdlineLeave * lua require('command-completion')._cmdline_leave_handler() ]])
    vim.cmd([[ augroup end ]])
  end
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
