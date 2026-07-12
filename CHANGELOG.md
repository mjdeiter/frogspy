# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-07-11

### Changed — full rewrite: Python tool replaced with a pure in-game Lua app
FrogSpy is no longer a two-step "export from game, then run a Python script" tool. The entire
workflow now lives in-game as an ImGui control panel that drives BazaarWnd directly and talks to
FrogTracker live.

- **`frogspy.lua`** (renamed from `frogspy_ui.lua`, v0.7.0) — ImGui control panel / tick-loop
  driver. Replaces the old `frogspy.lua` exporter entirely; run with `/lua run frogspy`.
- **`frogspy_price_fsm.lua`** (v0.2.0, new) — companion state-machine module: BazaarWnd
  automation (Window TLO + `/notify`), FrogTracker HTTP client, and the batch-audit engine.

### Added (highlights carried over from the pre-1.0 Lua development history)
- Live price-setting: type an item + Platinum/Gold/Silver/Copper amount and FrogSpy drives the
  BazaarWnd controls to queue the update — no manual INI editing.
- "Find Lowest Bazaar Price" and "Get FrogTracker Price" lookups to reference before committing
  a price.
- "Audit This Item" — single-item check, with a market-only fallback (`MARKET` status) for items
  not currently sitting in a trader slot.
- "Batch Audit Selected" — refresh the occupied-slot list, pick items via checklist, and audit
  them all in one pass. Results are grouped (duplicate item/price rows collapse with a Count
  column) and color-coded (red = undercut, green = cheapest/tied, gray = no competition,
  blue = market-only).
- Individually toggleable FrogTracker time windows (7-day / 30-day / 90-day / 1-year / lifetime),
  with the results table's columns adapting to which are enabled.
- Optional persistent audit log — appends a timestamped record (character, summary counts,
  per-item detail) to `frogspy_audit_log.txt` in the MacroQuest config directory once per
  finished audit.
- Per-scan FrogTracker response cache (keyed by lowercased item name) so a batch audit with
  duplicate item names doesn't re-query market data that can't have changed between two lookups
  moments apart.
- Window title includes the running version number at a glance.

### Removed
- `frogspy.py`, `frogspy_display.py`, `frogspy_scraper.py`, `frogspy.bat`, `requirements.txt` —
  the Python GUI/CLI price checker and its self-extracting launcher. Fully superseded by the
  live in-game tool; no external step needed anymore.
- `frogspy_frog.png`, `frogspy_frog_icon.ico`, `frogspy_icon.ico`, `frogspy_lady.png`,
  `frogspy_logo.png` — image assets used only by the retired Tkinter GUI/bat launcher.

## [1.5.1] - 2026-05-25

### Fixed
- `frogspy.bat` — rewrote base64 embedding to use `(echo ...)>>tempfile` approach instead of env vars
  - cmd.exe truncates env vars at 8,192 chars, silently corrupting the embedded PNG data
  - PNGs are now written in 200-char echo chunks to `%TEMP%\frogspy\*.b64`, decoded via `certutil`, then deleted
  - Bat is fully self-contained; no loose PNG files needed alongside it

## [1.5.0] - 2026-05-24

### Added
- **Full Tkinter GUI** — launch with `frogspy.bat` (double-click) or `python frogspy.py --gui`
  - Dark-themed table with color-coded rows: red = undercut, green = cheapest/tied, blue = solo
  - Stat cards showing total / undercut / cheapest / solo / elapsed time
  - Columns: Status, Item, Your Price, Lowest, Gap %, Rivals, 7d Low, 7d Med, 30d Low, 30d Med
  - Sortable columns (click header to toggle asc/desc)
  - Inventory file picker and trader name field
  - Live row streaming — results appear as they come in, no waiting for full scan
  - Stop button to cancel mid-scan
  - Auto-fills inventory path if `kreigar_inventory.txt` exists on Desktop
- `frogspy.bat` — double-click launcher; finds Python automatically (py → python → python3), opens GUI with no terminal window

### Changed
- `frogspy_scraper.py` merged into `frogspy.py` — single-file deployment, same reusable API layer
- `--gui` flag added to CLI; bare `python frogspy.py` (no `--inventory`) also opens GUI
- Version bumped to `1.5.0`

### Removed
- `frogspy_scraper.py` — functionality merged into `frogspy.py`
- `frogspy_logo.png` — removed from repo

## [1.4.0] - 2026-05-24

### Added
- `frogspy_scraper.py` — FrogTracker API data layer
  - `ScraperClient` class with configurable per-request delay, retry with exponential back-off, and in-memory TTL cache (default 5 min)
  - Typed dataclasses: `ItemHistoryResult`, `HistoryEntry`, `PriceWindows`, `HotDeal`
  - Full price window coverage: 7-day, 30-day, 90-day, 1-year, and lifetime lowest/median prices
  - `active_listings()`, `active_listings_excluding()`, and `competitor_prices()` convenience methods on `ItemHistoryResult`
  - `search_items(query)` — item name search via `/Home/Search`
  - `get_hot_dealz()` — optional hot deal list via `/Home/HotDealz`
  - `make_client()` convenience factory
  - Supports use as a context manager (`with make_client() as client:`)
- `--no-cache` flag in `frogspy.py` to bypass the scraper's in-memory cache
- `analyze_item()` now populates 30-day and 90-day price windows in addition to 7-day

### Changed
- `frogspy.py` now imports and uses `frogspy_scraper.ScraperClient` instead of raw `requests.Session`
- Version bumped to `1.4.0`

## [1.3.0] - 2026-05-24

### Added
- `frogspy_display.py` — rich terminal output module
  - Color-coded status badges: **UNDERCUT** (red), **SOLO** (green), **CHEAPEST** (cyan)
  - Live per-item output with competitor count and gap percentage during scan
  - End-of-scan summary with stat cards (total / undercut / solo / cheapest)
  - Full sorted detail table with undercut items floated to the top
  - Monospaced price columns with comma formatting
- `rich` added as an optional dependency (`pip install rich`)

### Changed
- `frogspy.py` refactored to use `frogspy_display.py` when available
- `analyze_item()` now returns a structured dict instead of a plain string
- Falls back gracefully to plain-text output if `rich` is not installed
- Version bumped to `1.3.0`

## [1.2.0] - 2026-05-23

### Changed
- Project renamed from **Bazaar Checker** to **FrogSpy**
- Repository renamed to `frogspy`
- `bazaar_checker.lua` renamed to `frogspy.lua`; run command is now `/lua run frogspy`
- `bazaar_checker.py` renamed to `frogspy.py`
- All log prefixes updated from `[BazaarChecker]` to `[FrogSpy]`
- Version header updated: `FrogSpy v1.2.0`
- Output report file renamed from `bazaar_check_output.txt` to `frogspy_output.txt`

## [1.1.0] - 2026-05-23

### Changed
- Renamed `export_trader.lua` to `bazaar_checker.lua`; run command updated to `/lua run bazaar_checker`
- All log prefixes updated from `[ExportTrader]` to `[BazaarChecker]`

### Added
- Version header and author signature printed on startup
- `SCRIPT_VERSION` constant defined at top of script

## [1.0.0] - 2026-05-23

### Added
- `export_trader.lua` — MacroQuest Lua script to export trader inventory via MQ2Bzsrch
  - Auto-loads MQ2Bzsrch plugin if not already active
  - Auto-opens BazaarSearchWnd if not already open (prevents client crash on Lazarus)
  - Searches bazaar filtered to current character name
  - Converts MQ2Bzsrch copper prices to platinum (divided by 1000, rounded to nearest)
  - Writes `ItemName|Price` inventory file to Desktop
- `bazaar_checker.py` — Python price comparison tool
  - Reads `ItemName|Price` inventory file generated by the Lua exporter
  - Queries FrogTracker ItemHistory API for each item
  - Reports cheapest/tied, undercut, and no-competition status per item
  - Includes 7-day low and median market prices
  - Generates summary report with counts
  - Saves full report to output text file
