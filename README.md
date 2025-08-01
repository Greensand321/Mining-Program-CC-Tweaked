# Mining Program (CC:Tweaked)

This repository contains two programs:

* **controller.lua** – run on a computer. It coordinates multiple mining turtles over `rednet`.
* **miner.lua** – run on a turtle. It receives jobs from the controller and mines.
Each job corresponds to the centre of a 16×16 chunk, producing a 15×15 shaft.

## Basic usage
1. Attach a modem to the computer and each turtle and set unique labels for every turtle.
2. Run `controller.lua` on the computer and `miner.lua` on each turtle.
3. Use the controller's menu (↑/↓ and Enter) to start turtles and begin mining.

### Controller Menu
1. Change Mining Start Depth
2. Start Turtle
3. Start Mining
4. Pause Mining
5. Resume Mining
6. View Status

Press **Backspace** to return from sub‑menus.

### Turtle display
Each turtle now shows its current GPS coordinates and chunk position on the first line of its display.
