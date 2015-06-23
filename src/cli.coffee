#!/usr/bin/env coffee
#
# tis100 executable command line interface. bin/cli1000 simply require()s this.

clear = require 'clear'
cluster = require 'cluster'
commander = require 'commander'
debug = require 'debug'
keypress = require 'keypress'
os = require 'os'
util = require 'util'

{Emulator, CheckError, SyntaxError, genetics} = require './index'

debug = debug 'tis100'

inspect = (obj) ->
  ret = util.inspect obj, depth: 5
  ret = ret.replace /(-?\d+,)\n\s*/g, '$1 '
  console.log ret

capture = (fn) ->
  try
    fn()
  catch e
    if e instanceof SyntaxError
      console.log "Error on line #{ e.line } col #{ e.column }:"
      lines = e.contents.split /\n/g
      console.log lines[e.line - 1]
      console.log new Array(e.column).join(' ') + '^'
      console.log e.message
    else if e instanceof CheckError
      console.log "Error in node #{ e.nodeIndex }, instruction #{ e.lineNumber }:"
      console.log "\t", e.raw
      console.log e.message
    else
      console.log e.stack
    process.exit 1

commander.on '--help', ->
  console.log '  Debugging:'
  console.log()
  console.log '    For verbose output / debugging information, run this with DEBUG=tis100 set.'
  console.log()

commander
  .command 'parse <progfile>'
  .description 'Parses the TISasm save file and displays the AST'
  .action (progfile) ->
    emu = new Emulator()
    capture -> emu.load progfile
    inspect emu.ast

commander
  .command 'check <progfile> [specfile]'
  .description 'Checks that the TISasm save file is semantically valid and ' +
    'optionally validates against the given Lua spec'
  .action (progfile, specfile) ->
    emu = new Emulator()
    capture -> emu.load progfile, specfile
    console.log progfile, 'OK'

commander
  .command 'spec <specfile>'
  .description 'Parses the TISasm Lua specification file and prints the config'
  .action (specfile) ->
    emu = new Emulator()
    capture -> emu.load null, specfile
    inspect emu.spec

commander
  .command 'run <progfile> <specfile>'
  .description 'Runs a program against a specification'
  .option('-n, --num-cycles <num>', 'Maximum number of cycles to execute', Number)
  .action (progfile, specfile, {numCycles}) ->
    emu = new Emulator()
    capture -> emu.load progfile, specfile
    if debug.enabled
      debug 'start'
      console.log emu.toString()
      emu.on 'step', -> console.log emu.toString()
    emu.run numCycles
    console.log emu.toString()
    debug 'finished'

commander
  .command 'debug <progfile> <specfile>'
  .description 'Debugs a program interactively (hit Enter to step)'
  .action (progfile, specfile) ->
    emu = new Emulator()
    capture -> emu.load progfile, specfile

    print = ->
      clear() unless debug.enabled
      console.log emu.toString()
      console.log "Hit Enter to continue..."

    keypress process.stdin
    process.stdin.on 'keypress', (ch, key) ->
      emu.step()
      print()

    process.stdin.resume()
    print()

commander
  .command 'breed <specfile>'
  .description 'Interactively breed programs (note argument order)'
  .action (specfile, progfile) ->
    emu = new Emulator()
    capture -> emu.load null, specfile
    {layout, layoutWidth, streams} = emu.spec

    if not emu.ast
      ast = genetics.generateSomewhatCorrectAST emu, layout, layoutWidth, streams

    print = ->
      clear() unless debug.enabled
      console.log emu.toString()
      console.log "Keys: (m)utate (c)rossover (a)lter (q)uit"

    process.stdin.setRawMode true
    keypress process.stdin
    process.stdin.on 'keypress', (ch, key) ->
      process.exit() if (key?.ctrl and key?.name is 'c') or key?.name is 'q'

      switch key?.name
        when 'm'
          console.log 'Mutating...'
          ast = genetics.mutateAST ast
        when 'a'
          console.log 'Altering...'
          ast = genetics.alterAST ast
        when 'c'
          console.log 'Crossovering...'
          other = genetics.generateSomewhatCorrectAST emu, layout, streams
          ast = genetics.crossoverAST ast, other

      console.log 'Running...'
      emu.ast = ast
      emu.reset()
      emu.run()
      print()

    process.stdin.resume()
    print()

commander
  .command 'solve <specfile>'
  .description 'Attempts to solve the specification through genetic programming'
  .option('-c, --children <num>', 'Number of children per generation', Number, 20)
  .option('-k, --maxRunCycles <num>', 'Maximum number of cycles to emulate per child', Number, 1000)
  .option('-p, --parents <num>', 'Number of parents to pick from each generation', Number, 2)
  .option('-m, --mutation <percent>', 'Probability of mutation', Number, 0.05)
  .option('-x, --crossover <percent>', 'Probability of crossover', Number, 0.85)
  .option('-r, --reproduction <percent>', 'Probability of reproduction', Number, 0.09)
  .option('-a, --alteration <percent>', 'Probability of architecture alteration', Number, 0.01)
  .action (specfile, options) ->
    #if cluster.isMaster
      #for i in [0...os.cpus().length]
        #cluster.fork()
    #else
    genetics.solve specfile, options

commander
  .command '*'
  .action ->
    console.log "Unknown command: #{ commander.args[0] }"
    process.exit(1)

commander.parse process.argv
commander.help() unless commander.args[1]
