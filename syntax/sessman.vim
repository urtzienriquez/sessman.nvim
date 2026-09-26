if exists("b:current_syntax")
  finish
endif

syn match sessmanHeader  /^\%(Session\|Project\|Help\):/ nextgroup=sessmanValue skipwhite
syn match sessmanValue   /.*/ contained
syn match sessmanSection /^\%(Running\|Saved\|Unnamed nvim\)\ze (\d\+)$/ nextgroup=sessmanCount skipwhite
syn match sessmanCount   /(\d\+)/ contained
syn match sessmanProject /^  \S\+$/
syn match sessmanDetail  /\s\{2}\zs\%(current\|never saved\|saved \|plain nvim\).*$/ contains=sessmanCurrent
syn match sessmanCurrent /\<current\>/ contained

hi def link sessmanHeader  Label
hi def link sessmanValue   Directory
hi def link sessmanSection PreProc
hi def link sessmanCount   Comment
hi def link sessmanProject Directory
hi def link sessmanDetail  Comment
hi def link sessmanCurrent Special

let b:current_syntax = "sessman"
