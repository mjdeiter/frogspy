-- frogspy_price_fsm.lua
-- Frogspy companion module – live Bazaar trader price-setting via BazaarWnd
-- automation (Window TLO + /notify), so you don't have to camp out to edit
-- the INI by hand.
-- Version: 0.2.0
-- Author: Alektra <Lederhosen>
--
-- CHANGELOG:
-- v0.2.0 - Two features matching frogspy_ui.lua v0.6.0's new UI (which was
--          already written against this API and crashing on the old
--          v0.1.22 - see M.getWindowConfig() traceback):
--          (1) M.getWindowConfig()/M.setWindowEnabled(key, enabled) - a
--              persistent on/off table for frogtracker.biz's five time
--              windows (sevenDay/thirtyDay/ninetyDay/oneYear/lifetime),
--              all on by default. BATCH_REQUEST now pulls all five via the
--              new extractWindowFields() helper (was: hardcoded to
--              7-day/30-day only), skipping extraction for disabled
--              windows - fmtPrice() already renders nil as "-".
--          (2) BATCH_STATUS_MARKET + M.auditSingleItem() market-only
--              fallback: an item not found on the trader now queues a
--              row=nil entry instead of failing outright. BATCH_SELECT
--              skips the slot click, BATCH_REQUEST skips "your price" and
--              classifies it MARKET, still reporting frogtracker.biz's
--              lowest/rivals/window data for context. Trader-slot items
--              are unaffected.
-- v0.1.22 - Two small API additions for the UI's new selective-audit
--           checklist (requested after the v0.1.21 live test):
--           (1) M.startBatchAudit(queue) - public entry point that takes
--               an arbitrary caller-built { {row=,name=}, ... } list, so
--               the UI can run an audit over just the items the person
--               checked instead of always the whole inventory.
--               M.startBatchScan() and M.auditSingleItem() now both just
--               build a queue and hand it to this (or the shared
--               startBatchWithQueue() helper directly).
--           (2) M.getOccupiedSlots() - exposes the ordered occupied-slot
--               scan (same one startBatchScan() uses internally) so the
--               UI can render a checklist without re-implementing the
--               BazaarWnd scan. It's a real TLO scan of up to 200 child
--               windows, so the UI should cache the result rather than
--               calling this every render frame.
--           No changes to BATCH_* state logic itself - purely additive.
-- v0.1.21 - Two additions, both requested after the v0.1.20 live test
--           (64-item scan, 14 slots all named "Celestial Blessing of the
--           Djinn"):
--           (1) Per-scan FrogTracker cache, keyed by lowercased item
--               name - duplicate item names across slots now reuse the
--               first lookup's rivals/low7/med7/low30/med30 instead of
--               re-querying frogtracker.biz for market data that can't
--               have changed between two passes moments apart. "Your
--               price" is still read fresh per slot (a duplicate item can
--               genuinely be priced differently stack to stack). Cache is
--               scoped to one scan only - cleared at the start of every
--               scan, never reused across separate audits.
--           (2) M.auditSingleItem(itemName) - single-item version of
--               Batch Audit, refactored to share the same
--               BATCH_SELECT/BATCH_SETTLE/BATCH_REQUEST/BATCH_DELAY
--               states and getBatchScanProgress()/getBatchScanResults()
--               accessors as the full scan (just a queue of one, found via
--               the same trader-slot lookup enqueueByName() uses).
--           UNTESTED - the cache logic and single-item queue path haven't
--           been run live yet; the underlying BATCH_* states and
--           extraction/classification logic were already confirmed
--           working in the v0.1.20 live test.
-- v0.1.20 - BUG FIX, LIVE TEST RESULT: v0.1.19's Batch Audit computed
--           yourPrice in total COPPER ((pNum*1000)+(gNum*100)+(sNum*10)
--           +cNum) but frogtracker.biz's lowest/low7/med7 fields are in
--           PLATINUM - every undercut/cheapest comparison was comparing
--           mismatched units, off by ~1000x. Confirmed live 2026-07-10:
--           64-item scan reported "Blighted Berry Brew" at Your Price
--           4000000 when the real listed price is 4000pp, and returned
--           53/64 UNDERCUT - almost certainly inflated by this bug rather
--           than a real reflection of the trader (any nonzero-platinum
--           item will show a copper value ~1000x its true platinum price,
--           which will exceed nearly any real competitor's platinum
--           price). Fixed: yourPrice is now a platinum-equivalent float
--           (pNum + gNum/10 + sNum/100 + cNum/1000), matching
--           frogtracker.biz's units. NEEDS RE-TEST - the read mechanism
--           and extraction pattern were already confirmed correct; this
--           only fixes the unit conversion on top of them.
-- v0.1.19 - NEW FEATURE: Batch Audit - scans every occupied trader slot
--           and classifies each item as cheapest/undercut/no-competition
--           against frogtracker.biz's active listings, porting the
--           `frogspy` (Python) repo's analyze_item()/STATUS_* logic. Adds
--           M.startBatchScan() / isBatchScanRunning() / isBatchScanDone()
--           / getBatchScanProgress() / getBatchScanResults(). New
--           BATCH_SELECT -> BATCH_SETTLE -> BATCH_REQUEST -> BATCH_DELAY
--           loop, one item per pass, throttled by BATCH_DELAY_MS (300ms,
--           mirrors frogspy.py's --delay 0.3) between items.
--           DESIGN NOTE: originally planned to embed a pure-Lua JSON
--           decoder to parse frogtracker.biz's `history[]` array. Pulled a
--           real response live (2026-07-10) and found history[] holds
--           EVERY auction record ever scraped (6151 entries for one item
--           tested), of which typically only a handful are
--           isForSaleNow:true - decoding the whole array generically would
--           waste real per-tick blocking time across a 100+ item
--           inventory. Every entry has a confirmed-consistent flat field
--           order (auctionDate, price, sellerName, isForSaleNow), so
--           extractActiveListings() uses one targeted Lua pattern instead
--           - no JSON decoder needed at all. Deliberately narrow, not a
--           general JSON extractor - revisit if frogtracker.biz ever
--           changes that field order/shape.
--           Also confirmed live (2026-07-10, frogspy_price_read_test.lua
--           v0.1.0): BZW_Money0-3's .Text() live-tracks the actual
--           currently-selected item's listed price (not static XML
--           default text), which is what BATCH_REQUEST relies on to read
--           "your price" per slot - no MQ2Bzsrch dependency needed either.
--           UNTESTED end-to-end in-game - the read primitives and the
--           extraction pattern are each independently confirmed, but the
--           full multi-item loop (timing, ImGui polling) has not been run
--           live yet.
-- v0.1.18 - NEW FEATURE (Feature 2): FrogTracker.biz median/lowest price
--           lookup. Adds M.requestFrogTrackerPrice(itemName) / async poll
--           via M.isFrogTrackerDone() / M.getFrogTrackerResult(), mirroring
--           the M.requestLowestPrice() pattern exactly. New FT_REQUEST
--           state loads socket.http/ssl.https and the urlEncode/
--           extractString/extractNumberOrNull helpers, all lifted verbatim
--           from frogspy_frogtracker_test.lua v0.2.0 (confirmed working
--           live, zero errors, no dkjson/JSON-library dependency). NOTE:
--           unlike FIND_PRICE_*, https.request() is a synchronous call -
--           FT_REQUEST blocks its single tick for the full HTTP
--           round-trip (~tens of ms to ~1s observed). Acceptable for a
--           deliberate button click; see the in-code comment on FT_REQUEST
--           if this ever needs to become non-blocking.
-- v0.1.17 - REQUESTED CHANGE, not a bug fix: v0.1.16 confirmed the search
--           itself works, but the console report line still printed the
--           raw total in copper ("... = 495000cp"), which isn't how
--           people actually read bazaar prices. Now reuses the existing
--           splitCoins() helper (already used by the pricing flow) to
--           report in platinum, showing only non-zero denominations, so a
--           normal round-plat price reads as "495pp" instead of
--           "495000cp" or "495pp 0gp 0sp 0cp". frogspy_ui.lua's own
--           PP/GP/SP/CP input fields were already platinum-first and
--           don't need a change - this only affects the console log line.
-- v0.1.16 - ACTUAL ROOT CAUSE FOUND AND FIXED (two live tests, two
--           different items, both confirmed the same shift): v0.1.15's
--           full column dump showed col0 and col1 are always an empty
--           string for every row - never the item name - almost certainly
--           unlabeled/icon columns, not the text columns the v0.1.10 XML
--           review assumed started at column 1. Real confirmed layout:
--           col2=Name, col3=Qty, col4=Plat, col5=Gold, col6=Silver,
--           col7=Copper, col8=Trader (col9 was "TRUE" on every row of both
--           tests - purpose unknown/unneeded, left alone). Verified
--           against "Kromzek Tower Shield Ornament" (3 rows, qty=1 each,
--           prices 500/1800/3000 plat, traders Giddi/Shalltrader/Kreigar)
--           which matches the in-game Search Results table exactly column
--           for column. Shifted every FIND_PRICE_SCAN column reference by
--           +1 accordingly. The always-on full column dump from v0.1.15
--           is now conditional - it only fires if a row still fails to
--           match after this fix, so a clean run stays quiet but any
--           further surprise (unexpected characters, a different window
--           state, etc.) still gets full diagnostics instead of a silent
--           "not found". Next live run should return a real, non-zero
--           lowest price for both previously-tested items.
-- v0.1.15 - LIVE TEST RESULTS from v0.1.14: (1) SetText() readback confirmed
--           the search box held the full, correct string
--           ("The Ravenous Shadow", match=true) - the earlier truncated-
--           looking screenshot was purely a display artifact, not a real
--           SetText() bug. Ruled out. (2) list.Items() came back as a
--           plain Lua number (3) on the FIRST call already - the pcall'd
--           second call correctly errored ("attempt to call ... a number
--           value"), confirming count=3 is accurate and matches the 3
--           real rows visible in-game. Hypothesis (a) from v0.1.14 (that
--           Items() needs double-eval like List() did) is REJECTED - this
--           TLO member apparently doesn't need it, unlike List(row,col).
--           (3) The real bug: list.List(row,1)() returned an empty string
--           (not nil, not an error) for all 3 rows, despite "The Ravenous
--           Shadow" being clearly visible in the in-game Item Name column
--           for every row. This rules out a case/whitespace mismatch -
--           column 1 itself doesn't hold the name text. Leading
--           hypothesis: BZR_ItemList has an unlabeled column (e.g. an item
--           icon) ahead of the text columns, shifting every column index
--           over by one or more versus the v0.1.10 XML-based assumption
--           (1=Name, 2=Qty, 3-6=Plat/Gold/Silver/Copper, 7=Trader). Added:
--           a full column-by-column dump (col 0-9, each pcall'd
--           individually so an out-of-range column errors instead of
--           crashing the whole scan) for the first 5 rows of any search,
--           so the real layout is visible directly instead of guessing a
--           shift and redeploying blind. No matching logic changed yet -
--           next live run's console output should show exactly which
--           column holds the name and how far everything is shifted.
-- v0.1.14 - DIAGNOSTIC ONLY, no behavior change: v0.1.13 fixed the crash but
--           FIND_PRICE_SCAN still reports "No listings found" for items
--           confirmed visible in the Bazaar Search Window with multiple
--           matching rows ("iron ration", "The Ravenous Shadow" - both
--           tested live, both returned 0 matches). Two live hypotheses,
--           both untested: (a) list.Items() - unlike list.List(row,col) -
--           may itself need a second, empty () to convert from MQ userdata
--           to a real Lua number (per the same "every MQ call returns
--           userdata" rule that caused the v0.1.13 crash), meaning `count`
--           could silently be 0 or non-numeric and the row loop never
--           actually runs; or (b) the loop runs fine but each row's raw name
--           (from list.List(row,1)()) doesn't match searchItemName:lower()
--           for some reason not yet visible (case, whitespace, truncation,
--           etc). Added: (1) logs list.Items() AND a pcall'd second call on
--           it, with tostring/type for both, so we can see directly which
--           one (if either) yields a real number - this also protects
--           against a crash if the first call already returns a plain
--           number and the second call isn't valid to make on it; (2) logs
--           the count actually used for the loop; (3) logs every row's raw
--           name next to the match target and whether it matched, so a
--           mismatch (rather than a zero-count loop) shows up directly
--           instead of just the final "not found" warning; (4) in
--           FIND_PRICE_ENTER_NAME, logs a Text() readback immediately after
--           SetText() to settle whether the "he Ravenous Shadow"
--           (missing leading T) seen in one screenshot was a real dropped
--           character or just a narrow-field display/scroll artifact. No
--           matching logic changed - next live run's console output should
--           show exactly which hypothesis is correct.
-- v0.1.13 - ACTUAL ROOT CAUSE FOUND (v0.1.12's diagnostics pinned it
--           exactly): searchItemName was never nil - the crash was
--           nm:lower() on line "if nm and nm:lower() == matchName", where
--           nm came from list.List(row, 1). Per MacroQuest's own docs,
--           "Data returned by MQ is always of type userdata. Adding () on
--           the end will convert... to the appropriate lua datatype" -
--           this applies even to calls that already take arguments, like
--           List(row, col). list.List(row, 1) alone returns userdata (a
--           MQ-wrapped non-nil object, not a plain Lua string) - truthy,
--           so it passed `if nm and ...`, but with no .lower method,
--           hence the crash. Needed a SECOND, empty () to actually
--           evaluate: list.List(row, 1)(). This also silently broke
--           plat/gold/silver/copper extraction the same way -
--           tonumber(userdata) just returns nil, falling back to 0 via
--           "or 0" every time, meaning every price this search "found" so
--           far would have come back as 0. Fixed all four .List() calls in
--           FIND_PRICE_SCAN. The v0.1.12 diagnostics stay in place; the
--           v0.1.11/v0.1.12 nil-guards are harmless no-ops now but left in
--           as defense in depth.
-- v0.1.12 - The v0.1.11 nil-guard in requestLowestPrice() did NOT stop a
--           second, identical crash (confirmed via hash that v0.1.11 was
--           genuinely deployed and running) - meaning searchItemName went
--           nil through some path the guard doesn't cover. Rather than
--           guess a third time, added: (1) a log line at the entry of
--           requestLowestPrice() showing the raw itemName and its Lua
--           type, (2) a log line at the entry of every FIND_PRICE_* state
--           showing searchItemName's current value, and (3) a defensive
--           check right at the point of use in FIND_PRICE_SCAN, so even if
--           this recurs it fails soft with a warning instead of crashing.
--           Also: M.reset() ("Force FSM Reset") now also clears
--           searchItemName/searchResult/searchDone, which it previously
--           left untouched - not confirmed as the cause, but a reasonable
--           hygiene fix regardless.
-- v0.1.11 - Live test found two things: (1) the search flow itself WORKS -
--           SetText() and the Find button both functioned correctly, and a
--           real result came back showing the item's current listed price.
--           (2) A crash: "attempt to call method 'lower' (a nil value)" at
--           searchItemName:lower() - requestLowestPrice() got called with a
--           nil item name at some point. Every traced call site in
--           frogspy_ui.lua guards against an empty string but not
--           explicitly nil, so added a defensive check in
--           requestLowestPrice() itself rather than trust the caller.
--           Also: BazaarSearchWnd now opens itself via /bazaar if not
--           already open (new FIND_PRICE_OPEN_SEARCH/WAIT_OPEN states) -
--           confirmed live that /bazaar opens it; untested here is only
--           whether the 3-second wait is enough.
-- v0.1.10 - NEW FEATURE, UNTESTED: M.requestLowestPrice(itemName) searches
--           BazaarSearchWnd (the buyer-side "search all sellers" window -
--           confirmed as a genuinely different window from BazaarWnd via
--           the actual client XML, EQUI_BazaarSearchWnd.xml) and finds the
--           lowest currently-listed price for a matching item name, across
--           all sellers. Async (real server round-trip involved) - four new
--           FSM states (FIND_PRICE_ENTER_NAME/CLICK_FIND/WAIT/SCAN), poll
--           via M.isSearchDone() / M.getSearchResult(). Built from
--           documented MacroQuest APIs (window.Items, window.List[row,col],
--           window.SetText[]) and the confirmed XML column layout (1=Name,
--           2=Qty, 3-6=Plat/Gold/Silver/Copper, 7=Trader) - but genuinely
--           untested live: the SetText() method may hit the same rejection
--           settext did elsewhere in this file, the 2-second results-wait
--           is a guess, and it's unverified whether BazaarSearchWnd can
--           even be open at the same time as active trader mode. Expect a
--           debugging round here the same way pricing needed one.
-- v0.1.9 - Added M.getSelectedSlot() - returns (row, itemName) for
--          whichever slot is currently selected in BazaarWnd, or (nil, nil)
--          if nothing's selected. Read-only, uses the same confirmed
--          slot.InvSlot.Selected() / slot.InvSlot.Item chain as
--          scanTraderSlots(). Lets frogspy_ui.lua auto-fill the Item Name
--          field from whatever's clicked on in-game instead of requiring
--          it to be typed manually every time.
-- v0.1.8 - ROOT CAUSE FOUND for the phantom-commit bug (confirmed against
--          MacroQuest's own docs, not just live probing again): /keypress
--          simulates KEYBIND presses or direct chat-window input - it was
--          NEVER a generic "type this character into whatever's focused"
--          mechanism. That's exactly why v0.1.7's trace showed the
--          QTYW_SliderInput editbox never changing at all, not even after
--          backspace: /notify ... leftmouseup on an editbox doesn't grant
--          real text-input focus, so every digit and backspace was going
--          nowhere. Replaced the entire focus+backspace+digit-keypress
--          dance with the officially documented way to drive this exact
--          window: `/notify QuantityWnd QTYW_slider newvalue #` sets the
--          slider (and its paired text display) directly. This also
--          retroactively explains why the original v0.1.0 "settext"
--          attempt on QTYW_SliderInput was rejected - editbox text-entry
--          notifications may simply not be how this particular slider+
--          editbox pair is meant to be driven at all; newvalue targets the
--          slider control itself, not the display box.
--          OPEN QUESTION for next live test: QTYW_Slider's Min/Max range is
--          unknown - if it's calibrated for typical item-stack-splitting
--          quantities (e.g. capped around 100-1000) rather than arbitrary
--          price entry, a newvalue call for a large platinum amount (prices
--          up to 100000p+ exist in this bazaar) could get silently clamped
--          to the slider's max. Worth testing with both a small amount
--          (like this 1001pp case) and a large one before trusting this for
--          your priciest items.
-- v0.1.7 - The v0.1.6 inter-keystroke delay did NOT fix it: two separate
--          fresh runs (new PID each time, confirming v0.1.6 was genuinely
--          loaded) both still landed "1001" as "1000" - same digit, same
--          way, every time. That rules out a timing fluke; something else
--          is dropping (or never sending) the trailing keystroke. Added
--          much finer-grained diagnostics to isolate it: log the editbox
--          text right after backspacing (before any digit is typed, in
--          case clearing itself is incomplete), AND after EVERY individual
--          keystroke (not just once at the end) - so the next live run
--          shows exactly which digit fails to register instead of just the
--          wrong final total. Also: recordResult() now accepts an optional
--          reason string, so a verification-mismatch failure (0 retries
--          involved) no longer misleadingly prints "FAILED after 3
--          attempts" - that message is reserved for actual retry
--          exhaustion now.
-- v0.1.6 - Live test with v0.1.5's diagnostics caught the actual bug:
--          requested 1001 platinum, but "ENTER_QTY: editbox text before
--          Accept (denom=plat, wanted=1001) = 1000" - the trailing digit of
--          a multi-digit amount was getting dropped. Cause: the digit-typing
--          loop fired all /keypress calls back-to-back with zero delay
--          between them (only a pause after the whole loop finished) - not
--          enough time for each keystroke to register before the next one
--          fired. Fixed by adding a 30ms delay between each digit. Also:
--          InvSlot.Selected was confirmed true both after SELECT_ITEM and
--          right before COMMIT, so selection loss (the other live
--          hypothesis) is ruled out - it was purely the dropped keystroke.
--          Separately, SETTLE_COMMIT previously just assumed success after
--          a delay (see old "unverified #4") - it silently reported "OK"
--          even with the wrong price committed, since it never checked. Now
--          reads back the actual coin fields via coinFieldsTotal() and
--          compares against current.newPrice, so a future partial failure
--          (dropped keystroke or otherwise) is reported as a failure with
--          the expected-vs-actual delta, not a false OK.
-- v0.1.5 - DIAGNOSTIC ONLY, no behavior change: live test after v0.1.4
--          reported "row 9 -> 50cp OK" but the real in-game price never
--          moved off 1000pp - the same phantom-commit shape as the original
--          settext bug, just surviving the keypress-based fix. Two live
--          hypotheses, both untested: (a) the digit-by-digit /keypress
--          sequence isn't actually landing in QTYW_SliderInput (a focus
--          issue), or (b) it lands fine, but the trader-slot selection gets
--          lost somewhere across the four QuantityWnd round-trips, so
--          BZW_SetPrice_Button has nothing selected to apply to by COMMIT
--          time. Added non-behavioral log lines to distinguish them: the
--          quantity editbox's Text() right before each Accept click, the
--          selected item's row/InvSlot.Selected() right after SELECT_ITEM
--          settles AND again right before COMMIT, and all four BZW_MoneyN
--          Text() values right before COMMIT and right after SETTLE_COMMIT.
--          Next real test's console output should show exactly where this
--          breaks.
-- v0.1.4 - ROOT CAUSE FOUND (confirmed against MacroQuest's own docs, not
--          just live probing): the `window` datatype has NO `.Item` member
--          at all, ever - that was never a valid access path, regardless of
--          trader-mode state. An InvSlot-type window exposes its item
--          through an intermediate `.InvSlot` member (an `invslotwindow`
--          datatype), and IT has `.Item`. So the whole `slot.Item()` /
--          `slot.Item.Name()` pattern from v0.1.0 was wrong from the start -
--          not a trader-mode precondition issue, not an ImGui-frame timing
--          issue, just the wrong accessor chain. scanTraderSlots() now uses
--          `slot.InvSlot.Item()` / `slot.InvSlot.Item.Name()`. This
--          supersedes the v0.1.3 defensive-guard-only fix (which stopped the
--          crash but still couldn't find any items, since slot.Item is
--          always nil).
-- v0.1.3 - scanTraderSlots() crashed with "attempt to call field 'Item' (a
--          nil value)" at the `slot.Item()` call - w.Child('BZR_BazaarSlot0')
--          can return a generic window wrapper (Item not a callable member)
--          instead of a real InvSlot, at least when BazaarWnd is open but
--          the client isn't actually in seller/Trader mode yet. Root cause
--          NOT yet confirmed live (see frogspy_slot_scan.lua diagnostic run
--          in the handoff notes) - this is the defensive fix regardless of
--          cause: guard as `slot.Item and slot.Item()` so a missing member
--          fails soft (slot just doesn't match, loop continues) instead of
--          crashing mid-ImGui-frame. Every crash-in-frame so far has cost an
--          overlay pause + manual /mqoverlay resume, so this alone is worth
--          having even before the root cause is nailed down.
-- v0.1.2 - frogspy_ui.lua was reading fsm.state and #fsm.queue directly,
--          but those are module-locals, never fields on the returned M
--          table - both were always nil from outside. This crashed
--          renderGUI() on the very first frame (TextColored got a nil
--          string, then #fsm.queue on nil), which left ImGui's Begin/End
--          unbalanced and forced an overlay pause. "Force FSM Reset" had
--          the identical bug: fsm.state = 'IDLE' / fsm.queue = {} just
--          created throwaway fields on M and never reset the real state.
--          Added M.getState() and M.reset() as the correct entry points;
--          frogspy_ui.lua updated to use them.
-- v0.1.1 - CONFIRMED LIVE: 'settext' on QTYW_SliderInput is rejected by this
--          client - every denomination click threw "Invalid notification
--          'settext'" in the MQ console (4x per item). Because ENTER_QTY
--          never checked for that error, the FSM proceeded to click Accept
--          and Set Price anyway, silently committing whatever value was
--          already sitting in the coin fields (phantom commit - reported
--          success, item price unchanged). ENTER_QTY now drives the
--          editbox via focus + backspace + /keypress digit-by-digit instead
--          of settext. This resolves "unverified #2" below - settext was
--          the wrong approach for this field on this client, despite being
--          a real Editbox.
-- v0.1.0 - Rewritten from the original trader_fsm_snippet.lua draft against
--          the actual client files on disk:
--            C:\Games\Project_Lazarus\Project_Lazarus\uifiles\default\EQUI_BazaarWnd.xml
--            C:\Games\Project_Lazarus\Project_Lazarus\uifiles\default\EQUI_QuantityWnd.xml
--
--          CONFIRMED FROM XML (not guessed):
--            - BZR_BazaarSlot0..199 are <InvSlot> controls, not plain buttons.
--            - BZW_Money0-3 are plain <Button>s using BDT_PlatinumCoin/
--              BDT_GoldCoin/etc. draw templates. Those templates are purely
--              cosmetic (ButtonDrawTemplate) - nothing in the XML wires them
--              to a popup, so the popup is hardcoded client-side behavior.
--            - EQUI_QuantityWnd.xml defines window "QuantityWnd" with a
--              QTYW_Slider, a QTYW_SliderInput <Editbox> (real edit box, so
--              settext is the correct, supported way to drive it), and a
--              QTYW_Accept_Button. No cancel button exists in the XML.
--            - BZW_SetPrice_Button's tooltip confirms two things: there IS a
--              "currently selected item" concept, and the client writes the
--              price to an INI file as a side effect of clicking it.
--            - EQUI_BazaarConfirmationWnd.xml (BZC_ prefix) is the BUYER
--              purchase-confirmation dialog, unrelated to seller pricing -
--              ruled out as a candidate popup.
--          Also fixed a bug in the original draft: setState() reset
--          `attempts` on every call, including retries, so MAX_ATTEMPTS could
--          never actually trip. Reset is now explicit (see setState below).
--
-- STILL UNVERIFIED - confirm these live before trusting a full run:
--   1. RESOLVED (implicitly) in v0.1.5/v0.1.6 live testing: QuantityWnd
--      reliably opened every time coin buttons were clicked across a full
--      4-denom cycle, so the popup-doesn't-spawn concern is no longer live.
--   2. RESOLVED in v0.1.6: doesn't matter which one Accept reads from
--      anymore - SETTLE_COMMIT now verifies the actual committed coin
--      fields via coinFieldsTotal() against current.newPrice, so whichever
--      internal mechanism Accept uses, a mismatch gets caught either way.
--   3. Whether BZW_Money0-3 retain the PREVIOUS item's values when you select
--      a new slot. This script assumes NO carryover and always sets all 4
--      fields (even to 0) for every item so it's correct either way. If you
--      confirm the fields reset automatically on selection, flip
--      SKIP_ZERO_DENOMS to true to cut clicks.
--   4. RESOLVED in v0.1.6: never did find the INI filename, but didn't need
--      it - SETTLE_COMMIT now verifies success by reading back BZW_Money0-3
--      directly instead of needing a file-based source of truth.
--   5. RESOLVED in v0.1.4: scanTraderSlots() needed slot.InvSlot.Item, not
--      slot.Item - confirmed against MacroQuest's own datatype docs. Not a
--      trader-mode issue after all. Still worth a live pass with an actual
--      populated trader satchel to confirm names resolve correctly end to
--      end (see frogspy_slot_scan.lua).
--
-- Run one item with VERBOSE=true and watch chat before turning this loose on
-- a full trader pass.

local mq = require('mq')

local VERBOSE           = true
local SKIP_ZERO_DENOMS  = false  -- see unverified #3 above - leave false until confirmed safe
local MAX_ATTEMPTS      = 3

-- ============================================================
-- CONFIG - confirmed against EQUI_BazaarWnd.xml / EQUI_QuantityWnd.xml
-- ============================================================
local WND = {
    window       = 'BazaarWnd',
    slotPrefix   = 'BZR_BazaarSlot',     -- InvSlot, + 0..199
    moneyPlat    = 'BZW_Money0',
    moneyGold    = 'BZW_Money1',
    moneySilver  = 'BZW_Money2',
    moneyCopper  = 'BZW_Money3',
    setPriceBtn  = 'BZW_SetPrice_Button',
    clearBtn     = 'BZW_Clear_Button',
}

local QTY = {
    window = 'QuantityWnd',
    slider = 'QTYW_Slider',         -- v0.1.8: drive this directly via
                                     -- /notify ... newvalue # instead of
                                     -- focus+keypress into the editbox
    input  = 'QTYW_SliderInput',    -- real Editbox, kept only to read back
                                     -- Text() for verification logging
    accept = 'QTYW_Accept_Button',
}

-- v0.1.10: confirmed against the actual client file
-- EQUI_BazaarSearchWnd.xml. This is a DIFFERENT window from BazaarWnd (the
-- buyer-side "search all sellers" interface, not your own trader satchel).
-- BZR_ItemList columns (1-indexed, confirmed from the XML's <Seg> headers):
--   1=Item Name, 2=Qty, 3=Plat, 4=Gold, 5=Silver, 6=Copper, 7=Trader
-- UNTESTED end-to-end - built from documentation/XML, not yet verified live.
local SEARCH = {
    window  = 'BazaarSearchWnd',
    nameBox = 'BZR_ItemNameInput',
    findBtn = 'BZR_QueryButton',
    results = 'BZR_ItemList',
}

-- ============================================================
-- Split a total copper value into plat/gold/silver/copper
-- ============================================================
local function splitCoins(totalCopper)
    local plat   = math.floor(totalCopper / 1000)
    local rem    = totalCopper % 1000
    local gold   = math.floor(rem / 100)
    rem          = rem % 100
    local silver = math.floor(rem / 10)
    local copper = rem % 10
    return plat, gold, silver, copper
end

-- ============================================================
-- FSM STATE
-- ============================================================
local state      = 'IDLE'
local state_ts   = 0
local queue      = {}    -- { {row=3, newPrice=1500}, {row=7, newPrice=200}, ... }
local current    = nil
local attempts   = 0
local denoms     = {}    -- built per-item: { {btn=, amount=, label=}, ... }
local denomIndex = 1
local results    = {}    -- { {row=, newPrice=, ok=}, ... } for post-run review

-- v0.1.10: state for the "find lowest bazaar price" flow - shares the same
-- FSM state variable as pricing (only one operation runs at a time, which
-- is intentional - avoids interleaving BazaarWnd and BazaarSearchWnd
-- interactions).
local searchItemName = nil
local searchResult   = nil   -- lowest price found, in copper, or nil
local searchDone     = false -- true once a search has finished (found or not)

-- v0.1.18: state for the FrogTracker.biz median/lowest price lookup
-- (Feature 2). Separate from the searchItemName/searchResult/searchDone
-- trio above (that's for the in-game BazaarSearchWnd flow) - this is an
-- external HTTP call, not a BazaarWnd interaction, but still shares the
-- same top-level FSM `state` var so only one operation runs at a time.
local ftItemName = nil
local ftResult   = nil   -- table of frogtracker.biz fields, or nil
local ftDone     = false -- true once the HTTP request has finished (ok or not)

-- v0.1.19: Batch Audit - scans every occupied trader slot against
-- frogtracker.biz and classifies each as cheapest/undercut/no-competition,
-- mirroring frogspy.py's analyze_item()/STATUS_* logic exactly (see
-- CHANGELOG for the port notes - a real JSON decoder turned out to be
-- unnecessary; see extractActiveListings() below).
local BATCH_STATUS_NONE     = 'none'
local BATCH_STATUS_CHEAPEST = 'cheapest'
local BATCH_STATUS_UNDERCUT = 'undercut'
local BATCH_STATUS_MARKET   = 'market'  -- v0.2.0: item not on the trader - informational only

-- Your trader character's name, used to exclude your own listing from
-- rival prices when computing competitor_prices() - change this if you
-- ever list under a different trader.
local TRADER_NAME = 'Kreigar'

-- Pause between items while scanning, mirrors frogspy.py's --delay 0.3
-- default (be a reasonable citizen toward frogtracker.biz on a full-
-- inventory scan, not just a single click).
local BATCH_DELAY_MS = 300

local batchQueue   = {}    -- { {row=, name=}, ... } - every occupied slot, in scan order (duplicate item names across slots are kept as separate entries - a plain name->slot lookup would silently collapse those)
local batchIndex   = 0     -- 1-based index into batchQueue of the item currently being processed
local batchResults = {}    -- { {row=, name=, yourPrice=, status=, lowest=, gap=, rivals=, low7=, med7=}, ... }
local batchRunning = false
local batchDone    = false
-- v0.1.21: per-scan cache of frogtracker.biz lookups, keyed by lowercased
-- item name - { [name] = { rivals=, low7=, med7=, low30=, med30= } or
-- { error=true } }. Cleared at the start of every scan (M.startBatchScan())
-- and on M.reset() - never reused across separate scans.
local ftCache = {}

-- v0.2.0: which frogtracker.biz time windows to fetch/display, toggled
-- from the UI. Standing preference, not per-scan state - M.reset()
-- deliberately leaves this untouched.
local windowConfig = {
    sevenDay  = true,
    thirtyDay = true,
    ninetyDay = true,
    oneYear   = true,
    lifetime  = true,
}

local function now()       return mq.gettime() end
local function elapsed(ms) return (now() - state_ts) >= ms end

-- resetAttempts defaults to false: only pass true at a genuine new-attempt
-- boundary (new item, new denomination) - NOT on every retry, or
-- MAX_ATTEMPTS never trips. This is the fix for the bug in the original draft.
local function setState(s, resetAttempts)
    state = s
    state_ts = now()
    if resetAttempts then attempts = 0 end
end

local function log(msg)
    if VERBOSE then printf('[FrogSpy] ' .. msg) end
end

local function warn(msg)
    print('\ar[FrogSpy] ' .. msg .. '\ax')
end

-- v0.1.18: FrogTracker.biz helpers - lifted verbatim from
-- frogspy_frogtracker_test.lua v0.2.0 (confirmed working live against a
-- real item, zero errors, zero new package installs). Kept as plain
-- string-pattern extraction rather than a JSON library - see that file's
-- v0.2.0 changelog for why (a dkjson install attempt correlated with a
-- client crash; never retried).
local function urlEncode(str)
    return (str:gsub('([^%w%-%.%_%~])', function(c)
        return string.format('%%%02X', string.byte(c))
    end))
end

local function extractString(body, fieldName)
    return body:match('"' .. fieldName .. '":"(.-)"')
end

-- Returns (value, wasNull). value is nil if either the field held JSON
-- null or the field wasn't found at all - wasNull distinguishes the two.
local function extractNumberOrNull(body, fieldName)
    local numMatch = body:match('"' .. fieldName .. '":%s*(%-?%d+%.?%d*)')
    if numMatch then
        return tonumber(numMatch), false
    end
    if body:match('"' .. fieldName .. '":%s*null') then
        return nil, true
    end
    return nil, false
end

-- v0.2.0: pulls whichever windows are enabled in windowConfig for
-- BATCH_REQUEST. Disabled windows stay nil (renders as "-" in the UI).
local function extractWindowFields(body)
    local out = {}
    if windowConfig.sevenDay then
        out.low7 = extractNumberOrNull(body, 'sevenDayLowestPrice')
        out.med7 = extractNumberOrNull(body, 'sevenDayMedianPrice')
    end
    if windowConfig.thirtyDay then
        out.low30 = extractNumberOrNull(body, 'thirtyDayLowestPrice')
        out.med30 = extractNumberOrNull(body, 'thirtyDayMedianPrice')
    end
    if windowConfig.ninetyDay then
        out.low90 = extractNumberOrNull(body, 'ninetyDayLowestPrice')
        out.med90 = extractNumberOrNull(body, 'ninetyDayMedianPrice')
    end
    if windowConfig.oneYear then
        out.low1y = extractNumberOrNull(body, 'oneYearLowestPrice')
        out.med1y = extractNumberOrNull(body, 'oneYearMedianPrice')
    end
    if windowConfig.lifetime then
        out.lowLife = extractNumberOrNull(body, 'lifetimeLowestPrice')
        out.medLife = extractNumberOrNull(body, 'lifetimeMedianPrice')
    end
    return out
end

-- v0.1.19: Batch Audit helpers. frogtracker.biz's `history[]` array holds
-- every auction record ever scraped for an item (confirmed live 2026-07-10:
-- 6151 entries for one item), but a batch audit only needs the handful
-- that are currently active (`isForSaleNow:true`). A full JSON decode of
-- the whole array to filter down to ~6 entries would waste real per-tick
-- blocking time across a 100+ item inventory, and every entry is a flat,
-- non-nested object with a CONFIRMED CONSISTENT field order
-- (auctionDate, price, sellerName, isForSaleNow - verified across all
-- 6151 entries in the sample, price always a plain integer), so a single
-- targeted pattern captures exactly what's needed with no general-purpose
-- JSON parser at all. If frogtracker.biz ever changes field order or
-- nesting this will need revisiting - it is deliberately narrow, not a
-- general JSON extractor.
local function extractActiveListings(body)
    local listings = {}
    for price, seller in body:gmatch('"auctionDate":"[^"]*","price":(%-?%d+%.?%d*),"sellerName":"([^"]*)","isForSaleNow":true') do
        table.insert(listings, { price = tonumber(price), sellerName = seller })
    end
    return listings
end

-- Active listings excluding your own trader, sorted ascending - mirrors
-- frogspy.py's HistoryResult.competitor_prices().
local function competitorPrices(listings, traderName)
    local prices = {}
    for _, l in ipairs(listings) do
        if l.sellerName ~= traderName then
            table.insert(prices, l.price)
        end
    end
    table.sort(prices)
    return prices
end

local function windowReady()
    local w = mq.TLO.Window(WND.window)
    return w.Open() and w.Child(WND.clearBtn).Open()
end

local function qtyOpen()
    return mq.TLO.Window(QTY.window).Open()
end

-- v0.1.5 diagnostics - read-only, no side effects. Lets us see what the
-- client actually shows at each step instead of assuming success from
-- elapsed time.
local function getSlotWindow(row)
    return mq.TLO.Window(WND.window).Child(WND.slotPrefix .. row)
end

local function logSelection(label)
    local sw = getSlotWindow(current.row)
    if sw and sw.InvSlot then
        log(string.format('%s: row %d InvSlot.Selected=%s',
            label, current.row, tostring(sw.InvSlot.Selected())))
    else
        log(string.format('%s: row %d - could not re-resolve slot window',
            label, current.row))
    end
end

local function logCoinFields(label)
    local w = mq.TLO.Window(WND.window)
    log(string.format('%s: plat=%s gold=%s silver=%s copper=%s',
        label,
        tostring(w.Child(WND.moneyPlat).Text()),
        tostring(w.Child(WND.moneyGold).Text()),
        tostring(w.Child(WND.moneySilver).Text()),
        tostring(w.Child(WND.moneyCopper).Text())))
end

-- v0.1.6: reconstructs the total copper value actually showing in the coin
-- fields, so we can verify against current.newPrice instead of just
-- trusting that the click sequence worked. Blank/non-numeric field text
-- (e.g. an untouched zero-value field, per the v0.1.5 gold/silver/copper
-- logs) is treated as 0.
local function coinFieldsTotal()
    local w = mq.TLO.Window(WND.window)
    local function num(txt)
        return tonumber(txt) or 0
    end
    local plat   = num(w.Child(WND.moneyPlat).Text())
    local gold   = num(w.Child(WND.moneyGold).Text())
    local silver = num(w.Child(WND.moneySilver).Text())
    local copper = num(w.Child(WND.moneyCopper).Text())
    return (plat * 1000) + (gold * 100) + (silver * 10) + copper
end

local function buildDenoms(newPrice)
    local plat, gold, silver, copper = splitCoins(newPrice)
    local list = {
        { btn = WND.moneyPlat,   amount = plat,   label = 'plat'   },
        { btn = WND.moneyGold,   amount = gold,   label = 'gold'   },
        { btn = WND.moneySilver, amount = silver, label = 'silver' },
        { btn = WND.moneyCopper, amount = copper, label = 'copper' },
    }
    if SKIP_ZERO_DENOMS then
        local filtered = {}
        for _, d in ipairs(list) do
            if d.amount > 0 then table.insert(filtered, d) end
        end
        -- Always touch at least one field, so a pure-zero price (i.e. a
        -- clear) still runs the click sequence once.
        if #filtered == 0 then filtered = { list[1] } end
        list = filtered
    end
    return list
end

local function recordResult(ok, reason)
    table.insert(results, { row = current.row, newPrice = current.newPrice, ok = ok })
    if ok then
        log(string.format('row %d -> %dcp OK', current.row, current.newPrice))
    elseif reason then
        -- v0.1.7: distinct from the attempts-exhausted case below - e.g. a
        -- verification mismatch fails on the first and only check, so
        -- "FAILED after N attempts" was misleading there.
        warn(string.format('row %d FAILED - %s', current.row, reason))
    else
        warn(string.format('row %d FAILED after %d attempts', current.row, MAX_ATTEMPTS))
    end
end

-- ============================================================
-- Slot scanner - maps item name -> physical trader slot (0..199).
-- Needed because MQ2Bzsrch's Bazaar TLO (used by frogspy.lua's export) only
-- gives you Name/Price from search results, not the seller's own slot index.
-- Uses the Window TLO's InvSlot -> Item chain directly on BazaarWnd.
-- ============================================================
local function scanTraderSlots()
    local lookup = {}
    local w = mq.TLO.Window(WND.window)
    if not w.Open() then
        warn('scanTraderSlots: BazaarWnd is not open')
        return lookup
    end
    for i = 0, 199 do
        local slot = w.Child(WND.slotPrefix .. i)
        -- v0.1.4: the window datatype has no .Item member - InvSlot-type
        -- windows expose their item via the intermediate .InvSlot member
        -- (invslotwindow datatype), which is what actually has .Item. Also
        -- kept the truthy guards so an unexpected nil anywhere in the chain
        -- (e.g. slot itself) still fails soft instead of crashing the frame.
        if slot and slot.InvSlot and slot.InvSlot.Item and slot.InvSlot.Item() then
            local nm = slot.InvSlot.Item.Name()
            if nm then lookup[nm:lower()] = i end
        end
    end
    return lookup
end

-- v0.1.19: ordered variant for Batch Audit - scanTraderSlots() above keys
-- by lowercased name, which silently collapses duplicate item names across
-- different slots (e.g. two stacks of the same spell in two slots). A
-- full-inventory audit needs to visit every occupied slot individually.
local function scanOccupiedSlotsList()
    local list = {}
    local w = mq.TLO.Window(WND.window)
    if not w.Open() then
        warn('scanOccupiedSlotsList: BazaarWnd is not open')
        return list
    end
    for i = 0, 199 do
        local slot = w.Child(WND.slotPrefix .. i)
        if slot and slot.InvSlot and slot.InvSlot.Item and slot.InvSlot.Item() then
            local nm = slot.InvSlot.Item.Name()
            if nm then table.insert(list, { row = i, name = nm }) end
        end
    end
    return list
end

-- ============================================================
-- MAIN FSM TICK (call once per mainLoop iteration - non-blocking)
-- ============================================================
local function tickFSM()

    if state == 'IDLE' then
        if #queue > 0 and windowReady() then
            current    = table.remove(queue, 1)
            denoms     = buildDenoms(current.newPrice)
            denomIndex = 1
            setState('SELECT_ITEM', true)
        end

    -- --------------------------------------------------------
    -- Select the trader slot (InvSlot, not a listbox row)
    -- --------------------------------------------------------
    elseif state == 'SELECT_ITEM' then
        mq.cmdf('/notify %s %s%d leftmouseup', WND.window, WND.slotPrefix, current.row)
        setState('SETTLE_SELECTION')

    elseif state == 'SETTLE_SELECTION' then
        -- No reliable "Selected()" TLO member for InvSlot controls, so give
        -- the client a beat to register the click before driving the coin
        -- buttons.
        if elapsed(250) then
            logSelection('after SELECT_ITEM settles')  -- v0.1.5 diagnostic
            setState('CLICK_COIN', true)
        end

    -- --------------------------------------------------------
    -- Per-denomination: click coin button -> wait for QuantityWnd ->
    -- type amount -> Accept -> wait for QuantityWnd to close -> next denom
    -- --------------------------------------------------------
    elseif state == 'CLICK_COIN' then
        local d = denoms[denomIndex]
        mq.cmdf('/notify %s %s leftmouseup', WND.window, d.btn)
        setState('WAIT_QTY_OPEN')

    elseif state == 'WAIT_QTY_OPEN' then
        if qtyOpen() then
            setState('ENTER_QTY', true)
        elseif elapsed(500) then
            attempts = attempts + 1
            if attempts >= MAX_ATTEMPTS then
                warn(string.format(
                    'QuantityWnd never opened for %s (row %d). Coin buttons may not spawn a ' ..
                    'popup after all - see "unverified #1" in the header.',
                    denoms[denomIndex].label, current.row))
                recordResult(false)
                setState('IDLE', true)
            else
                setState('CLICK_COIN')  -- retry same denom, keep attempts count
            end
        end

    elseif state == 'ENTER_QTY' then
        -- v0.1.8: replaced the whole focus+backspace+digit-keypress dance.
        -- Root cause of the v0.1.6/v0.1.7 failures: /keypress simulates
        -- KEYBIND presses or direct chat-window input (confirmed against
        -- MacroQuest's own /keypress docs) - it was never a generic "type
        -- this character into whatever's focused" mechanism. That's exactly
        -- why v0.1.7's trace showed the editbox never changing, not even
        -- after backspace: /notify ... leftmouseup on the editbox doesn't
        -- grant it real text-input focus, so every digit (and the
        -- backspaces) were going nowhere. MacroQuest's own /notify
        -- reference documents the actual supported way to drive this exact
        -- window: `/notify QuantityWnd QTYW_slider newvalue #` sets the
        -- slider (and its paired text display) directly - no focus, no
        -- keypresses, no backspacing needed.
        mq.cmdf('/notify %s %s newvalue %d', QTY.window, QTY.slider, denoms[denomIndex].amount)
        mq.delay(50)

        log(string.format('ENTER_QTY: editbox text after newvalue (denom=%s, wanted=%d) = "%s"',
            denoms[denomIndex].label, denoms[denomIndex].amount,
            tostring(mq.TLO.Window(QTY.window).Child(QTY.input).Text())))

        -- Click Accept
        mq.cmdf('/notify %s %s leftmouseup', QTY.window, QTY.accept)
        setState('WAIT_QTY_CLOSE')

    elseif state == 'WAIT_QTY_CLOSE' then
        if not qtyOpen() then
            if denomIndex >= #denoms then
                setState('COMMIT', true)
            else
                denomIndex = denomIndex + 1
                setState('CLICK_COIN', true)
            end
        elseif elapsed(500) then
            attempts = attempts + 1
            if attempts >= MAX_ATTEMPTS then
                warn(string.format(
                    'QuantityWnd would not close for %s (row %d). Accept may need a different ' ..
                    'notify, or the typed keystrokes did not register in the editbox.',
                    denoms[denomIndex].label, current.row))
                recordResult(false)
                setState('IDLE', true)
            else
                -- Popup's already open, so retry Accept rather than re-clicking the coin button.
                mq.cmdf('/notify %s %s leftmouseup', QTY.window, QTY.accept)
            end
        end

    -- --------------------------------------------------------
    -- Commit the price for this item
    -- --------------------------------------------------------
    elseif state == 'COMMIT' then
        logSelection('before COMMIT')   -- v0.1.5 diagnostic
        logCoinFields('before COMMIT')  -- v0.1.5 diagnostic
        mq.cmdf('/notify %s %s leftmouseup', WND.window, WND.setPriceBtn)
        setState('SETTLE_COMMIT')

    elseif state == 'SETTLE_COMMIT' then
        -- v0.1.6: was previously "assume success after a settle delay" -
        -- now actually reads back the coin fields and compares against
        -- current.newPrice, so a dropped keystroke (or any other partial
        -- failure) shows up as a reported failure instead of a false OK.
        if elapsed(300) then
            logCoinFields('after SETTLE_COMMIT')  -- v0.1.5 diagnostic
            local actualTotal = coinFieldsTotal()
            if actualTotal == current.newPrice then
                recordResult(true)
            else
                warn(string.format(
                    'row %d: coin fields show %dcp after commit, wanted %dcp (off by %d) - ' ..
                    'likely a dropped keystroke during digit entry.',
                    current.row, actualTotal, current.newPrice, current.newPrice - actualTotal))
                recordResult(false, string.format('price verification mismatch (wanted %dcp, got %dcp)',
                    current.newPrice, actualTotal))
            end
            setState('IDLE', true)
        end

    -- --------------------------------------------------------
    -- v0.1.10/v0.1.11/v0.1.12: "find lowest bazaar price" flow - separate
    -- from the pricing flow above, uses BazaarSearchWnd instead of
    -- BazaarWnd.
    -- --------------------------------------------------------
    elseif state == 'FIND_PRICE_OPEN_SEARCH' then
        -- v0.1.12 diagnostic: the requestLowestPrice() nil-guard didn't
        -- stop a second identical crash, so log searchItemName at every
        -- state entry this time instead of guessing again.
        log(string.format('FIND_PRICE_OPEN_SEARCH: searchItemName=%s', tostring(searchItemName)))
        local w = mq.TLO.Window(SEARCH.window)
        if w.Open() then
            setState('FIND_PRICE_ENTER_NAME', true)
        else
            mq.cmd('/bazaar')
            setState('FIND_PRICE_WAIT_OPEN', true)
        end

    elseif state == 'FIND_PRICE_WAIT_OPEN' then
        if mq.TLO.Window(SEARCH.window).Open() then
            log(string.format('FIND_PRICE_WAIT_OPEN done: searchItemName=%s', tostring(searchItemName)))
            setState('FIND_PRICE_ENTER_NAME', true)
        elseif elapsed(3000) then
            warn('BazaarSearchWnd did not open after /bazaar - are you near a bazaar broker?')
            searchResult = nil
            searchDone = true
            setState('IDLE', true)
        end

    elseif state == 'FIND_PRICE_ENTER_NAME' then
        log(string.format('FIND_PRICE_ENTER_NAME: searchItemName=%s', tostring(searchItemName)))
        local w = mq.TLO.Window(SEARCH.window)
        local nameBox = w.Child(SEARCH.nameBox)
        if nameBox and nameBox.SetText then
            nameBox.SetText(searchItemName)
            -- v0.1.14 diagnostic: read the box back immediately after
            -- SetText() to settle whether the earlier "he Ravenous Shadow"
            -- (missing leading T) seen in a screenshot was a real dropped
            -- character from SetText(), or just a UI scroll/truncation
            -- artifact from the cursor sitting at the end of a narrow
            -- field. If Text() here comes back missing the leading
            -- character too, SetText() itself is the bug; if it comes back
            -- correct, it was purely a display artifact and the 0-results
            -- bug is entirely in FIND_PRICE_SCAN's count/name-match logic.
            if nameBox.Text then
                local readback = nameBox.Text()
                log(string.format('FIND_PRICE_ENTER_NAME diag: readback after SetText() = "%s" (expected "%s") -> match=%s',
                    tostring(readback), searchItemName, tostring(readback == searchItemName)))
            else
                warn('FIND_PRICE_ENTER_NAME diag: nameBox.Text not available - cannot verify SetText()')
            end
            setState('FIND_PRICE_CLICK_FIND', true)
        else
            warn('findLowestPrice: could not find/set BZR_ItemNameInput')
            searchResult = nil
            searchDone = true
            setState('IDLE', true)
        end

    elseif state == 'FIND_PRICE_CLICK_FIND' then
        log(string.format('FIND_PRICE_CLICK_FIND: searchItemName=%s', tostring(searchItemName)))
        mq.cmdf('/notify %s %s leftmouseup', SEARCH.window, SEARCH.findBtn)
        setState('FIND_PRICE_WAIT', true)

    elseif state == 'FIND_PRICE_WAIT' then
        -- v0.1.10: guessed delay for the search server round-trip -
        -- untested, may need tuning based on what the live console log
        -- shows once this actually runs.
        if elapsed(2000) then
            log(string.format('FIND_PRICE_WAIT done: searchItemName=%s', tostring(searchItemName)))
            setState('FIND_PRICE_SCAN', true)
        end

    elseif state == 'FIND_PRICE_SCAN' then
        log(string.format('FIND_PRICE_SCAN: searchItemName=%s', tostring(searchItemName)))
        -- v0.1.12: defensive guard at the point of use - the entry-point
        -- guard in requestLowestPrice() didn't prevent a second identical
        -- crash here, so fail soft instead of crashing regardless of how
        -- searchItemName ended up nil.
        if not searchItemName then
            warn('FIND_PRICE_SCAN: searchItemName is nil - aborting this search without crashing')
            searchResult = nil
            searchDone = true
            setState('IDLE', true)
            return
        end
        local w = mq.TLO.Window(SEARCH.window)
        local list = w.Child(SEARCH.results)
        local lowest = nil
        if list then
            -- v0.1.14 diagnostic: list.Items() might itself need a second,
            -- empty () to convert from MQ userdata to a real Lua number, the
            -- same way list.List(row,col) did before the v0.1.13 fix. Log
            -- both the raw first call and a pcall'd second call so we can
            -- see directly which one (if either) is a usable number - pcall
            -- guards against a crash if the first call already returned a
            -- plain number (calling a number like a function would error).
            local rawItems = list.Items()
            log(string.format('FIND_PRICE_SCAN diag: list.Items() = %s (lua type=%s)',
                tostring(rawItems), type(rawItems)))
            local ok2, rawItems2 = pcall(function() return rawItems() end)
            if ok2 then
                log(string.format('FIND_PRICE_SCAN diag: list.Items()() = %s (lua type=%s)',
                    tostring(rawItems2), type(rawItems2)))
            else
                log(string.format('FIND_PRICE_SCAN diag: list.Items()() not callable (%s) - first call was already lua type=%s',
                    tostring(rawItems2), type(rawItems)))
            end
            local count = tonumber(rawItems) or (ok2 and tonumber(rawItems2)) or 0
            log(string.format('FIND_PRICE_SCAN diag: using count=%d for the row loop', count))
            local matchName = searchItemName:lower()
            for row = 1, count do
                -- v0.1.13 ROOT CAUSE FIX: list.List(row, col) alone returns
                -- MQ userdata, not a plain Lua string/number - confirmed
                -- against MacroQuest's own docs ("Data returned by MQ is
                -- always of type userdata. Adding () on the end will
                -- convert... to the appropriate lua datatype"). Every
                -- .List() call below needs a SECOND, empty () to actually
                -- evaluate it - that's what nm:lower() was crashing on (nm
                -- was truthy userdata with no .lower method, not nil).
                -- This also means plat/gold/silver/copper below were
                -- silently always 0 before this fix (tonumber(userdata)
                -- just returns nil, falling back to the "or 0" default).
                -- v0.1.16 ROOT CAUSE CONFIRMED (two live tests, two
                -- different items, both 3 rows): col 1 was never the name
                -- column at all. BZR_ItemList has two leading columns
                -- (col0, col1) that return an empty string on every row
                -- for every item tested - almost certainly unlabeled/icon
                -- columns not exposed as text - pushing every real column
                -- one index later than the v0.1.10 XML-based assumption.
                -- Confirmed real layout: col2=Name, col3=Qty, col4=Plat,
                -- col5=Gold, col6=Silver, col7=Copper, col8=Trader (col9
                -- was consistently "TRUE" on every row of both tests -
                -- purpose unknown, not needed for pricing, left alone).
                -- "Kromzek Tower Shield Ornament" test: 3 rows, qty=1 each,
                -- prices 500/1800/3000 plat, traders Giddi/Shalltrader/
                -- Kreigar - all pulled correctly from col2/col4/col8, and
                -- matched the in-game Search Results table exactly.
                local nm = list.List(row, 2)()
                -- v0.1.14/15 diagnostic: log every row's raw name (quoted,
                -- so whitespace is visible) next to the match target.
                log(string.format('FIND_PRICE_SCAN diag: row %d nm="%s" vs matchName="%s" -> match=%s',
                    row, tostring(nm), matchName, tostring(nm ~= nil and nm:lower() == matchName)))
                if not (nm and nm:lower() == matchName) and row <= 5 then
                    -- v0.1.15 full column dump, kept as a fallback: if a
                    -- row still doesn't match after the v0.1.16 column
                    -- fix, dump every column again so any further/different
                    -- layout surprise (e.g. a non-ASCII item name, or a
                    -- different window state) is immediately visible
                    -- instead of just another silent "not found".
                    local colDump = {}
                    for c = 0, 9 do
                        local ok3, v3 = pcall(function() return list.List(row, c)() end)
                        if ok3 then
                            colDump[#colDump + 1] = string.format('col%d="%s"', c, tostring(v3))
                        else
                            colDump[#colDump + 1] = string.format('col%d=ERR(%s)', c, tostring(v3))
                        end
                    end
                    log(string.format('FIND_PRICE_SCAN diag: row %d still no match, full column dump: %s',
                        row, table.concat(colDump, ' ')))
                end
                if nm and nm:lower() == matchName then
                    local plat   = tonumber(list.List(row, 4)()) or 0
                    local gold   = tonumber(list.List(row, 5)()) or 0
                    local silver = tonumber(list.List(row, 6)()) or 0
                    local copper = tonumber(list.List(row, 7)()) or 0
                    local total = (plat * 1000) + (gold * 100) + (silver * 10) + copper
                    if lowest == nil or total < lowest then
                        lowest = total
                    end
                end
            end
        else
            warn('findLowestPrice: could not find BZR_ItemList results')
        end
        searchResult = lowest
        searchDone = true
        if lowest then
            -- v0.1.17: report in platinum, not raw copper - that's how
            -- people actually read bazaar prices in-game, and it's how
            -- frogspy_ui.lua's own PP/GP/SP/CP fields already display the
            -- result. Reuses the same splitCoins() helper the pricing flow
            -- already uses, so this formatting stays consistent with the
            -- rest of the script. Only non-zero denominations are shown,
            -- so a normal round-plat price reads as "495pp" rather than
            -- "495pp 0gp 0sp 0cp".
            local plat, gold, silver, copper = splitCoins(lowest)
            local parts = {}
            if plat   > 0 then table.insert(parts, plat .. 'pp') end
            if gold   > 0 then table.insert(parts, gold .. 'gp') end
            if silver > 0 then table.insert(parts, silver .. 'sp') end
            if copper > 0 then table.insert(parts, copper .. 'cp') end
            if #parts == 0 then parts = { '0pp' } end
            log(string.format('Lowest price for "%s" = %s', searchItemName, table.concat(parts, ' ')))
        else
            warn(string.format('No listings found for "%s"', searchItemName))
        end
        setState('IDLE', true)

    elseif state == 'FT_REQUEST' then
        -- v0.1.18: Feature 2 - FrogTracker.biz median/lowest price lookup.
        -- NOTE: https.request() below is a synchronous/blocking Lua call
        -- with no established async pattern in this MQNext environment
        -- (unlike the FIND_PRICE_* flow above, which spreads its wait
        -- across many quick ticks). This single tick will block for the
        -- full HTTP round-trip - observed ~tens of ms up to ~1s live in
        -- frogspy_frogtracker_test.lua v0.2.0. Acceptable for a deliberate
        -- button click, but worth knowing if this state ever gets called
        -- somewhere latency-sensitive.
        log(string.format('FT_REQUEST: ftItemName=%s', tostring(ftItemName)))
        if not ftItemName or ftItemName == '' then
            warn('FT_REQUEST: no item name given - aborting without crashing')
            ftResult = nil
            ftDone = true
            setState('IDLE', true)
            return
        end

        local pmOk, PackageMan = pcall(require, 'mq/PackageMan')
        local http, https
        if pmOk and PackageMan then
            local httpOk, httpMod = pcall(function() return PackageMan.Require('luasocket', 'socket.http') end)
            if httpOk then http = httpMod end
            local sslOk = pcall(function() return PackageMan.Require('luasec', 'ssl') end)
            if sslOk then
                local httpsOk, httpsMod = pcall(require, 'ssl.https')
                if httpsOk then https = httpsMod end
            end
        end

        if not https then
            warn('FT_REQUEST: could not load ssl.https (PackageMan/luasec) - aborting')
            ftResult = nil
            ftDone = true
            setState('IDLE', true)
            return
        end

        local url = 'https://frogtracker.biz/Home/ItemHistory?itemName=' .. urlEncode(ftItemName)
        local reqOk, body, code = pcall(function() return https.request(url) end)
        if not reqOk or not body then
            warn(string.format('FT_REQUEST: request failed for "%s" - %s', ftItemName, tostring(code or body)))
            ftResult = nil
            ftDone = true
            setState('IDLE', true)
            return
        end

        local itemName = extractString(body, 'itemName')
        if not itemName then
            warn(string.format('FT_REQUEST: no itemName field in response for "%s" - unexpected format', ftItemName))
            ftResult = nil
            ftDone = true
            setState('IDLE', true)
            return
        end

        ftResult = {
            itemName               = itemName,
            sevenDayLowestPrice    = extractNumberOrNull(body, 'sevenDayLowestPrice'),
            sevenDayMedianPrice    = extractNumberOrNull(body, 'sevenDayMedianPrice'),
            thirtyDayLowestPrice   = extractNumberOrNull(body, 'thirtyDayLowestPrice'),
            thirtyDayMedianPrice   = extractNumberOrNull(body, 'thirtyDayMedianPrice'),
            ninetyDayLowestPrice   = extractNumberOrNull(body, 'ninetyDayLowestPrice'),
            ninetyDayMedianPrice   = extractNumberOrNull(body, 'ninetyDayMedianPrice'),
            oneYearLowestPrice     = extractNumberOrNull(body, 'oneYearLowestPrice'),
            oneYearMedianPrice     = extractNumberOrNull(body, 'oneYearMedianPrice'),
            lifetimeLowestPrice    = extractNumberOrNull(body, 'lifetimeLowestPrice'),
            lifetimeMedianPrice    = extractNumberOrNull(body, 'lifetimeMedianPrice'),
        }
        ftDone = true
        log(string.format('FT_REQUEST done: thirtyDayMedianPrice=%s pp for "%s"',
            tostring(ftResult.thirtyDayMedianPrice), itemName))
        setState('IDLE', true)

    -- --------------------------------------------------------
    -- v0.1.19: Batch Audit - one item per pass through
    -- SELECT -> SETTLE -> REQUEST -> DELAY, then loops to the next queued
    -- slot. Mirrors the single-item SELECT_ITEM/SETTLE_SELECTION timing
    -- exactly (250ms settle) for the click, then reuses the same blocking
    -- https.request() pattern as FT_REQUEST per item, with a throttle
    -- gap between items (BATCH_DELAY_MS) since this hits frogtracker.biz
    -- once per occupied slot rather than once per button click.
    -- --------------------------------------------------------
    elseif state == 'BATCH_SELECT' then
        local entry = batchQueue[batchIndex]
        if not entry then
            batchRunning = false
            batchDone = true
            setState('IDLE', true)
            return
        end
        if entry.row then
            mq.cmdf('/notify %s %s%d leftmouseup', WND.window, WND.slotPrefix, entry.row)
            setState('BATCH_SETTLE', true)
        else
            -- v0.2.0: market-only entry, no slot to select.
            setState('BATCH_REQUEST', true)
        end

    elseif state == 'BATCH_SETTLE' then
        if elapsed(250) then
            setState('BATCH_REQUEST', true)
        end

    elseif state == 'BATCH_REQUEST' then
        local entry = batchQueue[batchIndex]
        
        -- v0.2.0: entry.row is nil for a market-only audit (item not
        -- found on the trader - see M.auditSingleItem()). No slot means
        -- no "your price" to read.
        local yourPrice = nil
        if entry.row then
            local w = mq.TLO.Window(WND.window)
            local plat, gold, silver, copper =
                w.Child(WND.moneyPlat), w.Child(WND.moneyGold), w.Child(WND.moneySilver), w.Child(WND.moneyCopper)
            local pNum = (plat and tonumber(plat.Text())) or 0
            local gNum = (gold and tonumber(gold.Text())) or 0
            local sNum = (silver and tonumber(silver.Text())) or 0
            local cNum = (copper and tonumber(copper.Text())) or 0
            yourPrice = pNum + (gNum / 10) + (sNum / 100) + (cNum / 1000)
        end

        local result = { row = entry.row, name = entry.name, yourPrice = yourPrice }

        local cacheKey = entry.name:lower()
        local cached = ftCache[cacheKey]

        -- v0.2.0: shared classification, keyed off whether this entry has
        -- a real trader slot (row) or is a market-only lookup.
        local function classify(rivals)
            if not entry.row then
                result.status = BATCH_STATUS_MARKET
                result.lowest = (#rivals > 0) and rivals[1] or nil
                result.rivals = #rivals
                result.gap = nil
            elseif #rivals == 0 then
                result.status, result.lowest, result.rivals = BATCH_STATUS_NONE, nil, 0
            else
                result.lowest = rivals[1]
                result.rivals = #rivals
                result.status = (yourPrice <= result.lowest) and BATCH_STATUS_CHEAPEST or BATCH_STATUS_UNDERCUT
                result.gap = (result.status == BATCH_STATUS_UNDERCUT) and (yourPrice - result.lowest) or nil
            end
        end

        if cached then
            log(string.format('BATCH_REQUEST %d/%d: "%s" (slot %s) - reusing cached lookup from this scan',
                batchIndex, #batchQueue, entry.name, tostring(entry.row)))
            if cached.error then
                result.status, result.lowest, result.rivals, result.error = BATCH_STATUS_NONE, nil, 0, true
            else
                result.low7, result.med7 = cached.low7, cached.med7
                result.low30, result.med30 = cached.low30, cached.med30
                result.low90, result.med90 = cached.low90, cached.med90
                result.low1y, result.med1y = cached.low1y, cached.med1y
                result.lowLife, result.medLife = cached.lowLife, cached.medLife
                classify(cached.rivals)
            end
            table.insert(batchResults, result)
            setState('BATCH_DELAY', true)
            return
        end

        log(string.format('BATCH_REQUEST %d/%d: "%s" (slot %s)', batchIndex, #batchQueue, entry.name, tostring(entry.row)))

        local pmOk, PackageMan = pcall(require, 'mq/PackageMan')
        local https
        if pmOk and PackageMan then
            local sslOk = pcall(function() return PackageMan.Require('luasec', 'ssl') end)
            if sslOk then
                local httpsOk, httpsMod = pcall(require, 'ssl.https')
                if httpsOk then https = httpsMod end
            end
        end

        if not https then
            warn(string.format('BATCH_REQUEST: could not load ssl.https for "%s" - skipping', entry.name))
            result.status = BATCH_STATUS_NONE
            result.lowest, result.rivals, result.error = nil, 0, true
            ftCache[cacheKey] = { error = true }
        else
            local url = 'https://frogtracker.biz/Home/ItemHistory?itemName=' .. urlEncode(entry.name)
            local reqOk, body = pcall(function() return https.request(url) end)
            if not reqOk or not body then
                warn(string.format('BATCH_REQUEST: request failed for "%s"', entry.name))
                result.status = BATCH_STATUS_NONE
                result.lowest, result.rivals, result.error = nil, 0, true
                ftCache[cacheKey] = { error = true }
            else
                local listings = extractActiveListings(body)
                local rivals = competitorPrices(listings, TRADER_NAME)
                local wf = extractWindowFields(body)
                
                result.low7, result.med7 = wf.low7, wf.med7
                result.low30, result.med30 = wf.low30, wf.med30
                result.low90, result.med90 = wf.low90, wf.med90
                result.low1y, result.med1y = wf.low1y, wf.med1y
                result.lowLife, result.medLife = wf.lowLife, wf.medLife
                
                ftCache[cacheKey] = {
                    rivals = rivals,
                    low7 = result.low7, med7 = result.med7,
                    low30 = result.low30, med30 = result.med30,
                    low90 = result.low90, med90 = result.med90,
                    low1y = result.low1y, med1y = result.med1y,
                    lowLife = result.lowLife, medLife = result.medLife,
                }
                
                classify(rivals)
            end
        end

        table.insert(batchResults, result)
        setState('BATCH_DELAY', true)

    elseif state == 'BATCH_DELAY' then
        if elapsed(BATCH_DELAY_MS) then
            batchIndex = batchIndex + 1
            if batchIndex > #batchQueue then
                batchRunning = false
                batchDone = true
                setState('IDLE', true)
            else
                setState('BATCH_SELECT', true)
            end
        end
    end
end

-- ============================================================
-- Public API
-- ============================================================
local M = {}

-- Queue a price update by physical slot index (0-199).
function M.enqueue(row, newPrice)
    table.insert(queue, { row = row, newPrice = newPrice })
end

-- Queue a price update by item name - scans BazaarWnd's InvSlots to resolve
-- the slot. Re-scans every call, so batch your enqueueByName calls rather
-- than interleaving them with tick() if you're queuing a lot of items.
function M.enqueueByName(itemName, newPrice)
    local lookup = scanTraderSlots()
    local slot = lookup[itemName:lower()]
    if not slot then
        warn(string.format('enqueueByName: "%s" not found in a trader slot, skipping', itemName))
        return false
    end
    table.insert(queue, { row = slot, newPrice = newPrice })
    return true
end

-- Call once per mainLoop iteration.
function M.tick()
    tickFSM()
end

function M.isIdle()
    return state == 'IDLE' and #queue == 0
end

function M.queueLength()
    return #queue
end

function M.getResults()
    return results
end

-- Current FSM state string (e.g. 'IDLE', 'CLICK_COIN', ...). state/queue are
-- module-locals, not fields on M - callers (frogspy_ui.lua) must go through
-- this accessor rather than reading fsm.state directly, which is always nil.
function M.getState()
    return state
end

-- Diagnostic escape hatch: clears the queue and any in-flight item, and
-- returns the FSM to IDLE. Does not touch `results` history. Setting
-- fsm.state/fsm.queue directly (the old approach) only created throwaway
-- fields on M and never affected the real module-local state - this
-- function is the real reset.
function M.reset()
    state      = 'IDLE'
    state_ts   = now()
    queue      = {}
    current    = nil
    attempts   = 0
    denoms     = {}
    denomIndex = 1
    -- v0.1.12: also clear search-flow state - Force FSM Reset previously
    -- left searchItemName/searchDone/searchResult untouched, which could
    -- leave a mid-flight search in an inconsistent state.
    searchItemName = nil
    searchResult   = nil
    searchDone     = false
    -- v0.1.18: also clear the FrogTracker request flow for the same reason.
    ftItemName = nil
    ftResult   = nil
    ftDone     = false
    -- v0.1.19: also clear a mid-flight batch scan for the same reason.
    batchQueue   = {}
    batchIndex   = 0
    batchResults = {}
    batchRunning = false
    batchDone    = false
    -- v0.1.21: also clear the per-scan FrogTracker cache.
    ftCache = {}
end

-- Returns (row, itemName) for whichever trader slot is currently selected
-- in BazaarWnd (the yellow-highlighted slot), or (nil, nil) if nothing's
-- selected or the window isn't open. Read-only, no side effects - safe to
-- poll from the UI's render loop to auto-fill the item name field from
-- whatever the person clicks on in-game.
function M.getSelectedSlot()
    local w = mq.TLO.Window(WND.window)
    if not w.Open() then return nil, nil end
    for i = 0, 199 do
        local slot = w.Child(WND.slotPrefix .. i)
        if slot and slot.InvSlot and slot.InvSlot.Selected and slot.InvSlot.Selected() then
            local nm = nil
            if slot.InvSlot.Item and slot.InvSlot.Item() then
                nm = slot.InvSlot.Item.Name()
            end
            return i, nm
        end
    end
    return nil, nil
end

-- v0.1.10: starts a "find lowest bazaar price" search via BazaarSearchWnd.
-- Returns false immediately (does nothing) if the FSM is busy with a price
-- update. Poll M.isSearchDone() / M.getSearchResult() for the outcome -
-- this is async because it involves a real server round-trip wait.
function M.requestLowestPrice(itemName)
    -- v0.1.12 diagnostic: log exactly what was received, before any guard
    -- runs - the v0.1.11 guard didn't stop a second identical crash, so we
    -- need to see the raw value/type coming in from the caller.
    log(string.format('requestLowestPrice called with itemName=%s (lua type=%s)',
        tostring(itemName), type(itemName)))
    if state ~= 'IDLE' then
        warn('FSM is busy, cannot start a price search right now')
        return false
    end
    -- v0.1.11: defensive guard - a live run crashed with "attempt to call
    -- method 'lower' (a nil value)" at searchItemName:lower(), meaning this
    -- got called with itemName nil at some point. Every traced call site in
    -- frogspy_ui.lua guards against an empty string, but not explicitly
    -- against nil - this closes that off regardless of the exact upstream
    -- cause, rather than trusting the caller blindly.
    if not itemName or itemName == '' then
        warn('requestLowestPrice: no item name given')
        return false
    end
    searchItemName = itemName
    searchResult = nil
    searchDone = false
    setState('FIND_PRICE_OPEN_SEARCH', true)
    return true
end

-- True once the most recently requested search has finished (found a price
-- or not) - check this before calling getSearchResult().
function M.isSearchDone()
    return searchDone
end

-- Lowest price found in copper, or nil if nothing matched (or search
-- hasn't completed yet - check isSearchDone() first).
function M.getSearchResult()
    return searchResult
end

-- v0.1.18: starts a FrogTracker.biz price lookup (Feature 2). Returns false
-- immediately if the FSM is busy. Poll M.isFrogTrackerDone() /
-- M.getFrogTrackerResult() for the outcome - async because it's a real
-- external HTTP round-trip (see the FT_REQUEST comment in tickFSM for the
-- single-tick blocking caveat).
function M.requestFrogTrackerPrice(itemName)
    if state ~= 'IDLE' then
        warn('FSM is busy, cannot start a FrogTracker lookup right now')
        return false
    end
    if not itemName or itemName == '' then
        warn('requestFrogTrackerPrice: no item name given')
        return false
    end
    ftItemName = itemName
    ftResult = nil
    ftDone = false
    setState('FT_REQUEST', true)
    return true
end

-- True once the most recently requested FrogTracker lookup has finished
-- (found a result or not) - check this before calling getFrogTrackerResult().
function M.isFrogTrackerDone()
    return ftDone
end

-- Table of frogtracker.biz fields (itemName, sevenDayLowestPrice,
-- thirtyDayMedianPrice, etc. - all prices in platinum, may be nil per
-- field), or nil if the lookup failed / hasn't completed yet.
function M.getFrogTrackerResult()
    return ftResult
end

-- v0.1.19: starts a full-inventory Batch Audit - scans every occupied
-- trader slot, reads your listed price, checks it against frogtracker.biz's
-- active listings, and classifies each item as cheapest/undercut/no
-- competition. Mirrors frogspy.py's whole-inventory report. Returns false
-- immediately if the FSM is busy or no slots are occupied. This runs for a
-- while (one settle + one HTTP round-trip + one throttle delay per item -
-- expect roughly 1-2 seconds per item, so a 20-item trader is more like
-- 20-40 seconds with intermittent hitches, not instant). Poll
-- M.isBatchScanDone() / M.getBatchScanProgress() / M.getBatchScanResults().
-- Shared by M.startBatchScan() and M.auditSingleItem() - both just build a
-- differently-sized queue and hand it off to the same BATCH_* states.
local function startBatchWithQueue(q, emptyWarning)
    if state ~= 'IDLE' then
        warn('FSM is busy, cannot start an audit right now')
        return false
    end
    if #q == 0 then
        warn(emptyWarning)
        return false
    end
    batchQueue = q
    batchIndex = 1
    batchResults = {}
    batchRunning = true
    batchDone = false
    ftCache = {}  -- v0.1.21: fresh per-scan cache, never reused across scans
    setState('BATCH_SELECT', true)
    return true
end

-- v0.1.22: public entry point for an arbitrary caller-selected queue -
-- both M.startBatchScan() (below) and the UI's new selective-audit
-- checklist go through this. Same validation/setup as the other two.
function M.startBatchAudit(q)
    if not q or #q == 0 then
        warn('startBatchAudit: empty queue given')
        return false
    end
    return startBatchWithQueue(q, 'startBatchAudit: empty queue given')
end

function M.startBatchScan()
    return startBatchWithQueue(scanOccupiedSlotsList(), 'startBatchScan: no occupied trader slots found')
end

-- v0.1.22: exposes the ordered occupied-slot list (row+name) so the UI can
-- render a per-item selection checklist without duplicating the BazaarWnd
-- scan logic. Same underlying scan as startBatchScan() uses internally -
-- a real TLO scan of up to 200 child windows, so the UI should cache the
-- result rather than calling this every render frame.
function M.getOccupiedSlots()
    return scanOccupiedSlotsList()
end

-- v0.2.0: live table (not a copy) - UI only reads it and writes through
-- setWindowEnabled below.
function M.getWindowConfig()
    return windowConfig
end

function M.setWindowEnabled(key, enabled)
    if windowConfig[key] == nil then
        warn(string.format('setWindowEnabled: unknown window key "%s"', tostring(key)))
        return
    end
    windowConfig[key] = enabled
end

-- v0.2.0: falls back to a market-only lookup (row=nil) instead of failing
-- when itemName isn't on the trader - see BATCH_SELECT/BATCH_REQUEST.
function M.auditSingleItem(itemName)
    if not itemName or itemName == '' then
        warn('auditSingleItem: no item name given')
        return false
    end
    local lookup = scanTraderSlots()
    local slot = lookup[itemName:lower()]
    local entry = slot and { row = slot, name = itemName } or { row = nil, name = itemName }
    return startBatchWithQueue({ entry }, 'auditSingleItem: unexpected empty queue')
end

function M.isBatchScanRunning()
    return batchRunning
end

function M.isBatchScanDone()
    return batchDone
end

-- Returns (current, total) 1-based progress through the queue, for a
-- progress bar - current is 0 before the first item starts.
function M.getBatchScanProgress()
    return math.min(batchIndex, #batchQueue), #batchQueue
end

-- Array of { row, name, yourPrice, status, lowest, gap, rivals, low7, med7,
-- error } - status is 'cheapest'/'undercut'/'none', gap is only set for
-- 'undercut'. Grows as the scan progresses - safe to read mid-scan for a
-- live-updating table, not just after isBatchScanDone().
function M.getBatchScanResults()
    return batchResults
end

return M