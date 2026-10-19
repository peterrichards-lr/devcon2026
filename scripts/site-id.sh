#!/usr/bin/env bash
#
# site-id.sh — print the group id (site id) of the Masterclass CMS site.
#
# The check scripts call this when they are not given a group id, so they always act on
# the site the latest provision created. MASTERCLASS_GROUP_ID, when set, wins.
#
# SITE_NAME (default "Masterclass CMS"), LIFERAY_URL (default http://localhost:8080) and
# LIFERAY_ADMIN (default test@liferay.com:test) select the site and the instance.
#

set -o nounset
set -o pipefail

if [ -n "${MASTERCLASS_GROUP_ID:-}" ]; then
	echo "${MASTERCLASS_GROUP_ID}"
	exit 0
fi

H="${LIFERAY_URL:-http://localhost:8080}"
ADMIN="${LIFERAY_ADMIN:-test@liferay.com:test}"
NAME="${SITE_NAME:-Masterclass CMS}"

ids=$(curl --silent --user "${ADMIN}" "${H}/o/headless-admin-site/v1.0/sites?pageSize=200" \
	| jq -r --arg n "${NAME}" '.items[]? | select(.name == $n) | .id')

case $(echo "${ids}" | grep --count .) in
	1) echo "${ids}" ;;
	0) echo "no site named '${NAME}' on ${H}; provision first, or pass the group id" >&2; exit 1 ;;
	*) echo "more than one site named '${NAME}' ($(echo ${ids})); pass the group id" >&2; exit 1 ;;
esac
