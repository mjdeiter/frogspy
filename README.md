# FrogSpy

A [MacroQuest](https://www.macroquest.org/) Lua ImGui trader price management tool for the [Project Lazarus](https://www.lazaruseq.com/) EverQuest emulator server, powered by [FrogTracker](https://frogtracker.biz).

## Overview

As of v2.0.0, FrogSpy is a pure in-game Lua tool — no external Python step, no exported inventory file, no separate report to open afterward. It talks to your live BazaarWnd directly and pulls market data from FrogTracker in real time while you play.

- **`frogspy.lua`** — ImGui control panel and tick-loop driver. This is the file you run (`/lua run frogspy`).
- **`frogspy_price_fsm.lua`** — Companion state-machine module. Owns all BazaarWnd automation (Window TLO + `/notify`), FrogTracker HTTP requests, and the batch-audit engine. Required by `frogspy.lua`; not run directly.

## Requirements

- MacroQuest (Rekka's E3Next build for Project Lazarus)
- MQ2Bzsrch plugin (included in the Lazarus MQ build — loaded automatically as needed)
- ImGui support in your MacroQuest build

## Usage

1. Log into your trader character and enter trader mode (`/trader`)
2. Run:
   ```
   /lua run frogspy
   ```
3. The control panel opens. From there you can:
   - **Set a price** — enter an item name (auto-fills from whatever's selected in BazaarWnd) and Platinum/Gold/Silver/Copper amounts, then queue the update — FrogSpy drives the BazaarWnd controls for you.
   - **Find Lowest Bazaar Price** — look up the current lowest listing for an item before committing a price.
   - **Get FrogTracker Price** — pull FrogTracker's 30-day median (plus 7-day/90-day/1-year/lifetime windows printed to console) as a pricing reference.
   - **Audit This Item** — check a single item (trader slot or market-only) against FrogTracker data.
   - **Batch Audit Selected** — refresh the list of occupied trader slots, check the ones you want, and audit them all in one pass. Results show in a color-coded table (red = undercut, green = cheapest/tied, gray = no competition, blue = market-only).
   - **Time-window toggles** — turn FrogTracker's 7-day/30-day/90-day/1-year/lifetime windows on or off individually; the results table adapts its columns accordingly.
   - **Audit Logging** — optionally append a timestamped record of every finished audit (character, summary counts, per-item detail) to a log file on disk, for a persistent history beyond what's on screen.

## Important notes

### MQ2Bzsrch on Project Lazarus
MQ2Bzsrch crashes the EQ client if it triggers a search while the Bazaar Search Window is closed. FrogSpy handles this automatically — it opens the window and waits for it to be ready before searching.

MQ2Bzsrch is disabled by default in the Lazarus MQ build (`mq2bzsrch=0` in `MacroQuest.ini`). FrogSpy loads it automatically at runtime — you do not need to enable it permanently.

### Price format
BazaarWnd and FrogTracker both work in platinum-denominated prices. FrogSpy's price fields split platinum into Platinum/Gold/Silver/Copper for you, matching how the window itself displays and accepts prices.

### Blocking calls
FrogTracker lookups ("Get FrogTracker Price", audits) are synchronous HTTP requests and will briefly pause the game for the round-trip (typically well under a second, but a large batch audit will visibly take a few seconds per item).

## File locations

| File | Location |
|---|---|
| `frogspy.lua` | `C:\Games\MacroQuest\lua\` |
| `frogspy_price_fsm.lua` | `C:\Games\MacroQuest\lua\` |
| Audit log (if enabled) | `<MacroQuest config dir>\frogspy_audit_log.txt` |

## License

MIT
