-- frogspy.lua
-- ImGui control panel / tick-loop driver for frogspy_price_fsm.lua.
-- Version: 0.16.0
-- Author: Alektra <Lederhosen>
--
-- CHANGELOG:
-- v0.16.0 - Four requested UI/UX fixes, no FSM changes:
--           1) Hover tooltips added to every button except Audit Logging
--           (already had one) and Close##competitors (self-evident,
--           no side effects worth documenting). New shared tooltip()
--           helper called right after each button's if/then/end,
--           matching the existing Audit Logging tooltip's placement.
--           2) Auto-Audit Watchlist interval now has synced
--           minutes/hours/days fields instead of minutes-only - all
--           three read/write the same underlying autoAuditIntervalSec;
--           only the field actually edited that frame writes back, so
--           the other two don't stomp it to 0 the same frame.
--           3) "target plat" watchlist input widened from 90 to 140px
--           to fit 7-digit targets without clipping.
--           4) New "Help##ntfy" button next to the ntfy topic field
--           opens a separate pop-up window (own Begin/End) walking
--           through installing the ntfy app, picking a non-guessable
--           topic, subscribing, and wiring the topic into FrogSpy -
--           tracked by new showNtfyHelp local.
-- v0.15.0 - NEW FEATURE: auto-audit timer for the v0.14.0 watchlist,
--           closing the gap that made target-price watches mostly
--           pointless - without this, a watched item's price was only
--           ever checked at the moment you happened to click Batch
--           Audit or Audit This Item, so "notify me when it hits N
--           plat" silently did nothing while away from the panel.
--           New "Auto-Audit Watchlist: ON/OFF" toggle + "check every
--           (min)" interval input below the watchlist. When on,
--           renderGUI() periodically calls fsm.auditSingleItem() on
--           the next watchlist entry (round-robin via
--           autoAuditWatchIdx, one item per interval rather than the
--           whole list at once - keeps this indistinguishable from a
--           human occasionally clicking Audit This Item, and avoids
--           hammering frogtracker.biz as the watchlist grows). Only
--           triggers when the FSM is genuinely idle (reuses the same
--           scanRunningNow read the rest of the frame already takes,
--           never a second fsm.isBatchScanRunning() call, so this
--           can't race a manual audit click in the same frame).
--           Deliberately does NOT add a second alert-evaluation path -
--           it only starts audits; the existing v0.14.0
--           batchWasRunning/scanRunningNow transition hook (which
--           already checks the watchlist after any finished audit,
--           manual or auto-triggered) is what actually fires
--           sendPriceAlert(). Interval stored internally in seconds
--           (autoAuditIntervalSec) but shown/edited in whole minutes
--           in the UI, floored at 1. Off by default; resets to
--           defaults on script reload, same as everything else in
--           this alert system.
-- v0.14.0 - CORRECTION to v0.13.0: that release alerted on undercut GAP
--           (yours vs. lowest rival, only on UNDERCUT rows), but what
--           was actually wanted is a target-price watch - "tell me when
--           this item's market price reaches N plat" - which doesn't
--           require the item to be undercut, or even sitting in a
--           trader slot (MARKET-status rows qualify too, same as
--           CHEAPEST/UNDERCUT, since all three have a real r.lowest).
--           Replaced the single alertThresholdPlat gap field with a
--           watchlist: separate "watch item" name + "target plat"
--           inputs plus an Add Watch button, rendering the current
--           watchlist below with per-entry Remove buttons. Same
--           batch-finish hook point as before (and as writeAuditLog()),
--           but now looks up each watched item by name in
--           groupedResults and fires sendPriceAlert() when
--           r.lowest <= target. watchAlerted[name] gates each watch to
--           firing once per drop-below-target rather than every
--           finished audit while the price stays low, and re-arms
--           (clears) if the price rises back above target. ntfy topic
--           input, alertsEnabled toggle, and sendPriceAlert()'s
--           io.popen/curl.exe transport are otherwise unchanged from
--           v0.13.0.
-- v0.13.0 - NEW FEATURE: optional ntfy.sh push alert on undercut items,
--           closing the "how do I find out I got undercut without the
--           panel open" gap. "Price Alerts: ON/OFF" toggle next to Audit
--           Logging, plus a topic text input (ntfy.sh topic name - public/
--           unauthenticated, pick something non-guessable) and a min-gap
--           number input (plat). Fires on the same batch-finish
--           running->not-running transition as writeAuditLog() (once per
--           finished audit, not per frame), walks groupedResults, and
--           sends one sendPriceAlert() notification per UNDERCUT row
--           whose gap meets/exceeds the threshold - CHEAPEST/MARKET/no-
--           comp./error rows don't qualify. sendPriceAlert() reuses
--           checkForUpdate()'s proven io.popen + curl.exe pattern (same
--           timeout guards, same pcall wrapper) rather than a new HTTP
--           dependency - confirmed working in the MQNext Lua sandbox
--           since that's exactly how the v0.12.0 update check already
--           runs in production. Formats its own numbers inline (%.3f)
--           rather than calling fmtPrice(), since fmtPrice is declared
--           later in the file and isn't in scope yet at sendPriceAlert's
--           declaration point. Off by default; resets to defaults on
--           script reload, same as logAuditsEnabled (no settings-
--           persistence layer exists in this file yet).
-- v0.12.0 - Added auto-update check (same pattern as ItemPass.lua):
--           fetches the raw script from GitHub on load, compares VERSION,
--           and prints a console notice if a newer version is available.
-- v0.11.0 - Fix: added ScrollX so wide results tables (8-18 columns) stop
--           compressing/clipping column text instead of scrolling.
-- v0.10.0 - Reverted SizingStretchSame; back to default auto-fit column
--           sizing (the actual standard), Resizable still on top.
-- v0.9.0  - Added SizingStretchSame so resizing a column takes space from
--           its neighbor instead of just growing the table.
-- v0.8.0  - Columns now resizable. Added a "Competitors" column - View
--           button opens a per-seller auction breakdown sub-table.
-- v0.7.0  - Results table hides columns for disabled time windows instead
--           of showing dead "-" cells.
-- v0.6.0  - Audit This Item now falls back to a market-only lookup
--           (MARKET status) if the item isn't on the trader. Added
--           per-window (7d/30d/90d/1yr/life) toggles and columns.
-- v0.5.0  - Added optional persistent audit log (Audit Logging ON/OFF),
--           appends to frogspy_audit_log.txt after each batch audit.
-- v0.4.9  - Fixed window title not showing the running version. New
--           checklist rows default unchecked instead of checked.
-- v0.4.8  - Swapped the unreliable Checkbox binding for a Button-based
--           [X]/[ ] toggle in the item checklist.
-- v0.4.7  - Fixed checklist checkboxes immediately reverting. Added a
--           +/- visible-rows stepper.
-- v0.4.6  - Added a selective item checklist (Refresh/Select/Unselect
--           All) for Batch Audit. Duplicate rows now group with a Count.
-- v0.4.5  - Added "Audit This Item" for a single-item undercut check.
-- v0.4.4  - Added fmtPrice() to drop trailing ".0" on whole-plat prices.
-- v0.4.3  - Added "Batch Audit Trader" - full-inventory scan with a
--           color-coded results table.
-- v0.4.2  - Added "Get FrogTracker Price" button (30-day median + other
--           windows).
-- v0.4.1  - Guard against a nil inputItemName crash.
-- v0.4.0  - Added "Find Lowest Bazaar Price" button.
-- v0.3.0  - Item Name auto-fills from the currently selected trader slot.
-- v0.2.2  - Window title now shows the running version number.
-- v0.2.1  - Warn on blank item name instead of failing silently.
-- v0.2.0  - Split Total Copper into Platinum/Gold/Silver/Copper fields.
-- v0.1.x  - Pre-versioning fixes: settext/keystroke injection, module
--           encapsulation, enqueueByName.
local mq = require('mq')
local imgui = require('ImGui')
local fsm = require('frogspy_price_fsm')

local VERSION = '0.16.0'  -- keep in sync with the header comment above

-- v0.12.0: Update check - fetches the raw script from GitHub on load and
-- notifies (console only) if a newer VERSION is found. Same approach as
-- ItemPass.lua's checkForUpdate(): shells out to curl via io.popen rather
-- than an in-process HTTP client, since MQNext Lua has no bundled http lib.
-- NOTE: confirm this points at the real raw path for frogspy.lua before
-- relying on it - update the repo/branch/file path below if it differs.
local UPDATE_CHECK_URL = 'https://raw.githubusercontent.com/mjdeiter/frogspy/main/frogspy.lua'

-- UI State Variables
local openGUI = true
local inputItemName = ""
local inputPlat   = 0
local inputGold   = 0
local inputSilver = 0
local inputCopper = 0

-- Auto-fill tracking: polls fsm.getSelectedSlot() on a timer (not every
-- frame - 200 InvSlot checks per call adds up) and fills inputItemName
-- whenever the in-game selection changes to a new, named slot. Doesn't
-- clear the field on deselect or overwrite manual typing otherwise.
local lastSelectedRow = nil
local lastScanTime = 0
local SCAN_INTERVAL_MS = 250

-- Tracks whether a "Find Lowest Bazaar Price" search is in flight, so we
-- know to poll fsm.isSearchDone() on subsequent frames.
local searchPending = false

-- v0.4.2: tracks whether a "Get FrogTracker Price" lookup is in flight, so
-- we know to poll fsm.isFrogTrackerDone() on subsequent frames. Separate
-- from searchPending above since the two operations poll different
-- fsm accessors, even though only one can run at a time FSM-side.
local ftPending = false

-- v0.4.6: selective Batch Audit checklist state. occupiedSlotsCache is
-- only refreshed on demand (Refresh List button) rather than every render
-- frame, since the underlying scan is a real TLO walk of up to 200 child
-- windows. slotSelected is keyed by trader slot row - persists across a
-- Refresh so re-scanning doesn't silently clear your picks.
-- v0.4.9: new rows now default to UNCHECKED (previously defaulted
-- checked/"select everything") - see the v0.4.9 changelog entry above.
local occupiedSlotsCache = nil
local slotSelected = {}

-- v0.4.7: adjustable visible-rows count for the checklist region (+/-
-- stepper in the UI) and the approximate pixel height of one checkbox
-- row used to translate that into a BeginChild height. 22px is a rough
-- estimate for default ImGui font/spacing - tune this constant if the
-- checklist ends up showing noticeably more or fewer rows than the
-- number selected.
local checklistRows = 10
local CHECKLIST_ROW_HEIGHT = 22

-- v0.5.0: optional persistent audit log. Off by default (matches
-- frogspy.py's own opt-in report generation, not something you want
-- silently accumulating on disk). When enabled, writes one entry to
-- LOG_FILE each time a batch audit (Batch Audit Selected, Audit This
-- Item - both share the same BATCH_* state machine) finishes. Stored in
-- mq.configDir per Matt's established config-file convention rather than
-- the Desktop path frogspy.py used - keeps it alongside other script
-- config instead of cluttering the desktop. batchWasRunning tracks the
-- running->not-running transition across frames so the log write fires
-- exactly once per completed audit, not every render frame.
local LOG_FILE = mq.configDir .. '/frogspy_audit_log.txt'
local logAuditsEnabled = false
local batchWasRunning = false

-- v0.14.0: optional ntfy.sh push alert on a target-price WATCHLIST,
-- fired on the same batch-finish transition as writeAuditLog() above.
-- Replaces v0.13.0's undercut-gap alert (kept firing on the wrong
-- condition for what was actually wanted - "tell me when this item's
-- market price reaches N plat" is a target-price watch against
-- r.lowest, not a your-price-vs-competitor gap check, and doesn't
-- require the item to be UNDERCUT or even sitting in a trader slot at
-- all - MARKET-status rows have a r.lowest same as any other). Off by
-- default - same opt-in convention as logAuditsEnabled. Topic is a
-- free-text ntfy.sh topic name (public, unauthenticated - anyone who
-- knows the topic can subscribe, so pick something non-guessable if it
-- matters), shared across every watched item rather than per-item,
-- since one ntfy subscription covering all your price watches is the
-- simplest setup.
--
-- watchlist is an ordered array of {name=, target=} entries (order
-- preserved for stable UI row rendering, unlike a name-keyed table
-- which would reorder under hash iteration). watchInputName/
-- watchInputTarget are separate from inputItemName/inputPlat (the
-- Queue Price Update fields above) - reusing those would mean typing an
-- item name there always both stages a price update AND edits the
-- watchlist entry, which is two unrelated actions sharing one field by
-- accident. Alerted entries are tracked in watchAlerted (keyed by
-- name) so a given watch only fires once per session instead of
-- re-notifying on every subsequent audit while the price stays at or
-- below target - cleared (per-entry) if the price rises back above
-- target, so a later re-drop notifies again.
local alertsEnabled = false
local alertTopic = ""
local watchlist = {}
local watchAlerted = {}
local watchInputName = ""
local watchInputTarget = 0

-- v0.16.0: tracks whether the ntfy setup-help window is open. Separate
-- top-level ImGui window (own Begin/End), not a tooltip, since the
-- explanation is long enough to need scrolling/wrapping room a hover
-- tooltip can't give.
local showNtfyHelp = false

-- v0.15.0: optional auto-audit timer, closing the actual gap the
-- watchlist had until now - without this, a watched item's price is
-- only ever checked at the moment you happen to click Batch Audit /
-- Audit This Item, so "notify me when it hits target" silently did
-- nothing while you were away from the panel. When autoAuditEnabled,
-- renderGUI() below periodically calls fsm.auditSingleItem() on the
-- NEXT watchlist entry (round-robin via autoAuditWatchIdx, one item
-- per interval - not the whole watchlist at once, which would be
-- indistinguishable from spamming Batch Audit and would hammer
-- frogtracker.biz for no reason if the list grows). Reuses
-- auditSingleItem() rather than the trader-slot batch machinery since
-- watched items don't need to be on the trader - same MARKET-status
-- fallback the "Audit This Item" button already relies on. Piggybacks
-- on the EXISTING batchWasRunning/scanRunningNow transition-detection
-- hook further down (the one that already checks the watchlist after
-- any finished audit) rather than adding a second alert path - this
-- timer's only job is to start audits, not evaluate them.
-- autoAuditIntervalSec default of 300 (5 min) balances "actually
-- useful while away" against not hammering frogtracker.biz - lowered
-- via the UI's - button if you want tighter checks on a small
-- watchlist. lastAutoAuditMs uses mq.gettime() same as the existing
-- SCAN_INTERVAL_MS auto-fill poll above.
local autoAuditEnabled = false
local autoAuditIntervalSec = 300
local lastAutoAuditMs = 0
local autoAuditWatchIdx = 0

-- v0.8.0: which grouped Batch Audit result row (if any) is showing its
-- per-competitor auction breakdown below the main results table. Holds a
-- reference straight into groupedResults, so it stays in sync with that
-- row's most recent data on every render frame without a separate copy;
-- cleared on Close or whenever a new scan starts (batchResults reset
-- means the old reference no longer matches anything real).
local selectedAuditItem = nil

-- v0.6.0: ordered list of the five frogtracker.biz time windows, driving
-- both the toggle buttons and the results-table columns below. `key`
-- matches fsm.getWindowConfig()'s table keys; `low`/`med` match the short
-- field names on each batch result row (r.low7, r.med7, etc.); `label` is
-- the toggle-button/table-header text.
local WINDOWS = {
    { key = 'sevenDay',  low = 'low7',     med = 'med7',     label = '7d'   },
    { key = 'thirtyDay', low = 'low30',    med = 'med30',    label = '30d'  },
    { key = 'ninetyDay', low = 'low90',    med = 'med90',    label = '90d'  },
    { key = 'oneYear',   low = 'low1y',    med = 'med1y',    label = '1yr'  },
    { key = 'lifetime',  low = 'lowLife',  med = 'medLife',  label = 'life' },
}

local function totalCopper()
return (inputPlat * 1000) + (inputGold * 100) + (inputSilver * 10) + inputCopper
end

-- v0.12.0: same auto-update-check pattern as ItemPass.lua's checkForUpdate().
-- Shells out to curl (Windows-only, matches the MQNext/E3Next host env) to
-- pull the raw script from GitHub, then regex-matches the VERSION string out
-- of it and compares against the running VERSION. Console-only notification -
-- doesn't touch the ImGui window or block script startup on failure.
local function checkForUpdate()
    print('\ay[FrogSpy] Checking for updates...\ax')
    local ok, handle = pcall(io.popen,
        'C:\\Windows\\System32\\curl.exe -s --connect-timeout 5 --max-time 8 "' .. UPDATE_CHECK_URL .. '" 2>nul')
    if not ok or not handle then
        print('\ar[FrogSpy] Update check failed (io.popen).\ax')
        return
    end
    local body = handle:read('*a')
    handle:close()
    if not body or #body == 0 then
        print('\ar[FrogSpy] Update check: no response from curl.\ax')
        return
    end
    -- frogspy.lua declares VERSION with single quotes (local VERSION = '0.11.0'),
    -- unlike ItemPass's double-quoted SCRIPT_VERSION - match either style.
    local latest = body:match("VERSION%s*=%s*'([%d%.]+)'") or body:match('VERSION%s*=%s*"([%d%.]+)"')
    if latest and latest ~= VERSION then
        print('\ay[FrogSpy] Update available: v' .. latest .. ' (you have v' .. VERSION .. ')\ax')
        print('\ay[FrogSpy] Get it at: https://github.com/mjdeiter/frogspy\ax')
    else
        print('\ag[FrogSpy] FrogSpy v' .. VERSION .. ' is up to date.\ax')
    end
end

-- v0.14.0: fires an ntfy.sh push notification for a single watchlist
-- item whose market lowest has reached/dropped below its target price,
-- using the exact io.popen/curl.exe pattern checkForUpdate() above
-- already proved works in the MQNext Lua sandbox (same timeout guards,
-- same pcall wrapper, no new dependency). One process spawn per
-- qualifying item - batch audits are already multi-second operations
-- (settle + HTTP round-trip + throttle per item), so a few extra curl
-- calls on a rare price-target hit don't meaningfully add to that.
-- Silent no-op if alertsEnabled is off or alertTopic is blank, so
-- callers don't need to guard on those themselves.
local function sendPriceAlert(itemName, lowestPrice, targetPrice)
    if not alertsEnabled or not alertTopic or alertTopic == "" then return end
    -- NOTE: formats inline with %.3f rather than calling fmtPrice() - that
    -- helper is declared further down this file (after checkForUpdate),
    -- and as a local it isn't in scope yet up here. Trailing zeros in the
    -- notification body are a cosmetic tradeoff for not restructuring the
    -- whole file's declaration order.
    local msg = string.format('%s hit target: %.3f plat (target was %.3f)',
        itemName, lowestPrice or 0, targetPrice or 0)
    local cmd = string.format(
        'C:\\Windows\\System32\\curl.exe -s --connect-timeout 5 --max-time 8 -d "%s" "https://ntfy.sh/%s" 2>nul',
        msg, alertTopic)
    local ok, handle = pcall(io.popen, cmd)
    if not ok or not handle then
        print('\ar[FrogSpy] Price alert failed (io.popen): ' .. itemName .. '\ax')
        return
    end
    handle:close()
    print('\ag[FrogSpy] Price alert sent: ' .. itemName .. '\ax')
end

-- v0.4.4: formats a platinum value for display without a trailing ".0" on
-- whole numbers - yourPrice/gap in batch results can be fractional
-- platinum (gold/silver/copper folded in) after the v0.1.20 FSM fix that
-- switched them from total-copper to platinum-equivalent units.
local function fmtPrice(v)
if not v then return "-" end
    if v == math.floor(v) then
        return string.format("%d", v)
        end
        return string.format("%.3f", v)
        end

        -- v0.16.0: shared hover-tooltip helper. Must be called immediately
        -- after the widget it documents (imgui.IsItemHovered() reads
        -- whichever widget was drawn last) - every Button below in this
        -- file calls this right after its own if/then/end, matching the
        -- existing Audit Logging tooltip's placement rather than
        -- introducing a second convention.
        local function tooltip(text)
        if imgui.IsItemHovered() then
            imgui.SetTooltip(text)
            end
            end

        -- v0.4.6: collapses duplicate (item name, your price) pairs into one row
        -- with a count, instead of listing the same item once per slot. Only
        -- splits back out into separate rows when the price genuinely differs
        -- between slots - status/lowest/rivals/etc. are guaranteed identical
        -- within a group since they only depend on item name (same
        -- frogtracker.biz lookup or cache hit), never on your price.
        -- v0.6.0: carries the five window pairs (low7/med7 .. lowLife/medLife)
        -- through the grouping the same way status/lowest/etc. already were -
        -- they're item-name-only data too, so identical within a group.
        local function groupBatchResults(results)
        local groups, order = {}, {}
        for _, r in ipairs(results) do
            local key = r.name .. "|" .. tostring(r.yourPrice)
            local g = groups[key]
            if not g then
                g = {
                    name = r.name, yourPrice = r.yourPrice, status = r.status, error = r.error,
                    lowest = r.lowest, gap = r.gap, rivals = r.rivals, rivalListings = r.rivalListings,
                    low7 = r.low7, med7 = r.med7, low30 = r.low30, med30 = r.med30,
                    low90 = r.low90, med90 = r.med90, low1y = r.low1y, med1y = r.med1y,
                    lowLife = r.lowLife, medLife = r.medLife,
                    count = 0,
                }
                groups[key] = g
                table.insert(order, key)
                end
                g.count = g.count + 1
                end
                local list = {}
                for _, key in ipairs(order) do table.insert(list, groups[key]) end
                    return list
                    end

                    -- v0.5.0: appends one audit-log entry to LOG_FILE for a just-finished
                    -- batch audit. Takes the already-grouped results (same data the UI table
                    -- renders) plus the summary counts so the log mirrors what's on screen.
                    -- Uses append mode ('a') - this is a running history across sessions, not
                    -- a config file that gets overwritten. mq.TLO.Me.Name() is read live here
                    -- rather than duplicating frogspy_price_fsm.lua's hardcoded TRADER_NAME
                    -- constant, so the log always reflects whichever character is actually
                    -- logged in and running the script.
                    -- v0.6.0: status label now covers MARKET (a market-only entry - no
                    -- trader listing to compare against), and each row's line includes the
                    -- enabled time-window figures so the on-disk log carries the same data
                    -- the results table shows, not just 7-day.
                    local function writeAuditLog(groupedResults, cheapestCount, undercutCount, noneCount, marketCount, errorCount)
                    local f = io.open(LOG_FILE, 'a')
                    if not f then
                        print('\ar[FrogSpy] Could not open audit log for writing: ' .. LOG_FILE .. '\ax')
                        return
                        end

                        local charName = mq.TLO.Me.Name() or "Unknown"
                        f:write(string.format("=== Audit %s - %s ===\n", os.date('%Y-%m-%d %H:%M:%S'), charName))
                        f:write(string.format("Cheapest: %d   Undercut: %d   No competition: %d   Market-only: %d   Errors: %d\n",
                                              cheapestCount, undercutCount, noneCount, marketCount, errorCount))

                        for _, r in ipairs(groupedResults) do
                            local statusLabel = "no comp."
                            if r.error then statusLabel = "ERROR"
                                elseif r.status == "undercut" then statusLabel = "UNDERCUT"
                                    elseif r.status == "cheapest" then statusLabel = "CHEAPEST"
                                        elseif r.status == "market" then statusLabel = "MARKET" end
                                            local countLabel = (r.count > 1) and string.format(" x%d", r.count) or ""

                                            local windowParts = {}
                                            for _, w in ipairs(WINDOWS) do
                                                table.insert(windowParts, string.format("%s low/med: %s/%s",
                                                                                        w.label, fmtPrice(r[w.low]), fmtPrice(r[w.med])))
                                                end

                                                f:write(string.format("  [%s] %s%s - your: %s  lowest: %s  gap: %s  rivals: %s\n",
                                                                      statusLabel, r.name, countLabel, fmtPrice(r.yourPrice), fmtPrice(r.lowest),
                                                                      r.gap and ("+" .. fmtPrice(r.gap)) or "-", tostring(r.rivals or 0)))
                                                f:write("    " .. table.concat(windowParts, "  ") .. "\n")
                                                end
                                                f:write("\n")
                                                f:close()
                                                print('\ag[FrogSpy] Audit log entry written to ' .. LOG_FILE .. '\ax')
                                                end

                                                -- Main ImGui Render Function
                                                local function renderGUI()
                                                if not openGUI then return end

                                                    local shouldDraw
                                                    openGUI, shouldDraw = imgui.Begin('Frogspy Trader Controller v' .. VERSION, openGUI)
                                                    if shouldDraw then
                                                        imgui.Text("Active FSM State: ")
                                                        imgui.SameLine()
                                                        -- state/queue are module-locals inside frogspy_price_fsm.lua, not
                                                        -- fields on the returned table - must go through the accessors.
                                                        local fsmState = fsm.getState()
                                                        if fsmState == "IDLE" then
                                                            imgui.TextColored(ImVec4(0, 1, 0, 1), fsmState)
                                                            else
                                                                imgui.TextColored(ImVec4(1, 1, 0, 1), fsmState)
                                                                end

                                                                imgui.Text("Items in Queue: " .. tostring(fsm.queueLength()))
                                                                imgui.Separator()

                                                                -- Auto-fill from whatever's currently selected in BazaarWnd.
                                                                -- Throttled - scanning 200 InvSlots every single ImGui frame would
                                                                -- be wasteful when a human clicking a slot only needs ~4 checks/sec
                                                                -- to feel instant.
                                                                local nowMs = mq.gettime()
                                                                if nowMs - lastScanTime >= SCAN_INTERVAL_MS then
                                                                    lastScanTime = nowMs
                                                                    local selRow, selName = fsm.getSelectedSlot()
                                                                    if selRow ~= lastSelectedRow then
                                                                        lastSelectedRow = selRow
                                                                        -- Only fill in on a genuine new selection with a resolvable
                                                                        -- name - don't clear the field on deselect, and don't stomp
                                                                        -- on someone mid-typing a manual override.
                                                                        if selRow ~= nil and selName then
                                                                            inputItemName = selName
                                                                            end
                                                                            end
                                                                            end

                                                                            -- Input Fields
                                                                            inputItemName = imgui.InputText("Item Name", inputItemName)

                                                                            inputPlat   = imgui.InputInt("Platinum", inputPlat)
                                                                            inputGold   = imgui.InputInt("Gold", inputGold)
                                                                            inputSilver = imgui.InputInt("Silver", inputSilver)
                                                                            inputCopper = imgui.InputInt("Copper", inputCopper)

                                                                            -- InputInt's -/+ buttons (or manual typing) can go negative -
                                                                            -- clamp each denomination so a negative value can't corrupt the
                                                                            -- total sent to the FSM.
                                                                            if inputPlat   < 0 then inputPlat   = 0 end
                                                                                if inputGold   < 0 then inputGold   = 0 end
                                                                                    if inputSilver < 0 then inputSilver = 0 end
                                                                                        if inputCopper < 0 then inputCopper = 0 end

                                                                                            imgui.Text("Total: " .. tostring(totalCopper()) .. " cp")

                                                                                            -- Action Button
                                                                                            if imgui.Button("Queue Price Update") then
                                                                                                local total = totalCopper()
                                                                                                if inputItemName ~= "" and total >= 0 then
                                                                                                    -- This field is an item NAME, so resolve it to a trader
                                                                                                    -- slot via enqueueByName - fsm.enqueue() expects a numeric
                                                                                                    -- slot index and would silently queue a bad row otherwise.
                                                                                                    fsm.enqueueByName(inputItemName, total)
                                                                                                    inputItemName = ""
                                                                                                    inputPlat, inputGold, inputSilver, inputCopper = 0, 0, 0, 0
                                                                                                    -- Force the next scan to re-fill from the current selection
                                                                                                    -- even if it's the same slot as before (row hasn't changed,
                                                                                                    -- so the change-detection above wouldn't otherwise re-fire).
                                                                                                    lastSelectedRow = nil
                                                                                                    elseif inputItemName == "" then
                                                                                                        -- v0.2.1: previously silent - clicking with a blank name
                                                                                                        -- looked identical to the button doing nothing at all.
                                                                                                        print('\ar[FrogSpy] Type an item name before clicking Queue Price Update.\ax')
                                                                                                        end
                                                                                                        end
                                                                                                        tooltip("Sends the Item Name + Platinum/Gold/Silver/Copper above to the trader as a price update and clears the fields.")

                                                                                                        -- v0.1.10 feature, UNTESTED: searches BazaarSearchWnd for the
                                                                                                        -- lowest currently-listed price across all sellers and fills the
                                                                                                        -- PP/GP/SP/CP fields for review - does NOT auto-queue, so you can
                                                                                                        -- see the result before committing to it.
                                                                                                        if imgui.Button("Find Lowest Bazaar Price") then
                                                                                                            if inputItemName and inputItemName ~= "" then
                                                                                                                if fsm.requestLowestPrice(inputItemName) then
                                                                                                                    searchPending = true
                                                                                                                    end
                                                                                                                    else
                                                                                                                        print('\ar[FrogSpy] Type an item name before searching.\ax')
                                                                                                                        end
                                                                                                                        end
                                                                                                                        tooltip("Searches the Bazaar for the lowest currently-listed price on Item Name and fills the fields for review - does not queue anything by itself.")

                                                                                                                        if searchPending and fsm.isSearchDone() then
                                                                                                                            searchPending = false
                                                                                                                            local lowest = fsm.getSearchResult()
                                                                                                                            if lowest then
                                                                                                                                inputPlat   = math.floor(lowest / 1000)
                                                                                                                                local rem   = lowest % 1000
                                                                                                                                inputGold   = math.floor(rem / 100)
                                                                                                                                rem         = rem % 100
                                                                                                                                inputSilver = math.floor(rem / 10)
                                                                                                                                inputCopper = rem % 10
                                                                                                                                end
                                                                                                                                end

                                                                                                                                -- v0.4.2 feature: pulls FrogTracker.biz's 30-day median price as the
                                                                                                                                -- primary suggested price and fills PP/GP/SP/CP for review (same
                                                                                                                                -- "review before committing" spirit as Find Lowest Bazaar Price
                                                                                                                                -- above) - does NOT auto-queue. Prints the other windows (7-day,
                                                                                                                                -- 90-day, one-year, lifetime lowest+median) to console for context.
                                                                                                                                -- NOTE: this button blocks the game for the duration of the HTTP
                                                                                                                                -- round-trip (observed ~tens of ms up to ~1s) - see the FT_REQUEST
                                                                                                                                -- comment in frogspy_price_fsm.lua for why that's a one-tick cost
                                                                                                                                -- here rather than spread across frames like the search above.
                                                                                                                                if imgui.Button("Get FrogTracker Price") then
                                                                                                                                    if inputItemName and inputItemName ~= "" then
                                                                                                                                        if fsm.requestFrogTrackerPrice(inputItemName) then
                                                                                                                                            ftPending = true
                                                                                                                                            end
                                                                                                                                            else
                                                                                                                                                print('\ar[FrogSpy] Type an item name before looking up FrogTracker price.\ax')
                                                                                                                                                end
                                                                                                                                                end
                                                                                                                                                tooltip("Pulls FrogTracker.biz's 30-day median price for Item Name and fills the fields for review. Blocks briefly (up to ~1s) while it waits on the HTTP request.")

                                                                                                                                                if ftPending and fsm.isFrogTrackerDone() then
                                                                                                                                                    ftPending = false
                                                                                                                                                    local ft = fsm.getFrogTrackerResult()
                                                                                                                                                    if ft then
                                                                                                                                                        local median = ft.thirtyDayMedianPrice
                                                                                                                                                        if median then
                                                                                                                                                            -- Already pure platinum (an int/float pp value, not
                                                                                                                                                            -- copper) - no denomination math needed, unlike the
                                                                                                                                                            -- Find Lowest Bazaar Price flow's raw copper total.
                                                                                                                                                            inputPlat   = math.floor(median + 0.5)
                                                                                                                                                            inputGold   = 0
                                                                                                                                                            inputSilver = 0
                                                                                                                                                            inputCopper = 0
                                                                                                                                                            else
                                                                                                                                                                print('\ar[FrogSpy] No 30-day median price data for "' .. tostring(ft.itemName) .. '".\ax')
                                                                                                                                                                end

                                                                                                                                                                local function printWindow(label, value)
                                                                                                                                                                if value then
                                                                                                                                                                    print('\at[FrogSpy] ' .. label .. ': ' .. tostring(value) .. 'pp\ax')
                                                                                                                                                                    else
                                                                                                                                                                        print('\at[FrogSpy] ' .. label .. ': no data\ax')
                                                                                                                                                                        end
                                                                                                                                                                        end
                                                                                                                                                                        printWindow('7-day lowest',   ft.sevenDayLowestPrice)
                                                                                                                                                                        printWindow('7-day median',   ft.sevenDayMedianPrice)
                                                                                                                                                                        printWindow('90-day lowest',  ft.ninetyDayLowestPrice)
                                                                                                                                                                        printWindow('90-day median',  ft.ninetyDayMedianPrice)
                                                                                                                                                                        printWindow('1-year lowest',  ft.oneYearLowestPrice)
                                                                                                                                                                        printWindow('1-year median',  ft.oneYearMedianPrice)
                                                                                                                                                                        printWindow('lifetime lowest', ft.lifetimeLowestPrice)
                                                                                                                                                                        printWindow('lifetime median', ft.lifetimeMedianPrice)
                                                                                                                                                                        else
                                                                                                                                                                            print('\ar[FrogSpy] FrogTracker lookup for "' .. inputItemName .. '" failed - see console log above.\ax')
                                                                                                                                                                            end
                                                                                                                                                                            end

                                                                                                                                                                            -- v0.4.3: Batch Audit - classifies each audited item as
                                                                                                                                                                            -- cheapest/undercut/no-competition (or, since v0.6.0, market-only
                                                                                                                                                                            -- when it isn't on the trader) against frogtracker.biz, porting
                                                                                                                                                                            -- the `frogspy` (Python) repo's whole-inventory report. Runs for a
                                                                                                                                                                            -- while (one settle + one HTTP round-trip + one throttle delay per
                                                                                                                                                                            -- item) - expect visible per-item hitches and roughly 1-2s/item,
-- not instant.
imgui.Separator()
imgui.Text("Batch Audit")

-- v0.5.0: optional persistent audit log toggle. Same Button-based
-- pattern used everywhere else in this file (checkbox binding was
-- untrustworthy - see the v0.4.7/v0.4.8 history above) rather than
-- imgui.Checkbox. Off by default; the log file path is shown as a
-- tooltip on hover so it's discoverable without cluttering the
-- panel.
local logLabel = logAuditsEnabled and "Audit Logging: ON" or "Audit Logging: OFF"
if imgui.Button(logLabel) then
    logAuditsEnabled = not logAuditsEnabled
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Log file: " .. LOG_FILE)
        end

        -- v0.14.0: price-alert toggle + ntfy topic input + target-price
        -- watchlist, same Button on/off pattern as Audit Logging above.
        -- Kept as plain text/number inputs rather than a settings panel
        -- since this file has no persistence layer yet - matches how
        -- alertsEnabled itself resets on script reload (the watchlist
        -- itself resets too - re-add watches after a /lua stop+run).
        local alertLabel = alertsEnabled and "Price Alerts: ON" or "Price Alerts: OFF"
        if imgui.Button(alertLabel) then
            alertsEnabled = not alertsEnabled
            end
            tooltip("Turns ntfy.sh push notifications on/off for the watchlist below. Doesn't affect Audit Logging.")
            imgui.SameLine()
            imgui.SetNextItemWidth(140)
            alertTopic = imgui.InputText("ntfy topic", alertTopic)
            imgui.SameLine()
            if imgui.Button("Help##ntfy") then
                showNtfyHelp = true
                end
                tooltip("Explains what ntfy is, how to get the app, and how the topic name below connects FrogSpy's alerts to your phone.")

                -- v0.16.0: separate pop-up window walking a first-time user
                -- through the whole ntfy.sh setup, since "ntfy topic" alone
                -- gives no hint that ntfy is a third-party app that needs
                -- installing first. Own Begin/End (not nested inside the
                -- main panel's window) so it floats independently and can
                -- be moved/closed without touching the main panel -
                -- imgui.Begin/openState pattern mirrors the main window's
                -- own openGUI handling above.
                if showNtfyHelp then
                    local ntfyHelpShouldDraw
                    showNtfyHelp, ntfyHelpShouldDraw = imgui.Begin("FrogSpy - ntfy Alert Setup Help", showNtfyHelp)
                    if ntfyHelpShouldDraw then
                        imgui.TextWrapped("Price alerts in FrogSpy work by sending a push notification through ntfy.sh, a free, no-signup push notification service. FrogSpy does not send alerts directly to your phone - it publishes a message to an ntfy.sh 'topic', and only devices subscribed to that exact topic name receive it. Follow the steps below once, and every future price-drop alert from the watchlist will show up on your phone or desktop automatically.")
                        imgui.Separator()
                        imgui.TextWrapped("Step 1 - Install the ntfy app:")
                        imgui.TextWrapped("On your phone, install the 'ntfy' app from the Apple App Store (iOS) or Google Play Store (Android). A desktop app and a plain web browser (https://ntfy.sh/) also work if you'd rather not install anything, though a phone notification is the most useful for an away-from-keyboard alert.")
                        imgui.Separator()
                        imgui.TextWrapped("Step 2 - Pick a topic name:")
                        imgui.TextWrapped("A 'topic' is just a shared channel name - anyone who knows the exact name can publish to it or subscribe to it, and ntfy.sh's public server has no login or access control. Because of that, pick something long, random, and non-guessable (e.g. 'mattdeiter-frogspy-a91f7c') rather than something short like 'frogspy' - a guessable topic means a stranger could see your alerts, or spam you with their own.")
                        imgui.Separator()
                        imgui.TextWrapped("Step 3 - Subscribe in the app:")
                        imgui.TextWrapped("Open the ntfy app, tap '+' / 'Subscribe to topic', and type the exact same topic name you're about to enter in the 'ntfy topic' field on the FrogSpy panel. Capitalization and spelling must match exactly - ntfy treats 'MyTopic' and 'mytopic' as two different topics.")
                        imgui.Separator()
                        imgui.TextWrapped("Step 4 - Enter the topic in FrogSpy and turn alerts on:")
                        imgui.TextWrapped("Type that same topic name into the 'ntfy topic' field on the main panel, add at least one item to the watchlist below with a target plat price, then click 'Price Alerts: OFF' to turn it ON. When a watched item's market price drops to or below its target during an audit (manual or auto-audit), FrogSpy sends one push notification per drop - it won't repeat until the price rises back above target and drops again.")
                        imgui.Separator()
                        imgui.TextWrapped("Notes:")
                        imgui.TextWrapped("- The topic field and this whole feature are optional - leaving 'Price Alerts' OFF means nothing is ever sent anywhere.")
                        imgui.TextWrapped("- Because ntfy.sh's public server is unauthenticated, treat the topic name like a lightweight secret, not a password - random and unpublished is enough.")
                        imgui.TextWrapped("- If notifications aren't arriving, double-check the topic name matches exactly on both ends, and that the ntfy app has notification permissions enabled on your phone.")
                        imgui.Separator()
                        if imgui.Button("Close##ntfyhelp") then
                            showNtfyHelp = false
                            end
                            end
                            imgui.End()
                            end

            -- Add-to-watchlist row: separate input fields from the
            -- Queue Price Update fields above (inputItemName/inputPlat) -
            -- see the v0.14.0 note on the watchlist locals for why those
            -- aren't reused here.
            imgui.SetNextItemWidth(180)
            watchInputName = imgui.InputText("watch item", watchInputName)
            imgui.SameLine()
            -- v0.16.0: widened from 90 to 140 - a target price needs room
            -- for up to 7 digits (millions of plat on high-value items),
            -- and the old width clipped anything past ~5 digits.
            imgui.SetNextItemWidth(140)
            watchInputTarget = imgui.InputInt("target plat", watchInputTarget)
            if watchInputTarget < 0 then watchInputTarget = 0 end
            imgui.SameLine()
            if imgui.Button("Add Watch") then
                if watchInputName ~= "" then
                    -- v0.14.0: replaces an existing entry for the same
                    -- item name (case-sensitive match against r.name,
                    -- same as everywhere else in this file) instead of
                    -- appending a duplicate row - re-adding the same
                    -- item just updates its target and clears any prior
                    -- alerted-once state so the new target can fire
                    -- fresh.
                    local replaced = false
                    for _, w in ipairs(watchlist) do
                        if w.name == watchInputName then
                            w.target = watchInputTarget
                            replaced = true
                            break
                        end
                    end
                    if not replaced then
                        table.insert(watchlist, { name = watchInputName, target = watchInputTarget })
                    end
                    watchAlerted[watchInputName] = nil
                    watchInputName = ""
                    watchInputTarget = 0
                end
            end
            tooltip("Adds 'watch item' to the watchlist below with 'target plat' as its alert threshold. Re-adding an existing item updates its target instead of duplicating the row.")

            -- Watchlist display: name, target, a Remove button per row.
            -- Iterates backwards so table.remove during the loop doesn't
            -- skip the entry after a removed one.
            if #watchlist > 0 then
                imgui.Text("Watching:")
                for i = #watchlist, 1, -1 do
                    local w = watchlist[i]
                    imgui.Text("  " .. w.name .. " <= " .. tostring(w.target) .. " plat")
                    imgui.SameLine()
                    if imgui.Button("Remove##watch" .. tostring(i)) then
                        watchAlerted[w.name] = nil
                        table.remove(watchlist, i)
                    end
                    tooltip("Removes " .. w.name .. " from the watchlist. It will no longer be checked or alerted on.")
                end
            end

            -- v0.15.0: auto-audit toggle + interval control. Without
            -- this, alertsEnabled/watchlist only ever gets evaluated at
            -- the moment you click Batch Audit/Audit This Item - see the
            -- v0.15.0 note on the autoAuditEnabled locals above for why
            -- that made the watchlist mostly pointless while away from
            -- the panel. Interval is in whole minutes in the UI
            -- (autoAuditIntervalSec stores seconds internally, matching
            -- mq.gettime()'s millisecond convention elsewhere in this
            -- file) - minMinutes floor of 1 keeps someone from
            -- accidentally setting 0 and hammering frogtracker.biz every
            -- frame.
            local autoAuditLabel = autoAuditEnabled and "Auto-Audit Watchlist: ON" or "Auto-Audit Watchlist: OFF"
            if imgui.Button(autoAuditLabel) then
                autoAuditEnabled = not autoAuditEnabled
                if autoAuditEnabled then
                    -- Reset the timer on enable so it doesn't fire
                    -- immediately using a stale lastAutoAuditMs from a
                    -- much earlier session/toggle - first check happens
                    -- one full interval from right now.
                    lastAutoAuditMs = mq.gettime()
                end
            end
            tooltip("Turns the round-robin watchlist auto-audit on/off. When on, one watched item is re-checked every interval below without needing to click Batch Audit or Audit This Item.")
            imgui.SameLine()
            -- v0.16.0: three synchronized views of the same underlying
            -- autoAuditIntervalSec (minutes/hours/days), for when 5-min
            -- granularity is too fine (checking once a day) or too coarse
            -- (checking every couple minutes). Only the field the person
            -- actually edited this frame writes back to
            -- autoAuditIntervalSec - comparing each InputInt's return
            -- against its own just-computed display value (rather than
            -- unconditionally recomputing all three every frame, like the
            -- old minutes-only version did) is what keeps the other two
            -- fields from immediately stomping the edit back to 0 the
            -- same frame. Minimum stays 60s (1 min) however it's set,
            -- same floor as the original minutes-only field.
            local autoAuditMinutes = math.floor(autoAuditIntervalSec / 60)
            local autoAuditHours   = math.floor(autoAuditIntervalSec / 3600)
            local autoAuditDays    = math.floor(autoAuditIntervalSec / 86400)
            imgui.SetNextItemWidth(80)
            local newAutoAuditMinutes = imgui.InputInt("check every (min)", autoAuditMinutes)
            imgui.SameLine()
            imgui.SetNextItemWidth(80)
            local newAutoAuditHours = imgui.InputInt("check every (hr)", autoAuditHours)
            imgui.SameLine()
            imgui.SetNextItemWidth(80)
            local newAutoAuditDays = imgui.InputInt("check every (day)", autoAuditDays)
            if newAutoAuditMinutes ~= autoAuditMinutes then
                if newAutoAuditMinutes < 1 then newAutoAuditMinutes = 1 end
                autoAuditIntervalSec = newAutoAuditMinutes * 60
            elseif newAutoAuditHours ~= autoAuditHours then
                if newAutoAuditHours < 1 then newAutoAuditHours = 1 end
                autoAuditIntervalSec = newAutoAuditHours * 3600
            elseif newAutoAuditDays ~= autoAuditDays then
                if newAutoAuditDays < 1 then newAutoAuditDays = 1 end
                autoAuditIntervalSec = newAutoAuditDays * 86400
            end


        -- v0.6.0: time-window toggles - which of frogtracker.biz's five
        -- history windows to pull/display. Read/write straight through to
        -- fsm.getWindowConfig()/fsm.setWindowEnabled() rather than keeping
        -- a separate local copy, so the FSM module stays the single
        -- source of truth (matches how Audit Logging's own state is kept
        -- local here instead - the difference is this config needs to be
        -- visible to frogspy_price_fsm.lua's own extraction code, not just
        -- the UI). Same Button-based on/off pattern as Audit Logging,
-- for the same untrustworthy-Checkbox reason noted throughout
-- this file's history.
imgui.Text("Time windows to audit:")
local wcfg = fsm.getWindowConfig()
for i, w in ipairs(WINDOWS) do
    local enabled = wcfg[w.key]
    local wLabel = string.format("%s: %s", w.label, enabled and "ON" or "OFF")
    if imgui.Button(wLabel .. "##window_" .. w.key) then
        fsm.setWindowEnabled(w.key, not enabled)
        end
        tooltip("Toggles whether the " .. w.label .. " low/median columns are pulled from FrogTracker and shown in the results table.")
        if i < #WINDOWS then imgui.SameLine() end
            end

            -- v0.4.6: item selection checklist - lets you audit only specific
            -- items instead of always the whole inventory. occupiedSlotsCache
            -- stays nil until the first Refresh List click, so this never
            -- forces a 200-slot TLO scan before you've actually opened the
            -- panel with a trader window up.
            -- v0.4.9: newly-seen slots now default to UNCHECKED (previously
            -- defaulted checked, so Batch Audit Selected ran everything
            -- unless you opted out). Use Select All for the old behavior.
            if imgui.Button("Refresh List") then
                occupiedSlotsCache = fsm.getOccupiedSlots()
                for _, slot in ipairs(occupiedSlotsCache) do
                    if slotSelected[slot.row] == nil then slotSelected[slot.row] = false end
                        end
                        end
                        tooltip("Re-scans your trader's occupied slots below. New slots default to unchecked - existing checkbox states are kept.")
                        imgui.SameLine()
                        if imgui.Button("Select All") then
                            if occupiedSlotsCache then
                                for _, slot in ipairs(occupiedSlotsCache) do slotSelected[slot.row] = true end
                                    end
                                    end
                                    tooltip("Checks every occupied slot in the list below, for a full-inventory Batch Audit Selected.")
                                    imgui.SameLine()
                                    if imgui.Button("Unselect All") then
                                        if occupiedSlotsCache then
                                            for _, slot in ipairs(occupiedSlotsCache) do slotSelected[slot.row] = false end
                                                end
                                                end
                                                tooltip("Unchecks every slot in the list below.")

                                                if not occupiedSlotsCache then
                                                    imgui.Text("Click Refresh List to load your trader's occupied slots.")
                                                    else
                                                        local selectedCount = 0
                                                        for _, slot in ipairs(occupiedSlotsCache) do
                                                            if slotSelected[slot.row] then selectedCount = selectedCount + 1 end
                                                                end
                                                                imgui.Text(string.format("%d / %d selected", selectedCount, #occupiedSlotsCache))

                                                                -- v0.4.7: rows-visible stepper for the checklist region, using
                                                                -- Button (already proven working) rather than an untested
                                                                -- InputInt/SliderInt widget - keeps this addition low-risk.
                                                                imgui.Text("Visible rows:")
                                                                imgui.SameLine()
                                                                if imgui.Button("-##checklistRows") then
                                                                    checklistRows = math.max(3, checklistRows - 1)
                                                                    end
                                                                    tooltip("Shows one fewer row in the slot checklist below (minimum 3).")
                                                                    imgui.SameLine()
                                                                    imgui.Text(tostring(checklistRows))
                                                                    imgui.SameLine()
                                                                    if imgui.Button("+##checklistRows") then
                                                                        checklistRows = math.min(60, checklistRows + 1)
                                                                        end
                                                                        tooltip("Shows one more row in the slot checklist below (maximum 60).")

                                                                        -- v0.4.8 BUG FIX: v0.4.7's checkboxCompat() guessed at
                                                                        -- imgui.Checkbox's return signature - first the standard
                                                                        -- (changed, newValue) pair, then a single-return fallback -
                                                                        -- and checking a box still immediately reverted to unchecked
                                                                        -- under both. Rather than guess a third signature blind,
-- dropped Checkbox entirely and rebuilt the toggle on
-- imgui.Button, the one primitive already proven reliable
-- everywhere else in this file (Refresh List, Select All, the
-- rows stepper, etc.). Button's return is unambiguous - true
-- only on the exact frame it's clicked - so state is tracked
-- purely in Lua (slotSelected) with no return-value contract
-- left to get wrong. Marker text ([X]/[ ]) shows checked
-- state in the button label itself.
--
-- BeginChild usage is still untested against the live ImGui
-- binding (no prior use elsewhere in this file), so it stays
-- pcall-wrapped with a non-scrolling fallback - same caution
-- as the results table in v0.4.3, which turned out fine once
-- confirmed live.
local renderChecklist = function()
for _, slot in ipairs(occupiedSlotsCache) do
    local marker = slotSelected[slot.row] and "[X]" or "[ ]"
    if imgui.Button(string.format("%s %s (slot %d)##slot%d",
        marker, slot.name, slot.row, slot.row)) then
        slotSelected[slot.row] = not slotSelected[slot.row]
        end
        tooltip("Toggles whether slot " .. slot.row .. " (" .. slot.name .. ") is included in Batch Audit Selected.")
        end
        end
        local childOk = pcall(function()
        if imgui.BeginChild("SlotChecklist", 0, checklistRows * CHECKLIST_ROW_HEIGHT) then
            renderChecklist()
            end
            imgui.EndChild()
            end)
        if not childOk then
            renderChecklist()
            end
            end

            -- v0.5.0: capture the running state once up front so both the
            -- UI branch below and the completion-detection at the bottom of
            -- this section use the exact same read for a given frame.
            local scanRunningNow = fsm.isBatchScanRunning()

            -- v0.15.0: auto-audit trigger. Only starts a new audit when
            -- the FSM is genuinely idle (scanRunningNow false, same read
            -- as everything else this frame - never re-checks
            -- fsm.isBatchScanRunning() a second time here, so this can
            -- never race against a manual Batch Audit/Audit This Item
            -- click in the same frame) and the interval has elapsed.
            -- Starting fsm.auditSingleItem() here does NOT flip
            -- scanRunningNow for the REST of this frame (the FSM only
            -- reports running on a later frame), so the existing
            -- scanRunningNow-branch UI below (progress text vs. the
            -- Batch Audit/Audit This Item buttons) renders correctly
            -- either way this frame - it'll just show "Scanning..."
            -- starting next frame, same as a manual click would.
            -- Round-robins through watchlist via autoAuditWatchIdx
            -- rather than auditing everything at once - one item per
            -- interval keeps this from ever looking different to
            -- frogtracker.biz than a human occasionally clicking Audit
            -- This Item. Silently does nothing if watchlist is empty
            -- (idx has nothing to point at) - no error, no console spam,
            -- since an empty watchlist with the toggle left on isn't a
            -- mistake worth interrupting anyone over.
            if autoAuditEnabled and not scanRunningNow and #watchlist > 0 then
                local nowMsAA = mq.gettime()
                if nowMsAA - lastAutoAuditMs >= (autoAuditIntervalSec * 1000) then
                    lastAutoAuditMs = nowMsAA
                    autoAuditWatchIdx = autoAuditWatchIdx + 1
                    if autoAuditWatchIdx > #watchlist then autoAuditWatchIdx = 1 end
                    local target = watchlist[autoAuditWatchIdx]
                    if target then
                        -- v0.15.0: note that this replaces the visible
                        -- results table with a single-item result (same
                        -- as a manual "Audit This Item" click would) -
                        -- printed so an unexpected table change while
                        -- auto-audit is on reads as intentional, not a
                        -- glitch.
                        print('\ay[FrogSpy] Auto-audit checking watchlist item: ' .. target.name .. '\ax')
                        fsm.auditSingleItem(target.name)
                    end
                end
            end

            if scanRunningNow then
                local cur, total = fsm.getBatchScanProgress()
                imgui.Text(string.format("Scanning... %d / %d", cur, total))
                imgui.SameLine()
                if imgui.Button("Cancel Scan") then
                    fsm.reset()
                    end
                    tooltip("Aborts the in-progress batch scan and resets the FSM to idle. Any items already audited this run are discarded.")
                    else
                        if imgui.Button("Batch Audit Selected") then
                            if not occupiedSlotsCache then
                                print('\\ar[FrogSpy] Click Refresh List first.\\ax')
                                else
                                    local queue = {}
                                    for _, slot in ipairs(occupiedSlotsCache) do
                                        if slotSelected[slot.row] then
                                            table.insert(queue, { row = slot.row, name = slot.name })
                                            end
                                            end
                                            if #queue == 0 then
                                                print('\\ar[FrogSpy] No items selected - check at least one, or Select All.\\ax')
                                                elseif not fsm.startBatchAudit(queue) then
                                                    print('\\ar[FrogSpy] Could not start batch audit - FSM busy. Check console above.\\ax')
                                                    end
                                                    end
                                                    end
                                                    tooltip("Runs a full FrogTracker audit on every checked slot in the checklist above and fills the results table below.")
                                                    imgui.SameLine()
                                                    -- v0.4.5: single-item version - same undercut/cheapest check
                                                    -- as the full scan, but for just the item typed in the Item
                                                    -- Name field above, so you don't have to run the whole
                                                    -- inventory to check one item. Fills the same results table
                                                    -- below (with one row) since it shares fsm's batch machinery.
                                                    -- v0.6.0: no longer requires the item to be on the trader -
                                                    -- fsm.auditSingleItem() itself now falls back to a
                                                    -- market-only lookup (MARKET status) when the name isn't
                                                    -- found in a trader slot, so this button just works either
                                                    -- way without any change here.
                                                    if imgui.Button("Audit This Item") then
                                                        if inputItemName and inputItemName ~= "" then
                                                            if not fsm.auditSingleItem(inputItemName) then
                                                                print('\\ar[FrogSpy] Could not audit "' .. inputItemName .. '" - FSM busy. Check console above.\\ax')
                                                                end
                                                                else
                                                                    print('\\ar[FrogSpy] Type an item name before auditing it.\\ax')
                                                                    end
                                                                    end
                                                                    tooltip("Runs a single FrogTracker audit on the Item Name typed above, whether or not it's on the trader (falls back to a market-only lookup).")
                                                                    end

                                                                    local batchResults = fsm.getBatchScanResults()
                                                                    local groupedResults = groupBatchResults(batchResults)
                                                                    if #batchResults > 0 then
                                                                        local cheapestCount, undercutCount, noneCount, marketCount, errorCount = 0, 0, 0, 0, 0
                                                                        for _, r in ipairs(batchResults) do
                                                                            if r.error then errorCount = errorCount + 1
                                                                                elseif r.status == "cheapest" then cheapestCount = cheapestCount + 1
                                                                                    elseif r.status == "undercut" then undercutCount = undercutCount + 1
                                                                                        elseif r.status == "market" then marketCount = marketCount + 1
                                                                                            else noneCount = noneCount + 1 end
                                                                                                end
                                                                                                imgui.Text(string.format("Cheapest: %d   Undercut: %d   No competition: %d   Market-only: %d   Errors: %d",
                                                                                                                         cheapestCount, undercutCount, noneCount, marketCount, errorCount))

                                                                                                -- v0.5.0: fires exactly once, on the frame the scan transitions
                                                                                                -- from running to finished (batchWasRunning true last frame,
                                                                                                -- scanRunningNow false this frame) - not on every render frame
                                                                                                -- while the finished results just sit there being displayed.
                                                                                                if logAuditsEnabled and batchWasRunning and not scanRunningNow then
                                                                                                    writeAuditLog(groupedResults, cheapestCount, undercutCount, noneCount, marketCount, errorCount)
                                                                                                    end

                                                                                                    -- v0.14.0: same batch-finish transition as the audit log write
                                                                                                    -- above (fires exactly once per completed audit). Walks the
                                                                                                    -- WATCHLIST (not groupedResults - the watchlist is the small
                                                                                                    -- user-picked set of items being tracked, groupedResults is
                                                                                                    -- everything just audited) and looks up each watched item's
                                                                                                    -- matching row by name. Fires when r.lowest is present and
                                                                                                    -- has reached/dropped to/below the target - unlike the old
                                                                                                    -- v0.13.0 gap check, this applies regardless of r.status
                                                                                                    -- (MARKET/CHEAPEST/UNDERCUT all have a real r.lowest; only
                                                                                                    -- no-competition/error rows lack one, guarded by the nil
                                                                                                    -- check below). watchAlerted[name] gates it to firing once
                                                                                                    -- per drop-below-target rather than every audit while it
                                                                                                    -- stays low, and clears (re-arms) if the price rises back
                                                                                                    -- above target, so a later re-drop notifies again. A
                                                                                                    -- watched item not present in this audit's groupedResults
                                                                                                    -- (wasn't included in the batch) is silently skipped - it
                                                                                                    -- just waits for a future audit that does cover it.
                                                                                                    if alertsEnabled and batchWasRunning and not scanRunningNow then
                                                                                                        for _, w in ipairs(watchlist) do
                                                                                                            local matchRow = nil
                                                                                                            for _, r in ipairs(groupedResults) do
                                                                                                                if r.name == w.name then
                                                                                                                    matchRow = r
                                                                                                                    break
                                                                                                                    end
                                                                                                                    end
                                                                                                                    if matchRow and matchRow.lowest then
                                                                                                                        if matchRow.lowest <= w.target then
                                                                                                                            if not watchAlerted[w.name] then
                                                                                                                                sendPriceAlert(w.name, matchRow.lowest, w.target)
                                                                                                                                watchAlerted[w.name] = true
                                                                                                                                end
                                                                                                                                else
                                                                                                                                    watchAlerted[w.name] = nil
                                                                                                                                    end
                                                                                                                                    end
                                                                                                                                    end
                                                                                                                                    end


                                                                                                    -- v0.4.3: table rendering is untested against the live ImGui
                                                                                                    -- binding (no prior table usage anywhere in this file to
                                                                                                    -- confirm the exact API surface against), so the whole thing
                                                                                                    -- is wrapped defensively - falls back to a plain-text list if
                                                                                                    -- BeginTable/TableSetupColumn/etc. don't behave as expected,
-- rather than risking the whole GUI panel.
-- v0.7.0: column count is now dynamic instead of fixed at 17 -
-- computed right before BeginTable from the current
-- fsm.getWindowConfig() state (7 base columns:
-- Status/Item/Count/Your Price/Lowest/Gap/Rivals, + 2 columns for
-- each of the five time windows that's currently enabled).
-- TableSetupColumn and the per-row TableNextColumn calls below are
-- gated behind the same wcfg[w.key] check, so a disabled window's
-- columns are never created at all - the table collapses
-- horizontally on the very next render frame after a toggle click,
-- rather than sitting there full-width showing "-" as v0.6.0 did.
local tableOk = pcall(function()
local tableFlagsOk, tableFlags = pcall(function()
return ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollX
end)
if not tableFlagsOk then tableFlags = 0 end

    local colCount = 8
    for _, w in ipairs(WINDOWS) do
        if wcfg[w.key] then colCount = colCount + 2 end
        end

        if imgui.BeginTable("BatchAuditResults", colCount, tableFlags) then
            imgui.TableSetupColumn("Status")
            imgui.TableSetupColumn("Item")
            imgui.TableSetupColumn("Count")
            imgui.TableSetupColumn("Your Price")
            imgui.TableSetupColumn("Lowest")
            imgui.TableSetupColumn("Gap")
            imgui.TableSetupColumn("Rivals")
            imgui.TableSetupColumn("Competitors")
            for _, w in ipairs(WINDOWS) do
                if wcfg[w.key] then
                    imgui.TableSetupColumn(w.label .. " Low")
                    imgui.TableSetupColumn(w.label .. " Med")
                    end
                    end
                    imgui.TableHeadersRow()

            for idx, r in ipairs(groupedResults) do
                imgui.TableNextRow()
                local rowColor = ImVec4(1, 1, 1, 1)
                local statusLabel = "?"
                if r.error then
                    rowColor = ImVec4(1, 0.4, 0.4, 1); statusLabel = "ERROR"
                    elseif r.status == "undercut" then
                        rowColor = ImVec4(1, 0.3, 0.3, 1); statusLabel = "UNDERCUT"
                        elseif r.status == "cheapest" then
                            rowColor = ImVec4(0.3, 1, 0.3, 1); statusLabel = "CHEAPEST"
                            elseif r.status == "market" then
                                -- v0.6.0: distinct blue-gray from the existing
                                -- gray "no comp." color, so a market-only
                                -- (no trader listing) row reads as a different
                                -- case at a glance, not just another no-comp.
                                rowColor = ImVec4(0.4, 0.7, 1, 1); statusLabel = "MARKET"
                                else
                                    rowColor = ImVec4(0.6, 0.6, 0.6, 1); statusLabel = "no comp."
                                    end

                                    imgui.TableNextColumn(); imgui.TextColored(rowColor, statusLabel)
                                    imgui.TableNextColumn(); imgui.TextColored(rowColor, r.name)
                                    imgui.TableNextColumn(); imgui.TextColored(rowColor, tostring(r.count))
                                    imgui.TableNextColumn(); imgui.TextColored(rowColor, fmtPrice(r.yourPrice))
                                    imgui.TableNextColumn(); imgui.TextColored(rowColor, fmtPrice(r.lowest))
                                    imgui.TableNextColumn(); imgui.TextColored(rowColor, r.gap and ("+" .. fmtPrice(r.gap)) or "-")
                                    imgui.TableNextColumn(); imgui.TextColored(rowColor, tostring(r.rivals or 0))
                                    imgui.TableNextColumn()
                                    -- v0.8.0: opens the per-competitor auction
                                    -- breakdown below the table for this row.
                                    -- ##idx keeps the button ID unique per row
                                    -- (item name alone can repeat across rows
                                    -- when prices genuinely differ - same
                                    -- reasoning as groupBatchResults()).
                                    if imgui.Button("View##competitors" .. tostring(idx)) then
                                        selectedAuditItem = r
                                        end
                                        tooltip("Shows the full list of competing seller auctions for " .. r.name .. " below the table.")
                                        for _, w in ipairs(WINDOWS) do
                                            if wcfg[w.key] then
                                                imgui.TableNextColumn(); imgui.TextColored(rowColor, fmtPrice(r[w.low]))
                                                imgui.TableNextColumn(); imgui.TextColored(rowColor, fmtPrice(r[w.med]))
                                                end
                                                end
                                                end
                                            imgui.EndTable()
                                        end
                                        end)

if not tableOk then
    -- Fallback: plain-text rows, still color-coded, if the
    -- table API didn't behave as expected. v0.6.0: appends a
    -- compact "windows:" summary per row so the fallback path
    -- doesn't silently lose the expanded window data.
    for _, r in ipairs(groupedResults) do
        local rowColor = ImVec4(1, 1, 1, 1)
        local label = "no comp."
        if r.error then rowColor, label = ImVec4(1, 0.4, 0.4, 1), "ERROR"
            elseif r.status == "undercut" then rowColor, label = ImVec4(1, 0.3, 0.3, 1), "UNDERCUT"
                elseif r.status == "cheapest" then rowColor, label = ImVec4(0.3, 1, 0.3, 1), "CHEAPEST"
                    elseif r.status == "market" then rowColor, label = ImVec4(0.4, 0.7, 1, 1), "MARKET" end
                        local countLabel = (r.count > 1) and string.format(" x%d", r.count) or ""
                        imgui.TextColored(rowColor, string.format("[%s] %s%s - your: %s  lowest: %s  rivals: %s",
                                                                  label, r.name, countLabel, fmtPrice(r.yourPrice), fmtPrice(r.lowest), tostring(r.rivals or 0)))
                        local windowParts = {}
                        for _, w in ipairs(WINDOWS) do
                            table.insert(windowParts, string.format("%s %s/%s", w.label, fmtPrice(r[w.low]), fmtPrice(r[w.med])))
                            end
                            imgui.TextColored(rowColor, "    windows: " .. table.concat(windowParts, "  "))
                            end
                            end
                            end

                            -- v0.8.0: renders the per-competitor auction breakdown for whichever
-- row's "View" button was last clicked in the results table above.
-- Independent of the table/fallback split above it - reads
-- selectedAuditItem directly, so it still works even across a scan
-- restart as long as the person hasn't clicked Close (matches the FSM
-- always giving a real array back per the v0.2.1 changelog, so an empty
-- table here means genuinely zero competitors, not a missing field).
if selectedAuditItem then
    imgui.Separator()
    imgui.Text("Competitor Auctions - " .. selectedAuditItem.name)
    imgui.SameLine()
    if imgui.Button("Close##competitors") then
        selectedAuditItem = nil
    end
end

if selectedAuditItem then
    local rivalListings = selectedAuditItem.rivalListings or {}
    if #rivalListings == 0 then
        imgui.Text("No competitor auctions found for this item.")
    else
        local detailOk = pcall(function()
            local detailFlagsOk, detailFlags = pcall(function()
                return ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollX
            end)
            if not detailFlagsOk then detailFlags = 0 end

            if imgui.BeginTable("CompetitorAuctions", 2, detailFlags) then
                imgui.TableSetupColumn("Seller")
                imgui.TableSetupColumn("Price")
                imgui.TableHeadersRow()
                for _, listing in ipairs(rivalListings) do
                    imgui.TableNextRow()
                    imgui.TableNextColumn(); imgui.Text(listing.sellerName)
                    imgui.TableNextColumn(); imgui.Text(fmtPrice(listing.price))
                end
                imgui.EndTable()
            end
        end)
        if not detailOk then
            -- Same defensive fallback spirit as the main results table -
            -- plain-text rows if BeginTable misbehaves here too.
            for _, listing in ipairs(rivalListings) do
                imgui.Text(string.format("%s - %s", listing.sellerName, fmtPrice(listing.price)))
            end
        end
    end
end

-- v0.5.0: update the transition tracker at the very end of the
                            -- Batch Audit section, after both the running-state UI branch and
                            -- the completion-detection log write above have already used this
                            -- frame's scanRunningNow value.
                            batchWasRunning = scanRunningNow

                            -- Diagnostic
                            if imgui.Button("Force FSM Reset") then
                                fsm.reset()
                                end
                                tooltip("Resets the price-update/batch-audit FSM to idle. Use this if the panel seems stuck (e.g. 'Scanning...' that never finishes).")
                                end
                                imgui.End()
                                end

                                -- Bind the ImGui render loop
                                mq.imgui.init('FrogspyUI', renderGUI)

                                -- v0.12.0: one-shot update check on load (same timing as ItemPass.lua)
                                checkForUpdate()

                                -- Main execution loop
                                while openGUI do
                                    fsm.tick()     -- Drive the FSM forward
                                    mq.delay(10)   -- Prevent CPU locking
                                    end