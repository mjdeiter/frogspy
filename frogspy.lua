-- frogspy_ui.lua
-- ImGui control panel / tick-loop driver for frogspy_price_fsm.lua.
-- Version: 0.7.0
-- Author: Alektra <Lederhosen>
--
-- CHANGELOG:
-- v0.7.0 - Batch Audit results table now collapses columns for disabled
--          time windows instead of always showing all five (with "-" in
--          the cells) as v0.6.0 did. colCount is computed right before
--          BeginTable from the current fsm.getWindowConfig() state (7
--          base columns + 2 per enabled window), and both
--          TableSetupColumn and the per-row TableNextColumn/TextColored
--          calls are gated behind the same per-window enabled check. A
--          window toggle button click is a real width change now, not
--          just a content change - the table reclaims the horizontal
--          space instead of showing dead "-" columns. Plain-text
--          fallback and writeAuditLog() are unchanged - they're not
--          fixed-column layouts, so there's no shape to collapse.
-- v0.6.0 - Two features, both on the audit system:
--          (1) "Audit This Item" (and Batch Audit Selected, since they
--              share the same BATCH_* machinery FSM-side) no longer
--              requires the item to be sitting in a trader slot.
--              fsm.auditSingleItem() now falls back to a market-only
--              lookup when the typed name isn't found on the trader -
--              same frogtracker.biz data, just no "your price" to
--              compare it against, so those rows show a new MARKET
--              status (gray/blue, distinct from the existing
--              cheapest/undercut/no-comp. colors) instead of failing
--              with "not found in a trader slot". No UI change needed to
--              trigger this - it's automatic on the existing button.
--          (2) Time-window controls: frogtracker.biz's five history
--              windows (7-day/30-day/90-day/1-year/all-time) are now
--              shown as their own columns in the results table (below,
--              renamed from "7d Low"/"7d Med" to the fuller set) and can
--              individually be pulled or ignored via five new toggle
--              buttons ("7d: ON/OFF" etc.) next to the audit-logging
--              toggle. Reads/writes fsm.getWindowConfig()/
--              fsm.setWindowEnabled() - the FSM module owns this config,
--              not the UI, so it persists across Refresh List calls and
--              applies uniformly to both Audit This Item and Batch Audit
--              Selected. A disabled window just shows "-" in its columns
--              (table stays a fixed column count either way - toggling
--              only changes what gets fetched/displayed, not the table
--              shape, which keeps the already-cautious BeginTable code
--              from v0.4.3 unchanged in structure).
-- v0.5.0 - NEW FEATURE: optional persistent audit log, closing the one
--          real gap versus the Python frogspy repo (its frogspy_output.txt
--          report had no Lua equivalent - results only ever lived in the
--          ImGui table while the panel was open). "Audit Logging: OFF/ON"
--          toggle button next to Batch Audit (off by default; hover shows
--          the log file path as a tooltip). When on, writeAuditLog()
--          appends one timestamped entry - character name, summary
--          counts, and the same grouped per-item rows the results table
--          shows - to mq.configDir .. '/frogspy_audit_log.txt' exactly
--          once per finished audit (detected via a running->not-running
--          transition check, batchWasRunning vs. the newly-hoisted
--          scanRunningNow, so it fires once rather than every frame the
--          finished results sit on screen). Covers both Batch Audit
--          Selected and Audit This Item since they share the same
--          BATCH_* FSM state machine. Also fixed a stale v0.4.6-era
--          comment above slotSelected that still said new rows "default
--          to selected" - that changed to unchecked back in v0.4.9.
-- v0.4.9 - Two changes after the v0.4.8 live test confirmed the Button
--          toggle checklist works:
--          (1) BUG FIX: the window title still showed "0.4.7" even
--              though the header comment said 0.4.8 - there's a
--              separate `local VERSION` constant (added back in v0.2.2
--              specifically so the title bar shows the running version)
--              that the v0.4.8 edit missed bumping. Now kept in sync.
--          (2) BEHAVIOR CHANGE, requested after live test: Refresh List
--              used to default every occupied slot to checked, so
--              Batch Audit Selected ran the whole inventory unless you
--              manually unchecked items - same effective behavior as
--              the old always-whole-inventory Batch Audit Trader button
--              it replaced. Now Refresh List defaults everything
--              UNCHECKED, so you pick what runs instead of opting out
--              of items you don't want audited. Select All/Unselect All
--              are unchanged.
-- v0.4.8 - BUG FIX, reported live: v0.4.7's checkboxCompat() shim (which
--          guessed between a (changed, newValue) return and a
--          single-return fallback) still let checking an item revert to
--          unchecked immediately. Rather than guess a third
--          imgui.Checkbox return signature, the checklist no longer uses
--          Checkbox at all - it's now a Button per row with a [X]/[ ]
--          marker baked into the label, toggling slotSelected in Lua on
--          click. Button's return (true only on the click frame) is
--          already proven correct everywhere else in this file, so this
--          removes the last untested-signature risk from the checklist.
-- v0.4.7 - BUG FIX, reported live: checking an item in the v0.4.6
--          checklist immediately unchecked itself. Root cause: assumed
--          imgui.Checkbox returns (changed, newValue) like the standard
--          Dear ImGui Lua binding convention - if this binding actually
--          only returns the new value as a single result, Lua fills the
--          second local with nil, and "if changed then slotSelected[row]
--          = newVal end" was overwriting a real `true` with `nil` right
--          after you set it (nil then reads as unchecked next frame).
--          Added checkboxCompat() which detects which signature is
--          actually in play (second return nil vs. boolean) and handles
--          either correctly.
--          ALSO: added a "Visible rows" +/- stepper (Button-based, not an
--          untested InputInt/SliderInt) so the checklist's scroll region
--          height is adjustable instead of a fixed 150px - requested
--          alongside the checkbox fix.
-- v0.4.6 - NEW FEATURE, UNTESTED, requested after the v0.1.21 live test:
--          (1) Item selection checklist for Batch Audit - Refresh List /
--              Select All / Unselect All buttons plus a scrollable
--              per-slot checkbox list (Checkbox/BeginChild usage is
--              untested against the live binding, so pcall-wrapped with a
--              non-scrolling fallback, same caution as the results table
--              in v0.4.3). "Batch Audit Trader" (always whole inventory)
--              replaced with "Batch Audit Selected" (only checked items -
--              defaults to everything selected on Refresh, so the old
--              behavior still works out of the box).
--          (2) groupBatchResults() collapses duplicate (item name, your
--              price) rows into one with a Count column, instead of
--              listing e.g. 14 identical "Celestial Blessing of the
--              Djinn" rows. Only splits back into separate rows when the
--              price genuinely differs between slots for the same item.
-- v0.4.5 - NEW FEATURE, UNTESTED: "Audit This Item" button next to Batch
--          Audit Trader - calls fsm.auditSingleItem(inputItemName), the
--          same undercut/cheapest check as the full scan but for just the
--          typed item, so a single item doesn't require running the whole
--          inventory. No new UI plumbing needed for the result - it fills
--          the same results table below (with one row) since
--          auditSingleItem() shares the full scan's batch machinery
--          FSM-side.
-- v0.4.4 - Companion to frogspy_price_fsm.lua v0.1.20's units bug fix:
--          yourPrice/lowest/gap in the Batch Audit table are now
--          platinum-equivalent floats instead of integers, so raw
--          tostring() would show a trailing ".0" on whole-plat prices.
--          Added fmtPrice() and applied it to those three columns (and
--          the plain-text fallback row) - whole numbers display clean,
--          fractional plat (gold/silver/copper folded in) shows up to 3
--          decimal places.
-- v0.4.3 - NEW FEATURE, UNTESTED: "Batch Audit Trader" button - calls
--          fsm.startBatchScan() to scan every occupied trader slot and
--          shows a color-coded results table (red=undercut, green=
--          cheapest, gray=no competition) with a live progress indicator
--          while scanning. Porting frogspy.py's whole-inventory report -
--          see frogspy_price_fsm.lua v0.1.19's changelog for the full
--          design story (JSON decoder turned out unnecessary; own-price
--          read confirmed live via BZW_Money0-3.Text()). The results
--          table itself is the one genuinely untested piece here - no
--          prior imgui.BeginTable usage anywhere in this file to confirm
--          the exact API surface against, so it's wrapped in a pcall with
--          a plain-text fallback if the table API doesn't behave as
--          expected. Expect a scan to take roughly 1-2s per item with
--          visible hitches, not be instant.
-- v0.4.2 - NEW FEATURE, CONFIRMED WORKING (live test 2026-07-10): "Get
--          FrogTracker Price" button - calls
--          fsm.requestFrogTrackerPrice() (Feature 2) and fills PP from the
--          30-day median once the (async) lookup completes, mirroring
--          Find Lowest Bazaar Price's "review before committing" UX -
--          doesn't auto-queue. Also prints the 7-day/90-day/1-year/
--          lifetime lowest+median windows to console for context. Values
--          are already pure platinum from frogtracker.biz, so no
--          denomination math - GP/SP/CP always zeroed. NOTE: this button
--          blocks the game for the HTTP round-trip duration (~tens of ms
--          to ~1s observed) - see frogspy_price_fsm.lua v0.1.18's
--          FT_REQUEST comment for why.
-- v0.4.1 - Belt-and-suspenders: guard against inputItemName being nil (not
--          just empty string) before calling fsm.requestLowestPrice() - a
--          live crash traced to that function receiving nil somewhere.
--          Real fix is in frogspy_price_fsm.lua v0.1.11, this is just
--          defense in depth on the calling side too.
-- v0.4.0 - NEW FEATURE, UNTESTED: "Find Lowest Bazaar Price" button - calls
--          fsm.requestLowestPrice() and fills PP/GP/SP/CP from the result
--          once the (async) search completes, for review before queueing -
--          doesn't auto-commit. See frogspy_price_fsm.lua v0.1.10's
--          changelog for the real caveats here (untested SetText() call,
--          guessed 2s search-wait, unverified BazaarSearchWnd/trader-mode
--          interaction).
-- v0.3.0 - Item Name now auto-fills from whatever's currently selected in
--          BazaarWnd (polls fsm.getSelectedSlot() ~4x/sec), so clicking an
--          item in the trader window populates the field instead of
--          needing it typed by hand. Doesn't clear the field on deselect,
--          and won't clobber manual typing for a different item unless the
--          in-game selection actually changes to something new. Also
--          resets the tracked selection after a successful queue, so
--          re-pricing the same still-selected item again re-fills the name
--          instead of leaving it blank.
-- v0.2.2 - Window title now includes the version number ("Frogspy Trader
--          Controller v0.2.2"), per standing convention going forward: all
--          of Matt's ImGui window titles should show their running version,
--          so it's visible at a glance which build is actually loaded
--          without needing to check file dates or diff source. (This
--          matters in practice - see the v0.1.6/v0.1.7 sessions where a
--          stale cached require() kept running old code silently.)
-- v0.2.1 - "Queue Price Update" did nothing (no error, no log line) when
--          Item Name was left blank - looked identical to the button being
--          broken. Added an explicit console warning in that case so a
--          blank-name click is now visibly different from a real failure.
-- v0.2.0 - Replaced the single "Total Copper" InputInt with four separate
--          Platinum/Gold/Silver/Copper fields, matching how EQ players
--          actually think about prices (and how BazaarWnd itself displays
--          them) instead of requiring a manual pp -> cp conversion in your
--          head. Concretely: typing "50" meaning 1000pp into a field
--          labeled "Total Copper" priced an item at 50 copper instead of
--          1,000,000 - this removes that failure mode entirely. The coin
--          split math itself (in frogspy_price_fsm.lua) was already
--          correct; only this input layer was wrong.
-- v0.1.x - (untracked prior to this file getting its own version header -
--          see frogspy_price_fsm.lua's CHANGELOG for the shared history):
--          settext/keystroke injection fix, module-encapsulation fix
--          (fsm.getState()/fsm.reset() instead of reading fsm.state/
--          fsm.queue directly), enqueueByName instead of enqueue for the
--          item-name input field.

local mq = require('mq')
local imgui = require('ImGui')
local fsm = require('frogspy_price_fsm')

local VERSION = '0.7.0'  -- keep in sync with the header comment above

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
                    lowest = r.lowest, gap = r.gap, rivals = r.rivals,
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
                        imgui.SameLine()
                        if imgui.Button("Select All") then
                            if occupiedSlotsCache then
                                for _, slot in ipairs(occupiedSlotsCache) do slotSelected[slot.row] = true end
                                    end
                                    end
                                    imgui.SameLine()
                                    if imgui.Button("Unselect All") then
                                        if occupiedSlotsCache then
                                            for _, slot in ipairs(occupiedSlotsCache) do slotSelected[slot.row] = false end
                                                end
                                                end

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
                                                                    imgui.SameLine()
                                                                    imgui.Text(tostring(checklistRows))
                                                                    imgui.SameLine()
                                                                    if imgui.Button("+##checklistRows") then
                                                                        checklistRows = math.min(60, checklistRows + 1)
                                                                        end

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

            if scanRunningNow then
                local cur, total = fsm.getBatchScanProgress()
                imgui.Text(string.format("Scanning... %d / %d", cur, total))
                imgui.SameLine()
                if imgui.Button("Cancel Scan") then
                    fsm.reset()
                    end
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
return ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg
end)
if not tableFlagsOk then tableFlags = 0 end

    local colCount = 7
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
            for _, w in ipairs(WINDOWS) do
                if wcfg[w.key] then
                    imgui.TableSetupColumn(w.label .. " Low")
                    imgui.TableSetupColumn(w.label .. " Med")
                    end
                    end
                    imgui.TableHeadersRow()

            for _, r in ipairs(groupedResults) do
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

                            -- v0.5.0: update the transition tracker at the very end of the
                            -- Batch Audit section, after both the running-state UI branch and
                            -- the completion-detection log write above have already used this
                            -- frame's scanRunningNow value.
                            batchWasRunning = scanRunningNow

                            -- Diagnostic
                            if imgui.Button("Force FSM Reset") then
                                fsm.reset()
                                end
                                end
                                imgui.End()
                                end

                                -- Bind the ImGui render loop
                                mq.imgui.init('FrogspyUI', renderGUI)

                                -- Main execution loop
                                while openGUI do
                                    fsm.tick()     -- Drive the FSM forward
                                    mq.delay(10)   -- Prevent CPU locking
                                    end