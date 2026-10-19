#!/usr/bin/env bash
#
# follow-logs.sh — follow the Liferay server log, coloured, for recording the run.
#
# Runs `ldm logs -f <project> liferay`, printing that command first, and shows Liferay's
# log only (not the database's), with the service prefix removed and each line coloured
# by what it says:
#
#   red          ERROR, and any line naming an exception
#   yellow       WARN
#   green        a bundle or client extension STARTED
#   bold green   the site initializer starting and finishing, each batch file deployed
#   cyan         the site initializer's handler steps (Invoking …)
#
# Reconnects whenever the container restarts, which the restore does. Runs ldm from the
# LDM project folder, since ldm warns when run from the home directory.
#
#   LDM_DIR       default ~/ldm-verify/devcon2026
#   LDM_PROJECT   default devcon2026
#   LDM_SERVICE   default liferay
#

LDM_DIR="${LDM_DIR:-${HOME}/ldm-verify/devcon2026}"
LDM_PROJECT="${LDM_PROJECT:-devcon2026}"
LDM_SERVICE="${LDM_SERVICE:-liferay}"

cd "${LDM_DIR}" || exit 1

# Start with new lines only, so the window doesn't open on old log. After a restart, show
# the new container's last lines, so its startup isn't missed during the reconnect.
TAIL=0

while true; do
	# Show the real command, as the run window does, so the recording shows it is ldm logs.
	printf '\033[1m$ ldm logs -f -n %s %s %s\033[0m\n' "${TAIL}" "${LDM_PROJECT}" "${LDM_SERVICE}"

	# script(1) gives ldm a terminal, so it streams line by line as it does interactively.
	# Its input comes from /dev/null: given the window's terminal, script switches that to
	# raw mode, and every line then starts where the previous one ended.
	script -q /dev/null ldm logs -f -n "${TAIL}" "${LDM_PROJECT}" "${LDM_SERVICE}" < /dev/null 2>&1 \
		| awk '
			{
				gsub(/\r|\033\[[0-9;]*m/, "")
				sub(/^[^|]*\| /, "")
			}
			/Initializing com\.liferay\.site\.initializer|Initialized com\.liferay\.site\.initializer|Successfully deployed batch engine file/ {
				printf "\033[1;32m%s\033[0m\n", $0; fflush(); next
			}
			/ ERROR |Exception/ { printf "\033[31m%s\033[0m\n", $0; fflush(); next }
			/ WARN /            { printf "\033[33m%s\033[0m\n", $0; fflush(); next }
			/ STARTED /         { printf "\033[32m%s\033[0m\n", $0; fflush(); next }
			/ Invoking /        { printf "\033[36m%s\033[0m\n", $0; fflush(); next }
			{ print; fflush() }
		'

	printf '\033[2m--- container restarted, reconnecting ---\033[0m\n'
	TAIL=100
	sleep 2
done
