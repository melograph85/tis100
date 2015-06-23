#!/usr/bin/env coffee
#
# Semantic checker for parsed TISasm ASTs using asm-parser.js
#
# Implementation goals:
# - Don't spend too much time on the display (like colors). This is a runtime, not the game.
# - Straightforward and reasonably easy to read
# - Minimize garbage (toString() is exempt)
# - Assume V8 will optimize for hidden classes (no arbitrary properties, don't generate names)
# - No obviously-dumb performance mistakes, but no perf superstition either. (Profile later.)

Table = require 'cli-table'
debug = require 'debug'
fs = require 'fs'
statslib = require 'stats-lite'
{EventEmitter} = require 'events'

parserlib = require './asm-parser'
speclib = require './spec'

debug = debug 'tis100'

# Layout can be changed for experimentation, but these are constant for now.
MAX_LINES = 15
MAX_COLUMNS = 18
MIN_INT = -999
MAX_INT = 999
MAX_STREAM_LENGTH = 39
OP_ANY_READ_ORDER = ['LEFT', 'RIGHT', 'UP', 'DOWN']

class CheckError extends Error

  constructor: (@nodeIndex, @lineNumber, @raw, @message) ->
    super(@message)

class Emulator extends EventEmitter

  constructor: ->
    @maxNodes = 12 # May be overridden by spec.
    @layoutWidth = 4 # May be overridden by spec.
    @ast = null
    @spec = null
    @nodes = []
    @inputs = []
    @outputs = []
    @cycle = 0
    @finished = false
    @passed = false
    @stats = {}

  calculateStats: ->
    numActual = 0
    numTotal = 0

    stddevs = []
    for output in @outputs when output?
      stddevs.push statslib.stdev(output.actual) ? 0
      for actual, i in output.actual
        numActual++ if actual is output.expected[i]
        numTotal++

    stddev = statslib.mean(stddevs)
    correctness = numActual / numTotal

    computeNodes = (n for n in @nodes when n.numLogicalInstructions) # Only ComputeNodes
    nodeCount = computeNodes.length
    if computeNodes.length
      instrCount = (n.numLogicalInstructions ? 0 for n in computeNodes).reduce (a, b) -> a + b
    else
      instrCount = 0

    @stats.finished = @finished
    @stats.passed = @passed
    @stats.cycles = @cycle # No +1
    @stats.actualOutputs = numActual
    @stats.expectedOutputs = numTotal
    @stats.correctness = correctness
    @stats.outputStddev = stddev
    @stats.nodeCount = nodeCount
    @stats.instructionCount = instrCount
    return

  toString: ->
    @calculateStats()
    ret = ''

    table = new Table()
    row = ["TIS-100 JAVASCRIPT EMULATOR"]
    row.push if @spec?
      @spec.name + '\n' + @spec.description.join '\n'
    else
      ''

    row.push """
      CYCLES=#{ @stats.cycles }
      NODES=#{ @stats.nodeCount }
      INSTRUCTIONS=#{ @stats.instructionCount }
    """

    row.push if @finished
      """
        FINISHED
        #{ if @passed then 'TEST PASSED OK' else 'TEST FAILED' }
        #{ Math.round(@stats.correctness * 100 * 1e3)/1e3 }% CORRECT
      """
    else
      'RUNNING'
    table.push row
    ret += table.toString() + '\n'

    table = new Table()
    for arr in [@inputs, @nodes, @outputs]
      i = 0
      while i <= arr.length - 1
        table.push((arr[i+j]?.toString?() ? '') for j in [0...@layoutWidth])
        i += 4
    ret += table.toString() + '\n'

    for node in @outputs when node?
      {name, actual, expected} = node
      ret += "#{ name }:\n"
      ret += " EXPECTED: #{ expected.join ' ' }\n"
      ret += " ACTUAL:   #{ (a for a in actual when a?).join ' ' }\n"
    ret += '\n'

    return ret

  toSaveFile: ->
    ret = ''
    i = 0
    for node in @nodes
      if node instanceof ComputeNode
        ret += "@#{ i }\n"
        ret += node.toSaveFile()
        ret += "\n"
        i++
    return ret

  load: (progsrc, specsrc) ->
    if specsrc?
      if /get_description/.test specsrc
        @loadSpec specsrc
      else
        @loadSpec fs.readFileSync specsrc, 'utf8'
    if progsrc?
      if /^\s*@/.test progsrc
        @loadProgram progsrc
      else
        @loadProgram fs.readFileSync progsrc, 'utf8'
    @reset()
    return

  loadProgram: (contents) ->
    if contents?.tisasm is 1
      @ast = contents
    else
      try
        @ast = parserlib.parse contents
      catch e
        e.contents = contents
        throw e
    @staticCheck()
    return

  loadSpec: (contents) ->
    try
      @spec = speclib.parse contents
    catch e
      e.contents = contents
      throw e
    @maxNodes = @spec.layout.length
    @layoutWidth = @spec.layoutWidth
    return

  staticCheck: ->

    if @ast?.tisasm != 1
      throw new Error("Expected a parsed TISasm abstract syntax tree")

    for {index, lines}, nodeIndex in @ast.nodes

      if index != nodeIndex
        throw new CheckError(nodeIndex, 0, null,
          "Node indices must be specified in order starting from 0")

      if nodeIndex > @maxNodes - 1
        throw new CheckError(nodeIndex, 0, null,
          "Program cannot specify more than #{ @maxNodes } nodes")

      labels = {} # Label -> lineNumber

      for {label, instruction, comment, raw}, lineNumber in lines

        if lineNumber > MAX_LINES - 1
          throw new CheckError(nodeIndex, lineNumber, raw,
            "Program cannot have more than #{ MAX_LINES } lines per node")

        if label?
          labels[label] = lineNumber

        if raw?.length > MAX_COLUMNS + 1 # Plus a newline...
          throw new CheckError(nodeIndex, lineNumber, raw,
            "Lines cannot have more than #{ MAX_COLUMNS } columns")

      for {label, instruction, comment, raw}, lineNumber in lines

        assertArg = (value) ->
          switch typeof value
            when 'string'
              if value is 'BAK'
                throw new CheckError(nodeIndex, lineNumber, raw, "BAK is not addressable")
            when 'number'
              if value < MIN_INT or value > MAX_INT
                throw new CheckError(nodeIndex, lineNumber, raw,
                  "Number #{ value } exceeds range #{ MIN_INT } to #{ MAX_INT }")

        continue unless instruction?
        switch instruction[0]

          when 'MOV'
            assertArg instruction[0]
            assertArg instruction[1]

          when 'ADD', 'SUB', 'JRO'
            assertArg instruction[0]

          when 'JMP', 'JEZ', 'JNZ', 'JGZ', 'JLZ'
            if instruction[1] not of labels
              throw new CheckError(nodeIndex, lineNumber, raw,
                "Label '#{ instruction[1] }' is not specified in program")

      if @spec?

        inputs = []
        outputs = []
        for [type, name, pos, stream] in @spec.streams

          switch type
            when 'STREAM_INPUT'
              if inputs[pos]
                throw new Error("Duplicate input streams for position #{ pos }: #{ name } and #{ inputs[pos] }")
              inputs[pos] = name
            when 'STREAM_OUTPUT'
              if outputs[pos]
                throw new Error("Duplicate output streams for position #{ pos }: #{ name } and #{ outputs[pos] }")
              outputs[pos] = name
            else
              throw new Error("Unknown stream type #{ type } named #{ name }")

          if stream.length > MAX_STREAM_LENGTH
            throw new Error("Stream #{ name } length is greater than max #{ MAX_STREAM_LENGTH }")

        nodeIndex = 0
        for type, layoutIndex in @spec.layout
          switch type

            when 'TILE_COMPUTE'
              continue unless node = @ast.nodes[nodeIndex]

              # Check that some instruction reads an input.
              input = inputs[layoutIndex]
              if layoutIndex in [0...@layoutWidth] and input
                ok = false
                for {instruction} in node.lines when node.lines?
                  if instruction[0] in ['MOV']
                    ok or= instruction[1] in ['UP', 'ANY']
                  else if instruction[0] in ['ADD', 'SUB', 'JRO']
                    ok or= instruction[1] in ['UP', 'ANY']
                  break if ok
                if not ok
                  throw new Error("Node #{ layoutIndex } must read from input #{ input }")

              # Check that some instruction writes to an output.
              output = outputs[layoutIndex - 8]
              if layoutIndex in [8..11] and output
                ok = false
                for {instruction} in node.lines when node.lines?
                  if instruction[0] in ['MOV']
                    ok or= instruction[2] in ['DOWN', 'ANY']
                  break if ok
                if not ok
                  throw new Error("Node #{ layoutIndex } must write to output #{ output }")

              nodeIndex++

            when 'TILE_MEMORY', 'TILE_DAMAGED'
              # Nothing to do.

            else
              throw new Error("Unknown tile type in layout #{ layoutIndex }: #{ type }")

    return

  reset: ->
    return unless @ast?

    @cycle = 0
    @finished = false
    @passed = false
    @stats = {}

    # Init visible nodes.
    @nodes = []
    types = @spec?.layout or ('TILE_COMPUTE' for i in [0...@maxNodes])
    pn = @ast.nodes
    pni = 0
    for type, index in types
      node = switch type
        when 'TILE_DAMAGED' then new DamagedNode()
        when 'TILE_MEMORY' then new MemoryNode()
        when 'TILE_COMPUTE' then new ComputeNode(pn[pni++]?.lines ? [])
      node.layoutIndex = index
      node.name = "#{ type.replace 'TILE_', '' }-#{ index }"
      @nodes.push node

    # Inputs and outputs act as hidden, limited-function nodes.
    @inputs = new Array(4)
    @outputs = new Array(4)
    if @spec?.streams?
      for [type, name, pos, stream] in @spec.streams
        if type is 'STREAM_INPUT'
          node = new InputNode(stream)
          node.layoutIndex = -4 + pos
          node.name = name
          @inputs[pos] = node
        else
          node = new OutputNode(stream)
          node.layoutIndex = @maxNodes + pos
          node.name = name
          @outputs[pos] = node

    # Compute neighbors.
    #
    # inputs =  0  1  2  3
    # nodes  =  0  1  2  3
    #           4  5  6  7
    #           8  9  10 11
    # outputs = 0  1  2  3
    #
    for node, index in @nodes

      up = index - @layoutWidth
      if up < 0
        node.neighbor_up = @inputs[@layoutWidth + up]
      else
        node.neighbor_up = @nodes[up]

      down = index + @layoutWidth
      if down > @maxNodes - 1
        node.neighbor_down = @outputs[down - @maxNodes]
      else
        node.neighbor_down = @nodes[down]

      right = index + 1
      if right % @layoutWidth != 0
        node.neighbor_right = @nodes[right]

      left = index - 1
      if index % @layoutWidth != 0
        node.neighbor_left = @nodes[left]

    for node, index in @inputs when node?
      node.neighbor_down = @nodes[index + @layoutWidth]

    for node, index in @outputs when node?
      node.neighbor_up = @nodes[@maxNodes - @layoutWidth + index]

    @emit 'reset'
    return

  step: ->
    debug "CYCLE=#{ @cycle }"

    node.stepOne() for node in @inputs when node?
    node.stepOne() for node in @nodes
    node.stepOne() for node in @outputs when node?

    node.stepTwo() for node in @inputs when node?
    node.stepTwo() for node in @nodes
    node.stepTwo() for node in @outputs when node?

    @cycle++

    @finished = @passed = true
    for output in @outputs when output?
      @finished and= output.finished
      @passed and= output.passed

    @emit 'step'

    return

  run: (maxCycles = 1000) ->
    while @cycle < maxCycles and not @finished
      @step()
    @emit 'end'
    return

class Node

  constructor: ->
    @port_up = @port_down = @port_right = @port_left = null
    @neighbor_up = @neighbor_down = @neighbor_right = @neighbor_left = null

    # Debugging/toString properties.
    @layoutIndex = null
    @name = "UNNAMED"

  toString: ->
    return @name + '\n'

  stepOne: ->
  stepTwo: ->

class DamagedNode extends Node

class MemoryNode extends Node

  constructor: ->
    throw new Error("Memory nodes are unimplemented")

class ComputeNode extends Node

  constructor: (lines) ->
    super()
    @iptr = 0
    @acc = 0
    @bak = 0
    @mode = 'IDLE'

    @_fillValue = null # See WRTE mode for MOVs.

    # Notes:
    # - Jumping to a line with only a label jumps to the following instruction.
    # - If the last instruction is just a label, jumping to it should jump to 0.
    #   (I originally thought I could convert all jumps to JRO, but this rule makes doing
    #   that much more difficult. So let's keep labels and make _advance() smarter.)
    @instructions = []
    @numLogicalInstructions = 0
    @labelToIptr = {}
    @iptrToLabel = []
    for {label, instruction}, iptr in lines
      @iptrToLabel[iptr] = label
      @labelToIptr[label] = iptr if label?
      @instructions.push instruction
      @numLogicalInstructions++ if instruction?

    # Advance instruction pointer to first logical instructions.
    if @numLogicalInstructions > 0
      while not @instructions[@iptr]?
        @iptr++

  DIR_TO_CHAR = { UP: '↑', DOWN: '↓', LEFT: '←', RIGHT: '→' }

  toString: ->
    ret = super.toString()
    ret += " ACC=#{ @acc } BAK=(#{ @bak }) LAST=#{ @last ? 'N/A' } #{ @mode }\n"
    for dir in ['up', 'right', 'down', 'left']
      ret += " #{ DIR_TO_CHAR[dir.toUpperCase()] }=#{ @["port_#{ dir }"] ? '' }"
    ret += '\n'
    for instruction, i in @instructions
      ret += if @iptr is i then ' ▸ ' else '   '
      ret += @iptrToLabel[i] + ':' if @iptrToLabel[i]?
      ret += ' ' + (instruction?.join(' ') ? '')
      ret += '\n' if i < @instructions.length - 1
    return ret

  toSaveFile: ->
    ret = ''
    for instruction, i in @instructions
      ret += @iptrToLabel[i] + ':' if @iptrToLabel[i]?
      ret += ' ' + (instruction?.join(' ') ? '')
      ret += '\n'
    return ret

  _clamp: (value) ->
    return Math.min(MAX_INT, Math.max(MIN_INT, value))

  _advance: (inc = 1, wrap = true) ->
    max = @instructions.length - 1

    loop
      @iptr += inc
      if @iptr > max
        @iptr = if wrap then 0 else max
        break
      if @iptr < 0 then @iptr = 0 # Nothing wraps backwards.
      break if @instructions[@iptr]?

    # Last line was a label with no instruction.
    @iptr = 0 unless @instructions[@iptr]?

    # Advance instruction pointer to first logical instructions.
    if @numLogicalInstructions > 0
      while not @instructions[@iptr]?
        @iptr++

    @mode = 'RUN' # Probably an invariant - if @iptr moves, mode is RUN.
    debug @name, 'advanced to iptr', @iptr
    return

  _readFromNeighbor: (dir) ->

    # Get the neighbor node. If dir is invalid (i.e., last = null), return null.
    switch dir
      when 'UP' then neighbor = @neighbor_up
      when 'RIGHT' then neighbor = @neighbor_right
      when 'DOWN' then neighbor = @neighbor_down
      when 'LEFT' then neighbor = @neighbor_left
      else return null

    # No neighbor means we'll wait.
    return null unless neighbor?

    # Get the value from the neighbor. If no value, wait.
    switch dir
      when 'UP' then value = neighbor.port_down
      when 'RIGHT' then value = neighbor.port_left
      when 'DOWN' then value = neighbor.port_up
      when 'LEFT' then value = neighbor.port_right
    return null unless value?

    # Yay! A value to read! Clear the neighbor's ports. (MOV X ANY will fill all ports.)
    neighbor.port_up = neighbor.port_right = neighbor.port_down = neighbor.port_left = null

    # And we've got a value.
    return value

  stepOne: ->
    return unless @instructions[@iptr]?
    [op, arg1, arg2] = @instructions[@iptr]
    switch op

      when 'NOP'
        @_advance()

      when 'SWP'
        temp = @acc
        @acc = @bak
        @bak = temp
        @_advance()

      when 'SAV'
        @bak = @acc
        @_advance()

      when 'NEG'
        @acc *= -1
        @_advance()

      when 'JRO'
        switch arg1

          when 'NIL'
            @_advance 0 # Infinite loop.

          when 'ACC'
            @_advance @acc, false

          when 'UP', 'RIGHT', 'DOWN', 'LEFT'
            value = @_readFromNeighbor arg1
            if value?
              @_advance value, false
            else
              @mode = 'READ'

          when 'ANY'
            for dir in OP_ANY_READ_ORDER
              value = @_readFromNeighbor dir
              if value?
                @_advance value, false
                break
              else
                @mode = 'READ'

          when 'LAST'
            if @last?
              value = @_readFromNeighbor @last
              if value?
                @_advance value, false
              else
                @mode = 'READ'
            else # If LAST is N/A act like 'JRO NIL'
              @_advance 0

          else # Number
            @_advance arg1, false

      when 'JMP', 'JEZ', 'JNZ', 'JGZ', 'JLZ'
        switch op
          when 'JMP'
            dest = @labelToIptr[arg1]
          when 'JEZ'
            dest = if @acc == 0 then @labelToIptr[arg1] else @iptr + 1
          when 'JNZ'
            dest = if @acc != 0 then @labelToIptr[arg1] else @iptr + 1
          when 'JGZ'
            dest = if @acc > 0 then @labelToIptr[arg1] else @iptr + 1
          when 'JLZ'
            dest = if @acc < 0 then @labelToIptr[arg1] else @iptr + 1
        @_advance dest - @iptr, false

      when 'ADD', 'SUB'
        switch arg1

          when 'NIL'
            @_advance() # Acts like 'ADD 0'

          when 'ACC'
            value = if op is 'SUB' then -@acc else @acc
            @acc = @_clamp @acc + value
            @_advance()

          when 'UP', 'RIGHT', 'DOWN', 'LEFT'
            value = @_readFromNeighbor arg1
            if value?
              value *= -1 if op is 'SUB'
              @acc = @_clamp @acc + value
              @_advance()
            else
              @mode = 'READ'

          when 'ANY'
            for dir in OP_ANY_READ_ORDER
              value = @_readFromNeighbor dir
              if value?
                value *= -1 if op is 'SUB'
                @acc = @_clamp @acc + value
                @last = dir
                @_advance()
                break
              else
                @mode = 'READ'

          when 'LAST'
            if @last?
              value = @_readFromNeighbor @last
              if value?
                value *= -1 if op is 'SUB'
                @acc = @_clamp @acc + value
                @_advance()
              else
                @mode = 'READ'
            else # If LAST is N/A act like 'ADD NIL'
              @_advance()

          else # Number
            value = arg1
            value *= -1 if op is 'SUB'
            @acc = @_clamp @acc + value
            @_advance()

      when 'MOV'

        if @mode in ['IDLE', 'RUN']
          debug @name, 'is in mode', @mode
          if typeof arg1 is 'number'
            value = arg1
          else if arg1 is 'NIL'
            value = 0
          else if arg1 is 'ACC'
            value = @acc
          else
            debug @name, 'needs to wait and read from', arg1
            @mode = 'READ'

        if @mode in ['IDLE', 'RUN']
          debug @name, 'is in mode', @mode
          if arg2 is 'NIL' or (arg2 is 'LAST' and not last?)
            @_advance()
          else if arg2 is 'ACC'
            @acc = value
            @_advance()
          else
            debug @name, 'needs to wait and write to', arg2
            @_fillValue = value
            @mode = 'WRTE'
          return

        if @mode is 'READ'
          debug @name, 'must have waited to read from', arg1
          switch arg1
            when 'UP', 'RIGHT', 'DOWN', 'LEFT'
              value = @_readFromNeighbor arg1
            when 'ANY'
              for dir in OP_ANY_READ_ORDER
                value = @_readFromNeighbor dir
                break if value?
            when 'LAST'
              if @last?
                value = @_readFromNeighbor @last
              else # If LAST is N/A act like 'MOV NIL'
                value = 0

          # If no value available then wait.
          debug @name, 'read value', value
          if not value?
            return

          # Otherwise, continue....
          # If arg2 is immediate, write it and advance
          if arg2 is 'NIL' or (arg2 is 'LAST' and not last?)
            @_advance()
          else if arg2 is 'ACC'
            @acc = value
            @_advance()

          # Otherwise, remember that we need to fill the port on stepTwo. We can't do this now
          # because other nodes might be in mode READ and would drain the port in their stepOne.
          else
            debug @name, 'needs to wait to write', value, 'to', arg2
            @mode = 'WRTE'
            @_fillValue = value

    return

  stepTwo: ->
    return unless @instructions[@iptr]?
    [op, arg1, arg2] = @instructions[@iptr]
    # A second pass is needed because nodes in the WRTE mode might have had their ports drained.

    # Are we about to enter WRTE mode? If so, set the mode, fill the port, and return.
    if @_fillValue?
      debug @name, 'has a fill value,', @_fillValue, 'and will put it in', arg2
      @mode = 'WRTE'
      switch arg2
        when 'UP' then @port_up = @_fillValue
        when 'RIGHT' then @port_right = @_fillValue
        when 'DOWN' then @port_down = @_fillValue
        when 'LEFT' then @port_left = @_fillValue
        when 'ANY' then @port_up = @port_right = @port_down = @port_left = @_fillValue
        when 'LAST'
          switch @last
            when 'UP' then @port_up = @_fillValue
            when 'RIGHT' then @port_right = @_fillValue
            when 'DOWN' then @port_down = @_fillValue
            when 'LEFT' then @port_left = @_fillValue
      @_fillValue = null
      return

    # If op is MOV and mode is WRTE, processing is needed.
    if op is 'MOV' and @mode is 'WRTE'
      # If the arg2 port has no value, we've been drained, so advance.
      switch arg2
        when 'UP' then value = @port_up
        when 'RIGHT' then value = @port_right
        when 'DOWN' then value = @port_down
        when 'LEFT' then value = @port_left
        when 'ANY' then value = @port_up # Any port will do -- they've all been cleared.
        when 'LAST'
          switch @last # Must not be N/A, otherwise mode wouldn't be WRTE.
            when 'UP' then value = @port_up
            when 'RIGHT' then value = @port_right
            when 'DOWN' then value = @port_down
            when 'LEFT' then value = @port_left
      debug @name, 'needs to write', value, 'to', arg2 if value?
      if not value?
        debug @name, 'has been drained'
        @_advance()

    return

class InputNode extends Node

  constructor: (@stream) ->
    super()
    @ptr = 0
    @mode = 'RUN'
    @port_down = null

  toString: ->
    ret = "#{ @name } #{ @mode } ↓=#{ @port_down ? '' }"
    return ret

  stepTwo: ->
    if @port_down?
      @mode = 'WRTE'
    else
      if @mode is 'WRTE' # Just emptied.
        @mode = 'RUN'
      else if @mode is 'RUN'
        value = @stream[@ptr]
        if value?
          @port_down = @stream[@ptr]
          @ptr++
          @mode = 'WRTE'
        else
          @mode = 'IDLE'
    return

class OutputNode extends Node

  constructor: (@expected) ->
    super()
    @actual = new Array(@expected.length)
    @ptr = 0
    @mode = 'READ' # Starts ready to read.
    @neighbor_up = null
    @passed = true
    @finished = false

  toString: ->
    ret = @name
    ret += ' ' + @mode
    ret += ' - ' + if @passed then 'OK' else 'NOT OK'
    ret += ' - FINISHED' if @finished
    return ret

  stepOne: ->

    # We could do the READ/RUN mode flip-flop like in an InputNode, but it doesn't really matter.
    return unless @neighbor_up?
    value = @neighbor_up.port_down
    if value?
      @neighbor_up.port_up = @neighbor_up.port_right = @neighbor_up.port_down = @neighbor_up.port_left = null

      # Values past the expected length are ignored. Output doesn't block.
      if @ptr < @expected.length
        @actual[@ptr] = value

      # Update result status.
      @finished = @actual[@actual.length - 1]?
      if @actual[@ptr]?
        @passed and= @actual[@ptr] is @expected[@ptr]

      @ptr++

    return

exports.CheckError = CheckError
exports.Emulator = Emulator
exports.MAX_LINES = MAX_LINES
exports.MIN_INT = MIN_INT
exports.MAX_INT = MAX_INT
