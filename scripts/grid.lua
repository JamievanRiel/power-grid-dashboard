-- Electric network bookkeeping.
--
-- There is no API that lists all electric networks, so every electric pole is tracked and a census
-- (spread over several ticks) groups the poles by sub network. Sub networks that are joined through power
-- switches belong to one LuaElectricNetwork; that parent network is what the dashboard shows. A network is keyed
-- by the lowest id of its sub networks.
--
-- storage.poles[unit_number]   = LuaEntity
-- storage.pending_poles[unit_number] = LuaEntity built while a census walks storage.poles (merged afterwards)
-- storage.census               = { key = last unit_number visited, found = { [sub_id] = { count, poles = {...} } } }
-- storage.networks[key]        = {
--   key, surface_index, force_index, sub_ids = { ... }, poles = count, representatives = { LuaEntity... },
--   global = surface_index for a surface-wide global network (no poles),
--   summary = last flow summary, history = { satisfaction ring }, history_n,
--   low_since = tick satisfaction dropped below the threshold, alerts = { [kind] = LuaEntity },
-- }
-- storage.names[sub_id]        = name given by a player

local format = require("scripts.format")

local grid = {}

local HISTORY = 300 -- samples kept for "lowest satisfaction" (one per second -> 5 minutes)
grid.HISTORY = HISTORY

-----------------------------------------------------------------------------------------------------------------------
-- Poles

function grid.add_pole(entity)
  if storage.census then
    -- adding keys to a table that next() is walking is undefined; merge after this census
    storage.pending_poles[entity.unit_number] = entity
  else
    storage.poles[entity.unit_number] = entity
  end
end

--- Finds every pole again, for example after a configuration change (poles placed by scripts that did not raise
--- an event are picked up this way).
function grid.scan_all()
  storage.poles = {}
  storage.pending_poles = {}
  storage.census = nil
  for _, surface in pairs(game.surfaces) do
    for _, pole in pairs(surface.find_entities_filtered({ type = "electric-pole" })) do
      storage.poles[pole.unit_number] = pole
    end
  end
end

-----------------------------------------------------------------------------------------------------------------------
-- Census


local function network_key(sub_network)
  local key = sub_network.id
  for _, sub in pairs(sub_network.parent_network.sub_networks) do
    if sub.id < key then
      key = sub.id
    end
  end
  return key
end

--- Turns the sub networks found by the census into parent networks, keeping history and alerts of networks
--- that still exist.
local function publish(found)
  local old = storage.networks
  local networks = {}
  for sub_id, entry in pairs(found) do
    local pole, sub
    for _, candidate in pairs(entry.poles) do
      if candidate.valid and candidate.electric_network then
        pole, sub = candidate, candidate.electric_network
        break
      end
    end
    if sub and sub.valid then
      local key = network_key(sub)
      local network = networks[key]
      if not network then
        local previous = old[key]
        network = {
          key = key,
          surface_index = pole.surface_index,
          force_index = pole.force_index,
          sub_ids = {},
          poles = 0,
          representatives = {},
          summary = previous and previous.summary,
          history = previous and previous.history or {},
          history_n = previous and previous.history_n or 0,
          low_since = previous and previous.low_since,
          alerts = previous and previous.alerts or {},
        }
        networks[key] = network
      end
      network.poles = network.poles + entry.count
      network.sub_ids[#network.sub_ids + 1] = sub_id
      for _, representative in pairs(entry.poles) do
        if #network.representatives < 4 then
          network.representatives[#network.representatives + 1] = representative
        end
      end
    end
  end

  -- surface-wide global networks (map editor, some mods) have no poles
  for _, surface in pairs(game.surfaces) do
    if surface.has_global_electric_network then
      local sub = surface.global_electric_network
      if sub and sub.valid then
        local key = network_key(sub)
        if not networks[key] then
          local previous = old[key]
          networks[key] = {
            key = key,
            surface_index = surface.index,
            force_index = 1,
            sub_ids = { sub.id },
            poles = 0,
            representatives = {},
            global = surface.index,
            summary = previous and previous.summary,
            history = previous and previous.history or {},
            history_n = previous and previous.history_n or 0,
            alerts = previous and previous.alerts or {},
          }
        end
      end
    end
  end

  for key, network in pairs(old) do
    if not networks[key] then
      grid.clear_alerts(network)
    end
  end
  -- names of sub networks that no longer exist can never be shown again
  local alive = {}
  for _, network in pairs(networks) do
    for _, sub_id in pairs(network.sub_ids) do
      alive[sub_id] = true
    end
  end
  for sub_id in pairs(storage.names) do
    if not alive[sub_id] then
      storage.names[sub_id] = nil
    end
  end
  storage.networks = networks
  storage.census_completed = game.tick
end

--- Processes up to `budget` poles of the running census, starting a new one when the last finished.
--- The census walks storage.poles with next() and remembers where it stopped, so no tick touches every pole.
function grid.census_step(budget)
  local census = storage.census
  if not census then
    for unit_number, pole in pairs(storage.pending_poles) do
      storage.poles[unit_number] = pole
    end
    storage.pending_poles = {}
    census = { found = {} }
    storage.census = census
  end
  local poles, found = storage.poles, census.found
  local key = census.key
  for _ = 1, budget do
    local pole
    key, pole = next(poles, key)
    if key == nil then
      publish(found)
      storage.census = nil
      return
    end
    if not pole.valid then
      poles[key] = nil -- clearing the current key while walking is allowed
    else
      local sub = pole.electric_network
      if sub then
        local id = sub.id
        local entry = found[id]
        if not entry then
          entry = { count = 0, poles = {} }
          found[id] = entry
        end
        entry.count = entry.count + 1
        if #entry.poles < 3 then
          entry.poles[#entry.poles + 1] = pole
        end
      end
    end
  end
  census.key = key
end

--- Runs a complete census at once (used on init and by tests).
function grid.census_now()
  storage.census = nil
  grid.census_step(math.huge)
end

-----------------------------------------------------------------------------------------------------------------------
-- Sampling

--- The LuaElectricNetwork of a published network, or nil if all its representatives are gone.
function grid.electric_network(network)
  if network.global then
    local surface = game.get_surface(network.global)
    local sub = surface and surface.global_electric_network
    return sub and sub.valid and sub.parent_network or nil
  end
  for _, pole in pairs(network.representatives) do
    if pole.valid then
      local sub = pole.electric_network
      if sub and sub.valid then
        return sub.parent_network
      end
    end
  end
  return nil
end

--- A valid entity of the network (for alerts, pins and remote view), if any.
function grid.representative(network)
  for _, pole in pairs(network.representatives) do
    if pole.valid then
      return pole
    end
  end
  return nil
end

--- Flow of the last update in watts and joules (flow_last_tick is in joules per tick).
function grid.summarize(electric_network)
  local flow = electric_network.flow_last_tick
  local demand = (flow.primary_demand + flow.secondary_demand) * 60
  local summary = {
    -- a network without demand (only poles, or idle machines) reports 0; nothing is missing there
    satisfaction = demand > 0 and flow.consumption_satisfaction or 1,
    consumption = (flow.primary_demand * flow.primary_demand_usage + flow.secondary_demand * flow.secondary_demand_usage) * 60,
    demand = demand,
    -- maximum_production also counts accumulators while they deliver; capacity is generators and solar only
    capacity = (flow.primary_output + flow.secondary_output + flow.solar_output) * 60,
    solar = flow.solar_output * flow.solar_output_usage * 60,
    generators = (flow.primary_output * flow.primary_output_usage + flow.secondary_output * flow.secondary_output_usage) * 60,
    accumulator_energy = flow.accumulator_energy,
    accumulator_capacity = flow.accumulator_capacity,
    accumulator_in = flow.tertiary_demand * flow.tertiary_demand_usage * 60,
    accumulator_out = flow.tertiary_output * flow.tertiary_output_usage * 60,
  }
  if summary.accumulator_out > 0 and summary.accumulator_energy > 0 then
    summary.empty_in = summary.accumulator_energy / summary.accumulator_out
  elseif summary.accumulator_in > 0 and summary.accumulator_capacity > summary.accumulator_energy then
    summary.full_in = (summary.accumulator_capacity - summary.accumulator_energy) / summary.accumulator_in
  end
  return summary
end

--- Lowest satisfaction in the history, or nil when there is no history yet.
function grid.lowest_satisfaction(network)
  local lowest
  for i = 1, math.min(network.history_n, HISTORY) do
    local value = network.history[i]
    if value and (not lowest or value < lowest) then
      lowest = value
    end
  end
  return lowest
end

--- Whether the network deserves attention right now.
function grid.has_problem(network)
  local summary = network.summary
  if not summary then
    return false
  end
  local threshold = settings.global["power-grid-dashboard-alert-threshold"].value / 100
  local warning = settings.global["power-grid-dashboard-accumulator-warning"].value
  return (summary.demand > 0 and summary.satisfaction < threshold)
    or (warning > 0 and summary.empty_in ~= nil and summary.empty_in < warning)
end

-----------------------------------------------------------------------------------------------------------------------
-- Names

--- The name players see for a surface: the platform name, the planet name or the surface name.
function grid.surface_name(surface_index)
  local surface = game.get_surface(surface_index)
  if not surface then
    return "?"
  end
  if surface.platform then
    return surface.platform.name
  elseif surface.planet then
    return surface.planet.prototype.localised_name
  end
  return surface.localised_name or surface.name
end

--- The name a player gave the network, if any.
function grid.custom_name(network)
  for _, sub_id in pairs(network.sub_ids) do
    local name = storage.names[sub_id]
    if name then
      return name
    end
  end
  return nil
end

--- Plain-text name: the player-given name, otherwise "Grid #<n>" (pins only take plain text).
function grid.plain_name(network)
  return grid.custom_name(network) or ("Grid #" .. (network.key + 1))
end

--- Localised name for the GUI and alerts.
function grid.name(network)
  return grid.custom_name(network) or { "power-grid-dashboard.default-name", network.key + 1 }
end

--- Names the network; stored on its first sub network so it survives other sub networks joining or leaving.
function grid.rename(network, name)
  for _, sub_id in pairs(network.sub_ids) do
    storage.names[sub_id] = nil
  end
  if name and name ~= "" then
    storage.names[network.sub_ids[1]] = name
  end
end

-----------------------------------------------------------------------------------------------------------------------
-- Alerts

local ALERT_ICONS = {
  brownout = { type = "item", name = "medium-electric-pole" },
  accumulators = { type = "item", name = "accumulator" },
}

grid.ALERT_ICONS = ALERT_ICONS

-- The force is taken from the entity: force indices change when forces are merged.
local function set_alert(network, kind, active, message)
  local current = network.alerts[kind]
  if active then
    local entity = grid.representative(network)
    if not entity then
      return
    end
    -- re-added every update: this refreshes the alert and moves it if the representative changed
    if current and current.valid and current ~= entity then
      current.force.remove_alert({ entity = current, type = defines.alert_type.custom, icon = ALERT_ICONS[kind] })
    end
    entity.force.add_custom_alert(entity, ALERT_ICONS[kind], message, true)
    network.alerts[kind] = entity
  elseif current then
    if current.valid then
      current.force.remove_alert({ entity = current, type = defines.alert_type.custom, icon = ALERT_ICONS[kind] })
    end
    network.alerts[kind] = nil
  end
end

function grid.clear_alerts(network)
  for kind in pairs(network.alerts or {}) do
    set_alert(network, kind, false)
  end
end

local function update_alerts(network)
  local name = grid.name(network)
  local summary = network.summary
  local s = settings.global
  local big_enough = network.poles >= s["power-grid-dashboard-minimum-poles"].value or network.global
  local threshold = s["power-grid-dashboard-alert-threshold"].value / 100

  local brownout = false
  if big_enough and summary.demand > 0 and summary.satisfaction < threshold then
    network.low_since = network.low_since or game.tick
    brownout = game.tick - network.low_since >= s["power-grid-dashboard-alert-delay"].value * 60
  else
    network.low_since = nil
  end
  set_alert(network, "brownout", brownout, { "power-grid-dashboard.alert-brownout", name, string.format("%d", math.floor(summary.satisfaction * 100)) })

  local warning = s["power-grid-dashboard-accumulator-warning"].value
  local draining = big_enough and warning > 0 and summary.empty_in ~= nil and summary.empty_in < warning
  set_alert(network, "accumulators", draining, { "power-grid-dashboard.alert-accumulators", name, format.duration(summary.empty_in or 0) })
end

--- Samples every network once; called once per second. A network whose representative poles are all gone keeps
--- its last values until the next census finds it again (or drops it).
function grid.sample()
  for _, network in pairs(storage.networks) do
    local electric_network = grid.electric_network(network)
    if electric_network then
      local summary = grid.summarize(electric_network)
      network.summary = summary
      network.history_n = network.history_n + 1
      network.history[(network.history_n - 1) % HISTORY + 1] = summary.satisfaction
      update_alerts(network)
    end
  end
end

return grid
