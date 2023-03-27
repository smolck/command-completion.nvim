local f = vim.fn

local Completion = {}

local current_completions = {}

function Completion.set_current_completions_empty()
	current_completions = {}
end

function Completion.set_current_completions(completions)
	current_completions = completions
end

function Completion.get_current_completions()
	return current_completions
end

local Calculator = require('ui.calculate_win')

function Completion.map_completions_with_directory_flag(completions, total_columns)
  return vim.tbl_map(function (c)
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

	local shift_for_space = 4
	local col_width = Calculator.calculate_column_width(total_columns)
	if string.len(ret) >= col_width then
	  ret = string.sub(ret, 1, col_width - shift_for_space) .. '...'
	end

	return { completion = ret, is_directory = is_directory, full_completion = c }
	end, completions)
end

function Completion.get_completions(has_matchfuzzy)
    local input = f.getcmdline()
    local completions = f.getcompletion(input, 'cmdline')

    -- TODO(smolck): No clue if this really helps much if at all but we'll use it
    -- by default for now
    if has_matchfuzzy and input ~= '' then
      local split = vim.split(input, ' ')
      local str_to_match = split[#split]

      completions = vim.fn.matchfuzzy(completions, str_to_match)
    end

	return completions
end

return Completion
