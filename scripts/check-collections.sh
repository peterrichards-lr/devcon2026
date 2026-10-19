#!/usr/bin/env bash
#
# check-collections.sh <groupId> — list every collection display on the site's pages and
# templates, and fail if any has no collection configured (the handler order race).
#

set -o errexit
set -o nounset
set -o pipefail

GROUP_ID="${1:?usage: check-collections.sh <groupId>}"
DB_CONTAINER="${LDM_DB_CONTAINER:-devcon2026-db}"   # the LDM project's Postgres container

docker exec "${DB_CONTAINER}" sh -c "psql -U \${POSTGRES_USER:-liferay} -d \${POSTGRES_DB:-lportal} -At -F '|' -c \"
select l.friendlyurl,
       (select count(*) from regexp_matches(s.data_, '\\\"type\\\":\\\"collection\\\"', 'g')),
       (select count(*) from regexp_matches(s.data_, '\\\"collection\\\":\\\\{', 'g'))
from layoutpagetemplatestructurerel s
join layoutpagetemplatestructure t on t.layoutpagetemplatestructureid = s.layoutpagetemplatestructureid
join layout l on l.plid = t.plid
where l.groupid = ${GROUP_ID} and l.friendlyurl !~ '^/[0-9a-f]{8}-' and s.data_ like '%\\\"type\\\":\\\"collection\\\"%'
order by 1\"" | awk -F'|' '
	{ status = ($3 < $2) ? "MISSING" : "ok"; if ($3 < $2) bad++; printf "%-8s %-20s %s displays, %s configured\n", status, $1, $2, $3 }
	END { if (bad) { print bad " page(s) with a collection display and no collection"; exit 1 } }'
