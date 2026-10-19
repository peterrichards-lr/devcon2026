#!/usr/bin/env bash
#
# ldm-provision.sh — Approach 1 on an LDM instance, following README.md "Running Approach 1"
# step by step, from a clean snapshot.
#
#   WT             the checkout whose artifacts are deployed (default: this repository).
#                  Build them first with the README's blade command.
#   LDM_DIR        the LDM project folder (default ~/ldm-verify/devcon2026)
#   LDM_PROJECT    the LDM project name (default devcon2026)
#   CLEAN_SNAPSHOT a snapshot with no Masterclass data (default clean-2026q3.5)
#   LIFERAY_URL    default http://localhost:8080
#   LIFERAY_ADMIN  default test@liferay.com:test
#
# Empties osgi/modules apart from the activation key, restores the snapshot, deploys each
# artifact and waits for it to start, creates the site, then deploys the batch.
# Prints the new site's id: the <groupId> the check scripts take.
#

set -o errexit
set -o nounset
set -o pipefail

WT="${WT:-$(cd "$(dirname "$0")/.." && pwd)}"
LDM_DIR="${LDM_DIR:-${HOME}/ldm-verify/devcon2026}"
LDM_PROJECT="${LDM_PROJECT:-devcon2026}"
CLEAN_SNAPSHOT="${CLEAN_SNAPSHOT:-clean-2026q3.5}"
H="${LIFERAY_URL:-http://localhost:8080}"
ADMIN="${LIFERAY_ADMIN:-test@liferay.com:test}"
MOD="${LDM_DIR}/osgi/modules"
LOG="${LDM_DIR}/logs/liferay.$(date -u +%F).log"

wait_log() {
	local from=$1 pattern=$2 tries=${3:-120}

	for _ in $(seq 1 "${tries}"); do
		tail -n +"$((from + 1))" "${LOG}" 2>/dev/null | grep --quiet --extended-regexp "${pattern}" && return 0
		sleep 3
	done

	echo "TIMEOUT waiting for: ${pattern}" >&2

	return 1
}

deploy() {
	local file=$1 pattern=$2 n

	[ -f "${file}" ] || { echo "missing ${file}: build it first" >&2; exit 1; }
	touch "${LOG}"
	n=$(wc -l < "${LOG}")
	cp "${file}" "${MOD}/"
	wait_log "${n}" "${pattern}"
	echo "deployed $(basename "${file}")"
}

echo "== built from $(git -C "${WT}" log --oneline -1)"

docker ps --format '{{.Names}}' | grep --quiet '^liferay-search-global$' \
	|| { echo "liferay-search-global is not running; start it before restoring" >&2; exit 1; }

echo "== empty osgi/modules apart from the activation key"
find "${MOD}" -maxdepth 1 -type f ! -name 'activation-key-*' -print -delete

echo "== restore ${CLEAN_SNAPSHOT}"
touch "${LOG}"
N0=$(wc -l < "${LOG}")
(cd "${LDM_DIR}" && ldm restore "${LDM_PROJECT}" -n "${CLEAN_SNAPSHOT}" --up -y --no-color | tail -1)

echo "== step 1"
deploy "${WT}/modules/masterclass-cms-workarounds/build/libs/com.liferay.masterclass.cms.workarounds-1.0.0.jar" "STARTED com.liferay.masterclass.cms.workarounds"
deploy "${WT}/client-extensions/liferay-masterclassobj-simplerheadlesscallsjs/dist/liferay-masterclassobj-simplerheadlesscallsjs.zip" "STARTED liferaymasterclassobjsimplerheadlesscallsjs"
deploy "${WT}/client-extensions/liferay-masterclass-custom-css/dist/liferay-masterclass-custom-css.zip" "STARTED liferaymasterclasscustomcss"

echo "== step 2"
deploy "${WT}/modules/masterclass-cms-site-initializer/build/libs/com.liferay.site.initializer.masterclass.cms-1.0.0.jar" "STARTED com.liferay.site.initializer.masterclass.cms"

echo "== step 3: create the site"
n=$(wc -l < "${LOG}")
curl \
	--data '{"membershipType": "open", "name": "Masterclass CMS", "templateKey": "com.liferay.site.initializer.masterclass.cms", "templateType": "site-initializer"}' \
	--header "Content-Type: application/json" \
	--request POST \
	--silent \
	--url "${H}/o/headless-admin-site/v1.0/sites" \
	--user "${ADMIN}" \
	| jq --compact-output '{name, id}'
wait_log "${n}" "Initialized com.liferay.site.initializer.masterclass.cms|InitializationException"
tail -n +"$((n + 1))" "${LOG}" | grep --extended-regexp "Initialized|InitializationException" | cut -c1-160
tail -n +"$((n + 1))" "${LOG}" | grep --extended-regexp "Invoking (addAssetListEntries|addLayoutPageTemplates|addOrUpdateLayoutsContent|addUserAccounts) " | sed 's/.*Invoking/ Invoking/'

echo "== step 4: data batch"
n=$(wc -l < "${LOG}")
cp "${WT}/client-extensions/masterclass-cms-data-batch/dist/masterclass-cms-data-batch.zip" "${MOD}/"
wait_log "${n}" "Successfully deployed batch engine file .*10-elearning-session|Unable to deploy batch"
sleep 20
tail -n +"$((n + 1))" "${LOG}" | grep --count "Successfully deployed batch engine file" | sed 's/^/batch files deployed: /'
tail -n +"$((n + 1))" "${LOG}" | grep "Unable to deploy batch" | cut -c1-200 || true

echo "== errors since restore"
tail -n +"$((N0 + 1))" "${LOG}" | grep --extended-regexp " ERROR " | cut -c1-200 | sort | uniq -c | sort -rn | head -15 || true

G=$(curl --silent --user "${ADMIN}" "${H}/o/headless-admin-site/v1.0/sites?pageSize=100" | jq -r '[.items[] | select(.name == "Masterclass CMS")][0].id // empty')
echo "== site id (groupId): ${G:-not found}"
