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
		',\n\t'
	)
end

local function expand(format, vars)
	return format:gsub('$([%w_]+)', vars)
end

local grammar_string = [[
	statements <- {| statement+ |}
	
	statement <- comment / empty / create_table / insert / select / select_all / drop_table / delete / update
	empty <- { [%nl] } 
	comment <- { '--' [^%nl]+ %nl }
	
	create_table <- ({< '+@' {:optional:'?'?:} s {:table_name:identifier:}  {:columns:column_defs:}  >} &%nl) -> create_table
	identifier <- [_a-zA-Z][_a-zA-Z0-9]+
	column_defs <- '(' s {| column_def+ |} s ')'
	column_def <- {| {:column_name:identifier:} s ':' s {:column_type:column_type:} |} / (',' s column_def)
	column_type <- {| {:base_name:identifier:} {:postfixes:column_type_postfixes:} |}
	column_type_postfix <- '!' / '?' / '++'
	column_type_postfixes <- {| {column_type_postfix}* |} 
	s <- [%s]*
	
	insert <- {< '+' {:table_name:identifier:} {:key_values:key_values:} &%nl >} -> insert
	key_values <- '(' s {| key_value+ |} s ')'
	key_value <- {| {:key:identifier:} s ':' s {:value:value:} |} (s ',' s)?
	value <- integer_literal / string_literal / identifier
	integer_literal <- [0-9]+
	string_literal <- '"' [^"]+ '"'

	select <- {< {:fields:fields:} s '@' s {:table_name:identifier:} {:where_clause:where_clause?:} &%nl >}-> select
	fields <- LIST(field,',')
	field <- identifier
	where_clause <- ('[' s {| where_expr |} s ']') / {| id_expr |}
	where_expr <- equation_expr
	equation_expr <- {| {:type:''->'equation':} {:left:value:} s '=' s {:right:value:} |}
	id_expr <- {| {:type:''->'id':} '#' {:value:value:} |}

	select_all <- ( {< {:table_name:identifier:} >} & %nl) -> select_all

	drop_table <- ({< '-@' {:optional:'?'?:} {:table_name:identifier:} >} &%nl) -> drop_table

	delete <- {< '-' {:table_name:identifier:} {:where_clause:where_clause:} &%nl >}  -> delete

	update <- ({< {:update_pairs:update_pairs:} s '@' s {:table_name:identifier:} {:where_clause:where_clause:} >} %nl ) -> update
	update_pairs <- {| update_pair+ |}
	update_pair <- {| {:field_name:identifier:} s '=' s {:value:value:}  (s ',' s)? |}
]]

grammar_string = grammar_string:
	gsub('{<', '{| {:start:{}:} '):
	gsub('>}', '{:finish:{}:} |}'):
	gsub('LIST%(([%w]+)%s*,%s*([^%)]+)%)', function(elem, sep)
		return ('{| {%s} (s %s s {%s})* |}'):format(elem, sep, elem)
	end)

local function wrap_defs(defs)
	for name, func in pairs(defs) do
		defs[name] = function(statement)
			statement.value = func(statement)
			return statement
		end
	end
	return defs
end

local function where_clause_to_string(where_clause)
	if where_clause == '' then
		return ''
	end
	local words = { ' where'}
	for _, expression in ipairs(where_clause) do
		if expression.type == 'equation' then
			table.insert(words, ("%s = %s"):format(expression.left, expression.right))
		elseif expression.type == 'id' then
			table.insert(words, 'id = ' .. expression.value)
		end
	end
	return table.concat(words, ' ')
end

local function update_pairs_to_string(update_pairs)
	local words = {}
	for _, pair in pairs(update_pairs) do
		table.insert(words, ("%s = %s"):format(pair.field_name, pair.value))
	end
	return table.concat(words, ', ')
end

local grammar = re.compile(grammar_string, wrap_defs {
	create_table = function(statement)
		return
			("create table %s%s(\n\t%s\n);"):format(
				statement.optional == '?' and 'if not exists ' or '',
				statement.table_name,
				column_defs_from_columns(statement.columns)
			)
	end,
	insert = function(statement)
		local keys, values = {}, {}
		for _, pair in ipairs(statement.key_values) do
			table.insert(keys, pair.key)
			table.insert(values, pair.value)
		end

		return (("insert into %s(%s) values(%s);"):format(
			statement.table_name,
			table.concat(keys, ', '),
			table.concat(values, ', ')
		))
	end,
	select = function(statement)
		return ("select %s from %s%s;"):format(
			table.concat(statement.fields, ','),
			statement.table_name,
			where_clause_to_string(statement.where_clause)
		)
	end,
	select_all = function(statement)
		return expand('select * from $table_name;', statement)
	end,
	drop_table = function(statement)
		if statement.optional == '?' then
			return expand("drop table if exists $table_name;", statement)
		else
			return expand("drop table $table_name;", statement)
		end
	end,
	delete = function(statement)
		return ('delete from %s%s;'):format(statement.table_name, where_clause_to_string(statement.where_clause))
	end,
	update = function(statement)
		return ('update %s set %s%s;\n'):format(
			statement.table_name, 
			update_pairs_to_string(statement.update_pairs),
			where_clause_to_string(statement.where_clause)
		)
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
