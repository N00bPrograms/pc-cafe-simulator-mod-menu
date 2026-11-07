# PC Cafe Mod Menu

An in-game cheat menu for **PC Cafe Simulator** (Steam app 3375990), built as a
[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod. Press **Insert** in game.

> Unofficial fan mod, not affiliated with the developers. Works in single player and in co-op
> lobbies you host. As a guest the menu is read-only, because the host's game owns the cafe.

## Features

| Tab | What it does |
|---|---|
| Money | +$1k / +$10k / +$100k / +$1M, add or set any amount (5000, 50k, 2m), lock cash, clear unpaid bills. |
| Cafe | Add XP, level up or down, add skill points, raise or lower the rating. |
| Time | Freeze the clock, skip an hour, end the day, set the time, longer days, weather (clear, rain, snow, storm). |
| Player | Move speed ×1 to ×3, reach (interact and place distance) ×1 to ×4. |

The top of the panel shows cash, level, XP, skill points, day, time and rating.
Cheat money isn't counted as income, so the end-of-day report stays accurate.

## Install

1. Install the **UE4SS experimental build** (it supports Unreal Engine 5.6): download
   `UE4SS_v3.0.1-…zip` from the [experimental-latest release](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest)
   and extract it into `PC Cafe Simulator\PCCafeSimulator\Binaries\Win64`.
2. Extract `PCCafeModMenu-v1.0.zip` into the same `Binaries\Win64` folder. It adds
   `ue4ss\Mods\PCCafeModMenu` (its `enabled.txt` tells UE4SS to load it).
3. Start the game, load a save and press **Insert**.

To change the key, edit `MENU_KEY` and `INSERT` near the top and in the loop section of `Scripts\main.lua`.

## How it works

- The game's state lives on `PCCafeGameState` (cash, level, XP, skill points, rating, clock).
  Cash is stored in thousandths of a dollar; the menu converts to real dollars.
- The UI is built at run time from UMG widgets (`Border`, `Button`, `TextBlock`, `WidgetSwitcher`)
  and added to the viewport. Clicks are detected by polling each button's pressed state.
- Weather and XP use the game's own `PCCafeCheatManager`.
- Insert is caught by a UE4SS key bind and, as a fallback, by asking the player controller
  whether the key is down.
