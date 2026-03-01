local VoidPool = {}

local SURFACE_NAME = "aw_void"
local DEFAULT_PITCH = 16
local DEFAULT_COLUMNS = 128

local function hide_surface_for_all_forces(surface)
    if not (surface and surface.valid) then
        return
    end

    for _, force in pairs(game.forces) do
        force.set_surface_hidden(surface, true)
    end
end

local function get_or_create_pool_state()
    storage.aw_void_pool = storage.aw_void_pool or {
        next_slot_id = 0,
        freed_slots = {},
        used_slots = {},
        pitch = DEFAULT_PITCH,
        columns = DEFAULT_COLUMNS,
    }
    return storage.aw_void_pool
end

local function slot_to_position(slot_id, pool)
    local pitch = pool.pitch or DEFAULT_PITCH
    local columns = pool.columns or DEFAULT_COLUMNS
    local x = (slot_id % columns) * pitch
    local y = math.floor(slot_id / columns) * pitch
    return { x = x, y = y }
end

function VoidPool.get_or_create_surface()
    local surface = game.surfaces[SURFACE_NAME]
    if not surface then
        surface = game.create_surface(SURFACE_NAME, {
            default_enable_all_autoplace_controls = false,
            autoplace_controls = {},
            peaceful_mode = true,
        })
        surface.freeze_daytime = true
        surface.daytime = 0
    end

    hide_surface_for_all_forces(surface)
    return surface
end

function VoidPool.on_init()
    get_or_create_pool_state()
    VoidPool.get_or_create_surface()
end

function VoidPool.allocate_slot()
    local pool = get_or_create_pool_state()
    local freed = pool.freed_slots

    local slot_id = nil
    if #freed > 0 then
        slot_id = table.remove(freed)
    else
        slot_id = pool.next_slot_id
        pool.next_slot_id = pool.next_slot_id + 1
    end

    pool.used_slots[slot_id] = true

    local surface = VoidPool.get_or_create_surface()
    local position = slot_to_position(slot_id, pool)
    return slot_id, surface, position
end

function VoidPool.release_slot(slot_id)
    if slot_id == nil then
        return
    end

    local pool = get_or_create_pool_state()
    if not pool.used_slots[slot_id] then
        return
    end

    pool.used_slots[slot_id] = nil
    table.insert(pool.freed_slots, slot_id)
end

return VoidPool