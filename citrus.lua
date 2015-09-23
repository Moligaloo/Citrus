local re = require 're'

local function collect_values(func, sep, ...)
	local co = coroutine.create(func)
	local words = {}
	while true do
		local status, value = coroutine.resume(co)
		if value then
			table.insert(words, value)
		else
			break
		end
	end
	return table.concat(words, sep)
end

local yield = coroutine.yield

local function yield_column_def(column_def)
	local column_type = column_def.column_type
	local base_name = column_type.base_name
	local postfixes = column_type.postfixes
	local primary_key = false
	local nullable = false
	local autoincrement = false
	for _, postfix in ipairs(postfixes) do
		if postfix == '!' then
			primary_key = true
			nullable = false
		elseif postfix == '?' then
			nullable = true
		elseif postfix == '++' then
			autoincrement = true
		end
	end

	yield(column_def.column_name)
	yield(base_name)

	if primary_key then
		yield 'primary key'
	end

	if not nullable and not primary_key then
		yield 'not null'
	end

	if autoincrement then
		yield 'autoincrement'
	end
end

local function column_defs_from_columns(columns)
	return collect_values(
		function()
			for _, column_def in ipairs(columns) do
				yield(collect_values(
					function()
						yield_column_def(column_def)
					end,
					' '
				))
			end
		end,
		', '
	)
end

local grammar_string = [[
	statements <- {| statement+ |}
	
	statement <- comment / empty / create_table / insert
	empty <- { [%nl] } 
	comment <- { '--' [^%nl]+ %nl }
	
	create_table <- ({< '+@' {:optional:'?'?:} s {:table_name:identifier:}  {:columns:column_defs:}  >} %nl) -> create_table
	identifier <- [_a-zA-Z][_a-zA-Z0-9]+
	column_defs <- '(' s {| column_def+ |} s ')'
	column_def <- {| {:column_name:identifier:} s ':' s {:column_type:column_type:} |} / (',' s column_def)
	column_type <- {| {:base_name:identifier:} {:postfixes:column_type_postfixes:} |}
	column_type_postfix <- '!' / '?' / '++'
	column_type_postfixes <- {| {column_type_postfix}* |} 
	s <- [%s]*
	
	insert <- {< '+' {:table_name:identifier:} {:key_values:key_values:} >} -> insert
	key_values <- '(' s {| key_value+ |} s ')'
	key_value <- {| {:key:identifier:} s ':' s {:value:value:} |} / (',' s key_value)
	value <- integer_literal / string_literal
	integer_literal <- [0-9]+
	string_literal <- '"' [^"]+ '"'
]]

grammar_string = grammar_string:gsub('{<', '{| {:start:{}:} '):gsub('>}', '{:finish:{}:} |}')

local grammar = re.compile(grammar_string, {
	create_table = function(statement)
		statement.value = 
			("create table %s%s(%s);\n"):format(
				statement.table_name,
				statement.optional == '?' and ' if not exists' or '',
				column_defs_from_columns(statement.columns)
			)

		return statement
	end,
	insert = function(statement)
		local keys, values = {}, {}
		for _, pair in ipairs(statement.key_values) do
			table.insert(keys, pair.key)
			table.insert(values, pair.value)
		end

		statement.value = (("insert into %s(%s) values(%s);"):format(
			statement.table_name,
			table.concat(keys, ', '),
			table.concat(values, ', ')
		))

		return statement
	end
})

local function to_sqlite(content, options)
	options = options or { keep_citrus_as_comment = true}

	local statements = grammar:match(content)
	if statements then
		local strings = {}
		for _, statement in ipairs(statements) do
			if type(statement) == 'string' then
				table.insert(strings, statement)
			else
				if options.keep_citrus_as_comment then
					local start, finish = statement.start, statement.finish
					table.insert(strings, '-- ' .. content:sub(start, finish))
				end
				table.insert(strings, statement.value)
			end
		end

		return table.concat(strings)
	end
end

return {
	to_sqlite = to_sqlite
}
