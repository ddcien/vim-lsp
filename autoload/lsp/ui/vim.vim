let s:last_req_id = 0

function! s:not_supported(what) abort
    return lsp#utils#error(a:what.' not supported for '.&filetype)
endfunction

function! lsp#ui#vim#implementation() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_implementation_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1
    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving implementation')
        return
    endif
    let l:ctx = { 'counter': len(l:servers), 'list':[], 'last_req_id': s:last_req_id, 'jump_if_one': 1 }
    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'textDocument/implementation',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \   'position': lsp#get_position(),
                    \ },
                    \ 'on_notification': function('s:handle_location', [l:ctx, l:server, 'implementation']),
                    \ })
    endfor

    echo 'Retrieving implementation ...'
endfunction

function! lsp#ui#vim#type_definition() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_type_definition_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1
    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving type definition')
        return
    endif
    let l:ctx = { 'counter': len(l:servers), 'list':[], 'last_req_id': s:last_req_id, 'jump_if_one': 1 }
    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'textDocument/typeDefinition',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \   'position': lsp#get_position(),
                    \ },
                    \ 'on_notification': function('s:handle_location', [l:ctx, l:server, 'type definition']),
                    \ })
    endfor

    echo 'Retrieving type definition ...'
endfunction

function! lsp#ui#vim#definition() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_definition_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1
    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving definition')
        return
    endif

    let l:ctx = { 'counter': len(l:servers), 'list':[], 'last_req_id': s:last_req_id, 'jump_if_one': 1 }
    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'textDocument/definition',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \   'position': lsp#get_position(),
                    \ },
                    \ 'on_notification': function('s:handle_location', [l:ctx, l:server, 'definition']),
                    \ })
    endfor

    echo 'Retrieving definition ...'
endfunction

function! lsp#ui#vim#references() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_references_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    let l:ctx = { 'counter': len(l:servers), 'list':[], 'last_req_id': s:last_req_id, 'jump_if_one': 0 }
    if len(l:servers) == 0
        call s:not_supported('Retrieving references')
        return
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'textDocument/references',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \   'position': lsp#get_position(),
                    \   'context': {'includeDeclaration': v:false},
                    \ },
                    \ 'on_notification': function('s:handle_location', [l:ctx, l:server, 'references']),
                    \ })
    endfor

    echo 'Retrieving references ...'
endfunction

function! lsp#ui#vim#rename() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_rename_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    if len(l:servers) == 0
        call s:not_supported('Renaming')
        return
    endif

    let l:new_name = input('new name: ', expand('<cword>'))

    if empty(l:new_name)
        echo '... Renaming aborted ...'
        return
    endif

    " TODO: ask the user which server it should use to rename if there are multiple
    let l:server = l:servers[0]
    " needs to flush existing open buffers
    call lsp#send_request(l:server, {
                \ 'method': 'textDocument/rename',
                \ 'params': {
                \   'textDocument': lsp#get_text_document_identifier(),
                \   'position': lsp#get_position(),
                \   'newName': l:new_name,
                \ },
                \ 'on_notification': function('s:handle_workspace_edit', [l:server, s:last_req_id, 'rename']),
                \ })

    echo ' ... Renaming ...'
endfunction

function! lsp#ui#vim#document_format() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_formatting_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    if len(l:servers) == 0
        call s:not_supported('Document formatting')
        return
    endif

    " TODO: ask user to select server for formatting
    let l:server = l:servers[0]
    call lsp#send_request(l:server, {
                \ 'method': 'textDocument/formatting',
                \ 'params': {
                \   'textDocument': lsp#get_text_document_identifier(),
                \   'options': {
                \       'tabSize': getbufvar(bufnr('%'), '&tabstop'),
                \       'insertSpaces': getbufvar(bufnr('%'), '&expandtab') ? v:true : v:false,
                \   },
                \ },
                \ 'on_notification': function('s:handle_text_edit', [l:server, s:last_req_id, 'document format']),
                \ })

    echo 'Formatting document ...'
endfunction

function! s:get_visual_selection_pos() abort
    " https://groups.google.com/d/msg/vim_dev/oCUQzO3y8XE/vfIMJiHCHtEJ
    " https://stackoverflow.com/a/6271254
    " getpos("'>'") doesn't give the right column so need to do extra processing
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return [0, 0, 0, 0]
    endif
    let lines[-1] = lines[-1][: column_end - (&selection ==# 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return [line_start, column_start, line_end, len(lines[-1])]
endfunction

function! lsp#ui#vim#document_range_format() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_range_formatting_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    if len(l:servers) == 0
        call s:not_supported('Document range formatting')
        return
    endif

    " TODO: ask user to select server for formatting
    let l:server = l:servers[0]

    let [l:start_lnum, l:start_col, l:end_lnum, l:end_col] = s:get_visual_selection_pos()
    call lsp#send_request(l:server, {
                \ 'method': 'textDocument/rangeFormatting',
                \ 'params': {
                \   'textDocument': lsp#get_text_document_identifier(),
                \   'range': {
                \       'start': { 'line': l:start_lnum - 1, 'character': l:start_col - 1 },
                \       'end': { 'line': l:end_lnum - 1, 'character': l:end_col - 1 },
                \   },
                \   'options': {
                \       'tabSize': getbufvar(bufnr('%'), '&shiftwidth'),
                \       'insertSpaces': getbufvar(bufnr('%'), '&expandtab') ? v:true : v:false,
                \   },
                \ },
                \ 'on_notification': function('s:handle_text_edit', [l:server, s:last_req_id, 'range format']),
                \ })

    echo 'Formatting document range ...'
endfunction

function! lsp#ui#vim#workspace_symbol() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_workspace_symbol_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving workspace symbols')
        return
    endif

    let l:query = input('query>')

    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'workspace/symbol',
                    \ 'params': {
                    \   'query': l:query,
                    \ },
                    \ 'on_notification': function('s:handle_symbol', [l:server, s:last_req_id, 'workspaceSymbol']),
                    \ })
    endfor

    echo 'Retrieving workspace symbols ...'
endfunction

function! lsp#ui#vim#document_symbol() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_symbol_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving symbols')
        return
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'textDocument/documentSymbol',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \ },
                    \ 'on_notification': function('s:handle_symbol', [l:server, s:last_req_id, 'documentSymbol']),
                    \ })
    endfor

    echo 'Retrieving document symbols ...'
endfunction

function! s:handle_executecommand(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif
    " TODO(Richard):
    call lsp#log('s:executecommand', a:data)
endfunction

function! lsp#ui#vim#workspace_executecommand(command) abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_execute_command_provider(v:val, a:command.command)')
    let s:last_req_id = s:last_req_id + 1

    let l:info = printf('Executing command [%s]', a:command.command)

    if len(l:servers) == 0
        return -1
    endif

    call lsp#log('lsp#ui#vim#workspace_executecommand', a:command)

    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'workspace/executeCommand',
                    \ 'params': a:command,
                    \ 'on_notification': function('s:handle_executecommand', [l:server, s:last_req_id, l:info]),
                    \ })
    endfor

    echo l:info . ' ...'
    return 0
endfunction

function! s:handle_signature_help(server, last_req_id, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif
    " TODO(Richard)
    call lsp#log('s:handle_signature_help', a:data)
endfunction

function! lsp#ui#vim#signature_help() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_signature_help_provider(v:val)')

    if len(l:servers) == 0
        call s:not_supported('Retrieving signature help')
        return
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'textDocument/signatureHelp',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \   'position': lsp#get_position(),
                    \ },
                    \ 'on_notification': function('s:handle_signature_help', [l:server, s:last_req_id]),
                    \ })
    endfor

    echo 'Retrieving signature help ...'
endfunction

function! s:handle_code_lens_resolved(codelenses) abort
    let l:dict = {}

    for l:codelens in a:codelenses
        let l:line = l:codelens['command']['arguments'][1]['line']
        let l:dict[l:line] = add(get(l:dict, l:line, []), l:codelens['command'])
    endfor

    for [l:line, l:commands] in items(l:dict)
        call sort(l:commands, {x, y -> x['arguments'][1]['character'] - y['arguments'][1]['character']})
        call map(l:commands, {_, x -> x['title']})
        call nvim_buf_set_virtual_text(0, 1025, str2nr(l:line), [['| ' . join(l:commands, ' | ') . ' |', 'Comment']], {})
    endfor
endfunction

function! s:handle_document_link_resolved(doclinks) abort
    for l:dl in a:doclinks
        let l:line = l:dl['range']['start']['line']
        let l:text = fnamemodify(resolve(lsp#utils#uri_to_path(l:dl['target'])), ':~:.')
        call nvim_buf_set_virtual_text(0, 1026, l:line, [['| ' . l:text . ' |', 'Comment']], {})
    endfor
endfunction

function! s:handle_code_lens_resolve(server, data) abort
    call handle_code_lens_resolved(a:data['response']['result'])
endfunction

function! s:handle_document_link_resolve(server, data) abort
    call handle_document_link_resolved(a:data['response']['result'])
endfunction

function! s:code_lens_resolve(server, codelens) abort
    call lsp#log('s:code_lens_resolve', a:codelens)
    call lsp#send_request(a:server, {
                \ 'method': 'codeLens/resolve',
                \ 'params': a:codelens,
                \ 'on_notification': function('s:handle_code_lens_resolve', [a:server]),
                \ })
endfunction

function! s:document_link_resolve(server, doclink) abort
    call lsp#log('s:document_link_resolve', a:doclink)
    call lsp#send_request(a:server, {
                \ 'method': 'documentLink/resolve',
                \ 'params': a:doclink,
                \ 'on_notification': function('s:handle_document_link_resolve', [a:server]),
                \ })
endfunction

function! s:handle_code_lens(server, last_req_id, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif
    call s:handle_code_lens_resolved(a:data['response']['result'])
    echo 'Code lens retrieved'
endfunction

function! s:handle_document_link(server, last_req_id, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif
    call s:handle_document_link_resolved(a:data['response']['result'])
    echo 'Document link retrieved'
endfunction

function! lsp#ui#vim#code_lens() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_code_lens_provider(v:val)')

    if len(l:servers) == 0
        call s:not_supported('Retrieving code lens')
        return
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'textDocument/codeLens',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \ },
                    \ 'on_notification': function('s:handle_code_lens', [l:server, s:last_req_id]),
                    \ })
    endfor

    echo 'Retrieving code lens ...'
endfunction

function! lsp#ui#vim#code_lens_clear() abort
    call nvim_buf_clear_namespace(0, 1025, 0, -1)
endfunction

function! lsp#ui#vim#code_lens_stop() abort
    let g:lsp_auto_show_codelens = 0
    call nvim_buf_clear_namespace(0, 1025, 0, -1)
endfunction

function! lsp#ui#vim#code_lens_resume() abort
    let g:lsp_auto_show_codelens = 1
    call lsp#ui#vim#code_lens()
endfunction

function! lsp#ui#vim#document_link() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_link_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    if len(l:servers) == 0
        call s:not_supported('Retrieving document link')
        return
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'textDocument/documentLink',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \ },
                    \ 'on_notification': function('s:handle_document_link', [l:server, s:last_req_id]),
                    \ })
    endfor

    echo 'Retrieving document link ...'
endfunction

function! lsp#ui#vim#document_link_clear() abort
    echo 'Clearing document link ...'
    call nvim_buf_clear_namespace(0, 1026, 0, -1)
    echo 'Document link cleared'
endfunction

function! lsp#ui#vim#document_highlight() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_highlight_provider(v:val)')
    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving document highlights')
        return
    endif

    let l:server = l:servers[0]
    call lsp#send_request(l:server, {
                \ 'method': 'textDocument/documentHighlight',
                \ 'params': {
                \   'textDocument': lsp#get_text_document_identifier(),
                \   'position': lsp#get_position(),
                \ },
                \ 'on_notification': function('s:handle_document_highlight', [l:server, s:last_req_id]),
                \ })

    echo 'Retrieving document highlights ...'
endfunction

function! lsp#ui#vim#document_highlight_clear() abort
    echo 'Clearing document highlights ...'
    call nvim_buf_clear_namespace(0, 1024, 0, -1)
    echo 'Document highlights cleared'
endfunction

" https://microsoft.github.io/language-server-protocol/specification#textDocument_codeAction
function! lsp#ui#vim#code_action() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_code_action_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1
    let s:diagnostics = lsp#ui#vim#diagnostics#get_diagnostics_under_cursor()

    if len(l:servers) == 0
        call s:not_supported('Code action')
        return
    endif

    if len(s:diagnostics) == 0
        echo 'No diagnostics found under the cursors'
        return
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
                    \ 'method': 'textDocument/codeAction',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \   'range': s:diagnostics['range'],
                    \   'context': {
                    \       'diagnostics' : [s:diagnostics],
                    \   },
                    \ },
                    \ 'on_notification': function('s:handle_code_action', [l:server, s:last_req_id, 'codeAction']),
                    \ })
    endfor

    echo 'Retrieving code actions ...'
endfunction

function! s:jump_to_location(loc) abort
    let l:idx = split(a:loc, '\.')[0]
    execute 'cc' l:idx
endfunction

function! s:show_locations() abort
    if get(g:, 'lsp_fzf_enable') && get(g:, 'loaded_fzf')
        let l:qfl = getqflist()
        call map(l:qfl, {idx, item -> string(idx + 1) . '. ' . fnamemodify(expand(bufname(item['bufnr'])), ":~:.") . ':' . string(item['lnum']) . ':' . string(item['col']) . ':' . item['text']})
        call fzf#run(fzf#wrap({
                    \ 'source': l:qfl,
                    \ 'sink': function('s:jump_to_location'),
                    \ 'options': '--reverse +m --prompt="Jump> "'
                    \ }))
        return
    endif
    botright copen
endfunction

function! s:handle_symbol(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server)
        return
    endif

    let l:list = lsp#ui#vim#utils#symbols_to_loc_list(a:data)

    call setqflist(l:list)

    if empty(l:list)
        call lsp#utils#error('No ' . a:type .' found')
    else
        echo 'Retrieved ' . a:type
        call s:show_locations()
    endif
endfunction

function! s:handle_location(ctx, server, type, data) abort "ctx = {counter, list, jump_if_one, last_req_id}
    if a:ctx['last_req_id'] != s:last_req_id
        return
    endif

    let a:ctx['counter'] = a:ctx['counter'] - 1

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server)
    else
        let a:ctx['list'] = a:ctx['list'] + lsp#ui#vim#utils#locations_to_loc_list(a:data)
    endif

    if a:ctx['counter'] == 0
        if empty(a:ctx['list'])
            call lsp#utils#error('No ' . a:type .' found')
        else
            if len(a:ctx['list']) == 1 && a:ctx['jump_if_one']
                normal! m'
                let l:loc = a:ctx['list'][0]
                let l:buffer = bufnr(l:loc['filename'])
                let l:cmd = l:buffer !=# -1 ? 'b ' . l:buffer : 'edit ' . l:loc['filename']
                execute l:cmd . ' | call cursor('.l:loc['lnum'].','.l:loc['col'].')'
                redraw
            else
                call setqflist(a:ctx['list'])
                echo 'Retrieved ' . a:type
                call s:show_locations()
            endif
        endif
    endif
endfunction

function! s:handle_workspace_edit(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data)
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server)
        return
    endif

    call s:apply_workspace_edits(a:data['response']['result'])

    echo 'Renamed'
endfunction

function! s:parse_highlight(hl)
    let l:list = []

    let l:hl = get(g:, 'lsp_document_highlight')[a:hl['kind']]
    let l:rg = a:hl['range']
    let l:sl = l:rg['start']['line']
    let l:el = l:rg['end']['line']

    for l:line in range(l:sl, l:el)
        let l:sc = l:line == l:sl ? l:rg['start']['character'] : 0
        let l:ec = l:line == l:el ? l:rg['end']['character'] : -1
        call add(l:list, [l:hl , l:line, l:sc, l:ec])
    endfor

    return l:list
endfunction

function! s:handle_document_highlight(server, last_req_id, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif
    for l:hl in a:data['response']['result']
        for [l:hl, l:line, l:sc, l:ec] in s:parse_highlight(l:hl)
            call nvim_buf_add_highlight(0, 1024, l:hl, l:line, l:sc, l:ec)
        endfor
    endfor
    echo 'Document highlighted'
endfunction

function! s:handle_text_edit(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to '. a:type . ' for ' . a:server)
        return
    endif

    call s:apply_text_edits(a:data['request']['params']['textDocument']['uri'], a:data['response']['result'])

    echo 'Document formatted'
endfunction

function! s:fix_it(action) abort
    let l:ret = 0

    if has_key(a:action, 'edit')
        call s:apply_workspace_edits(a:action['edit'])
    endif

    if has_key(a:action, 'command')
        if type(a:action['command']) == type('')
            let l:ret = lsp#ui#vim#workspace_executecommand(a:action)
        else
            let l:ret = lsp#ui#vim#workspace_executecommand(a:action['command'])
        endif
    endif

    if l:ret == 0
        return
    endif

    if a:action['command'] ==# 'cquery._applyFixIt'
        let l:edits = []
        for l:edit in a:action['arguments'][1]
            let l:e = deepcopy(l:edit)
            let l:e['range']['end']['character'] -= 1
            call add(l:edits, l:e)
        endfor
        call s:apply_workspace_edits({'changes': {a:action['arguments'][0]: l:edits}})
    endif

endfunction

function! s:fzf_fix_it(actions, action) abort
    let l:idx = split(a:action, '\.')[0]
    call s:fix_it(a:actions[l:idx - 1])
endfunction

function! s:show_actions(actions) abort
    if len(a:actions) == 1
        call s:fix_it(a:actions[0])
        return
    endif

    let l:idx = 0
    let l:actlist = []

    for l:action in a:actions
        if has_key(l:action, 'command')
            if type(l:action['command']) == type('')
                call add(l:actlist, string(l:idx + 1) . '. ' . l:action['command'] . ': ' . l:action['title'])
            else
                call add(l:actlist, string(l:idx + 1) . '. ' . l:action['command']['command'] . ': ' . l:action['title'])
            endif
        else
            call add(l:actlist, string(l:idx + 1) . '. ' . 'NA' . ': ' . l:action['title'])
        endif
        let l:idx += 1
    endfor

    if get(g:, 'lsp_fzf_enable') && get(g:, 'loaded_fzf')
        call fzf#run(fzf#wrap({
                    \ 'source': l:actlist,
                    \ 'sink': function('s:fzf_fix_it', [a:actions]),
                    \ 'options': '--reverse +m --prompt="FixIt> "'
                    \ }))
        return
    endif
    let l:idx = inputlist(l:actlist)
    if l:idx >= 1 && l:idx <= len(l:actlist)
        call s:fix_it(a:actions[l:idx - 1])
    endif
endfunction

function! s:handle_code_action(server, last_req_id, type, data) abort
    let l:codeActions = a:data['response']['result']

    call lsp#log('s:handle_code_action', l:codeActions)

    if empty(l:codeActions)
        echo 'No code actions found'
        return
    endif

    call s:show_actions(l:codeActions)
endfunction

" @params
"   workspace_edits - https://microsoft.github.io/language-server-protocol/specification#workspaceedit
function! s:apply_workspace_edits(workspace_edits) abort
    if has_key(a:workspace_edits, 'changes')
        let l:cur_buffer = bufnr('%')
        let l:view = winsaveview()
        for [l:uri, l:text_edits] in items(a:workspace_edits['changes'])
            call s:apply_text_edits(l:uri, l:text_edits)
        endfor
        if l:cur_buffer !=# bufnr('%')
            execute 'keepjumps keepalt b ' . l:cur_buffer
        endif
        call winrestview(l:view)
    endif
    if has_key(a:workspace_edits, 'documentChanges')
        let l:cur_buffer = bufnr('%')
        let l:view = winsaveview()
        for l:text_document_edit in a:workspace_edits['documentChanges']
            call s:apply_text_edits(l:text_document_edit['textDocument']['uri'], l:text_document_edit['edits'])
        endfor
        if l:cur_buffer !=# bufnr('%')
            execute 'keepjumps keepalt b ' . l:cur_buffer
        endif
        call winrestview(l:view)
    endif
endfunction

function! s:apply_text_edits(uri, text_edits) abort
    " https://microsoft.github.io/language-server-protocol/specification#textedit
    " The order in the array defines the order in which the inserted string
    " appear in the resulting text.
    "
    " The edits must be applied in the reverse order so the early edits will
    " not interfere with the position of later edits, they need to be applied
    " one at the time or put together as a single command.
    "
    " Example: {"range": {"end": {"character": 45, "line": 5}, "start":
    " {"character": 45, "line": 5}}, "newText": "\n"}, {"range": {"end":
    " {"character": 45, "line": 5}, "start": {"character": 45, "line": 5}},
    " "newText": "import javax.ws.rs.Consumes;"}]}}
    "
    " If we apply the \n first we will need adjust the line range of the next
    " command (so the import will be written on the next line) , but if we
    " write the import first and then the \n everything will be fine.
    " If you do not apply a command one at  time, you will need to adjust the
    " range columns after which edit. You will get this (only one execution):
    "
    " execute 'keepjumps normal! 6G045laimport javax.ws.rs.Consumes;'" |
    " execute 'keepjumps normal! 6G045la\n'
    "
    " resulting in this:
    " import javax.servlet.http.HttpServletRequest;i
    " mport javax.ws.rs.Consumes;
    "
    " instead of this (multiple executions):
    " execute 'keepjumps normal! 6G045laimport javax.ws.rs.Consumes;'"
    " execute 'keepjumps normal! 6G045li\n'
    "
    " resulting in this:
    " import javax.servlet.http.HttpServletRequest;
    " import javax.ws.rs.Consumes;
    "
    "
    " The sort is also necessary since the LSP specification does not
    " guarantee that text edits are sorted.
    "
    " Example:
    " Initial text:  "abcdef"
    " Edits:
    " ((0, 0), (0, 1), "") - remove first character 'a'
    " ((0, 4), (0, 5), "") - remove fifth character 'e'
    " ((0, 2), (0, 3), "") - remove third character 'c'
    let l:text_edits = sort(deepcopy(a:text_edits), '<SID>sort_text_edit_desc')
    let l:i = 0

    try
        let l:was_paste = &paste
        let l:was_selection = &selection
        let l:was_virtualedit = &virtualedit
        let l:was_view = winsaveview()

        set paste
        set selection=exclusive
        set virtualedit=onemore

        while l:i < len(l:text_edits)
            let l:merged_text_edit = s:merge_same_range(l:i, l:text_edits)
            let l:cmd = s:build_cmd(a:uri, l:merged_text_edit['merged'])
            execute l:cmd
            let l:i = l:merged_text_edit['end_index']
        endwhile

    finally
        let &paste = l:was_paste
        let &selection = l:was_selection
        let &virtualedit = l:was_virtualedit
        call winrestview(l:was_view)
    endtry

endfunction

" Merge the edits on the same range so we do not have to reverse the
" text_edits  that are inserts, also from the specification:
" If multiple inserts have the same position, the order in the array
" defines the order in which the inserted strings appear in the
" resulting text
function! s:merge_same_range(start_index, text_edits) abort
    let l:i = a:start_index + 1
    let l:merged = deepcopy(a:text_edits[a:start_index])

    while l:i < len(a:text_edits) &&
                \ s:is_same_range(l:merged['range'], a:text_edits[l:i]['range'])

        let l:merged['newText'] .= a:text_edits[l:i]['newText']
        let l:i += 1
    endwhile

    return {'merged': l:merged, 'end_index': l:i}
endfunction

function! s:is_same_range(range1, range2) abort
    return a:range1['start']['line'] == a:range2['start']['line'] &&
                \ a:range1['end']['line'] == a:range2['end']['line'] &&
                \ a:range1['start']['character'] == a:range2['start']['character'] &&
                \ a:range1['end']['character'] == a:range2['end']['character']
endfunction

" https://microsoft.github.io/language-server-protocol/specification#textedit
function! s:is_insert(range) abort
    return a:range['start']['line'] == a:range['end']['line'] &&
                \ a:range['start']['character'] == a:range['end']['character']
endfunction

" Compares two text edits, based on the starting position of the range.
" Assumes that edits have non-overlapping ranges.
"
" `text_edit1` and `text_edit2` are dictionaries and represent LSP TextEdit type.
"
" Returns 0 if both text edits starts at the same position (insert text),
" positive value if `text_edit1` starts before `text_edit2` and negative value
" otherwise.
function! s:sort_text_edit_desc(text_edit1, text_edit2) abort
    if a:text_edit1['range']['start']['line'] != a:text_edit2['range']['start']['line']
        return a:text_edit2['range']['start']['line'] - a:text_edit1['range']['start']['line']
    endif

    if a:text_edit1['range']['start']['character'] != a:text_edit2['range']['start']['character']
        return a:text_edit2['range']['start']['character'] - a:text_edit1['range']['start']['character']
    endif

    return !s:is_insert(a:text_edit1['range']) ? -1 :
                \ s:is_insert(a:text_edit2['range']) ? 0 : 1
endfunction

function! s:build_cmd(uri, text_edit) abort
    let l:path = lsp#utils#uri_to_path(a:uri)
    let l:buffer = bufnr(l:path)
    let l:cmd = 'keepjumps keepalt ' . (l:buffer !=# -1 ? 'b ' . l:buffer : 'edit ' . l:path)
    let s:text_edit = deepcopy(a:text_edit)

    let s:text_edit['range'] = s:parse_range(s:text_edit['range'])
    let l:sub_cmd = s:generate_sub_cmd(s:text_edit)
    let l:escaped_sub_cmd = substitute(l:sub_cmd, '''', '''''', 'g')
    let l:cmd = l:cmd . " | execute 'keepjumps normal! " . l:escaped_sub_cmd . "'"

    call lsp#log('s:build_cmd', l:cmd)

    return l:cmd
endfunction

function! s:generate_sub_cmd(text_edit) abort
    if s:is_insert(a:text_edit['range'])
        return s:generate_sub_cmd_insert(a:text_edit)
    else
        return s:generate_sub_cmd_replace(a:text_edit)
    endif
endfunction

function! s:generate_sub_cmd_insert(text_edit) abort
    let l:start_line = a:text_edit['range']['start']['line']
    let l:start_character = a:text_edit['range']['start']['character']
    let l:new_text = s:parse(a:text_edit['newText'])

    let l:sub_cmd = s:preprocess_cmd(a:text_edit['range'])
    let l:sub_cmd .= s:generate_move_cmd(l:start_line, l:start_character)

    if len(l:new_text) == 0
        let l:sub_cmd .= 'x'
    else
        if l:start_character >= len(getline(l:start_line))
            let l:sub_cmd .= 'a'
        else
            let l:sub_cmd .= 'i'
        endif
    endif

    let l:sub_cmd .= printf('%s', l:new_text)

    return l:sub_cmd
endfunction

function! s:generate_sub_cmd_replace(text_edit) abort
    let l:start_line = a:text_edit['range']['start']['line']
    let l:start_character = a:text_edit['range']['start']['character']
    let l:end_line = a:text_edit['range']['end']['line']
    let l:end_character = a:text_edit['range']['end']['character']
    let l:new_text = substitute(a:text_edit['newText'], '\n$', '', '')

    let l:sub_cmd = s:preprocess_cmd(a:text_edit['range'])
    let l:sub_cmd .= s:generate_move_cmd(l:start_line, l:start_character) " move to the first position
    let l:sub_cmd .= 'v'
    let l:sub_cmd .= s:generate_move_cmd(l:end_line, l:end_character) " move to the last position

    if len(l:new_text) == 0
        let l:sub_cmd .= 'x'
    else
        let l:sub_cmd .= 'c'
        let l:sub_cmd .= printf('%s', l:new_text) " change text
    endif

    return l:sub_cmd
endfunction

function! s:generate_move_cmd(line_pos, character_pos) abort
    return printf('%dG%d|', a:line_pos, a:character_pos + 1)
endfunction

function! s:parse(text) abort
    " https://stackoverflow.com/questions/71417/why-is-r-a-newline-for-vim
    return substitute(a:text, '\(^\n|\n$\|\r\n\)', '\r', 'g')
endfunction

function! s:preprocess_cmd(range) abort
    " preprocess by opening the folds, this is needed because the line you are
    " going might have a folding
    let l:preprocess = ''

    if foldlevel(a:range['start']['line']) > 0
        let l:preprocess .= a:range['start']['line']
        let l:preprocess .= 'GzO'
    endif

    if foldlevel(a:range['end']['line']) > 0
        let l:preprocess .= a:range['end']['line']
        let l:preprocess .= 'GzO'
    endif

    return l:preprocess
endfunction

" https://microsoft.github.io/language-server-protocol/specification#text-documents
" Position in a text document expressed as zero-based line and zero-based
" character offset, and since we are using the character as a offset position
" we do not have to fix its position
function! s:parse_range(range) abort
    let l:range = deepcopy(a:range)
    let l:range['start']['line'] += 1
    let l:range['end']['line'] += 1

    let l:linelen = col([l:range['end']['line'], '$']) - 1
    if l:range['end']['character'] > l:linelen
        let l:range['end']['line'] += 1
        let l:range['end']['character'] = 0
    endif

    let l:range['start']['character'] = virtcol([l:range['start']['line'], l:range['start']['character']])
    let l:range['end']['character'] = virtcol([l:range['end']['line'], l:range['end']['character']])

    return l:range
endfunction
