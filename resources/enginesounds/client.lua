local ENGINE_SOUNDS = {
    '12vcummins', '64powerstroke', '488sound',
    'a80ffeng', 'alfa690t', 'amg1eng',
    'aq02coyotef150', 'aq2jzgterace', 'aq06nhonc30a',
    'aq07powerstroke67', 'aq10nisvr38dett', 'aq22honb18c',
    'aqls7raceswap', 'aqm275amg', 'aqtoy2jzstock',
    'argento', 'ariant', 'aston59v12',
    'audi7a', 'audicrdbakra', 'audiea855',
    'audiwx', 'audr8tteng', 'aventadorv12',
    'avesvv12', 'b58b30', 'bgw16',
    'bmws1krreng', 'bmws55', 'bnr34ffeng',
    'brabus850', 'camls3v8', 'cammedcharger',
    'chargertrackhawkhemiv8', 'chevydmaxeng', 'chevroletlt4',
    'cummins5924v', 'cvpiv8', 'cw2019',
    'czr1eng', 'demonengine', 'demonv8',
    'dodgehemihellcat', 'ea825',
    'ea888', 'ecoboostv6', 'elegyx',
    'evoixsound', 'f10m5', 'f20c',
    'f40v8', 'f50gteng', 'f113',
    'f136', 'ferrarif12', 'ferrarif140fe',
    'fordvoodoo', 'ftypesound', 'gallardov10',
    'gresleyh', 'gt3flat6', 'gt3rstun',
    'hemisound', 'italianttv10', 'k20a',
    'kc24r33gts', 'kc28sr180', 'kc63fordgt2gen',
    'lambov10', 'lamcountach', 'lamveneng',
    'lfasound', 'lg14c6vette', 'lg21focusrs',
    'lg50ftypev8', 'lg53fer488capri', 'lg57mustangtv8',
    'lg67koagerars', 'lg81hcredeye', 'lgcy01chargerv8',
    'lgcy04murciv12', 'm5cracklemod', 'm158huayra',
    'm297zonda', 'm840trsenna', 'mbnzc63eng',
    'mcp1eng', 'mercedesm113', 'mercedesm155',
    'mercm177', 'mercm279', 'ml720v8eng',
    'monroec', 'mrtasty', 'musv8',
    'n4g63t', 'n55b30t0', 'nfsv8',
    'nisgtr35', 'npbfs', 'npcul',
    'npolchar', 'nsr2teng', 'p60b40',
    'porsche57v10', 'predatorv8', 'r34sound',
    'r35sound', 'rb26dett', 'rb28dett',
    'rotary7', 'rx7bpeng', 's15sound',
    's54b32', 's55b30', 's63b44',
    's85b50', 'saleen54v8sc', 'sentinelsg4',
    'shonen', 'skart', 'subaruej20',
    'superchargerdemonv8', 'suzukigsxr1k', 'ta006bmws65',
    'ta013vq35', 'ta028viper', 'ta032s63b44',
    'ta038sr20', 'ta059mit4b11r', 'ta076m156',
    'ta081maz20b', 'ta081vr38', 'ta084lstt',
    'ta088raptor', 'ta89v8dsc', 'ta092nov812',
    'ta094f120', 'ta098sr20cust', 'ta103ninjah2r',
    'ta104bmws55', 'ta115huracantt', 'ta117vr38',
    'ta126p918', 'ta128subrx', 'ta132ls7sp',
    'ta135hellcatsp', 'ta140ls9', 'ta141lt5',
    'ta142n54', 'ta149camv8', 'ta176m177',
    'ta178amgb', 'ta181gt3', 'ta183lt1',
    'ta185amv8', 'ta197s50', 'ta488f154',
    'taaud40v8', 'tacumminsb', 'tagt3flat6',
    'tamustanggt50', 'tascmustanggt50', 'tjz1eng',
    'toysupmk4', 'trumpetzr', 'ttecov6',
    'twinhuracan', 'urusv8', 'v6audiea839',
    'veyronsound', 'w211',
}

local isOpen = false

RegisterCommand('enginesound', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh == 0 then
        TriggerEvent('chat:addMessage', { args = { '^1You must be in a vehicle.' } })
        return
    end
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        TriggerEvent('chat:addMessage', { args = { '^1You must be the driver.' } })
        return
    end

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', sounds = ENGINE_SOUNDS })
end, false)

RegisterNUICallback('applySound', function(data, cb)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
        cb('error')
        return
    end

    local sound = data.sound or ''
    if sound == '' then
        local name = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
        ForceVehicleEngineAudio(veh, name)
    else
        ForceVehicleEngineAudio(veh, sound)
    end
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    isOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)
