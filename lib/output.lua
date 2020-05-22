local utils = require "util"
local crowconfig =  _path.data .. "kria_midi/crowout.lua"

local defaultoutputconfig = [[
crowouts = {
  { 
    name="Crow CV/G 1 & 2 ",
    on_fn = function(note,velocity)
        crow.output[1].volts = note/12
        crow.output[2].volts = 8
      end
      ,
      off_fn = function(note)
        crow.output[2].volts = 0
      end
      },
    { 
    name="Crow CV/G 3 & 4 ",
    on_fn = function(note,velocity)
        crow.output[3].volts = note/12
        crow.output[4].volts = 8
      end
      ,
      off_fn = function(note)
        crow.output[4].volts = 0
      end
      },
    { 
    name="Crow Ansible CV/G 1",
    on_fn = function(note,velocity)
        crow.ii.ansible.trigger( 1 ,1  )
        crow.ii.ansible.cv( 1, note/12)
      end
    ,
    off_fn = function(note)
      crow.ii.ansible.trigger( 1 ,0  )
      end
      }
  }
  
return crowouts
]]

-- the idea here is that IF it doesn't exist we copy our default 
-- config into the data dir 
-- if it already exists we leave it alone so people can configure it 
-- locally and upgrade this script without losing any crow functions

if not utils.file_exists(crowconfig ) then 
  -- to a config file
  local f = io.open(crowconfig ,"w")
  f:write(defaultoutputconfig)
  f:close()
end

local output = {
  n = 1,
  crowopts = { } ,
  midichannels = { }, 
  -- collection of all the devices we have open
  devices = {},
  -- all the crow functions from the config file
  crowouts = {},
  -- output type for each channel
  -- 1 is midi 
  -- 2 is crow
  outtype = {},
  -- selections for each track 
  mididevice = {},
  midichannel = {},
  crowsel = {},
  -- keep a list of note ons so we can 
  -- send note offs to them in certain situations
  noteons = {nil,nil,nil,nil}
}

local z = loadfile(crowconfig)  
output.crowouts = z()

for n,f in pairs(output.crowouts) do 
  for k,v in pairs(f) do 
    if k == 'name' then 
      table.insert(output.crowopts,#output.crowopts + 1,v)  
    end
  end
end
  
for idx = 1,16 do 
  table.insert(output.midichannels,#output.midichannels + 1, idx)   
end

output.__index = output

function _out_type(n)
  ret = "midi"
  if n == 2 then
    ret = "crow"
  end
  return ret
end

--- constructor.
-- @tparam int n - number of output channels
function output:new(n)
  local o = setmetatable({}, output)
  o.n = n
  return o
end

function output:add_params() 
  for i = 1, self.n do
  	  -- ultimately I want this to show and hide the appropriate option folowing it but 
  	  -- seems like can only be done with jiggery pokery for the moment so not going there 
      params:add{type="option",name="Output " .. i ,id="output" .. i ,options={"midi","crow"} ,default=1, 
        action=function(n) 
          if self.outtype[i] ~= n and self.noteons[i] ~= nil then 
            self:note_off(i,self.noteons[i].note,self.noteons[i].velocity)
          end
          self.outtype[i] = n
        end
      }
      params:add{type = "number", id = "midi_out_device" .. i, name = "midi out device",
            min = 1, max = 4, default = 1,
            action = function(n) 

              self.devices[n] = midi.connect(n) 
              self.mididevice[i] = n
            end}
      params:add{type="option",name="Midi Channel",id="midi" .. i ,options=self.midichannels ,default=i,
        action = function(n)
          if self.midichannel[i] ~= n and self.noteons[i] ~= nil then 
            self:note_off(i,self.noteons[i].note,self.noteons[i].velocity)
          end
          self.midichannel[i] = n
        end
      }
      params:add{type="option",name="Crow",id="crow" .. i ,options=self.crowopts ,default=1,
        action = function(n)
          if self.crowsel[i] ~= n and self.noteons[i] ~= nil then 
            self:note_off(i,self.noteons[i].note,self.noteons[i].velocity)
          end
          self.crowsel[i] = n
        end
      }
      if i < self.n then 
        params:add_separator()
      end
    end
end

function output:note_on(track,note,velocity )
  self.noteons[track] = {note=note,velocity=velocity}
  if self.outtype[track] == 1 then 
    -- midi
    self.devices[self.mididevice[track]]:note_on(note,100,self.midichannel[track])
  else 
    self.crowouts[self.crowsel[track]].on_fn(note,velocity)
  end
end

function output:note_off(track,note,velocity )
  self.noteons[track] = nil
  if self.outtype[track] == 1 then 
    -- midi
    self.devices[self.mididevice[track]]:note_off(note,0,self.midichannel[track])
  else 
    self.crowouts[self.crowsel[track]].off_fn(note,velocity)
  end
end
  
function output:all_notes_off()
  for i = 1,4 do 
    if self.noteons[i] ~= nil then 
      self:note_off(i,self.noteons[i].note,self.noteons[i].velocity)
    end
  end
end
  
return output 