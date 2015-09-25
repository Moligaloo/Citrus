#!/usr/bin/env lua

EXPORT_ASSERT_TO_GLOBALS = true
local luaunit = require 'luaunit'

local citrus = require 'citrus'
local convert = function(citrus_code)
	return citrus.to_sqlite(citrus_code, {keep_citrus_as_comment = false})
end

function test_create_table()
	assertEquals(
		convert(
			'+@?users(id: integer!++, name:text, gender:integer, location: text?)\n'
		), 
		'create table if not exists users(\n\tid integer primary key autoincrement,\n\tname text not null,\n\tgender integer not null,\n\tlocation text\n);\n'
	)

	assertEquals(
		convert(
			'+@users(id: integer!++, name:text, gender:integer, location: text?)\n'
		), 
		'create table users(\n\tid integer primary key autoincrement,\n\tname text not null,\n\tgender integer not null,\n\tlocation text\n);\n'
	)
end

function test_drop_table()
	assertEquals(convert('-@users\n'), 'drop table users;\n')
	assertEquals(convert('-@?users\n'), 'drop table if exists users;\n')
end

function test_insert()
	assertEquals(convert('+users(name: "Moligaloo", gender: "male")\n'), 'insert into users(name, gender) values("Moligaloo", "male");\n')
end

function test_select()
	assertEquals(convert('users\n'), 'select * from users;\n')
	assertEquals(convert('*@users\n'), 'select * from users;\n')
	assertEquals(convert('name@users#123\n'), 'select name from users where id = 123;\n')
	assertEquals(convert('name@users\n'), 'select name from users;\n')
	assertEquals(convert('name@users>id\n'), 'select name from users order by id desc;\n')
	assertEquals(convert('name@users>id<name\n'), 'select name from users order by id desc, name asc;\n')
	assertEquals(convert('name@users^10\n'), 'select name from users limit 10;\n')
	assertEquals(convert('name@users+20\n'), 'select name from users offset 20;\n')
	assertEquals(convert('name@users+20^10\n'), 'select name from users limit 10 offset 20;\n')
	assertEquals(convert('id,name@users\n'), 'select id, name from users;\n')
end

function test_delete()
	assertEquals(convert('-users[location = "Shanghai"]\n'), 'delete from users where location = "Shanghai";\n')
end

os.exit(luaunit.LuaUnit.run())