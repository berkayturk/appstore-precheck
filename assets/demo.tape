# vhs tape — renders a real appstore-precheck demo (GREEN then RED) to assets/demo.gif.
#
# Prerequisite: vhs (https://github.com/charmbracelet/vhs) — `brew install vhs`.
# Render from the repo root:   vhs assets/demo.tape
#
# It copies two bundled fixtures OUT of the repo (so the scanner treats each as its own
# project root) and runs the static scan + deterministic verdict on each.

Output assets/demo.gif

Set Shell bash
Set FontSize 16
Set Width 1100
Set Height 760
Set Padding 18
Set Theme "Dracula"

Hide
Type "SCAN=$PWD/skills/appstore-precheck/scripts/scan.sh; VERDICT=$PWD/skills/appstore-precheck/scripts/verdict.sh" Enter
Type "rm -rf /tmp/apc-green /tmp/apc-red" Enter
Type "cp -R tests/fixtures/clean-app /tmp/apc-green; cp -R tests/fixtures/sample-app /tmp/apc-red" Enter
Type "clear" Enter
Show

Type "# A clean app — nothing blocks submission" Sleep 800ms Enter
Type "cd /tmp/apc-green && bash $SCAN | bash $VERDICT" Sleep 600ms Enter
Sleep 3s

Type "clear" Sleep 400ms Enter
Type "# An app with rejection vectors — submission blocked" Sleep 800ms Enter
Type "cd /tmp/apc-red && bash $SCAN | tee /dev/stderr | bash $VERDICT" Sleep 600ms Enter
Sleep 4s

Hide
Type "rm -rf /tmp/apc-green /tmp/apc-red" Enter
Show
