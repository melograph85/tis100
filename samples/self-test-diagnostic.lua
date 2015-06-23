function get_name()
  return "SELF-TEST DIAGNOSTIC"
end

function get_description()
  return {
    "> READ A VALUE FROM IN.X AND",
    "  WRITE THE VALUE TO OUT.X",
    "> READ A VALUE FROM IN.A AND",
    "  WRITE THE VALUE TO OUT.A",
  }
end

function get_streams()
  inx = {}
  outx = {}
  ina = {}
  outa = {}
  for i = 1,39 do
    inx[i] = math.random(10, 99)
    outx[i] = inx[i]
    ina[i] = math.random(10, 99)
    outa[i] = ina[i]
  end
  return {
    { STREAM_INPUT, "IN.X", 0, inx },
    { STREAM_OUTPUT, "OUT.X", 0, outx },
    { STREAM_INPUT, "IN.A", 3, ina },
    { STREAM_OUTPUT, "OUT.A", 3, outa },
  }
end

function get_layout()
  return {
    TILE_COMPUTE,   TILE_DAMAGED, TILE_COMPUTE,   TILE_COMPUTE,
    TILE_COMPUTE,   TILE_DAMAGED, TILE_COMPUTE,   TILE_DAMAGED,
    TILE_COMPUTE,   TILE_DAMAGED, TILE_COMPUTE,   TILE_COMPUTE,
  }
end
