function get_name()
  return "A SINGLE NODE"
end

function get_description()
  return {}
end

function get_streams()
  inx = { 0, 1, 2, 3, 4, 5, 6, 7 }
  outx = { 0, 2, 4, 6, 8, 10, 12, 14 }
  return {
    { STREAM_INPUT, "IN", 0, inx },
    { STREAM_OUTPUT, "OUT", 1, outx },
  }
end

function get_layout()
  return {
    TILE_COMPUTE, TILE_COMPUTE
  }
end

function get_layout_width()
  return 2
end
