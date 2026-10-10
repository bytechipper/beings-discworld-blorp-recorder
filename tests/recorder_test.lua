local saved, writes, fail = nil, 0, false
local notes, commands, events, messages, updates = {}, {}, {}, {}, {}
storage = {
    get = function(key) assert(key == "blorps"); return saved end,
    set = function(key, value)
        assert(key == "blorps")
        if fail then error("disk full") end
        writes = writes + 1
        saved = value
    end,
}
local gmcp_handlers = {}
gmcp = {
    get = function(key) if key == "char.info.name" then return "Alice" end end,
    on = function(name, callback) gmcp_handlers[name] = callback end,
}
local sent = {}
mud = {
    send = function(text) sent[#sent + 1] = text end,
    note = function(text) notes[#notes + 1] = text end,
    command_prefix = function() return "/" end,
    command = function(name, callback) commands[name] = callback end,
    panel = function(id)
        assert(id == "beings-discworld-blorp-recorder")
        return {
            post = function(_, name, data)
                assert(name == "update"); updates[#updates + 1] = data
            end,
            on_message = function(_, name, callback) messages[name] = callback end,
        }
    end,
}
world = { on = function(name, callback) events[name] = callback end }
require = function(name) assert(name == "recorder"); return dofile("src/recorder.lua") end
dofile("src/main.lua")
local function latest() return updates[#updates] end
local function line(text) events.line({text = text}) end
messages.ready()
assert(not latest().recording and #latest().places == 0)
line('The necklace ("ignored") is in the pack.')
assert(writes == 0)
commands.blorps_rec_start()
assert(latest().recording)
local examples = {
    'The ruby wedding necklace ("smugglers") is in the hunter\'s pack.',
    'The twisting myrtle necklet ("savannah") is in the hunter\'s pack.',
    'The ruby wedding necklace ("dojo") is in the hunter\'s pack.',
    'The twisting myrtle necklet ("casino") is in the hunter\'s pack.',
    'The twisting myrtle necklet ("lancre") is in the hunter\'s pack.',
}
for _, text in ipairs(examples) do line(text) end
assert(#latest().places == 5 and writes == 5)
for _, text in ipairs(examples) do line(text) end
assert(writes == 5)
line('A boot ("two words"), a spoon ("<b>place</b>"), and a ring ("dojo").')
assert(#latest().places == 7 and writes == 6)
messages.go({name = "dojo"})
messages.go({name = "two words"})
assert(sent[1] == "go dojo" and sent[2] == "go two words")
messages.go({name = "missing"})
messages.go({name = "dojo\nquit"})
messages.go({name = 42})
messages.go(nil)
assert(#sent == 2)
line('Unidentified jewellery; (""), ("unfinished')
assert(#latest().places == 7 and writes == 6)
commands.blorps_rec_stop()
line('A ring ("ignored")')
assert(writes == 6 and not latest().recording)
commands.blorps_remove({args = "dojo"})
assert(#latest().places == 6 and writes == 7)
messages.go({name = "dojo"})
assert(#sent == 2)
commands.blorps_remove({args = "missing"})
commands.blorps_remove({args = ""})
assert(writes == 7)
fail = true
commands.blorps_remove({args = "casino"})
assert(#latest().places == 6 and writes == 7)
messages.start()
line('A stone ("unsaved")')
assert(#latest().places == 6 and writes == 7)
fail = false
line('A stone ("unsaved")')
assert(#latest().places == 7 and writes == 8)
messages.remove({name = "two words"})
assert(#latest().places == 6)
events.disconnect()
assert(not latest().recording)
line('A ring ("after disconnect")')
assert(#latest().places == 0 and latest().character == nil)
dofile("src/main.lua")
messages.ready()
assert(#latest().places == 6 and not latest().recording)
for _, name in ipairs(latest().places) do assert(name ~= "dojo") end
commands.blorps()
assert(notes[#notes] == "6 places saved.")
messages.start()
line('A different necklace ("dojo")')
assert(#latest().places == 7)
messages.see({name = "dojo"})
messages.see({name = "casino"})
assert(sent[#sent - 1] == "see dojo" and sent[#sent] == "see casino")
local send_count = #sent
messages.see({name = "missing"})
messages.see({name = "dojo\nquit"})
messages.see({name = "dojo\rquit"})
messages.see({name = 42})
messages.see(nil)
assert(#sent == send_count)
-- Switching characters isolates lists and stops recording; names ignore case.
gmcp_handlers["char.info"]("char.info", {name = "Bob"})
assert(latest().character == "bob" and #latest().places == 0 and not latest().recording)
messages.go({name = "dojo"})
assert(#sent == send_count)
messages.start()
line('A ring ("bob only")')
assert(#latest().places == 1)
gmcp_handlers["char.info"]("char.info", {name = "ALICE"})
assert(#latest().places == 7 and not latest().recording)
gmcp_handlers["char.info"]("char.info", {name = "Bob"})
assert(latest().places[1] == "bob only")
events.disconnect()
messages.start()
line('A ring ("unknown")')
assert(not latest().recording and #latest().places == 0)
-- Old shared data is retained until explicitly copied to a known character.
saved = {version = 1, places = {"old shared"}}
dofile("src/main.lua")
messages.ready()
assert(#latest().places == 0 and latest().legacy_count == 1)
fail = true
commands.blorps_import_legacy()
assert(#latest().places == 0 and saved.version == 1)
fail = false
commands.blorps_import_legacy()
assert(latest().places[1] == "old shared" and saved.version == 2)
assert(saved.legacy[1] == "old shared")
gmcp_handlers["char.info"]("char.info", {name = "Bob"})
assert(#latest().places == 0)
dofile("src/main.lua")
messages.ready()
assert(latest().places[1] == "old shared")
-- Clearing is persisted, isolated, and leaves memory unchanged on write failure.
gmcp_handlers["char.info"]("char.info", {name = "Bob"})
messages.start()
line('A ring ("bob keep")')
gmcp_handlers["char.info"]("char.info", {name = "Alice"})
messages.start()
fail = true
local before_clear = writes
commands.blorps_clear()
assert(writes == before_clear and latest().places[1] == "old shared" and latest().recording)
fail = false
commands.blorps_clear()
assert(#latest().places == 0 and not latest().recording)
assert(notes[#notes]:find("Cleared all places for alice", 1, true))
line('A ring ("must not return")')
assert(#latest().places == 0)
assert(saved.legacy[1] == "old shared" and saved.characters.bob[1] == "bob keep")
dofile("src/main.lua")
messages.ready()
assert(#latest().places == 0)
gmcp_handlers["char.info"]("char.info", {name = "Bob"})
assert(latest().places[1] == "bob keep")
events.disconnect()
local before_unknown = writes
commands.blorps_clear()
assert(writes == before_unknown)
assert(notes[#notes]:find("Waiting for", 1, true))
local write_count = writes
saved = { version = 99, places = {} }
assert(not pcall(dofile, "src/main.lua"))
assert(writes == write_count)
print("PASS: recording boundaries, all examples, multiple IDs, deduplication, removal, persistence, panel messages, disconnect, and write failures")
