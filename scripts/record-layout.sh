#!/usr/bin/env bash
#
# record-layout.sh — lay out Terminal.app for recording the Approach 1 run (macOS).
#
# Opens two Terminal windows side by side on the recording display, using a
# "Recording" profile with a large font, whose window titles show only a description of
# what the window shows (created on first use):
#
#   left   the Liferay logs, from the LDM project folder, reconnecting whenever the restore restarts the container
#   right  in the checkout this script lives in, with scripts/record-approach-1.sh typed
#          at the prompt but not run: press Enter to start
#
# The right window starts CLOCK_H pixels down, so the top-right corner of the screen
# (CLOCK_W x CLOCK_H) stays clear for a clock overlay.
#
# The recording display is the one whose name contains SCREEN_NAME (for example
# SCREEN_NAME=Built-in for a MacBook's own screen), or else the one whose size is
# SCREEN_W x SCREEN_H, wherever it sits in the arrangement. If none matches, the main
# display is used. The layout adapts to the display's size.
#
#   SCREEN_NAME          part of the display's name; overrides the size match
#   SCREEN_W, SCREEN_H   default 1920 x 1080
#   CLOCK_W, CLOCK_H     default 300 x 350
#   MENU_BAR             default 30: pixels kept clear for a menu bar macOS doesn't
#                        report; 0 when the menu bar is hidden
#   FONT, FONT_SIZE      default Menlo-Regular, 20
#   PROFILE              default Recording
#   LOGS_TITLE, RUN_TITLE  the two window titles
#   LDM_PROJECT          default devcon2026
#   LDM_DIR              default ~/ldm-verify/devcon2026; the logs window runs ldm from
#                        here, since ldm warns when run from the home directory
#
# Running it again replaces the windows a previous run opened.
#
# The right window types the command with zsh's `print -z`, so it needs zsh, the macOS
# default shell, and no Accessibility permission.
#

set -o errexit
set -o nounset
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCREEN_W="${SCREEN_W:-1920}"
SCREEN_H="${SCREEN_H:-1080}"
SCREEN_NAME="${SCREEN_NAME:-}"
CLOCK_W="${CLOCK_W:-300}"
CLOCK_H="${CLOCK_H:-350}"
FONT="${FONT:-Menlo-Regular}"
FONT_SIZE="${FONT_SIZE:-20}"
PROFILE="${PROFILE:-Recording}"
LDM_PROJECT="${LDM_PROJECT:-devcon2026}"
MENU_BAR="${MENU_BAR:-30}"
LDM_DIR="${LDM_DIR:-${HOME}/ldm-verify/devcon2026}"

# The display's usable rectangle in macOS's own coordinates (origin at the bottom left of
# the main display, y upwards): x y width height, then the display's top edge. Terminal
# converts AppleScript window bounds wrongly on a display above the main one, so the
# windows are placed by size and origin, which use these coordinates directly.
read -r VX VY VW VH SCREEN_TOP < <(osascript -l JavaScript - "${SCREEN_W}" "${SCREEN_H}" "${SCREEN_NAME}" <<'EOF2'
ObjC.import("AppKit");
function run(argv) {
	const w = Number(argv[0]), h = Number(argv[1]), name = argv[2];
	const screens = $.NSScreen.screens;
	let chosen = screens.objectAtIndex(0);
	for (let i = 0; i < screens.count; i++) {
		const s = screens.objectAtIndex(i);
		const matches = name
			? s.localizedName.js.toLowerCase().includes(name.toLowerCase())
			: s.frame.size.width === w && s.frame.size.height === h;
		if (matches) { chosen = s; break; }
	}
	const f = chosen.frame, v = chosen.visibleFrame;
	return [v.origin.x, v.origin.y, v.size.width, v.size.height, f.origin.y + f.size.height]
		.map(Math.round).join(" ");
}
EOF2
)

# With "Displays have separate Spaces" on, a second display shows its own menu bar, but
# macOS still reports its whole height as usable. Keep MENU_BAR pixels clear at the top
# whenever it does. Set MENU_BAR=0 when the menu bar is hidden.
if [ $(( VY + VH )) -ge "${SCREEN_TOP}" ]; then
	VH=$(( VH - MENU_BAR ))
fi

HALF=$(( VW / 2 ))
RIGHT_TOP=$(( SCREEN_TOP - CLOCK_H ))
[ "${RIGHT_TOP}" -gt $(( VY + VH )) ] && RIGHT_TOP=$(( VY + VH ))
RIGHT_H=$(( RIGHT_TOP - VY ))

echo "display ${VW}x${VH} (${SCREEN_NAME:-${SCREEN_W}x${SCREEN_H}}) at ${VX},${VY}; logs ${HALF}x${VH} at ${VX},${VY}; run ${HALF}x${RIGHT_H} at $(( VX + HALF )),${VY}"

# The profile is created by importing a .terminal file, the only way to switch off the
# running command and the folder in the window title: AppleScript can't reach those
# settings, and a running Terminal doesn't reread its preferences. Importing also opens a
# window with the profile, which is closed again.
if ! osascript -e "tell application \"Terminal\" to exists settings set \"${PROFILE}\"" | grep --quiet true; then
	PROFILE_FILE="${TMPDIR:-/tmp}/${PROFILE}.terminal"

	FONT_DATA=$(osascript -l JavaScript - "${FONT}" "${FONT_SIZE}" <<'EOF2'
ObjC.import("AppKit");
function run(argv) {
	const font = $.NSFont.fontWithNameSize(argv[0], Number(argv[1]));
	const data = $.NSKeyedArchiver.archivedDataWithRootObjectRequiringSecureCodingError(font, false, null);
	return data.base64EncodedStringWithOptions(0).js;
}
EOF2
)

	python3 - "${PROFILE}" "${PROFILE_FILE}" "${FONT_DATA}" <<'EOF3'
import base64, plistlib, sys
name, path, font = sys.argv[1], sys.argv[2], sys.argv[3]
profile = {"name": name, "type": "Window Settings", "ProfileCurrentVersion": 2.07,
	"Font": base64.b64decode(font)}
for key in ["ShowActiveProcessInTitle", "ShowActiveProcessArgumentsInTitle",
		"ShowCommandKeyInTitle", "ShowDimensionsInTitle", "ShowRepresentedURLInTitle",
		"ShowRepresentedURLPathInTitle", "ShowShellCommandInTitle", "ShowTTYNameInTitle",
		"ShowWindowSettingsNameInTitle"]:
	profile[key] = False
profile["ShowWindowCustomTitle"] = True
plistlib.dump(profile, open(path, "wb"))
EOF3

	open "${PROFILE_FILE}"
	sleep 2
	osascript -e "tell application \"Terminal\" to close (windows whose name of current settings of selected tab is \"${PROFILE}\")"
	echo "created the ${PROFILE} profile"
fi

LOGS="cd '${LDM_DIR}' && clear; while true; do ldm logs -f ${LDM_PROJECT}; echo \"--- container restarted, reconnecting ---\"; sleep 2; done"
RUN="cd '${ROOT}' && clear && print -z 'scripts/record-approach-1.sh'"
LOGS_TITLE="${LOGS_TITLE:-Liferay server log (live)}"
RUN_TITLE="${RUN_TITLE:-Approach 1: build, provision and check}"

# Close the windows a previous run opened, found by their titles, so a rerun doesn't stack
# them. Their shells are stopped first: the logs loop would otherwise keep restarting ldm.
for tty in $(osascript - "${LOGS_TITLE}" "${RUN_TITLE}" <<'EOF2'
on run argv
	set out to ""
	tell application "Terminal"
		repeat with w in windows
			try
				if custom title of selected tab of w is in argv then set out to out & (tty of selected tab of w) & " "
			end try
		end repeat
	end tell
	return out
end run
EOF2
); do
	# pkill -t matches nothing on macOS for these terminals; ps -t does.
	kill $(ps -t "${tty#/dev/}" -o pid=) 2>/dev/null || true
done

osascript - "${LOGS_TITLE}" "${RUN_TITLE}" <<'EOF2' >/dev/null
on run argv
	delay 1
	tell application "Terminal"
		set ids to {}
		repeat with w in windows
			try
				if custom title of selected tab of w is in argv then set end of ids to id of w
			end try
		end repeat
		repeat with i in ids
			try
				close (first window whose id is i)
			end try
		end repeat
	end tell
end run
EOF2

osascript - "${PROFILE}" "${FONT}" "${FONT_SIZE}" "${LOGS}" "${RUN}" \
	"${VX}" "${VY}" "${HALF}" "${VH}" "${RIGHT_H}" "${LOGS_TITLE}" "${RUN_TITLE}" <<'EOF'
on run argv
	set {profileName, fontName, fontSize, logsCommand, runCommand} to items 1 thru 5 of argv
	set {vx, vy, half, vh, rightH, logsTitle, runTitle} to items 6 thru 12 of argv
	set {vx, vy, half, vh, rightH} to {vx as integer, vy as integer, half as integer, vh as integer, rightH as integer}

	tell application "Terminal"
		activate

		set font name of settings set profileName to fontName
		set font size of settings set profileName to (fontSize as integer)

		set logsTab to do script logsCommand
		set current settings of logsTab to settings set profileName
		set custom title of logsTab to logsTitle
		set size of front window to {half, vh}
		set origin of front window to {vx, vy}

		set runTab to do script runCommand
		set current settings of runTab to settings set profileName
		set custom title of runTab to runTitle
		set size of front window to {half, rightH}
		set origin of front window to {vx + half, vy}
	end tell
end run
EOF
