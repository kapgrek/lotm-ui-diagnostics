-- ============================================================================
-- Lord of the Mysteries (C7 / UE4 / LuaJIT) — Autonomous Diagnostic Mod
-- File: LotmDiagnostics.lua
-- Purpose: Collect detailed runtime UI, Slate font engine, and module dumps
--          to pinpoint font stretching, LetterSpacing, and asset resolution.
-- ============================================================================

local VERSION = "1.0.4"
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

local function reportError(context, err)
    local line = MODULE_TAG .. " [ERROR] in " .. tostring(context) .. ": " .. tostring(err)
    local logger = rawget(_G, "Log") or rawget(_G, "LaunchLog") or rawget(_G, "LuaCLogger")
    if logger ~= nil then
        if type(logger.Error) == "function" then
            pcall(logger.Error, line)
        elseif type(logger.Info) == "function" then
            pcall(logger.Info, line)
        end
    end
    pcall(function()
        local tempDir = os.getenv("TEMP") or "."
        local f = io.open(tempDir .. "/lotm_diagnostics_error.log", "a")
        if f then
            f:write(string.format("[%s] [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(context), tostring(err)))
            f:close()
        end
    end)
end

local function getSavedLogsDir()
    local savedDir = nil
    pcall(function()
        if FileLib ~= nil and PathsLib ~= nil and type(PathsLib.ProjectSavedDir) == "function" then
            local p = PathsLib.ProjectSavedDir()
            if p ~= nil and type(FileLib.GetFilePath) == "function" then
                savedDir = tostring(FileLib.GetFilePath(p))
            end
        end
    end)
    if savedDir == nil or savedDir == "" then
        pcall(function()
            if PathsLib ~= nil and type(PathsLib.ProjectSavedDir) == "function" then
                savedDir = tostring(PathsLib.ProjectSavedDir())
            end
        end)
    end
    if savedDir == nil or savedDir == "" then
        savedDir = "Saved"
    end
    savedDir = savedDir:gsub("\\", "/")
    if savedDir:sub(-1) == "/" then
        savedDir = savedDir:sub(1, -2)
    end
    return savedDir .. "/Logs"
end

local function saveOutputFile(filePath, content)
    local written = false
    pcall(function()
        local f = io.open(filePath, "wb")
        if f ~= nil then
            f:write(content)
            f:close()
            written = true
        end
    end)
    return written
end

-- ----------------------------------------------------------------------------
-- 2. Pure-Lua Zero-Dependency JSON Serializer (Crash-Proof)
-- ----------------------------------------------------------------------------
local json_escape_map = {}
for i = 0, 255 do
    if i == 34 then -- "
        json_escape_map[i] = "\\\""
    elseif i == 92 then -- \
        json_escape_map[i] = "\\\\"
    elseif i == 8 then -- \b
        json_escape_map[i] = "\\b"
    elseif i == 9 then -- \t
        json_escape_map[i] = "\\t"
    elseif i == 10 then -- \n
        json_escape_map[i] = "\\n"
    elseif i == 12 then -- \f
        json_escape_map[i] = "\\f"
    elseif i == 13 then -- \r
        json_escape_map[i] = "\\r"
    elseif i < 32 then
        json_escape_map[i] = string.format("\\u%04x", i)
    else
        json_escape_map[i] = string.char(i)
    end
end

local function escape_json_string(s)
    if type(s) ~= "string" then s = tostring(s or "") end
    local len = #s
    local res = {}
    for i = 1, len do
        local b = string.byte(s, i)
        res[i] = json_escape_map[b]
    end
    return table.concat(res)
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

local function to_json_indented(val, current_indent, visited, depth)
    visited = visited or {}
    depth = depth or 0
    if depth > 25 then return "\"<max_depth>\"" end

    current_indent = current_indent or ""
    local sub_indent = current_indent .. "  "
    local t = type(val)

    if val == nil then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "null" end
        if val == math.huge or val == -math.huge then return "null" end
        return tostring(val)
    elseif t == "string" then
        return "\"" .. escape_json_string(val) .. "\""
    elseif t == "table" then
        if visited[val] then return "\"<cyclic_ref>\"" end
        visited[val] = true

        if is_table_array(val) then
            if #val == 0 then
                visited[val] = nil
                return "[]"
            end
            local parts = {}
            for i = 1, #val do
                parts[#parts + 1] = sub_indent .. to_json_indented(val[i], sub_indent, visited, depth + 1)
            end
            visited[val] = nil
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. current_indent .. "]"
        else
            local keys = {}
            for k, _ in pairs(val) do
                keys[#keys + 1] = k
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            if #keys == 0 then
                visited[val] = nil
                return "{}"
            end
            local parts = {}
            for _, k in ipairs(keys) do
                local v = val[k]
                local keyStr = tostring(k)
                parts[#parts + 1] = sub_indent .. "\"" .. escape_json_string(keyStr) .. "\": " .. to_json_indented(v, sub_indent, visited, depth + 1)
            end
            visited[val] = nil
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
    ActivePanels = {},
    RecentEvents = {},
    CapturedWidgetsCount = 0,
    IsDirty = false,
}

local function format_timestamp()
    local ts = "unknown"
    pcall(function() ts = os.date("%Y-%m-%d %H:%M:%S") end)
    return ts
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

    pcall(function()
        if type(package) == "table" and type(package.loaded) == "table" then
            for k, _ in pairs(package.loaded) do
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
            table.sort(result.matched_package_modules)
            table.sort(result.identified_shop_classes)
            table.sort(result.identified_task_classes)
        end
    end)

    pcall(function()
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
                    local clsName = nil
                    pcall(function()
                        if type(v) == "table" then
                            clsName = rawget(v, "__cname") or (rawget(v, "Class") and tostring(rawget(v, "Class")))
                        end
                    end)
                    result.global_game_systems[#result.global_game_systems + 1] = {
                        name = keyStr,
                        type = type(v),
                        class = clsName
                    }
                end
            end
        end
    end)

    return result
end

-- ----------------------------------------------------------------------------
-- 5. Slate & UMG Widget Inspection
-- ----------------------------------------------------------------------------
local function getWidgetText(widget)
    if widget == nil then return "" end
    local text = ""
    pcall(function()
        local getText = nil
        pcall(function() getText = widget.GetText end)
        if type(getText) == "function" then
            local ok, t = pcall(getText, widget)
            if ok and t ~= nil then text = tostring(t) end
        end
        if text == "" then
            local getPT = nil
            pcall(function() getPT = widget.GetPlainText end)
            if type(getPT) == "function" then
                local ok, t = pcall(getPT, widget)
                if ok and t ~= nil then text = tostring(t) end
            end
        end
        if text == "" and widget.Text ~= nil then
            local val = nil
            pcall(function() val = widget.Text end)
            if val ~= nil then
                if type(val) == "string" then
                    text = val
                elseif type(val) == "userdata" then
                    local s = tostring(val)
                    if not s:find(":") and not s:find("0x") and not s:find("userdata:") and not s:find("TextBlock") then
                        text = s
                    end
                end
            end
        end
        if text == "" and widget.Content ~= nil then
            local cnt = nil
            pcall(function() cnt = widget.Content end)
            if cnt ~= nil and type(cnt) == "string" then
                text = cnt
            end
        end
    end)
    return text
end

local function getWidgetHierarchyPath(widget)
    if widget == nil then return "unknown" end
    local chain = {}
    local curr = widget
    local depth = 0
    while curr ~= nil and depth < 25 do
        depth = depth + 1
        local name = nil
        pcall(function()
            if type(curr.GetName) == "function" then
                name = tostring(curr:GetName())
            end
        end)
        if name == nil or name == "" then
            pcall(function()
                if type(curr) == "table" then
                    name = curr.__cname or curr.uid or curr.UID
                end
            end)
        end
        if name == nil or name == "" then
            name = tostring(curr)
        end
        chain[#chain + 1] = tostring(name)

        local parent = nil
        pcall(function()
            if type(curr.GetParent) == "function" then
                parent = curr:GetParent()
            end
        end)
        if parent == curr then break end
        curr = parent
    end

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
        pcall(function()
            if type(widget) == "table" then
                wName = tostring(widget.__cname or widget.uid or widget.UID or "")
            end
        end)
        if wName == "" then wName = tostring(widget) end
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
        end
    end)
    if font == nil then
        pcall(function() font = widget.Font end)
    end

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

    -- UMG Widget-level letter spacing
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

    local hasCyrillic = false
    for i = 1, #rawText do
        local b = string.byte(rawText, i)
        if b == 208 or b == 209 then
            hasCyrillic = true
            break
        end
    end

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
-- 6. Widget Tree Traversal & Inspection
-- ----------------------------------------------------------------------------
local function isTextWidget(w)
    if w == nil then return false end
    local twType = type(w)
    if twType ~= "userdata" and twType ~= "table" then return false end

    -- 1. UPanelWidget containers with children are NOT leaf text widgets
    local hasChildren = false
    pcall(function()
        if type(w.GetChildrenCount) == "function" and tonumber(w:GetChildrenCount()) > 0 then
            hasChildren = true
        end
    end)
    if hasChildren then return false end

    -- 2. Inspect class name
    local cname = ""
    pcall(function()
        if type(w.GetClass) == "function" then
            local c = w:GetClass()
            if c ~= nil and type(c.GetName) == "function" then
                cname = tostring(c:GetName())
            end
        end
    end)
    if cname == "" and twType == "table" and w.__cname then
        cname = tostring(w.__cname)
    end

    -- Known text widget classes
    if cname ~= "" then
        if cname:find("TextBlock") or cname:find("RichText") or cname:find("TextWidget") then
            return true
        end
        -- Composite user widgets (WBP_...) or UI panels are containers, not leaf text widgets
        if cname:find("^WBP_") or cname:find("_Panel") or cname:find("Component") then
            return false
        end
    end

    -- 3. Check for text methods (GetText / GetPlainText)
    local hasTextMethod = false
    pcall(function()
        if type(w.GetText) == "function" or type(w.GetPlainText) == "function" then
            hasTextMethod = true
        end
    end)
    if hasTextMethod then return true end

    -- 4. Has Font / DefaultTextStyleOverride AND valid string text
    local hasFont = false
    pcall(function()
        if type(w.GetFont) == "function" or w.Font ~= nil or w.DefaultTextStyleOverride ~= nil then
            hasFont = true
        end
    end)
    if hasFont then
        local rawT = getWidgetText(w)
        if rawT ~= "" then return true end
    end

    -- 5. Text property with non-empty string
    local hasStringText = false
    pcall(function()
        if type(w.Text) == "string" and w.Text ~= "" then
            hasStringText = true
        end
    end)
    if hasStringText then return true end

    return false
end

local function walkAllWidgets(owner, visited, collector)
    if owner == nil or visited[owner] then return end
    visited[owner] = true

    -- If owner is a Lua table (e.g. component or view table)
    if type(owner) == "table" then
        local rw = owner.userWidget or owner.widget or owner.panel or owner.RootWidget or owner.m_Widget or owner.m_UserWidget
        if rw ~= nil then
            walkAllWidgets(rw, visited, collector)
        end
        if type(owner.view) == "table" then
            for _, v in pairs(owner.view) do
                if v ~= nil and type(v) ~= "function" then
                    walkAllWidgets(v, visited, collector)
                end
            end
            if type(owner.view._widgetCache) == "table" then
                for _, v in pairs(owner.view._widgetCache) do
                    if v ~= nil and type(v) ~= "function" then
                        walkAllWidgets(v, visited, collector)
                    end
                end
            end
        end
        if type(owner._widgetCache) == "table" then
            for _, v in pairs(owner._widgetCache) do
                if v ~= nil and type(v) ~= "function" then
                    walkAllWidgets(v, visited, collector)
                end
            end
        end
        if type(owner._childComponents) == "table" then
            for _, child in pairs(owner._childComponents) do
                walkAllWidgets(child, visited, collector)
            end
        end
        -- Also scan direct fields of the component table that hold text or composite widgets
        for k, v in pairs(owner) do
            if type(k) == "string" and type(v) ~= "function" then
                if k:find("^Text") or k:find("^Rich") or k:find("^TB_") or k:find("^RTB_") or k:find("^WBP_") then
                    walkAllWidgets(v, visited, collector)
                end
            end
        end
        return
    end

    -- owner is a userdata / UObject: inspect it!
    pcall(collector, owner)

    -- If owner has WidgetTree, traverse RootWidget & GetAllWidgets
    local tree = nil
    pcall(function() tree = owner.WidgetTree end)
    if tree ~= nil then
        pcall(function()
            if tree.RootWidget ~= nil then
                walkAllWidgets(tree.RootWidget, visited, collector)
            end
        end)
        pcall(function()
            if type(tree.GetAllWidgets) == "function" then
                local tbl = {}
                local ok = pcall(tree.GetAllWidgets, tree, tbl)
                if ok and #tbl > 0 then
                    for _, w in ipairs(tbl) do
                        walkAllWidgets(w, visited, collector)
                    end
                elseif slua and type(slua.Array) == "function" then
                    local propCls = import and import("EPropertyClass")
                    local widgetCls = import and import("Widget")
                    if propCls and widgetCls then
                        local arr = slua.Array(propCls.Object, widgetCls)
                        if arr then
                            local ok2 = pcall(tree.GetAllWidgets, tree, arr)
                            if ok2 and arr.Num and arr.Get then
                                for idx = 0, arr:Num() - 1 do
                                    local item = arr:Get(idx)
                                    if item ~= nil then
                                        walkAllWidgets(item, visited, collector)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    -- Children via UPanelWidget (CanvasPanel, HorizontalBox, VerticalBox, Overlay, ScrollBox, etc.)
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

    -- Direct content container (UBorder, USizeBox, UButton, etc.)
    local content = nil
    pcall(function()
        if type(owner.GetContent) == "function" then
            content = owner:GetContent()
        end
    end)
    if content ~= nil then
        walkAllWidgets(content, visited, collector)
    end

    -- Virtualized ListView / TileView / TreeView entries
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
end

-- ----------------------------------------------------------------------------
-- 7. Panel Inspection Handler
-- ----------------------------------------------------------------------------
local function inspectPanel(component, triggerReason)
    if component == nil then return end

    local uid = "UnknownPanel"
    pcall(function()
        uid = tostring(component.uid or component.UID or component.__cname or "UnknownPanel")
    end)

    local rootWidget = nil
    pcall(function()
        rootWidget = component.userWidget or component.widget or component.panel or (type(component) ~= "table" and component)
    end)
    local view = nil
    pcall(function() view = component.view end)

    local panelWidgets = {}
    local collected = setmetatable({}, { __mode = "k" })
    local visited = setmetatable({}, { __mode = "k" })

    local function checkAndCollect(w)
        if w == nil or collected[w] then return end
        if isTextWidget(w) then
            collected[w] = true
            local details = nil
            pcall(function() details = inspectWidgetDetails(w) end)
            if details ~= nil then
                panelWidgets[#panelWidgets + 1] = details
            end
        end
    end

    -- 1. Walk component itself (handles table references, view, _childComponents)
    walkAllWidgets(component, visited, checkAndCollect)

    -- 2. Walk root widget explicitly
    if rootWidget ~= nil then
        walkAllWidgets(rootWidget, visited, checkAndCollect)
    end

    -- 3. Probe common text widget names directly via UIFunctionLibrary / WidgetTree / View
    local probeNames = {
        "Text_TargetDesc", "Text_Name", "Text_ChapterName", "Text_Title", "Text_Content",
        "Text_Tips", "Text_BtnName", "Text_Use", "Text_Used", "TextUsing", "Text_State",
        "Text_Status", "Text_Apply", "Text_Equip", "RichText_Use", "Button_Text",
        "RichText_Hint01", "RichText_Hint02", "RichText_Path", "Text_Price", "Text_Cost",
        "Text_Num", "Text_Count", "Text_Level", "Text_Gold", "Text_ItemName", "Text_TaskName",
        "Text_Recommend", "Text_Extra", "Text_Reset", "TB_Word", "Text_lua", "Text2_lua",
        "Text_Desc", "Text_Detail", "Text_Quality", "Text_Attr", "Text_Coin", "Text_Diamond",
        "Text_GoldCoin", "Text_SilverCoin", "Text_CopperCoin", "Text_PlayerName", "Text_RoleName"
    }

    local uiLib = safe_import("UIFunctionLibrary")
    local findWidgetFn = uiLib and uiLib.FindWidget

    for _, name in ipairs(probeNames) do
        local found = nil
        if view ~= nil and view[name] ~= nil then
            found = view[name]
        end
        if found == nil and rootWidget ~= nil then
            pcall(function()
                if rootWidget.WidgetTree ~= nil then
                    if rootWidget.WidgetTree.FindWidget ~= nil then
                        found = rootWidget.WidgetTree:FindWidget(name)
                    elseif rootWidget.WidgetTree.GetWidgetFromName ~= nil then
                        found = rootWidget.WidgetTree:GetWidgetFromName(name)
                    end
                end
            end)
            if found == nil and type(findWidgetFn) == "function" then
                pcall(function()
                    found = findWidgetFn(rootWidget, name)
                end)
            end
        end
        if found ~= nil then
            checkAndCollect(found)
            walkAllWidgets(found, visited, checkAndCollect)
        end
    end

    local className = uid
    pcall(function() className = tostring(component.__cname or uid) end)

    Diagnostics.ActivePanels[uid] = {
        uid = uid,
        class_name = className,
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
    if type(reportData.environment.modules.identified_shop_classes) == "table" then
        for _, c in ipairs(reportData.environment.modules.identified_shop_classes) do
            add("  - " .. c)
        end
    end
    add("Классы Заданий и Доски:")
    if type(reportData.environment.modules.identified_task_classes) == "table" then
        for _, c in ipairs(reportData.environment.modules.identified_task_classes) do
            add("  - " .. c)
        end
    end
    add("")

    add("--- 3. АКТИВНЫЕ ПАНЕЛИ И ВИДЖЕТЫ (Всего виджетов: " .. tostring(reportData.summary.total_captured_widgets) .. ") ---")
    if type(reportData.active_panels) == "table" then
        for _, panel in ipairs(reportData.active_panels) do
            add("--------------------------------------------------------------------------------")
            add("ПАНЕЛЬ: " .. tostring(panel.uid) .. " (Виджетов: " .. tostring(panel.text_widgets_count) .. ", Событие: " .. tostring(panel.last_event) .. ")")
            add("--------------------------------------------------------------------------------")
            if type(panel.widgets) == "table" then
                for idx, w in ipairs(panel.widgets) do
                    local f = w.font or {}
                    add(string.format("[%02d] %-32s | Font: %-4s | Spacing(Slate): %-5s | Spacing(Widget): %-4s | Desired: (%d,%d)",
                        idx,
                        tostring(w.name):sub(1, 32),
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
        end
    end

    add("================================================================================")
    add("КОНЕЦ ОТЧЕТА")
    add("================================================================================")
    return table.concat(lines, "\r\n")
end

function Diagnostics:Flush()
    local ok, err = pcall(function()
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

        -- Serialize TXT summary
        local txtString = generateTxtSummary(reportData)

        -- 1. Save to Saved/Logs
        local jsonSaved = saveOutputFile(jsonPath, jsonString)
        local txtSaved = saveOutputFile(txtPath, txtString)

        -- 2. Always save to %TEMP%
        local tempDir = os.getenv("TEMP")
        if tempDir then
            saveOutputFile(tempDir .. "/lotm_diagnostics.json", jsonString)
            saveOutputFile(tempDir .. "/lotm_diagnostics.txt", txtString)
        end

        report(string.format("Diagnostics dumped #%d: SavedLogs=%s, Temp=true, Panels=%d, Widgets=%d",
            self.DumpCount, tostring(jsonSaved), #panelList, self.CapturedWidgetsCount))
    end)

    if not ok then
        reportError("Diagnostics:Flush", err)
    end
end

-- Public method called by external hooks (e.g. Init.lua)
function Diagnostics:InspectPanel(component, reason)
    local ok, err = pcall(function()
        inspectPanel(component, reason)
        self:Flush()
    end)
    if not ok then
        reportError("Diagnostics:InspectPanel", err)
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
    pcall(function()
        local GameObj = rawget(_G, "Game")
        if GameObj ~= nil and GameObj.NewUIManager ~= nil and type(GameObj.NewUIManager.AddTimerWithFunction) == "function" then
            GameObj.NewUIManager:AddTimerWithFunction(delaySeconds, 1, function()
                flushPending = false
                Diagnostics:Flush()
            end)
            scheduled = true
        end
    end)

    if not scheduled then
        flushPending = false
        Diagnostics:Flush()
    end
end

local function installUIComponentHooks(targetClass)
    if type(targetClass) ~= "table" then return false end
    if rawget(targetClass, "__lotmDiagnosticsHooked") then return true end

    local hookedCount = 0
    for _, methodName in ipairs({ "Open", "Refresh" }) do
        local original = targetClass[methodName]
        if type(original) == "function" then
            targetClass[methodName] = function(self, ...)
                local results = { original(self, ...) }
                pcall(function()
                    inspectPanel(self, methodName)
                    requestDebouncedFlush(0.20)
                end)
                return unpack(results)
            end
            hookedCount = hookedCount + 1
        end
    end

    rawset(targetClass, "__lotmDiagnosticsHooked", true)
    report("Hooked UIComponent methods: " .. tostring(hookedCount) .. " (Open/Refresh)")
    return hookedCount > 0
end

local function resolveUIComponentClass(value, environment)
    if type(value) == "table" then
        if type(value.Open) == "function" or type(value.Refresh) == "function" then
            return value
        end
        if type(value.UIComponent) == "table" then
            return value.UIComponent
        end
    end
    if type(environment) == "table" then
        if type(environment.UIComponent) == "table" then
            return environment.UIComponent
        end
    end
    local g = rawget(_G, "UIComponent")
    if type(g) == "table" then
        return g
    end
    if type(package) == "table" and type(package.loaded) == "table" then
        local pkg = package.loaded["Framework.KGFramework.KGUI.Core.UIComponent"]
        if type(pkg) == "table" then
            if type(pkg.Open) == "function" or type(pkg.Refresh) == "function" then
                return pkg
            end
            if type(pkg.UIComponent) == "table" then
                return pkg.UIComponent
            end
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- 10. Periodic Timer Loop (2-second interval)
-- ----------------------------------------------------------------------------
local timerRunning = false
local function schedulePeriodicScan()
    if timerRunning then return end
    timerRunning = true

    local function onTick()
        pcall(function()
            local GameObj = rawget(_G, "Game")
            if GameObj ~= nil and GameObj.NewUIManager ~= nil then
                local mgr = GameObj.NewUIManager
                for _, prop in ipairs({ "openComponents", "Components", "allComponents", "PanelMap" }) do
                    local tbl = nil
                    pcall(function() tbl = mgr[prop] end)
                    if type(tbl) == "table" then
                        for _, comp in pairs(tbl) do
                            if type(comp) == "table" and not comp.isDestroyed then
                                inspectPanel(comp, "TimerTick")
                            end
                        end
                    end
                end
            end
            if Diagnostics.IsDirty then
                Diagnostics:Flush()
            end
        end)

        pcall(function()
            local GameObj = rawget(_G, "Game")
            if GameObj ~= nil and GameObj.NewUIManager ~= nil and type(GameObj.NewUIManager.AddTimerWithFunction) == "function" then
                GameObj.NewUIManager:AddTimerWithFunction(2.0, 1, onTick)
            end
        end)
    end

    pcall(function()
        local GameObj = rawget(_G, "Game")
        if GameObj ~= nil and GameObj.NewUIManager ~= nil and type(GameObj.NewUIManager.AddTimerWithFunction) == "function" then
            GameObj.NewUIManager:AddTimerWithFunction(2.0, 1, onTick)
            report("Periodic 2-second UI diagnostics timer started")
        end
    end)
end

-- ----------------------------------------------------------------------------
-- 11. Module Initialization
-- ----------------------------------------------------------------------------
local function initialize()
    pcall(function()
        local tempDir = os.getenv("TEMP") or "."
        local f = io.open(tempDir .. "/lotm_diagnostics_error.log", "w")
        if f then f:close() end
    end)
    report("Initializing LotmDiagnostics v" .. VERSION .. "...")

    local compClass = resolveUIComponentClass()
    if compClass ~= nil then
        installUIComponentHooks(compClass)
    end

    local Loader = rawget(_G, "LOMModLoader")
    if Loader ~= nil and type(Loader.AfterLoad) == "function" then
        Loader.AfterLoad(
            "Framework.KGFramework.KGUI.Core.UIComponent",
            function(value, environment)
                local cls = resolveUIComponentClass(value, environment) or value
                installUIComponentHooks(cls)
                return value
            end,
            2000000,
            "lotm.diagnostics.uicomponent"
        )

        if type(Loader.On) == "function" then
            Loader.On("after_main", function()
                report("after_main triggered: scanning environment and starting timers...")
                pcall(schedulePeriodicScan)
                local okFlush, errFlush = pcall(function() Diagnostics:Flush() end)
                if not okFlush then
                    reportError("after_main Diagnostics:Flush", errFlush)
                end
            end, 2000000, "lotm.diagnostics.after_main")
        end
    end

    -- Initial test flush to verify file writing at launch
    local ok, err = pcall(function()
        Diagnostics:Flush()
    end)
    if not ok then
        reportError("initial Diagnostics:Flush", err)
    else
        report("LotmDiagnostics v" .. VERSION .. " initialized successfully")
    end
end

local okInit, errInit = pcall(initialize)
if not okInit then
    reportError("initialize", errInit)
end

_G.LotmDiagnostics = Diagnostics
return Diagnostics
