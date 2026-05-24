import argparse
import time
import random
import datetime
import os

SCRIPT_VERSION = "1.4.0"

try:
    from frogspy_display import (
        print_item_line, print_report,
        STATUS_UNDERCUT, STATUS_NONE, STATUS_CHEAPEST,
        console,
    )
    RICH = True
except ImportError:
    RICH = False
    STATUS_UNDERCUT = "undercut"
    STATUS_NONE     = "none"
    STATUS_CHEAPEST = "cheapest"

from frogspy_scraper import make_client


def load_inventory(filepath):
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


def analyze_item(item_name, my_price, history_result, trader_name):
    if history_result is None:
        return {
            "name": item_name, "your_price": my_price,
            "status": STATUS_NONE, "lowest": None,
            "rivals": 0, "low7": None, "med7": None,
            "low30": None, "med30": None,
            "low90": None, "med90": None,
            "lifetime_low": None, "lifetime_med": None,
            "error": True,
        }

    competitor_prices = history_result.competitor_prices(trader_name)
    w = history_result.windows

    if not competitor_prices:
        status = STATUS_NONE
        lowest = None
        rivals = 0
    else:
        lowest = competitor_prices[0]
        rivals = len(competitor_prices)
        status = STATUS_CHEAPEST if my_price <= lowest else STATUS_UNDERCUT

    return {
        "name":         item_name,
        "your_price":   my_price,
        "status":       status,
        "lowest":       lowest,
        "rivals":       rivals,
        "low7":         w.seven_day_low,
        "med7":         w.seven_day_median,
        "low30":        w.thirty_day_low,
        "med30":        w.thirty_day_median,
        "low90":        w.ninety_day_low,
        "med90":        w.ninety_day_median,
        "lifetime_low": w.lifetime_low,
        "lifetime_med": w.lifetime_median,
    }


def format_result_plain(result):
    name      = result["name"]
    my_price  = result["your_price"]
    status    = result["status"]
    lowest    = result.get("lowest")
    rivals    = result.get("rivals", 0)
    low7      = result.get("low7")
    med7      = result.get("med7")
    price_fmt = f"{my_price:,}"

    if result.get("error"):
        return f"  {name}: Could not retrieve market data.\n"

    if status == STATUS_NONE:
        if low7:
            return f"  {name}: Your price {price_fmt} -- no other sellers active. (7d low: {low7:,} | 7d med: {med7:,})\n"
        return f"  {name}: Your price {price_fmt} -- no other sellers active.\n"

    if status == STATUS_CHEAPEST:
        stats = f" | 7d low: {low7:,} | 7d med: {med7:,}" if low7 is not None else ""
        return f"  {name}: CHEAPEST (or tied) at {price_fmt} | {rivals} competitor(s){stats}\n"

    diff = my_price - lowest
    pct  = (diff / lowest) * 100
    stats = f" | 7d low: {low7:,} | 7d med: {med7:,}" if low7 is not None else ""
    return f"  {name}: UNDERCUT -- your {price_fmt} vs lowest {lowest:,} (+{diff:,} / +{pct:.1f}%) | {rivals} competitor(s){stats}\n"


def main():
    parser = argparse.ArgumentParser(
        description=f"FrogSpy v{SCRIPT_VERSION} - Bazaar price checker for Project Lazarus"
    )
    parser.add_argument("--trader",    default="Kreigar")
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--delay",     type=float, default=0.3)
    parser.add_argument("--output",    default="frogspy_output.txt")
    parser.add_argument("--no-cache",  action="store_true")
    args = parser.parse_args()

    start_time = datetime.datetime.now()
    print(f"\nFrogSpy v{SCRIPT_VERSION} -- Originally created by Alektra <Lederhosen>")
    print(f"Starting at {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Trader: {args.trader}")
    print(f"Inventory file: {args.inventory}\n")

    trader_items = load_inventory(args.inventory)
    if not trader_items:
        print("No items loaded.")
        return

    cache_ttl = 0 if args.no_cache else 300
    results = []
    total   = len(trader_items)

    with make_client(delay=args.delay, cache_ttl=cache_ttl) as client:
        for i, (item_name, my_price) in enumerate(sorted(trader_items.items()), 1):
            print(f"[{i}/{total}] Checking: {item_name} (your price: {my_price:,})")
            history = client.get_item_history(item_name)
            result  = analyze_item(item_name, my_price, history, args.trader)
            results.append(result)
            if RICH:
                print_item_line(result)
            else:
                print(format_result_plain(result), end="")

    end_time = datetime.datetime.now()
    elapsed  = (end_time - start_time).total_seconds()

    undercut_count = sum(1 for r in results if r["status"] == STATUS_UNDERCUT)
    cheapest_count = sum(1 for r in results if r["status"] == STATUS_CHEAPEST)
    no_competition = total - undercut_count - cheapest_count

    if RICH:
        print_report(results, trader=args.trader, elapsed=elapsed,
                     timestamp=end_time.strftime("%Y-%m-%d %H:%M:%S"))
    else:
        print(
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
        for r in results:
            f.write(format_result_plain(r))
        f.write(
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

    print(f"Full report saved to: {args.output}")


if __name__ == "__main__":
    main()
