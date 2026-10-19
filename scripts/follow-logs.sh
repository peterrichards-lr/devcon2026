#!/usr/bin/env bash
#
# follow-logs.sh — follow the Liferay server log, coloured, for recording the run.
#
# Runs `ldm logs -f <project>`, printing that command first: the consolidated log of every
# service in the project, each line keeping ldm's coloured "service |" prefix, with the
# message after it coloured by what it says:
#
#   red          ERROR (and the database's ERROR: and FATAL:), any line naming an exception
#   yellow       WARN (and the database's WARNING:)
#   green        a bundle or client extension STARTED
#   bold green   the site initializer starting and finishing, each batch file deployed
#   cyan         the site initializer's handler steps (Invoking …)
#
# Reconnects whenever the container restarts, which the restore does. Runs ldm from the
# LDM project folder, since ldm warns when run from the home directory.
#
#   LDM_DIR       default ~/ldm-verify/devcon2026
#   LDM_PROJECT   default devcon2026
#   LDM_SERVICE   default all services; set to one service name (liferay, …) to follow
#                 only that one
#

LDM_DIR="${LDM_DIR:-${HOME}/ldm-verify/devcon2026}"
LDM_PROJECT="${LDM_PROJECT:-devcon2026}"
LDM_SERVICE="${LDM_SERVICE:-}"

cd "${LDM_DIR}" || exit 1

# Start with new lines only, so the window doesn't open on old log. After a restart, show
# the new container's last lines, so its startup isn't missed during the reconnect.
TAIL=0

while true; do
	# Show the real command, as the run window does, so the recording shows it is ldm logs.
	printf '\033[1m$ ldm logs -f -n %s %s\033[0m\n' "${TAIL}" "${LDM_PROJECT}${LDM_SERVICE:+ ${LDM_SERVICE}}"

	# script(1) gives ldm a terminal, so it streams line by line as it does interactively.
	# Its input comes from /dev/null: given the window's terminal, script switches that to
	# raw mode, and every line then starts where the previous one ended.
	script -q /dev/null ldm logs -f -n "${TAIL}" "${LDM_PROJECT}" ${LDM_SERVICE:+"${LDM_SERVICE}"} < /dev/null 2>&1 \
		| awk '
			{
				line = $0
				gsub(/\r/, "", line)

				# Keep ldm'"'"'s "service |" prefix in its own colour; colour only the message.
				p = index(line, "| ")
				if (p > 0) { prefix = substr(line, 1, p + 1) "\033[0m"; msg = substr(line, p + 2) }
				else { prefix = ""; msg = line }
				gsub(/\033\[[0-9;]*m/, "", msg)

				colour = ""
				if (msg ~ /Initializing com\.liferay\.site\.initializer|Initialized com\.liferay\.site\.initializer|Successfully deployed batch engine file/) colour = "1;32"
				else if (msg ~ / ERROR |ERROR:|FATAL|Exception/) colour = "31"
				else if (msg ~ / WARN |WARNING:/) colour = "33"
				else if (msg ~ / STARTED /) colour = "32"
				else if (msg ~ / Invoking /) colour = "36"

				if (colour == "") printf "%s%s\n", prefix, msg
				else printf "%s\033[%sm%s\033[0m\n", prefix, colour, msg
				fflush()
			}
		'

	printf '\033[2m--- container restarted, reconnecting ---\033[0m\n'
	TAIL=100
	sleep 2
done
