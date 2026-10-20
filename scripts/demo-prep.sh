#!/usr/bin/env bash
#
# demo-prep.sh [groupId] [student-email] [student-password] [course title]
#
# Run once after provisioning, before student-check.sh and before taking a snapshot.
#
#   1. Activates the demo student. The site initializer creates every user inactive on
#      purpose (LPS-184738).
#   2. Makes the instance open the Masterclass site instead of the default Welcome site:
#      the Home URL, the page users land on after signing in, and the page they land on
#      after signing out (Instance Settings > Instance Configuration > General). A site
#      initializer can't set instance settings.
#   3. Gives the student one Confirmed course the way a real student gets one: enrol with
#      the register button's payload, an admin approves, the student confirms.
#   4. Checks that My Learning shows that course.
#
# Steps 1 and 2 are the only allowed post-provision changes. Grants no permissions. Safe
# to re-run: settings already in place, and an enrolment already Confirmed, are kept.
#
# Where signing in lands: the site's home page by default, or My Learning with
# LANDING=my-learning (any other page name under the site works too). SITE_PATH (default
# /web/masterclass-cms) is the site.
#
# LIFERAY_URL (default http://localhost:8080) and LIFERAY_ADMIN (default
# test@liferay.com:test) select the instance and the administrator.
#

set -o nounset
set -o pipefail

if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
	G="${1}"
	shift
elif [ -n "${MASTERCLASS_GROUP_ID:-}" ]; then
	G="${MASTERCLASS_GROUP_ID}"
else
	echo "no group id: paste the 'export MASTERCLASS_GROUP_ID=…' line that ldm-provision.sh printed, or pass the id as the first argument" >&2
	exit 1
fi

echo "== site ${G}"
SE="${1:-student.one@liferay.com}"
SP="${2:-test}"
TITLE="${3:-Building Enterprise Websites with Liferay}"
SITE_PATH="${SITE_PATH:-/web/masterclass-cms}"
LANDING="${LANDING:-home}"
H="${LIFERAY_URL:-http://localhost:8080}"
ADMIN="${LIFERAY_ADMIN:-test@liferay.com:test}"

lr() { curl --silent --user "${ADMIN}" "$@"; }
st() { curl --silent --user "${SE}:${SP}" "$@"; }
# Print a command before running it, with every --user password masked.
show() {
	printf '$ %s\n' "$(printf '%s' "$*" | sed -E 's/(--user[ =])([^: ]+):[^ ]+/\1\2:****/g')"
}
die() { echo "FAIL  $*"; exit 1; }
status() { lr "${H}/o/c/mycourseenrollments/$1" | jq -r '.enrollmentStatus.key'; }

echo "== 1. activate the demo student"
U=$(lr "${H}/o/headless-admin-user/v1.0/user-accounts/by-email-address/${SE}")
SID=$(echo "${U}" | jq -r '.id // empty')
[ -n "${SID}" ] || die "no user ${SE}"

if [ "$(echo "${U}" | jq -r .status)" != Active ]; then
	show "curl --request PATCH --url ${H}/o/headless-admin-user/v1.0/user-accounts/${SID} --user ${ADMIN} --data '{\"status\": \"Active\"}'"
	lr -X PATCH -H 'Content-Type: application/json' -d '{"status": "Active"}' \
		"${H}/o/headless-admin-user/v1.0/user-accounts/${SID}" -o /dev/null
fi

[ "$(lr "${H}/o/headless-admin-user/v1.0/user-accounts/${SID}" | jq -r .status)" = Active ] || die "${SE} is still inactive"
code=$(st --output /dev/null --write-out '%{http_code}' "${H}/o/headless-admin-user/v1.0/my-user-account")
[ "${code}" = 200 ] || die "${SE} is active but cannot sign in (${code})"
echo "ok    ${SE} (id ${SID}) is active and can sign in"

echo "== 2. open the Masterclass site by default"
# The instance whose virtual host is LIFERAY_URL's host. Updating the Home URL sends
# that host back as the virtual host, so it must really be this instance's.
HOST=$(echo "${H}" | sed -E 's#^[a-z]+://([^:/]+).*#\1#')
CID=$(lr "${H}/api/jsonws/company/get-company-by-virtual-host" -d "virtualHost=${HOST}" | jq -r '.companyId // empty')
[ -n "${CID}" ] || die "${HOST} is not an instance's virtual host; nothing changed"

# Landing and logout pages are instance preferences.
LANDING_PATH="${SITE_PATH}/${LANDING#/}"
PREFS=$(jq -cn --arg l "${LANDING_PATH}" --arg o "${SITE_PATH}" '{"default.landing.page.path": $l, "default.logout.page.path": $o}')
show "curl --request POST --url ${H}/api/jsonws/company/update-preferences --user ${ADMIN} --data companyId=${CID} --data unicodeProperties='${PREFS}'"
code=$(lr "${H}/api/jsonws/company/update-preferences" --data-urlencode "companyId=${CID}" \
	--data-urlencode "unicodeProperties=${PREFS}" --output /dev/null --write-out '%{http_code}')
[ "${code}" = 200 ] || die "the landing and logout pages were refused (${code})"
echo "ok    sign in lands on ${LANDING_PATH}, sign out on ${SITE_PATH}"

# The Home URL is a field of the company record. Updating it replaces every field,
# including the virtual host, so send back what is there.
COMPANY=$(lr "${H}/api/jsonws/company/get-company-by-id" -d "companyId=${CID}")

if [ "$(echo "${COMPANY}" | jq -r .homeURL)" = "${SITE_PATH}" ]; then
	echo "ok    the Home URL is already ${SITE_PATH}"
else
	field() { echo "${COMPANY}" | jq -r ".$1 // empty"; }
	HAS_LOGO=false
	[ "$(field logoId)" != 0 ] && HAS_LOGO=true

	show "curl --request POST --url ${H}/api/jsonws/company/update-company --user ${ADMIN} --data companyId=${CID} --data virtualHost=${HOST} --data homeURL=${SITE_PATH} (every other field sent back unchanged)"
	R=$(lr "${H}/api/jsonws/company/update-company" --write-out '\n%{http_code}' \
		--data-urlencode "companyId=${CID}" --data-urlencode "virtualHost=${HOST}" \
		--data-urlencode "mx=$(field mx)" --data-urlencode "homeURL=${SITE_PATH}" \
		--data-urlencode "hasLogo=${HAS_LOGO}" --data-urlencode 'logoBytes=[]' \
		--data-urlencode "name=$(field name)" --data-urlencode "legalName=$(field legalName)" \
		--data-urlencode "legalId=$(field legalId)" --data-urlencode "legalType=$(field legalType)" \
		--data-urlencode "sicCode=$(field sicCode)" --data-urlencode "tickerSymbol=$(field tickerSymbol)" \
		--data-urlencode "industry=$(field industry)" --data-urlencode "type=$(field type)" \
		--data-urlencode "size=$(field size)")
	[ "${R##*$'\n'}" = 200 ] && [ "$(echo "${R%$'\n'*}" | jq -r '.homeURL // empty')" = "${SITE_PATH}" ] \
		|| die "the Home URL was refused (${R##*$'\n'})"
	echo "ok    the Home URL is ${SITE_PATH}"
fi

title=$(curl --silent --location "${H}/" | grep -o -E '<title>[^<]*' | head -1 | cut -c8-)
echo "${title}" | grep --quiet "Masterclass" || die "${H}/ still opens '${title}'"
echo "ok    ${H}/ opens '${title}'"

C=$(lr "${H}/o/c/elearningcourses/scopes/eLearning?pageSize=50" | jq -r --arg t "${TITLE}" '.items[] | select(.title == $t) | .id')
[ -n "${C}" ] || die "no course titled ${TITLE}"

E=$(lr "${H}/o/c/mycourseenrollments?pageSize=200" \
	| jq -r --argjson u "${SID}" --argjson c "${C}" '[.items[] | select(.r_courseToUser_userId == $u and .courseID == $c and .enrollmentStatus.key == "Confirmed")][0].id // empty')

if [ -n "${E}" ]; then
	echo "== 3. already Confirmed in '${TITLE}' (entry ${E}); keeping it"
else
	ES=$(lr "${H}/o/c/elearningcourses/${C}/elearningCourseSessions?sort=id:asc" | jq -r '.items[0].id // empty')
	[ -n "${ES}" ] || die "course ${C} has no sessions"

	echo "== 3. as the student: look up the session the way the button does, then enrol"
	MS=$(st "${H}/o/c/mycoursesessions?filter=courseSessionID%20eq%20${ES}" | jq -r '.items[0].id // empty')
	[ -n "${MS}" ] || die "the student cannot find MyCourseSession for session ${ES}"
	show "curl --request POST --url ${H}/o/c/mycourseenrollments --user ${SE}:${SP} --data '{\"enrollmentStatus\": \"Pending\", \"r_courseToUser_userId\": ${SID}, \"r_enrollmentToCourseSession_c_myCourseSessionId\": ${MS}, \"courseID\": ${C}}'"
	E=$(st -X POST -H 'Content-Type: application/json' "${H}/o/c/mycourseenrollments" \
		-d "{\"enrollmentStatus\": \"Pending\", \"r_courseToUser_userId\": ${SID}, \"r_enrollmentToCourseSession_c_myCourseSessionId\": ${MS}, \"courseID\": ${C}}" \
		| jq -r '.id // empty')
	[ -n "${E}" ] || die "the student's enrolment was refused"
	echo "ok    enrolled in '${TITLE}' (course ${C}, session ${ES}): entry ${E} $(status "${E}")"

	echo "== as admin: approve"
	show "curl --request PUT --url ${H}/o/c/mycourseenrollments/${E}/object-actions/approveACourse --user ${ADMIN}"
	lr -X PUT "${H}/o/c/mycourseenrollments/${E}/object-actions/approveACourse" -o /dev/null
	[ "$(status "${E}")" = Approved ] || die "approve left it $(status "${E}")"
	echo "ok    Approved"

	echo "== as the student: confirm"
	show "curl --request PUT --url ${H}/o/c/mycourseenrollments/${E}/object-actions/confirmingEnrollment --user ${SE}:${SP}"
	st -X PUT "${H}/o/c/mycourseenrollments/${E}/object-actions/confirmingEnrollment" -o /dev/null
	[ "$(status "${E}")" = Confirmed ] || die "confirm left it $(status "${E}")"
	echo "ok    Confirmed"
fi

echo "== 4. My Learning as the student"
st -H 'Accept: text/html' "${H}/o/headless-delivery/v1.0/sites/${G}/site-pages/my-learning/rendered-page" \
	| grep --quiet --fixed-strings "${TITLE}" || die "My Learning does not show ${TITLE}"
echo "ok    My Learning shows '${TITLE}'. Next: student-check.sh, then the snapshot."
