function get_name()
  return "SIGNAL PATTERN DETECTOR"
end

function get_description()
  return {
    "> READ A VALUE FROM IN",
    "> LOOK FOR THE PATTERN 1,5,4",
    "> WRITE 1 WHEN PATTERN IS FOUND",
    "> IF NOT TRUE, WRITE 0 INSTEAD",
  }
end

function get_streams()
  inx = { 1, 5, 1, 5, 4, 1, 5, 4, 3, 1, 2, 2, 2, 1, 5, 4, 1, 5, 4, 3, 2, 1, 1, 1, 5, 4, 5, 4, 3, 2, 1, 1, 3, 1, 1, 1, 5, 4, 2 }
  outx = { 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0 }
  return {
    { STREAM_INPUT, "IN", 1, inx },
    { STREAM_OUTPUT, "OUT", 2, outx },
  }
end

function get_layout()
  return {
    TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE, TILE_DAMAGED,
    TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE,
    TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE, TILE_COMPUTE,
  }
end
