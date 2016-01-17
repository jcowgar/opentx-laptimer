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
local SOUND_LAST_LAP = 'LAPTIME/lastlap.wav'
local SOUND_WAITING_RACE_START = 'LAPTIME/wrcstart.wav'
local SOUND_RACE_OVER = 'LAPTIME/racedone.wav'

local LAP_TIME_MUCH_MULTIPLIER = 0.15 -- 15% better/worse to trip the "much" language
local LAP_TIME_SAME_MULTIPLIER = 0.02 -- 2% better/worse to trip the "same" language

--
-- User Configuration Done
--
-- Do not alter below unless you know what you're doing!
--

local cfg = dofile('/SCRIPTS/LIBRARY/config.lua')
local frm = dofile('/SCRIPTS/LIBRARY/form.lua')

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

local SWITCH_NAMES = {}

local CONFIG_FILENAME = '/LAPTIME.cfg'
local CSV_FILENAME = '/LAPTIME.csv'

--
-- State Variables
--

local currentScreen = SCREEN_RACE_SETUP

-- Timer Related

local isTiming = false
local lastLapSw = -2048
local spokeBetterWorse = false
local spokeWaitingForRaceStart = false
local spokeRaceDone = false

local laps = {}
local lapNumber = 0
local lapStartDateTime = {}
local lapStartTicks = 0
local lapThrottles = {}
local lapSpokeMid = false

-----------------------------------------------------------------------
--
-- Configuration
--
-----------------------------------------------------------------------

local CONFIG_VERSION = 1

local config = {
	Version = -1,
	ThrottleChannelNumber = 1,
	ThrottleChannel = 'ch1',
	LapSwitch = 8,
	SpeakBetterWorse = true,
	SpeakLapNumber = true,
	BeepOnMidLap = true,
	LapCount = 3
}

local CONFIG_SAVE_BUTTON = -1

local configForm = {
	ValueColumn = 125,
	{ frm.TYPE_INTEGER, 'Throttle Channel', 'ThrottleChannelNumber', 10, 11, 1, 16 },
	{ frm.TYPE_LIST, 'Lap Switch', 'LapSwitch', 10, 21, SWITCH_NAMES },
	{ frm.TYPE_YES_NO, 'Speak Better/Worse', 'SpeakBetterWorse', 10, 31 },
	{ frm.TYPE_YES_NO, 'Speak Lap Number', 'SpeakLapNumber', 10, 41 },
	{ frm.TYPE_YES_NO, 'Beep on Mid Lap', 'BeepOnMidLap', 10, 51 },
	{ frm.TYPE_BUTTON, 'Save', CONFIG_SAVE_BUTTON, 180, 51 },
}

local function config_read()
	config = cfg.read(CONFIG_FILENAME, config)

	if config.Version == -1 then
		return false
	end
end

local function config_write()
	config.Version = CONFIG_VERSION
	config.ThrottleChannel = 'ch' .. string.format('%d', config.ThrottleChannelNumber)
	
	cfg.write(CONFIG_FILENAME, config)
end

local function configuration_func(keyEvent)
	lcd.clear()
	lcd.drawScreenTitle('Configuration', 1, 1)
	
	keyEvent = frm.execute(configForm, config, keyEvent)
	
	if keyEvent == CONFIG_SAVE_BUTTON then
		config_write()
		currentScreen = SCREEN_RACE_SETUP
		return
	end
end

-----------------------------------------------------------------------
--
-- ???
--
-----------------------------------------------------------------------

local function laps_compute_stats()
	local stats = {}
	local lc = #laps
	
	stats.raceLapCount = config.LapCount
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

local RACE_START_BUTTON = -1

local raceSetupForm = {
	ValueColumn = 63,
	{ frm.TYPE_PIXMAP, '/BMP/LAPTIME/S_SWHAND.bmp', nil, 135, 9 },
	{ frm.TYPE_PIXMAP, '/BMP/LAPTIME/S_TITLE.bmp', nil, 2, 7 },
	{ frm.TYPE_INTEGER, 'Lap Count', 'LapCount', 6, 39, 1, 99 },
	{ frm.TYPE_BUTTON, 'Start', RACE_START_BUTTON, 6, 53 },
}

local function race_setup_func(keyEvent)
	lcd.clear()
	
	keyEvent = frm.execute(raceSetupForm, config, keyEvent)
	
	if keyEvent == RACE_START_BUTTON then
		currentScreen = SCREEN_TIMER
	elseif keyEvent == EVT_MENU_BREAK then
		currentScreen = SCREEN_CONFIGURATION
	end
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
	spokeRaceDone = false
end

local function timerDraw()
	local tickNow = getTime()
	local tickDiff = tickNow - lapStartTicks
	
	lcd.drawNumber(65, 3, tickDiff, PREC2 + DBLSIZE)
	
	if config.BeepOnMidLap and lapSpokeMid == false then
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
			i, ',', config.LapCount, ',',
			lap[2] / 100.0, ',',
			0, -- Average throttle not yet tracked
			"\r\n")
	end
	io.close(f)	
	
	lapsReset()
end

local function lapsSpeakProgress()
	if #laps > 0 then
		if config.SpeakLapNumber then
			playFile(SOUND_LAP)
			playNumber(lapNumber, 0)			
		end
	end
	
	if #laps > 1 then
		local lastLapTime = laps[#laps - 1][2]
		local thisLapTime = laps[#laps][2]

		if config.SpeakBetterWorse and spokeBetterWorse == false then
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
	
	if lapNumber + 1 == config.LapCount then
		playFile(SOUND_LAST_LAP)
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
		lcd.drawNumber(135, 35, config.LapCount, DBLSIZE)
		lcd.drawText(102, 42, 'of')

		-- Outline
		lcd.drawRectangle(0, 0, 212, 64, SOLID)
	
	else
		if config.SpeakLapNumber == true and spokeWaitingForRaceStart == false then
			playFile(SOUND_WAITING_RACE_START)
			playNumber(config.LapCount, 0)
			playFile(SOUND_LAPS)
			
			spokeWaitingForRaceStart = true
		end
		
		lcd.drawText(55, 15, 'Waiting for', DBLSIZE)
		lcd.drawText(55, 35, 'Race Start', DBLSIZE)
	end


	--
	-- Check to see if we should do anything with the lap switch
	--
	
	local lapSwVal = getValue(SWITCH_NAMES[config.LapSwitch])
	local lapSwChanged = (lastLapSw ~= lapSwVal)
	
	--
	-- Trick our system into thinking it should start the
	-- timer if our throttle goes high
	--
	
	if isTiming == false and getValue(config.ThrottleChannel) >= OFF_MS then
		lapSwChanged = true
		lapSwVal = ON_MS
	end
	
	--
	-- Start a new lap
	--
	
	if lapSwChanged and lapSwVal >= OFF_MS then
		if isTiming then
			--
			-- We already have a lap going, save the timer data
			--
			
			local lapTicks = (getTime() - lapStartTicks)
							
			laps[lapNumber] = { lapStartDateTime, lapTicks }
		end
		
		lapsSpeakProgress()
		
		lapNumber = lapNumber + 1
		
		if lapNumber > config.LapCount then
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
	
	if config.SpeakLapNumber == true and spokeRaceDone == false then
		playFile(SOUND_RACE_OVER)
		
		spokeRaceDone = true
	end

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
	local ver, radio, maj, minor, rev = getVersion()
	
	if radio == 'taranisx9e' then
		SWITCH_NAMES = { 'sa', 'sb', 'sc', 'sd', 'se', 'sf', 'sg', 'sh',
			'si', 'sj', 'sk', 'sl', 'sm',  'sn', 'so', 'sp', 'sq', 'sr',
			'ls1', 'ls2', 'ls3', 'ls4', 'ls5', 'ls6', 'ls7', 'ls8', 'ls9', 'ls10',
			'ls11', 'ls12', 'ls13', 'ls14', 'ls15', 'ls16', 'ls17', 'ls18', 'ls19', 'ls20',
			'ls21', 'ls22', 'ls23', 'ls24', 'ls25', 'ls26', 'ls27', 'ls28', 'ls29', 'ls30',
			'ls31', 'ls32' }
	else
		SWITCH_NAMES = { 'sa', 'sb', 'sc', 'sd', 'se', 'sf', 'sg', 'sh',
			'ls1', 'ls2', 'ls3', 'ls4', 'ls5', 'ls6', 'ls7', 'ls8', 'ls9', 'ls10',
			'ls11', 'ls12', 'ls13', 'ls14', 'ls15', 'ls16', 'ls17', 'ls18', 'ls19', 'ls20',
			'ls21', 'ls22', 'ls23', 'ls24', 'ls25', 'ls26', 'ls27', 'ls28', 'ls29', 'ls30',
			'ls31', 'ls32' }
	end

	configForm[2][6] = SWITCH_NAMES

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