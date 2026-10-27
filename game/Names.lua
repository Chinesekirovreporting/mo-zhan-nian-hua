-- ============================================================
-- 玩法事件名。挂到 App.Ev 上，和插件壳的名字放在同一张表。
-- ============================================================
local ADDON_NAME, MZ = ...
local Ev = MZ.App.Ev

Ev.CHECKERS_CHANGED = "MZ_CHECKERS_CHANGED"
Ev.TIMER_START      = "MZ_TIMER_START"
Ev.TIMER_PAUSE      = "MZ_TIMER_PAUSE"
Ev.TIMER_DONE       = "MZ_TIMER_DONE"
