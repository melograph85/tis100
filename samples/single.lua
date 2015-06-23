function get_name()
  return "A SINGLE NODE"
end

function get_description()
  return {}
end

function get_streams()
  inx = { 0, 0, 0, 0, 0, 0, 0 }
  outx = { 0, 0, 0, 0, 0, 0, 0 }
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
