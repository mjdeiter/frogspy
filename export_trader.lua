-- export_trader.lua
-- Run with: /lua run export_trader
-- Exports Kreigar's trader inventory to kreigar_inventory.txt for bazaar_checker.py
--
-- REQUIREMENTS:
--   1. Be in the bazaar zone
--   2. Open the Bazaar Search Window (/bazaar) BEFORE running this script
--   3. MQ2Bzsrch will be loaded automatically if not already loaded

local mq = require('mq')

local OUTPUT_FILE = 'C:\\Users\\mjdei\\Desktop\\kreigar_inventory.txt'
local TRADER_NAME = mq.TLO.Me.Name()

printf('\n[ExportTrader] ========================================')
printf('[ExportTrader] Trader Inventory Export for %s', TRADER_NAME)
printf('[ExportTrader] ========================================')

-- Ensure MQ2Bzsrch is loaded
local pluginLoaded = mq.TLO.Plugin('MQ2Bzsrch').IsLoaded()
if not pluginLoaded then
    printf('[ExportTrader] Loading MQ2Bzsrch...')
    mq.cmd('/plugin MQ2Bzsrch')
    mq.delay(2000)
    pluginLoaded = mq.TLO.Plugin('MQ2Bzsrch').IsLoaded()
    if not pluginLoaded then
        printf('[ExportTrader] ERROR: Failed to load MQ2Bzsrch. Aborting.')
        return
    end
    printf('[ExportTrader] MQ2Bzsrch loaded.')
end

-- Verify bazaar window is open (must be open for bzsrch to work on Lazarus)
if not mq.TLO.Window('BazaarSearchWnd').Open() then
    printf('[ExportTrader] ERROR: Bazaar Search Window is not open!')
    printf('[ExportTrader] Type /bazaar to open it, then re-run this script.')
    return
end

-- Reset any previous search results
mq.cmd('/breset')
mq.delay(500)

-- Run search filtered to this trader
printf('[ExportTrader] Searching bazaar for trader: %s...', TRADER_NAME)
mq.cmdf('/bzsrch trader %s', TRADER_NAME)

-- Wait for search to complete
local timeout = 10000
local elapsed = 0
local interval = 250
while not mq.TLO.Bazaar.Done() and elapsed < timeout do
    mq.delay(interval)
    elapsed = elapsed + interval
end

if not mq.TLO.Bazaar.Done() then
    printf('[ExportTrader] ERROR: Search timed out after %ds.', timeout / 1000)
    printf('[ExportTrader] Make sure the Bazaar Search Window is open and try again.')
    return
end

local count = mq.TLO.Bazaar.Count()
printf('[ExportTrader] Search complete. Found %d item(s).', count)

if count == 0 then
    printf('[ExportTrader] No items found for %s. Are you in trader mode?', TRADER_NAME)
    return
end

-- Write results to file
-- MQ2Bzsrch Price is in copper (PGSC): 1 plat = 1000 copper
-- Round to nearest plat so prices like 1999cp -> 2pp not 1pp
local file, err = io.open(OUTPUT_FILE, 'w')
if not file then
    printf('[ExportTrader] ERROR: Could not open output file: %s', tostring(err))
    return
end

local exported = 0
for i = 1, count do
    local item = mq.TLO.Bazaar.Item(i)
    local name  = item.Name()
    local price = item.Price()  -- in copper
    if name and price then
        local plat = math.floor((price + 500) / 1000)  -- round to nearest plat
        if plat < 1 then plat = 1 end                  -- minimum 1pp
        file:write(string.format('%s|%d\n', name, plat))
        printf('[ExportTrader]   %-40s %d pp', name, plat)
        exported = exported + 1
    end
end

file:close()

printf('\n[ExportTrader] Exported %d item(s) to:', exported)
printf('[ExportTrader]   %s', OUTPUT_FILE)
printf('[ExportTrader] Now run:')
printf('[ExportTrader]   python bazaar_checker.py --inventory "%s"', OUTPUT_FILE)
printf('[ExportTrader] ========================================\n')
