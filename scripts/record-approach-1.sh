#!/usr/bin/env bash
#
# record-approach-1.sh — the whole Approach 1 run in one command, for recording.
#
# Runs every stage of TESTING-APPROACH-1.md from the checkout it lives in, with a banner
# per stage and a pause before each one so the presenter sets the pace:
#
#   1. build          blade, from this checkout
#   2. provision      scripts/ldm-provision.sh (restores the clean snapshot first)
#   3. collections    scripts/check-collections.sh
#   4. guest view     scripts/guest-check.sh
#   5. demo student   scripts/demo-prep.sh
#   6. student checks scripts/student-check.sh
#   7. snapshot       optional, asked for at the end
#
# The group id is taken from the new site and passed on; nothing needs pasting.
# Stops at the first stage that fails.
#
# PAUSE=0 runs straight through. SNAPSHOT=<name> takes the snapshot without asking.
# Show the logs in a second window, reconnecting when the restore restarts Liferay:
#
#   while true; do ldm logs -f devcon2026; sleep 2; done
#

set -o errexit
set -o nounset
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
PAUSE="${PAUSE:-1}"
LDM_DIR="${LDM_DIR:-${HOME}/ldm-verify/devcon2026}"
LDM_PROJECT="${LDM_PROJECT:-devcon2026}"

stage() {
	echo
	echo "=================================================================="
	echo "  $*"
	echo "=================================================================="

	if [ "${PAUSE}" = 1 ]; then
		read -r -p "  press Enter to start " _
	fi
}

cd "${ROOT}"

stage "1. Build $(git log --oneline -1)"
blade gw clean \
	:modules:masterclass-cms-workarounds:jar \
	:modules:masterclass-cms-site-initializer:jar \
	:client-extensions:liferay-masterclassobj-simplerheadlesscallsjs:assemble \
	:client-extensions:liferay-masterclass-custom-css:assemble \
	:client-extensions:masterclass-cms-data-batch:assemble

stage "2. Provision from the clean snapshot"
WT="${ROOT}" "${HERE}/ldm-provision.sh"

MASTERCLASS_GROUP_ID=$("${HERE}/site-id.sh")
export MASTERCLASS_GROUP_ID

stage "3. Collections (site ${MASTERCLASS_GROUP_ID})"
"${HERE}/check-collections.sh"

stage "4. What a visitor sees"
"${HERE}/guest-check.sh"

stage "5. Prepare the demo student"
"${HERE}/demo-prep.sh"

stage "6. Student checks"
"${HERE}/student-check.sh"

echo
echo "=================================================================="
echo "  All stages passed on $(git log --oneline -1 | cut -c1-7), site ${MASTERCLASS_GROUP_ID}"
echo "=================================================================="

name="${SNAPSHOT:-}"

if [ -z "${name}" ] && [ "${PAUSE}" = 1 ]; then
	read -r -p "  snapshot name to save now (Enter to skip): " name
fi

if [ -n "${name}" ]; then
	(cd "${LDM_DIR}" && ldm snapshot "${LDM_PROJECT}" -n "${name}" -y --no-color | tail -1)
fi

echo "  Next: the browser check (TESTING-APPROACH-1.md, stage 8)."
