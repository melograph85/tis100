function get_name()
  return "GREATER THAN THREE"
end

function get_description()
  return {}
end

function get_streams()
  inx = { 1, -4, 5, 6, 1, 3, 10, 99, -38, 0 }
  outx = { 0, 0, 1, 1, 0, 0, 1, 1, 0, 0 }
  return {
    { STREAM_INPUT, "IN", 0, inx },
    { STREAM_OUTPUT, "OUT", 0, outx },
  }
end

function get_layout()
  return {
    TILE_COMPUTE
  }
end

function get_layout_width()
  return 1
end
