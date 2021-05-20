local builtins = require("null-ls.builtins")
local methods = require("null-ls.methods")
local main = require("null-ls")

local s = require("null-ls.state")
local c = require("null-ls.config")
local u = require("null-ls.utils")
local tu = require("test.utils")

local lsp = vim.lsp
local api = vim.api

-- need to wait for most LSP commands to pass through the client
-- setting this lower reduces testing time but is more likely to cause failures
local lsp_wait = function() vim.wait(400) end

main.setup()

describe("integration", function()
    after_each(function()
        vim.cmd("bufdo! bwipeout!")
        c.reset_sources()
    end)

    describe("code actions", function()
        local actions, null_ls_action
        before_each(function()
            c.register(builtins._test.toggle_line_comment)

            tu.edit_test_file("test-file.lua")
            lsp_wait()

            actions = lsp.buf_request_sync(api.nvim_get_current_buf(),
                                           methods.lsp.CODE_ACTION)
            null_ls_action = actions[1].result[1]
        end)

        after_each(function()
            actions = nil
            null_ls_action = nil
        end)

        it("should get code action", function()
            assert.equals(vim.tbl_count(actions[1].result), 1)

            assert.equals(null_ls_action.title, "Comment line")
            assert.equals(null_ls_action.command, methods.internal.CODE_ACTION)
        end)

        it("should apply code action", function()
            vim.lsp.buf.execute_command(null_ls_action)

            assert.equals(u.buf.content(nil, true),
                          "--print(\"I am a test file!\")\n")
        end)

        it("should adapt code action based on params", function()
            vim.lsp.buf.execute_command(null_ls_action)

            actions = lsp.buf_request_sync(api.nvim_get_current_buf(),
                                           methods.lsp.CODE_ACTION)
            null_ls_action = actions[1].result[1]
            assert.equals(null_ls_action.title, "Uncomment line")

            vim.lsp.buf.execute_command(null_ls_action)
            assert.equals(u.buf.content(nil, true),
                          "print(\"I am a test file!\")\n")
        end)

        it("should combine actions from multiple sources", function()
            c.register(builtins._test.mock_code_action)

            actions = lsp.buf_request_sync(api.nvim_get_current_buf(),
                                           methods.lsp.CODE_ACTION)

            assert.equals(vim.tbl_count(actions[1].result), 2)
        end)
    end)

    describe("diagnostics", function()
        before_each(function()
            c.register(builtins.markdown.write_good)

            tu.edit_test_file("test-file.md")
            lsp_wait()
        end)

        it("should get buffer diagnostics on attach", function()
            local buf_diagnostics = lsp.diagnostic.get()
            assert.equals(vim.tbl_count(buf_diagnostics), 1)

            local write_good_diagnostic = buf_diagnostics[1]
            assert.equals(write_good_diagnostic.message,
                          "\"really\" can weaken meaning")
            assert.equals(write_good_diagnostic.source, "write-good")
            assert.same(write_good_diagnostic.range, {
                start = {character = 7, line = 0},
                ["end"] = {character = 13, line = 0}
            })
        end)

        it("should update buffer diagnostics on text change", function()
            -- remove "really"
            api.nvim_buf_set_text(api.nvim_get_current_buf(), 0, 6, 0, 13, {})
            lsp_wait()

            assert.equals(vim.tbl_count(lsp.diagnostic.get()), 0)
        end)

        it("should combine diagnostics from multiple sources", function()
            vim.cmd("bufdo! bwipeout!")

            c.register(builtins._test.mock_diagnostics)
            tu.edit_test_file("test-file.md")
            lsp_wait()

            assert.equals(vim.tbl_count(lsp.diagnostic.get()), 2)
        end)
    end)
end)

-- wait for on_exit callback to prevent orphan processes
s.stop_client()
vim.wait(5000, function() return s.get().initialized == false end, 10)
