local bcfm = require("Bullets Come From The Muzzle")
local statics = require("utility/Statics")
local re4 = require("utility/RE4")

if reframework:get_game_name() ~= "re4" then
    return
end

                        --\\ Laser Size //--
local beam_scale = 0.4                     -- Default(0.15) // Large(0.4)
local dot_min_scale = 1.0                  -- Default(0.75) // Large(1.0)
local dot_max_scale = 3.5                   -- Default(3.5) //  Large(5.0)

local cast_ray_method = sdk.find_type_definition("via.physics.System"):get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)")
local cast_ray_async_method = sdk.find_type_definition("via.physics.System"):get_method("castRayAsync(via.physics.CastRayQuery, via.physics.CastRayResult)")
local mesh_resource = sdk.create_resource("via.render.MeshResource", "BOOBIES/Laser/wp4000_21.mesh"):add_ref()
local dot_mesh_resource = sdk.create_resource("via.render.MeshResource", "BOOBIES/Laser/wp4000_21_dot.mesh"):add_ref()

local CollisionLayer = statics.generate(sdk.game_namespace("CollisionUtil.Layer"))
local CollisionFilter = statics.generate(sdk.game_namespace("CollisionUtil.Filter"))

local mask_bits = 0x80000000

local crosshair_bullet_ray_result = nil
local crosshair_attack_ray_result = nil

local latestRaycastID = 0 
local raycastID_table = {}
local is_aim = false
local CharacterContext = nil
local scene = nil
local save_file_path = "Boobies Lasers\\Saved.json"
local gun_obj = nil

local character_ids = {
    "ch3a8z0_head", "ch6i0z0_head", "ch6i1z0_head", "ch6i2z0_head",
    "ch6i3z0_head", "ch3a8z0_MC_head", "ch6i5z0_head"
}

local laser_resources = {
    blue = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Blue/wp4000_21.mdf2"):add_ref(),
    cyan = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Cyan/wp4000_21.mdf2"):add_ref(),
    green = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Green/wp4000_21.mdf2"):add_ref(),
    orange = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Orange/wp4000_21.mdf2"):add_ref(),
    purple = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Purple/wp4000_21.mdf2"):add_ref(),
    red = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Red/wp4000_21.mdf2"):add_ref(),
    yellow = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Yellow/wp4000_21.mdf2"):add_ref(),
}

local dot_resources = {
    blue = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Blue/wp4000_21_dot.mdf2"):add_ref(),
    cyan = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Cyan/wp4000_21_dot.mdf2"):add_ref(),
    green = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Green/wp4000_21_dot.mdf2"):add_ref(),
    orange = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Orange/wp4000_21_dot.mdf2"):add_ref(),
    purple = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Purple/wp4000_21_dot.mdf2"):add_ref(),
    red = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Red/wp4000_21_dot.mdf2"):add_ref(),
    yellow = sdk.create_resource("via.render.MeshMaterialResource", "BOOBIES/Laser/Colors/Yellow/wp4000_21_dot.mdf2"):add_ref(),
}

local color_options = {
    ["1"] = "blue",
    ["2"] = "cyan",
    ["3"] = "green",
    ["4"] = "orange",
    ["5"] = "purple",
    ["6"] = "red",
    ["7"] = "yellow",
}

local no_laser_weapons = {
    5000, 5001, 5002, 5003, 5006, 5400, 5401, 5402, 5403, 5404, 5405, 5406, 6107, 6108, 
}

local dot_material_holders = {}
local laser_material_holders = {}

local are_material_holders_created = false

local function create_material_holders()
    -- Check if the holders have already been created
    if are_material_holders_created then
        return
    end

    -- Create holders for dot materials
    for color_name, material_resource in pairs(dot_resources) do
        local material_holder = sdk.create_instance("via.render.MeshMaterialResourceHolder", true):add_ref()
        if material_holder then
            material_holder:write_qword(0x10, material_resource:get_address())
            dot_material_holders[color_name] = material_holder
        else
            -- log.warn("Could not create dot material holder for color: " .. color_name)
        end
    end

    -- Create holders for laser beam materials
    for color_name, material_resource in pairs(laser_resources) do
        local material_holder = sdk.create_instance("via.render.MeshMaterialResourceHolder", true):add_ref()
        if material_holder then
            material_holder:write_qword(0x10, material_resource:get_address())
            laser_material_holders[color_name] = material_holder
        else
            -- log.warn("Could not create laser material holder for color: " .. color_name)
        end
    end

    -- Set the flag to true to prevent multiple creations
    are_material_holders_created = true
end

-- This call will create the material holders the first time it is run.
-- Subsequent calls will do nothing.
create_material_holders()

local function cast_ray_async(ray_result, start_pos, end_pos, layer, filter_info, raycastID)
    if layer == nil then
        layer = CollisionLayer.Bullet
    end

    local via_physics_system = sdk.get_native_singleton("via.physics.System")
    local ray_query = sdk.create_instance("via.physics.CastRayQuery")
    local ray_result = ray_result or sdk.create_instance("via.physics.CastRayResult")



    ray_query:call("setRay(via.vec3, via.vec3)", start_pos, end_pos)
    ray_query:call("clearOptions")
    ray_query:call("enableAllHits")
    ray_query:call("enableNearSort")

    if filter_info == nil then
        filter_info = ray_query:call("get_FilterInfo")
        filter_info:call("set_Group", 0)
        filter_info:call("set_MaskBits", 0xFFFFFFFF & ~1) -- everything except the player.
        filter_info:call("set_Layer", layer)
    end

    ray_query:call("set_FilterInfo", filter_info)
    cast_ray_async_method:call(via_physics_system, ray_query, ray_result)
    -- Attach the raycastID to the ray_result. You'll need a mechanism for this.
    raycastID_table[ray_result] = raycastID
    return ray_result
end

local laser_table = {}
local dot_table = {}
local laser_weapons_data = {}
local dot_weapons = {}

local laser_created = false
local dot_created = false
local laser_go = nil
local dot_go = nil
-- Function to save the selected color to the JSON file
local function save_selected_color(selected_color_key)
    local data = { selected_color_key = selected_color_key }
    local success, err = pcall(json.dump_file, save_file_path, data)
    if not success then
        --log.warn("Error saving selected color: " .. tostring(err))
    end
end

-- Function to load the selected color from the JSON file
local function load_selected_color()
    local status, data = pcall(json.load_file, save_file_path)
    if not status or not data then
        --log.info("Error loading selected color or data is nil.")
        return "default_key" -- use an actual default key if "6" is not the correct one
    end
    if type(data) ~= "table" then
        --log.info("Data is not a table.")
        return "default_key"
    end
    if not data.selected_color_key then
        --log.info("selected_color_key is not present in data.")
        return "default_key"
    end
    if not color_options[data.selected_color_key] then
        --log.info("Invalid selected_color_key value.")
        return "default_key"
    end
    --log.info("Loaded color key: " .. data.selected_color_key)
    return data.selected_color_key
end

local selected_color_key = load_selected_color()
--log.info("Selected color key after loading: " .. tostring(selected_color_key))


local function set_laser_dot_material(color_name)
    --log.info("Setting laser dot material to color: " .. tostring(color_name))
    if not dot_table["dot"] then return end
    local dot_material_holder = dot_material_holders[color_name]
    if not dot_material_holder then
        -- log.warn("Dot material holder for color '" .. color_name .. "' not found!")
        return
    end
    local dot_mesh = dot_table["dot"]:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
    if dot_mesh then
        dot_mesh:set_Material(dot_material_holder)
    end
end

local function set_laser_beam_material(color_name)
    if not laser_table["laser"] then return end
    local laser_material_holder = laser_material_holders[color_name]
    if not laser_material_holder then
        -- log.warn("Laser material holder for color '" .. color_name .. "' not found!")
        return
    end
    local mesh = laser_table["laser"]:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
    if mesh then
        mesh:set_Material(laser_material_holder)
    end
end


local function create_laser_dot(dir)
    
    if dot_table["dot"] then return dot_table["dot"] end

    local pl_head = scene:call("findGameObject(System.String)", "ch0a0z0_head")

    if not pl_head then
        for _, character_id in ipairs(character_ids) do
            pl_head = scene:call("findGameObject(System.String)", character_id)
            if pl_head then
                break
            end
        end
    end

    if not pl_head then
        -- log.warn("Player Head not found!")
        return
    end

    local player_equip = pl_head:call("getComponent(System.Type)", sdk.typeof("chainsaw.PlayerEquipment"))
    local equip_weapon = player_equip:call("get_EquipWeaponID()")

    local gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon))

    if not gun_obj then
        gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon) .. "_AO")
    end

    if not gun_obj then
        gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon) .. "_MC")
    end

    if not gun_obj then
        --    log.warn("gun_obj not found, exiting create_laser_weapon.")
        return
    end
    local bt_gun = gun_obj:call("getComponent(System.Type)", sdk.typeof("chainsaw.Gun"))
    local bt_arms = gun_obj:call("getComponent(System.Type)", sdk.typeof("chainsaw.Arms"))

    local muzzle_joint = bt_arms:call("getMuzzleJoint")
    if not muzzle_joint then
        --    log.warn("Initial Muzzle joint not found in on_pre_application_entry.")
        local gun_transforms = gun_obj:get_Transform()

        -- Directly retrieve the "vfx_muzzle" joint using the getJointByName method
        muzzle_joint = gun_transforms:call("getJointByName", "vfx_muzzle")

        if muzzle_joint then
            --        log.info("Found vfx_muzzle")
        else
            --        log.warn("VFX Muzzle joint not found in on_pre_application_entry.")
        end
    end

    local dot_go = sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil,
        "BOOBIELaserDot")


    if dot_go then
        local dot_transform = dot_go:get_Transform()
        dot_transform:set_Parent(gun_obj:get_Transform())

        local dot_mesh = dot_go:call("createComponent(System.Type)", sdk.typeof("via.render.Mesh"))

        if dot_mesh then
            local dot_mesh_resource_holder = sdk.create_instance("via.render.MeshResourceHolder", true):add_ref()
            dot_mesh_resource_holder:write_qword(0x10, dot_mesh_resource:get_address())

            dot_mesh:setMesh(dot_mesh_resource_holder)

            
            --write_vec4(laser_transform, start_pos, 0xB0)

            local start = muzzle_joint:get_Position()
            dot_transform:set_Position(start)
            dot_transform:set_Rotation(dir:normalized():to_quat())

            laser_weapons_data[gun_obj] = {
                start_pos = start,
                end_pos = start + (dir * 8192.0),
            }
        end
        dot_table["dot"] = dot_go
        dot_created = true
        return dot_go
    end
end

local function create_laser_weapon(dir)
    if laser_table["laser"] then return laser_table["laser"] end

    local pl_head = scene:call("findGameObject(System.String)", "ch0a0z0_head")

    if not pl_head then
        for _, character_id in ipairs(character_ids) do
            pl_head = scene:call("findGameObject(System.String)", character_id)
            if pl_head then
                break
            end
        end
    end

    if not pl_head then
        -- log.warn("Player Head not found!")
        return
    end

    local player_equip = pl_head:call("getComponent(System.Type)", sdk.typeof("chainsaw.PlayerEquipment"))
    local equip_weapon = player_equip:call("get_EquipWeaponID()")

    local gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon))

    if not gun_obj then
        gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon) .. "_AO")
    end

    if not gun_obj then
        gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon) .. "_MC")
    end

    if not gun_obj then
        --    log.warn("gun_obj not found, exiting create_laser_weapon.")
        return
    end
    local bt_gun = gun_obj:call("getComponent(System.Type)", sdk.typeof("chainsaw.Gun"))
    local bt_arms = gun_obj:call("getComponent(System.Type)", sdk.typeof("chainsaw.Arms"))

    local muzzle_joint = bt_arms:call("getMuzzleJoint")
    if not muzzle_joint then
        --   log.warn("Initial Muzzle joint not found in on_pre_application_entry.")
        local gun_transforms = gun_obj:get_Transform()

        -- Directly retrieve the "vfx_muzzle" joint using the getJointByName method
        muzzle_joint = gun_transforms:call("getJointByName", "vfx_muzzle")

        if muzzle_joint then
            --      log.info("Found vfx_muzzle")
        else
            --       log.warn("VFX Muzzle joint not found in on_pre_application_entry.")
        end
    end

    local laser_go = sdk.find_type_definition("via.GameObject"):get_method("create(System.String)"):call(nil,
        "BOOBIELaser")


    if laser_go then
        local laser_transform = laser_go:get_Transform()
        laser_transform:set_Parent(gun_obj:get_Transform())
        --laser_transform:set_Rotation((impact_pos - start_pos):normalized():to_quat())
        --laser_transform:set_Position(start_pos:to_vec4())

        local mesh = laser_go:call("createComponent(System.Type)", sdk.typeof("via.render.Mesh"))



        if mesh then
            local mesh_resource_holder = sdk.create_instance("via.render.MeshResourceHolder", true):add_ref()
            mesh_resource_holder:write_qword(0x10, mesh_resource:get_address())

            mesh:setMesh(mesh_resource_holder)

            --write_vec4(laser_transform, start_pos, 0xB0)

            local start = muzzle_joint:get_Position()
            laser_transform:set_Position(start)
            laser_transform:set_Rotation(dir:normalized():to_quat())

            -- Calculate the maximum potential endpoint for the laser
            local max_distance = 8192.0
            local end_pos = start + dir:normalized() * max_distance

            laser_weapons_data[gun_obj] = {
                start_pos = start,
                end_pos = end_pos,
            }
        end
        laser_table["laser"] = laser_go
        laser_created = true
        return laser_go
    end
end

local function destroy_lasers()
    -- Destroy laser object if it exists
    if laser_table["laser"] then
        laser_table["laser"]:call("destroy", laser_table["laser"])
        laser_table["laser"] = nil
    end

    -- Destroy dot object if it exists
    if dot_table["dot"] then
        dot_table["dot"]:call("destroy", dot_table["dot"])
        dot_table["dot"] = nil
    end
    is_aim = false
    CharacterContext = nil
end

re.on_script_reset(function()
    destroy_lasers()

    initial_laser_transform = {
        position = Vector3f.new(0, 0, 0),
        rotation = Quaternion.new(0, 0, 0, 1),
        scale = Vector3f.new(1, 1, 1)
    }

    initial_dot_transform = {
        position = Vector3f.new(0, 0, 0),
        rotation = Quaternion.new(0, 0, 0, 1),
        scale = Vector3f.new(1, 1, 1)
    }

    crosshair_bullet_ray_result = nil
    crosshair_attack_ray_result = nil

    latestRaycastID = 0
    raycastID_table = {}
    muzzle_pos = nil
    desired_rotation = nil
    is_aim = false
    CharacterContext = nil
    is_shoot = false

    laser_table = {}
    dot_table = {}
    laser_weapons_data = {}
    dot_weapons = {}
    laser_created = false
    dot_created = false
    laser_go = nil
    dot_go = nil
end)

local function safeGetObject(name)
    local obj = scene:call("findGameObject(System.String)", name)
    if obj then
        return obj
    else
        --log.warn("Object " .. name .. " not found in the scene.")
        return nil
    end
end

local last_time = os.clock()

local last_weapon_id = nil

-- Assuming you have a global table to store muzzle info:
muzzle_info = {
    position = nil,
    joint = nil
}

local function reset_muzzle()
    -- Clearing stored muzzle info:
    muzzle_info.position = nil
    muzzle_info.joint = nil
    is_aim = false
    CharacterContext = nil
    equip_weapon = nil

    local pl_head = scene:call("findGameObject(System.String)", "ch0a0z0_head")

    if not pl_head then
        for _, character_id in ipairs(character_ids) do
            pl_head = scene:call("findGameObject(System.String)", character_id)
            if pl_head then
                break
            end
        end
    end

    if not pl_head then
        -- log.warn("Player Head not found!")
        return
    end

    local player_equip = pl_head:call("getComponent(System.Type)", sdk.typeof("chainsaw.PlayerEquipment"))
    local equip_weapon = player_equip:call("get_EquipWeaponID()")

    local gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon))

    if not gun_obj then
        gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon) .. "_AO")
    end

    if not gun_obj then
        gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon) .. "_MC")
    end

    if not gun_obj then
        --   log.warn("gun_obj not found, exiting create_laser_weapon.")
        return
    end

    local bt_arms = gun_obj:call("getComponent(System.Type)", sdk.typeof("chainsaw.Arms"))
    if not bt_arms then
        --   log.warn("Arms component not found.")
        return
    end

    local muzzle_joint = bt_arms:call("getMuzzleJoint")
    if not muzzle_joint then
       -- log.warn("Initial Muzzle joint not found in on_pre_application_entry.")
        local gun_transforms = gun_obj:get_Transform()

        -- Directly retrieve the "vfx_muzzle" joint using the getJointByName method
        muzzle_joint = gun_transforms:call("getJointByName", "vfx_muzzle")

        if muzzle_joint then
            --  log.info("Found vfx_muzzle")
        else
            --  log.warn("VFX Muzzle joint not found in on_pre_application_entry.")
        end
    end

    -- Storing the newly fetched info:
    muzzle_info.position = muzzle_joint:call("get_Position")
    muzzle_info.joint = muzzle_joint
end



local last_known_weapon_id = nil


local function update_lasers(equip_weapon, laser, laser_dot)
    local pl_head = scene:call("findGameObject(System.String)", "ch0a0z0_head")

    if not pl_head then
        for _, character_id in ipairs(character_ids) do
            pl_head = scene:call("findGameObject(System.String)", character_id)
            if pl_head then
                break
            end
        end
    end

    if not pl_head then
        -- log.warn("Player Head not found!")
        return
    end

     gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon))

    if not gun_obj then
        gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon) .. "_AO")
    end

    if not gun_obj then
        gun_obj = scene:call("findGameObject(System.String)", "wp" .. tostring(equip_weapon) .. "_MC")
    end

    if gun_obj == no_laser_weapons then
       -- return
    end

    if not gun_obj then
        --  log.warn("gun_obj not found, exiting create_laser_weapon.")
        return
    end
    local bt_gun = gun_obj:call("getComponent(System.Type)", sdk.typeof("chainsaw.Gun"))
    local bt_arms = gun_obj:call("getComponent(System.Type)", sdk.typeof("chainsaw.Arms"))

    local muzzle_joint = bt_arms:call("getMuzzleJoint")
    if not muzzle_joint then
        -- log.warn("Initial Muzzle joint not found in on_pre_application_entry.")
        local gun_transforms = gun_obj:get_Transform()

        -- Directly retrieve the "vfx_muzzle" joint using the getJointByName method
        muzzle_joint = gun_transforms:call("getJointByName", "vfx_muzzle")

        if not muzzle_joint then
            return
        end

        if muzzle_joint then
            -- log.info("Found vfx_muzzle")
        else
            -- log.warn("VFX Muzzle joint not found in on_pre_application_entry.")
        end
    end

    local muzzle_pos = muzzle_joint:call("get_Position")


    if last_known_weapon_id ~= equip_weapon then
        reset_muzzle()
        last_known_weapon_id = equip_weapon     -- Update the last known weapon ID
    end

    local start_pos = muzzle_pos
    local end_pos = muzzle_pos + (global_intersection_point - muzzle_pos):normalized() * 8192.0

    if not laser_table["laser"] then
        create_laser_weapon(global_intersection_point - start_pos)
        set_laser_beam_material(color_options[selected_color_key])
    end

    if not dot_table["dot"] then
        log.info("Creating lasers and setting colors.")
        create_laser_dot(global_intersection_point - start_pos)
        set_laser_dot_material(color_options[selected_color_key])
    end

    if is_aim == true then
         --log.info("My dude is aiming.")

        if not crosshair_attack_ray_result or not crosshair_bullet_ray_result then
            --   log.info("Initializing ray casting.")
            latestRaycastID = latestRaycastID + 1
            crosshair_attack_ray_result = cast_ray_async(crosshair_attack_ray_result, start_pos, end_pos, 5, nil,
                latestRaycastID)
            crosshair_bullet_ray_result = cast_ray_async(crosshair_bullet_ray_result, start_pos, end_pos, 10, nil,
                latestRaycastID)
            crosshair_attack_ray_result:add_ref()
            crosshair_bullet_ray_result:add_ref()
        end

        local attack_raycastID = raycastID_table[crosshair_attack_ray_result]
        local bullet_raycastID = raycastID_table[crosshair_bullet_ray_result]
        local attack_finished = crosshair_attack_ray_result:call("get_Finished") == true and
        attack_raycastID == latestRaycastID
        local bullet_finished = crosshair_bullet_ray_result:call("get_Finished") == true and
        bullet_raycastID == latestRaycastID
        local finished = attack_finished and bullet_finished
        local attack_hit = finished and crosshair_attack_ray_result:call("get_NumContactPoints") > 0
        local bullet_hit = finished and crosshair_bullet_ray_result:call("get_NumContactPoints") > 0
        local any_hit = finished and (attack_hit or crosshair_bullet_ray_result:call("get_NumContactPoints") > 0)

        if finished then
            if any_hit then
                local best_result = attack_hit and crosshair_attack_ray_result or crosshair_bullet_ray_result
                local contact_point = best_result:call("getContactPoint(System.UInt32)", 0)
                local ray_direction = (end_pos - start_pos):normalized()
                local hit_distance = contact_point:get_field("Distance")
                local hit_position = start_pos + ray_direction * hit_distance
                local start = muzzle_joint:get_Position()
                local direction_to_intersection = (hit_position - start):normalized()

                if laser then
                    local laser_transform = laser:get_Transform()
                    laser_transform:set_Parent(gun_obj:get_Transform())
                    local start = muzzle_joint:get_Position()
                    local distance = contact_point:get_field("Distance")
                    --log.info("Updating laser. Distance: " .. tostring(distance))

                    local desired_rotation = (direction_to_intersection):normalized():to_quat()
                    laser_transform:set_Position(start)
                    laser_transform:set_Rotation(desired_rotation)
                    -- laser_transform:set_Rotation((direction_to_intersection):normalized():to_quat())
                    local offset = 0.05 -- Adjust this value accordingly
                    laser_transform:set_LocalScale(Vector3f.new(beam_scale, beam_scale, (distance - offset) * 1.0))


                    if laser_dot then
                        local dot_transform = laser_dot:get_Transform()
                        dot_transform:set_Parent(gun_obj:get_Transform())
                        local distance = contact_point:get_field("Distance")
                        --  log.info("Updating laser. Distance: " .. tostring(distance))

                        local desired_rotation = (direction_to_intersection):normalized():to_quat()
                        dot_transform:set_Position(hit_position - (direction_to_intersection * .05))
                        dot_transform:set_Rotation(desired_rotation)

                        local minDistance = 1    -- Minimum distance from the muzzle
                        local maxDistance = 60.0 -- Maximum distance from the muzzle
                        local minScale = dot_min_scale    -- Dot's scale at minimum distance
                        local maxScale = dot_max_scale     -- Dot's scale at maximum distance

                        local t = (distance - minDistance) / (maxDistance - minDistance)

                        -- Clamp t to the range [0, 1] to ensure we don't overshoot our scaling
                        t = math.max(0, math.min(1, t))

                        -- Interpolate scale based on t
                        local currentScale = minScale + (maxScale - minScale) * t
                        dot_transform:set_LocalScale(Vector3f.new(currentScale, currentScale, currentScale))
                    end
                    --  log.info("Laser update complete.")
                end
            else
                -- This block handles the scenario where there's no hit.
                --  log.info("No hit detected. Aiming at sky or out-of-bounds.")

                -- Use the direction from the muzzle towards the global intersection point
                local direction_to_intersection = (global_intersection_point - start_pos):normalized()

                -- Define the end position for the laser dot when no hit occurs
                local end_pos_far = start_pos + direction_to_intersection * 100

                -- Calculate the distance from the muzzle to the laser dot
                local diff = end_pos_far - start_pos
                local laser_distance = math.sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z)

                -- Set the laser's position and rotation
                if laser then
                    local laser_transform = laser:get_Transform()
                    local start = muzzle_joint:get_Position()

                    laser_transform:set_Position(start)
                    laser_transform:set_Rotation(direction_to_intersection:to_quat())
                    laser_transform:set_LocalScale(Vector3f.new(beam_scale, beam_scale, laser_distance)) -- Use laser_distance for scaling
                end

                -- Set the laser dot's position
                if laser_dot then
                    local dot_transform = laser_dot:get_Transform()

                    dot_transform:set_Position(end_pos_far)
                    dot_transform:set_Rotation(direction_to_intersection:to_quat())
                    dot_transform:set_LocalScale(Vector3f.new(1, 1, 1)) -- Keep the laser dot at a default size when no hit
                end
            end
        end

        if finished then
            reset_muzzle()
            desired_rotation = nil

            raycastID_table[crosshair_attack_ray_result] = nil
            raycastID_table[crosshair_bullet_ray_result] = nil

            -- log.info("Restarting ray casting.")
            latestRaycastID = latestRaycastID + 1
            cast_ray_async(crosshair_attack_ray_result, start_pos, end_pos, 5, CollisionFilter
            .DamageCheckOtherThanPlayer, latestRaycastID)
            cast_ray_async(crosshair_bullet_ray_result, start_pos, end_pos, 10, nil, latestRaycastID)
        end
    end
end
local function disable_base_lasers()
    local laser_sight_obj = scene:call("findGameObject(System.String)", "LaserSight")
    if not laser_sight_obj then
        return
    end
    local laser_controller = laser_sight_obj:call("getComponent(System.Type)",
        sdk.typeof("chainsaw.LaserSightController"))
    if not laser_controller then
        return
    end
    laser_controller:call("destroy", laser_controller)
end


re.on_pre_application_entry("LockScene", function()
    -- log.info("Entered on_pre_application_entry.")

    --  local now = os.clock()
    -- if now - last_time < (1.0 / 60.0) then
    --     log.info("Exiting due to time check.")
    --       return
    -- end

    last_time = now
if not scene then
    return
end
    local camera = sdk.get_primary_camera()
    if not camera then
        destroy_lasers()
        is_aim = false
        log.warn("Primary camera not found, exiting on_pre_application_entry.")
        return
    end

    local character_manager = sdk.get_managed_singleton(sdk.game_namespace("CharacterManager"))
    local player_context = character_manager:call("getPlayerContextRef")
    if player_context == nil then
        destroy_lasers()
        reset_muzzle()
        is_aim = false
        return
    end

    local pl_head = scene:call("findGameObject(System.String)", "ch0a0z0_head")

    if not pl_head then
        for _, character_id in ipairs(character_ids) do
            pl_head = scene:call("findGameObject(System.String)", character_id)
            if pl_head then
                break
            end
        end
    end

    if not pl_head then
        -- log.warn("Player Head not found!")
        return
    end

    local player_equip = pl_head:call("getComponent(System.Type)", sdk.typeof("chainsaw.PlayerEquipment"))
    local equip_weapon = player_equip:call("get_EquipWeaponID()")
    -- local is_aim = player_equip:call("get_IsReticle()")
    -- log.info("Player Aiming Status is ", is_aim)
    if CharacterContext then
        is_aim = CharacterContext:call("get_IsShootEnable")
        is_shoot = CharacterContext:call("get_IsShooting")
        --log.info("CharacterContext Exists, aim state set.")
    else
        is_aim = false
        --log.info("No CharacterContext, is_aim set to false")
    end

    --log.info("equip_weapon is currently "..equip_weapon)

    for _, weapon in ipairs(no_laser_weapons) do
        if equip_weapon == weapon then
            is_aim = false
            break
        end
    end

    local laser = safeGetObject("BOOBIELaser")
    local laser_dot = safeGetObject("BOOBIELaserDot")
        if laser and laser_dot then
            if is_aim then
                 --log.info("Turning lasers on.")
                laser:set_DrawSelf(true)
                laser_dot:set_DrawSelf(true)
            else
                 -- log.info("Turning lasers off.")
                laser:set_DrawSelf(false)
                laser_dot:set_DrawSelf(false)
            end
        end
    disable_base_lasers()
    update_lasers(equip_weapon, laser, laser_dot)
end)

re.on_frame(function()
    if CharacterContext == nil then
        local camera = sdk.get_primary_camera()

        if camera then
            local scene_manager = sdk.get_native_singleton("via.SceneManager")
            if scene_manager then
                 scene = sdk.call_native_func(scene_manager, sdk.find_type_definition("via.SceneManager"),"get_CurrentScene")
                if scene == nil then
                    log.error("Failed to get current scene.")
                    return
                end
                local PlayerInventoryObserver = scene:call("findGameObject(System.String)", "PlayerInventoryObserver")

                if PlayerInventoryObserver then
                    local InventoryObserver = PlayerInventoryObserver:call("getComponent(System.Type)",
                        sdk.typeof("chainsaw.PlayerInventoryObserver"))

                    if InventoryObserver then
                        local Observer = InventoryObserver:get_field("_Observer")

                        if Observer then
                            local InventoryController = Observer:get_field("_InventoryController")

                            if InventoryController then
                                CharacterContext = InventoryController:get_field("<_CharacterContext>k__BackingField")
                            end
                        end
                    end
                end
            else
                log.error("Failed to get scene manager.")
                return
            end
        end
    end
end)


re.on_draw_ui(function()

    if not scene then
        return
    end

    local changed = false
    local mchanged = false

    mchanged, mask_bits = imgui.drag_int("Mask bits", mask_bits, 1)
    if mchanged then
        -- log.info("Mask bits changed to: " .. mask_bits)
    end

    if imgui.tree_node("Universal Lasers") then
        -- Extract the color names and sort them if necessary
        local color_names = {}
        local color_keys = {}
        for k, v in pairs(color_options) do
            table.insert(color_keys, k)
            table.insert(color_names, v)
        end
        
        -- Sort the color keys if the table is supposed to be random
        -- This will provide a consistent order for the imgui combo
        table.sort(color_keys, function(a, b) return color_options[a] < color_options[b] end)
        
        -- Create a display list for imgui combo
        local color_display_list = {}
        for i, key in ipairs(color_keys) do
            color_display_list[i] = color_options[key]
        end

        -- Find the current index of the selected color
        local selected_index = nil
        for i, key in ipairs(color_keys) do
            if key == selected_color_key then
                selected_index = i
                break
            end
        end

        -- Ensure a valid selection
        selected_index = selected_index or 1

        -- imgui combo to select color
        changed, selected_index = imgui.combo("Laser Color", selected_index, color_display_list)
        if changed then
            --log.info("Laser Color Changed is True")
            -- Update the selected color key based on the new index
            selected_color_key = color_keys[selected_index]
            -- Save the new selected color
            save_selected_color(selected_color_key)
            -- Call the function to apply the material to the laser dot
            set_laser_dot_material(color_options[selected_color_key])
            set_laser_beam_material(color_options[selected_color_key])
        end
        
        imgui.tree_pop()
    end
end)
