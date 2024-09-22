local jsonb = {}
local ffi = require("ffi")
local bit = require("bit")

local ElementType = {
  Null = 0x0,
  True = 0x1,
  False = 0x2,
  Int = 0x3,
  Int5 = 0x4,
  Float = 0x5,
  Float5 = 0x6,
  Text = 0x7,
  TextJ = 0x8,
  Text5 = 0x9,
  TextRaw = 0xA,
  Array = 0xB,
  Object = 0xC,
  Reserved13 = 0xD,
  Reserved14 = 0xE,
  Reserved15 = 0xF
}

local size_bytes_table = {1, 2, 4, 8}

local function read_int(state, size)
  local offset = state.offset

  state.offset = offset + size

  if size == 1 then return state.data[offset - 1] end
  if size == 2 then return bit.lshift(state.data[offset - 1], 8) + state.data[offset] end
  if size == 4 then
    return bit.lshift(state.data[offset - 1], 24) +
            bit.lshift(state.data[offset], 16) +
            bit.lshift(state.data[offset + 1], 8) +
            state.data[offset + 2]
  end

  local value = 0

  for i = 0, size - 1 do
    value = bit.lshift(value, 8) + state.data[offset + i - 1]
  end

  return value
end

local function read_string(state, size)
  local offset = state.offset

  state.offset = state.offset + size

  return ffi.string(state.data + offset - 1, size)
end

local function read_float(state, size)
  return tonumber(read_string(state, size))
end

local function read_header(state)
  if state.offset > state.data_size then
    error("Offset exceeds data size")
  end

  local first_byte = state.data[state.offset - 1]
  local size_code = bit.rshift(first_byte, 4)

  state.offset = state.offset + 1

  if size_code <= 0xB then
    return bit.band(first_byte, 0x0F), size_code
  end

  return bit.band(first_byte, 0x0F), read_int(state, size_bytes_table[size_code - 0xC + 1])
end

local decoders_map = {}
decoders_map[ElementType.Null] = function() return nil end
decoders_map[ElementType.True] = function() return true end
decoders_map[ElementType.False] = function() return false end
decoders_map[ElementType.Int] = read_int
decoders_map[ElementType.Int5] = read_int
decoders_map[ElementType.Float] = read_float
decoders_map[ElementType.Float5] = read_float
decoders_map[ElementType.Text] = read_string
decoders_map[ElementType.TextJ] = read_string
decoders_map[ElementType.Text5] = read_string
decoders_map[ElementType.TextRaw] = read_string
decoders_map[ElementType.Array] = function(state, payload_size)
  local array = {}
  local size = 0;
  local payload_end = state.offset + payload_size
  while state.offset < payload_end and state.offset <= state.data_size do
    size = size + 1
    array[size] = decoders_map.any(state, payload_end)
  end
  return array
end
decoders_map[ElementType.Object] = function(state, payload_size)
  local object = {}
  local payload_end = state.offset + payload_size
  while state.offset < payload_end and state.offset <= state.data_size do
    local key = decoders_map.any(state, payload_end)
    if type(key) ~= "string" then
      error("Expected string key for object, but got " .. tostring(key) .. " (type: " .. type(key) .. ")")
    end
    object[key] = decoders_map.any(state, payload_end)
  end
  return object
end
decoders_map.any = function (state, end_offset)
  if state.offset > state.data_size then
    error("Offset exceeds data size")
  end

  local element_type, payload_size = read_header(state)

  if decoders_map[element_type] == nil then
    error("Unknown element type: " .. element_type)
  end

  return decoders_map[element_type](state, payload_size)
end

function jsonb.deserialize(data, data_size)
  return decoders_map.any(
    {
      data = data,
      offset = 1,
      data_size = data_size,
    },
    data_size + 1
  )
end

return jsonb