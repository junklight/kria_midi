-- Kria MIDI
--
-- Port of Kira from Ansible
--
-- original code by Tehn
--
--

-- don't need an engine
-- but it seems to do a sine noise
-- if you don't specifiy one
-- engine.name = "ack"
local MusicUtil = require "musicutil"
local UI = require "ui"
local kria = require 'kria_midi/lib/kria'
local BeatClock = require 'kria_midi/lib/beattest'
local clk = BeatClock.new()
local clk_midi = midi.connect()
clk_midi.event = function(data)
  clk:process_midi(data)
end

  

local options = {}
options.STEP_LENGTH_NAMES = {"1 bar", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32", "1/48", "1/64"}
options.STEP_LENGTH_DIVIDERS = {1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64}

local g = grid.connect(1)
function g.key(x,y,z) gridkey(x,y,z) end
local k

local preset_mode = false
local clocked = true
local clock_count = 1


local note_list = {}
local screen_notes = { -1 , -1 , -1 , -1 }

local root_note = 60

local playback_icon = UI.PlaybackIcon.new(121, 55)
playback_icon.status = 1

local midi_in_device
local midi_out_device


function process_midi_in(data)
  local msg = midi.to_msg(data)
  if msg.type == "note_on" then
    root_note = msg.note
  else
    clk:process_midi(data)
  end
end

local function nsync(x)
	if x == 2 then
		k.note_sync = true
	else
		k.note_sync = false
	end
end

local function lsync(x)
	if x == 1 then
		k.loop_sync = 0
  elseif x == 2 then
		k.loop_sync = 1
  else
		k.loop_sync = 2
	end
end

function make_note(track,n,oct,dur,tmul,rpt,glide)
		local midich = params:get(track .."_midi_chan")
		local nte = k:scale_note(n)
		print("[" .. track .. "/" .. midich .. "] Note " .. nte .. "/" .. oct .. " for " .. dur .. " repeats " .. rpt .. " glide " .. glide  )
		-- ignore repeats and glide for now
		-- currently 1 == C3 (60 = 59 + 1)
		local r = rpt + 1
		local notedur = 6  * (dur/r * tmul)
		for rptnum = 1,r do
		  midi_note = nte + ( (oct - 3) * 12 ) + root_note
		  -- m:note_on(midi_note,100,midich)
		  table.insert(note_list,{ action = 1 , track = track , timestamp = clock_count + ( (rptnum - 1) * notedur), channel = midich , note = midi_note })
		  table.insert(note_list,{ action = 0 , track = track , timestamp = (clock_count + (rptnum * notedur)) - 0.1, channel = midich , note = midi_note })
		end
end


function init()
  print("Kria Init")
	k = kria.loadornew("Kria/kria.data")
	--k = kria.new()
	norns.enc.sens(2,4)
  k:init(make_note)
  clk.on_step = step
  clk.on_start = function() k:reset() end
  clk.beats_per_bar = 4
  clk.on_select_internal = function() clk:start() end
  clk.on_select_external = function() print("external") end
  params:add{type = "number", id = "midi_in_device", name = "midi in device",
    min = 1, max = 4, default = 1,
    action = function(value) 
      midi_in_device = midi.connect(value) 
      midi_in_device.event = process_midi_in
      end}

  params:add{type = "number", id = "midi_out_device", name = "midi out device",
    min = 1, max = 4, default = 1,
    action = function(value) midi_out_device = midi.connect(value) end}
	params:add_separator()
  clk:add_clock_params()
  	params:add{type = "option", id = "step_length", name = "step length", options = options.STEP_LENGTH_NAMES, default = 6,
    action = function(value)
      clk.ticks_per_step = ( 96 / (options.STEP_LENGTH_DIVIDERS[value])  ) 
      clk.steps_per_beat = ( options.STEP_LENGTH_DIVIDERS[value] ) 
      -- clk.ticks_per_step = 24
      -- clk.steps_per_beat = 4
      clk:bpm_change(clk.bpm)
      print("clock " .. clk.ticks_per_step .. " steps " .. clk.steps_per_beat)
    end}
	params:add_separator()
	params:add{type="option",name="Note Sync",id="note_sync",options={"Off","On"},default=1, action=nsync}
	params:add{type="option",name="Loop Sync",id="loop_sync",options={"None","Track","All"},default=1, action=lsync}
	params:add_separator()
	for i = 1, 4 do
    params:add_number(i.."_midi_chan", i..": midi chan", 1, 16,i)
  end
	params:add_separator()
	-- params:add_number("clock_ticks", "clock ticks", 1, 96,1)
  params:bang()
  -- grid refresh timer, 15 fps
  metro_grid_redraw = metro.init(function(idx,stage) gridredraw() end, 1 / 30 )
  metro_grid_redraw:start()
  -- screen redraw - really low fps 
  metro_screen_redraw = metro.init(function(idx,stage) redraw() end, 1 / 5 )
  metro_screen_redraw:start()
end

function step()
	clock_count = clock_count + 1
	table.sort(note_list,function(a,b) return a.timestamp < b.timestamp end)
	while note_list[1] ~= nil and note_list[1].timestamp <= clock_count do
		--print("note off " .. note_off_list[1].note)
		-- print("clock " .. clock_count)
		if note_list[1].action == 1 then 
		  -- print("note on " .. note_list[1].timestamp)
		  midi_out_device:note_on(note_list[1].note,100,note_list[1].channel)
		  screen_notes[note_list[1].track] = note_list[1].note
		else 
		  -- print("note off " .. note_list[1].timestamp)
		  midi_out_device:note_off(note_list[1].note,0,note_list[1].channel)
		  screen_notes[note_list[1].track] = -1
		end
		table.remove(note_list,1)
	end
	k:clock()
end

function redraw()
  -- screen.clear()
	-- screen.move(40,40)
	-- screen.text("Kria")
  screen.clear()
  screen.font_size(12)
  screen.font_face(3)
  if k.mode == kria.mScale then   
    screen.move(10,20)
    screen.text("Root: " .. MusicUtil.note_num_to_name(root_note,true))
    screen.font_size(8)
    screen.font_face(1)
    for idx = 1,7 do
      screen.move(15 + (idx - 1 ) * 16,40)
      local n =  k:scale_note(idx)  +  root_note 
      screen.text(MusicUtil.note_num_to_name(n))
    end
  else
    screen.move(10,20)
    screen.text("Root: " .. MusicUtil.note_num_to_name(root_note,true))
    screen.move(70,20)
    if clk.external then 
      screen.text("BPM: ext")
    else 
      screen.text("BPM: " .. params:get("bpm"))
    end
    for idx = 1,4 do 
      screen.move(15 + (idx - 1 ) * 27,40)
      if screen_notes[idx] > 0 then
       screen.text(MusicUtil.note_num_to_name(screen_notes[idx] , true))
      end
    end
    playback_icon:redraw()
  end
  screen.update()
end

function gridredraw()
 
	if preset_mode then
		k:draw_presets(g)
	else
	  k:draw(g)
	end
end

function enc(n,delta)
  if n == 2 then 
    root_note = util.clamp(root_note + delta, 24, 72)
    -- print(root_note)
  elseif n == 3 then       
    params:delta("bpm",delta)
  end
  
end

function key(n,z)
	-- key 2 opens presets for now
	-- this may change
	if n == 2 and z == 1 then
		preset_mode = true
	else
		preset_mode = false
	end
	if n == 3 and z == 1 then
		if clocked == true then
				clocked = false
				playback_icon.status = 3
		else
				clocked = true
				playback_icon.status = 1
		end
	end
end

function gridkey(x, y, z)
	k:event(x,y,z)
end

function cleanup()
	-- print("Cleanup")
	k:save("Kria/kria.data")
	-- print("Done")
end
