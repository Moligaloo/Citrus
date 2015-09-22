#!/usr/bin/env lua

local citrus = require 'citrus'

local file = io.open('sample.citrus')
local content = file:read '*a'
file:close()

local sql = citrus.to_sqlite(content)
if sql == nil then
	print 'Syntax error'
	return
end

file = io.open('sample.sql', 'w')
file:write(sql)
file:close()
