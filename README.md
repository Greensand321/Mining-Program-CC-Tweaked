# Mining Program CC Tweaked

This repository contains Lua scripts for the [CC: Tweaked](https://github.com/cc-tweaked/CC-Tweaked) mod for Minecraft. These programs let turtles automate a variety of mining tasks.

## Getting Started
1. Install CC: Tweaked and obtain a Turtle in your world.
2. Copy the desired `.lua` files onto the turtle using `pastebin`, `wget`, or a disk.
3. Ensure the turtle has fuel and the tools it needs (for example a diamond pickaxe and a modem for wireless features). Fuel items in the turtle's inventory count toward its fuel reserve and are only consumed when needed.
4. Keep all scripts in the same directory so that helper APIs such as `flex.lua` and `dig.lua` can be loaded by other programs.

## Included Programs
- `dig.lua` – movement and coordinate tracking API used by the other scripts.
- `flex.lua` – utility functions for logging, block detection, and network messaging.
- `quarry.lua` – digs out a rectangular quarry. Usage: `quarry <width> [length] [depth]`.
- `receive.lua` – listens on modem channel `6464` and prints messages sent via `flex.lua`.
- `stairs.lua` – digs a staircase a fixed distance (`distance` variable).

## Running the Programs
From the turtle prompt run the script by name. For example:

```
quarry 16 16 30   -- dig a 16×16 quarry 30 blocks deep
```

Run `receive` on a computer with a modem attached to monitor messages sent with `flex.lua`'s `send` function.

## Global Control
Turtles running `quarry.lua` listen for a Rednet broadcast of the string `RETURN`. Broadcasting `RETURN` causes every turtle to navigate home, unload, refuel, and then automatically resume mining. If the chest at home is missing, the turtle waits and reports an error until the chest is restored.

These scripts are intended for experimentation. Adjust the code and parameters to suit your own mining setup.
