# vhs tape — renders the fix loop (RED, apply the fix, GREEN) to assets/demo-fix-loop.gif.
#
# Prerequisite: vhs (https://github.com/charmbracelet/vhs) — `brew install vhs`.
# Render from the repo root:   vhs assets/demo-fix-loop.tape
#
# It copies the bundled sample-app fixture OUT of the repo (so the scanner treats it as its
# own project root), makes it a git repo so the fix can be applied as a patch, and puts an
# `appstore-precheck` shim on PATH so the demo shows the same command a user would type
# after `npm i -g` / `brew install`. The fix itself is assets/demo-fix-loop.patch.

Output assets/demo-fix-loop.gif

Set Shell bash
Set FontSize 13
Set Width 1360
Set Height 555
Set Padding 22
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "REPO=$PWD; rm -rf /tmp/apc-demo; mkdir -p /tmp/apc-demo/bin" Enter
Type "cp -R tests/fixtures/sample-app /tmp/apc-demo/habits" Enter
Type "cp assets/demo-fix-loop.patch /tmp/apc-demo/paywall-fix.patch" Enter
Type "printf '#!/bin/sh\nexec node %s/bin/cli.js $@\n' $REPO > /tmp/apc-demo/bin/appstore-precheck" Enter
Type "chmod +x /tmp/apc-demo/bin/appstore-precheck; export PATH=/tmp/apc-demo/bin:$PATH" Enter
Type "cd /tmp/apc-demo/habits && git init -q && git add -A && git -c user.email=demo@local -c user.name=demo commit -qm init" Enter
Type "export PS1=$'\\e[38;5;81m~/habits\\e[0m $ '" Enter
Type "clear" Enter
Show

Sleep 1s
Type "appstore-precheck"
Sleep 600ms
Enter
Sleep 7s

Type "git apply ../paywall-fix.patch"
Sleep 400ms
Enter
Sleep 1500ms

Ctrl+L
Sleep 800ms
Type "appstore-precheck"
Sleep 600ms
Enter
Sleep 7s

Hide
Type "cd $REPO && rm -rf /tmp/apc-demo" Enter
Show
