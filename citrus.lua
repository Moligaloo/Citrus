local re = require 're'

local grammar = re.compile [[
	statements <- {| statement+ |}
	
	statement <- comment / empty / create_table / insert
	empty <- { [%nl] } 
	comment <- { '--' [^%nl]+ %nl }
	
	create_table <- {| {:type: '' -> 'create_table':} '+@' s {:table_name:identifier:} {:optional:'?'?:} {:columns:column_defs:} %nl |}
	identifier <- [_a-zA-Z][_a-zA-Z0-9]+
	column_defs <- '(' s {| column_def+ |} s ')'
	column_def <- {| {:column_name:identifier:} s ':' s {:column_type:column_type:} |} / (',' s column_def)
	column_type <- {| {:base_name:identifier:} {:postfixes:column_type_postfixes:} |}
	column_type_postfix <- '!' / '?' / '++'
	column_type_postfixes <- {| {column_type_postfix}* |} 
	s <- [ ]*
	
	insert <- {| {:type: '' -> 'insert':} '+' {:table_name:identifier:} {:key_values:key_values:} |}
	key_values <- '(' s {| key_value+ |} s ')'
	key_value <- {| {:key:identifier:} s ':' s {:value:value:} |} / (',' s key_value)
	value <- integer_literal / string_literal
	integer_literal <- [0-9]+
	string_literal <- '"' [^"]+ '"'
]]

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

local function to_sqlite(content)
	local statements = grammar:match(content)
	if statements == nil then
		return
	end

	return collect_values(
		function()
			for _, statement in ipairs(statements) do
				if type(statement) == 'string' then
					yield(statement)
				end

				local type = statement.type
				if type == 'comment' then
					yield("--" .. statement.content)
				elseif type == 'empty' then
					yield ''
				elseif type == 'create_table' then
					yield(
						collect_values(
							function() 
								yield 'create table '
								yield(statement.table_name)
								if statement.optional == '?' then
									yield ' if not exists'
								end
								yield(("(%s);\n"):format(column_defs_from_columns(statement.columns)))
							end, 
							''
						)
					)
				elseif type == 'insert' then
					local keys, values = {}, {}
					for _, pair in ipairs(statement.key_values) do
						table.insert(keys, pair.key)
						table.insert(values, pair.value)
					end

					yield(("insert into %s(%s) values(%s);"):format(
						statement.table_name,
						table.concat(keys, ', '),
						table.concat(values, ', ')
					))
				end
			end
		end,
		''
	)
end

return {
	to_sqlite = to_sqlite
}
