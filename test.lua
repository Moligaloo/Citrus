#!/usr/bin/env lua

local luaunit = require 'luaunit'
local assertEquals = luaunit.assertEquals

local citrus = require 'citrus'
local ae = function(citrus_code_without_newline, sql_code_without_semicolon_and_newline)
	local citrus_code = citrus_code_without_newline .. '\n'
	local result_code = citrus.to_sqlite(citrus_code, {keep_citrus_as_comment = false})
	assertEquals(result_code, sql_code_without_semicolon_and_newline .. ';\n')
end

function test_create_table()
	ae(
		'+@?users(id: integer!++, name:text, gender:integer, location: text?)',
		'create table if not exists users(\n\tid integer primary key autoincrement,\n\tname text not null,\n\tgender integer not null,\n\tlocation text\n)'
	)

	ae(
		'+@users(id: integer!++, name:text, gender:integer, location: text?)',
		'create table users(\n\tid integer primary key autoincrement,\n\tname text not null,\n\tgender integer not null,\n\tlocation text\n)'
	)
end

function test_drop_table()
	ae('-@users', 'drop table users')
	ae('-@?users', 'drop table if exists users')
end

function test_insert()
	ae([[+users(name: "Moligaloo", gender: 'male', age: 22)]], [[insert into users(name, gender, age) values("Moligaloo", 'male', 22)]])
end

function test_select()
	ae('users', 'select * from users')
	ae('*@users', 'select * from users')
	ae('name@users#123', 'select name from users where id = 123')
	ae('name@users', 'select name from users')
	ae('name@users>id', 'select name from users order by id desc')
	ae('name@users>id<name', 'select name from users order by id desc, name asc')
	ae('name@users^10', 'select name from users limit 10')
	ae('name@users+20', 'select name from users offset 20')
	ae('name@users+20^10', 'select name from users limit 10 offset 20')
	ae('id,name@users', 'select id, name from users')
	ae('name@users[age>18]', 'select name from users where age > 18')
	ae('name@users[age<18]', 'select name from users where age < 18')
	ae('name@users[age<>18]', 'select name from users where age <> 18')
	ae('name@users[age!=18]', 'select name from users where age <> 18')
	ae('name@users[age>=18]', 'select name from users where age >= 18')
	ae('name@users[age<=18]', 'select name from users where age <= 18')
	ae('name@users[location != null]', 'select name from users where location notnull')
	ae('name@users[location != NULL]', 'select name from users where location notnull')
	ae('name@users[location == null]', 'select name from users where location isnull')
	ae('name@users[location = null]', 'select name from users where location isnull')
end

function test_update()
	ae('location="Shanghai"@users[id=123]', 'update users set location = "Shanghai" where id = 123')
	ae('age=18@users', 'update users set age = 18')
end

function test_delete()
	ae('-users', 'delete from users')
	ae('-users[location = "Shanghai"]', 'delete from users where location = "Shanghai"')
	ae('-users#123', 'delete from users where id = 123')
end

os.exit(luaunit.LuaUnit.run())