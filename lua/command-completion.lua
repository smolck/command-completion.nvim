local M = {}

local nvim_commands = require('core.initialize').get_nvim_commands()
local window = require("ui.window")
window.set_nvim_commands(nvim_commands)
window.prepare_namespaces()

local completion = require('core.completion')

local user_opts = {
  border = nil,
  total_columns = 5,
  total_rows = 3,
  use_matchfuzzy = true,
  highlight_selection = true,
  highlight_directories = true,
  mapping_next = "<Tab>",
  mapping_prev = "<S-Tab>",
  completion = true,
}

window.set_current_selection(1)
local debounce_timer
local in_that_cursed_cmdwin = false
local enter_aucmd_id, leave_aucmd_id

local function setup_handlers()
  debounce_timer = nil
  if in_that_cursed_cmdwin then
    return
  end

  local empty_lines = user_opts.total_rows - 1
  local height = user_opts.total_rows + empty_lines

  window.open_and_setup_win(user_opts.border, height)

  local table_win = window.create_blank_table(height)

  local function autocmd_cb()
    if window.is_cmdline_changed_disabled() then
      return
    end

    if not window.get_winid() then
      window.open_and_setup_win(user_opts.border, height)
    end

	window.clear_window(height, table_win)

	local has_matchfuzzy = user_opts.use_matchfuzzy
	local completions = completion.get_completions(has_matchfuzzy)

    -- TODO(smolck): This *should* only apply to suggestions that are files, but
    -- I'm not totally sure if that's right so might need to be properly tested.
    -- (Or maybe find a better way of cutting down filepath suggestions to their tails?)
    completions = completion.map_completions_with_directory_flag(completions, user_opts.total_columns)

	completion.set_current_completions_empty()
	window.set_current_selection(-1)

    -- Don't show completion window if there are no completions.
	local no_completions = window.dont_show_if_no_completions(completions)
	if no_completions then
		return
	end

	completion.set_current_completions(window.render_window(completion.get_current_completions(), completions, user_opts.total_rows, user_opts.total_columns))
  end

  M.cmdline_changed_autocmd = nvim_commands.create_autocmd({ 'CmdlineChanged' }, {
    callback = autocmd_cb,
  })

  -- Initial completions when cmdline is already open and empty
  autocmd_cb()
end

local function teardown_handlers()
  if M.cmdline_changed_autocmd then
    nvim_commands.del_autocmd(M.cmdline_changed_autocmd)
    M.cmdline_changed_autocmd = nil
  end
  if window.get_winid() then -- TODO(smolck): Check if nvim_commands.win_is_valid(window.winid)?
    if in_that_cursed_cmdwin then
      nvim_commands.win_hide(window.get_winid()) -- Idk but it works (EDIT: NOT REALLY this is probably quite bad, so prepare for breakge
                          -- just gotta fix this upstream I guess by making cmdwin sane with float and stuff
                          -- TODO(smolck): come back once you've hopefully done that upstream)
    else
      nvim_commands.win_close(window.get_winid(), true)
    end
  end
  window.set_winid(nil)
  window.set_current_selection(1)

  local wbufnr = window.get_wbufnr()
  if wbufnr then
    nvim_commands.buf_set_lines(wbufnr, 0, -1, true, {})
  end
end

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    user_opts[k] = v
  end

  window.set_highlight_selection(user_opts.highlight_selection)
  window.set_highlight_directories(user_opts.highlight_directories)

  if user_opts.completion then
    vim.keymap.set('c', user_opts.mapping_next, function()
		window.select_next(completion.get_current_completions())
    end)

    vim.keymap.set('c', user_opts.mapping_prev, function()
		window.select_prev(completion.get_current_completions())
    end)
  end

  nvim_commands.create_autocmd({ 'CmdwinEnter' }, {
    callback = function()
      in_that_cursed_cmdwin = true

      -- Could also be entering cmdwin from cmdline so handle that
      if window.get_winid() then
        teardown_handlers()
      end
    end,
  })
  nvim_commands.create_autocmd({ 'CmdwinLeave' }, {
    callback = function()
      in_that_cursed_cmdwin = false
    end,
  })
  enter_aucmd_id = nvim_commands.create_autocmd({ 'CmdlineEnter' }, {
    callback = function()
      if vim.v.event.cmdtype == ':' then
        debounce_timer = vim.defer_fn(setup_handlers, 100) -- TODO(smolck): Make this time configurable?
      end
    end,
  })
  leave_aucmd_id = nvim_commands.create_autocmd({ 'CmdlineLeave' }, {
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
    nvim_commands.del_autocmd(enter_aucmd_id)
    enter_aucmd_id = nil
  end

  if leave_aucmd_id then
    nvim_commands.del_autocmd(leave_aucmd_id)
    leave_aucmd_id = nil
  end

  vim.keymap.del('c', user_opts.mapping_next)
  vim.keymap.del('c', user_opts.mapping_prev)
end

return M
