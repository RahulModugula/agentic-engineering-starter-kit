# Render with: vhs demo/demo.tape   (needs vhs, ttyd, ffmpeg). Uses a throwaway HOME: touches nothing real.
Output demo/demo.gif
Require git
Require jq
Set FontSize 20
Set Width 1200
Set Height 640
Set TypingSpeed 35ms

Hide
Type "export HOME=$(mktemp -d) && mkdir -p $HOME/.claude && clear"
Enter
Show

Type "./install.sh            # dry run: shows every change, changes nothing"
Enter
Sleep 3s
Type "INSTALL_ANY_VERSION=1 ./install.sh --apply"
Enter
Sleep 3s
Type `echo '{"tool_input":{"command":"git push origin main"},"cwd":"/tmp"}' | ~/.claude/hooks/lane-guard.sh | jq -r .hookSpecificOutput.permissionDecisionReason`
Enter
Sleep 4s
Type "./install.sh --rollback   # exact undo"
Enter
Sleep 3s
