Lap Timer for OpenTX v2.1.x
===========================

The goal is to have an advanced lap timer on your OpenTX compatible radio
using as little controls as possible. It should be able to store race and
lap data for analysis back at the computer.

Controls
--------

Lap Timer needs a 3 position switch and preferably a momentary 2 position
switch. The momentary 2 position switch will be toggled to indicate a lap
completion.

The 3 position switch will change modes for the timer:
  *   UP = Save Race
  *  MID = Timer Ready
  * DOWN = Reset Race

When saving a race, all associated laps will be written to a CSV file on
the SD card in the following layout:

  1. Start Time (YYYY-MM-DD HH:MM:SS)
  2. Lap Number
  3. Time (in milliseconds, divide by 1,000 to get seconds)
  4. Average Throttle
