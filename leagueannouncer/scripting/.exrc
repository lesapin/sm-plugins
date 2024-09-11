if &cp | set nocp | endif
let s:cpo_save=&cpo
set cpo&vim
imap <C-R>	 <Plug>snipMateShow
imap <S-Tab> <Plug>snipMateBack
inoremap <silent> <Plug>snipMateShow =snipMate#ShowAvailableSnips()
inoremap <silent> <Plug>snipMateBack =snipMate#BackwardsSnippet()
inoremap <silent> <Plug>snipMateTrigger =snipMate#TriggerSnippet(1)
inoremap <silent> <Plug>snipMateNextOrTrigger =snipMate#TriggerSnippet()
xmap 	 <Plug>snipMateVisual
smap 	 <Plug>snipMateNextOrTrigger
map c "_d
xmap gx <Plug>NetrwBrowseXVis
nmap gx <Plug>NetrwBrowseX
smap <S-Tab> <Plug>snipMateBack
xnoremap <silent> <Plug>NetrwBrowseXVis :call netrw#BrowseXVis()
nnoremap <silent> <Plug>NetrwBrowseX :call netrw#BrowseX(netrw#GX(),netrw#CheckIfRemote(netrw#GX()))
snoremap <silent> <Plug>snipMateBack a=snipMate#BackwardsSnippet()
snoremap <silent> <Plug>snipMateNextOrTrigger a=snipMate#TriggerSnippet()
map <Insert> :new
map <Del> :bd!
nmap <F8> :TagbarToggle
map <silent> <F6> :w:make install
map <silent> <F5> :w:make
imap 	 <Plug>snipMateNextOrTrigger
imap 	 <Plug>snipMateShow
let &cpo=s:cpo_save
unlet s:cpo_save
set background=dark
set backspace=indent,eol,start
set belloff=all
set expandtab
set fileencodings=ucs-bom,utf-8,default,latin1
set helplang=en
set history=1000
set hlsearch
set ignorecase
set incsearch
set laststatus=2
set nomodeline
set printoptions=paper:letter
set ruler
set runtimepath=~/.vim,~/.vim/plugged/vim-addon-mw-utils,~/.vim/plugged/vim-snipmate,~/.vim/plugged/tagbar,/var/lib/vim/addons,/etc/vim,/usr/share/vim/vimfiles,/usr/share/vim/vim90,/usr/share/vim/vimfiles/after,/etc/vim/after,/var/lib/vim/addons/after,~/.vim/plugged/vim-snipmate/after,~/.vim/after
set shiftwidth=4
set showcmd
set showmatch
set smartcase
set statusline=%L\ %f\ %M\ %Y\ %R%=\ col:\ %c\ percent:\ %p%%\ 
set suffixes=.bak,~,.swp,.o,.info,.aux,.log,.dvi,.bbl,.blg,.brf,.cb,.ind,.idx,.ilg,.inx,.out,.toc
set tabstop=4
set wildignore=*.jpg,*.png,*.gif,*.pdf,*.img
set wildmenu
set wildmode=list:longest
" vim: set ft=vim :
