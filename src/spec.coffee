#!/usr/bin/env coffee
#
# Loads TIS-100 specifications from Lua.
#
# TODO: Lua random numbers seem to be deterministic (seeded from the same
# value). That's what we want, but I don't know why it's happening, and it
# should at least be configurable.

fs = require 'fs'
intercept = require 'intercept-stdout'
pathlib = require 'path'
{Lua} = require 'lua.vm.js'

state = new Lua.State()

# A cheesy hack to get `JSON` in the global Lua scope without modifying the source.
jsonLua = fs.readFileSync(pathlib.join(__dirname, 'JSON.lua'), 'utf8')
jsonLua = jsonLua.replace /local OBJDEF = {[^}]+}/, (match) ->
  match + '\nJSON = OBJDEF\n'

# Constants used by the spec scripts. We want this as strings, not nil.
constants = [
  'STREAM_INPUT'
  'STREAM_OUTPUT'
  'TILE_COMPUTE'
  'TILE_MEMORY'
  'TILE_DAMAGED'
]
constantsLua = ("#{k} = \"#{k}\"\n" for k in constants).join ''

exports.parse = (contents) ->

  catchLuaError = (fn) ->
    try
      fn()
    catch err
      throw new Error("Error in Lua spec: #{ err.message }\n#{ err.lua_stack }")

  captureOutput = (code) ->
    buf = ""
    try
      unhook = intercept (chunk) ->
        buf += chunk
        return '' # Don't print anything.
      catchLuaError -> state.execute code
    finally
      unhook()
    try
      return JSON.parse buf
    catch e
      throw new Error("Couldn't parse results of code '#{ code }': #{ buf }")

  catchLuaError ->
    state.execute constantsLua
    state.execute contents
    state.execute jsonLua

  call = (name) ->
    return captureOutput "print(JSON:encode(#{ name }()))"

  # Support non-standard layout sizes.
  try
    layoutWidth = call 'get_layout_width'
  catch e
    layoutWidth = 4
  layout = call 'get_layout'
  streams = call 'get_streams'

  # Simple checks.
  if layoutWidth <= 0
    throw new Error("Layout width must be > 0 (was #{ layoutWidth })")
  if layout.length < layoutWidth
    throw new Error("Layout must specify at least #{ layoutWidth } nodes (got #{ layout.length })")
  if layout.length % layoutWidth
    throw new Error("Layout must specify multiple of #{ layoutWidth } nodes")
  for type, i in layout
    if type not in ['TILE_COMPUTE', 'TILE_DAMAGED', 'TILE_MEMORY']
      throw new Error("Unknown tile type '#{ type }' at node #{ i }")
  for [type, name, index, stream], i in streams
    if type not in ['STREAM_INPUT', 'STREAM_OUTPUT']
      throw new Error("Unknown stream type '#{ type }' at stream #{ i }")
    if not /\S/.test name
      throw new Error("Stream #{ i } needs a name")
    if index < 0 or index >= layoutWidth
      throw new Error("Stream #{ i } position must be between 0 and #{ layoutWidth - 1 }")

  return {
    name: call 'get_name'
    description: call 'get_description'
    streams: streams
    layout: layout
    layoutWidth: layoutWidth
  }
