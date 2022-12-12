local cmp = require'cmp'

local source = { }

local last_compl_item = nil
local cb_cmp = nil
local cb_inf = nil
local compl_id = 0
local ter = nil
local qcell_opts = nil
local chunk_opts = nil

-- Translate symbols added by nvimcom to LSP kinds
local kindtbl = {["f"] = cmp.lsp.CompletionItemKind.Function,       -- function
                 ["$"] = cmp.lsp.CompletionItemKind.Struct,         -- data.frame
                 ["%"] = cmp.lsp.CompletionItemKind.Method,         -- logical
                 ["~"] = cmp.lsp.CompletionItemKind.Text,           -- character
                 ["{"] = cmp.lsp.CompletionItemKind.Value,          -- numeric
                 ["!"] = cmp.lsp.CompletionItemKind.Field,          -- factor
                 [";"] = cmp.lsp.CompletionItemKind.Constructor,    -- control
                 ["["] = cmp.lsp.CompletionItemKind.Struct,         -- list
                 ["<"] = cmp.lsp.CompletionItemKind.Class,          -- S4
                 [":"] = cmp.lsp.CompletionItemKind.Interface,      -- environment
                 ["&"] = cmp.lsp.CompletionItemKind.Event,          -- promise
                 ["l"] = cmp.lsp.CompletionItemKind.Module,         -- library
                 ["a"] = cmp.lsp.CompletionItemKind.Variable,       -- function argument
                 ["v"] = cmp.lsp.CompletionItemKind.Field,          -- data.frame column
                 ["*"] = cmp.lsp.CompletionItemKind.TypeParameter } -- other

local options = {filetypes = {'r', 'rmd', 'quarto', 'rnoweb', 'rhelp'},
                 doc_width = 58}

local get_chunk_opts = function()
    local copts = {}
    local f = io.open(vim.g.rplugin.home .. '/R/chunk_options.json', 'r')
    if f then
        local ctext = f:read("*all")
        f:close()
        local cjson = vim.fn.json_decode(ctext)
        if cjson then
            for _, v in pairs(cjson) do
                table.insert(copts,
                             {label = v['word'] .. '=',
                              kind = cmp.lsp.CompletionItemKind.Field,
                              sortText = "0",
                              documentation = {
                                  kind = cmp.lsp.MarkupKind.Markdown,
                                  value = v.user_data.descr}})
            end
        end
    end
    return copts
end

local get_quarto_cell_opts = function()
    local qopts  = {}
    local quarto_yaml_intel

    if vim.g.R_quarto_intel then
        quarto_yaml_intel = vim.g.R_quarto_intel
    else
        if vim.fn.has('win32') == 1 then
            local path = os.getenv("PATH")
            if path then
                local paths = vim.fn.split(path, ';')
                vim.fn.filter(paths, 'v:val =~? "quarto"')
                if #paths > 0 then
                    local qjson = string.gsub(paths[1], 'bin$', 'share/editor/tools/yaml/yaml-intelligence-resources.json')
                    qjson = string.gsub(qjson, '\\', '/')
                    local f = io.open(qjson, "r")
                    if f then
                        quarto_yaml_intel = qjson
                        io.close(f)
                    end
                end
            end
        elseif vim.fn.executable('quarto') == 1 then
            local handle = io.popen('which quarto')
            if handle then
                local quarto_bin = handle:read("*a")
                handle:close()
                local quarto_dir1 = string.gsub(quarto_bin, '(.*)/.-/.*', '%1')
                local f = io.open(quarto_dir1 .. '/share/editor/tools/yaml/yaml-intelligence-resources.json', "r")
                if f then
                    quarto_yaml_intel = quarto_dir1 .. '/share/editor/tools/yaml/yaml-intelligence-resources.json'
                    io.close(f)
                else
                    handle = io.popen('readlink ' .. quarto_bin)
                    if handle then
                        local quarto_dir2 = handle:read("*a")
                        handle:close()
                        quarto_dir2 = string.gsub(quarto_dir2, '(.*)/.-/.*', '%1')
                        if string.find(quarto_dir2, '^%.%./') then
                            while string.find(quarto_dir2, '^%.%./') do
                                quarto_dir2 = string.gsub(quarto_dir2, '^%.%./*', '')
                            end
                            quarto_dir2 = quarto_dir1 .. '/' .. quarto_dir2
                        end
                        f = io.open(quarto_dir2 .. '/share/editor/tools/yaml/yaml-intelligence-resources.json', "r")
                        if f then
                            quarto_yaml_intel = quarto_dir2 .. '/share/editor/tools/yaml/yaml-intelligence-resources.json'
                            io.close(f)
                        end
                    end
                end
            end
        end
    end

    if quarto_yaml_intel then
        local f = io.open(quarto_yaml_intel, 'r')
        if f then
            local yaml_txt = f:read("*all")
            f:close()
            local intel = vim.fn.json_decode(yaml_txt)
            if intel then
                local cell_keys = {'schema/cell-attributes.yml',
                'schema/cell-cache.yml',
                'schema/cell-codeoutput.yml',
                'schema/cell-figure.yml',
                'schema/cell-include.yml',
                'schema/cell-layout.yml',
                'schema/cell-pagelayout.yml',
                'schema/cell-table.yml',
                'schema/cell-textoutput.yml'}
                for _, s in pairs(cell_keys) do
                    if s and intel[s] then
                        for _, item in pairs(intel[s]) do
                            local lbl = item['name'] .. ': '
                            local descr = nil
                            if type(item['description']) == "string" then
                                descr = item['description']
                            else
                                descr = item['description']['long']
                            end
                            table.insert(qopts,
                                         {label = lbl,
                                          kind = cmp.lsp.CompletionItemKind.Field,
                                          sortText = "0",
                                          documentation = {
                                              kind = cmp.lsp.MarkupKind.Markdown,
                                              value = descr }})
                        end
                    end
                end
            end
        end
    end
    return qopts
end

source.new = function()
    local self = setmetatable({}, { __index = source })
    return self
end

source.setup = function(opts)
    options = vim.tbl_extend('force', options, opts or {})
end

source.get_keyword_pattern = function()
    return '[\\._@\\$:_[:digit:][:lower:][:upper:]\\u00FF-\\uFFFF]*'
end

source.get_trigger_characters = function()
    return { ':', '(', '"', '@', '$' }
end

source.get_debug_name = function()
    return 'cmp_nvim_r'
end

source.is_available = function()
    for _, v in pairs(options.filetypes) do
        if vim.bo.filetype == v then
            return true
        end
    end
    return false
end

local fix_doc = function(txt)
    -- The nclientserver replaces ' with \004 and \n with \002.
    -- We have to revert this:
    txt = string.gsub(txt , "\002", "\n")
    txt = string.gsub(txt , "\004", "'")
    return txt
end

local format_usage = function(fname, u)
    local fmt = "\n---\n\n```r\n"
    local line = fname .. '('
    local a

    for k, v in pairs(u) do
        if #v == 1 then
            a = v[1]
        elseif #v == 2 then
            a = v[1] .. ' = ' .. v[2]
        end

        -- a will be nil if u is an empty table
        if a then
            if k < #u then
                a = a .. ', '
            end
            if (#line + #a) > options.doc_width then
                fmt = fmt .. line .. "\n"
                line = "  "
            end
            line = line .. a
        end
    end
    fmt = fmt .. line .. ')\n```\n'
    return fmt
end

source.finish_glbenv_fun = function()
    local f = io.open(vim.g.rplugin.tmpdir .. "/args_for_completion", "r")
    if f then
        local u = f:read("*all")
        f:close()
        last_compl_item.documentation.value = last_compl_item.documentation.value ..
            format_usage(last_compl_item.label, vim.fn.eval("[" .. u .. "]"))
    end
    cb_inf({items = {last_compl_item}})
end

source.finish_get_summary = function()
    local f = io.open(vim.g.rplugin.tmpdir .. "/args_for_completion", "r")
    if f then
        local summary = f:read("*all")
        f:close()
        last_compl_item.documentation.value = last_compl_item.documentation.value .. summary
    end
    cb_inf({items = {last_compl_item}})
end

source.finish_get_args = function(a)
    last_compl_item.documentation.value = fix_doc(a)
    cb_inf({items = {last_compl_item}})
end

source.resolve = function(_, completion_item, callback)
    cb_inf = callback
    last_compl_item = completion_item

    if completion_item.user_data then
        if completion_item.user_data.env then
            completion_item.user_data.pkg = completion_item.user_data.env
        end
        if completion_item.user_data.pkg == '.GlobalEnv' then
            if completion_item.user_data.cls then
                if completion_item.user_data.cls == 'v' then
                    vim.fn.SendToNvimcom("E", 'nvimcom:::nvim.get.summary(' ..
                        completion_item.user_data.word .. ', 59)')
                    return nil
                elseif completion_item.user_data.cls == '{' or
                       completion_item.user_data.cls == '!' or
                       completion_item.user_data.cls == '~' then
                    vim.fn.SendToNvimcom("E", 'nvimcom:::nvim.get.summary(' ..
                       completion_item.label .. ', 59)')
                    return nil
                elseif completion_item.user_data.cls == 'f' then
                    vim.fn.SendToNvimcom("E", 'nvimcom:::nvim.GlobalEnv.fun.args("' ..
                            completion_item.label .. '")')
                    return nil
                end
             end
         else
             if completion_item.user_data.cls and completion_item.user_data.cls == 'A' then
                 -- Show arguments documentation when R isn't running
                 completion_item.documentation.value = fix_doc(completion_item.user_data.argument)
                 vim.fn.chansend(vim.g.rplugin.jobs["ClientServer"], "7" ..
                                 completion_item.user_data.pkg .. "\002" ..
                                 completion_item.user_data.fnm .. "\002" ..
                                 completion_item.user_data.itm .. "\n")
             elseif completion_item.user_data.cls and completion_item.user_data.cls == 'a' then
                 -- Show arguments documentation when R is running
                 completion_item.documentation.value = fix_doc(completion_item.user_data.argument)
                 callback(completion_item)
             elseif completion_item.user_data.cls and completion_item.user_data.cls == 'l' then
                 local txt = "**" .. completion_item.user_data.ttl ..
                     "**\n\n" .. completion_item.user_data.descr
                 completion_item.documentation.value = fix_doc(txt)
                 callback(completion_item)
             else
                 vim.fn.chansend(vim.g.rplugin.jobs["ClientServer"], "6" ..
                                 completion_item.label .. "\002" ..
                                 completion_item.user_data.pkg .. "\n")
             end
             return nil
         end
    end
    callback(completion_item)
end

source.complinfo = function(info)
    local doc
    if last_compl_item.documentation and last_compl_item.documentation.value then
        doc = last_compl_item.documentation.value .. "\n\n"
    else
        doc = ""
    end
    if info.ttl and info.ttl ~= '' then
        doc = doc .. '**' .. info.ttl .. '**\n'
    end
    if info.descr and info.descr ~= '' then
        doc = doc .. "\n" .. info.descr .. '\n'
    end
    if info.cls == 'f' and info.usage then
        doc = doc .. format_usage(info.word, info.usage)
    end
    local resp = last_compl_item
    resp.documentation = {kind = cmp.lsp.MarkupKind.Markdown,
                          value = fix_doc(doc) }
    cb_inf({items = {resp}})
end

source.asynccb = function(cid, compl)
    if cid ~= compl_id then
        return nil
    end

    local resp = {}
    for _, v in pairs(compl) do
        local kind = cmp.lsp.CompletionItemKind.TypeParameter
        local stxt = ""

        -- Completion of function arguments
        if v.args then
            for _, b in pairs(v.args) do
                local lbl = ""
                if #b == 2 then
                    lbl = b[1] .. " = "
                else
                    lbl = b[1]
                end
                table.insert(resp, {
                    label = lbl,
                    kind = kindtbl["a"],
                    sortText = "0",
                    user_data = {cls = "A", pkg = v.pkg, fnm = v.fnm, itm = b[1], argument = "Not yet"},
                    textEdit = {newText = lbl, range = ter},
                    documentation = {
                        kind = cmp.lsp.MarkupKind.Markdown,
                        value = ""
                    }
                })
            end
        else
            if v.user_data then
                if v.user_data.cls then
                    if kindtbl[v.user_data.cls] then
                        kind = kindtbl[v.user_data.cls]
                    end
                    if v.user_data.cls == 'a' then
                        stxt = '0'
                    else
                        stxt = '9'
                    end
                end
                table.insert(resp,
                {label = v['word'],
                kind = kind,
                user_data = v.user_data,
                sortText = stxt,
                textEdit = {newText = v['word'], range = ter},
                documentation = {
                    kind = cmp.lsp.MarkupKind.Markdown,
                    value = v['menu'] }})
            end
        end
    end
    cb_cmp(resp)
end

local GetPipedObj = function(line, lnum)
    if string.find(line, "|>%s*$") then
        return string.match(line, ".-([%w%._]+)%s*|>%s*$")
    end
    if string.find(line, "%%>%%%s*$") then
        return string.match(line, ".-([%w%._]+)%s*%%>%%%s*$")
    end
    local l
    l = vim.fn.getline(lnum - 1)
    if type(l) == "string" and string.find(l, "|>%s*$") then
        return string.match(l, ".-([%w%._]+)%s*|>%s*$")
    end
    if type(l) == "string" and string.find(l, "%%>%%%s*$") then
        return string.match(l, ".-([%w%._]+)%s*%%>%%%s*$")
    end
    return nil
end

local GetFirstObj = function(line, lnum)
    local no
    local piece
    local funname
    local firstobj
    local pkg
    no = 0
    local op
    op = string.byte("(")
    local cp
    cp = string.byte(")")
    local idx
    repeat
        idx = #line
        while idx > 0 do
            if line:byte(idx) == op then
                no = no + 1
            elseif line:byte(idx) == cp then
                no = no - 1
            end
            if no == 1 then
                -- The opening parenthesis is here. Now, get the function and
                -- its first object (if in the same line)
                piece = string.sub(line, 1, idx - 1)
                funname = string.match(piece, ".-([%w%._]+)%s*$")
                if funname then
                    pkg = string.match(piece, ".-([%w%._]+)::" .. funname)
                end
                piece = string.sub(line, idx + 1)
                firstobj = string.match(piece, "%s-([%w%.%_]+)")
                if funname then
                    idx = string.find(line, funname)
                end
                break
            end
            idx = idx - 1
        end
        if funname then
            break
        end
        lnum = lnum - 1
        line = vim.fn.getline(lnum)
    until type(line) == "string" and string.find(line, "^%S") or lnum == 0
    return pkg, funname, firstobj, line, lnum, idx
end

local NeedRArguments = function(line, lnum)
    local funname = nil
    local firstobj = nil
    local funname2 = nil
    local firstobj2 = nil
    local listdf = nil
    local nline = nil
    local nlnum = nil
    local cnum = nil
    local pkg = nil
    pkg, funname, firstobj, nline, nlnum, cnum = GetFirstObj(line, lnum)

    -- Check if this is function for which we expect to complete data frame column names
    if funname then
        -- Check if the data.frame is supposed to be the first argument:
        for _, v in pairs(vim.g.R_fun_data_1) do
            if v == funname then
                listdf = 1
                break
            end
        end

        -- Check if the data.frame is supposed to be the first argument of the
        -- nesting function:
        if not listdf and cnum > 1 then
            nline = string.sub(nline, 1, cnum)
            for k, v in pairs(vim.g.R_fun_data_2) do
                for _, a in pairs(v) do
                    if funname == a then
                        _, funname2, firstobj2, nline, nlnum, _ = GetFirstObj(nline, nlnum)
                        if funname2 == k then
                            firstobj = firstobj2
                            listdf = 2
                            break
                        end
                    end
                end
            end
        end
    end

    -- Check if the first object was piped
    local pobj = GetPipedObj(nline, nlnum)
    if pobj then
        firstobj = pobj
    end
    local resp
    resp = {pkg = pkg, fnm = funname, fnm2 = funname2, firstobj = firstobj, listdf = listdf, firstobj2 = firstobj2, pobj = pobj}
    return resp
end


source.complete = function(_, request, callback)
    cb_cmp = callback

    -- Check if this is Rmd and the cursor is in the chunk header
    if request.context.filetype == 'rmd' and string.find(request.context.cursor_before_line, '^```{r') then
        if not chunk_opts then
            chunk_opts = get_chunk_opts()
        end
        callback({ items = chunk_opts })
        return
    end

    -- Check if the cursor is in R code
    local isr = true
    if request.context.filetype ~= 'r' then
        local lines = vim.api.nvim_buf_get_lines(request.context.bufnr, 0, request.context.cursor.row, true)
        local lnum = request.context.cursor.row
        if request.context.filetype == 'rmd' or request.context.filetype == 'quarto' then
            isr = false
            for i = lnum, 1, -1 do
                if string.find(lines[i], "^```{") then
                    isr = true
                    break
                elseif string.find(lines[i], "^```$") or string.find(lines[i], "^---$") or string.find(lines[i], "^%.%.%.$") then
                    return {}
                end
            end
        elseif request.context.filetype == 'rnoweb' then
            isr = false
            for i = lnum, 1, -1 do
                if string.find(lines[i], "^%s*<<.*>>=") then
                    isr = true
                    break
                elseif string.find(lines[i], "^@") then
                    return {}
                end
            end
        elseif request.context.filetype == 'rhelp' then
            isr = false
            for i = lnum, 1, -1 do
                if string.find(lines[i], [[\examples{]]) or string.find(lines[i], [[\usage{]]) then
                    isr = true
                    break
                elseif string.find(lines[i], "\\%w+{") then
                    return {}
                end
            end
        end
    end

    if not isr then
        return {}
    end

    -- Is the current cursor position within YAML header of an R block of code?
    if string.find(request.context.cursor_before_line, '^#| ') then
        if string.find(request.context.cursor_before_line, '^#| .*:') and not
            string.find(request.context.cursor_before_line, '^#| .*: !expr ') then
            return nil
        end
        if not string.find(request.context.cursor_before_line, '^#| .*: !expr ') then
            if not qcell_opts then
                qcell_opts = get_quarto_cell_opts()
            end
            callback({ items = qcell_opts })
            return
        end
    end

    -- check if the cursor is within rComment
    local snm = vim.fn.synIDattr(vim.fn.synID(request.context.cursor.row,
        request.context.cursor.col - 1, 1), "name")
    if snm == 'rComment' then
        return nil
    end

    -- required by nclientserver
    compl_id = compl_id + 1

    local wrd = string.sub(request.context.cursor_before_line, request.offset)
    ter = {
        start = {
            line = request.context.cursor.line,
            character = request.offset - 1,
        },
        ['end'] = {
            line = request.context.cursor.line,
            character = request.context.cursor.character,
        },
    }


    -- Should we complete function arguments?
    local nra
    nra = NeedRArguments(request.context.cursor_before_line,
                         request.context.cursor.row)

    if nra.fnm then
        -- We are passing arguments for a function

        -- Special completion for library and require
        if (nra.fnm == "library" or nra.fnm == "require") and (not nra.firstobj or nra.firstobj == wrd) then
            vim.fn.chansend(vim.g.rplugin.jobs["ClientServer"], "5" .. compl_id .. "\003\004" .. wrd .. "\n")
            return nil
        end

        if snm == 'rString' then
            return nil
        end

        if vim.g.rplugin.nvimcom_port == 0 then
            -- Get the arguments of the first function whose name matches nra.fnm
            if nra.pkg then
                vim.fn.chansend(vim.g.rplugin.jobs["ClientServer"], "5" .. compl_id .. "\003\005" .. wrd .. "\005" .. nra.pkg .. "::" .. nra.fnm .. "\n")
            else
                vim.fn.chansend(vim.g.rplugin.jobs["ClientServer"], "5" .. compl_id .. "\003\005" .. wrd .. "\005" .. nra.fnm .. "\n")
            end
            return nil
        else
            -- Get arguments according to class of first object
            vim.fn.delete(vim.g.rplugin.tmpdir .. "/args_for_completion")
            local msg
            msg = 'nvimcom:::nvim_complete_args("' .. compl_id .. '", "' .. nra.fnm .. '", "' .. wrd .. '"'
            if nra.firstobj then
                msg = msg .. ', firstobj = "' .. nra.firstobj .. '"'
            elseif nra.pkg then
                msg = msg .. ', pkg = "' .. nra.pkg .. '"'
            end
            if nra.firstobj and nra.listdf then
                msg = msg .. ', ldf = TRUE'
            end
            msg = msg .. ')'

            -- Save documentation of arguments to be used by nclientserver
            vim.fn.SendToNvimcom("E", msg)
            return nil
        end
    end

    if #wrd == 0 or snm == 'rString' then
        return nil
    end
    vim.fn.chansend(vim.g.rplugin.jobs["ClientServer"], "5" .. compl_id .. "\003" .. wrd .. "\n")

    return nil
end

return source
