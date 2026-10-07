local Recorder = {}
local key = "blorps"
local places = {}
local recording = false

local function sorted(set)
    local result = {}
    for name in pairs(set) do result[#result + 1] = name end
    table.sort(result)
    return result
end

-- Persist before changing memory, so a failed write leaves the displayed list intact.
local function commit(next_places)
    local ok, err = pcall(storage.set, key, { version = 1, places = sorted(next_places) })
    if not ok then
        mud.note("[blorps] Could not save places: " .. tostring(err), { fg = "red" })
        return false
    end
    places = next_places
    return true
end

local function copy_places()
    local result = {}
    for name in pairs(places) do result[name] = true end
    return result
end

function Recorder.init()
    local saved = storage.get(key)
    if saved == nil then return end
    if type(saved) ~= "table" or saved.version ~= 1 or type(saved.places) ~= "table" then
        error("[blorps] Unsupported or invalid saved data; refusing to overwrite it")
    end
    for _, name in ipairs(saved.places) do
        if type(name) ~= "string" or name == "" then
            error("[blorps] Invalid saved identification; refusing to overwrite it")
        end
        places[name] = true
    end
end

function Recorder.set_recording(value)
    recording = value == true
end

function Recorder.display()
    return { recording = recording, places = sorted(places) }
end

function Recorder.record(text)
    if not recording or type(text) ~= "string" then return false end
    local next_places = copy_places()
    local changed = false
    -- Lua pattern: scan every identification, including several on the same line.
    for name in text:gmatch('%("(.-)"%)') do
        if name ~= "" and not next_places[name] then
            next_places[name] = true
            changed = true
        end
    end
    return changed and commit(next_places) or false
end

function Recorder.remove(name)
    if not places[name] then return false, "missing" end
    local next_places = copy_places()
    next_places[name] = nil
    if not commit(next_places) then return false, "save" end
    return true
end

return Recorder
