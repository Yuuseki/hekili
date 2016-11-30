-- Scripts.lua
-- December 2014

local addon, ns = ...
local Hekili = _G[ addon ]

local class = ns.class
local scripts = ns.scripts
local state = ns.state

local trim = string.trim

Hekili.Scripts = scripts.A

-- Convert SimC syntax to Lua conditionals.
local SimToLua = function( str, modifier )

  -- If no conditions were provided, function should return true.
  if not str or str == '' then return nil end

  -- Strip comments.
  str = str:gsub("^%-%-.-\n", "")

  -- Replace '%' for division with actual division operator '/'.
  str = str:gsub("%%", "/")

  -- Replace '&' with ' and '.
  str = str:gsub("&", " and ")

  -- Replace '|' with ' or '.
  str = str:gsub("||", " or "):gsub("|", " or ")

  if not modifier then
    -- Replace assignment '=' with conditional '=='
    str = str:gsub("=", "==")

    -- Fix any conditional '==' that got impacted by previous.
    str = str:gsub("==+", "==")
    str = str:gsub(">=+", ">=")
    str = str:gsub("<=+", "<=")
    str = str:gsub("!=+", "~=")
    str = str:gsub("~=+", "~=")
  end

  -- Replace '!' with ' not '.
  str = str:gsub("!(.-) ", " not (%1) " )
  str = str:gsub("!(.-)$", " not (%1)" )
  str = str:gsub("!([^=])", " not %1")

  -- Condense whitespace.
  str = str:gsub("%s+", " ")

  -- Condense parenthetical spaces.
  str = str:gsub("[(][%s+]", "("):gsub("[%s+][)]", ")")

  return str

end


local storeValues = function( tbl, node )

  if not node.Elements then
    return
  end

  for k in pairs( tbl ) do
    tbl[k] = nil
  end

  for k, v in pairs( node.Elements ) do
    local success, result = pcall( v )

    if success then tbl[k] = result
    elseif type( result ) == 'string' then
      tbl[k] = result:match( "lua:%d+: (.*)" ) or result
    else tbl[k] = 'nil' end
  end
end
ns.storeValues = storeValues


function ns.storeReadyValues( tbl, node )

    if not node.Elements then
        return
    end

    if node.ReadyElements then
        for k, v in pairs( node.ReadyElements ) do
            local success, result = pcall( v )

            if success then tbl[k] = result
            elseif type( result ) == 'string' then
                tbl[k] = result:match( "lua:%d+: (.*)" ) or result
            else tbl[k] = 'nil' end
        end
    end

end


local stripScript = function( str, thorough )
  if not str then return 'true' end

  -- Remove the 'return ' that was added during conversion.
  str = str:gsub("^return ", "")

  -- Remove comments and parentheses.
  str = str:gsub("%-%-.-\n", ""):gsub("[()]", "")

  -- Remove conjunctions.
  str = str:gsub("[%s-]and[%s-]", " "):gsub("[%s-]or[%s-]", " "):gsub("%(-%s-not[%s-]", " ")

  if not thorough then
    -- Collapse whitespace around comparison operators.
    str = str:gsub("[%s-]==[%s-]", "=="):gsub("[%s-]>=[%s-]", ">="):gsub("[%s-]<=[%s-]", "<="):gsub("[%s-]~=[%s-]", "~="):gsub("[%s-]<[%s-]", "<"):gsub("[%s-]>[%s-]", ">")
  else
    str = str:gsub("[=+]", " "):gsub("[><~]", " "):gsub("[%*//%-%+]", " ")
  end

  -- Collapse the rest of the whitespace.
  str = str:gsub("[%s+]", " ")

  return ( str )
end


local getScriptElements = function( script )
  local Elements, Check = {}, stripScript( script, true )

  for i in Check:gmatch( "%S+" ) do
    if not Elements[i] and not tonumber(i) then
      local eFunction = loadstring( 'return '.. (i or true) )

      if eFunction then setfenv( eFunction, state ) end

      local success, value = pcall( eFunction )

      Elements[i] = eFunction
    end
  end

  return Elements
end


local convertScript = function( node, hasModifiers )
  local Translated = SimToLua( node.Script )
  local sFunction, Error

  if Translated then
    sFunction, Error = loadstring( 'return ' .. Translated )
  end

  if sFunction then
    setfenv( sFunction, state )
  end

  if Error then
    Error = Error:match( ":%d+: (.*)" )
  end

  local sElements = Translated and getScriptElements( Translated )

  local Output = {
    Conditions = sFunction,
    Error = Error,
    Elements = sElements,
    Modifiers = {},

    Lua = Translated,
    SimC = node.Script and trim( node.Script ) or nil
  }

  if hasModifiers and ( node.Args and node.Args ~= '' ) then
    local tModifiers = SimToLua( node.Args, true )

    for m in tModifiers:gmatch("[^,|^$]+") do
      local Key, Value = m:match("^(.-)=(.-)$")

      if Key and Value then
        local sFunction, Error = loadstring( 'return ' .. Value )

        if sFunction then
          setfenv( sFunction, state )
          Output.Modifiers[ Key ] = sFunction
        else
          Output.Modifiers[ Key ] = Error
        end
      end
    end
  end

  if hasModifiers and ( node.ReadyTime and node.ReadyTime ~= '' ) then
    local tReady = SimToLua( node.ReadyTime, true )
    local rFunction, rError

    if tReady then
        rFunction, rError = loadstring( 'return function( delay, spend, spend_type )\n' ..
            'return max( 0, delay, ' .. tReady .. ' )\n' ..
            'end' )
    end

    if rFunction then
        _, rFunction = pcall( rFunction )
        setfenv( rFunction, state )
    end

    if rError then
        rError = rError:match( ":%d+: (.*)" )
    end

    Output.Ready = rFunction
    Output.ReadyError = rError
    Output.ReadyLua = tReady
    Output.ReadyElements = tReady and getScriptElements( tReady )
  end

  return Output
end


ns.checkScript = function( cat, key, action, override, delay )

  if action then state.this_action = action end

  local tblScript = scripts[ cat ][ key ]

  if not tblScript then
    return false

  elseif tblScript.Error then
    return false, tblScript.Error

  elseif tblScript.Conditions == nil then
    return true

  else
    delay = delay or 0
    local offset = state.offset
    state.offset = offset + delay

    local success, value = pcall( tblScript.Conditions )

    state.offset = offset

    if success then
      return value
    end
  end

  return false

end
local checkScript = ns.checkScript


function ns.checkTimeScript( entry, delay, spend, spend_type )

    local script = scripts.A[ entry ]

    if not entry or not script or not script.Ready then return delay end

    local out = script.Ready( delay, spend, spend_type )

    return out

end


ns.getModifiers = function( list, entry )

  local mods = {}

  if not scripts['A'][list..':'..entry].Modifiers then return mods end

  for k,v in pairs( scripts['A'][list..':'..entry].Modifiers ) do
    local success, value = pcall(v)
    if success then mods[k] = value end
  end

  return mods

end
local getModifiers = ns.getModifiers
state.getModifiers = getModifiers


ns.importModifiers = function( list, entry )

  for k in pairs( state.args ) do
    state.args[ k ] = nil
  end

  if not scripts['A'][list..':'..entry].Modifiers then return end

  for k,v in pairs( scripts['A'][list..':'..entry].Modifiers ) do
    local success, value = pcall(v)
    if success then state.args[k] = value end
  end

end


ns.loadScripts = function()

  local Displays, Hooks, Actions = scripts.D, scripts.P, scripts.A
  local Profile = Hekili.DB.profile

  for i, _ in ipairs( Displays ) do
    Displays[i] = nil
  end

  for k, _ in pairs( Hooks ) do
    Hooks[k] = nil
  end

  for k, _ in pairs( Actions ) do
    Actions[k] = nil
  end

  for i, display in ipairs( Hekili.DB.profile.displays ) do
    Displays[ i ] = convertScript( display )

    for j, priority in ipairs( display.Queues ) do
      local pKey = i..':'..j
      Hooks[ pKey ] = convertScript( priority )
    end
  end

  for i, list in ipairs( Hekili.DB.profile.actionLists ) do
    for a, action in ipairs( list.Actions ) do
      local aKey = i..':'..a
      Actions[ aKey ] = convertScript( action, true )
    end
  end
end
local loadScripts = ns.loadScripts


function ns.implantDebugData( queue )
  if queue.display and queue.hook then
    if type( queue.hook ) == 'string' then
      -- this was a nested action list.
      local scrHook = scripts.A[ queue.hook ]
      local list, action = queue.hook:match( "(%d+):(%d+)" )
      queue.HookHeader = 'Called from ' .. Hekili.DB.profile.actionLists[ tonumber( list ) ].Name .. ' #' .. action
      queue.HookScript = scrHook.SimC
      queue.HookElements = queue.HookElements or {}
      storeValues( queue.HookElements, scrHook )
    else
      local scrHook = scripts.P[ queue.display..':'..queue.hook ]
      queue.HookScript = scrHook.SimC
      queue.HookElements = queue.HookElements or {}
      storeValues( queue.HookElements, scrHook )
    end
  end

  if queue.list and queue.action then
    local scrAction = scripts.A[ queue.list..':'..queue.action ]
    
    if queue.scriptType == 'simc' then
        queue.ActScript = scrAction.SimC
        queue.ActElements = queue.ActElements or {}
        storeValues( queue.ActElements, scrAction )
    elseif queue.scriptType == 'time' then
        queue.ActScript = scrAction.ReadyLua
        queue.ActElements = queue.ReadyElements or {}
        ns.storeReadyValues( queue.ActElements, scrAction )
    else
        queue.ActElements = queue.ActElements or {}

    end
  end
end
