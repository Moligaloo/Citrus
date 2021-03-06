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
	local string = format:gsub('$([%w_]+)', vars)
	return string
end

local grammar_string = ([[
	statements <- {| statement+ |}
	
	statement <- comment / empty / create_table / insert / select_all / select / drop_table / delete / update
	empty <- { [%nl] } 
	comment <- { '--' [^%nl]+ %nl }

	SQL:create_table '+@' {:optional:'?'?:} s {:table_name:identifier:}  {:columns:column_defs:}
	identifier <- !(reserved_words) [_a-zA-Z][_a-zA-Z0-9]+
	column_defs <- '(' s {| column_def+ |} s ')'
	column_def <- {| {:column_name:identifier:} s ':' s {:column_type:column_type:} |} / (',' s column_def)
	column_type <- {| {:base_name:identifier:} {:postfixes:column_type_postfixes:} |}
	column_type_postfix <- '!' / '?' / '++'
	column_type_postfixes <- {| {column_type_postfix}* |} 
	reserved_words <- null_value
	s <- [%s]*
	
	SQL:insert '+' {:table_name:identifier:} {:key_values:key_values:} 
	key_values <- '(' s {| key_value+ |} s ')'
	key_value <- {| {:key:identifier:} s ':' s {:value:value:} |} (s ',' s)?
	value <- integer_literal / string_literal / identifier / null_value
	integer_literal <- [0-9]+
	string_literal <- ('"' [^"]+ '"') / ("'" [^']+ "'")
	null_value <- {| {:type:('null' / 'NULL')->'null':} |}
 
	SQL:select ({:csv:csv:} / {:csv:'*':}) &'@' {:modifiers:modifiers?:} 
	csv <- {| ({value} (s ',' s)?)+ |}
	where_clause <- ('[' s {| expr |} s ']') / {| id_expr |}
	expr <- compare_expr
	compare_expr <- {| {:type:''->'compare_expr':} {:left:value:} s {:compare_op:compare_op:} s {:right:value:} |}
	compare_op <- '<>' / ('!=' -> '<>') / '>=' / '<=' / '<' / '>' / ('==' -> '=' / '=') 
	id_expr <- {| {:type:''->'id':} '#' {:value:value:} |}
	modifiers <- {| {modifier}+ |}
	modifier <- asc_modifier / desc_modifier / where_modifier / from_modifier / limit_modifer / offset_modifier
	where_modifier <- {| {:where_clause:where_clause:} |}
	asc_modifier <-  {| s '<' s {:asc:identifier:} |}
	desc_modifier <- {| s '>' s {:desc:identifier:} |}
	from_modifier <- {| s '@' s {:from:identifier:} |}
	limit_modifer <- {| s '^' s {:limit:integer_literal:} |}
	offset_modifier <- {| s '+' s {:offset:integer_literal:} |}

	SQL:select_all {:table_name:identifier:} 

	SQL:drop_table '-@' {:optional:'?'?:} {:table_name:identifier:} 

	SQL:delete '-' {:table_name:identifier:} {:where_clause:where_clause?:}

	SQL:update {:update_pairs:update_pairs:} s '@' s {:table_name:identifier:} {:where_clause:where_clause?:} 
	update_pairs <- {| update_pair+ |}
	update_pair <- {| {:field_name:identifier:} s '=' s {:value:value:}  (s ',' s)? |}
]]):gsub(
	'SQL:([%w_]+)%s+([^\n]+)', 
	'%1 <- ({| %2 |} &%%nl ) -> %1'
)
	
local json = require 'dkjson'

local function where_clause_to_string(where_clause, options)
	options = options or { prepend_space = false }
	if where_clause == '' then
		return ''
	end
	local words = { options.prepend_space and ' where' or 'where'}
	for _, expression in ipairs(where_clause) do
		if expression.type == 'compare_expr' then
			-- special case
			local special_case = false

			if  expression.right.type == 'null' then
				local compare_op = expression.compare_op
				if compare_op == '<>' then
					table.insert(words, expression.left .. ' notnull')
					special_case = true
				elseif compare_op == '=' then
					table.insert(words, expression.left .. ' isnull')
					special_case = true
				end
			end

			if not special_case then
				table.insert(words, expand('$left $compare_op $right', expression))
			end
		elseif expression.type == 'id' then
			table.insert(words, 'id = ' .. expression.value)
		end
	end
	return table.concat(words, ' ')
end

local function modifiers_to_string(modifiers)
	if modifiers == '' then
		return ''
	end

	local order_items = {}
	local where_string, from_string
	local limit, offset
	for _, modifier in ipairs(modifiers) do
		if modifier.asc then
			table.insert(order_items, ('%s asc'):format(modifier.asc))
		elseif modifier.desc then
			table.insert(order_items, ('%s desc'):format(modifier.desc))
		elseif modifier.where_clause then
			where_string = where_clause_to_string(modifier.where_clause)
		elseif modifier.from then
			from_string = 'from ' .. modifier.from
		elseif modifier.limit then
			if limit then
				error 'only one limit allowed'
			end
			limit = modifier.limit
		elseif modifier.offset then
			if offset then
				error 'only one offset allowed'
			end
			offset = modifier.offset
		end
	end

	local words = {}
	if from_string then
		table.insert(words, from_string)
	end

	if where_string then
		table.insert(words, where_string)
	end

	if next(order_items) then
		table.insert(words, 'order by ' .. table.concat(order_items, ', '))
	end

	if limit then
		table.insert(words, 'limit ' .. limit)
	end

	if offset then
		table.insert(words, 'offset ' .. offset)
	end

	return table.concat(words, ' ')
end

local function csv_to_string(csv)
	return csv == '*' and '*' or table.concat(csv, ', ')
end

local function update_pairs_to_string(update_pairs)
	local words = {}
	for _, pair in pairs(update_pairs) do
		table.insert(words, ("%s = %s"):format(pair.field_name, pair.value))
	end
	return table.concat(words, ', ')
end

local grammar = re.compile(grammar_string, {
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
		return ("select %s %s;"):format(
			csv_to_string(statement.csv),
			modifiers_to_string(statement.modifiers)
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
		return ('delete from %s%s;'):format(
			statement.table_name, 
			where_clause_to_string(statement.where_clause, {prepend_space = true})
		)
	end,
	update = function(statement)
		return expand(
			'update $table_name set $update_pairs$where_clause;',
			{
				table_name = statement.table_name,
				update_pairs = update_pairs_to_string(statement.update_pairs),
				where_clause = where_clause_to_string(statement.where_clause, {prepend_space = true})
			}
		)
	end
})

local function to_sqlite(content)
	local statements = grammar:match(content)
	if statements then
		return table.concat(statements)
	end
end

return {
	to_sqlite = to_sqlite
}
