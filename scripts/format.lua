-- Number, power and duration formatting.

local format = {}

local SUFFIXES = { "", "k", "M", "G", "T", "P", "E" }

--- 1234 -> "1.23k"
function format.number(n)
  local negative = n < 0
  local abs = math.abs(n)
  local i = 1
  while abs >= 1000 and i < #SUFFIXES do
    abs = abs / 1000
    i = i + 1
  end
  local text
  if abs >= 100 or (i == 1 and abs == math.floor(abs)) then
    text = string.format("%d", math.floor(abs + 0.5))
  elseif abs >= 10 then
    text = string.format("%.1f", abs)
  else
    text = string.format("%.2f", abs)
  end
  return (negative and "-" or "") .. text .. SUFFIXES[i]
end

--- Watts -> "12.3 MW"
function format.power(watts)
  local text = format.number(watts)
  local suffix = string.match(text, "%a$")
  if suffix then
    return string.sub(text, 1, -2) .. " " .. suffix .. "W"
  end
  return text .. " W"
end

--- 0.4567 -> "46%" (never shows 100% for anything below 1)
function format.percent(fraction)
  local percent = math.floor(fraction * 100 + 0.5)
  if percent == 100 and fraction < 1 then
    percent = 99
  end
  return string.format("%d%%", percent)
end

--- Seconds -> "3h 12m", "12m 5s" or "45s"
function format.duration(seconds)
  seconds = math.floor(seconds + 0.5)
  if seconds >= 100 * 3600 then
    return { "power-grid-dashboard.duration-long" }
  end
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return { "power-grid-dashboard.duration-hm", h, m }
  elseif m > 0 then
    return { "power-grid-dashboard.duration-ms", m, s }
  end
  return { "power-grid-dashboard.duration-s", s }
end

return format
