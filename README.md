# Power Grid Dashboard

Every electric network on every planet and platform in one window. Open it with the lightning button in the shortcut
bar or **Ctrl + Shift + G**.

## What you see per network

- **Satisfaction**: how much of the power the machines ask for they actually get.
- **Usage / capacity**: power used by machines against the maximum output of generators and solar panels
  (hover it for demand, solar, generator and accumulator flows).
- **Accumulators**: charge, and when they will be full or empty at the current rate.
- **Lowest (5 min)**: the lowest satisfaction of the last five minutes, so short brownouts are not missed.
- **Poles**, and where the network is.

Networks joined by a closed power switch count as one network. Filter by planet or platform, show only networks with
problems, and hide small networks (fewer poles than set in the mod settings).

## Actions

- **Rename** a network (the pencil). Leave the name empty to go back to the default.
- **Show on map** opens the remote view at the network.
- **Pin** adds the network to the pin bar.

## Alerts

- **Brownout**: satisfaction below the threshold (default 99 %) for longer than the delay (default 5 seconds).
- **Accumulators running out**: draining accumulators will be empty within the warning time (default 2 minutes).

Alerts are refreshed every second and disappear when the problem is gone. Small networks get no alerts.

## Performance

Factorio has no list of electric networks, so the mod tracks every electric pole and checks them in the background,
250 per tick by default (adjustable). Each network is measured once per second.

Poles are tracked through the build events. Poles that another mod creates without raising an event are found the next
time the mod configuration changes, or immediately with `remote.call("power-grid-dashboard", "rescan")`.

## Remote interface

```lua
remote.call("power-grid-dashboard", "get_networks") -- { { key, name, surface_index, poles, summary, lowest, problem, alerts }, ... }
remote.call("power-grid-dashboard", "update_now")
remote.call("power-grid-dashboard", "rename", key, "Main bus")
remote.call("power-grid-dashboard", "open", player_index)
remote.call("power-grid-dashboard", "rescan")
```

`summary` values are in watts and joules. Requires Factorio 2.1 (LuaElectricNetwork). MIT license.
