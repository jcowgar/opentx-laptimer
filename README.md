Lap Timer for OpenTX v2.1.x
===========================

The goal is to have an advanced lap timer on your OpenTX compatible radio
using as little controls as possible. It should be able to store race and
lap data for analysis back at the computer.

See https://www.youtube.com/watch?v=ZyI2gwdLWe0 for a quick demo of the Lap Timer.

**NOTE**: OpenTX v2.1.x is required. Lap Timer does not work on OpenTX 2.0.x.

Installation
------------

1. Copy `SCRIPTS/TELEMETRY/LAPTIMER.lua` to your SD card's `SCRIPTS/TELEMETRY`
   folder. Create the folder if it does not exist.
2. Copy the folder `BMP/LAPTIME` to your SD card's `BMP` folder. Create the
   folder if it does not exist. In the end you should have `BMP/LAPTIME/S_SWHAND.bmp`
   for example.
3. Copy the folder `SOUNDS/LAPTIME` to your SD card's `SOUNDS/<LANG>` folder. `<LANG>`
   should be abbreviation of you configured language. For example, English is `en` thus
   the correct sounds directory would be `SOUNDS/en`. In the end you should have
   `SOUNDS/en/LAPTIME/better.wav` for example.
3. For any model you wish to enable the lap timer on, from the Telemetry setup
   screen, add a new screen, choose *Script* as the Type, and `LAPTIMER.lua` for
   the script name.

Configuration
-------------

When launching *Lap Timer* for the first time, you will be presented with a configuration
screen. Here, you can change a few key settings:

* **Throttle Channel** - Output channel for your throttle. This is used to detect
  when a race starts for the first time from the *Timer* page. The output channel
  is used instead of `Thr` stick values because the channel output may be overridden
  by Kill switches, for example. If the channel goes high, then your aircraft will
  take off.
* **Lap Switch** - Switch you wish to use to indicate a lap was just completed. It
  is best to put this on a momentary 2 position switch. On the Taranis, *SH* is
  ideal.
* **Speak Better/Worse** - If *Yes*, your radio will say "Better" if the lap you just
  completed is faster than your previous lap or "Worse" if slower. You can alter these
  sound files to your likings. They are located in the `SOUNDS/LAPTIME` directory and
  are named `better.wav` and `worse.wav`.
* **Speak Lap Number** - If *Yes*, when a lap is completed, that number will be spoken.
* **Beep At Half Lap** - If *Yes*, a long beep will occur when you reach the mid way point
  of the lap as defined by half of your last laps time. For example, say your last lap was
  60 seconds exactly. At 30 seconds you will hear a long beep. If you are further than
  1/2 way around the course, then you are doing better than you did last lap. If, however,
  you are not yet to the half way point, you are doing worse than you did last lap.

Usage
-----

To access the lap timer program, press and hold your *Page* button. This will
then display any Telemetry screens you have defined. If you have multiple
screens, press the *Page* button until you are on the lap timer screen.

When first entering the Lap Timer screen, you will be presented with the
*Race Setup* page. Here you set how many laps you wish to run. Press your
*Plus* and *Minus* keys to adjust accordingly, then press *Enter* to accept
the value and go to the *Timing* page.

The timer will automatically start when the throttle becomes active. To mark
the completion of a lap, pull the SG momentary switch. Once you have completed
all of the laps, the *Post Race* page will appear.

On the *Post Race* page you will see a summary of your race including lap
times, average time, total time and the number of laps completed. You can then
use the *Plus* and *Minus* keys to select *Save* or *Discard.* If you choose
*Save*, your race and lap details are appended to a file on your SD card named
`laps.csv` in the following format:

  1. Start Time (YYYY-MM-DD HH:MM:SS)
  2. Lap Number
  3. Lap Count (total laps for race)
  4. Time (in milliseconds, divide by 1,000 to get seconds)
  5. Average Throttle

**NOTE**: At this time, average throttle is not calculated but it is planned and
added to the CSV export to allow for easy future addition.

Special Actions
---------------

From the *Timer* page you can press *Exit* to abort the race. For example, maybe
you crashed on lap 2 of 5. This will take you to the *Post Race* page, where you
will be able to save or discard the incomplete race.

From the *Timer* page you can press *Menu* to access the *Race Setup* page
and change any parameters accordingly. **NOTE**: If you do this during a race,
your race will be lost.

From the *Race Setup* page you can press *Menu* to access the *Configuration* page. There
you can configure some basic *Lap Timer* settings that affect all races.