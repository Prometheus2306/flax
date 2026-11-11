# FLAX

A minimalist, mobile-first puzzle game in the spirit of Atari's *Klax*, built with Godot 4.

Tiles roll down a 5-lane conveyor. Catch them on the paddle, drop them into the five bins, and line up
**3 or more of the same color** (across, up, or diagonally) to clear them. Miss three tiles, or throw a
tile at a full bin, and the run is over.

## Controls

| Action | Touch | Keyboard |
| --- | --- | --- |
| Move paddle | Tap a lane or drag horizontally | Left / Right, A / D |
| Drop top tile | Tap your current lane, or the **DROP** button | Space / Down / S |
| Flip top tile back up the belt | Swipe up, or the **FLIP** button | Up / W |
| Pause | Pause icon (top left) | Esc / P |

The paddle holds up to 5 tiles; the last one caught is the first one dropped.

## Scoring

* Line of 3 / 4 / 5: 100 / 300 / 800 points, diagonals pay double.
* Clears that cascade (gravity creates a new match) multiply with the chain count.
* Every wave has a "clear N tiles" goal; clearing it gives a bonus, speeds the belt up, and every third wave
  adds a life. More colors join the belt as waves progress.

## Project layout

| File | Purpose |
| --- | --- |
| `main.gd` / `Main.tscn` | Game state, rules, input |
| `board.gd` | Pure board logic (match finding, gravity), unit-testable |
| `view.gd` | All drawing (procedural, no image assets) |
| `sfx.gd` | Synthesized sound effects |
| `flax_style.gd` | Palette |
| `tests/` | Headless tests and a screenshot helper |

## Tests

```
godot --headless --path . --script res://tests/board_test.gd   # board logic
godot --headless --path . --script res://tests/smoke_test.gd   # bot plays, touch gestures, flow
godot --path . --resolution 720x1280 --script res://tests/screenshot.gd -- <output_dir>
```
