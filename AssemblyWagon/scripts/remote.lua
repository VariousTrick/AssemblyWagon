-- =================================================================================================
-- Assembly Wagon - remote.lua
-- =================================================================================================
-- 作用：对外暴露远程接口，供其他模组在“车厢实体被替换”时转移绑定关系。

local Remote = {}
local Builder
local log_debug = function(_) end

-- 初始化并注册 AssemblyWagon 远程接口
-- 风格与 RiftRail 保持一致：由 control 注入依赖后统一 add_interface
function Remote.init(params)
    Builder = params.Builder
    if params and params.log_debug then
        log_debug = params.log_debug
    end

    remote.add_interface("AssemblyWagon", {
        -- transfer_binding(old_wagon, new_wagon)
        -- 参数：两个 LuaEntity，且都应为 assembly-wagon
        -- 返回：true 表示转移成功，false 表示校验失败或无可转移数据
        transfer_binding = function(old_wagon, new_wagon)
            if AssemblyWagon.DEBUG_MODE_ENABLED then
                local old_unit = old_wagon and old_wagon.valid and old_wagon.unit_number or "nil"
                local new_unit = new_wagon and new_wagon.valid and new_wagon.unit_number or "nil"
                log_debug("remote.transfer_binding 调用: old=" .. tostring(old_unit) .. ", new=" .. tostring(new_unit))
            end
            return Builder.transfer_binding(old_wagon, new_wagon)
        end,
    })

    if AssemblyWagon.DEBUG_MODE_ENABLED then
        log_debug("remote 接口 AssemblyWagon 注册完成")
    end
end

return Remote
