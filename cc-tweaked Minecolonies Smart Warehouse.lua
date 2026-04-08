local colony = peripheral.find("colony_integrator")
local bridge = peripheral.find("me_bridge")
local warehouse = peripheral.find("minecolonies:warehouse")

local buffer = peripheral.find("minecraft:barrel")
local bufferName = peripheral.getName(buffer)

local monitor = peripheral.find("monitor")
local warehousCleanIn = 0

-- Tabela para armazenar o estado das solicitações para o monitor
local displayState = {}

local function updateMonitor()
    if not monitor then return end
    monitor.setTextScale(0.5)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    
    local w, h = monitor.getSize()
    
    -- Cabeçalho Estilizado
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(1, 1)
    monitor.clearLine()
    local title = " SMART WAREHOUSE STATUS "
    monitor.setCursorPos(math.floor((w - #title)/2) + 1, 1)
    monitor.write(title)
    
    -- Cabeçalho da Tabela
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.yellow)
    monitor.setCursorPos(1, 2)
    monitor.write(string.format("%-14s | %3s | %s", "Item", "Qt", "Status"))
    monitor.setCursorPos(1, 3)
    monitor.write(string.rep("-", w))
    
    local line = 4
    for name, data in pairs(displayState) do
        if line > h then break end
        monitor.setCursorPos(1, line)
        
        if data.status == "Crafting" then
            monitor.setTextColor(colors.blue)
        elseif data.status == "Missing" then
            monitor.setTextColor(colors.red)
        else
            monitor.setTextColor(colors.green)
        end
        
        local shortName = name:gsub("minecraft:", ""):gsub("minecolonies:", "")
        shortName = string.sub(shortName, 1, 14)
        
        monitor.write(string.format("%-14s | %3d | %s", shortName, data.count, data.status))
        line = line + 1
    end
end

-- Função para encontrar cabanas de construtor automaticamente via API
local function findBuilderHuts()
    print("Scanning for Builder Huts...")
    local allBuildings = colony.getBuildings()
    local huts = {}

    for _, building in ipairs(allBuildings) do
        -- Filtra apenas prédios do tipo 'builder'
        if building.type == "builder" then
            table.insert(huts, {
                ["name"] = building.name,
                ["position"] = building.location
            })
        end
    end

    print("Found " .. #huts .. " Builder Huts. Items will be sent to Warehouse.")
    return huts
end

builderHuts = findBuilderHuts()

function logicLoop()
    displayState = {} -- Limpa os dados para o novo ciclo
    updateMonitor()
    --Clean warehouse
    if warehousCleanIn <= 0 then
        warehousCleanIn = 120

        print("Running warehouse clean")

        local warehouseSize = warehouse.size()

        print("\tWarehouse has", warehouseSize, "slots")

        for slot=1, warehouseSize do
            local invSlot = warehouse.getItemDetail(slot)

            if invSlot ~= nil then
                print('\tSticking', invSlot.name, 'into buffer')

                warehouse.pushItems(bufferName, slot)

                print('\tMoving from buffer to ME')

                bridge.importItem({ name= invSlot.name }, "right")
            end
        end
    else
        warehousCleanIn = warehousCleanIn - 1
    end

    local chestFree = warehouse.size() - #warehouse.list()
    local chestUsed = 0

    print('Indexing smart warehouse inventory')

    local warehouseInventory = {}

    for slot, item in pairs(warehouse.list()) do
        print('Warehouse has: x' .. item.count, item.name)

        warehouseInventory[item.name] = item.count
    end

    print('Chest has slots', chestFree)

    -- BUILDER HUT ITEM GRABBING
    for hutNum, hut in pairs(builderHuts) do
        local hutNeeds = colony.getBuilderResources(hut.position)

        print("Builder hut scan for", hut.name)

        if #hutNeeds > 0 then
            if chestFree > 0 then
                for i, hutNeed in ipairs(hutNeeds) do
                    local warehouseAmount = warehouseInventory[hutNeed.item.name] or 0

                    local pullAmount = (hutNeed.needs - hutNeed.available) - warehouseAmount

                    print("\t", hutNeed.needs .. '/' .. hutNeed.available .. ', x' .. pullAmount, hutNeed.item.name)

                    if pullAmount > 0 then
                        local meItem = bridge.getItem({ ["name"] = hutNeed.item.name })
                        local available = (meItem and meItem.count) or 0

                        -- Se não houver estoque suficiente, tenta craftar
                        if available < pullAmount then
                            local missing = pullAmount - available
                            if not bridge.isItemCrafting({ ["name"] = hutNeed.item.name }) then
                                print("\tME: Tentando craftar x" .. missing, hutNeed.item.name)
                                local success = bridge.craftItem({ ["name"] = hutNeed.item.name, ["count"] = missing })
                                if not success then
                                    term.setTextColour(colours.red)
                                    print("\tME: Bloco " .. hutNeed.item.name .. " não foi possível craftar")
                                    term.setTextColour(colours.white)
                                    displayState[hutNeed.item.name] = {count = missing, status = "Missing"}
                                else
                                    displayState[hutNeed.item.name] = {count = missing, status = "Crafting"}
                                end
                            else
                                print("\tME: Crafting em progresso: " .. hutNeed.item.name)
                                displayState[hutNeed.item.name] = {count = missing, status = "Crafting"}
                            end
                        end

                        -- Se tiver algo no estoque (mesmo que parcial), retira
                        if available > 0 then
                            local toExtract = math.min(available, pullAmount)
                            print("\tME: x" .. available, hutNeed.item.name)

                            term.setTextColour(colours.blue)
                            print("\tPulling: x", toExtract, hutNeed.item.name)
                            term.setTextColour(colours.white)
                            displayState[hutNeed.item.name] = displayState[hutNeed.item.name] or {count = toExtract, status = "OK"}

                            bridge.exportItem({ ["name"] = hutNeed.item.name, ["count"] = toExtract}, "right")

                            -- Envia para o Armazém em vez da cabana direta
                            buffer.pushItems(peripheral.getName(warehouse), 1)

                            sleep(1)

                            chestUsed = chestUsed + 1
                            if chestUsed >= chestFree then
                                term.setTextColour(colours.red)
                                print("\tWarehouse: OUT OF STORAGE")
                                term.setTextColour(colours.white)

                                break
                            end
                        end
                    else
                        term.setTextColour(colours.orange)
                        print("\tHut: Has enough", hutNeed.item.name)
                        term.setTextColour(colours.white)
                    end
                end
            else
                term.setTextColour(colours.red)
                print("\tWarehouse: OUT OF STORAGE")
                term.setTextColour(colours.white)
            end
        else
            term.setTextColour(colours.green)
            print("\tHut: Has no requests")
            term.setTextColour(colours.white)
        end

        sleep(1)
    end

    print()
    print("Checking for citzen requests")

    -- CITIZEN REQUEST GRABBER
    local requests = colony.getRequests()

    for reqPos, req in pairs(requests) do
        print("Req:", req.target, "x" .. req.count, req.name)

        local itemFound = false

        for itemPos, item in pairs(req.items) do
            if warehouseInventory[item.name] then
                print("\tReq: Warehouse has", warehouseInventory[item.name])

                itemFound = true

                break
            end

            local meItem = bridge.getItem({ ["name"] = item.name })
            local available = (meItem and meItem.count) or 0
            local pullAmount = item.minCount or 1

            if available < pullAmount then
                local missing = pullAmount - available
                if not bridge.isItemCrafting({ ["name"] = item.name }) then
                    print("\tReq: Tentando craftar x" .. missing, item.name)
                    local success = bridge.craftItem({ ["name"] = item.name, ["count"] = missing })
                    if not success then
                        term.setTextColour(colours.red)
                        print("\tReq: Bloco " .. item.name .. " não foi possível craftar")
                        term.setTextColour(colours.white)
                        displayState[item.name] = {count = missing, status = "Missing"}
                    else
                        displayState[item.name] = {count = missing, status = "Crafting"}
                    end
                else
                    displayState[item.name] = {count = missing, status = "Crafting"}
                end
            end

            if available > 0 then
                local toExtract = math.min(available, pullAmount)
                print("\tReq: ME has x" .. available)

                term.setTextColour(colours.blue)
                print("\tPulling: x" .. toExtract, item.name)
                term.setTextColour(colours.white)
                displayState[item.name] = displayState[item.name] or {count = toExtract, status = "OK"}

                bridge.exportItem({ ["name"] = item.name, ["count"] = toExtract }, "right")

                buffer.pushItems(peripheral.getName(warehouse), 1)

                itemFound = true

                break
            end
        end

        if itemFound == false then
            term.setTextColour(colours.red)
            print("\tReq: No item", req.name)
            term.setTextColour(colours.white)
        end

        sleep(1)
    end

    term.setTextColour(colours.grey)
    print('System is sleeping for 60 seconds...')
    term.setTextColour(colours.white)
end

while true do
    local success, error = pcall(logicLoop)

    if error then
        print(error)
    end

    sleep(60)
end
