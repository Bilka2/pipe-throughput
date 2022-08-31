---@param length int
---@param surface LuaSurface
---@param offset int
local function spawn_row(length, surface, offset)
  -- rows are north -> south and height is horizontal. basically it should be columns and width
  local row_height = global.row_index * 3 
  local pump_size = 2/2

  ---@class Row
  ---@field length int
  ---@field source LuaEntity?
  ---@field sink LuaEntity?
  ---@field pumps LuaEntity[]
  global.rows[global.row_index] = {}
  local row = global.rows[global.row_index]
  row.length = length
  row.sink = surface.create_entity{name="storage-tank", position = {  x = row_height + offset - 1, y = offset - 3 - pump_size}, force = "player"}
  row.source = surface.create_entity{name="storage-tank", position = { x = row_height + offset + 1, y = offset + length + pump_size + 2}, force = "player"}

  row.pumps = {}
  row.pumps[2] = surface.create_entity{name="pump", position = { x = row_height + offset, y = offset - pump_size}, direction = defines.direction.north, force = "player"}
  surface.create_entity{name="substation", position = { x = row_height + offset, y = offset - 5 - pump_size}, force = "player"}
  row.pumps[1] = surface.create_entity{name="pump", position = { x = row_height + offset, y = offset + length + pump_size}, direction = defines.direction.north, force = "player"}
  surface.create_entity{name="substation", position = { x = row_height + offset, y = offset + length + pump_size + 5}, force = "player"}
  for _, pump in pairs(row.pumps) do
    rendering.draw_text{text=tostring(length), surface = surface, color = {1,1,1}, scale = 2, target = pump}
  end

  assert(length >= 1)
  for i=0,length-1 do
    surface.create_entity{name="pipe", position = { x = row_height + offset, y = offset + i}, force = "player"}
  end

  global.row_index = global.row_index + 1
end


script.on_event(defines.events.on_player_created, function(event)
  -- Set up the debug surface
  local map_size = 3000
  local mgs = {}
  mgs.width = map_size
  mgs.height = map_size
  mgs.default_enable_all_autoplace_controls = false
  mgs.property_expression_names = {}
  mgs.property_expression_names.elevation = 10
  local surface = game.create_surface("test", mgs)
  surface.request_to_generate_chunks({0, 0}, map_size / 2 / 32)
  surface.force_generate_chunk_requests()

  --spawn power
  --note, if not starting with pipe length 1, the pumps on the right (near "sink" storage tanks) may not be powered
  local offset = -1450
  local eei = surface.create_entity{name="electric-energy-interface", position={x = offset - 4, y = offset - 10}, force = "player"}
  eei.electric_buffer_size = 1000000000
  eei.power_production = 1000000000

  -- spawn pipe/pump setups
  ---@type table<uint, Row>
  global.rows = {}
  global.row_index = 1
  local max_pipe_length = 1001 -- change wanted pipe length here, e.g. to 601 or 201
  for i=1,max_pipe_length do
    spawn_row(i, surface, offset)
  end

  -- Enable map editor for the player
  local player = game.get_player(event.player_index) ---@cast player -nil
  player.toggle_map_editor()
  game.tick_paused = false
  game.speed = 6
  player.teleport({0, 0}, "test")
end)

---@param length int length of pipe between two pumps
---@return int throughput throughput of the given length pipe based on the formula
local function throughput_by_formula(length)
--[[ quote from https://wiki.factorio.com/index.php?title=Fluid_system&oldid=189491:
  1 <= pipes <= 197:
    flow = 10000 / (3 * pipes - 1) + 1000
    pipes > 197:
        flow = 240000 / (pipes + 39)
  ]]

  assert(length >= 1)
  if length >= 1 and length <= 197 then
    return 10000 / (3 * length - 1) + 1000
  else
    return 240000 / (length + 39)
  end
end

local throughput_from_wiki = --https://wiki.factorio.com/index.php?title=Fluid_system&oldid=189716
{
  [1] = 6000,
  [2] = 3000,
  [3] = 2250,
  [4] = 1909,
  [5] = 1714,
  [6] = 1588,
  [7] = 1500,
  [8] = 1434,
  [9] = 1384,
  [10] = 1344,
  [11] = 1312,
  [12] = 1285,
  [17] = 1200,
  [20] = 1169,
  [30] = 1112,
  [50] = 1067,
  [100] = 1033,
  [150] = 1022,
  [200] = 1004,
  [201] = 999,
  [261] = 799,
  [300] = 707,
  [400] = 546,
  [500] = 445,
  [600] = 375,
  [800] = 286,
  [1000] = 230,
}

script.on_nth_tick(10, function(event)
  for _, row in pairs(global.rows) do
    row.source.insert_fluid{name="water", amount = 25000}
    row.sink.remove_fluid{name="water", amount = 25000}
  end

  -- pause the game once the throughput should be stable 
  if event.tick == 60*60*15 then -- 7 minutes are enough for up to pipe length 300
    game.tick_paused = true
    game.speed = 1

    if true then -- set to false when using a factorio version where you can read pump speed with mods
      game.print("Pumping speed values should be balanced out (verified with pipe lengths up to 1001), you can now read them from the tooltips")
    else -- custom factorio version that can read pump speed with mods
      game.print("Pumping speed values should be balanced out. If not, pipe lengths with problem are printed here in chat")
      local output_file = "pumping-speeds.txt"
      game.write_file(output_file, "Pumping speeds by length of pipe between two pumps:\n", false)
      local float_output_file = "float-pumping-speeds.txt"
      game.write_file(float_output_file, "Float pumping speeds by length of pipe between two pumps:\n", false)

      for _, row in pairs(global.rows) do
        -- flooring read pump speeds because the game floors for the pump tooltip
        local in_pump_speed = math.floor(row.pumps[1].pump_speed)
        local formula_speed = math.floor(throughput_by_formula(row.length))
        game.write_file(output_file, "length: " .. row.length .. " measured: " .. in_pump_speed .. " calculated: " .. formula_speed, true)

        if in_pump_speed ~= formula_speed then
          game.write_file(output_file, " formula wrong " .. throughput_by_formula(row.length) - row.pumps[1].pump_speed, true)
        end
        local wiki_speed = throughput_from_wiki[row.length]
        if wiki_speed and wiki_speed ~= in_pump_speed then
          game.write_file(output_file, " wiki wrong, wiki has " .. wiki_speed, true)
        end

        game.write_file(output_file, "\n", true)

        if (row.pumps[1].pump_speed - row.pumps[2].pump_speed) > 0.001 then
          game.print(row.length) -- input and output pump do not have the same throughput. Most likely it needs to run longer to balance out
        end

        game.write_file(float_output_file, "length: " .. row.length .. " measured in pump: " .. row.pumps[1].pump_speed .. " measured out pump: " .. row.pumps[2].pump_speed .. "\n", true)
      end
    end
  end
end)
