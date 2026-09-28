if exists("b:current_syntax")
  finish
endif

syn match sessmanHeader  /^\%(Session\|Project\|Help\):/ nextgroup=sessmanValue skipwhite
syn match sessmanValue   /.*/ contained
syn match sessmanSection /^\%(Servers\|Sessions\)\ze (\d\+)$/ nextgroup=sessmanCount skipwhite
syn match sessmanCount   /(\d\+)/ contained
" Entries: "  project:name  details"; names have no ':', '/' or spaces
syn match sessmanProject /^  \zs.\{-}\ze:\%((no session)\|[^:/ ]\+\)\%(  \|$\)/
syn match sessmanNoSession /:\zs(no session)\ze\%(  \|$\)/
syn match sessmanDetail  /\s\{2}\zs\%(current\|not saved\|\d\+[mhd] ago\|just now\).*$/ contains=sessmanCurrent,sessmanNotSaved
syn match sessmanCurrent /\<current\>/ contained
syn match sessmanNotSaved /\<not saved\>/ contained

hi def link sessmanHeader  Label
hi def link sessmanValue   Directory
hi def link sessmanSection PreProc
hi def link sessmanCount   Comment
hi def link sessmanProject Directory
hi def link sessmanNoSession Comment
hi def link sessmanDetail  Comment
hi def link sessmanCurrent DiagnosticOk
hi def link sessmanNotSaved WarningMsg

let b:current_syntax = "sessman"
