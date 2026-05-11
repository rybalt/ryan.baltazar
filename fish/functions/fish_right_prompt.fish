function fish_right_prompt --description 'Right side: cmd duration + vi mode'
    set -l normal (set_color normal)
    set -l dim (set_color brblack)
    set -l parts

    # Duration (only when last command took >= 1s)
    if test "$CMD_DURATION" -ge 1000 2>/dev/null
        set -l secs (math --scale=1 "$CMD_DURATION/1000 % 60")
        set -l mins (math --scale=0 "$CMD_DURATION/60000 % 60")
        set -l hrs  (math --scale=0 "$CMD_DURATION/3600000")

        set -l out
        test $hrs  -gt 0; and set -a out "$hrs"h
        test $mins -gt 0; and set -a out "$mins"m
        test $secs -gt 0; and set -a out "$secs"s

        test (count $out) -gt 0; and set -a parts $dim'['(string join ' ' $out)']'$normal
    end

    # Vi mode (only when vi keybindings are active).
    # ANSI named colors so the terminal's theme picks the actual RGB.
    # The previous code referenced $fish_color_selection/$fish_color_match
    # — those are line-editor highlight vars (often background-shaded), so
    # they render invisible as foreground.  Normal stays dim (matches the
    # duration display); transient modes pop because they're worth noticing.
    if test "$fish_key_bindings" != fish_default_key_bindings
        set -l mode_color
        set -l mode_letter
        switch $fish_bind_mode
            case default
                set mode_color $dim
                set mode_letter N
            case insert
                set mode_color (set_color green)
                set mode_letter I
            case replace replace_one
                set mode_color (set_color red)
                set mode_letter R
            case visual
                set mode_color (set_color yellow)
                set mode_letter V
        end
        set -a parts $mode_color'['$mode_letter']'$normal
    end

    string join ' ' $parts
end
