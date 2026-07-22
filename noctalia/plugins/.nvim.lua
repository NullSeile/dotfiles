-- local root_dir = vim.fn.getcwd()
--
-- return {
--     cmd = {
--         "luau-lsp",
--         "lsp",
--         "--definitions:@noctalia=" .. root_dir .. "/noctalia.d.luau",
--     },
--     settings = {
--         ["luau-lsp"] = {
--             ignoreGlobs = { "**/*.d.luau" },
--             platform = {
--                 type = "standard",
--             },
--             sourcemap = {
--                 enabled = false,
--             },
--         },
--     },
-- }

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.notice("Loading Luau LSP from: " .. root)

vim.lsp.config("luau_lsp", {
    root_markers = { ".luaurc" },
    cmd = {
        "luau-lsp",
        "lsp",
        "--definitions:noctalia=" .. root .. "/noctalia.d.luau",
    },
    settings = {
        ["luau-lsp"] = {
            platform = { type = "standard" },
            sourcemap = { enabled = false },
            ignoreGlobs = { "**/*.d.luau" },
        },
    },
})
