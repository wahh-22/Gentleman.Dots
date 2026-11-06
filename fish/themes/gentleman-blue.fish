# Night City Gentleman Blue Fish colors.

set -l surface "#070B1A"
set -l selection "#1A2440"
set -l text "#DBE9FF"
set -l dimmed "#4A5578"
set -l blue "#347AFF"
set -l cyan "#5CE1FF"
set -l violet "#7C5CFF"
set -l green "#4DFF88"
set -l red "#FF6B7A"
set -l orange "#FF9F1C"

# Syntax highlighting colors.
set -g fish_color_normal $text
set -g fish_color_command --bold $cyan
set -g fish_color_keyword --bold $violet
set -g fish_color_quote $green
set -g fish_color_redirection $blue
set -g fish_color_end $orange
set -g fish_color_error --bold $red
set -g fish_color_param $text
set -g fish_color_comment --dim $dimmed
set -g fish_color_selection --background=$selection
set -g fish_color_search_match --background=$selection
set -g fish_color_operator $cyan
set -g fish_color_escape $violet
set -g fish_color_option $cyan
set -g fish_color_autosuggestion --dim $dimmed

# Completion pager colors.
set -g fish_pager_color_progress --dim $dimmed
set -g fish_pager_color_prefix --bold $blue
set -g fish_pager_color_completion $text
set -g fish_pager_color_description --dim $dimmed
set -g fish_pager_color_selected_background --background=$selection
set -g fish_pager_color_secondary_background --background=$surface

# fzf colors.
set -gx FZF_DEFAULT_OPTS "--color=fg:$text,bg:-1,gutter:-1,hl:$cyan,fg+:$text,bg+:$selection,hl+:$blue,info:$dimmed,prompt:$blue,pointer:$violet,marker:$green,spinner:$orange,header:$cyan,border:$blue,separator:$surface,label:$dimmed"
