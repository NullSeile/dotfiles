-- Launcher provider for the example plugin.
--
-- Type `/ex` in the launcher. The top level lists categories; pressing Enter on
-- one calls launcher.setQuery() to rewrite the input (e.g. `/ex fruits `) and
-- drill into it WITHOUT closing the launcher. Pressing Enter on a leaf item
-- copies it and lets the launcher close normally.
--
-- launcher.setQuery() takes effect when called from a handler while the launcher
-- is open. Called synchronously from onActivate it keeps the panel open and
-- rewrites the input instead of closing — the basis for autocomplete / drill-in.


function onQuery(query)
  local entries = {}

  noctalia.log("fish.luau: onQuery: " .. query)

  local prefix = string.match(query, "^(.*%s)")
  if not prefix then
    prefix = ""
  end

  local escaped_query = query:gsub('"', '\\"'):gsub("'", "\\'")
  noctalia.runAsync('fish -c "complete -C \\"' .. escaped_query .. '\\"" 2>/dev/null', function(result)

    for l in result.stdout:gmatch("([^\n]*)\n?") do
      local line = noctalia.string.trim(l)
      if line ~= "" then
        local tab_index = line:find("\t")
        local completion = line
        local description = ""

        if tab_index then
          completion = line:sub(1, tab_index - 1)
          description = line:sub(tab_index + 1)
        end

        local fullCommand = prefix .. completion

        table.insert(entries, {
          id = fullCommand,
          text = fullCommand,
          subtitle = description,
        })
      end
      launcher.setResults(query, entries)
    end
  end)
end

function onActivate(id)
  noctalia.notify("fish", id)
  noctalia.runInTerminal('fish -c "' .. id .. '"')
end

