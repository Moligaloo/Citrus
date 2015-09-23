#!/usr/bin/env lua

local citrus = require 'citrus'

if #arg >= 1 then
	io.input(arg[1])
	if #arg >= 2 then
		io.output(arg[2])
	end
end

local content = io.input():read '*a'

local sql = citrus.to_sqlite(content)
if sql == nil then
	print 'Syntax error'
	return
end

io.write(sql)
