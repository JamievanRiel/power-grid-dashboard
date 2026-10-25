local MOD = "__power-grid-dashboard__"

data:extend({
  {
    type = "custom-input",
    name = "power-grid-dashboard-toggle",
    key_sequence = "CONTROL + SHIFT + G",
    action = "lua",
  },
  {
    type = "shortcut",
    name = "power-grid-dashboard",
    action = "lua",
    toggleable = true,
    associated_control_input = "power-grid-dashboard-toggle",
    icon = MOD .. "/graphics/shortcut-x56.png",
    icon_size = 56,
    small_icon = MOD .. "/graphics/shortcut-x24.png",
    small_icon_size = 24,
    order = "p[power-grid-dashboard]",
  },
})

data:extend({
  { type = "sprite", name = "power-grid-dashboard-pin", filename = MOD .. "/graphics/pin.png", size = 32, flags = { "gui-icon" } },
})

local styles = data.raw["gui-style"].default

styles.power_grid_dashboard_table = {
  type = "table_style",
  parent = "table_with_selection",
  horizontal_spacing = 12,
  vertical_spacing = 2,
  column_alignments = {
    { column = 4, alignment = "left" },
    { column = 5, alignment = "right" },
    { column = 6, alignment = "right" },
    { column = 7, alignment = "right" },
    { column = 8, alignment = "right" },
  },
}

styles.power_grid_dashboard_satisfaction = {
  type = "progressbar_style",
  parent = "progressbar",
  width = 110,
  bar_width = 10,
}

styles.power_grid_dashboard_header = {
  type = "label_style",
  parent = "bold_label",
  font_color = { r = 1, g = 0.9, b = 0.75 },
}
