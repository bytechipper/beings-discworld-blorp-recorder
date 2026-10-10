local Recorder = require("recorder")
Recorder.init()
local panel = mud.panel("beings-discworld-blorp-recorder")

local function update()
    panel:post("update", Recorder.display())
end

-- Read mirrored identity when enabled during an existing session.
Recorder.set_character(gmcp.get("char.info.name") or gmcp.get("Char.Info.name"))

local function identity(_, data)
    if type(data) == "table" and data.name ~= nil and Recorder.set_character(data.name) then update() end
end
gmcp.on("char.info", identity)
gmcp.on("Char.Info", identity)

local function set_recording(value)
    Recorder.set_recording(value)
    mud.note("[blorps] Recording " .. (Recorder.display().recording and "started." or "stopped."), { fg = "cyan" })
    update()
end

local function remove(name)
    if type(name) ~= "string" or name == "" then
        mud.note("[blorps] Usage: " .. mud.command_prefix() .. "blorps_remove <identification>", { fg = "yellow" })
        return
    end
    local ok, reason = Recorder.remove(name)
    if ok then
        mud.note("[blorps] Removed: " .. name, { fg = "green" })
        update()
    elseif reason == "missing" then
        mud.note("[blorps] Place not found: " .. name, { fg = "yellow" })
    end
end

mud.command("blorps_rec_start", function() set_recording(true) end,
    { description = "Start recording identified items" })
mud.command("blorps_rec_stop", function() set_recording(false) end,
    { description = "Stop recording identified items" })
mud.command("blorps_remove", function(m) remove(m.args) end,
    { description = "Remove a saved blorp identification", usage = "/blorps_remove <identification>" })
mud.command("blorps", function()
    local data = Recorder.display()
    mud.note(".:: Blorped Places ::.", { bold = true })
    mud.note("Character: " .. (data.character or "waiting for login"))
    mud.note("Recording: " .. (data.recording and "on" or "off"))
    for _, name in ipairs(data.places) do mud.note(" - " .. name) end
    mud.note(tostring(#data.places) .. " places saved.")
end, { description = "List saved blorped places" })

mud.command("blorps_clear", function()
    local ok, reason = Recorder.clear()
    if ok then
        mud.note("[blorps] Cleared all places for " .. Recorder.display().character .. "; recording stopped.", { fg = "green" })
        update()
    elseif reason == "character" then
        mud.note("[blorps] Waiting for the logged-in character name from Discworld.", { fg = "yellow" })
    end
end, { description = "Clear all saved blorps for the current character and stop recording" })

mud.command("blorps_import_legacy", function()
    if Recorder.import_legacy() then
        mud.note("[blorps] Imported old shared places for " .. Recorder.display().character .. ".", { fg = "green" })
        update()
    end
end, { description = "Copy the old shared blorps into the current character's list" })

world.on("line", function(line)
    if Recorder.record(line.text) then update() end
end)
world.on("disconnect", function()
    Recorder.set_character(nil)
    Recorder.set_recording(false)
    update()
end)

panel:on_message("ready", update)
panel:on_message("start", function() set_recording(true) end)
panel:on_message("stop", function() set_recording(false) end)
panel:on_message("remove", function(data)
    if type(data) == "table" then remove(data.name) end
end)

local function send_place_command(command, data)
    if type(data) ~= "table" or type(data.name) ~= "string" then return end
    local name = data.name
    -- mud.send fans out newlines; each click must send exactly one command.
    if name == "" or name:find("[\r\n]") then return end
    for _, place in ipairs(Recorder.display().places) do
        if place == name then
            mud.send(command .. " " .. name)
            return
        end
    end
end

panel:on_message("go", function(data) send_place_command("go", data) end)
panel:on_message("see", function(data) send_place_command("see", data) end)
