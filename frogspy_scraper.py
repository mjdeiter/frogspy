"""
frogspy_scraper.py — FrogTracker API data layer for FrogSpy
============================================================
Wraps the FrogTracker.biz REST API with:
  - Typed dataclasses for all response shapes
  - Automatic retry with exponential back-off
  - Simple in-memory TTL cache to avoid redundant requests
  - Rate-limiting via configurable per-request delay
  - A high-level ScraperClient class used by frogspy.py

API endpoints used:
  GET /Home/ItemHistory?itemName=<name>
      Full price history + pre-aggregated price windows (7/30/90-day, 1-year, lifetime)
  GET /Home/Search?q=<partial>
      Item name search (returns matching item names)
  GET /Home/HotDealz
      Server-side curated deal list (optional / informational)

Author: FrogSpy project (mjdeiter)
"""

from __future__ import annotations

import time
import random
import urllib3
import requests
import datetime
import dataclasses
from typing import Optional

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

FROGTRACKER_BASE = "https://frogtracker.biz/Home"

_DEFAULT_HEADERS = {
    "Accept": "application/json, text/javascript, */*; q=0.01",
    "X-Requested-With": "XMLHttpRequest",
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
}


@dataclasses.dataclass
class PriceWindows:
    seven_day_low: Optional[int]
    seven_day_median: Optional[int]
    thirty_day_low: Optional[int]
    thirty_day_median: Optional[int]
    ninety_day_low: Optional[int]
    ninety_day_median: Optional[int]
    one_year_low: Optional[int]
    one_year_median: Optional[int]
    lifetime_low: Optional[int]
    lifetime_median: Optional[int]


@dataclasses.dataclass
class HistoryEntry:
    auction_date: str
    price: int
    seller_name: str
    is_for_sale_now: bool


@dataclasses.dataclass
class ItemHistoryResult:
    item_name: str
    last_scrape_time: Optional[int]
    history: list
    windows: PriceWindows

    def active_listings(self):
        return [e for e in self.history if e.is_for_sale_now]

    def active_listings_excluding(self, trader_name: str):
        lower = trader_name.lower()
        return [e for e in self.active_listings() if e.seller_name.lower() != lower]

    def competitor_prices(self, trader_name: str):
        return sorted(e.price for e in self.active_listings_excluding(trader_name))

    def last_scrape_dt(self):
        if self.last_scrape_time is None:
            return None
        return datetime.datetime.utcfromtimestamp(self.last_scrape_time / 1000)


@dataclasses.dataclass
class HotDeal:
    item_name: str
    price: int
    seller_name: str
    lowest_price: Optional[int]


class _TTLCache:
    def __init__(self, ttl_seconds: int = 300):
        self._ttl = ttl_seconds
        self._store = {}

    def get(self, key: str):
        entry = self._store.get(key)
        if entry is None:
            return None
        ts, value = entry
        if time.time() - ts > self._ttl:
            del self._store[key]
            return None
        return value

    def set(self, key: str, value) -> None:
        self._store[key] = (time.time(), value)

    def invalidate(self, key: str) -> None:
        self._store.pop(key, None)

    def clear(self) -> None:
        self._store.clear()


class ScraperClient:
    """
    High-level client for the FrogTracker API.

    Parameters
    ----------
    delay : float
        Base delay between requests in seconds (actual delay is
        randomised +/-50% to avoid rate-limit patterns).
    retries : int
        Number of retry attempts on transient failure before giving up.
    cache_ttl : int
        Seconds to cache ItemHistory results in memory (default 5 min).
        Set to 0 to disable caching.
    timeout : int
        HTTP request timeout in seconds.
    """

    def __init__(self, delay=0.3, retries=3, cache_ttl=300, timeout=15):
        self._delay = delay
        self._retries = retries
        self._timeout = timeout
        self._cache = _TTLCache(cache_ttl) if cache_ttl > 0 else None
        self._session = requests.Session()
        self._session.headers.update(_DEFAULT_HEADERS)
        self._last_request_time = 0.0

    def _throttle(self):
        if self._delay <= 0:
            return
        elapsed = time.time() - self._last_request_time
        jitter = random.uniform(self._delay * 0.5, self._delay * 1.5)
        wait = max(0.0, jitter - elapsed)
        if wait > 0:
            time.sleep(wait)
        self._last_request_time = time.time()

    def _get(self, endpoint: str, params: dict):
        url = f"{FROGTRACKER_BASE}/{endpoint}"
        backoff = 1.0
        for attempt in range(1, self._retries + 1):
            try:
                self._throttle()
                resp = self._session.get(url, params=params, timeout=self._timeout, verify=False)
                resp.raise_for_status()
                return resp.json()
            except requests.exceptions.HTTPError as exc:
                if exc.response is not None and exc.response.status_code < 500:
                    return None
                _warn(f"HTTP error on attempt {attempt}/{self._retries}: {exc}")
            except requests.exceptions.RequestException as exc:
                _warn(f"Request error on attempt {attempt}/{self._retries}: {exc}")
            if attempt < self._retries:
                time.sleep(backoff + random.uniform(0, 0.5))
                backoff *= 2
        return None

    def get_item_history(self, item_name: str):
        cache_key = f"history:{item_name.lower()}"
        if self._cache is not None:
            cached = self._cache.get(cache_key)
            if cached is not None:
                return cached
        raw = self._get("ItemHistory", {"itemName": item_name})
        if raw is None:
            return None
        result = _parse_item_history(raw)
        if result is not None and self._cache is not None:
            self._cache.set(cache_key, result)
        return result

    def search_items(self, query: str):
        raw = self._get("Search", {"q": query})
        if raw is None:
            return []
        return raw.get("itemNames", []) or []

    def get_hot_dealz(self):
        raw = self._get("HotDealz", {})
        if raw is None:
            return []
        deals = raw.get("dealz") or []
        results = []
        for d in deals:
            try:
                results.append(HotDeal(
                    item_name=d.get("itemName", ""),
                    price=_safe_int(d.get("price")),
                    seller_name=d.get("sellerName", ""),
                    lowest_price=d.get("lowestPrice"),
                ))
            except Exception:
                continue
        return results

    def invalidate_cache(self, item_name=None):
        if self._cache is None:
            return
        if item_name is None:
            self._cache.clear()
        else:
            self._cache.invalidate(f"history:{item_name.lower()}")

    def close(self):
        self._session.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def _parse_item_history(raw: dict):
    try:
        history = []
        for entry in raw.get("history") or []:
            try:
                history.append(HistoryEntry(
                    auction_date=entry.get("auctionDate", ""),
                    price=_safe_int(entry.get("price")),
                    seller_name=entry.get("sellerName", ""),
                    is_for_sale_now=bool(entry.get("isForSaleNow", False)),
                ))
            except Exception:
                continue

        windows = PriceWindows(
            seven_day_low=raw.get("sevenDayLowestPrice"),
            seven_day_median=raw.get("sevenDayMedianPrice"),
            thirty_day_low=raw.get("thirtyDayLowestPrice"),
            thirty_day_median=raw.get("thirtyDayMedianPrice"),
            ninety_day_low=raw.get("ninetyDayLowestPrice"),
            ninety_day_median=raw.get("ninetyDayMedianPrice"),
            one_year_low=raw.get("oneYearLowestPrice"),
            one_year_median=raw.get("oneYearMedianPrice"),
            lifetime_low=raw.get("lifetimeLowestPrice"),
            lifetime_median=raw.get("lifetimeMedianPrice"),
        )

        return ItemHistoryResult(
            item_name=raw.get("itemName", ""),
            last_scrape_time=raw.get("lastScrapeTime"),
            history=history,
            windows=windows,
        )
    except Exception as exc:
        _warn(f"Failed to parse ItemHistory response: {exc}")
        return None


def _safe_int(value) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _warn(msg: str) -> None:
    print(f"  [frogspy_scraper] WARNING: {msg}")


def make_client(delay=0.3, cache_ttl=300) -> ScraperClient:
    """Create a ScraperClient with sensible defaults."""
    return ScraperClient(delay=delay, cache_ttl=cache_ttl)
