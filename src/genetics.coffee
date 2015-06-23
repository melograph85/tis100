#!/usr/bin/env coffee
#
# Functions for generating programs.
#
# References:
# - http://www.genetic-programming.com/
# - http://rednuht.org/genetic_walkers/
# - http://rednuht.org/genetic_cars_2/
#
# TODO:
# - Better intuition when growing/altering programs

Random = require 'random-js'
clone = require 'clone'
cluster = require 'cluster'
debug = require 'debug'
keypress = require 'keypress'

{MAX_INT, MIN_INT, MAX_LINES, Emulator, CheckError} = require './emulator'

# We'll use the debug library for logging because it has timestamp deltas.
debug.enable 'genetics'
debug = debug 'genetics'

# TODO: Set seed.
mt = Random.engines.mt19937()
mt.autoSeed()
random = new Random(mt)

LABEL_NAMES = 'ABCDEFGHIJKLMNOJKLMNOPQRSTUVWXYZ'.split ''
OPERATORS =    ['NOP', 'MOV', 'SWP', 'SAV', 'ADD', 'SUB', 'NEG', 'JMP', 'JEZ', 'JNZ', 'JGZ', 'JLZ', 'JRO']
OPER_WEIGHTS = [ 1,     5,     2,     2,     4,     4,     3,     1,     1,     1,     1,     1,     1   ]
NAMED_SOURCES = ['UP', 'RIGHT', 'DOWN', 'LEFT', 'NIL', 'ACC', 'ANY', 'LAST']
NAMED_DESTINATIONS = ['UP', 'RIGHT', 'DOWN', 'LEFT', 'NIL', 'ACC', 'ANY', 'LAST']
JUMP_SOURCES = ['UP', 'RIGHT', 'DOWN', 'LEFT', 'ANY', 'LAST']

[OP_REPRODUCTION, OP_CROSSOVER, OP_MUTATION, OP_ALTERATION] = [0..3]

calculateFitness = (emu) ->
  # TODO: Optimize node count / instruction count / cycles
  emu.calculateStats()
  return (
    (emu.stats.correctness * 0.45) +
    (if emu.stats.finished then 0.45 else 0.0) +
    (if emu.stats.outputStddev > 0 then 0.1 else 0.0) # Discourage single repeating numbers?
  )

pickFromWeights = (arr) ->
  total = 0
  total += w for w in arr
  if total is 0
    return random.pick arr
  else
    p = random.real 0, total
    t = 0
    for i in [0...arr.length]
      t += arr[i]
      return i if p < t
    return i

newLabel = (labels) ->
  loop
    pick = random.pick LABEL_NAMES
    break if pick not of labels
  return pick

randomLabel = (labels) ->
  return random.pick Object.keys labels

randomSource = ->
  if random.bool()
    return random.pick NAMED_SOURCES
  else
    if random.bool 0.66
      # Let's try selecting smaller ints some of the time.
      return random.integer -10, 10
    else
      return random.integer MIN_INT, MAX_INT

randomDest = ->
  return random.pick NAMED_DESTINATIONS

randomOperator = ->
  return OPERATORS[pickFromWeights OPER_WEIGHTS]

extractLabels = (node) ->
  labels = {}
  for line in node.lines when line.label?
    labels[line.label] = true
  return labels

generateLine = (node) ->
  {lines} = node
  labels = extractLabels node
  label = newLabel labels

  loop
    op = randomOperator()
    break unless op in ['JMP', 'JEZ', 'JNZ', 'JGZ', 'JLZ'] and Object.keys(labels).length is 0

  switch op

    when 'NOP', 'SWP', 'SAV', 'NEG'
      return { label: label, instruction: [op] }

    when 'ADD', 'SUB'
      return { label: label, instruction: [op, randomSource()] }

    when 'MOV'
      # TODO: Don't write to inputs and read from outputs.
      return { label: label, instruction: [op, randomSource(), randomDest()] }

    when 'JMP', 'JEZ', 'JNZ', 'JGZ', 'JLZ'
      return { label: label, instruction: [op, randomLabel(labels)] }

    when 'JRO'
      offset = random.pick([
        -> random.integer -MAX_LINES, MAX_LINES
        -> random.integer MIN_INT, MAX_INT
        -> random.pick JUMP_SOURCES
      ])()
      return { label: label, instruction: [op, offset] }

  return

growNode = (node) ->
  line = generateLine node
  node.lines.push line
  random.shuffle node.lines
  return

generateRandomAST = (layout, layoutWidth, streams) ->

  ast = { tisasm: 1, nodes: [] }
  index = 0
  nodesByLayout = new Array(layout.length)
  for i in [0...layout.length]
    if layout[i] is 'TILE_COMPUTE'
      node = { index: index++, lines: [] }
      ast.nodes.push node
      nodesByLayout[i] = node

  numComputeNodes = ast.nodes.length
  numInstructions = random.integer 1, numComputeNodes * MAX_LINES

  # Make sure we start by passing input/output checks.
  for [type, name, pos, stream] in streams
    if type is 'STREAM_INPUT'
      node = nodesByLayout[pos]
      node.lines.push { label: null, instruction: ['MOV', 'UP', randomDest()] }
    else
      node = nodesByLayout[layout.length + pos - layoutWidth]
      node.lines.push { label: null, instruction: ['MOV', randomSource(), 'DOWN'] }

  for i in [0...numInstructions]
    tries = 0
    loop
      node = random.pick ast.nodes
      break if tries++ > numInstructions # Maybe the program is full.
      if node.lines.length < MAX_LINES
        growNode node
        break

  return ast

generateValidAST = (emu, layout, layoutWidth, streams, tries = 1000) ->
  i = 0
  loop
    try
      ast = generateRandomAST layout, layoutWidth, streams
      emu.loadProgram ast
      return ast
    catch e
      if e instanceof CheckError
        debug "generated a bad AST: #{ e }"
      else
        throw e
    if i++ > tries
      throw new Error("Couldn't generate a working AST after #{ tries } tries")

generateSomewhatCorrectAST = (emu, layout, layoutWidth, streams, tries = 1000) ->
  i = 0
  loop
    child = generateValidAST emu, layout, layoutWidth, streams, tries
    try
      emu.loadProgram child
      emu.reset()
      emu.run tries
      f = calculateFitness emu
    catch e
      debug e
      f = 0
    return emu.ast if f > 0
    if i++ > tries
      throw new Error("Couldn't generate a somewhat correct AST after #{ tries } tries")

crossoverAST = (a, b) ->
  child = { tisasm: 1, nodes: [] }
  for i in [0...a.nodes.length]
    if random.bool()
      child.nodes.push a.nodes[i]
    else
      child.nodes.push b.nodes[i]
  return child

mutateAST = (parent) ->
  # Our mutation will be to replace a random node with new code.
  # TODO: Pay attention to inputs and outputs.
  child = clone parent
  node = random.pick child.nodes
  node.lines = []
  for i in [0..random.integer(1, MAX_LINES)]
    growNode node
  return child

alterAST = (parent) ->
  child = clone parent
  node = random.pick child.nodes
  {lines} = node
  line = random.pick node.lines

  op = random.integer(0, 2)

  # Maybe delete a random instruction.
  if op in [0, 1]
    lines.splice lines.indexOf(line), 1

  # Maybe insert a new random instruction.
  if op in [1, 2]
    lines.splice lines.indexOf(line), 1 if lines.length >= MAX_LINES
    if lines.length > 0
      index = random.integer 0, lines.length
      lines.splice index, 0, generateLine(node)
    else
      growNode node

  return child

pickChild = (population, fitness) ->
  i = pickFromWeights fitness
  child = population[i]
  return child

solve = (specfile, options) ->

  emu = new Emulator()
  if specfile?
    emu.load null, specfile
    {layout, layoutWidth, streams} = emu.spec
  else
    layout = ('TILE_COMPUTE' for i in [0..11])
    layoutWidth = 4
    streams = []

  generation = 0
  population = new Array(options.children)
  fitness = new Array(options.children)
  newPopulation = new Array(options.children)
  maxFitness = 0

  pickGeneticOperation = do ->
    # Returns an int [0..3] based on probabilities from options.
    weights = [options.reproduction, options.crossover, options.mutation, options.alteration]
    return -> pickFromWeights weights

  # Generate initial population.
  console.log "Generating initial population..."
  for i in [0...population.length]
    child = generateSomewhatCorrectAST emu, layout, layoutWidth, streams, options.maxRunCycles
    console.log "Child #{i+1}/#{population.length} fitness = #{ calculateFitness emu }"
    population[i] = child

  # Main generational loop
  loop

    # Determine fitness of each child.
    maxFitness = 0
    for child, i in population
      try
        emu.loadProgram child
        emu.reset()
        emu.run options.maxRunCycles
        f = calculateFitness emu
      catch e
        if not e instanceof CheckError
          debug "Error with child #{ i }: #{ e }"
        f = 0

      maxFitness = f if f > maxFitness
      fitness[i] = f

      # End case!
      if f is 1
        console.log "Solved on generation #{ generation }!"
        console.log emu.toString()
        console.log emu.toSaveFile()
        return

    if (generation % 100) is 0
      console.log "Generation #{ generation } - max(fitness) = #{ maxFitness }"
    if (generation % 1000) is 0
      console.log "Showing program with the highest fitness..."
      for value, i in fitness
        if value is maxFitness
          console.log emu.toString()
          break

    for i in [0...population.length]
      op = pickGeneticOperation()
      switch op

        when OP_MUTATION
          parent = pickChild population, fitness
          child = mutateAST parent

        when OP_CROSSOVER
          a = pickChild population, fitness
          b = pickChild population, fitness
          child = crossoverAST a, b

        when OP_REPRODUCTION
          parent = pickChild population, fitness
          child = clone parent

        when OP_ALTERATION
          parent = pickChild population, fitness
          child = alterAST parent

      newPopulation[i] = child

    # Copy new population.
    for i in [0...population.length]
      population[i] = newPopulation[i]
    generation++

  return

exports.solve = solve
exports.generateSomewhatCorrectAST = generateSomewhatCorrectAST
exports.mutateAST = mutateAST
exports.crossoverAST = crossoverAST
exports.alterAST = alterAST
