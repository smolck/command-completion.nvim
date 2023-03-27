local Calculator = {}

function Calculator.calculate_column_width(total_columns)
	local col_width

	col_width = math.floor(vim.o.columns / total_columns)

	return col_width
end

return Calculator
