local spawnPoints = {}
local autoSpawnEnabled = false
local autoSpawnCallback

AddEventHandler('getMapDirectives', function(addDirective)
    addDirective('spawnpoint', function(state, model)
        return function(opts)
            local success, error = pcall(function()
                local x, y, z = opts.x or opts[1], opts.y or opts[2], opts.z or opts[3]
                local heading = opts.heading or 0
                x, y, z = x + 0.0001, y + 0.0001, z + 0.0001
                heading = heading + 0.01
                model = tonumber(model) or GetHashKey(model)
                addSpawnPoint({x = x, y = y, z = z, heading = heading, model = model})
                state.add('xyz', {x, y, z})
                state.add('model', model)
            end)
            if not success then
                print("Error adding spawn point: " .. error)
            end
        end
    end, 
    function(state, arg)
        for i, sp in ipairs(spawnPoints) do
            if sp.x == state.xyz[1] and sp.y == state.xyz[2] and sp.z == state.xyz[3] and sp.model == state.model then
                table.remove(spawnPoints, i)
                break
            end
        end
    end)
end)

function loadSpawns(spawnString)
    local data = json.decode(spawnString)
    if not data.spawns then
        error("no 'spawns' in JSON data")
    end
    for i, spawn in ipairs(data.spawns) do
        addSpawnPoint(spawn)
    end
end

local spawnNum = 1

function addSpawnPoint(spawn)
    if not tonumber(spawn.x) or not tonumber(spawn.y) or not tonumber(spawn.z) then
        error("invalid spawn position")
    end
    if not tonumber(spawn.heading) then
        error("invalid spawn heading")
    end
    local model = spawn.model
    if not tonumber(spawn.model) then
        model = GetHashKey(spawn.model)
    end
    if not IsModelInCdimage(model) then
        error("invalid spawn model")
    end
    spawn.model = model
    spawn.idx = spawnNum
    spawnNum = spawnNum + 1
    table.insert(spawnPoints, spawn)
    return spawn.idx
end

function removeSpawnPoint(spawn)
    for i = 1, #spawnPoints do
        if spawnPoints[i].idx == spawn then
            table.remove(spawnPoints, i)
            return
        end
    end
end

function setAutoSpawn(enabled)
    autoSpawnEnabled = enabled
end

function setAutoSpawnCallback(cb)
    autoSpawnCallback = cb
    autoSpawnEnabled = true
end

local function freezePlayer(playerId, freeze)
    local playerPed = GetPlayerPed(playerId)
    SetPlayerControl(playerId, not freeze, false)
    SetEntityVisible(playerPed, not freeze)
    SetEntityCollision(playerPed, not freeze)
    FreezeEntityPosition(playerPed, freeze)
    SetPlayerInvincible(playerId, freeze)
    if freeze then
        if not IsPedFatallyInjured(playerPed) then
            ClearPedTasksImmediately(playerPed)
        end
    end
end

function loadScene(x, y, z)
    if not NewLoadSceneStart then
        return
    end
    NewLoadSceneStart(x, y, z, 0.0, 0.0, 0.0, 20.0, 0)
    while IsNewLoadSceneActive() do
        networkTimer = GetNetworkTimer()
        NetworkUpdateLoadScene()
    end
end

local spawnLock = false

function spawnPlayer(spawnIdx, cb)
    if spawnLock then return end
    spawnLock = true
    Citizen.CreateThread(function()
        local spawn = type(spawnIdx) == 'table' and spawnIdx or spawnPoints[spawnIdx or GetRandomIntInRange(1, #spawnPoints)]
        if not spawn then
            print("Invalid spawn index.")
            spawnLock = false
            return
        end
        if not spawn.skipFade then
            DoScreenFadeOut(500)
            Citizen.Wait(500)
        end
        freezePlayer(PlayerId(), true)
        if spawn.model then
            RequestModel(spawn.model)
            while not HasModelLoaded(spawn.model) do Citizen.Wait(1) end
            SetPlayerModel(PlayerId(), spawn.model)
            SetModelAsNoLongerNeeded(spawn.model)
        end
        RequestCollisionAtCoord(spawn.x, spawn.y, spawn.z)
        SetEntityCoordsNoOffset(PlayerPedId(), spawn.x, spawn.y, spawn.z, false, false, false, true)
        NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, spawn.heading, true, false)
        ClearPedTasksImmediately(PlayerPedId())
        RemoveAllPedWeapons(PlayerPedId(), true)
        ClearPlayerWantedLevel(PlayerId())
        local endTime = GetGameTimer() + 5000
        while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < endTime do
            Citizen.Wait(0)
        end
        ShutdownLoadingScreen()
        if IsScreenFadedOut() then
            DoScreenFadeIn(500)
            Citizen.Wait(500)
        end
        freezePlayer(PlayerId(), false)
        TriggerEvent('playerSpawned', spawn)
         if cb then cb(spawn) end
        spawnLock = false
    end)
end

local respawnForced
local diedAt

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(50)
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= -1 then
            if autoSpawnEnabled then
                if NetworkIsPlayerActive(PlayerId()) then
                    if (diedAt and (math.abs(GetTimeDifference(GetGameTimer(), diedAt)) > 2000)) or respawnForced then
                        if autoSpawnCallback then
                            autoSpawnCallback()
                        else
                            spawnPlayer()
                        end
                        respawnForced = false
                    end
                end
            end
            if IsEntityDead(playerPed) then
                if not diedAt then
                    diedAt = GetGameTimer()
                end
            else
                diedAt = nil
            end
        end
    end
end)

function forceRespawn()
    spawnLock = false
    respawnForced = true
end

exports('spawnPlayer', spawnPlayer)
exports('addSpawnPoint', addSpawnPoint)
exports('removeSpawnPoint', removeSpawnPoint)
exports('loadSpawns', loadSpawns)
exports('setAutoSpawn', setAutoSpawn)
exports('setAutoSpawnCallback', setAutoSpawnCallback)
exports('forceRespawn', forceRespawn)
