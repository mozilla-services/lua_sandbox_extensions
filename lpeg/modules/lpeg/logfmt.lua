local l = require "lpeg"
l.locale(l)

local empty = l.C("")
local emptytable = l.Ct("")
local whitespace = l.space
local doublequote = l.P("\"")
local escdoublequote = l.P('\\"')
local underscore = l.P("_")
local anyletter = l.R("az")

local key = l.C((anyletter + underscore)^1) * whitespace^0
local val = l.C((1-(whitespace + doublequote))^1) + (doublequote * l.C((escdoublequote + (1 - doublequote))^1) * doublequote)

local separator = whitespace^1
local pair = l.Cg(key * "=" * (val + empty) ) * separator^-1
grammar = l.Cf(emptytable * pair^0, rawset)

return grammar
