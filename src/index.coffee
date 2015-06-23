#!/usr/bin/env coffee
#
# Module entry point

{Emulator, CheckError} = require './emulator'
parserlib = require './asm-parser'
speclib = require './spec'
genetics = require './genetics'

exports.Emulator = Emulator
exports.CheckError = CheckError
exports.SyntaxError = parserlib.SyntaxError
exports.genetics = genetics
exports.parseProgram = parserlib.parse
exports.parseSpec = speclib.parse
