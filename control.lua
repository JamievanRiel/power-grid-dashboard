-- Power Grid Dashboard: every electric network in one window, with alerts for brownouts and draining accumulators.

local grid = require("scripts.grid")
local gui = require("scripts.gui")

local SAMPLE_INTERVAL = 60 -- ticks; history and alert delays assume one sample per second

local function init_storage()
  storage.poles = storage.poles or {}
  storage.pending_poles = storage.pending_poles or {}
  storage.networks = storage.networks or {}
  storage.names = storage.names or {}
  storage.guis = storage.guis or {}
  storage.filters = storage.filters or {}
  storage.locations = storage.locations or {}
end

script.on_init(function()
  init_storage()
  grid.scan_all()
  grid.census_now()
end)

script.on_configuration_changed(function()
  init_storage()
  for _, network in pairs(storage.networks) do
    grid.clear_alerts(network)
  end
  storage.networks = {}
  storage.census = nil
  grid.scan_all()
  grid.census_now()
  for _, player in pairs(game.players) do
    gui.close(player)
  end
end)

-----------------------------------------------------------------------------------------------------------------------
-- Pole tracking

local function on_built(event)
  local entity = event.entity or event.destination
  if entity and entity.valid and entity.type == "electric-pole" then
    grid.add_pole(entity)
  end
end

local pole_filter = { { filter = "type", type = "electric-pole" } }
for _, id in pairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_entity_cloned,
}) do
  script.on_event(id, on_built, pole_filter)
end

-- Surfaces created or cleared by scripts may contain poles that were never "built".
script.on_event(defines.events.on_surface_cleared, function()
  grid.scan_all()
end)

-----------------------------------------------------------------------------------------------------------------------
-- Census, sampling and refresh

script.on_event(defines.events.on_tick, function(event)
  grid.census_step(settings.global["power-grid-dashboard-census-budget"].value)
  if event.tick % SAMPLE_INTERVAL == 0 then
    grid.sample()
    gui.refresh_all()
  end
end)

-----------------------------------------------------------------------------------------------------------------------
-- GUI

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == "power-grid-dashboard" then
    gui.toggle(game.get_player(event.player_index))
  end
end)

script.on_event("power-grid-dashboard-toggle", function(event)
  gui.toggle(game.get_player(event.player_index))
end)

--- Only GUI events of elements created by this mod (other mods may use the same tag names).
local function own(handler)
  return function(event)
    local element = event.element
    if element and element.valid and element.get_mod() == script.mod_name then
      handler(event)
    end
  end
end

script.on_event(defines.events.on_gui_click, own(gui.on_click))
script.on_event(defines.events.on_gui_confirmed, own(gui.on_confirmed))
script.on_event(defines.events.on_gui_checked_state_changed, own(gui.on_checked))
script.on_event(defines.events.on_gui_selection_state_changed, own(gui.on_selection_changed))
script.on_event(defines.events.on_gui_closed, own(gui.on_closed))

script.on_event(defines.events.on_player_left_game, function(event)
  gui.close(game.get_player(event.player_index)) -- otherwise a frozen window is waiting after rejoining
end)

script.on_event(defines.events.on_player_removed, function(event)
  storage.guis[event.player_index] = nil
  storage.filters[event.player_index] = nil
  storage.locations[event.player_index] = nil
end)

-- Alerts are only removed for connected players. Drop this mod's alerts when somebody joins; the ones that are
-- still valid come back within a second.
script.on_event(defines.events.on_player_joined_game, function(event)
  local player = game.get_player(event.player_index)
  for _, by_type in pairs(player.get_alerts({ type = defines.alert_type.custom })) do
    for _, alerts in pairs(by_type) do
      for _, alert in pairs(alerts) do
        local key = type(alert.message) == "table" and alert.message[1]
        if type(key) == "string" and string.sub(key, 1, 27) == "power-grid-dashboard.alert-" and alert.target then
          player.remove_alert({ entity = alert.target, type = defines.alert_type.custom, icon = alert.icon })
        end
      end
    end
  end
end)

-----------------------------------------------------------------------------------------------------------------------
-- Remote interface (also used by the integration tests)

remote.add_interface("power-grid-dashboard", {
  --- Summaries of all networks: { key, name, surface_index, force_index, poles, summary, lowest, problem, alerts }
  get_networks = function()
    local result = {}
    for key, network in pairs(storage.networks) do
      local alerts = {}
      for kind in pairs(network.alerts) do
        alerts[#alerts + 1] = kind
      end
      result[#result + 1] = {
        key = key,
        name = grid.name(network),
        surface_index = network.surface_index,
        force_index = network.force_index,
        poles = network.poles,
        sub_networks = #network.sub_ids,
        summary = network.summary,
        lowest = grid.lowest_satisfaction(network),
        problem = grid.has_problem(network),
        alerts = alerts,
      }
    end
    return result
  end,
  --- Runs a full census and a sample immediately instead of waiting for the background passes.
  update_now = function()
    grid.census_now()
    grid.sample()
    gui.refresh_all()
  end,
  rename = function(key, name)
    local network = storage.networks[key]
    if network then
      grid.rename(network, name)
    end
  end,
  open = function(player_index)
    local player = game.get_player(player_index)
    if player then
      gui.open(player)
    end
  end,
  --- Finds all poles again, e.g. after another mod created poles without raising an event.
  rescan = function()
    grid.scan_all()
    grid.census_now()
  end,
})
