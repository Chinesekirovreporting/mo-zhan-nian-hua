-- ============================================================
-- CodeEvent · 插件自己的代码事件
-- 小写 on / once / off / emit。回调只收载荷，不塞事件名。
-- 暴雪事件不走这里，走 SystemEvent。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local bus = App.EventBus:new()

App._modules.Code = bus
