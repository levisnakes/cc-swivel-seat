# CC Swivel Seat

Aim a swivel seat with **W A S D** on a **Linked Typewriter**. Two **Sequenced Gearshifts** do the turning: one for left/right (yaw), one for up/down (pitch). Three computers, one on each sublevel, talk over wireless or Ender Modems.

| Computer | Needs | Job |
|---|---|---|
| **Seat** | Linked Typewriter (touching or on a wired modem) + wireless/Ender modem | reads the keys |
| **Yaw** | Sequenced Gearshift (touching or wired) + wireless/Ender modem | A / D: left / right |
| **Pitch** | Sequenced Gearshift (touching or wired) + wireless/Ender modem | W / S: up / down |

## Install

On all three computers:

```
wget https://raw.githubusercontent.com/levisnakes/cc-swivel-seat/main/swivel.lua startup.lua
reboot
```

First boot asks what the computer is: **S**eat, **Y**aw or **P**itch. To change it later: `startup seat`, `startup yaw` or `startup pitch`.

## Use

- Hold **W A S D** on the typewriter. The gearshift turns `STEP` degrees at a time while the key is held.
- On the seat computer's keyboard: **H** = back to center, **Z** = make the current position the center.
- On a yaw/pitch computer: **Z** = set center, **H** = go to center.

Point the seat straight ahead before the first run (or press **Z** once it is), since that's angle 0 for the limits.

## Settings (top of startup.lua)

| Setting | Default | |
|---|---|---|
| `SEAT` | `"seat1"` | same on all 3; use another name for a second seat |
| `KEYS` | w/s/a/d | typewriter keys (they must be bound to a frequency on the typewriter) |
| `STEP` | 5 | degrees per gearshift step |
| `SPEED` | 1 | 1 = gearshift input speed, 2 = double |
| `INVERT_YAW` / `INVERT_PITCH` | false | flip if a key turns the wrong way |
| `YAW_MIN` / `YAW_MAX` | nil | yaw limits (nil = spin freely) |
| `PITCH_MIN` / `PITCH_MAX` | -60 / 60 | pitch limits |
| `TIMEOUT` | 0.5 | seconds without the seat before the gearshifts stop |

Angles are gearshift shaft degrees. If you gear the bearing up or down, the limits scale with it.

## Safety

If the seat computer goes quiet (unloaded, broken, rebooting), yaw and pitch stop after `TIMEOUT`. The angle is saved after every step, so limits survive reboots.

Updates install by themselves (every 15 min and on reboot), keeping your settings. `AUTO_UPDATE = false` turns that off.
