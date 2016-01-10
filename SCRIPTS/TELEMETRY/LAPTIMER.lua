--
-- Lap Timer by Jeremy Cowgar <jeremy@cowgar.com>
--
-- https://github.com/jcowgar/opentx-laptimer
--

--
-- User Configuration
--

local THROTTLE_CHANNEL = 'ch1'
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

local SCREEN_SETUP = 1
local SCREEN_TIMER = 2
local SCREEN_POST_RACE = 3
local SCREEN_COUNT = SCREEN_POST_RACE

--
-- State Variables
--

local currentScreen = SCREEN_SETUP

-- Setup Related

local lapCount = 3

-- Timer Related

local isTiming = false
local lastLapSw = -2048
local spokeGoodBad = false

local laps = {}
local lapNumber = 0
local lapStartDateTime = {}
local lapStartTicks = 0
local lapThrottles = {}
local lapSpokeMid = false

--
-- Helper Methods
--

local function round(num, decimals)
  local mult = 10^(decimals or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function draw_screen_title(title, pageNumber)
	lcd.drawScreenTitle('Lap Timer - ' .. title, pageNumber, SCREEN_COUNT)
end

-----------------------------------------------------------------------
--
-- Setup Portion of the program
--
-----------------------------------------------------------------------

local function setup_draw()
	lcd.clear()
	
	draw_screen_title('Setup', SCREEN_SETUP)
	
	lcd.drawText(2, 13, ' Lap Timer ', DBLSIZE)
	lcd.drawText(93, 23, 'by Jeremy Cowgar', SMLSIZE)
	lcd.drawText(5, 40, 'Race Name:')
	lcd.drawText(63, 40, ' ' .. 'Not Yet Implemented' .. ' ')
	lcd.drawText(6, 52, 'Lap Count:')
	lcd.drawText(63, 52, ' ' .. lapCount .. ' ', INVERS)
end

local function setup_func(keyEvent)
	if keyEvent == EVT_PLUS_FIRST or keyEvent == EVT_PLUS_RPT then
		lapCount = lapCount + 1
	elseif keyEvent == EVT_MINUS_FIRST or keyEvent == EVT_MINUS_RPT then
		lapCount = lapCount - 1
	elseif keyEvent == EVT_ENTER_BREAK then
		currentScreen = SCREEN_TIMER
	end
	
	if lapCount < 1 then
		lapCount = 1
	end
	
	setup_draw()
end

-----------------------------------------------------------------------
--
-- Timer Portion of the program
--
-----------------------------------------------------------------------

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

local function lapsReset()
	laps = {}
	lapNumber = 0

	timerReset()
end

local function lapsSave()
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
	
	if isTiming then
		lcd.drawText(90, 40, lapNumber .. ' of ' .. lapCount, DBLSIZE)
	else
		lcd.drawText(55, 15, 'Waiting for', DBLSIZE)
		lcd.drawText(55, 35, 'Race Start', DBLSIZE)
	end

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
	
	lcd.drawText(5, 23, string.format('%0.2f', round(avg / 100.0, 2)) .. ' avg', DBLSIZE)
	
	if isTiming and lc > 1 then
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

local function timer_func(keyEvent)
	lcd.clear()

	--
	-- Check to see if we should do anything with the lap switch
	--
	
	local lapSwVal = getValue(LAP_SWITCH)
	local lapSwChanged = (lastLapSw ~= lapSwVal)
	
	--
	-- Trick our system into thinking it should start the
	-- timer if our throttle goes high
	--
	
	if isTiming == false and getValue(THROTTLE_CHANNEL) >= OFF_MS then
		lapSwChanged = true
		lapSwVal = ON_MS
	end
	
	--
	-- Start a new lap
	--
	
	if lapSwChanged and lapSwVal >= ON_MS then
		if isTiming then
			--
			-- We already have a lap going, save the timer data
			--
			
			local lapTicks = (getTime() - lapStartTicks)
							
			laps[lapNumber] = { lapStartDateTime, lapTicks }
		end
		
		lapNumber = lapNumber + 1
		
		if lapNumber > lapCount then
			timerReset()
			
			lapNumber = 0
			
			currentScreen = SCREEN_POST_RACE
		else
			timerStart()
		end
	end
	
	lastLapSw = lapSwVal

	if isTiming then
		timerDraw()
	end

	lapsShow()
end

-----------------------------------------------------------------------
--
-- Post Race Portion of the program
--
-----------------------------------------------------------------------

local function post_race_func(keyEvent)
	lcd.clear()
	
	draw_screen_title('Post Race', SCREEN_POST_RACE)
	
	lcd.drawText(2, 13, 'Save Race?', DBLSIZE)
	lcd.drawText(20, 35, 'Enter to save, Exit to discard')
	
	if keyEvent == EVT_ENTER_BREAK then
		lapsSave()
		
		playFile('on.wav')
		
		currentScreen = SCREEN_TIMER
		
	elseif keyEvent == EVT_EXIT_BREAK then
		lapsReset()
		
		playFile('reset.wav')
		
		currentScreen = SCREEN_TIMER
	end
end

-----------------------------------------------------------------------
--
-- OpenTx Entry Points
--
-----------------------------------------------------------------------

local function init_func()
	lcd.clear()
end

local function run_func(keyEvent)
	if currentScreen == SCREEN_SETUP then
		setup_func(keyEvent)
	elseif currentScreen == SCREEN_TIMER then
		timer_func(keyEvent)
	elseif currentScreen == SCREEN_POST_RACE then
		post_race_func(keyEvent)
	end
end

return { init=init_func, run=run_func }
