# VHS tape for the GitHub social preview image (Settings → Social preview).
# Render from the repo root:  vhs docs/social-preview.tape
# Uses the same sandbox as the demo (docs/demo-env.sh); no real Claude state.

Output "/tmp/claude-as-social.gif"

Set Shell bash
Set FontSize 30
Set Width 1280
Set Height 640
Set Padding 60
Set Theme "Catppuccin Mocha"

Hide
Type "source docs/demo-env.sh && claude-as setup acme >/dev/null 2>&1 && claude-as acme auth login >/dev/null 2>&1 && claude-as setup lab >/dev/null 2>&1 && claude-as lab auth login >/dev/null 2>&1"
Enter
Sleep 1.5s
Type `printf '%s\n' "printf '\n\033[1;38;5;216mclaude-as\033[0m\n\033[1mMultiple Claude Code accounts on one machine.\033[0m\nSeparate logins, one shared setup.\n\n\033[2m\$\033[0m claude-as list\n'; claude-as list | cut -c3-" > /tmp/claude-as-card.sh && PS1='' && clear && bash /tmp/claude-as-card.sh`
Enter
Sleep 1.5s
Show
Sleep 0.5s
Screenshot docs/social-preview.png
