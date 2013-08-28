--[[--
	The settings interface reads and writes configuration keys using UCI.
	All keys have pre-defined defaults in @{conf_defaults} which will be used
	if no value is stored in the UCI config. The UCI config file is
	'/etc/config/wifibox'.
	The default values guarantee there will always be a set of reasonable settings
	to use and provide a clear overview of all existing configuration keys as well.
	
	By the way, returning correct values in get()/fromUciValue() for booleans has
	been fixed at a relatively convenient time purely thanks to the unit tests...
	just to indicate how useful they are. :)
]]
local uci = require('uci').cursor()
local utils = require('util.utils')
local baseconfig = require('conf_defaults')

local M = {}

--- UCI config name (i.e. file under /etc/config)
local UCI_CONFIG_NAME = 'wifibox'

--- Absolute path to the UCI config file
local UCI_CONFIG_FILE = '/etc/config/' .. UCI_CONFIG_NAME

--- Section type that will be used in UCI\_CONFIG\_FILE
local UCI_CONFIG_TYPE = 'settings'

--- Section name that will be used for 'public' settings (as predefined in conf_defaults.lua) in UCI\_CONFIG\_FILE
local UCI_CONFIG_SECTION = 'general'

--- Section name that will be used for 'firmware-local' settings in UCI\_CONFIG\_FILE
local UCI_CONFIG_SYSTEM_SECTION = 'system'

local ERR_NO_SUCH_KEY = "key does not exist"


--- Returns a key with all periods ('.') replaced by underscores ('_').
-- @tparam string key The key for which to substitute dots.
-- @return The substituted key, or the key parameter itself if it is not of type 'string'.
local function replaceDots(key)
	if type(key) ~= 'string' then return key end
	local r = key:gsub('%.', '_')
	return r
end

--- Returns a key with all underscores ('_') replaced by periods ('.').
-- @tparam string key The key for which to substitute underscores.
-- @return The substituted key, or the key parameter itself if it is not of type 'string'.
local function replaceUnderscores(key)
	if type(key) ~= 'string' then return key end
	local r = key:gsub('_', '%.')
	return r
end

--- Converts a lua value to equivalent representation for UCI.
-- Boolean values are converted to '1' and '0', everything else is converted to a string.
--
-- @param v The value to convert.
-- @param vType The type of the given value.
-- @return A value usable to write to UCI.
local function toUciValue(v, vType)
	if vType == 'bool' then return v and '1' or '0' end
	if(vType == 'string') then 
		v = v:gsub('[\n\r]', '\\n') 
	end

	return tostring(v)
end

--- Converts a value read from UCI to a correctly typed lua value.
-- For boolean, '1' is converted to true and everything else to false. Floats
-- and ints are converted to numbers and everything else will be returned as is.
--
-- @param v The value to convert.
-- @param vType The type of the given value.
-- @return A lua value typed correctly with regard to the vType parameter.
local function fromUciValue(v, vType)
	if v == nil then return nil end
	
	if vType == 'bool' then
		return (v == '1') and true or false
	elseif vType == 'float' or vType == 'int' then
		return tonumber(v)
	elseif vType == 'string' then
		v = v:gsub('\\n', '\n') 
		return v
	else
		return v
	end
	
end

--- Reports whether a value is valid given the constraints specified in a base table.
-- @param value The value to test.
-- @tparam table baseTable The base table to use constraint data from (min,max,regex).
-- @treturn bool Returns true if the value is valid, false if it is not.
local function isValid(value, baseTable)
	local varType, min, max, regex, isValid = baseTable.type, baseTable.min, baseTable.max, baseTable.regex, baseTable.isValid

	if isValid then 
		local ok = isValid(value)
		return ok or nil,"invalid value"
	end

	if varType == 'bool' then
		return type(value) == 'boolean' or nil,"invalid bool value"
		
	elseif varType == 'int' or varType == 'float' then
		local numValue = tonumber(value)
		local ok = numValue and true or false
		ok = ok and (varType == 'float' or math.floor(numValue) == numValue)
		if min then ok = ok and numValue >= min end
		if max then ok = ok and numValue <= max end
		return ok or nil,"invalid int/float value or out of range"
		
	elseif varType == 'string' then
		local ok = true
		if min then ok = ok and value:len() >= min end
		if max then ok = ok and value:len() <= max end
		if regex then ok = ok and value:match(regex) ~= nil end
		return ok or nil,"invalid string value"
	end

	return true
end

--- Looks up the table in conf_defaults.lua corresponding to a key.
-- @tparam string key The key for which to return the base table.
-- @treturn table The base table for key, or nil if it does not exist.
local function getBaseKeyTable(key)
	local base = baseconfig[key]
	return type(base) == 'table' and base.default ~= nil and base or nil
end


--- Returns the value of the requested key if it exists.
-- @param key The key to return the associated value for.
-- @return The associated value, beware (!) that this may be boolean false for keys of 'bool' type.
function M.get(key)
	key = replaceDots(key)
	local base = getBaseKeyTable(key)
	
	if not base then return nil,ERR_NO_SUCH_KEY end
	
	local v = base.default
	local uciV = fromUciValue(uci:get(UCI_CONFIG_NAME, UCI_CONFIG_SECTION, key), base.type)

	local actualV = v
	if uciV ~= nil then actualV = uciV end
	
	return actualV
end

--- Returns all configuration keys with their current values.
-- @treturn table A table containing a key/value pair for each configuration key.
function M.getAll()
	local result = {}
	for k,_ in pairs(baseconfig) do
		if not k:match('^[A-Z_]*$') then --TEMP: skip 'constants', which should be moved anyway
			local key = replaceUnderscores(k)
			result[key] = M.get(key)
		end
	end
	return result
end

--- Reports whether or not a key exists.
-- @tparam string key The key to find.
-- @treturn bool True if the key exists, false if not.
function M.exists(key)
	key = replaceDots(key)
	return getBaseKeyTable(key) ~= nil
end

--- Reports whether or not a key is at its default value.
-- 'Default' in this regard means that no UCI value is defined. This means that
-- if for instance, the default is 'abc', and UCI contains a configured value of
-- 'abc' as well, that key is _not_ a default value.
--
-- @tparam string key The key to report about.
-- @treturn bool True if the key is currently at its default value, false if not.
function M.isDefault(key)
	key = replaceDots(key)
	if not M.exists(key) then return nil,ERR_NO_SUCH_KEY end
	return uci:get(UCI_CONFIG_NAME, UCI_CONFIG_SECTION, key) == nil
end

--- Sets a key to a new value or reverts it to the default value.
-- @tparam string key The key to set.
-- @param value The value or set, or nil to revert key to its default value.
-- @treturn bool|nil True if everything went well, nil in case of error.
-- @treturn ?string Error message in case first return value is nil (invalid key).
function M.set(key, value)
	key = replaceDots(key)

	local r = utils.create(UCI_CONFIG_FILE)
	uci:set(UCI_CONFIG_NAME, UCI_CONFIG_SECTION, UCI_CONFIG_TYPE)
	
	local base = getBaseKeyTable(key)
	if not base then return nil,ERR_NO_SUCH_KEY end

	if M.isDefault(key) and value == nil then return true end -- key is default already
	
	local current = uci:get(UCI_CONFIG_NAME, UCI_CONFIG_SECTION, key)
	
	if base.type == 'bool' then
		if value ~= "" then
			value = utils.toboolean(value)
		else
			value = nil
		end
	elseif base.type == 'int' or base.type == 'float' then
		value = tonumber(value)
		if(value == nil) then 
			return nil,"Value isn't a valid int or float"
		end
	end

	if fromUciValue(current, base.type) == value then return true end

	if value ~= nil then
		local valid,m = isValid(value, base)
		if (valid) then
			uci:set(UCI_CONFIG_NAME, UCI_CONFIG_SECTION, key, toUciValue(value, base.type))
		else
			return nil,m
		end
	else
		uci:delete(UCI_CONFIG_NAME, UCI_CONFIG_SECTION, key)
	end
	
	uci:commit(UCI_CONFIG_NAME)
	return true
end

--- Returns a UCI configuration key from the system section.
-- @tparam string key The key for which to return the value, must be non-empty.
-- @return Requested value or false if it does not exist or nil on invalid key.
function M.getSystemKey(key)
	if type(key) ~= 'string' or key:len() == 0 then return nil end
	local v = uci:get(UCI_CONFIG_NAME, UCI_CONFIG_SYSTEM_SECTION, key)
	return v or false
end

--- Sets the given key to the given value.
-- Note that unlike the public settings, system keys are untyped and value must
-- be of type string; UCI generally uses '1' and '0' for boolean values.
-- @tparam string key The key to set, must be non-empty.
-- @tparam string value The value to set key to.
-- @return True on success or false if key or value arguments are invalid.
function M.setSystemKey(key, value)
	if type(key) ~= 'string' or key:len() == 0 then return nil end
	if type(value) ~= 'string' then return nil end
	
	local r = utils.create(UCI_CONFIG_FILE) -- make sure the file exists for uci to write to
	uci:set(UCI_CONFIG_NAME, UCI_CONFIG_SYSTEM_SECTION, UCI_CONFIG_TYPE)
	uci:set(UCI_CONFIG_NAME, UCI_CONFIG_SYSTEM_SECTION, key, value)
	uci:commit(UCI_CONFIG_NAME)
	
	return true
end

return M
