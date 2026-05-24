# FrogSpy

A two-part bazaar price checking tool for the [Project Lazarus](https://www.lazaruseq.com/) EverQuest emulator server, powered by [FrogTracker](https://frogtracker.biz).

## Overview

- **`frogspy.lua`** -- MacroQuest Lua script that exports your trader's inventory to a flat file using MQ2Bzsrch
- **`frogspy.py`** -- Python script that reads the inventory file and checks each item's price against live market data from [FrogTracker](https://frogtracker.biz)
- **`frogspy_scraper.py`** -- FrogTracker API data layer: typed dataclasses, retry logic, TTL cache, and access to all price windows
- **`frogspy_display.py`** -- Optional rich terminal output module with color-coded results and summary dashboard

## Requirements

### In-game (Lua exporter)
- MacroQuest (Rekka's E3Next build for Project Lazarus)
- MQ2Bzsrch plugin (included in the Lazarus MQ build -- loaded automatically by the script)

### Python (price checker)
- Python 3.8+
- `requests` library: `pip install requests`
- `rich` library *(optional, for color output)*: `pip install rich`

## Usage

### Step 1 -- Export your trader inventory

1. Log into your trader character and enter trader mode (`/trader`)
2. Run the Lua script -- it opens the Bazaar Search Window automatically:
   ```
   /lua run frogspy
   ```
3. This creates `kreigar_inventory.txt` on your Desktop in `ItemName|Price` format

### Step 2 -- Check prices against the market

```
python frogspy.py --inventory "C:\Users\YourName\Desktop\kreigar_inventory.txt"
```

#### Options

| Argument | Default | Description |
|---|---|---|
| `--inventory` | *(required)* | Path to inventory file |
| `--trader` | `Kreigar` | Your trader's character name |
| `--delay` | `0.3` | Seconds between API requests |
| `--output` | `frogspy_output.txt` | Output report file |
| `--no-cache` | *(flag)* | Disable the in-memory response cache |

## Module: frogspy_scraper

`frogspy_scraper.py` is a standalone data-access layer you can use independently:

```python
from frogspy_scraper import make_client

with make_client(delay=0.3) as client:
    result = client.get_item_history("Water Flask")
    if result:
        print(result.windows.seven_day_low)
        print(result.windows.thirty_day_median)
        print(result.competitor_prices("Kreigar"))
    
    names = client.search_items("robe")
    deals = client.get_hot_dealz()
```

### Price windows available

| Field | Description |
|---|---|
| `seven_day_low` / `seven_day_median` | 7-day lowest and median |
| `thirty_day_low` / `thirty_day_median` | 30-day lowest and median |
| `ninety_day_low` / `ninety_day_median` | 90-day lowest and median |
| `one_year_low` / `one_year_median` | 1-year lowest and median |
| `lifetime_low` / `lifetime_median` | All-time lowest and median |

## File locations

| File | Location |
|---|---|
| `frogspy.lua` | `C:\Games\MacroQuest\lua\` |
| `frogspy.py` | Anywhere Python can run it |
| `frogspy_scraper.py` | Same directory as `frogspy.py` |
| `frogspy_display.py` | Same directory as `frogspy.py` |
| Inventory file (output) | Desktop (configurable in lua script) |
| Report file (output) | Same directory as `frogspy.py` |

## License

MIT
