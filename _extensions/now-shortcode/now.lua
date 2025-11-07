local utils = pandoc.utils

local function shortcode_value(value)
  if value == nil then
    return nil
  end
  if type(value) == "table" then
    return utils.stringify(value)
  end
  return tostring(value)
end

local function convert_format(format)
  if not format or format == "" then
    return "%Y-%m-%d"
  end
  local converted = format
  local matched = false
  local replacements = {
    { "YYYY", "%Y" },
    { "YY", "%y" },
    { "MMMM", "%B" },
    { "MMM", "%b" },
    { "MM", "%m" },
    { "DD", "%d" },
    { "HH", "%H" },
    { "hh", "%I" },
    { "mm", "%M" },
    { "ss", "%S" }
  }
  for _, mapping in ipairs(replacements) do
    local token, replacement = table.unpack(mapping)
    if converted:find(token, 1, true) then
      converted = converted:gsub(token, function()
        matched = true
        return replacement
      end)
    end
  end
  if not matched and not converted:find("%%") then
    return "%Y-%m-%d"
  end
  return converted
end

local function now_shortcode(args, kwargs)
  args = args or {}
  kwargs = kwargs or {}
  local format = shortcode_value(kwargs["format"]) or shortcode_value(kwargs["fmt"]) or shortcode_value(args[1])
    or "%Y-%m-%d"
  format = convert_format(format)
  local timezone = shortcode_value(kwargs["timezone"]) or shortcode_value(kwargs["tz"])
  local prefix = ""
  if timezone and type(timezone) == "string" and timezone:upper() == "UTC" then
    prefix = "!"
  end
  return os.date(prefix .. format)
end

return {
  now = now_shortcode
}
