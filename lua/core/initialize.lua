local Initialize = {}

function Initialize.get_nvim_commands()
	return setmetatable({}, {
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
end

return Initialize
