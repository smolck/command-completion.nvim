local Window = {}

local window_current_selection
local window_nvim_commands
local window_bufnr
local window_id

local window_highlight_selection
local window_highlight_directories

local window_search_hl_nsid
local window_directory_hl_nsid

local cmdline_changed_disabled

function Window.set_nvim_commands(nvim_commands)
	window_nvim_commands = nvim_commands
end

function Window.set_wbufnr(wbufnr)
	window_bufnr = wbufnr
end

function Window.get_wbufnr()
	return window_bufnr
end

function Window.set_winid(winid)
	window_id = winid
end

function Window.get_winid()
	return window_id
end

function Window.set_current_selection(current_selection)
	window_current_selection = current_selection
end

function Window.get_current_selection()
	return window_current_selection
end

function Window.set_highlight_selection(highlight_selection)
	window_highlight_selection = highlight_selection
end

function Window.set_highlight_directories(highlight_directories)
	window_highlight_directories = highlight_directories
end

function Window.is_cmdline_changed_disabled()
	return cmdline_changed_disabled
end

function Window.prepare_namespaces()
	if window_nvim_commands == nil then
		error("Not setted nvim commands for window.")
	end
	window_search_hl_nsid = window_nvim_commands.create_namespace('__ccs_hls_namespace_search___')
	window_directory_hl_nsid = window_nvim_commands.create_namespace('__ccs_hls_namespace_directory___')
end

function Window.open_and_setup_win(border, height)
  if not window_bufnr then
    window_bufnr = window_nvim_commands.create_buf(false, true)
  end

  window_id = window_nvim_commands.open_win(window_bufnr, false, {
    relative = 'editor',
    border = border,
    style = 'minimal',
    width = vim.o.columns,
    height = height,
    row = vim.o.lines - 2,
    col = 0,
  })

  vim.cmd('redraw')
end

local Calculator = require('ui.calculate_win')

function Window.render_window(current_completions, completions, total_rows, total_columns)
	local col_width = Calculator.calculate_column_width(total_columns)
	local completion_index = 1
	for line = 0, total_rows - 1 do
	  for column = 0, total_columns - 1 do
		if completion_index > #completions then
		  break
		end
		local left_bound_column = column * col_width
		local right_bound_column = left_bound_column + string.len(completions[completion_index].completion)
		if right_bound_column > vim.o.columns then
		  break
		end
		window_nvim_commands.buf_set_text(window_bufnr, line, left_bound_column, line, right_bound_column, { completions[completion_index].completion })

		current_completions[completion_index] = {
		  start = { line, left_bound_column },
		  finish = { line, right_bound_column },
		  full_completion = completions[completion_index].full_completion,
		}

		if completion_index == window_current_selection and window_highlight_selection then
		  vim.highlight.range(window_bufnr, window_search_hl_nsid, 'Search', { line, left_bound_column }, { line, right_bound_column }, {})
		end

		if completions[completion_index].is_directory and window_highlight_directories then
		  vim.highlight.range(
			window_bufnr,
			window_directory_hl_nsid,
			'Directory',
			{ line, left_bound_column },
			{ line, right_bound_column },
			{}
		  )
		end

		completion_index = completion_index + 1
	  end
	end
	local rows = math.floor(#completions / total_columns)
	local rows_with_spaces = rows * 2 - 1
	if rows_with_spaces < 0 then
		rows_with_spaces = 0
	end
	local height = total_rows * 2 - 1
	window_nvim_commands.win_set_height(window_id, math.min(rows_with_spaces, height))
	vim.cmd('redraw')

	return current_completions
end

function Window.clear_window(height, table_win)
    window_nvim_commands.buf_set_lines(window_bufnr, 0, height, false, table_win)
end

function Window.create_blank_table(height)
	local blank_table = {}
	for _ = 0, height - 1 do
		blank_table[#blank_table+1] = (' '):rep(vim.o.columns)
	end
	return blank_table
end

function Window.dont_show_if_no_completions(completions)
    if vim.tbl_isempty(completions) then
      window_nvim_commands.win_close(window_id, true)
      window_id = nil

      return true
    end
	return false
end

local function replace_last_word_next_matches(current_completions)
  -- TODO(smolck): Re-visit this when/if https://github.com/neovim/neovim/pull/18096 is merged.
  local cmdline = vim.fn.getcmdline()
  local words_from_cmd = vim.split(cmdline, ' ')
  local last_word_len = string.len(words_from_cmd[#words_from_cmd])

  cmdline_changed_disabled = true
  vim.api.nvim_input(('<BS>'):rep(last_word_len) .. current_completions[window_current_selection].full_completion)
end

local function change_item(current_completions)
	window_nvim_commands.buf_clear_namespace(window_bufnr, window_search_hl_nsid, 0, -1)

	print(window_search_hl_nsid)
	vim.highlight.range(
		window_bufnr,
		window_search_hl_nsid,
		'Search',
		current_completions[window_current_selection].start,
		current_completions[window_current_selection].finish,
		{})
	vim.cmd('redraw!')

	replace_last_word_next_matches(current_completions)

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

function Window.select_next(current_completions)
      if vim.tbl_isempty(current_completions) then
        window_current_selection = 1
        return
      end

      if window_current_selection == -1 then
        -- TODO(smolck): This comment might not *quite* be accurate.
        -- Means we just reset this back to the first completion from the CmdlineChanged autocmd
        window_current_selection = 1
      else
        window_current_selection = window_current_selection + 1 > #current_completions and 1 or window_current_selection + 1
      end

	  change_item(current_completions)
end

function Window.select_prev(current_completions)
      if vim.tbl_isempty(current_completions) then
        window_current_selection = 1
        return
      end

      if window_current_selection == -1 then
        -- TODO(smolck): This comment might not *quite* be accurate.
        -- Means we just reset this back to the first completion from the CmdlineChanged autocmd
        window_current_selection = 1
      else
        window_current_selection = window_current_selection - 1 <= 0 and #current_completions or window_current_selection - 1
      end

	change_item(current_completions)
end

return Window
