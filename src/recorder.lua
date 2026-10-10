local Recorder = {}
local key = "blorps"
local places = {}
local recording = false
local character = nil
local profiles = {}
local legacy = {}

local function sorted(set)
    local result = {}
    for name in pairs(set) do result[#result + 1] = name end
    table.sort(result)
    return result
end

-- Persist before changing memory, so a failed write leaves the displayed list intact.
local function commit(next_places)
    local next_profiles = {}
    for name, list in pairs(profiles) do next_profiles[name] = list end
    next_profiles[character] = sorted(next_places)
    local ok, err = pcall(storage.set, key, { version = 2, characters = next_profiles, legacy = sorted(legacy) })
    if not ok then
        mud.note("[blorps] Could not save places: " .. tostring(err), { fg = "red" })
        return false
    end
    profiles = next_profiles
    places = next_places
    return true
end

local function copy_places()
    local result = {}
    for name in pairs(places) do result[name] = true end
    return result
end

local function read_places(list)
    if type(list) ~= "table" then error("[blorps] Invalid saved list; refusing to overwrite it") end
    local result = {}
    for _, name in ipairs(list) do
        if type(name) ~= "string" or name == "" then
            error("[blorps] Invalid saved identification; refusing to overwrite it")
        end
        result[name] = true
    end
    return result
end

function Recorder.init()
    local saved = storage.get(key)
    if saved == nil then return end
    if type(saved) ~= "table" then error("[blorps] Invalid saved data; refusing to overwrite it") end
    if saved.version == 1 then
        legacy = read_places(saved.places)
    elseif saved.version == 2 and type(saved.characters) == "table" then
        legacy = read_places(saved.legacy or {})
        for name, list in pairs(saved.characters) do
            if type(name) ~= "string" or name == "" then error("[blorps] Invalid saved character") end
            profiles[name] = sorted(read_places(list))
        end
    else
        error("[blorps] Unsupported or invalid saved data; refusing to overwrite it")
    end
end

function Recorder.set_character(name)
    if type(name) == "string" then
        name = name:match("^%s*(.-)%s*$"):lower()
        if name == "" or name == "you" then name = nil end
    else
        name = nil
    end
    if name == character then return false end
    character = name
    recording = false
    places = name and read_places(profiles[name] or {}) or {}
    return true
end

function Recorder.import_legacy()
    if not character then return false end
    local next_places = copy_places()
    for name in pairs(legacy) do next_places[name] = true end
    return commit(next_places)
end

function Recorder.clear()
    if not character then return false, "character" end
    if not commit({}) then return false, "save" end
    recording = false
    return true
end

function Recorder.set_recording(value)
    recording = value == true and character ~= nil
    if value and not character then
        mud.note("[blorps] Waiting for the logged-in character name from Discworld.", { fg = "yellow" })
    end
end

function Recorder.display()
    return { recording = recording, character = character, places = sorted(places), legacy_count = #sorted(legacy) }
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
