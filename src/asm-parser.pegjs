// TIS instruction language parser in PEG.js grammar - http://pegjs.org/

start = nodes:node*
  { return { tisasm: 1, nodes: nodes } }

node = index:index lines:line* NL*
  {
    // There's always an extra blank line, but we don't want to strip blank lines and our matcher is
    // greedy. There's probably a smarter way of doing this.
    if (lines.length > 0) {
      var last = lines[lines.length - 1];
      if (last.label === null && last.instruction === null && last.comment === null) {
        lines.length = lines.length - 1;
      }
    }
    return { index: index, lines: lines }
  }

index = '@' num:[0-9]+ NL+ { return Number(num.join('')) }

line = WS* label:lineLabel? WS* instruction:instruction? WS* comment:comment? NL
  { return { label: label, instruction: instruction, comment: comment, raw: text() } }

instruction
  = nop / mov / swp / sav / add / sub / neg
  / jmp / jez / jnz / jgz / jlz / jro

comment = prefix:'#' text:[^\n]* { return prefix + text.join('') }

lineLabel = label:label ':' { return label }

label = name:[A-Za-z0-9]+ { return name.join('') }

value = sign:'-'? value:[0-9]+ { return Number((sign || '') + value.join('')) }

address = 'ACC' / 'BAK' / 'NIL' / 'LEFT' / 'RIGHT' / 'UP' / 'DOWN' / 'ANY' / 'LAST'

valueOrAddress = value:value / address:address

NL = '\r\n' / '\r' / '\n'
WS = [ \t]

mov = name:'MOV' WS+ src:valueOrAddress ','* WS+ dest:valueOrAddress
  { return [name, src, dest] }

add = name:'ADD' WS+ arg:valueOrAddress { return [name, arg] }
sub = name:'SUB' WS+ arg:valueOrAddress { return [name, arg] }
jro = name:'JRO' WS+ arg:valueOrAddress { return [name, arg] }
nop = name:'NOP' { return [name] }
swp = name:'SWP' { return [name] }
sav = name:'SAV' { return [name] }
neg = name:'NEG' { return [name] }
jmp = name:'JMP' WS+ label:label { return [name, label] }
jez = name:'JEZ' WS+ label:label { return [name, label] }
jnz = name:'JNZ' WS+ label:label { return [name, label] }
jgz = name:'JGZ' WS+ label:label { return [name, label] }
jlz = name:'JLZ' WS+ label:label { return [name, label] }
