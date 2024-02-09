local spawnPoints={}
local autoSpawnEnabled=false
local autoSpawnCallback
AddEventHandler('getMapDirectives',function(addDirective)
    addDirective('spawnpoint',function(state,model)
        return function(options)
            local coords,heading=parseSpawnOptions(options)
            addSpawnPoint({
                x=coords.x, y=coords.y, z=coords.z,
                heading=heading,
                model=model
            })
            state.add('coords',coords)
            state.add('model',ensureModelHash(model))
        end
    end,removeSpawnPointByState)
end)
function parseSpawnOptions(options)
    local coords={x=0, y=0, z=0}
    local heading=0
    if options.x and options.y and options.z then
        coords={x=options.x+0.0001, y=options.y+0.0001, z=options.z+0.0001}
    else
        coords={x=options[1]+0.0001, y=options[2]+0.0001, z=options[3]+0.0001}
    end
    heading=options.heading and(options.heading+0.01)or 0
    return coords,heading
end
function ensureModelHash(model)
    if not tonumber(model) then
        return GetHashKey(model, _r)
    end
    return model
end
function removeSpawnPointByState(state,arg)
    for i,sp in ipairs(spawnPoints)do
        local coords=state.coords
        if sp.x==coords.x and sp.y==coords.y and sp.z==coords.z and sp.model==state.model then
            table.remove(spawnPoints,i)
            break
        end
    end
end
function loadSpawns(spawnString)
    local data=json.decode(spawnString)
    assert(data.spawns,"No 'spawns' field in JSON data")
    for _,spawn in ipairs(data.spawns)do
        addSpawnPoint(validateSpawnPoint(spawn))
    end
end
local spawnNum=1
function addSpawnPoint(spawn)
    validateSpawnPoint(spawn)
    spawn.idx=#spawnPoints+1
    table.insert(spawnPoints,spawn)
    return spawn.idx
end
function validateSpawnPoint(spawn)
    assert(tonumber(spawn.x)and tonumber(spawn.y)and tonumber(spawn.z),"Invalid spawn position")
    assert(tonumber(spawn.heading),"Invalid spawn heading")
    local model=ensureModelHash(spawn.model)
    assert(IsModelInCdimage(model),"Invalid spawn model")
    spawn.model=model
    return spawn
end
function removeSpawnPoint(spawn)
    for i=1,#spawnPoints do
        if spawnPoints[i].idx==spawn then
            table.remove(spawnPoints,i)
            return
        end
    end
end
function setAutoSpawn(enabled)
    autoSpawnEnabled=enabled
end
function setAutoSpawnCallback(cb)
    autoSpawnCallback=cb
    autoSpawnEnabled=true
end
local function freezePlayer(id,freeze)
    local player=id
    SetPlayerControl(player,not freeze,false)
    local ped=GetPlayerPed(player)
    if not freeze then
        if not IsEntityVisible(ped)then
            SetEntityVisible(ped,true)
        end
        if not IsPedInAnyVehicle(ped)then
            SetEntityCollision(ped,true)
        end
        FreezeEntityPosition(ped,false)
        SetPlayerInvincible(player,false)
    else
        if IsEntityVisible(ped)then
            SetEntityVisible(ped,false)
        end
        SetEntityCollision(ped,false)
        FreezeEntityPosition(ped,true)
        SetPlayerInvincible(player,true)
        if not IsPedFatallyInjured(ped)then
            ClearPedTasksImmediately(ped)
        end
    end
end
function loadScene(x,y,z)
    if not NewLoadSceneStart then
        return
    end
    NewLoadSceneStart(x,y,z,0.0,0.0,0.0,20.0,0)
    while IsNewLoadSceneActive()do
        networkTimer=GetNetworkTimer()
        NetworkUpdateLoadScene()
    end
end
local spawnLock=false
function spawnPlayer(spawnIdx,callback)
    if spawnLock then
        print("Spawn attempt blocked due to ongoing spawn process.")
        return
    end
    spawnLock=true
    Citizen.CreateThread(function()
        if not spawnIdx then
            spawnIdx=math.random(1,#spawnPoints)
        end
        local spawn=validateSpawnPoint(spawnIdx)
        if not spawn then
            print("Invalid spawn point specified.")
            spawnLock=false
            return
        end
        if not spawn.skipFade then
            performScreenFadeOut()
        end
        prepareModel(spawn.model,function()
            respawnPlayerAtSpawnPoint(spawn)
            postSpawnActions(spawn,callback)
        end)
    end)
end
function validateSpawnPoint(spawnIdx)
    local spawn=type(spawnIdx)=='table'and spawnIdx or spawnPoints[spawnIdx]
    if spawn and type(spawn)=='table'then
        spawn.x,spawn.y,spawn.z=spawn.x+0.0001,spawn.y+0.0001,spawn.z+0.0001
        spawn.heading=spawn.heading or 0
        return spawn
    end
end
function performScreenFadeOut()
    ShutdownLoadingScreen()
    DoScreenFadeOut(500)
    while not IsScreenFadedOut()do
        Citizen.Wait(0)
    end
end
function prepareModel(model,onLoad)
    if model then
        RequestModel(model)
        while not HasModelLoaded(model)do
            Citizen.Wait(0)
        end
        onLoad()
        SetModelAsNoLongerNeeded(model)
    else
        onLoad()
    end
end
function respawnPlayerAtSpawnPoint(spawn)
    local playerPed=PlayerPedId()
    RequestCollisionAtCoord(spawn.x,spawn.y,spawn.z)
    SetEntityCoordsNoOffset(playerPed,spawn.x,spawn.y,spawn.z,false,false,false,true)
    NetworkResurrectLocalPlayer(spawn.x,spawn.y,spawn.z,spawn.heading,true,false)
    ClearPedTasksImmediately(playerPed)
    RemoveAllPedWeapons(playerPed,true)
    ClearPlayerWantedLevel(PlayerId())
end
function postSpawnActions(spawn,callback)
    waitForCollisionLoading(PlayerPedId())
    if IsScreenFadedOut()then
        DoScreenFadeIn(500)
    end
    freezePlayer(PlayerId(),false)
    if callback then callback(spawn)end
    TriggerEvent('playerSpawned',spawn)
    spawnLock=false
end
function waitForCollisionLoading(ped)
    local startTime=GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped)and(GetGameTimer()-startTime)<5000 do
        Citizen.Wait(0)
    end
end
local respawnForced
local diedAt
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(50)
        local playerPed=PlayerPedId()
        if playerPed and playerPed~=-1 then
            if autoSpawnEnabled then
                if NetworkIsPlayerActive(PlayerId())then
                    if(diedAt and(math.abs(GetTimeDifference(GetGameTimer(),diedAt))>2000))or respawnForced then
                        if autoSpawnCallback then
                            autoSpawnCallback()
                        else
                            spawnPlayer()
                        end
                        respawnForced=false
                    end
                end
            end
            if IsEntityDead(playerPed)then
                if not diedAt then
                    diedAt=GetGameTimer()
                end
            else
                diedAt=nil
            end
        end
    end
end)
function forceRespawn()
    spawnLock=false
    respawnForced=true
end
exports('spawnPlayer',spawnPlayer)
exports('addSpawnPoint',addSpawnPoint)
exports('removeSpawnPoint',removeSpawnPoint)
exports('loadSpawns',loadSpawns)
exports('setAutoSpawn',setAutoSpawn)
exports('setAutoSpawnCallback',setAutoSpawnCallback)
exports('forceRespawn',forceRespawn)
