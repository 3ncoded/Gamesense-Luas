local csgo_weapons = require 'gamesense/csgo_weapons'
local vector = require("vector")
local inspect = require('inspect')

local weaponSettings = { }
local activeGroup
local cachedGroup
local enabled = false
local telePeek = false
local spHead = false
local bestEnemy = nil

local masterSwitch = ui.new_checkbox("Lua", "A", "Enable adaptive weapons")
local weaponGroupsBox = ui.new_combobox("Lua", "A", "Weapon", "Global", "AWP", "Auto", "Scout", "Revolver", "Deagle", "Pistol", "Zeus", "Rifle", "SMG", "Heavy", "Shotgun")
local minDmgOverrideKey1 = ui.new_hotkey("lua", "a", "Min damage override 1")
local minDmgOverrideKey2 = ui.new_hotkey("lua", "a", "Min damage override 2")

local screenSizeVec = vector(client.screen_size())
local middleVec = vector(screenSizeVec.x/2, screenSizeVec.y/2)

local labels = {
    minDamage = {[0] = "Auto"},
    hitChance = {[0] = "Off", [100] = "Ur retarded"},
    multipoint = {[24] = "Auto"}
}
for i=1, 26 do
    labels.minDamage[100 + i] = 'HP + ' .. i
end

local weaponIndexes = {
    Global      = {},
    AWP         = {9},
    Auto        = {11, 38},
    Scout       = {40},
    Revolver    = {64},
    Deagle      = {1},
    Pistol      = {2, 3, 4, 30, 32, 36, 61, 63},
    Zeus        = {31},
    Rifle       = {7, 8, 10, 13, 16, 39, 60},
    SMG         = {17, 19, 24, 26, 33, 34},
    Heavy       = {14, 28},
    Shotgun     = {25, 27, 29, 35}
}

-- useful functions
local function contains(key, value)
    for i = 1, #key do
        if key[i] == value then
            return true
        end
    end
    return false
end

local function tableContains(table, key)
    return table[key] ~= nil
end

local function getGroup(weapon)
    for key, value in pairs(weaponIndexes) do
        if (contains(value, weapon)) then
            return key
        end
    end
    return "Global"
end


local function get_best_enemy()
    local best_enemy = nil
    local enemies = entity.get_players(true)
    local lowestDistance
    for i=1, #enemies do
        local enemyVec = vector(entity.get_origin(enemies[i]))
        local w2sVec = vector(renderer.world_to_screen(enemyVec.x, enemyVec.y, enemyVec.z + 50))
        if w2sVec.x ~= nil and w2sVec.x ~= 0 then
            --renderer.line(w2sVec.x, w2sVec.y, middleVec.x, middleVec.y, 255, 255, 255, 255)
            if  lowestDistance == nil or w2sVec:dist2d(middleVec) < lowestDistance then
                lowestDistance = w2sVec:dist2d(middleVec)
                best_enemy = enemies[i]
            end
        end
    end
    return best_enemy
end

local function isLethal(player)
    local lp = entity.get_local_player()
    local localWeapon = entity.get_player_weapon(lp)
    local localWeaponIdx = entity.get_prop(localWeapon, "m_iItemDefinitionIndex")
    if localWeapon == nil or not localWeapon then
        return
    end
    local weaponData = csgo_weapons[localWeaponIdx]
    local health = entity.get_prop(player, "m_iHealth")
    if health ~= nil and weaponData.damage >= health then
        return true
    else
        return false
    end
end

local multiPoint, _, multiPointNum = ui.reference("Rage", "Aimbot", "Multi-point")
local quickPeek, quickPeekHotkey = ui.reference("Rage", "Other", "Quick peek assist")
local doubleTap, doubleTapHotkey = ui.reference("Rage", "Other", "Double tap")
local freestanding, freestandingHotkey = ui.reference("AA", "Anti-aimbot angles", "Freestanding")
local references = {
    targetSelection = ui.reference("Rage", "Aimbot", "Target selection"),
    targetHitbox = ui.reference("Rage", "Aimbot", "Target hitbox"),
    multiPoint = multiPoint,
    multiPointNum = multiPointNum,
    multiPointScale = ui.reference("Rage", "Aimbot", "Multi-point scale"),
    preferSafe = ui.reference("Rage", "Aimbot", "Prefer safe point"),
    avoidUnsafe = ui.reference("Rage", "Aimbot", "Avoid unsafe hitboxes"),
    hitChance = ui.reference("Rage", "Aimbot", "Minimum hit chance"),
    minDamage = ui.reference("Rage", "Aimbot", "Minimum damage"),
    autoScope = ui.reference("Rage", "Aimbot", "Automatic scope"),
    maxFov = ui.reference("Rage", "Aimbot", "Maximum FOV"),
    accuracyBoost = ui.reference("Rage", "Other", "Accuracy boost"),
    delayShot = ui.reference("Rage", "Other", "Delay shot"),
    quickStop = ui.reference("Rage", "Other", "Quick stop"),
    quickStopOptions = ui.reference("Rage", "Other", "Quick stop options"),
    preferBaim = ui.reference("Rage", "Other", "Prefer body aim"),
    preferBaimOptions = ui.reference("Rage", "Other", "Prefer body aim disablers"),
    baimOnPeek = ui.reference("Rage", "Other", "Force body aim on peek"),
    doubleTap = doubleTap,
    doubleTapHotkey = doubleTapHotkey,
    doubleTapHc = ui.reference("Rage", "Other", "Double tap hit chance"),
    doubleTapFl = ui.reference("Rage", "Other", "Double tap fake lag limit"),
    dtQuickStop = ui.reference("Rage", "Other", "Double tap quick stop"),
    qpAssist = quickPeekHotkey,
    hideShots = ui.reference("AA", "Other", "On shot anti-aim"),
    fLimit = ui.reference("AA", "Fake Lag", "Limit"),
    freestanding = freestanding,
    freestandingHotkey = freestandingHotkey,
    edgeYaw = ui.reference("AA", "Anti-aimbot angles", "Edge yaw"),
}

local function setupMenu()
    for key, value in pairs(weaponIndexes) do
        weaponSettings[key] = {
        targetSelection = ui.new_combobox("lua", "a", string.format("[%s] Target Selection", key), {"Cycle", "Cycle (x2)", "Near Crosshair", "Highest Damage", "Lowest Ping", "Best K/D Ratio", "Best hit chance"}),
        targetHitbox = ui.new_multiselect("lua", "a", string.format("[%s] Target Hitbox", key), {"Head", "Chest", "Stomach", "Arms", "Legs", "Feet"}),
        multiPoint = ui.new_multiselect("lua", "a", string.format("[%s] Multi-point", key), {"Head", "Chest", "Stomach", "Arms", "Legs", "Feet"}),
        multiPointNum = ui.new_combobox("lua", "a", string.format("[%s] Multi-point amount", key), {"Low", "Medium", "High"}),
        multiPointScale = ui.new_slider("lua", "a", string.format("[%s] Multi-point scale", key), 24, 100, 50, true, "%", 1, labels.multipoint),
        preferSafe = ui.new_checkbox("lua", "a", string.format("[%s] Prefer Safe Point", key)),
        avoidUnsafe = ui.new_multiselect("lua", "a", string.format("[%s] Avoid unsafe hitboxes", key), {"Head", "Chest", "Stomach", "Arms", "Legs"}),
        hitChance = ui.new_slider("lua", "a", string.format("[%s] Hit Chance", key), 0, 100, 50, true, "%", 1, labels.hitChance),
        minDamage = ui.new_slider("lua", "a", string.format("[%s] Minimum Damage", key), 0, 126, 50, true, "", 1, labels.minDamage),
        minDmgOverride1 = ui.new_slider("lua", "a", string.format("[%s] Min Damage Override 1", key), 0, 126, 50, true, "", 1, labels.minDamage),
        minDmgOverride2 = ui.new_slider("lua", "a", string.format("[%s] Min Damage Override 2", key), 0, 126, 50, true, "", 1, labels.minDamage),
        autoScope = ui.new_checkbox("lua", "a", string.format("[%s] Automatic Scope", key)),
        maxFov = ui.new_slider("lua", "a", string.format("[%s] Maximum FOV", key), 1, 180, 180, true, "°", 1),
        accuracyBoost = ui.new_combobox("lua", "a", string.format("[%s] Accuracy Boost", key), {"Off", "Low", "Medium", "High", "Maximum"}),delayShot = ui.new_checkbox("lua", "a", string.format("[%s] Delay Shot", key)),
        quickStop = ui.new_checkbox("lua", "a", string.format("[%s] Quick Stop", key)),
        quickStopOptions = ui.new_multiselect("lua", "a", string.format("[%s] Quick stop options", key), {"Early", "Slow motion", "Duck", "Fake Duck", "Move Between Shots", "Ignore Molotov", "Taser"}),
        preferBaim = ui.new_checkbox("lua", "a", string.format("[%s] Prefer Body Aim", key)),
        preferBaimOptions = ui.new_multiselect("lua", "a", string.format("[%s] Prefer body aim disablers", key), {"Low Inaccuracy", "Target Shot Fired", "Target Resolved", "Safe Point Headshot", "Low Damage"}),
        baimOnPeek = ui.new_checkbox("lua", "a", string.format("[%s] Force body aim on peek", key)),
        doubleTap = ui.new_checkbox("lua", "a", string.format("[%s] Double tap", key)),
        doubleTapHc = ui.new_slider("lua", "a", string.format("[%s] Double Tap Hitchance", key), 0, 100, 50, true, "%", 1),
        doubleTapFl = ui.new_slider("lua", "a", string.format("[%s] Double Tap Fake Lagg Limit", key), 1, 10, 4, true, "", 1),
        dtQuickStop = ui.new_multiselect("lua", "a", string.format("[%s] Double Tap Quick Stop", key), {"Slow Motion", "Duck", "Move between shots"}),
        spHeadIfLethal = ui.new_checkbox("lua", "a", string.format("[%s] Force safepoint on head if lethal", key)),
        telePeek = ui.new_checkbox("lua", "a", string.format("[%s] Telepeek/Ideal tick", key)),
        }
    end
end
setupMenu()

local function updateCfg(weapon)
    spHead = false
    if not ui.get(masterSwitch) then return end
    local activeSettings = weaponSettings[weapon] --weapon we're holding
    for key, value in pairs(weaponSettings) do -- updates the menu elements
        local settings = weaponSettings[key]
        local active = key == ui.get(weaponGroupsBox)
        for key, value in pairs(settings) do
            ui.set_visible(value, active)
        end
    end
    for setting, reference in pairs(references) do -- update the actual ragebot settings here
        -- Fix hitboxes so they're always occupied
        if setting == "targetHitbox" and next(ui.get(activeSettings[setting])) == nil then
            local newTable = ui.get(activeSettings[setting])
            table.insert(newTable, 1, "Head")
            ui.set(activeSettings[setting], newTable)
        end

        if tableContains(activeSettings, setting) then
            ui.set(reference, ui.get(activeSettings[setting]))
        end

        if setting == "avoidUnsafe" and ui.get(activeSettings["spHeadIfLethal"]) then
            local newTable = ui.get(activeSettings[setting])
            if newTable[1] ~= "Head" then
                if isLethal(bestEnemy) then
                    table.insert(newTable, 1, "Head")
                    ui.set(reference, newTable)
                    spHead = true
                end
            end
        elseif setting == "minDamage" and ui.get(minDmgOverrideKey1) then
            ui.set(reference, ui.get(activeSettings["minDmgOverride1"]))
        elseif setting == "minDamage" and ui.get(minDmgOverrideKey2) then
            ui.set(reference, ui.get(activeSettings["minDmgOverride2"]))
        elseif setting == "qpAssist" and ui.get(activeSettings["telePeek"]) and ui.get(references.doubleTapHotkey)then
            telePeek = false
            if ui.get(references.qpAssist) then
                telePeek = true
                ui.set(references.hideShots, false)
                ui.set(references.fLimit, 1)
                ui.set(references.edgeYaw, true)
                ui.set(references.doubleTapFl, 1)
                ui.set(references.doubleTapFl, 5)
                ui.set(references.doubleTapFl, 1)
            else
                telePeek = false
                ui.set(references.hideShots, true)
                ui.set(references.fLimit, 13)
                ui.set(references.edgeYaw, false)
            end
        end
    end
end

local function menuCallback()
    enabled = ui.get(masterSwitch)
    ui.set_visible(weaponGroupsBox, enabled)
    ui.set_visible(minDmgOverrideKey1, enabled)
    ui.set_visible(minDmgOverrideKey2, enabled)
    for key, value in pairs(weaponIndexes) do
        local group = key
        for key, value in pairs(weaponSettings[group]) do
            ui.set_visible(weaponSettings[group][key], enabled)
        end
    end
end

menuCallback()
ui.set_callback(masterSwitch, menuCallback)

local function changeWeaponCfg()
    for key, value in pairs(weaponIndexes) do
        local group = key
        for key, value in pairs(weaponSettings[group]) do
            if group == ui.get(weaponGroupsBox) then
                ui.set_visible(weaponSettings[group][key], true)
            else
                ui.set_visible(weaponSettings[group][key], false)
            end
            
        end
    end
end
ui.set_callback(weaponGroupsBox, changeWeaponCfg)

client.register_esp_flag("LETHAL", 255, 0, 0, function(player)
    if not ui.get(masterSwitch) then return end
    return isLethal(player)
end)

client.set_event_callback("net_update_end", function ()
    local lp = entity.get_local_player()
    if not enabled or lp == nil or entity.get_prop(lp, "m_lifeState" ) ~= 0 then return end
    local localWeapon = entity.get_player_weapon(lp)
    local localWeaponIdx = entity.get_prop(localWeapon, "m_iItemDefinitionIndex")
    if localWeapon == nil or not localWeapon then
        return
    end
    activeGroup = getGroup(localWeaponIdx) 
    updateCfg(activeGroup, localWeaponIdx)
    if activeGroup ~= cachedGroup then
        cachedGroup = activeGroup
        ui.set(weaponGroupsBox, activeGroup) 
    end
end)

client.set_event_callback("paint", function ()
    bestEnemy = get_best_enemy()
    local lp = entity.get_local_player()
	local localWeapon = entity.get_prop(lp, "m_hActiveWeapon")
	local nextAttack = entity.get_prop(lp,"m_flNextAttack") 
	local nextShot = entity.get_prop(localWeapon,"m_flNextPrimaryAttack")
	local nextShotSecondary = entity.get_prop(localWeapon,"m_flNextSecondaryAttack")
    if entity.is_alive(lp) then
        if localWeapon == nil then
            return
        end
    end
    if nextAttack == nil or nextShot == nil or nextShotSecondary == nil then
        return
    end
    nextAttack = nextAttack + 0.5
	nextShot = nextShot + 0.5
	nextShotSecondary = nextShotSecondary + 0.5
    if ui.get(minDmgOverrideKey1) or ui.get(minDmgOverrideKey2) then renderer.indicator(255, 255, 255, 255, "MD: "..ui.get(references.minDamage)) end
    if telePeek then
        if math.max(nextShot,nextShotSecondary) - globals.curtime() > 0.00  then
            renderer.text(middleVec.x, middleVec.y+20, 255, 255, 255, 255, '-', nil, 'IDEAL TICK: CHARGING')
        elseif math.max(nextShot,nextShotSecondary) - globals.curtime() < 0.00  then
            renderer.text(middleVec.x, middleVec.y+20, 255, 75, 75, 255, '-', nil,'IDEAL TICK: CHARGED')
        elseif math.max(nextShot,nextShotSecondary) < nextAttack then
            if nextAttack - globals.curtime() > 0.00 then
                renderer.text(middleVec.x, middleVec.y+20, 255, 50, 50, 255, '-', nil, 'IDEAL TICK: SWAPPING')
            end
        end
    end
    if spHead then
        renderer.text(middleVec.x, middleVec.y+25, 200, 200, 200, 255, '-', nil, 'Safepoint Head')
    end
end)
