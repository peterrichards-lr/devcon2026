#!/usr/bin/env bash
#
# prepare-stage.sh
#
# Gets both stage instances ready before the talk, in one command. Run it, then sign in
# again in both Chrome profiles: a restart signs everyone out.
#
#   Approach 1 (Peter)   devcon2026              http://approach1.devcon.demo:8080
#   Approach 2 (Rafa)    masterclass-approach2   http://approach2.devcon.demo:8081
#
#   0. Starts Colima with 6 CPUs and 16 GiB if it isn't running. Both instances need that
#      much; with less it stops, because resizing Colima stops every container. Colima's
#      home (~/.colima) is on the SanDisk drive, so the drive must be mounted.
#   1. Starts the shared search node if it is stopped. If its container is gone, stops:
#      starting LDM without it can wipe every project's search data.
#   2. Approach 1: with RESTORE_MINE=1, restores masterclass-02-3c9a590 first (do this
#      after any rehearsal of the registration). Otherwise starts it if it isn't running.
#   3. Approach 2: restores masterclass-approach2-063ee2f with restore-approach2.sh.
#      SKIP_APPROACH2=1 leaves it as it is.
#   4. Approach 1: runs demo-prep.sh with LANDING=my-learning, which puts the instance
#      settings back and checks the demo student.
#   5. Checks both search indices answer, and that each has documents once its reindex
#      has finished.
#
# Nothing here is meant to run during the talk: a restore takes minutes.
#

set -o errexit
set -o nounset
set -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LDM_PROJECTS="${LDM_PROJECTS:-${HOME}/ldm-verify}"
URL1=http://approach1.devcon.demo:8080
URL2=http://approach2.devcon.demo:8081
COLIMA_CPUS=6
COLIMA_MEMORY=16

LDM=(ldm)
if ! ldm --version >/dev/null 2>&1; then
	LDM=(/opt/homebrew/bin/python3.14 /usr/local/bin/ldm)
fi

die() { echo "FAIL  $*" >&2; exit 1; }

start=$(date +%s)

echo "== 0. Docker"
[ -e "${HOME}/.colima/default" ] \
	|| die "${HOME}/.colima/default is missing: is the SanDisk drive mounted?"
if ! colima status >/dev/null 2>&1; then
	colima start --cpu "${COLIMA_CPUS}" --memory "${COLIMA_MEMORY}"
fi
cpus=$(docker info --format '{{.NCPU}}')
memory=$(docker info --format '{{.MemTotal}}')
[ "${cpus}" -ge "${COLIMA_CPUS}" ] && [ "${memory}" -ge $(( (COLIMA_MEMORY - 1) * 1024 * 1024 * 1024 )) ] \
	|| die "Docker has ${cpus} CPUs and $(( memory / 1024 / 1024 / 1024 )) GiB; both instances need ${COLIMA_CPUS} and ${COLIMA_MEMORY}. Run: colima stop && colima start --cpu ${COLIMA_CPUS} --memory ${COLIMA_MEMORY} (this stops every container)"
echo "ok    Colima: ${cpus} CPUs, $(( memory / 1024 / 1024 / 1024 )) GiB"

echo "== 1. search node"
state=$(docker inspect --format '{{.State.Status}}' liferay-search-global 2>/dev/null || true)
case "${state}" in
	running) ;;
	"") die "the liferay-search-global container is gone; don't start LDM without it (it can wipe every project's search data)" ;;
	*) docker start liferay-search-global >/dev/null ;;
esac
until docker exec liferay-search-global curl --silent localhost:9200/_cluster/health 2>/dev/null \
	| grep --quiet --extended-regexp '"status":"(green|yellow)"'; do
	sleep 3
done
echo "ok    liferay-search-global is up"

echo "== 2. Approach 1"
if [ "${RESTORE_MINE:-0}" = 1 ]; then
	(cd "${LDM_PROJECTS}/devcon2026" && "${LDM[@]}" restore devcon2026 -n masterclass-02-3c9a590 --up -y --no-color)
elif ! docker ps --format '{{.Names}}' | grep --quiet --line-regexp devcon2026; then
	(cd "${LDM_PROJECTS}/devcon2026" && "${LDM[@]}" run devcon2026 --host-name approach1.devcon.demo -y --no-color)
else
	echo "ok    already running"
fi

echo "== 3. Approach 2"
if [ "${SKIP_APPROACH2:-0}" = 1 ]; then
	echo "skip  SKIP_APPROACH2=1"
else
	LDM_PROJECTS="${LDM_PROJECTS}" "${HERE}/restore-approach2.sh"
fi

echo "== 4. Approach 1: instance settings and the demo student"
for _ in $(seq 1 60); do
	group=$(LIFERAY_URL="${URL1}" "${HERE}/site-id.sh" 2>/dev/null) && break
	sleep 5
done
[ -n "${group:-}" ] || die "no Masterclass CMS site on ${URL1}"
LIFERAY_URL="${URL1}" LANDING=my-learning MASTERCLASS_GROUP_ID="${group}" "${HERE}/demo-prep.sh" \
	|| die "demo-prep.sh failed on ${URL1}"

# Counts a log line since the container last started: the log survives a restart.
since_start() {
	docker logs --since "$(docker inspect --format '{{.State.StartedAt}}' "$1")" "$1" 2>&1 \
		| grep --count "$2" || true
}

echo "== 5. search"
for project in devcon2026 masterclass-approach2; do
	index="ldm-${project}-$(docker exec "${project}-db" psql -U lportal -d lportal -tAc 'select companyid from company limit 1')"
	for _ in $(seq 1 90); do
		started=$(since_start "${project}" 'Start reindexing')
		[ "${started}" -gt 0 ] && [ "${started}" = "$(since_start "${project}" 'Finished reindexing')" ] && break
		sleep 10
	done
	count=$(docker exec liferay-search-global curl --silent "localhost:9200/${index}/_count" \
		| python3 -c 'import json,sys; print(json.load(sys.stdin).get("count", "error"))')
	[ "${count}" != error ] && [ "${count}" -gt 1000 ] \
		|| die "${index} has '${count}' documents (LDM #2316): docker restart liferay-search-global, then docker restart ${project}"
	echo "ok    ${project}: ${count} documents"
done

echo "== ready in $(( $(date +%s) - start )) s"
echo "      Approach 1  ${URL1}/   (Peter's Chrome profile: sign in again)"
echo "      Approach 2  ${URL2}/web/masterclass-cms   (Rafa's Chrome profile: sign in again as test@liferay.com)"
