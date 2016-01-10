Lap Timer for OpenTX v2.1.x
===========================

The goal is to have an advanced lap timer on your OpenTX compatible radio
using as little controls as possible. It should be able to store race and
lap data for analysis back at the computer.

The timer automatically starts when in the Ready Mode and the throttle
becomes active.

Controls
--------

Lap Timer only needs one control, preferably a momentary 2 position
switch to record a lap.

When saving a race, all associated laps will be written to a CSV file on
the SD card in the following layout:

  1. Start Time (YYYY-MM-DD HH:MM:SS)
  2. Lap Number
  3. Time (in milliseconds, divide by 1,000 to get seconds)
  4. Average Throttle
