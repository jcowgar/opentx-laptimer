--
-- Lap Timer by Jeremy Cowgar <jeremy@cowgar.com>
--
-- https://github.com/jcowgar/opentx-laptimer
--

--
-- User Configuration
--

local MODE_SWITCH = 'sg'
local LAP_SWITCH = 'sh'
local SHOW_SPLIT = true
local SHOW_SPLIT_AVG = false
local SPEAK_GOOD_BAD = true
local SPEAK_MID = true

--
-- User Configuration Done
--
-- Do not alter below unless you know what you're doing!
--

--
-- Constants
--

local OFF_MS = -924
local MID_MS_MIN = -100
local MID_MS_MAX = 100
local ON_MS  = 924

--
-- State Variables
--

local isTiming = false
local lastModeSw = -2048
local lastLapSw = -2048
local spokeGoodBad = false

local laps = {}
local lapCount = 0
local lapStartDateTime = {}
local lapStartTicks = 0
local lapThrottles = {}
local lapSpokeMid = false

--
-- Helper Methods
--

function round(num, decimals)
  local mult = 10^(decimals or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function timerReset()
	isTiming = false
	lapStartTicks = 0
	lapStartDateTime = {}
	lapSpokeMid = false
end

local function timerStart()
	isTiming = true
	lapStartTicks = getTime()
	lapStartDateTime = getDateTime()
	lapSpokeMid = false
	spokeGoodBad = false
end

local function timerDraw()
	local tickNow = getTime()
	local tickDiff = tickNow - lapStartTicks
	
	lcd.drawText(5, 3, "" .. round(tickDiff / 100.0, 2), DBLSIZE)
	
	if SPEAK_MID and lapSpokeMid == false then
		local lastIndex = #laps
		
		if lastIndex > 0 then
			local mid = laps[lastIndex][2] / 2
			if mid < tickDiff then
				playTone(700, 300, 5, PLAY_BACKGROUND, 1000)
				lapSpokeMid = true
			end
		end
	end
end

local function statusDraw(msg)
	lcd.drawText(5, 53, msg .. '...')
end

local function lapsReset()
	laps = {}
	lapCount = 0

	statusDraw('Resetting')		
	timerReset()
end

local function lapsSave()
	statusDraw('Saving')
	
	local f = io.open('/laps.csv', 'a')
	for i = 1, #laps do
		local lap = laps[i]
		local dt = lap[1]

		io.write(f, 
			string.format('%02d', dt.year), '-', 
			string.format('%02d', dt.mon), '-',
			string.format('%02d', dt.day), ' ',
			string.format('%02d', dt.hour), ':',
			string.format('%02d', dt.min), ':',
			string.format('%02d', dt.sec), ',',
			i, ',',
			lap[2] / 100.0, ',',
			0, -- Average throttle not yet tracked
			"\r\n")
	end
	io.close(f)	
	
	lapsReset()
end

local function lapsShow()
	local lc = #laps
	local lastLapTime = 0
	local thisLapTime = 0
	
	if lc == 0 then
		return
	elseif lc > 1 then
		lastLapTime = laps[lc - 1][2]
		thisLapTime = laps[lc][2]
	end
	
	local lcEnd = math.max(lc - 5, 1)
	
	for i = lc, lcEnd, -1 do
		local lap = laps[i]
		
		lcd.drawText(170, ((lc - i) * 10) + 3,
			string.format('%d', i) .. ': ' ..
			string.format('%0.2f', lap[2] / 100.0))
	end

	local sum = 0
	for i = 1, lc do
		sum = sum + laps[i][2]
	end
	
	local avg = sum / lc
	
	lcd.drawText(5, 23, string.format('%0.2f', round(avg / 100.0, 2)), DBLSIZE)
	
	if lc > 1 then
		if SPEAK_GOOD_BAD and spokeGoodBad == false then
			spokeGoodBad = true
			
			if thisLapTime < lastLapTime then
				playFile("good.wav")
			else
				playFile("bad.wav")
			end
		end
		
		if SHOW_SPLIT then
			local splitLast = round(thisLapTime - lastLapTime, 2) / 100.0
			lcd.drawText(70, 3, string.format('%+0.2f', splitLast), DBLSIZE)
		end

		if SHOW_SPLIT_AVG then
			local splitAvg = round(thisLapTime - avg, 2) / 100.0
			lcd.drawText(70, 23, string.format('%+0.2f', splitAvg), DBLSIZE)
		end
	end
end

local function init_func()
	lcd.clear()
end

local function run_func(keyEvent)
	local modeSwVal = getValue(MODE_SWITCH)
	local modeChanged = (lastModeSw ~= modeSwVal)
	
	lcd.clear()
	
	if modeChanged and modeSwVal <= OFF_MS then
		--
		-- Reset the current race
		--

		lapsReset()
		
	elseif modeSwVal >= MID_MS_MIN and modeSwVal <= MID_MS_MAX then
		--
		-- Check to see if we should do anything with the lap switch
		--
		
		local lapSwVal = getValue(LAP_SWITCH)
		local lapSwChanged = (lastLapSw ~= lapSwVal)
		
		if lapSwChanged and lapSwVal >= ON_MS then
			if isTiming then
				--
				-- We already have a lap going, save the timer data
				--
				
				local lapTicks = (getTime() - lapStartTicks)
								
				laps[lapCount] = { lapStartDateTime, lapTicks }
			end
			
			lapCount = lapCount + 1
			timerStart()
		end
		
		if isTiming then
			statusDraw('Active')
		else
			statusDraw('Ready')
		end

		lastLapSw = lapSwVal
	
	elseif modeChanged and modeSwVal >= ON_MS then
		--
		-- Save the current race
		--
		
		lapsSave()
		timerReset()
	end

	if isTiming then
		timerDraw()
		
		if lapCount > 0 then
			lapsShow()
		end
	end

	lastModeSw = modeSwVal	
end

return { init=init_func, run=run_func }
