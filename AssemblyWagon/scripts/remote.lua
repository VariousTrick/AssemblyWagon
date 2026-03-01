-- =================================================================================================
-- Assembly Wagon - remote.lua
-- =================================================================================================
-- 作用：对外暴露远程接口，供其他模组在“车厢实体被替换”时转移绑定关系。

local Remote = {}
local Builder

-- 初始化并注册 AssemblyWagon 远程接口
-- 风格与 RiftRail 保持一致：由 control 注入依赖后统一 add_interface
function Remote.init(params)
    Builder = params.Builder

    remote.add_interface("AssemblyWagon", {
        -- transfer_binding(old_wagon, new_wagon)
        -- 参数：两个 LuaEntity，且都应为 assembly-wagon
        -- 返回：true 表示转移成功，false 表示校验失败或无可转移数据
        transfer_binding = function(old_wagon, new_wagon)
            return Builder.transfer_binding(old_wagon, new_wagon)
        end,
    })
end

return Remote
