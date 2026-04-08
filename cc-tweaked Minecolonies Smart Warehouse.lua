local colony = peripheral.find("colony_integrator")
local bridge = peripheral.find("me_bridge")
local warehouse = peripheral.find("minecolonies:warehouse")

-- Tenta encontrar um barril ou baú para servir de buffer
local buffer = peripheral.find("minecraft:barrel") or peripheral.find("minecraft:chest") or peripheral.find("minecraft:shulker_box")
local bufferName = nil

if buffer then
    bufferName = peripheral.getName(buffer)
else
    term.setTextColour(colors.red)
    print("ERRO: Nenhum 'Buffer' (Barril ou Bau) encontrado!")
    print("Conecte um Barril ou Bau ao computador e reinicie.")
    term.setTextColour(colors.white)
    error("Falta periférico: Buffer")
end

local monitor = peripheral.find("monitor")
local warehousCleanIn = 0

-- Tabela para armazenar o estado das solicitações para o monitor
local displayState = {}
local recentLogs = {}
local colonyOverview = {}

local function addLog(msg)

local function addLog(msg)
    local time = os.date("%H:%M")
    local shortMsg = msg:gsub("minecraft:", ""):gsub("minecolonies:", "")
    table.insert(recentLogs, 1, "[" .. time .. "] " .. shortMsg) -- Adiciona no topo
    if #recentLogs > 6 then table.remove(recentLogs) end -- Mantém os últimos 6
end

local function updateMonitor()
    if not monitor then return end
    
    local w, h = monitor.getSize()
    
    -- Desenha em um buffer mental primeiro (evita tela preta)
    monitor.setTextScale(0.5)
    
    -- Cabeçalho Principal com Overview da Colônia
    monitor.setCursorPos(1, 1)
    monitor.setBackgroundColor(colors.blue)
    monitor.setTextColor(colors.white)
    monitor.clearLine()
    local overviewLine = string.format(" %s | Lvl: %d | Cids: %d/%d | Hap: %.1f", 
        colonyOverview.name or "Colonia", 
        colonyOverview.level or 0,
        colonyOverview.cits or 0,
        colonyOverview.maxcits or 0,
        colonyOverview.happiness or 0 or 0)
    monitor.write(string.sub(overviewLine, 1, w))
    
    -- Sub-cabeçalho
    monitor.setCursorPos(1, 2)
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.white)
    monitor.clearLine()
    monitor.write(" --- LOGISTICS DASHBOARD --- ")

    local activeItems = {}
    local missingItems = {}
    
    -- Separa os itens por categoria
    for name, data in pairs(displayState) do
        if data.status == "Missing" then
            table.insert(missingItems, {name = name, displayName = data.displayName, count = data.count})
        else
            table.insert(activeItems, {name = name, displayName = data.displayName, count = data.count, status = data.status})
        end
    end

    local line = 3
    monitor.setBackgroundColor(colors.black)
    
    -- Seção de Ativos (OK / Crafting) – Limpa as linhas conforme escreve
    if #activeItems > 0 then
        monitor.setTextColor(colors.yellow)
        monitor.setCursorPos(1, line)
        monitor.clearLine()
        monitor.write("-- ATIVO / CRAFTING --")
        line = line + 1

        for _, it in ipairs(activeItems) do
            if line > h then break end
            monitor.setCursorPos(1, line)
            monitor.clearLine()
            monitor.setTextColor(it.status == "Crafting" and colors.blue or colors.green)
            
            local nameToDraw = string.sub(it.displayName or it.name, 1, 14)
            monitor.write(string.format("%-14s x%2d [%s]", nameToDraw, it.count, it.status))
            line = line + 1
        end
    else
        -- Se não há nada ativo, limpa uma linha
        monitor.setCursorPos(1, line)
        monitor.clearLine()
        line = line + 1
    end

    -- Seção de Faltando (RED ALERT)
    if #missingItems > 0 and line <= h then
        line = line + 1
        if line <= h then
            monitor.setCursorPos(1, line)
            monitor.setBackgroundColor(colors.red)
            monitor.setTextColor(colors.white)
            monitor.clearLine()
            monitor.write(" !!! ACAO MANUAL REQ. !!! ")
            monitor.setBackgroundColor(colors.black)
            line = line + 1
            
            for _, it in ipairs(missingItems) do
                if line > h then break end
                monitor.setCursorPos(1, line)
                monitor.clearLine()
                monitor.setTextColor(colors.red)
                local nameToDraw = string.sub(it.displayName or it.name, 1, 14)
                monitor.write(string.format("- %-14s x%d", nameToDraw, it.count))
                line = line + 1
            end
        end
    end

    -- Seção de Histórico Recente (Log)
    if line <= h - 1 then
        line = line + 1
        monitor.setCursorPos(1, line)
        monitor.setBackgroundColor(colors.gray)
        monitor.setTextColor(colors.white)
        monitor.clearLine()
        monitor.write(" --- HISTORICO RECENTE --- ")
        monitor.setBackgroundColor(colors.black)
        line = line + 1
        
        monitor.setTextColor(colors.lightGray)
        for _, log in ipairs(recentLogs) do
            if line > h then break end
            monitor.setCursorPos(1, line)
            monitor.clearLine()
            monitor.write(string.sub(log, 1, w))
            line = line + 1
        end
    end

    -- Limpa o resto do monitor se sobrar espaço
    while line <= h do
        monitor.setCursorPos(1, line)
        monitor.clearLine()
        line = line + 1
    end
end

-- Função auxiliar para verificar se algo está craftando (compatibilidade de versões)
local function checkIsCrafting(item)
    if bridge.isItemCrafting then
        return bridge.isItemCrafting(item)
    elseif bridge.isCrafting then
        -- Tenta usar isCrafting como fallback
        local success, result = pcall(bridge.isCrafting, item.name or item)
        return success and result
    end
    return false
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
    -- Atualiza os dados da colônia
    colonyOverview = {
        name = colony.getColonyName(),
        level = colony.getColonyLevel(),
        cits = colony.getAmountOfCitizens(),
        maxcits = colony.getMaxAmountOfCitizens(),
        happiness = colony.getHappiness()
    }

    displayState = {} -- Limpa os dados de status para o novo ciclo
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
                            if not checkIsCrafting({ ["name"] = hutNeed.item.name }) then
                                print("\tME: Tentando craftar x" .. missing, hutNeed.item.name)
                                local success = bridge.craftItem({ ["name"] = hutNeed.item.name, ["count"] = missing })
                                if not success then
                                    term.setTextColour(colours.red)
                                    print("\tME: Bloco " .. hutNeed.item.name .. " não foi possível craftar")
                                    term.setTextColour(colours.white)
                                    local cleanerName = getCleanName(hutNeed.item)
                                    displayState[hutNeed.item.name] = {count = missing, status = "Missing", displayName = cleanerName}
                                    addLog("FALHA: " .. cleanerName)
                                else
                                    local cleanerName = getCleanName(hutNeed.item)
                                    displayState[hutNeed.item.name] = {count = missing, status = "Crafting", displayName = cleanerName}
                                    addLog("CRAFT: " .. missing .. "x " .. cleanerName)
                                end
                            else
                                local cleanerName = getCleanName(hutNeed.item)
                                print("\tME: Crafting em progresso: " .. hutNeed.item.name)
                                displayState[hutNeed.item.name] = {count = missing, status = "Crafting", displayName = cleanerName}
                            end
                        end

                        -- Se tiver algo no estoque (mesmo que parcial), retira
                        if available > 0 then
                            local toExtract = math.min(available, pullAmount)
                            print("\tME: x" .. available, hutNeed.item.name)

                            term.setTextColour(colours.blue)
                            print("\tPulling: x", toExtract, hutNeed.item.name)
                            term.setTextColour(colours.white)
                            
                            local cleanerName = getCleanName(hutNeed.item)
                            displayState[hutNeed.item.name] = displayState[hutNeed.item.name] or {count = toExtract, status = "OK", displayName = cleanerName}
                            addLog("OK: " .. toExtract .. "x " .. cleanerName)

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
                if not checkIsCrafting({ ["name"] = item.name }) then
                    print("\tReq: Tentando craftar x" .. missing, item.name)
                    local success = bridge.craftItem({ ["name"] = item.name, ["count"] = missing })
                    if not success then
                        term.setTextColour(colours.red)
                        print("\tReq: Bloco " .. item.name .. " não foi possível craftar")
                        term.setTextColour(colours.white)
                        local cleanerName = getCleanName(item)
                        displayState[item.name] = {count = missing, status = "Missing", displayName = cleanerName}
                        addLog("FALHA: " .. cleanerName)
                    else
                        local cleanerName = getCleanName(item)
                        displayState[item.name] = {count = missing, status = "Crafting", displayName = cleanerName}
                        addLog("CRAFT: " .. missing .. "x " .. cleanerName)
                    end
                else
                    local cleanerName = getCleanName(item)
                    displayState[item.name] = {count = missing, status = "Crafting", displayName = cleanerName}
                end
            end

            if available > 0 then
                local toExtract = math.min(available, pullAmount)
                print("\tReq: ME has x" .. available)

                term.setTextColour(colours.blue)
                print("\tPulling: x" .. toExtract, item.name)
                term.setTextColour(colours.white)
                
                local cleanerName = getCleanName(item)
                displayState[item.name] = displayState[item.name] or {count = toExtract, status = "OK", displayName = cleanerName}
                addLog("REQ OK: " .. cleanerName)

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
