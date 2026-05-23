import argparse
import requests
import time
import random
import datetime
import urllib3
import os

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

SCRIPT_VERSION    = "1.2.0"
FROGTRACKER_BASE  = "https://frogtracker.biz/Home"
HEADERS = {
    "Accept": "application/json, text/javascript, */*; q=0.01",
    "X-Requested-With": "XMLHttpRequest",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
}


def load_inventory(filepath):
    """Load items from a text file. Format: ItemName|Price (one per line)."""
    items = {}
    if not os.path.exists(filepath):
        print(f"  ERROR: Inventory file not found: {filepath}")
        return items
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            if len(parts) == 2:
                item_name = parts[0].strip()
                try:
                    price = int(parts[1].strip().replace(",", ""))
                    items[item_name] = price
                except ValueError:
                    print(f"  WARNING: Could not parse price for line: {line}")
    print(f"  Loaded {len(items)} item(s) from {filepath}")
    return items


def get_item_history(session, item_name):
    """Fetch full price history for an item."""
    try:
        response = session.get(
            f"{FROGTRACKER_BASE}/ItemHistory",
            params={"itemName": item_name},
            headers=HEADERS,
            timeout=15,
        )
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"  ERROR fetching history for '{item_name}': {e}")
        return None


def analyze_item(item_name, my_price, history_data, trader_name):
    """Compare my price against current competitors."""
    if not history_data or "history" not in history_data:
        return f"  {item_name}: Could not retrieve market data.\n"

    competitor_prices = [
        entry["price"]
        for entry in history_data["history"]
        if entry.get("isForSaleNow")
        and entry.get("sellerName", "").lower() != trader_name.lower()
    ]

    seven_day_low = history_data.get("sevenDayLowestPrice")
    seven_day_med = history_data.get("sevenDayMedianPrice")
    price_fmt = f"{my_price:,}"

    if not competitor_prices:
        if seven_day_low:
            return f"  {item_name}: Your price {price_fmt} -- no other sellers active. (7d low: {seven_day_low:,} | 7d med: {seven_day_med:,})\n"
        return f"  {item_name}: Your price {price_fmt} -- no other sellers active.\n"

    lowest_competitor = min(competitor_prices)
    num_competitors = len(competitor_prices)

    if my_price <= lowest_competitor:
        status = f"CHEAPEST (or tied) at {price_fmt}"
    else:
        diff = my_price - lowest_competitor
        pct = (diff / lowest_competitor) * 100
        status = f"UNDERCUT -- your {price_fmt} vs lowest {lowest_competitor:,} (+{diff:,} / +{pct:.1f}%)"

    stats = ""
    if seven_day_low is not None:
        stats = f" | 7d low: {seven_day_low:,} | 7d med: {seven_day_med:,}"

    return f"  {item_name}: {status} | {num_competitors} competitor(s){stats}\n"


def main():
    parser = argparse.ArgumentParser(description=f"FrogSpy v{SCRIPT_VERSION} — Bazaar price checker for Project Lazarus")
    parser.add_argument("--trader", default="Kreigar", help="Your trader name (default: Kreigar)")
    parser.add_argument("--inventory", required=True, help="Path to inventory file (ItemName|Price per line)")
    parser.add_argument("--delay", type=float, default=0.3, help="Delay between requests in seconds (default: 0.3)")
    parser.add_argument("--output", default="frogspy_output.txt", help="Output report file (default: frogspy_output.txt)")
    args = parser.parse_args()

    session = requests.Session()
    start_time = datetime.datetime.now()
    print(f"\nFrogSpy v{SCRIPT_VERSION} -- Originally created by Alektra <Lederhosen>")
    print(f"Starting at {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Trader: {args.trader}")
    print(f"Inventory file: {args.inventory}\n")

    trader_items = load_inventory(args.inventory)

    if not trader_items:
        print("No items loaded. Make sure the inventory file exists and has lines like:")
        print("  Crystal Dagger|100000")
        print("  Water Flask|1000")
        return

    results = []
    total = len(trader_items)
    for i, (item_name, my_price) in enumerate(sorted(trader_items.items()), 1):
        print(f"[{i}/{total}] Checking: {item_name} (your price: {my_price:,})")
        if args.delay:
            time.sleep(random.uniform(args.delay * 0.5, args.delay * 1.5))
        history = get_item_history(session, item_name)
        result = analyze_item(item_name, my_price, history, args.trader)
        results.append(result)
        print(result, end="")

    end_time = datetime.datetime.now()
    elapsed = (end_time - start_time).total_seconds()
    undercut_count = sum(1 for r in results if "UNDERCUT" in r)
    cheapest_count = sum(1 for r in results if "CHEAPEST" in r)
    no_competition = total - undercut_count - cheapest_count

    summary = (
        f"\n{'='*60}\n"
        f"FrogSpy -- {args.trader} -- {end_time.strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"{'='*60}\n"
        f"Total items checked : {total}\n"
        f"Cheapest / tied     : {cheapest_count}\n"
        f"Being undercut      : {undercut_count}\n"
        f"No competition      : {no_competition}\n"
        f"Time elapsed        : {elapsed:.1f}s\n"
        f"{'='*60}\n"
    )

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(f"FrogSpy -- {args.trader} -- {start_time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.writelines(results)
        f.write(summary)

    print(summary)
    print(f"Full report saved to: {args.output}")


if __name__ == "__main__":
    main()
