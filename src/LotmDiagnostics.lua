-- ============================================================================
-- Lord of the Mysteries (C7 / UE4 / LuaJIT) — Autonomous Diagnostic Mod
-- File: LotmDiagnostics.lua
-- Purpose: Collect detailed runtime UI, Slate font engine, and module dumps
--          to pinpoint font stretching, LetterSpacing, and asset resolution.
-- ============================================================================

local VERSION = "1.0.0"
local MODULE_TAG = "[LotmDiagnostics]"

-- ----------------------------------------------------------------------------
-- 1. Native UE4 / Lua Engine Libraries & Logging
-- ----------------------------------------------------------------------------
local function safe_import(name)
    local ok, lib = pcall(import, name)
    if ok and lib ~= nil then return lib end
    return nil
end

local FileLib = safe_import("LuaFunctionLibrary")
local PathsLib = safe_import("BlueprintPathsLibrary")
local KismetSysLib = safe_import("KismetSystemLibrary")

local function report(message)
    local line = MODULE_TAG .. " " .. tostring(message)
    local logger = rawget(_G, "Log") or rawget(_G, "LaunchLog") or rawget(_G, "LuaCLogger")
    if logger ~= nil then
        if type(logger.Info) == "function" then
            pcall(logger.Info, line)
        elseif type(logger.Log) == "function" then
            pcall(logger.Log, line)
        end
    end
end

local function getSavedLogsDir()
    local savedDir = nil
    if PathsLib ~= nil and type(PathsLib.ProjectSavedDir) == "function" then
        local ok, res = pcall(PathsLib.ProjectSavedDir)
        if ok and res ~= nil and res ~= "" then
            savedDir = tostring(res)
        end
    end
    if savedDir == nil and FileLib ~= nil and type(FileLib.GetFilePath) == "function" and PathsLib ~= nil then
        local ok, res = pcall(function()
            return FileLib.GetFilePath(PathsLib.ProjectSavedDir())
        end)
        if ok and res ~= nil and res ~= "" then
            savedDir = tostring(res)
        end
    end
    if savedDir == nil or savedDir == "" then
        savedDir = "Saved"
    end
    -- Normalize path separators to forward slash
    savedDir = savedDir:gsub("\\", "/")
    if savedDir:sub(-1) == "/" then
        savedDir = savedDir:sub(1, -2)
    end
    return savedDir .. "/Logs"
end

local function saveOutputFile(filePath, content)
    local written = false

    -- Attempt 1: FileLib.SaveFile(path, content)
    if FileLib ~= nil and type(FileLib.SaveFile) == "function" then
        local ok = pcall(FileLib.SaveFile, filePath, content)
        if ok then written = true end
        if not written then
            -- Some bindings swap arguments: (content, path)
            local ok2 = pcall(FileLib.SaveFile, content, filePath)
            if ok2 then written = true end
        end
    end

    -- Attempt 2: FileLib.SaveStringContentToFile(content, path)
    if not written and FileLib ~= nil and type(FileLib.SaveStringContentToFile) == "function" then
        local ok = pcall(FileLib.SaveStringContentToFile, content, filePath)
        if ok then written = true end
        if not written then
            local ok2 = pcall(FileLib.SaveStringContentToFile, filePath, content)
            if ok2 then written = true end
        end
    end

    -- Attempt 3: Native Lua io.open
    if not written then
        local ok, f = pcall(io.open, filePath, "wb")
        if ok and f ~= nil then
            f:write(content)
            f:close()
            written = true
        end
    end

    return written
end

-- ----------------------------------------------------------------------------
-- 2. Pure-Lua Zero-Dependency JSON Serializer
-- ----------------------------------------------------------------------------
local function escape_json_string(s)
    if type(s) ~= "string" then s = tostring(s or "") end
    local escapes = {
        ["\\"] = "\\\\",
        ["\""] = "\\\"",
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t",
    }
    return s:gsub("[\"\\\b\f\n\r\t]", escapes):gsub("[\0-\31]", function(c)
        return string.format("\\u%04x", string.byte(c))
    end)
end

local function is_table_array(t)
    if type(t) ~= "table" then return false end
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
            return false
        end
        count = count + 1
    end
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

local function to_json_indented(val, current_indent)
    current_indent = current_indent or ""
    local sub_indent = current_indent .. "  "
    local t = type(val)

    if val == nil then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "null" end -- NaN
        if val == math.huge or val == -math.huge then return "null" end
        return tostring(val)
    elseif t == "string" then
        return "\"" .. escape_json_string(val) .. "\""
    elseif t == "table" then
        if is_table_array(val) then
            if #val == 0 then return "[]" end
            local parts = {}
            for i = 1, #val do
                parts[#parts + 1] = sub_indent .. to_json_indented(val[i], sub_indent)
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. current_indent .. "]"
        else
            local keys = {}
            for k, _ in pairs(val) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            if #keys == 0 then return "{}" end
            local parts = {}
            for _, k in ipairs(keys) do
                local v = val[k] or val[tonumber(k)]
                parts[#parts + 1] = sub_indent .. "\"" .. escape_json_string(k) .. "\": " .. to_json_indented(v, sub_indent)
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. current_indent .. "}"
        end
    else
        return "\"" .. escape_json_string(tostring(val)) .. "\""
    end
end

-- ----------------------------------------------------------------------------
-- 3. Diagnostics State & History
-- ----------------------------------------------------------------------------
local Diagnostics = {
    Version = VERSION,
    StartTime = os.date("%Y-%m-%d %H:%M:%S"),
    LastDumpTime = nil,
    DumpCount = 0,
    ActivePanels = {},       -- [panel_uid] = panel_data
    RecentEvents = {},       -- list of recent UIComponent Open/Refresh events
    CapturedWidgetsCount = 0,
    IsDirty = false,
}

local function format_timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- ----------------------------------------------------------------------------
-- 4. Environment & Module Scanner
-- ----------------------------------------------------------------------------
local TARGET_KEYWORDS = {
    "shop", "task", "quest", "item", "menu", "ui", "kgui", "card", "board", "bag", "store", "chat"
}

local function matches_keywords(str)
    if type(str) ~= "string" then return false end
    local lower = str:lower()
    for _, kw in ipairs(TARGET_KEYWORDS) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

local function scanLoadedModules()
    local result = {
        total_package_loaded = 0,
        total_game_loaded = 0,
        matched_package_modules = {},
        matched_game_modules = {},
        identified_shop_classes = {},
        identified_task_classes = {},
        global_game_systems = {},
    }

    if type(package) == "table" and type(package.loaded) == "table" then
        for k, v in pairs(package.loaded) do
            result.total_package_loaded = result.total_package_loaded + 1
            local name = tostring(k)
            if matches_keywords(name) then
                result.matched_package_modules[#result.matched_package_modules + 1] = name
                local lower = name:lower()
                if lower:find("shop", 1, true) then
                    result.identified_shop_classes[#result.identified_shop_classes + 1] = name
                end
                if lower:find("task", 1, true) or lower:find("quest", 1, true) or lower:find("board", 1, true) then
                    result.identified_task_classes[#result.identified_task_classes + 1] = name
                end
            end
        end
    end
    table.sort(result.matched_package_modules)
    table.sort(result.identified_shop_classes)
    table.sort(result.identified_task_classes)

    local GameObj = rawget(_G, "Game")
    if type(GameObj) == "table" then
        if type(GameObj.loaded) == "table" then
            for k, _ in pairs(GameObj.loaded) do
                result.total_game_loaded = result.total_game_loaded + 1
                local name = tostring(k)
                if matches_keywords(name) then
                    result.matched_game_modules[#result.matched_game_modules + 1] = name
                end
            end
            table.sort(result.matched_game_modules)
        end

        for k, v in pairs(GameObj) do
            local keyStr = tostring(k)
            if matches_keywords(keyStr) then
                result.global_game_systems[#result.global_game_systems + 1] = {
                    name = keyStr,
                    type = type(v),
                    class = (type(v) == "table" and (v.__cname or (v.Class and tostring(v.Class)))) or nil
                }
            end
        end
    end

    return result
end

-- ----------------------------------------------------------------------------
-- 5. Slate & UMG Widget Inspection
-- ----------------------------------------------------------------------------
local function getWidgetText(widget)
    if widget == nil then return "" end
    local text = ""
    pcall(function()
        if type(widget.GetText) == "function" then
            local t = widget:GetText()
            text = (type(t) == "string" and t) or (t ~= nil and tostring(t)) or ""
        elseif widget.Text ~= nil then
            local t = widget.Text
            text = (type(t) == "string" and t) or (t ~= nil and tostring(t)) or ""
        elseif type(widget.GetPlainText) == "function" then
            local t = widget:GetPlainText()
            text = (type(t) == "string" and t) or (t ~= nil and tostring(t)) or ""
        elseif widget.Content ~= nil then
            local t = widget.Content
            text = (type(t) == "string" and t) or (t ~= nil and tostring(t)) or ""
        elseif type(widget.GetContent) == "function" then
            local t = widget:GetContent()
            text = (type(t) == "string" and t) or (t ~= nil and tostring(t)) or ""
        end
    end)
    return text
end

local function getWidgetHierarchyPath(widget)
    if widget == nil then return "unknown" end
    local chain = {}
    local curr = widget
    local depth = 0
    while curr ~= nil and depth < 30 do
        depth = depth + 1
        local name = nil
        pcall(function()
            if type(curr.GetName) == "function" then
                name = tostring(curr:GetName())
            end
        end)
        if name == nil or name == "" then
            name = (type(curr) == "table" and (curr.__cname or curr.uid or curr.UID)) or tostring(curr)
        end
        chain[#chain + 1] = name
        local parent = nil
        pcall(function()
            if type(curr.GetParent) == "function" then
                parent = curr:GetParent()
            end
        end)
        curr = parent
    end

    -- Reverse chain to get Root -> Child path
    local reversed = {}
    for i = #chain, 1, -1 do
        reversed[#reversed + 1] = chain[i]
    end
    return table.concat(reversed, " / ")
end

local function inspectWidgetDetails(widget)
    if widget == nil then return nil end

    local wName = ""
    pcall(function()
        if type(widget.GetName) == "function" then
            wName = tostring(widget:GetName())
        end
    end)
    if wName == "" then
        wName = (type(widget) == "table" and (widget.__cname or widget.uid or widget.UID)) or tostring(widget)
    end

    local rawText = getWidgetText(widget)
    local sampleText = rawText:gsub("\r", ""):gsub("\n", " ")
    if #sampleText > 60 then
        sampleText = sampleText:sub(1, 60) .. "..."
    end

    -- Font inspection
    local font = nil
    pcall(function()
        if type(widget.GetFont) == "function" then
            font = widget:GetFont()
        elseif widget.Font ~= nil then
            font = widget.Font
        end
    end)

    local styleFont = nil
    pcall(function()
        if widget.DefaultTextStyleOverride ~= nil and widget.DefaultTextStyleOverride.Font ~= nil then
            styleFont = widget.DefaultTextStyleOverride.Font
        end
    end)

    local effectiveFont = font or styleFont
    local fontInfo = {
        font_object_path = "none",
        font_size = nil,
        letter_spacing_slate = nil,
        typeface_name = "unknown",
    }

    if effectiveFont ~= nil then
        pcall(function()
            fontInfo.font_size = effectiveFont.Size
            fontInfo.letter_spacing_slate = effectiveFont.LetterSpacing
            if effectiveFont.TypefaceFontName ~= nil then
                fontInfo.typeface_name = tostring(effectiveFont.TypefaceFontName)
            end
            local fontObj = effectiveFont.FontObject
            if fontObj ~= nil then
                local objPath = nil
                pcall(function()
                    if type(fontObj.GetPathName) == "function" then
                        objPath = tostring(fontObj:GetPathName())
                    end
                end)
                if (objPath == nil or objPath == "") and KismetSysLib ~= nil and type(KismetSysLib.GetPathName) == "function" then
                    pcall(function()
                        objPath = tostring(KismetSysLib.GetPathName(fontObj))
                    end)
                end
                if objPath == nil or objPath == "" then
                    objPath = tostring(fontObj)
                end
                fontInfo.font_object_path = objPath
            end
        end)
    end

    -- UMG Widget-level letter spacing (if present on custom C7/KG text widget)
    local widgetLetterSpacing = nil
    pcall(function()
        if widget.LetterSpacing ~= nil then
            widgetLetterSpacing = widget.LetterSpacing
        elseif type(widget.GetLetterSpacing) == "function" then
            widgetLetterSpacing = widget:GetLetterSpacing()
        end
    end)

    -- Widget dimensions & desired size
    local desiredSize = { x = 0, y = 0 }
    pcall(function()
        if type(widget.GetDesiredSize) == "function" then
            local ds = widget:GetDesiredSize()
            if ds ~= nil then
                desiredSize.x = ds.X or ds.x or 0
                desiredSize.y = ds.Y or ds.y or 0
            end
        end
    end)

    local visibility = "unknown"
    pcall(function()
        if type(widget.GetVisibility) == "function" then
            visibility = tostring(widget:GetVisibility())
        elseif widget.Visibility ~= nil then
            visibility = tostring(widget.Visibility)
        end
    end)

    local hasCyrillic = rawText:find("[\208\209]") ~= nil

    -- Determine widget type class
    local widgetClass = (type(widget) == "table" and widget.__cname) or "Widget"
    pcall(function()
        if type(widget.GetClass) == "function" then
            local c = widget:GetClass()
            if c ~= nil and type(c.GetName) == "function" then
                widgetClass = tostring(c:GetName())
            end
        end
    end)

    return {
        name = wName,
        class = widgetClass,
        hierarchy_path = getWidgetHierarchyPath(widget),
        text_sample = sampleText,
        text_length = #rawText,
        has_cyrillic = hasCyrillic,
        font = fontInfo,
        widget_letter_spacing = widgetLetterSpacing,
        desired_size = desiredSize,
        visibility = visibility,
    }
end

-- ----------------------------------------------------------------------------
-- 6. Widget Tree Traversal
-- ----------------------------------------------------------------------------
local function walkAllWidgets(owner, visited, collector)
    if owner == nil or visited[owner] then return end
    visited[owner] = true

    collector(owner)

    -- Children via UPanelWidget
    local count = nil
    pcall(function()
        if type(owner.GetChildrenCount) == "function" then
            count = tonumber(owner:GetChildrenCount())
        end
    end)
    if count ~= nil and count > 0 then
        for i = 0, count - 1 do
            local child = nil
            pcall(function() child = owner:GetChildAt(i) end)
            if child ~= nil then
                walkAllWidgets(child, visited, collector)
            end
        end
    end

    -- Direct content container
    local content = nil
    pcall(function()
        if type(owner.GetContent) == "function" then
            content = owner:GetContent()
        end
    end)
    if content ~= nil then
        walkAllWidgets(content, visited, collector)
    end

    -- ListView / TileView virtualized row entries
    local getDisplayedEntries = nil
    pcall(function() getDisplayedEntries = owner.GetDisplayedEntryWidgets end)
    if type(getDisplayedEntries) == "function" then
        local displayedEntries = {}
        local ok, result = pcall(getDisplayedEntries, owner, displayedEntries)
        if ok then
            local entries = (type(result) == "table" and result) or displayedEntries
            for _, entry in pairs(entries) do
                walkAllWidgets(entry, visited, collector)
            end
        end
    end

    -- Unreal WidgetTree lookups
    local tree = nil
    pcall(function() tree = owner.WidgetTree end)
    if tree ~= nil and type(tree.GetAllWidgets) == "function" then
        local widgets = {}
        local ok, res = pcall(tree.GetAllWidgets, tree, widgets)
        local allWidgets = (ok and type(res) == "table" and res) or widgets
        for _, w in pairs(allWidgets) do
            walkAllWidgets(w, visited, collector)
        end
    end
end

-- ----------------------------------------------------------------------------
-- 7. Panel Inspection Handler
-- ----------------------------------------------------------------------------
local function inspectPanel(component, triggerReason)
    if component == nil then return end

    local uid = tostring(component.uid or component.UID or component.__cname or "UnknownPanel")
    local rootWidget = component.userWidget or component.widget
    local view = component.view

    local panelWidgets = {}
    local visited = setmetatable({}, { __mode = "k" })

    local function checkAndCollect(w)
        if w == nil then return end
        -- Check if it is a text-bearing widget
        local isText = false
        pcall(function()
            if type(w.GetText) == "function" or w.Text ~= nil or type(w.GetPlainText) == "function"
                or type(w.GetFont) == "function" or w.Font ~= nil
                or (w.DefaultTextStyleOverride ~= nil and w.DefaultTextStyleOverride.Font ~= nil) then
                isText = true
            end
        end)
        if isText then
            local details = inspectWidgetDetails(w)
            if details ~= nil then
                panelWidgets[#panelWidgets + 1] = details
            end
        end
    end

    if rootWidget ~= nil then
        walkAllWidgets(rootWidget, visited, checkAndCollect)
    end

    if type(view) == "table" then
        for _, vw in pairs(view) do
            if vw ~= nil and type(vw) ~= "function" then
                walkAllWidgets(vw, visited, checkAndCollect)
            end
        end
    end

    -- Walk any child UIComponents
    if type(component._childComponents) == "table" then
        for _, child in pairs(component._childComponents) do
            local childRoot = child and (child.userWidget or child.widget)
            if childRoot ~= nil then
                walkAllWidgets(childRoot, visited, checkAndCollect)
            end
        end
    end

    Diagnostics.ActivePanels[uid] = {
        uid = uid,
        class_name = tostring(component.__cname or uid),
        last_event = triggerReason or "Manual",
        last_updated = format_timestamp(),
        text_widgets_count = #panelWidgets,
        widgets = panelWidgets,
    }

    Diagnostics.CapturedWidgetsCount = 0
    for _, p in pairs(Diagnostics.ActivePanels) do
        Diagnostics.CapturedWidgetsCount = Diagnostics.CapturedWidgetsCount + p.text_widgets_count
    end

    Diagnostics.RecentEvents[#Diagnostics.RecentEvents + 1] = {
        timestamp = format_timestamp(),
        panel = uid,
        event = triggerReason or "Refresh",
        widgets_found = #panelWidgets,
    }
    if #Diagnostics.RecentEvents > 50 then
        table.remove(Diagnostics.RecentEvents, 1)
    end

    Diagnostics.IsDirty = true
    report("Captured " .. #panelWidgets .. " text widgets for panel: " .. uid .. " (Reason: " .. tostring(triggerReason) .. ")")
end

-- ----------------------------------------------------------------------------
-- 8. Save Reports (JSON + TXT)
-- ----------------------------------------------------------------------------
local function generateTxtSummary(reportData)
    local lines = {}
    local function add(l) lines[#lines + 1] = tostring(l or "") end

    add("================================================================================")
    add(" LORD OF THE MYSTERIES — автономный отчет диагностики интерфейса и шрифтов")
    add(" Версия мода: " .. tostring(reportData.diagnostics_version) .. " | Сгенерировано: " .. tostring(reportData.timestamp))
    add("================================================================================")
    add("")
    add("--- 1. СРЕДА ВЫПОЛНЕНИЯ ---")
    add("Каталог Saved/Logs: " .. tostring(reportData.environment.saved_logs_dir))
    add("Всего модулей в package.loaded: " .. tostring(reportData.environment.modules.total_package_loaded))
    add("Всего модулей в Game.loaded:    " .. tostring(reportData.environment.modules.total_game_loaded))
    add("")

    add("--- 2. ИДЕНТИФИЦИРОВАННЫЕ КЛАССЫ МАГАЗИНОВ И КВЕСТОВ ---")
    add("Классы Магазинов:")
    for _, c in ipairs(reportData.environment.modules.identified_shop_classes) do
        add("  - " .. c)
    end
    add("Классы Заданий и Доски:")
    for _, c in ipairs(reportData.environment.modules.identified_task_classes) do
        add("  - " .. c)
    end
    add("")

    add("--- 3. АКТИВНЫЕ ПАНЕЛИ И ВИДЖЕТЫ (Всего виджетов: " .. tostring(reportData.summary.total_captured_widgets) .. ") ---")
    for _, panel in ipairs(reportData.active_panels) do
        add("--------------------------------------------------------------------------------")
        add("ПАНЕЛЬ: " .. tostring(panel.uid) .. " (Виджетов: " .. tostring(panel.text_widgets_count) .. ", Событие: " .. tostring(panel.last_event) .. ")")
        add("--------------------------------------------------------------------------------")
        for idx, w in ipairs(panel.widgets) do
            local f = w.font or {}
            add(string.format("[%02d] %-32s | Font: %-4s | Spacing(Slate): %-5s | Spacing(Widget): %-4s | Desired: (%d,%d)",
                idx,
                w.name:sub(1, 32),
                tostring(f.font_size or "-"),
                tostring(f.letter_spacing_slate or "-"),
                tostring(w.widget_letter_spacing or "-"),
                f.desired_size and f.desired_size.x or (w.desired_size and w.desired_size.x or 0),
                f.desired_size and f.desired_size.y or (w.desired_size and w.desired_size.y or 0)
            ))
            add("     Иерархия: " .. tostring(w.hierarchy_path))
            add("     Ассет шрифта: " .. tostring(f.font_object_path) .. " [" .. tostring(f.typeface_name) .. "]")
            add("     Текст: \"" .. tostring(w.text_sample) .. "\" (Длина: " .. tostring(w.text_length) .. ", Кириллица: " .. tostring(w.has_cyrillic) .. ")")
            add("")
        end
    end

    add("================================================================================")
    add("КОНЕЦ ОТЧЕТА")
    add("================================================================================")
    return table.concat(lines, "\r\n")
end

function Diagnostics:Flush()
    if not self.IsDirty and self.DumpCount > 0 then return end
    self.IsDirty = false
    self.DumpCount = self.DumpCount + 1
    self.LastDumpTime = format_timestamp()

    local logsDir = getSavedLogsDir()
    local jsonPath = logsDir .. "/lotm_diagnostics.json"
    local txtPath = logsDir .. "/lotm_diagnostics.txt"

    local reportData = {
        diagnostics_version = self.Version,
        timestamp = self.LastDumpTime,
        dump_count = self.DumpCount,
        environment = {
            saved_logs_dir = logsDir,
            modules = scanLoadedModules(),
        },
        summary = {
            total_active_panels = 0,
            total_captured_widgets = self.CapturedWidgetsCount,
        },
        active_panels = {},
        recent_events = self.RecentEvents,
    }

    local panelList = {}
    for _, p in pairs(self.ActivePanels) do
        panelList[#panelList + 1] = p
    end
    table.sort(panelList, function(a, b) return tostring(a.uid) < tostring(b.uid) end)
    reportData.active_panels = panelList
    reportData.summary.total_active_panels = #panelList

    -- Serialize JSON
    local jsonString = to_json_indented(reportData)
    local jsonSaved = saveOutputFile(jsonPath, jsonString)

    -- Serialize TXT summary
    local txtString = generateTxtSummary(reportData)
    local txtSaved = saveOutputFile(txtPath, txtString)

    if jsonSaved then
        report("Successfully saved diagnostics to: " .. jsonPath .. " (Panels: " .. #panelList .. ", Widgets: " .. self.CapturedWidgetsCount .. ")")
    else
        report("Warning: failed to save JSON to: " .. jsonPath .. ", attempting temp fallback")
        local tempDir = os.getenv("TEMP")
        if tempDir then
            saveOutputFile(tempDir .. "/lotm_diagnostics.json", jsonString)
            saveOutputFile(tempDir .. "/lotm_diagnostics.txt", txtString)
        end
    end
end

-- ----------------------------------------------------------------------------
-- 9. Automatic Hooks into UIComponent & Lifecycle
-- ----------------------------------------------------------------------------
local flushPending = false
local function requestDebouncedFlush(delaySeconds)
    if flushPending then return end
    flushPending = true
    delaySeconds = delaySeconds or 0.25

    local scheduled = false
    local GameObj = rawget(_G, "Game")
    if GameObj ~= nil and GameObj.NewUIManager ~= nil and type(GameObj.NewUIManager.AddTimerWithFunction) == "function" then
        scheduled = pcall(GameObj.NewUIManager.AddTimerWithFunction, GameObj.NewUIManager, delaySeconds, 1, function()
            flushPending = false
            Diagnostics:Flush()
        end)
    end
    if not scheduled then
        flushPending = false
        Diagnostics:Flush()
    end
end

local function installUIComponentHooks(targetClass)
    if type(targetClass) ~= "table" then return false end
    if rawget(targetClass, "__lotmDiagnosticsHooked") then return true end

    for _, methodName in ipairs({ "Open", "Refresh" }) do
        local original = rawget(targetClass, methodName)
        if type(original) == "function" then
            targetClass[methodName] = function(self, ...)
                local results = { original(self, ...) }
                pcall(function()
                    inspectPanel(self, methodName)
                    requestDebouncedFlush(0.20)
                end)
                return unpack(results)
            end
        end
    end

    rawset(targetClass, "__lotmDiagnosticsHooked", true)
    report("Successfully hooked UIComponent.Open and UIComponent.Refresh")
    return true
end

-- ----------------------------------------------------------------------------
-- 10. Periodic Timer Loop (2-second interval)
-- ----------------------------------------------------------------------------
local timerRunning = false
local function schedulePeriodicScan()
    if timerRunning then return end
    timerRunning = true

    local function onTick()
        -- Inspect any active panels present in NewUIManager or already tracked
        pcall(function()
            local GameObj = rawget(_G, "Game")
            if GameObj ~= nil and GameObj.NewUIManager ~= nil then
                -- Check open components table if accessible
                local openComps = GameObj.NewUIManager.openComponents or GameObj.NewUIManager.Components
                if type(openComps) == "table" then
                    for _, comp in pairs(openComps) do
                        if type(comp) == "table" and not comp.isDestroyed then
                            inspectPanel(comp, "TimerTick")
                        end
                    end
                end
            end
            if Diagnostics.IsDirty then
                Diagnostics:Flush()
            end
        end)

        -- Re-schedule next tick
        local GameObj = rawget(_G, "Game")
        if GameObj ~= nil and GameObj.NewUIManager ~= nil and type(GameObj.NewUIManager.AddTimerWithFunction) == "function" then
            pcall(GameObj.NewUIManager.AddTimerWithFunction, GameObj.NewUIManager, 2.0, 1, onTick)
        end
    end

    local GameObj = rawget(_G, "Game")
    if GameObj ~= nil and GameObj.NewUIManager ~= nil and type(GameObj.NewUIManager.AddTimerWithFunction) == "function" then
        pcall(GameObj.NewUIManager.AddTimerWithFunction, GameObj.NewUIManager, 2.0, 1, onTick)
        report("Periodic 2-second UI diagnostics timer started")
    end
end

-- ----------------------------------------------------------------------------
-- 11. Module Initialization
-- ----------------------------------------------------------------------------
local function initialize()
    report("Initializing LotmDiagnostics v" .. VERSION .. "...")

    -- Hook UIComponent immediately if loaded
    local loadedUIComp = package.loaded["Framework.KGFramework.KGUI.Core.UIComponent"]
        or rawget(_G, "UIComponent")
    if loadedUIComp ~= nil then
        installUIComponentHooks(loadedUIComp)
    end

    -- Hook via LOMModLoader if available
    local Loader = rawget(_G, "LOMModLoader")
    if Loader ~= nil and type(Loader.AfterLoad) == "function" then
        Loader.AfterLoad(
            "Framework.KGFramework.KGUI.Core.UIComponent",
            function(value, environment)
                installUIComponentHooks(value)
                return value
            end,
            2000000,
            "lotm.diagnostics.uicomponent"
        )

        if type(Loader.On) == "function" then
            Loader.On("after_main", function()
                report("after_main triggered: scanning environment and starting timers...")
                pcall(schedulePeriodicScan)
                pcall(function() Diagnostics:Flush() end)
            end, 2000000, "lotm.diagnostics.after_main")
        end
    end

    -- Initial flush to record starting environment
    Diagnostics:Flush()
    report("LotmDiagnostics v" .. VERSION .. " initialized successfully")
end

pcall(initialize)

_G.LotmDiagnostics = Diagnostics
return Diagnostics
