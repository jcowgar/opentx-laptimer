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
local SPEAK_GOOD_BAD = true
local SPEAK_MID = true
local SPEAK_LAP_NUMBER = true
local SOUND_GOOD_LAP = 'good.wav'
local SOUND_BAD_LAP = 'bad.wav'
local SOUND_RACE_SAVE = 'on.wav'
local SOUND_RACE_DISCARD = 'reset.wav'

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

local function laps_compute_stats()
	local stats = {}
	local lc = #laps
	
	stats.raceLapCount = lapCount
	stats.lapCount = lc
	stats.averageLap = 0.0
	stats.totalTime = 0.0
	
	for i = 1, lc do
		stats.totalTime = stats.totalTime + laps[i][2]
	end
	
	stats.averageLap = stats.totalTime / stats.lapCount
	
	return stats
end

local function laps_show(x, y, max)
	local lc = #laps
	local lastLapTime = 0
	local thisLapTime = 0
	
	if lc == 0 then
		return
	end
	
	local lcEnd = math.max(lc - max - 1, 1)
	
	for i = lc, lcEnd, -1 do
		local lap = laps[i]
		
		lcd.drawText(x, ((lc - i) * 10) + y,
			string.format('%d', i) .. ': ' ..
			string.format('%0.2f', lap[2] / 100.0))
	end
end

-----------------------------------------------------------------------
--
-- Setup Portion of the program
--
-----------------------------------------------------------------------

local setup_did_initial_draw = false

local function setup_draw()
	if setup_did_initial_draw == false then
		setup_did_initial_draw = true
		
		lcd.clear()
	
		lcd.drawScreenTitle('Configuration', 1, 1)
	
		lcd.drawPixmap(135, 11, '/BMP/LAPTIME/S_SWHAND.bmp')
		lcd.drawPixmap(2, 14, '/BMP/LAPTIME/S_TITLE.bmp')
	end
	
	-- Clear the lap counter (if you go from 10 down to 9, for example, it displays as 90
	lcd.drawText(63, 47, '     ', MIDSIZE)

	lcd.drawText(6, 48, 'Lap Count:')
	lcd.drawText(63, 48, ' ' .. lapCount .. ' ', INVERS)
end

local function setup_func(keyEvent)
	if keyEvent == EVT_PLUS_FIRST or keyEvent == EVT_PLUS_RPT then
		lapCount = lapCount + 1
	elseif keyEvent == EVT_MINUS_FIRST or keyEvent == EVT_MINUS_RPT then
		lapCount = lapCount - 1
	elseif keyEvent == EVT_ENTER_BREAK then
		currentScreen = SCREEN_TIMER
		
		setup_did_initial_draw = false
		
		return
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
	
	lcd.drawNumber(65, 3, tickDiff, PREC2 + DBLSIZE)
	
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
			i, ',', lapCount, ',',
			lap[2] / 100.0, ',',
			0, -- Average throttle not yet tracked
			"\r\n")
	end
	io.close(f)	
	
	lapsReset()
end

local function lapsSpeakProgress()
	if #laps > 0 then
		if SPEAK_LAP_NUMBER then
			playNumber(lapNumber, 0)
		end
	end
	
	if #laps > 1 then
		local lastLapTime = laps[#laps - 1][2]
		local thisLapTime = laps[#laps][2]

		if SPEAK_GOOD_BAD and spokeGoodBad == false then
			spokeGoodBad = true

			if thisLapTime < lastLapTime then
				playFile(SOUND_GOOD_LAP)
			else
				playFile(SOUND_BAD_LAP)
			end
		end
	end
end

local function timer_func(keyEvent)
	local showTiming = isTiming

	if keyEvent == EVT_EXIT_BREAK then
		currentScreen = SCREEN_POST_RACE
		return

	elseif keyEvent == EVT_MENU_BREAK then
		lapsReset()		
		currentScreen = SCREEN_SETUP

		return
	end

	lcd.clear()
	
	if isTiming then
		-- Average
		local avg = 0.0
		local diff = 0.0
		
		if #laps > 0 then
			local sum = 0
			for i = 1, #laps do
				sum = sum + laps[i][2]
			end
	
			avg = sum / #laps
		end
		
		if #laps > 1 then
			local lastLapTime = laps[#laps - 1][2]
			local thisLapTime = laps[#laps][2]

			diff = thisLapTime - lastLapTime
		end

		-- Column 1
		lcd.drawFilledRectangle(0, 22, 70, 11, BLACK)	
		lcd.drawText(30, 24, 'Cur', INVERS)

		lcd.drawFilledRectangle(0, 53, 70, 11, BLACK)	
		lcd.drawNumber(65, 35, avg, PREC2 + DBLSIZE)
		lcd.drawText(30, 55, 'Avg', INVERS)
	
		-- Column 2	
		lcd.drawFilledRectangle(70, 22, 70, 11, BLACK)
		lcd.drawNumber(135, 3, diff, PREC2 + DBLSIZE)
		lcd.drawText(98, 25, 'Diff', INVERS)
	
		lcd.drawFilledRectangle(70, 53, 70, 11, BLACK)
		lcd.drawText(100, 55, 'Lap', INVERS)
	
		lcd.drawLine(70, 0, 70, 63, SOLID, FORCE)
		lcd.drawLine(140, 0, 140, 63, SOLID, FORCE)

		lcd.drawNumber(98, 35, lapNumber, DBLSIZE)
		lcd.drawNumber(135, 35, lapCount, DBLSIZE)
		lcd.drawText(102, 42, 'of')

		-- Outline
		lcd.drawRectangle(0, 0, 212, 64, SOLID)
	
	else
		lcd.drawText(55, 15, 'Waiting for', DBLSIZE)
		lcd.drawText(55, 35, 'Race Start', DBLSIZE)
	end


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
		
		lapsSpeakProgress()
		
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

	if showTiming then
		timerDraw()

		laps_show(170, 3, 6)
	end
end

-----------------------------------------------------------------------
--
-- Post Race Portion of the program
--
-----------------------------------------------------------------------

local PR_SAVE = 1
local PR_DISCARD = 2

local post_race_option = PR_SAVE

local function post_race_func(keyEvent)
	local stats = laps_compute_stats()

	if keyEvent == EVT_MINUS_FIRST or keyEvent == EVT_MINUS_RPT or
	   keyEvent == EVT_PLUS_FIRST or keyEvent == EVT_PLUS_RPT
	then
		if post_race_option == PR_SAVE then
			post_race_option = PR_DISCARD
		elseif post_race_option == PR_DISCARD then
			post_race_option = PR_SAVE
		end
	end

	local saveFlag = 0
	local discardFlag = 0
	
	if post_race_option == PR_SAVE then
		saveFlag = INVERS
	elseif post_race_option == PR_DISCARD then
		discardFlag = INVERS
	end

	lcd.clear()
	
	lcd.drawText(2, 2, 'Post Race Stats', MIDSIZE)
	lcd.drawText(2, 55, ' Save ', saveFlag)
	lcd.drawText(35, 55, ' Discard ', discardFlag)
	
	laps_show(170, 3, 6)
	
	lcd.drawText(12, 18, 'Finished ' .. stats.lapCount .. ' of ' .. stats.raceLapCount .. ' laps')
	lcd.drawText(12, 28, 'Average Lap ' .. string.format('%0.2f', stats.averageLap / 100.0) .. ' seconds')
	lcd.drawText(12, 39, 'Total Time ' .. string.format('%0.2f', stats.totalTime / 100.0) .. ' seconds')
	
	if keyEvent == EVT_ENTER_BREAK then
		if post_race_option == PR_SAVE then
			lapsSave()
		
			playFile(SOUND_RACE_SAVE)
		
			currentScreen = SCREEN_TIMER
		elseif post_race_option == PR_DISCARD then
			lapsReset()
		
			playFile(SOUND_RACE_DISCARD)
		
			currentScreen = SCREEN_TIMER
		end
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
