#!/usr/bin/env bash
#
# restore-approach2.sh [snapshot]
#
# Restores Rafa's Approach 2 instance (LDM project masterclass-approach2, at
# http://approach2.devcon.demo:8081) and puts back what a restore undoes. Default
# snapshot: masterclass-approach2-063ee2f, the migrated site.
#
#   1. Restore drops back in the snapshot's index prefix, ldm-devcon2026- (LDM #2315).
#      Both instances share a company ID, so with it this instance's startup reindex
#      empties devcon2026's index. Removed from meta.
#   2. A normal start forces -XX:TieredStopAtLevel=1 (LDM #2308), which makes every
#      authenticated request about 8x slower. reindex_required=true starts the JVM
#      without it.
#   3. ldm restart doesn't re-render docker-compose.yml (LDM #2317), so stop, then run.
#   4. The MCP server needs its own switch as well as LPD-63311.
#   5. A restored search index can come back dead (LDM #2316), so the company index
#      must answer _count before this reports success.
#
# LDM_PROJECTS (default ~/ldm-verify) is where the LDM projects live.
#

set -o errexit
set -o nounset
set -o pipefail

SNAPSHOT="${1:-masterclass-approach2-063ee2f}"
PROJECT=masterclass-approach2
HOST=approach2.devcon.demo
DIR="${LDM_PROJECTS:-${HOME}/ldm-verify}/${PROJECT}"
URL="http://${HOST}:8081"

LDM=(ldm)
if ! ldm --version >/dev/null 2>&1; then
	LDM=(/opt/homebrew/bin/python3.14 /usr/local/bin/ldm)
fi

die() { echo "FAIL  $*" >&2; exit 1; }

case "${SNAPSHOT}" in
	-*) sed -n '2,22p' "$0"; exit 2 ;;
esac

start=$(date +%s)

docker ps --format '{{.Names}}' | grep --quiet --line-regexp liferay-search-global \
	|| die "liferay-search-global is not running; start it first (docker start liferay-search-global)"

cd "${DIR}"

echo "== restore ${SNAPSHOT}"
"${LDM[@]}" restore "${PROJECT}" -n "${SNAPSHOT}" -y --no-color

echo "== fix meta: index prefix, JIT"
python3 - <<'EOF'
import json
m = json.load(open("meta"))
env = json.loads(m.get("custom_env") or "{}")
env.pop("LIFERAY_ELASTICSEARCH_PERIOD_INDEX_PERIOD_NAME_PERIOD_PREFIX", None)
m["custom_env"] = json.dumps(env)
m["reindex_required"] = "true"
json.dump(m, open("meta", "w"), indent=4)
EOF

MCP_CONFIG=osgi/configs/com.liferay.mcp.server.rest.internal.configuration.MCPServerConfiguration.config
[ -f "${MCP_CONFIG}" ] || printf 'enabled=B"true"\n' > "${MCP_CONFIG}"

echo "== start"
"${LDM[@]}" stop "${PROJECT}" -y --no-color >/dev/null 2>&1 || true
"${LDM[@]}" run "${PROJECT}" --host-name "${HOST}" -y --no-color

echo "== checks"
prefix=$(docker exec "${PROJECT}" env | sed -n 's/^LIFERAY_ELASTICSEARCH_PERIOD_INDEX_PERIOD_NAME_PERIOD_PREFIX=//p')
[ "${prefix}" = "ldm-${PROJECT}-" ] || die "index prefix is '${prefix}'"
echo "ok    index prefix ${prefix}"

if docker exec "${PROJECT}" sh -c 'ps -eo args' | grep --quiet 'TieredStopAtLevel=1'; then
	echo "WARN  the JVM still has -XX:TieredStopAtLevel=1; requests will be slow"
else
	echo "ok    full JIT"
fi

for _ in $(seq 1 60); do
	code=$(curl --silent --output /dev/null --write-out '%{http_code}' --user test@liferay.com:test \
		"${URL}/o/headless-admin-user/v1.0/my-user-account")
	[ "${code}" = 200 ] && break
	sleep 5
done
[ "${code}" = 200 ] || die "REST not answering (${code})"
echo "ok    REST answers"

title=$(curl --silent --location "${URL}/web/masterclass-cms/home" | grep -o -E '<title>[^<]*' | head -1 | cut -c8-)
echo "${title}" | grep --quiet "Masterclass" || die "home page title is '${title}'"
echo "ok    home page: ${title}"

INDEX="ldm-${PROJECT}-$(docker exec "${PROJECT}-db" psql -U lportal -d lportal -tAc 'select companyid from company limit 1')"
for _ in $(seq 1 60); do
	count=$(docker exec liferay-search-global curl --silent "localhost:9200/${INDEX}/_count" \
		| python3 -c 'import json,sys; print(json.load(sys.stdin).get("count", "error"))')
	[ "${count}" != error ] && break
	sleep 5
done
[ "${count}" != error ] \
	|| die "search index ${INDEX} is not answering (LDM #2316): docker restart liferay-search-global, then docker restart ${PROJECT}"
echo "ok    search index answers (${count} documents so far; the reindex is still running)"

echo "== done in $(( $(date +%s) - start )) s"
