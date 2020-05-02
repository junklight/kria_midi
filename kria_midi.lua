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


local statestore = "kria_midi/kria.data"

local options = {}
options.STEP_LENGTH_NAMES = {"1 bar", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32", "1/48", "1/64"}
options.STEPS = {               1 , 2 , 3 , 4  , 6 , 8 , 12 , 16 , 24 , 32 , 48 , 64 }
local stepchoice = 6
local ticks_per_step = 12 

local g = grid.connect(1)
function g.key(x,y,z) gridkey(x,y,z) end
local k

local preset_mode = false
local clocked = true
local clock_count = 0
local tick_count = 0

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
		-- print("[" .. track .. "/" .. midich .. "] Note " .. nte .. "/" .. oct .. " for " .. dur .. " repeats " .. rpt .. " glide " .. glide  )
		-- ignore repeats and glide for now
		-- currently 1 == C3 (60 = 59 + 1)
		local r = rpt + 1
		local notedur = (dur/r * tmul) 
		-- print("notedur " .. notedur .. " metro " .. (clk.metro.time * clk.ticks_per_step) )
		for rptnum = 1,r do
		  midi_note = nte + ( (oct - 3) * 12 ) + root_note
		  -- m:note_on(midi_note,100,midich)
		  table.insert(note_list,{ action = 1 , track = track , timestamp = clock_count + ( (rptnum - 1) * notedur), channel = midich , note = midi_note })
		  table.insert(note_list,{ action = 0 , track = track , timestamp = (clock_count + (rptnum * notedur))  , channel = midich , note = midi_note })
		end
end


function init()
  print("Kria Init")
	k = kria.loadornew(statestore)
	--k = kria.new()
	norns.enc.sens(2,4)
  k:init(make_note)
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
	params:add{type = "option", id = "step_length", name = "step length", options = options.STEP_LENGTH_NAMES, default = 6,
  action = function(value)
    stepchoice = value
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
  -- setup clock 
  clock.run(do_bar)
  
  -- grid refresh timer, 15 fps
  metro_grid_redraw = metro.init(function(idx,stage) gridredraw() end, 1 / 30 )
  metro_grid_redraw:start()
  -- screen redraw - really low fps 
  metro_screen_redraw = metro.init(function(idx,stage) redraw() end, 1 / 5 )
  metro_screen_redraw:start()
end

function do_bar()
  clock.sync(4)
  clock.run(do_step)
end

function do_step()
  while true do
    for i=1,options.STEPS[stepchoice] do -- tick counter inside the bar
      tick()
      steplen = ((1/options.STEPS[stepchoice]) * 4.0 ) / ticks_per_step
      clock.sync(steplen)
    end
  end
end

function tick() 
  if not clocked then 
    return
  end
  tick_count = tick_count + 1
  if tick_count == ticks_per_step then 
    tick_count = 0
    clock_count = clock_count + 1
    k:clock()
  end
  local clock_value = clock_count +  (( 1 / ticks_per_step ) * tick_count)
	
	table.sort(note_list, 
	          function(a,b) 
	            if a.timestamp < b.timestamp then 
	              return true  
	            elseif a.timestamp == b.timestamp then 
	              return a.action < b.action 
	            else 
	              return false
	            end
	           end )
	while note_list[1] ~= nil and note_list[1].timestamp <= clock_value do
		--print("note off " .. note_off_list[1].note)
		
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
end

function redraw()
  -- screen.clear()
	-- screen.move(40,40)
	-- screen.text("Kria")
  screen.clear()
  screen.font_size(10)
  screen.font_face(6)
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
    screen.move(8,20)
    screen.text("Root: " .. MusicUtil.note_num_to_name(root_note,true))
    screen.move(70,20)
    
    screen.text("BPM: " .. clock.get_tempo())

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
    params:delta("clock_tempo",delta)
  end
  
end

function key(n,z)
	-- key 2 opens presets for now
	-- this may change
	if n == 2 and z == 1 then
	  if preset_mode then
	    preset_mode = false
	  else 
		  preset_mode = true
	  end
	elseif n == 3 and z == 1 then
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
	print("Cleanup")
	k:save(statestore)
	print("Done")
end
