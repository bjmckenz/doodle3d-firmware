-- NOTE: the module 'detects' command-line invocation by existence of 'arg', so we have to make sure it is not defined.
argStash = arg
arg = nil
local updater = require('script.d3d-updater')
arg = argStash

local log = require('util.logger')
local utils = require('util.utils')

local M = {
	isApi = true
}

function M.status(request, response)
	updater.setLogger(log)
	updater.setUseCache(false)
	local success,status,msg = updater.getStatus()
	
	--response:addData('current_version', status.currentVersion)
	response:addData('current_version', updater.formatVersion(status.currentVersion))
	
	response:addData('state_code', status.stateCode)
	response:addData('state_text', status.stateText)
	
	if not success then
		response:setFail(msg)
		return
	end

	local canUpdate = updater.compareVersions(status.newestVersion, status.currentVersion) > 0
		
	--response:addData('newest_version', status.newestVersion)
	response:addData('newest_version', updater.formatVersion(status.newestVersion))
	response:addData('can_update', canUpdate)
	
	if status.progress then response:addData('progress', status.progress) end
	if status.imageSize then response:addData('image_size', status.imageSize) end
	response:setSuccess()
end

-- accepts: version(string) (major.minor.patch)
-- accepts: clear_gcode(bool, defaults to true) (this is to lower the chance on out-of-memory crashes, but still allows overriding this behaviour)
-- accepts: clear_images(bool, defaults to true) (same rationale as with clear_gcode)
-- note: call this with a long timeout - downloading may take a while (e.g. ~3.3MB with slow internet...)
function M.download_POST(request, response)
	local argVersion = request:get("version")
	local argClearGcode = utils.toboolean(request:get("clear_gcode"))
	local argClearImages = utils.toboolean(request:get("clear_images"))
	if argClearGcode == nil then argClearGcode = true end
	if argClearImages == nil then argClearImages = true end

	updater.setLogger(log)
	
	updater.setState(updater.STATE.DOWNLOADING,"")
	
	local vEnt, rv, msg
	
	if not argVersion then
		local success,status,msg = updater.getStatus()
		if not success then
			updater.setState(updater.STATE.DOWNLOAD_FAILED, msg)
			response:setFail(msg)
			return
		else 
			argVersion = updater.formatVersion(status.newestVersion)
		end
	end
	
	if argClearImages then
		rv,msg = updater.clear()
		if not rv then
			updater.setState(updater.STATE.DOWNLOAD_FAILED, msg)
			response:setFail(msg)
			return
		end
	end

	if argClearGcode then
		response:addData('gcode_clear',true)
		local rv,msg = printer:clearGcode()

		if not rv then
			updater.setState(updater.STATE.DOWNLOAD_FAILED, msg)
			response:setError(msg)
			return
		end
	end

	vEnt,msg = updater.findVersion(argVersion)
	if vEnt == nil then
		updater.setState(updater.STATE.DOWNLOAD_FAILED, "error searching version index (" .. msg .. ")")
		response:setFail("error searching version index (" .. msg .. ")")
		return
	elseif vEnt == false then
		updater.setState(updater.STATE.DOWNLOAD_FAILED, "no such version")
		response:setFail("no such version")
		return
	end

	rv,msg = updater.downloadImageFile(vEnt)
	if not rv then
		updater.setState(updater.STATE.DOWNLOAD_FAILED, msg)
		response:setFail(msg)
		return
	end

	response:setSuccess()
end

-- if successful, this call won't return since the device will flash its memory and reboot
function M.install_POST(request, response)
	local argVersion = request:get("version")
	updater.setLogger(log)
	
	log:info("API:update/install")
	updater.setState(updater.STATE.INSTALLING,"")
	
	if not argVersion then
		local success,status,msg = updater.getStatus()
		if not success then
			updater.setState(updater.STATE.INSTALL_FAILED, msg)
			response:setFail(msg)
			return
		else 
			argVersion = updater.formatVersion(status.newestVersion)
		end
	end

	vEnt,msg = updater.findVersion(argVersion)
	if vEnt == nil then
		updater.setState(updater.STATE.INSTALL_FAILED, "error searching version index (" .. msg .. ")")
		response:setFail("error searching version index (" .. msg .. ")")
		return
	elseif vEnt == false then
		updater.setState(updater.STATE.INSTALL_FAILED, "no such version")
		response:setFail("no such version")
		return
	end

	local rv,msg = updater.flashImageVersion(vEnt)

	if not rv then
		updater.setState(updater.STATE.INSTALL_FAILED, "installation failed (" .. msg .. ")")
		response:setFail("installation failed (" .. msg .. ")")
	else 
		response:setSuccess()
	end
end

function M.clear_POST(request, response)
	updater.setLogger(log)
	local rv,msg = updater.clear()

	if rv then response:setSuccess()
	else response:setFail(msg)
	end
end

return M
