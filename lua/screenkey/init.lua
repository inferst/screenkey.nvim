local M = {}
local api = vim.api

local keys = {
    ["<TAB>"] = "󰌒",
    ["<CR>"] = "󰌑",
    ["<ESC>"] = "Esc",
    [" "] = "␣",
    ["<BS>"] = "󰌥",
    ["<DEL>"] = "Del",
    ["<LEFT>"] = "",
    ["<RIGHT>"] = "",
    ["<UP>"] = "",
    ["<DOWN>"] = "",
    ["<HOME>"] = "Home",
    ["<END>"] = "End",
    ["<PAGEUP>"] = "PgUp",
    ["<PAGEDOWN>"] = "PgDn",
    ["<INSERT>"] = "Ins",
    ["<F1>"] = "󱊫",
    ["<F2>"] = "󱊬",
    ["<F3>"] = "󱊭",
    ["<F4>"] = "󱊮",
    ["<F5>"] = "󱊯",
    ["<F6>"] = "󱊰",
    ["<F7>"] = "󱊱",
    ["<F8>"] = "󱊲",
    ["<F9>"] = "󱊳",
    ["<F10>"] = "󱊴",
    ["<F11>"] = "󱊵",
    ["<F12>"] = "󱊶",
    ["CTRL"] = "Ctrl",
    ["ALT"] = "󰘵",
}

local config = {
    win_opts = {
        relative = "editor",
        anchor = "SE",
        width = 40,
        height = 3,
        border = "single",
    },
    compress_after = 3,
}

local active = false
local bufnr, winnr = -1, -1
local ns_id = api.nvim_create_namespace("screenkey")
local queued_keys = {}

local function create_window()
    if active then
        return
    end

    bufnr = api.nvim_create_buf(false, true)
    winnr = api.nvim_open_win(bufnr, false, {
        relative = config.win_opts.relative,
        anchor = config.win_opts.anchor,
        title = "Screenkey",
        title_pos = "center",
        row = vim.o.lines - vim.o.cmdheight - 1,
        col = vim.o.columns - 1,
        width = config.win_opts.width,
        height = config.win_opts.height,
        style = "minimal",
        border = config.win_opts.border,
        focusable = false,
        noautocmd = true,
    })

    if winnr == 0 then
        error("Screenkey: failed to create window")
    end

    api.nvim_set_option_value("filetype", "screenkey", { buf = bufnr })
end

local function close_window()
    if not active then
        return
    end

    if bufnr ~= -1 and api.nvim_buf_is_valid(bufnr) then
        api.nvim_buf_delete(bufnr, { force = true })
    end

    if winnr ~= -1 and api.nvim_win_is_valid(winnr) then
        api.nvim_win_close(winnr, true)
    end

    bufnr, winnr = -1, -1
end

--- Explanation:
--- Vim sometimes packs multiple keys into one input, e.g. `jk` when exiting insert mode with `jk`.
--- For this reason, we need to split the input into individual keys and transform them into the
--- corresponding symbols.
--- see `:h keytrans()`
---@param key string
---@return string[]
local function transform_input(key)
    key = vim.fn.keytrans(key)
    ---@type string[]
    local split = {}
    local tmp = ""
    local diamond_open = false
    for i = 1, #key do
        local curr_char = key:sub(i, i)
        tmp = tmp .. curr_char
        if curr_char == "<" then
            diamond_open = true
        elseif curr_char == ">" then
            diamond_open = false
        end
        if not diamond_open then
            table.insert(split, tmp)
            tmp = ""
        end
    end

    ---@type string[]
    local transformed_keys = {}

    for _, k in pairs(split) do
        -- ignore mouse input (just use keyboard)
        if not (k:match("Left") or k:match("Right") or k:match("Middle") or k:match("Scroll")) then
            -- parse keyboard input
            if #k == 1 then
                table.insert(transformed_keys, k)
            elseif keys[k:upper()] then
                table.insert(transformed_keys, keys[k:upper()])
            else
                -- check ctrl combo keys
                local ctrl_match = k:match("^<C.-(.)>$")
                if ctrl_match then
                    -- check ctrl-shift combo keys
                    local shift_match = k:match("^<C%-S%-.>$")
                    if not shift_match then
                        ctrl_match = ctrl_match:lower()
                    end
                    table.insert(transformed_keys, string.format("%s+%s", keys["CTRL"], ctrl_match))
                end
            end
        end
    end

    return transformed_keys
end

---@return string
local function compress_output()
    local compressed_keys = {}

    local last_key = queued_keys[1]
    local duplicates = 0
    for _, key in ipairs(queued_keys) do
        if key == last_key then
            duplicates = duplicates + 1
        else
            if duplicates >= config.compress_after then
                table.insert(compressed_keys, string.format("%s..x%d", last_key, duplicates))
            else
                for _ = 1, duplicates do
                    table.insert(compressed_keys, last_key)
                end
            end
            last_key = key
            duplicates = 1
        end
    end
    -- check the last key
    if duplicates >= config.compress_after then
        table.insert(compressed_keys, string.format("%s..x%d", last_key, duplicates))
    else
        for _ = 1, duplicates do
            table.insert(compressed_keys, last_key)
        end
    end

    -- remove old entries
    local text = table.concat(compressed_keys, " ")
    while #text > config.win_opts.width - 2 do
        local removed = table.remove(compressed_keys, 1)
        -- HACK: don't touch this, please
        local num_removed = tonumber(string.match(removed:match("%.%.x%d$") or "1", "%d$"))
        for _ = 1, num_removed do
            table.remove(queued_keys, 1)
        end
        text = table.concat(compressed_keys, " ")
    end

    return text
end

local function display_text()
    local text = compress_output()
    -- center text inside of screenkey window
    local padding =
        string.rep(" ", math.floor((config.win_opts.width - api.nvim_strwidth(text)) / 2))
    local line = math.floor(config.win_opts.height / 2)
    api.nvim_buf_set_lines(
        bufnr,
        line,
        line + 1,
        false,
        { string.format("%s%s%s", padding, text, padding) }
    )
end

---@param opts? table
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.toggle()
    if active then
        close_window()
    else
        create_window()
    end
    active = not active
end

vim.on_key(function(_, typed)
    if not active or #typed == 0 then
        return
    end
    local transformed_keys = transform_input(typed)
    for _, k in pairs(transformed_keys) do
        table.insert(queued_keys, k)
    end
    display_text()
end, ns_id)

return M
