" Vim filetype plugin file
" filetype: ledger
" Version: 0.1.0
" by Johann Klähn; Use according to the terms of the GPL>=2.
" vim:ts=2:sw=2:sts=2:foldmethod=marker

if exists("b:did_ftplugin")
  finish
endif

let b:did_ftplugin = 1

let b:undo_ftplugin = "setlocal ".
                    \ "foldmethod< foldtext< ".
                    \ "include< comments< iskeyword< omnifunc< "

" don't fill fold lines --> cleaner look
setl fillchars="fold: "
setl foldtext=LedgerFoldText()
setl foldmethod=syntax
setl include=^!include
setl comments=b:;
" so you can use C-X C-N completion on accounts
" FIXME: Does not work with something like:
"          Assets:Accountname with Spaces
setl iskeyword+=:
setl omnifunc=LedgerComplete

" You can set a maximal number of columns the fold text (excluding amount)
" will use by overriding g:ledger_maxwidth in your .vimrc.
" When maxwidth is zero, the amount will be displayed at the far right side
" of the screen.
if !exists('g:ledger_maxwidth')
  let g:ledger_maxwidth = 0
endif

if !exists('g:ledger_fillstring')
  let g:ledger_fillstring = ' '
endif

let s:rx_amount = '\('.
                \   '\%([0-9]\+\)'.
                \   '\%([,.][0-9]\+\)*'.
                \ '\|'.
                \   '[,.][0-9]\+'.
                \ '\)'.
                \ '\s*\%([[:alpha:]¢$€£]\+\s*\)\?'.
                \ '\%(\s*;.*\)\?$'

function! LedgerFoldText() "{{{1
  " find amount
  let amount = ""
  let lnum = v:foldstart
  while lnum <= v:foldend
    let line = getline(lnum)

    " Skip metadata/leading comment
    if line !~ '^\s\+;'
      " No comment, look for amount...
      let groups = matchlist(line, s:rx_amount)
      if ! empty(groups)
        let amount = groups[1]
        break
      endif
    endif
    let lnum += 1
  endwhile

  let fmt = '%s %s '
  " strip whitespace at beginning and end of line
  let foldtext = substitute(getline(v:foldstart),
                          \ '\(^\s\+\|\s\+$\)', '', 'g')

  " number of columns foldtext can use
  let columns = s:get_columns(0)
  if g:ledger_maxwidth
    let columns = min([columns, g:ledger_maxwidth])
  endif
  let columns -= s:multibyte_strlen(printf(fmt, '', amount))

  " add spaces so the text is always long enough when we strip it
  " to a certain width (fake table)
  if strlen(g:ledger_fillstring)
    " add extra spaces so fillstring aligns
    let filen = s:multibyte_strlen(g:ledger_fillstring)
    let folen = s:multibyte_strlen(foldtext)
    let foldtext .= repeat(' ', filen - (folen%filen))

    let foldtext .= repeat(g:ledger_fillstring,
                  \ s:get_columns(0)/filen)
  else
    let foldtext .= repeat(' ', s:get_columns(0))
  endif

  " we don't use slices[:5], because that messes up multibyte characters
  let foldtext = substitute(foldtext, '.\{'.columns.'}\zs.*$', '', '')

  return printf(fmt, foldtext, amount)
endfunction "}}}

function! LedgerComplete(findstart, base)
  if a:findstart
    let lnum = line('.')
    let line = getline('.')
    let lastcol = col('.') - 2
    if line =~ '^\d'
      let b:compl_context = 'payee'
      return -1
    elseif line =~ '^\s\+;'
      let b:compl_context = 'meta'
      return -1
    elseif line =~ '^\s\+'
      let b:compl_context = 'account'
      let firstcol = lastcol
      while firstcol >= 0 && (matchend(line, '^\%(\S\|\S \S\)\+', (firstcol - 1))-1) == lastcol
        let firstcol -= 1
      endwhile
      return firstcol
    else
      return -1
    endif
  else
    if b:compl_context == 'account'
      unlet! b:compl_context
      let hierarchy = split(a:base, ':')
      if a:base =~ ':$'
        call add(hierarchy, '')
      endif

      let results = LedgerFindInTree(LedgerGetAccountHierarchy(), hierarchy)
      call add(results, a:base)
      return reverse(results)
    else
      unlet! b:compl_context
      return []
    endif
  endif
endf

function! LedgerFindInTree(tree, levels)
  if empty(a:levels)
    return []
  endif
  let results = []
  let currentlvl = a:levels[0]
  let nextlvls = a:levels[1:]
  let branches = filter(keys(a:tree), 'v:val =~ ''^\V'.substitute(currentlvl, '\\', '\\\\', 'g').'''')
  for branch in branches
    call add(results, branch)
    if !empty(nextlvls)
      for result in LedgerFindInTree(a:tree[branch], nextlvls)
        call add(results, branch.':'.result)
      endfor
    endif
  endfor
  return results
endf

function! LedgerGetAccountHierarchy()
  let hierarchy = {}
  let accounts = map(getline(1, '$'), 'matchstr(v:val, ''^\s\+\zs[^[:blank:];]\%(\S \S\|\S\)\+\ze'')')
  let accounts = filter(accounts, 'v:val != ""')
  for name in accounts
    let last = hierarchy
    for part in split(name, ':')
      let last[part] = get(last, part, {})
      let last = last[part]
    endfor
  endfor
  return hierarchy
endf

" Helper functions {{{1
function! s:multibyte_strlen(text) "{{{2
   return strlen(substitute(a:text, ".", "x", "g"))
endfunction "}}}

function! s:get_columns(win) "{{{2
  " As long as vim doesn't provide a command natively,
  " we have to compute the available columns.
  " see :help todo.txt -> /Add argument to winwidth()/
  " FIXME: Although this will propably never be used with debug mode enabled
  "        this should take the signs column into account (:help sign.txt)
  let columns = (winwidth(a:win) == 0 ? 80 : winwidth(a:win)) - &foldcolumn
  if &number
    " line('w$') is the line number of the last line
    let columns -= max([len(line('w$'))+1, &numberwidth])
  endif
  return columns
endfunction "}}}

