# Mining Program (CC:Tweaked)

This repository contains two programs:

* **controller.lua** – run on a computer. It coordinates multiple mining turtles over `rednet`.
* **miner.lua** – run on a turtle. It receives jobs from the controller and mines.

## Basic usage
1. Place a modem on both the computer and each turtle and set unique labels for the turtles.
2. Run `controller.lua` on the computer and `miner.lua` on each turtle.
3. Turtles automatically receive jobs once they connect.

### Controller controls
- Press **ESC** to enter command mode and type commands shown at the bottom of the screen.
- Use the arrow keys to select a turtle. Press **Enter** to open the per‑turtle menu (Ping/Resume). Press **ESC** again to return to the command prompt.

### Turtle display
Each turtle now shows its current GPS coordinates and chunk position on the first line of its display.
