#!/usr/bin/env bash
#
# demo-prep.sh <groupId> [student-email] [student-password] [course title]
#
# Run once after provisioning, before student-check.sh and before taking a snapshot.
#
#   1. Activates the demo student. The site initializer creates every user inactive on
#      purpose (LPS-184738), so this is the one allowed post-provision step.
#   2. Gives the student one Confirmed course the way a real student gets one: enrol with
#      the register button's payload, an admin approves, the student confirms.
#   3. Checks that My Learning shows that course.
#
# Grants no permissions. Safe to re-run: an enrolment that is already Confirmed is kept.
#
# LIFERAY_URL (default http://localhost:8080) and LIFERAY_ADMIN (default
# test@liferay.com:test) select the instance and the administrator.
#

set -o nounset
set -o pipefail

G="${1:?usage: demo-prep.sh <groupId> [student-email] [student-password] [course title]}"
SE="${2:-student.one@liferay.com}"
SP="${3:-test}"
TITLE="${4:-Building Enterprise Websites with Liferay}"
H="${LIFERAY_URL:-http://localhost:8080}"
ADMIN="${LIFERAY_ADMIN:-test@liferay.com:test}"

lr() { curl --silent --user "${ADMIN}" "$@"; }
st() { curl --silent --user "${SE}:${SP}" "$@"; }
die() { echo "FAIL  $*"; exit 1; }
status() { lr "${H}/o/c/mycourseenrollments/$1" | jq -r '.enrollmentStatus.key'; }

echo "== 1. activate the demo student"
U=$(lr "${H}/o/headless-admin-user/v1.0/user-accounts/by-email-address/${SE}")
SID=$(echo "${U}" | jq -r '.id // empty')
[ -n "${SID}" ] || die "no user ${SE}"

if [ "$(echo "${U}" | jq -r .status)" != Active ]; then
	lr -X PATCH -H 'Content-Type: application/json' -d '{"status": "Active"}' \
		"${H}/o/headless-admin-user/v1.0/user-accounts/${SID}" -o /dev/null
fi

[ "$(lr "${H}/o/headless-admin-user/v1.0/user-accounts/${SID}" | jq -r .status)" = Active ] || die "${SE} is still inactive"
code=$(st --output /dev/null --write-out '%{http_code}' "${H}/o/headless-admin-user/v1.0/my-user-account")
[ "${code}" = 200 ] || die "${SE} is active but cannot sign in (${code})"
echo "ok    ${SE} (id ${SID}) is active and can sign in"

C=$(lr "${H}/o/c/elearningcourses/scopes/eLearning?pageSize=50" | jq -r --arg t "${TITLE}" '.items[] | select(.title == $t) | .id')
[ -n "${C}" ] || die "no course titled ${TITLE}"

E=$(lr "${H}/o/c/mycourseenrollments?pageSize=200" \
	| jq -r --argjson u "${SID}" --argjson c "${C}" '[.items[] | select(.r_courseToUser_userId == $u and .courseID == $c and .enrollmentStatus.key == "Confirmed")][0].id // empty')

if [ -n "${E}" ]; then
	echo "== 2. already Confirmed in '${TITLE}' (entry ${E}); keeping it"
else
	ES=$(lr "${H}/o/c/elearningcourses/${C}/elearningCourseSessions?sort=id:asc" | jq -r '.items[0].id // empty')
	[ -n "${ES}" ] || die "course ${C} has no sessions"

	echo "== 2. as the student: look up the session the way the button does, then enrol"
	MS=$(st "${H}/o/c/mycoursesessions?filter=courseSessionID%20eq%20${ES}" | jq -r '.items[0].id // empty')
	[ -n "${MS}" ] || die "the student cannot find MyCourseSession for session ${ES}"
	E=$(st -X POST -H 'Content-Type: application/json' "${H}/o/c/mycourseenrollments" \
		-d "{\"enrollmentStatus\": \"Pending\", \"r_courseToUser_userId\": ${SID}, \"r_enrollmentToCourseSession_c_myCourseSessionId\": ${MS}, \"courseID\": ${C}}" \
		| jq -r '.id // empty')
	[ -n "${E}" ] || die "the student's enrolment was refused"
	echo "ok    enrolled in '${TITLE}' (course ${C}, session ${ES}): entry ${E} $(status "${E}")"

	echo "== as admin: approve"
	lr -X PUT "${H}/o/c/mycourseenrollments/${E}/object-actions/approveACourse" -o /dev/null
	[ "$(status "${E}")" = Approved ] || die "approve left it $(status "${E}")"
	echo "ok    Approved"

	echo "== as the student: confirm"
	st -X PUT "${H}/o/c/mycourseenrollments/${E}/object-actions/confirmingEnrollment" -o /dev/null
	[ "$(status "${E}")" = Confirmed ] || die "confirm left it $(status "${E}")"
	echo "ok    Confirmed"
fi

echo "== 3. My Learning as the student"
st -H 'Accept: text/html' "${H}/o/headless-delivery/v1.0/sites/${G}/site-pages/my-learning/rendered-page" \
	| grep --quiet --fixed-strings "${TITLE}" || die "My Learning does not show ${TITLE}"
echo "ok    My Learning shows '${TITLE}'. Next: student-check.sh, then the snapshot."
