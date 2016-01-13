--
-- Lap Timer by Jeremy Cowgar <jeremy@cowgar.com>
--
-- https://github.com/jcowgar/opentx-laptimer
--

--
-- User Configuration
--

local SOUND_LAP_SAME = 'LAPTIME/same.wav'
local SOUND_LAP_BETTER = 'LAPTIME/better.wav'
local SOUND_LAP_MUCH_BETTER = 'LAPTIME/mbetter.wav'
local SOUND_LAP_WORSE = 'LAPTIME/worse.wav'
local SOUND_LAP_MUCH_WORSE = 'LAPTIME/mworse.wav'
local SOUND_RACE_SAVE = 'LAPTIME/rsaved.wav'
local SOUND_RACE_DISCARD = 'LAPTIME/rdiscard.wav'
local SOUND_LAP = 'LAPTIME/lap.wav'
local SOUND_LAPS = 'LAPTIME/laps.wav'
local SOUND_WAITING_RACE_START = 'LAPTIME/wrcstart.wav'

local LAP_TIME_MUCH_MULTIPLIER = 0.15 -- 15% better/worse to trip the "much" language
local LAP_TIME_SAME_MULTIPLIER = 0.02 -- 2% better/worse to trip the "same" language

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

local SCREEN_RACE_SETUP = 1
local SCREEN_CONFIGURATION = 2
local SCREEN_TIMER = 3
local SCREEN_POST_RACE = 4

local SWITCH_NAMES = { 'sa', 'sb', 'sc', 'sd', 'se', 'sf', 'sg', 'sh' }

local CONFIG_FILENAME = '/LAPTIME.cfg'
local CSV_FILENAME = '/LAPTIME.csv'

--
-- Configuration Variables
--

local ConfigThrottleChannelNumber = 1
local ConfigThrottleChannel = 'ch1'
local ConfigLapSwitch = 'sh'
local ConfigSpeakBetterWorse = true
local ConfigSpeakLapNumber = true
local ConfigBeepOnMidLap = true

--
-- State Variables
--

local currentScreen = SCREEN_RACE_SETUP

-- Setup Related

local lapCount = 3

-- Timer Related

local isTiming = false
local lastLapSw = -2048
local spokeBetterWorse = false
local spokeWaitingForRaceStart = false

local laps = {}
local lapNumber = 0
local lapStartDateTime = {}
local lapStartTicks = 0
local lapThrottles = {}
local lapSpokeMid = false

-----------------------------------------------------------------------
--
-- Helper Methods (Generic)
--
-----------------------------------------------------------------------

local function iif(cond, T, F)
    if cond then return T else return F end
end

-----------------------------------------------------------------------
--
-- Configuration
--
-----------------------------------------------------------------------

local CONFIG_FIELD_THROTTLE = 1
local CONFIG_FIELD_ConfigLapSwitch = 2
local CONFIG_FIELD_SPEAK_BETTER_WORSE = 3
local CONFIG_FIELD_SPEAK_LAP = 4
local CONFIG_FIELD_BEEP_AT_HALF = 5

local CONFIG_OPTIONS = {
	{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
	SWITCH_NAMES,
	{ 'Yes', 'No' },
	{ 'Yes', 'No' },
	{ 'Yes', 'No' }
}

local ConfigCurrentField = CONFIG_FIELD_THROTTLE
local ConfigEditing = false

local function config_read()
	--
	-- OpenTX Lua throws an error if you attempt to open a file that does not exist:
	--
	-- f_open(/Users/jeremy/Documents/RC/Taranis-X9E-SD/LAPTIME.cfg) = INVALID_NAME
	-- f_close(0x1439291e05400000) (FIL:0x114392828)
	-- PANIC: unprotected error in call to Lua API ((null))
	--
	-- Thus, let's open it in append mode, which should create a blank file if it does
	-- not yet exist.
	--
	
	local f = io.open(CONFIG_FILENAME, 'a')
	if f ~= nil then
		io.close(f)
	end

	f = io.open(CONFIG_FILENAME, 'r')
	if f == nil then
		-- defaults will be used
		return false
	end
	
	local content = io.read(f, 1024)
	io.close(f)
	
	if content == '' then
		-- defaults will be used
		return false
	end
	
	local c = {}

	for value in string.gmatch(content, '([^,]+)') do
		c[#c + 1] = value
	end
	
	ConfigThrottleChannelNumber = tonumber(c[1])
	ConfigThrottleChannel = 'ch' .. c[1]
	ConfigLapSwitch = c[2]
	ConfigSpeakBetterWorse = (c[3] == 'true')
	ConfigSpeakLapNumber = (c[4] == 'true')
	ConfigBeepOnMidLap = (c[5] == 'true')
	
	return true
end

local function config_write()
	local f = io.open(CONFIG_FILENAME, 'w')
	io.write(f, ConfigThrottleChannelNumber)
	io.write(f, ',' .. ConfigLapSwitch)
	io.write(f, ',' .. iif(ConfigSpeakBetterWorse, 'true', 'false'))
	io.write(f, ',' .. iif(ConfigSpeakLapNumber, 'true', 'false'))
	io.write(f, ',' .. iif(ConfigBeepOnMidLap, 'true', 'false'))
	io.close(f)
end

local function config_cycle_editing_value(keyEvent)
	local values = CONFIG_OPTIONS[ConfigCurrentField]
	local value
	
	if ConfigCurrentField == CONFIG_FIELD_THROTTLE then
		value = ConfigThrottleChannelNumber
	elseif ConfigCurrentField == CONFIG_FIELD_ConfigLapSwitch then
		value = ConfigLapSwitch
	elseif ConfigCurrentField == CONFIG_FIELD_SPEAK_BETTER_WORSE then
		value = iif(ConfigSpeakBetterWorse, 'Yes', 'No')
	elseif ConfigCurrentField == CONFIG_FIELD_SPEAK_LAP then
		value = iif(ConfigSpeakLapNumber, 'Yes', 'No')
	elseif ConfigCurrentField == CONFIG_FIELD_BEEP_AT_HALF then
		value = iif(ConfigBeepOnMidLap, 'Yes', 'No')
	end
	
	local idx = 1

	for i = 1, #values do
		if values[i] == value then
			idx = i
		end
	end
	
	if keyEvent == EVT_MINUS_FIRST or keyEvent == EVT_MINUS_RPT then
		idx = idx - 1
	else
		idx = idx + 1
	end
	
	if idx < 1 then
		idx = #values
	elseif idx > #values then
		idx = 1
	end

	value = values[idx]

	if ConfigCurrentField == CONFIG_FIELD_THROTTLE then
		ConfigThrottleChannelNumber = idx
		ConfigThrottleChannel = 'ch' .. string.format('%d', idx)
	elseif ConfigCurrentField == CONFIG_FIELD_ConfigLapSwitch then
		ConfigLapSwitch = value
	elseif ConfigCurrentField == CONFIG_FIELD_SPEAK_BETTER_WORSE then
		ConfigSpeakBetterWorse = (value == 'Yes')
	elseif ConfigCurrentField == CONFIG_FIELD_SPEAK_LAP then
		ConfigSpeakLapNumber = (value == 'Yes')
	elseif ConfigCurrentField == CONFIG_FIELD_BEEP_AT_HALF then
		ConfigBeepOnMidLap = (value == 'Yes')
	end
end

local function configuration_func(keyEvent)
	if keyEvent == EVT_ENTER_BREAK then
		if ConfigEditing then
			ConfigEditing = false
		else
			ConfigEditing = true
		end
	
	elseif ConfigEditing and 
		(
			keyEvent == EVT_MINUS_FIRST or keyEvent == EVT_MINUS_RPT or
			keyEvent == EVT_PLUS_FIRST or keyEvent == EVT_PLUS_RPT
		)
	then
		config_cycle_editing_value(keyEvent)
	
	elseif keyEvent == EVT_MINUS_FIRST or keyEvent == EVT_MINUS_RPT then
		ConfigCurrentField = ConfigCurrentField - 1
		
		if ConfigCurrentField < CONFIG_FIELD_THROTTLE then
			ConfigCurrentField = CONFIG_FIELD_BEEP_AT_HALF
		end

	elseif keyEvent == EVT_PLUS_FIRST or keyEvent == EVT_PLUS_RPT then
		ConfigCurrentField = ConfigCurrentField + 1
		
		if ConfigCurrentField > CONFIG_FIELD_BEEP_AT_HALF then
			ConfigCurrentField = CONFIG_FIELD_THROTTLE
		end
	
	elseif keyEvent == EVT_EXIT_BREAK then
		config_write()
		
		currentScreen = SCREEN_RACE_SETUP

		return
	end
	
	lcd.clear()

	lcd.drawScreenTitle('Configuration', 1, 1)
	
	lcd.drawText(23, 12, 'Throttle Channel:')
	lcd.drawText(lcd.getLastPos() + 2, 12, ConfigThrottleChannelNumber, 
		iif(ConfigCurrentField == CONFIG_FIELD_THROTTLE, 
			iif(ConfigEditing, INVERS+BLINK, INVERS), 0))

	lcd.drawText(58, 22, 'Lap Switch:')
	lcd.drawText(lcd.getLastPos() + 2, 22, ConfigLapSwitch,
		iif(ConfigCurrentField == CONFIG_FIELD_ConfigLapSwitch,
			iif(ConfigEditing, INVERS+BLINK, INVERS), 0))

	lcd.drawText(8, 32, 'Speak Better/Worse:')
	lcd.drawText(lcd.getLastPos() + 2, 32, iif(ConfigSpeakBetterWorse, 'Yes', 'No'),
		iif(ConfigCurrentField == CONFIG_FIELD_SPEAK_BETTER_WORSE,
			iif(ConfigEditing, INVERS+BLINK, INVERS), 0))

	lcd.drawText(24, 42, 'Speak Lap Number:')
	lcd.drawText(lcd.getLastPos() + 2, 42, iif(ConfigSpeakLapNumber, 'Yes', 'No'),
		iif(ConfigCurrentField == CONFIG_FIELD_SPEAK_LAP,
			iif(ConfigEditing, INVERS+BLINK, INVERS), 0))

	lcd.drawText(28, 52, 'Beep At Half Lap:')
	lcd.drawText(lcd.getLastPos() + 2, 52, iif(ConfigBeepOnMidLap, 'Yes', 'No'),
		iif(ConfigCurrentField == CONFIG_FIELD_BEEP_AT_HALF,
			iif(ConfigEditing, INVERS+BLINK, INVERS), 0))
end

-----------------------------------------------------------------------
--
-- ???
--
-----------------------------------------------------------------------

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

local function race_setup_draw()
	if setup_did_initial_draw == false then
		setup_did_initial_draw = true
		
		lcd.clear()

		lcd.drawPixmap(135, 7, '/BMP/LAPTIME/S_SWHAND.bmp')
		lcd.drawPixmap(2, 9, '/BMP/LAPTIME/S_TITLE.bmp')
	end
	
	-- Clear the lap counter (if you go from 10 down to 9, for example, it displays as 90
	lcd.drawText(63, 42, '     ', MIDSIZE)

	lcd.drawText(6, 43, 'Lap Count:')
	lcd.drawText(63, 43, ' ' .. lapCount .. ' ', INVERS)
end

local function race_setup_func(keyEvent)
	if keyEvent == EVT_PLUS_FIRST or keyEvent == EVT_PLUS_RPT then
		lapCount = lapCount + 1

	elseif keyEvent == EVT_MINUS_FIRST or keyEvent == EVT_MINUS_RPT then
		lapCount = lapCount - 1

	elseif keyEvent == EVT_MENU_BREAK then
		currentScreen = SCREEN_CONFIGURATION
		setup_did_initial_draw = false
		return

	elseif keyEvent == EVT_ENTER_BREAK then
		currentScreen = SCREEN_TIMER
		setup_did_initial_draw = false
		return
	end
	
	if lapCount < 1 then
		lapCount = 1
	end
	
	race_setup_draw()
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
	spokeBetterWorse = false
	spokeWaitingForRaceStart = false
end

local function timerDraw()
	local tickNow = getTime()
	local tickDiff = tickNow - lapStartTicks
	
	lcd.drawNumber(65, 3, tickDiff, PREC2 + DBLSIZE)
	
	if ConfigBeepOnMidLap and lapSpokeMid == false then
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
	local f = io.open(CSV_FILENAME, 'a')
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
		if ConfigSpeakLapNumber then
			playFile(SOUND_LAP)
			playNumber(lapNumber, 0)
		end
	end
	
	if #laps > 1 then
		local lastLapTime = laps[#laps - 1][2]
		local thisLapTime = laps[#laps][2]

		if ConfigSpeakBetterWorse and spokeBetterWorse == false then
			spokeBetterWorse = true
			
			local lastLapTimeMuch = lastLapTime * LAP_TIME_MUCH_MULTIPLIER
			local lastLapTimeSame = lastLapTime * LAP_TIME_SAME_MULTIPLIER
			
			if thisLapTime <= lastLapTime - lastLapTimeMuch then
				playFile(SOUND_LAP_MUCH_BETTER)
			
			elseif thisLapTime >= lastLapTime - lastLapTimeSame and
				thisLapTime <= lastLapTime + lastLapTimeSame
			then
				playFile(SOUND_LAP_SAME)
			
			elseif thisLapTime < lastLapTime then
				playFile(SOUND_LAP_BETTER)
				
			elseif thisLapTime >= lastLapTime + lastLapTimeMuch then
				playFile(SOUND_LAP_MUCH_WORSE)
			
			elseif thisLapTime > lastLapTime then
				playFile(SOUND_LAP_WORSE)
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
		currentScreen = SCREEN_RACE_SETUP
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
		if ConfigSpeakLapNumber == true and spokeWaitingForRaceStart == false then
			playFile(SOUND_WAITING_RACE_START)
			playNumber(lapCount, 0)
			playFile(SOUND_LAPS)
			
			spokeWaitingForRaceStart = true
		end
		
		lcd.drawText(55, 15, 'Waiting for', DBLSIZE)
		lcd.drawText(55, 35, 'Race Start', DBLSIZE)
	end


	--
	-- Check to see if we should do anything with the lap switch
	--
	
	local lapSwVal = getValue(ConfigLapSwitch)
	local lapSwChanged = (lastLapSw ~= lapSwVal)
	
	--
	-- Trick our system into thinking it should start the
	-- timer if our throttle goes high
	--
	
	if isTiming == false and getValue(ConfigThrottleChannel) >= OFF_MS then
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
	
	if config_read() == false then
		--
		-- A configuration file did not exist, so let's drop the user off a the lap timer
		-- configuration screen. Let them setup some basic preferences for all races.
		--
		
		currentScreen = SCREEN_CONFIGURATION
	end
end

local function run_func(keyEvent)
	if currentScreen == SCREEN_CONFIGURATION then
		configuration_func(keyEvent)
	elseif currentScreen == SCREEN_RACE_SETUP then
		race_setup_func(keyEvent)
	elseif currentScreen == SCREEN_TIMER then
		timer_func(keyEvent)
	elseif currentScreen == SCREEN_POST_RACE then
		post_race_func(keyEvent)
	end
end

return { init=init_func, run=run_func }