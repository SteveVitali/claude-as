# VHS tape (https://github.com/charmbracelet/vhs) for the README demo GIF.
# Render from the repo root:  vhs docs/demo.tape
# Runs entirely inside the sandbox built by docs/demo-env.sh (throwaway HOME,
# stand-in claude) and never touches your real Claude state.

Output docs/demo.gif

Set Shell bash
Set FontSize 15
Set Width 1100
Set Height 500
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

Hide
Type "source docs/demo-env.sh && clear"
Enter
Sleep 1s
Show

Type "claude-as list"
Enter
Sleep 2s

Type "claude-as work auth login"
Enter
Sleep 2.5s

Type "claude-as link work"
Enter
Sleep 1.5s

Type "claude-as list"
Enter
Sleep 3s

Type "claude-work auth status"
Enter
Sleep 2.5s

Type "ls ~/.claude-work/skills    # shared with ~/.claude"
Enter
Sleep 2s

Type "claude-as doctor work | tail -2"
Enter
Sleep 4s
