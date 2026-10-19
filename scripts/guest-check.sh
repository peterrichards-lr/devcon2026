#!/usr/bin/env bash
#
# guest-check.sh [groupId] — what an anonymous visitor gets.
#
# Fetches every page of the site as Guest, then every course and blog display page they
# link to, then every image and document those pages reference, and reports status and
# size. A 200 with zero bytes counts as a failure: an empty attachment answers exactly that.
#
# Pages that only members may see must answer 404 to Guest; they are listed in
# MEMBER_ONLY and reported as "member-only" rather than as failures.
#
# LIFERAY_URL (default http://localhost:8080), LIFERAY_ADMIN (default
# test@liferay.com:test, used only to list the pages), GUEST_CHECK_OUT (where the fetched
# HTML is kept, default ${TMPDIR}/guest-check).
#

set -o nounset
set -o pipefail

if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
	GROUP_ID="${1}"
	shift
elif [ -n "${MASTERCLASS_GROUP_ID:-}" ]; then
	GROUP_ID="${MASTERCLASS_GROUP_ID}"
else
	echo "no group id: paste the 'export MASTERCLASS_GROUP_ID=…' line that ldm-provision.sh printed, or pass the id as the first argument" >&2
	exit 1
fi

echo "== site ${GROUP_ID}"
H="${LIFERAY_URL:-http://localhost:8080}"
ADMIN="${LIFERAY_ADMIN:-test@liferay.com:test}"
OUT="${GUEST_CHECK_OUT:-${TMPDIR:-/tmp}/guest-check}"
MEMBER_ONLY="${MEMBER_ONLY:-/account-settings /course-completions /course-registrations /my-learning /notifications}"

rm -rf "${OUT}" && mkdir -p "${OUT}"
bad=0

fetch() {
	local url=$1 file=$2 expect=${3:-200} r

	r=$(curl --location --output "${file}" --silent --write-out '%{http_code} %{size_download}' "${H}${url}")
	set -- ${r}

	if [ "${expect}" = 404 ]; then
		[ "$1" = 404 ] && echo "ok    $1 member-only  ${url}" || { echo "FAIL  $1 (member-only page visible to Guest)  ${url}"; bad=$((bad + 1)); }
	elif [ "$1" != 200 ] || [ "$2" = 0 ]; then
		echo "FAIL  $1 $2B  ${url}"
		bad=$((bad + 1))
	else
		echo "ok    $1 $2B  ${url}"
	fi
}

media() {
	grep --only-matching --extended-regexp '(src|href)="([^"]*/documents/[^"]+|/o/[^"]+\.(png|jpe?g|webp|svg|gif|css|js)[^"]*)"' "$@" \
		| sed -E 's/^[^:]*:(src|href)="//; s/"$//; s/&amp;/\&/g; s#^'"${H}"'##'
}

SITE=$(curl --silent --user "${ADMIN}" "${H}/api/jsonws/group/get-group?groupId=${GROUP_ID}" | jq -r .friendlyURL)

PAGES=$(curl --silent --user "${ADMIN}" \
	"${H}/o/headless-delivery/v1.0/sites/${GROUP_ID}/site-pages?pageSize=100&fields=friendlyUrlPath" \
	| jq -r '.items[].friendlyUrlPath')

echo "== pages (site ${SITE})"
for p in ${PAGES}; do
	case " ${MEMBER_ONLY} " in
		*" ${p} "*) fetch "/web${SITE}${p}" "${OUT}/page$(echo "${p}" | tr / _).html" 404 ;;
		*) fetch "/web${SITE}${p}" "${OUT}/page$(echo "${p}" | tr / _).html" ;;
	esac
done

echo "== course and blog display pages"
grep --only-matching --no-filename --extended-regexp "${H}/web${SITE}/c_[a-z]+/[^\"]+" "${OUT}"/page*.html \
	| sed "s#^${H}##" | sort -u > "${OUT}/display-pages.txt"
i=0
while read -r url; do
	i=$((i + 1))
	fetch "${url}" "${OUT}/display${i}.html"
done < "${OUT}/display-pages.txt"
[ "${i}" -gt 0 ] || { echo "FAIL  no display page links found"; bad=$((bad + 1)); }

echo "== images, documents, CSS and JS on all of them"
media "${OUT}"/page*.html "${OUT}"/display*.html 2>/dev/null | sort -u > "${OUT}/media.txt"
i=0
while read -r url; do
	i=$((i + 1))
	fetch "${url}" "${OUT}/media${i}"
done < "${OUT}/media.txt"

echo "== unresolved tokens or empty collections in page HTML"
grep --count --extended-regexp 'No Results Found|\[\$[A-Z_]+|\[#[A-Z_]+|ObjectField_[0-9]' "${OUT}"/page*.html "${OUT}"/display*.html \
	| grep --invert-match ':0$' && bad=$((bad + 1)) || echo "none"

echo "${bad} failure(s)"
[ "${bad}" = 0 ]
