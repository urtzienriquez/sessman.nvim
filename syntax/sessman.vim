if exists("b:current_syntax")
  finish
endif

syn match sessmanHeader  /^\%(Session\|Project\|Help\):/ nextgroup=sessmanValue skipwhite
syn match sessmanValue   /.*/ contained
syn match sessmanSection /^\%(Running\|Saved\)\ze (\d\+)$/ nextgroup=sessmanCount skipwhite
syn match sessmanCount   /(\d\+)/ contained
syn match sessmanProject /^  \S\+$/
syn match sessmanUnnamed /^    \zs(unnamed)/
syn match sessmanDetail  /\s\{2}\zs\%(current\|unsaved\|\d\+[mhd] ago\|just now\).*$/ contains=sessmanCurrent,sessmanUnsaved
syn match sessmanCurrent /\<current\>/ contained
syn match sessmanUnsaved /\<unsaved\>/ contained

hi def link sessmanHeader  Label
hi def link sessmanValue   Directory
hi def link sessmanSection PreProc
hi def link sessmanCount   Comment
hi def link sessmanProject Directory
hi def link sessmanUnnamed Comment
hi def link sessmanDetail  Comment
hi def link sessmanCurrent DiagnosticOk
hi def link sessmanUnsaved WarningMsg

let b:current_syntax = "sessman"
