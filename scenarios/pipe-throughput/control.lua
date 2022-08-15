---@param length int
---@param surface LuaSurface
---@param offset int
local function spawn_row(length, surface, offset)
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
  row.source = surface.create_entity{name="storage-tank", position = { x = offset - 3 - pump_size, y = row_height + offset - 1}, force = "player"}
  row.sink = surface.create_entity{name="storage-tank", position = { x = offset + length + pump_size + 2, y = row_height + offset + 1}, force = "player"}

  row.pumps = {}
  row.pumps[1] = surface.create_entity{name="pump", position = { x = offset - pump_size, y = row_height + offset}, direction = defines.direction.east, force = "player"}
  surface.create_entity{name="substation", position = { x = offset - 5 - pump_size, y = row_height + offset}, force = "player"}
  row.pumps[2] = surface.create_entity{name="pump", position = { x = offset + length + pump_size, y = row_height + offset}, direction = defines.direction.east, force = "player"}
  surface.create_entity{name="substation", position = { x = offset + length + pump_size + 5, y = row_height + offset}, force = "player"}
  for _, pump in pairs(row.pumps) do
    rendering.draw_text{text=tostring(length), surface = surface, color = {1,1,1}, scale = 2, target = pump}
  end

  assert(length >= 1)
  for i=0,length-1 do
    surface.create_entity{name="pipe", position = { x = offset + i, y = row_height + offset}, force = "player"}
  end

  global.row_index = global.row_index + 1
end


script.on_event(defines.events.on_player_created, function(event)
  -- Set up the debug surface
  local map_size = 900
  local mgs = {}
  mgs.width = map_size
  mgs.height = map_size
  mgs.default_enable_all_autoplace_controls = false
  mgs.property_expression_names = {}
  mgs.property_expression_names.elevation = 10
  local surface = game.create_surface("test", mgs)
  surface.request_to_generate_chunks({0, 0}, map_size / 2 / 32)
  surface.force_generate_chunk_requests()

  --spawn power and pipes
  local offset = -400
  local eei = surface.create_entity{name="electric-energy-interface", position={x = offset - 10, y = offset - 4}, force = "player"}
  eei.electric_buffer_size = 1000000000
  eei.power_production = 1000000000

  ---@type table<uint, Row>
  global.rows = {}
  global.row_index = 1
  for i=1,301 do
    spawn_row(i, surface, offset)
  end

  -- Enable map editor for the player
  local player = game.get_player(event.player_index) ---@cast player -nil
  player.toggle_map_editor()
  game.tick_paused = false
  game.speed = 30
  player.teleport({0, 0}, "test")
end)

script.on_nth_tick(10, function(event)
  for _, row in pairs(global.rows) do
    row.source.insert_fluid{name="water", amount = 25000}
    row.sink.remove_fluid{name="water", amount = 25000}
  end

  if event.tick == 60*60*7 then
    game.tick_paused = true
    game.speed = 1

    if true then -- set to false when using a factorio version where you can read pump speed with mods
      game.print("pumping speed values should be balanced out (verified with pipe lengths up to 300), you can read them now")
    else -- custom factorio version that can read pump speed with mods
      game.print("pump speed values should be balanced out. If not, pipe length is printed here")

      for _, row in pairs(global.rows) do
        log("length: " .. row.length .. " measured: " .. math.floor(row.pumps[1].pump_speed)) -- flooring because the game floors for the pump tooltip
        if (row.pumps[1].pump_speed - row.pumps[2].pump_speed) > 0.05 then
          game.print(row.length)
        end
      end
    end
  end
end)

