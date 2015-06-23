# TIS-100 Emulation and Tools

Parser, emulator, and genetic programming framework for experimenting with the [Tessellated Intelligence System](http://www.zachtronics.com/tis-100/). This project is in no way associated with [Zachtronics](http://www.zachtronics.com/).

![Imgur](http://i.imgur.com/UAallaA.gif)

**SPOILERS SPOILERS SPOILERS!** This repository contains a few sample files which may reveal solutions to some of the puzzles. If you haven't played TIS-100 yet, you really should play it now. Really.

**TODO**: Emulator does not yet support memory nodes or graphical output.

## Getting Started

Mac/Windows/Linux: Install [https://nodejs.org/](NodeJS) version 0.10 or later.

    > npm install -g tis100
    > tis100 run myprogram.txt myspec.lua

### Usage

```
  Usage: tis100 [options] [command]

  Commands:

    parse <progfile>                     Parses the TISasm save file and displays the AST
    check <progfile> [specfile]          Checks that the TISasm save file is semantically valid and optionally validates against the given Lua spec
    spec <specfile>                      Parses the TISasm Lua specification file and prints the config
    run [options] <progfile> <specfile>  Runs a program against a specification
    debug <progfile> <specfile>          Debugs a program interactively (hit Enter to step)
    breed <specfile>                     Interactively breed programs (note argument order)
    solve [options] <specfile>           Attempts to solve the specification through genetic programming

  Options:

    -h, --help  output usage information

  Debugging:

    For verbose output / debugging information, run this with DEBUG=tis100 set.
```

### Programs

Programs are written in TIS-100 assembler and using the game's save file format. Play TIS-100 and read the manual (or hit F1 in-game) to see the full set of instructions. The `tis100` executable can operate on save files -- click "OPEN SAVE DIRECTORY" in the game's segment map to see your solutions. See the samples directory for some examples.

Use `tis100 run` to run a program against a specification and view the final result. Use `tis100 debug` to step through the program by hitting the Enter key.

### Specifications

Specifications let players share puzzles. They're written in Lua and can be accessed from the game's specification editor. Click "CREATE NEW SPECIFICATION" in the game to open a new boilerplate specification. That boilerplate has been checked in as `samples/default.lua`.

## Genetic Programming

This was written as an attempt to solve puzzles through [genetic programming](http://www.genetic-programming.org/). It can currently solve very simple examples, but not much more. It's a long way from solving even the self test diagnostic. Maybe you can help!

For now, see the quick tutorial on [http://www.genetic-programming.org/](http://www.genetic-programming.org/), and see the options using `tis100 solve --help`. Some key terms:

- **Initial population** size is specified by the `--children` option
- **Fitnesa** is how likely a program is to be copied or changed in the next generation. We currently weight higher when a program finishes, has correct numbers in the output, or has a non-zero standard deviation in the output.
- **Alteration** adds, removes or changes a single instruction in a random node
- **Mutation** replaces a random node with new random code
- **Crossover** combines two parent programs, picking a node from either at random
- **Reproduction** simply copies a program from one generation to the next

### Example

There's a simple two-node specification in `samples/one-two.lua`. It puts an input on top of the first node and an output below the second. Its input specifies the numbers 0 thru 7 and the output expects those numbers to be doubled. It's possible that the genetic solver would write a program to do what you think but it's much more likely to generate a program which adds two to `ACC` in a loop. I'm running the program with a very high alteration probability and low crossover/reproduction since the latter are less useful for low-node programs. Let's try:

```
> tis100 solve samples/one-two.lua -a .8 -m .1 -x 0 -r .1
Generating initial population...
Child 1/20 fitness = 0.45
Child 2/20 fitness = 0.05625
Child 3/20 fitness = 0.45
Child 4/20 fitness = 0.60625
...
Generation 7700 - max(fitness) = 0.55
Generation 7800 - max(fitness) = 0.60625
Generation 7900 - max(fitness) = 0.60625
Solved on generation 7990!
┌─────────────────────────────┬───────────────┬─────────────────┬────────────────┐
│ TIS-100 JAVASCRIPT EMULATOR │ A SINGLE NODE │ CYCLES=51       │ FINISHED       │
│                             │               │ NODES=2         │ TEST PASSED OK │
│                             │               │ INSTRUCTIONS=28 │ 100% CORRECT   │
└─────────────────────────────┴───────────────┴─────────────────┴────────────────┘
┌─────────────────────────────┬───────────────────────────────┐
│ IN WRTE ↓=1                 │                               │
├─────────────────────────────┼───────────────────────────────┤
│ COMPUTE-0                   │ COMPUTE-1                     │
│  ACC=0 BAK=(0) LAST=UP WRTE │  ACC=14 BAK=(12) LAST=N/A RUN │
│  ↑=214 →=214 ↓=214 ←=214    │  ↑= →= ↓= ←=                  │
│    G: ADD ANY               │    J: MOV ACC DOWN            │
│    O: SAV                   │  ▸ C: JGZ L                   │
│    J: NEG                   │    L: NOP                     │
│    N: ADD 2                 │    W: SAV                     │
│    Z: JNZ J                 │    E: JRO 645                 │
│    R: SWP                   │    N: SAV                     │
│    L: JLZ E                 │    H: MOV LAST UP             │
│    E: NOP                   │    Q: JMP H                   │
│  ▸ Y: MOV 214 ANY           │    U: SUB 10                  │
│    D: SWP                   │    K: SWP                     │
│    M: MOV LAST LAST         │    D: MOV 310 RIGHT           │
│    K: MOV ANY LAST          │    P: NOP                     │
│    U: JRO -458              │    X: SUB -2                  │
│    X: JMP E                 │                               │
│    A: ADD LEFT              │                               │
├─────────────────────────────┼───────────────────────────────┤
│                             │ OUT READ - OK - FINISHED      │
└─────────────────────────────┴───────────────────────────────┘
OUT:
 EXPECTED: 0 2 4 6 8 10 12 14
 ACTUAL:   0 2 4 6 8 10 12 14
...
```

After 7990 generations (159,800 programs), the emulator found a solution that uses one node to `SUB -2` and `MOV ACC DOWN` repeatedly.

## Developing

1. Install Node v0.10 or later (I recommend [nvm](https://github.com/creationix/nvm))
1. Clone this repo and `cd` to it
1. Install dependencies: `npm install`
1. Install useful tools: `npm install -g coffee-script wach`
1. In a terminal: `npm run watch` (converts CoffeeScript files to JS source)
1. In another terminal: `npm run parser` (converts the ast-parser to JS source)
1. In a third terminal: `./bin/tis100 solve samples/one-two.lua`
1. Make your changes and send me a pull request :)

Run `./bin/tis100` to see all subcommands. `debug` will step through the program interactively.

## Special Thanks

* [Zachtronics](http://www.zachtronics.com/) for the creation of the TIS-100 game.
* [/r/tis100](http://www.reddit.com/r/tis100) for interesting discussions.

## License

This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <http://unlicense.org/>
