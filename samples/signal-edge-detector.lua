function get_name()
  return "SIGNAL EDGE DETECTOR"
end

function get_description()
  return {
    "> READ A VALUE FROM IN",
    "> COMPARE VALUE TO PREVIOUS VALUE",
    "> WRITE 1 IF CHANGED BY 10 OR MORE",
    "> IF NOT TRUE, WRITE 0 INSTEAD",
    "> THE FIRST VALUE IS ALWAYS 0",
  }
end

function get_streams()
  inx = { 0, 25, 23, 26, 15, 19, 28, 38, 42, 40, 43, 45, 54, 56, 45, 43, 52, 42, 41, 44, 54, 65, 76, 86, 82, 73, 63, 65, 54, 58, 68, 66, 68, 69, 80, 71, 67, 71, 68 }
  outx = { 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0 }
  return {
    { STREAM_INPUT, "IN", 1, inx },
    { STREAM_OUTPUT, "OUT", 2, outx },
  }
end

function get_layout()
  return {
    TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE,
    TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE,
    TILE_DAMAGED, TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE,
  }
end
