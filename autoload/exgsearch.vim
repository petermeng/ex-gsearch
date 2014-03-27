" variables {{{1
let s:title = "-GSearch-" 
let s:zoom_in = 0
let s:confirm_at = -1
let s:keymap = {}
" }}}

" functions {{{1

" exgsearch#bind_mappings {{{2
function exgsearch#bind_mappings()
    call ex#keymap#bind( s:keymap )
endfunction

" exgsearch#register_hotkey {{{2
function exgsearch#register_hotkey( priority, key, action, desc )
    call ex#keymap#register( s:keymap, a:priority, a:key, a:action, a:desc )
endfunction

" exgsearch#open_window {{{2

function! s:init_buffer()
    set filetype=exgsearch
endfunction

function exgsearch#open_window()
    let winnr = bufwinnr(s:title)
    if winnr == -1
        call ex#window#open( 
                    \ s:title, 
                    \ g:ex_gsearch_winsize,
                    \ g:ex_gsearch_winpos,
                    \ 1,
                    \ 1,
                    \ function('s:init_buffer')
                    \ )

        if s:confirm_at != -1
            call ex#hl#confirm_line(s:confirm_at)
        endif
    else
        exe winnr . 'wincmd w'
    endif
endfunction

" exgsearch#toggle_window {{{2
function exgsearch#toggle_window()
    let result = exgsearch#close_window()
    if result == 0
        call exgsearch#open_window()
    endif
endfunction

" exgsearch#close_window {{{2
function exgsearch#close_window()
    let winnr = bufwinnr(s:title)
    if winnr != -1
        call ex#window#close(winnr)
        return 1
    endif
    return 0
endfunction

" exgsearch#toggle_zoom {{{2
function exgsearch#toggle_zoom()
    let winnr = bufwinnr(s:title)
    if winnr != -1
        if s:zoom_in == 0
            let s:zoom_in = 1
            call ex#window#resize( winnr, g:ex_gsearch_winpos, g:ex_gsearch_winsize_zoom )
        else
            let s:zoom_in = 0
            call ex#window#resize( winnr, g:ex_gsearch_winpos, g:ex_gsearch_winsize )
        endif
    endif
endfunction

" exgsearch#confirm_select {{{2
" modifier: '' or 'shift'
function exgsearch#confirm_select(modifier)
    " check if the line is valid file line
    let line = getline('.') 

    " get filename 
    let filename = line

    " NOTE: GSF,GSFW only provide filepath information, so we don't need special process.
    let idx = stridx(line, ':') 
    if idx > 0 
        let filename = strpart(line, 0, idx) "DISABLE: escape(strpart(line, 0, idx), ' ') 
    endif 

    " check if file exists
    if findfile(filename) == '' 
        call ex#warning( filename . ' not found!' ) 
        return
    endif 

    " confirm the selection
    let s:confirm_at = line('.')
    call ex#hl#confirm_line(s:confirm_at)

    " goto edit window
    call ex#window#goto_edit_window()

    " if we don't start a new stack, we pop the old jump, so that the new one
    " will only take the old stack position while we are selecting our result. 
    " TODO:
    " let keepjumps_cmd = '' 
    " if !s:exGS_need_push_search_result 
    "     let keepjumps_cmd = 'keepjumps' 
    " endif 
    let keepjumps_cmd = 'keepjumps' 

    " open the file
    if bufnr('%') != bufnr(filename) 
        exe keepjumps_cmd . ' silent e ' . escape(filename,' ') 
    endif 

    if idx > 0 
        " get line number 
        let line = strpart(line, idx+1) 
        let idx = stridx(line, ":") 
        let linenr  = eval(strpart(line, 0, idx)) 
        exec keepjumps_cmd . ' call cursor(linenr, 1)' 

        " jump to the pattern if the code have been modified 
        let pattern = strpart(line, idx+2) 
        let pattern = '\V' . substitute( pattern, '\', '\\\', "g" ) 
        if search(pattern, 'cw') == 0 
            call ex#warning('Line pattern not found: ' . pattern)
        endif 
    endif 

    " go back to global search window 
    exe 'normal! zz'
    call ex#hl#target_line(line('.'))
    call ex#window#goto_plugin_window()
endfunction

" exgsearch#search {{{2

function! s:search_result_comp (line1, line2)
    let line1lst = matchlist(a:line1 , '^\([^:]*\):\(\d\+\):')
    let line2lst = matchlist(a:line2 , '^\([^:]*\):\(\d\+\):')
    if empty(line1lst) && empty(line2lst)
        return 0
    elseif empty(line1lst)
        return -1
    elseif empty(line2lst)
        return 1
    else
        if line1lst[1]!=line2lst[1]
            return line1lst[1]<line2lst[1]?-1:1
        else
            let linenum1 = eval(line1lst[2])
            let linenum2 = eval(line2lst[2])
            return linenum1==linenum2?0:(linenum1<linenum2?-1:1)
        endif
    endif
endfunction

function! s:sort_search_result( start, end )
    let lines = getline( a:start, a:end )
    silent call sort(lines, 's:search_result_comp')
    silent call setline(a:start, lines)
endfunction

function exgsearch#search( pattern, option )
    let s:confirm_at = -1
    let id_path = g:exvim_folder.'/ID' 

    " ignore case setup
    let ignore_case = g:ex_gsearch_ignore_case
    " smartcase check
    if match(a:pattern, '\u') == -1
        let ignore_case = 0
    endif

    " start search process
    if ignore_case
        echomsg 'search ' . a:pattern . '...(case insensitive)'
        let cmd = 'lid --result=grep -i -f' . id_path . ' ' . a:option . ' ' . a:pattern
    else
        echomsg 'search ' . a:pattern . '...(case sensitive)'
        let cmd = 'lid --result=grep -f' . id_path . ' ' . a:option . ' ' . a:pattern
    endif

    " TODO: online help
    let help = '" Press ? for help'
    let header = '---------- ' . a:pattern . ' ----------'
    let result = system(cmd)
    let text = help . "\n\n" . header . "\n" . result

    " open the global search window
    call exgsearch#open_window()

    " clear screen and put new result
    silent exec '1,$d _'
    silent 0put = text
    silent exec '$d'
    let start_line = 4
    let end_line = line('$')

    " sort the search result
    if g:ex_gsearch_enable_sort == 1
        if (end_line-start_line) <= g:ex_gsearch_sort_lines_threshold
            call s:sort_search_result ( start_line, end_line )
        endif
    endif

    " init search state
    silent normal gg
    let linenr = search(header,'w')
    silent call cursor(linenr,1)
    silent normal zz
endfunction

" exgsearch#filter {{{2
" option: 'pattern', 'file'
" reverse: 0, 1
function exgsearch#filter( pattern, option, reverse )
    if a:pattern == ''
        call ex#warning('Search pattern is empty. Please provide your search pattern')
        return
    endif

    let final_pattern = a:pattern
    if a:option == 'pattern'
        let final_pattern = '^.\+:\d\+:.*\zs' . a:pattern
    elseif a:option == 'file'
        let final_pattern = '\(.\+:\d\+:\)\&' . a:pattern
    endif
    let range = '4,$'

    " if reverse search, we first filter out not pattern line, then then filter pattern
    if a:reverse 
        let search_results = '\(.\+:\d\+:\).*'
        silent exec range . 'v/' . search_results . '/d'
        silent exec range . 'g/' . final_pattern . '/d'
    else
        silent exec range . 'v/' . final_pattern . '/d'
    endif
    silent call cursor( 4, 1 )
    call ex#hint('Filter ' . a:option . ': ' . a:pattern )
endfunction


" }}}1

" vim:ts=4:sw=4:sts=4 et fdm=marker:
