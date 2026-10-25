-- The dashboard window.
--
-- storage.guis[player_index]    = { frame, table, footer, surface_dropdown, surface_options = { index -> surface_index }, renaming = key? }
-- storage.filters[player_index] = { surface_index?, problems_only, show_small }
-- storage.locations[player_index] = last window position

local grid = require("scripts.grid")
local format = require("scripts.format")

local FRAME = "power_grid_dashboard"
local SHORTCUT = "power-grid-dashboard"
local COLUMNS = 9

local gui = {}

local function filters(player_index)
  local f = storage.filters[player_index]
  if not f then
    f = { problems_only = false, show_small = false }
    storage.filters[player_index] = f
  end
  return f
end

local function satisfaction_color(satisfaction)
  if satisfaction >= 0.99 then
    return { r = 0.3, g = 0.85, b = 0.3 }
  elseif satisfaction >= 0.75 then
    return { r = 0.95, g = 0.8, b = 0.2 }
  end
  return { r = 0.95, g = 0.25, b = 0.2 }
end

--- Whether the player already has a pin on this entity.
local function pinned(player, entity)
  for _, pin in pairs(player.get_pins()) do
    for _, target in pairs(pin.targets or {}) do
      if target == entity then
        return true
      end
    end
  end
  return false
end

--- Networks of the player's force that pass the filters, biggest consumers first.
local function visible_networks(player)
  local f = filters(player.index)
  local minimum = settings.global["power-grid-dashboard-minimum-poles"].value
  local list = {}
  local total = 0
  for _, network in pairs(storage.networks) do
    if network.force_index == player.force_index then
      total = total + 1
      local shown = (not f.surface_index or network.surface_index == f.surface_index)
        and (f.show_small or network.poles >= minimum or network.global)
        and (not f.problems_only or grid.has_problem(network))
      if shown then
        list[#list + 1] = network
      end
    end
  end
  table.sort(list, function(a, b)
    local ca = a.summary and a.summary.consumption or 0
    local cb = b.summary and b.summary.consumption or 0
    if ca ~= cb then
      return ca > cb
    end
    return a.key < b.key
  end)
  return list, total
end

-----------------------------------------------------------------------------------------------------------------------
-- Building

local function header(t, caption, tooltip)
  t.add({ type = "label", style = "power_grid_dashboard_header", caption = caption, tooltip = tooltip })
end

local function usage_tooltip(summary)
  return {
    "power-grid-dashboard.usage-tooltip",
    format.power(summary.consumption),
    format.power(summary.demand),
    format.power(summary.capacity),
    format.power(summary.solar),
    format.power(summary.generators),
    format.power(summary.accumulator_out),
    format.power(summary.accumulator_in),
  }
end

local function add_row(t, state, network)
  local summary = network.summary
  local key = network.key

  local status = "utility/status_yellow"
  local status_tooltip = { "power-grid-dashboard.status-waiting" }
  if summary then
    if grid.has_problem(network) then
      status, status_tooltip = "utility/status_not_working", { "power-grid-dashboard.status-problem" }
    else
      status, status_tooltip = "utility/status_working", { "power-grid-dashboard.status-ok" }
    end
  end
  t.add({ type = "sprite", sprite = status, tooltip = status_tooltip })

  local name_flow = t.add({ type = "flow", direction = "horizontal" })
  name_flow.style.vertical_align = "center"
  if state.renaming == key then
    local field = name_flow.add({
      type = "textfield",
      text = grid.custom_name(network) or "",
      tooltip = { "power-grid-dashboard.rename-tooltip" },
      tags = { action = "rename-confirm", key = key },
      icon_selector = true,
    })
    field.style.width = 160
    field.focus()
    field.select_all()
  else
    name_flow.add({ type = "label", style = "bold_label", caption = grid.name(network) })
    name_flow.add({ type = "sprite-button", style = "frame_action_button", sprite = "utility/rename_icon", tooltip = { "power-grid-dashboard.rename" }, tags = { action = "rename", key = key } })
  end

  t.add({ type = "label", caption = grid.surface_name(network.surface_index) })

  local satisfaction = t.add({ type = "flow", direction = "horizontal" })
  satisfaction.style.vertical_align = "center"
  local bar = satisfaction.add({ type = "progressbar", style = "power_grid_dashboard_satisfaction", value = summary and summary.satisfaction or 0 })
  if summary then
    bar.style.color = satisfaction_color(summary.satisfaction)
    satisfaction.add({ type = "label", caption = format.percent(summary.satisfaction) })
  end

  if summary then
    t.add({ type = "label", caption = { "power-grid-dashboard.usage", format.power(summary.consumption), format.power(summary.capacity) }, tooltip = usage_tooltip(summary) })
  else
    t.add({ type = "label", caption = "–" })
  end

  local accumulators = "–"
  if summary and summary.accumulator_capacity > 0 then
    local charge = format.percent(summary.accumulator_energy / summary.accumulator_capacity)
    if summary.empty_in then
      accumulators = { "power-grid-dashboard.accumulators-draining", charge, format.duration(summary.empty_in) }
    elseif summary.full_in then
      accumulators = { "power-grid-dashboard.accumulators-charging", charge, format.duration(summary.full_in) }
    else
      accumulators = charge
    end
  end
  t.add({ type = "label", caption = accumulators })

  local lowest = grid.lowest_satisfaction(network)
  local lowest_label = t.add({ type = "label", caption = lowest and format.percent(lowest) or "–" })
  if lowest then
    lowest_label.style.font_color = satisfaction_color(lowest)
  end

  t.add({ type = "label", caption = network.global and { "power-grid-dashboard.global" } or tostring(network.poles) })

  local actions = t.add({ type = "flow", direction = "horizontal" })
  actions.add({ type = "sprite-button", style = "frame_action_button", sprite = "utility/search", tooltip = { "power-grid-dashboard.locate" }, tags = { action = "locate", key = key } })
  actions.add({ type = "sprite-button", style = "frame_action_button", sprite = "power-grid-dashboard-pin", tooltip = { "power-grid-dashboard.pin" }, tags = { action = "pin", key = key } })
end

--- Rebuilds the rows and the surface filter of an open dashboard.
function gui.refresh(player)
  local state = storage.guis[player.index]
  if not (state and state.frame.valid) then
    return
  end
  local f = filters(player.index)

  -- surface filter: all surfaces that have a network of this force
  local surfaces, seen = {}, {}
  for _, network in pairs(storage.networks) do
    if network.force_index == player.force_index and not seen[network.surface_index] then
      seen[network.surface_index] = true
      surfaces[#surfaces + 1] = network.surface_index
    end
  end
  table.sort(surfaces)
  local items, selected = { { "power-grid-dashboard.all-surfaces" } }, 1
  state.surface_options = {}
  for i, surface_index in pairs(surfaces) do
    items[i + 1] = grid.surface_name(surface_index)
    state.surface_options[i + 1] = surface_index
    if f.surface_index == surface_index then
      selected = i + 1
    end
  end
  state.surface_dropdown.items = items
  state.surface_dropdown.selected_index = selected

  local t = state.table
  t.clear()
  header(t, "")
  header(t, { "power-grid-dashboard.column-name" })
  header(t, { "power-grid-dashboard.column-surface" })
  header(t, { "power-grid-dashboard.column-satisfaction" })
  header(t, { "power-grid-dashboard.column-usage" }, { "power-grid-dashboard.column-usage-tooltip" })
  header(t, { "power-grid-dashboard.column-accumulators" })
  header(t, { "power-grid-dashboard.column-lowest" }, { "power-grid-dashboard.column-lowest-tooltip" })
  header(t, { "power-grid-dashboard.column-poles" })
  header(t, "")
  local list, total = visible_networks(player)
  for _, network in pairs(list) do
    add_row(t, state, network)
  end
  state.empty.visible = #list == 0
  state.footer.caption = { "power-grid-dashboard.footer", #list, total }
end

function gui.open(player)
  gui.close(player)
  local f = filters(player.index)
  local frame = player.gui.screen.add({ type = "frame", name = FRAME, direction = "vertical" })

  local titlebar = frame.add({ type = "flow", direction = "horizontal", style = "frame_header_flow" })
  titlebar.drag_target = frame
  titlebar.add({ type = "label", style = "frame_title", caption = { "power-grid-dashboard.title" }, ignored_by_interaction = true })
  local drag = titlebar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  drag.style.height = 24
  drag.style.horizontally_stretchable = true
  drag.style.right_margin = 4
  titlebar.add({ type = "sprite-button", style = "close_button", sprite = "utility/close", tags = { action = "close" } })

  local inside = frame.add({ type = "frame", style = "inside_deep_frame", direction = "vertical" })
  local toolbar = inside.add({ type = "frame", style = "subheader_frame", direction = "horizontal" })
  toolbar.style.horizontally_stretchable = true
  toolbar.style.vertical_align = "center"
  local dropdown = toolbar.add({ type = "drop-down", tags = { action = "surface" } })
  dropdown.style.width = 220
  dropdown.style.left_margin = 8
  local problems = toolbar.add({ type = "checkbox", state = f.problems_only, caption = { "power-grid-dashboard.problems-only" }, tags = { action = "problems-only" } })
  problems.style.left_margin = 12
  local small = toolbar.add({ type = "checkbox", state = f.show_small, caption = { "power-grid-dashboard.show-small" }, tooltip = { "power-grid-dashboard.show-small-tooltip" }, tags = { action = "show-small" } })
  small.style.left_margin = 12

  local scroll = inside.add({ type = "scroll-pane", style = "naked_scroll_pane", horizontal_scroll_policy = "never" })
  scroll.style.maximal_height = 600
  scroll.style.padding = 8
  local t = scroll.add({ type = "table", style = "power_grid_dashboard_table", column_count = COLUMNS })
  local empty = scroll.add({ type = "label", caption = { "power-grid-dashboard.empty" } })
  empty.style.padding = 8

  local footer = frame.add({ type = "label" })
  footer.style.top_margin = 4

  storage.guis[player.index] = { frame = frame, table = t, empty = empty, footer = footer, surface_dropdown = dropdown }
  local location = storage.locations[player.index]
  if location then
    frame.location = location
  else
    frame.force_auto_center()
  end
  player.opened = frame
  player.set_shortcut_toggled(SHORTCUT, true)
  gui.refresh(player)
end

function gui.close(player)
  local state = storage.guis[player.index]
  storage.guis[player.index] = nil
  if state and state.frame.valid then
    storage.locations[player.index] = state.frame.location
    state.frame.destroy()
  end
  local leftover = player.gui.screen[FRAME]
  if leftover then
    leftover.destroy()
  end
  player.set_shortcut_toggled(SHORTCUT, false)
end

function gui.toggle(player)
  if storage.guis[player.index] then
    gui.close(player)
  else
    gui.open(player)
  end
end

function gui.refresh_all()
  for player_index, state in pairs(storage.guis) do
    local player = game.get_player(player_index)
    if player and not state.renaming then
      gui.refresh(player)
    end
  end
end

-----------------------------------------------------------------------------------------------------------------------
-- Events

function gui.on_click(event)
  local element = event.element
  local action = element.valid and element.tags.action
  if not action then
    return
  end
  local player = game.get_player(event.player_index)
  if action == "close" then
    gui.close(player)
    return
  end
  local state = storage.guis[event.player_index]
  local network = element.tags.key and storage.networks[element.tags.key]
  if not (state and network) then
    return
  end
  if action == "rename" then
    state.renaming = network.key
    gui.refresh(player)
  elseif action == "locate" then
    local entity = grid.representative(network)
    if entity then
      player.centered_on = entity
    elseif network.global then
      player.set_controller({ type = defines.controllers.remote, surface = network.global, position = { 0, 0 } })
    end
  elseif action == "pin" then
    local entity = grid.representative(network)
    if entity and pinned(player, entity) then
      player.print({ "power-grid-dashboard.already-pinned", grid.name(network) })
    elseif entity then
      player.add_pin({ entity = entity, label = grid.plain_name(network) })
      player.print({ "power-grid-dashboard.pinned", grid.name(network) })
    end
  end
end

function gui.on_confirmed(event)
  local element = event.element
  if not (element.valid and element.tags.action == "rename-confirm") then
    return
  end
  local player = game.get_player(event.player_index)
  local state = storage.guis[event.player_index]
  local network = storage.networks[element.tags.key]
  if network then
    grid.rename(network, element.text)
  end
  if state then
    state.renaming = nil
  end
  gui.refresh_all()
  gui.refresh(player)
end

function gui.on_checked(event)
  local element = event.element
  local action = element.valid and element.tags.action
  if action ~= "problems-only" and action ~= "show-small" then
    return
  end
  local f = filters(event.player_index)
  if action == "problems-only" then
    f.problems_only = element.state
  else
    f.show_small = element.state
  end
  gui.refresh(game.get_player(event.player_index))
end

function gui.on_selection_changed(event)
  local element = event.element
  if not (element.valid and element.tags.action == "surface") then
    return
  end
  local state = storage.guis[event.player_index]
  if not state then
    return
  end
  filters(event.player_index).surface_index = state.surface_options[element.selected_index]
  gui.refresh(game.get_player(event.player_index))
end

function gui.on_closed(event)
  local element = event.element
  if element and element.valid and element.name == FRAME then
    gui.close(game.get_player(event.player_index))
  end
end

return gui
