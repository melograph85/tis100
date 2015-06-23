function get_name()
  return "A SIMPLE COUNTER"
end

function get_description()
  return {}
end

function get_streams()
  outx = { 1, 2, 3, 4, 5, 6, 7 }
  return {
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
