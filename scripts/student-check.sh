#!/usr/bin/env bash
#
# student-check.sh [groupId] [student-email] [student-password]
#
# Verifies the demo student after scripts/demo-prep.sh has run. Run it before taking a
# snapshot: it removes everything it creates, so the snapshot keeps only demo-prep's
# Confirmed enrolment.
#
#   1. The student exists, is active, is a site member, and can sign in.
#   2. The student can read every course object, and the MyCourseSession lookup the
#      register button makes.
#   3. demo-prep's Confirmed course is visible; the full flow works over REST: enrol with
#      the button's payload (Pending), admin approves, student confirms, My Learning
#      shows it. Self-approval and self-update are reported as WARN: a known issue,
#      logged and not fixed before DevCon.
#   4. The student can't list, read, change or delete another user's enrolment.
#   5. No manual permission changes. This script grants nothing, so a missing grant in
#      the tree shows up as a FAIL above. The only allowed post-provision step is the
#      scripted, documented user activation in demo-prep.sh.
#
# Check 3 on stage (the register button in a browser) is manual: a second course goes
# to Pending on Course Registrations.
#
# LIFERAY_URL (default http://localhost:8080) and LIFERAY_ADMIN (default
# test@liferay.com:test) select the instance and the administrator.
#

set -o nounset
set -o pipefail

if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
	G="${1}"
	shift
else
	G=$("$(dirname "$0")/site-id.sh") || exit 1
	echo "site ${G} (Masterclass CMS)"
fi
SE="${1:-student.one@liferay.com}"
SP="${2:-test}"
H="${LIFERAY_URL:-http://localhost:8080}"
ADMIN="${LIFERAY_ADMIN:-test@liferay.com:test}"
OTHER_EMAIL=other.tester@example.com
OTHER_PASSWORD='Test1234!'
KNOWN="known issue: enrolment owners can change their own status (LESSONS-LEARNT)"

fails=0
warns=0
E=
OE=
OTHER=

lr() { curl --silent --user "${ADMIN}" "$@"; }
st() { curl --silent --user "${SE}:${SP}" "$@"; }

pass() { echo "ok    $*"; }
warn() { echo "WARN  $*"; warns=$((warns + 1)); }
fail() { echo "FAIL  $*"; fails=$((fails + 1)); }

cleanup() {
	for id in ${E} ${OE}; do
		lr -X DELETE "${H}/o/c/mycourseenrollments/${id}" -o /dev/null
	done

	[ -n "${OTHER}" ] && lr -X DELETE "${H}/o/headless-admin-user/v1.0/user-accounts/${OTHER}" -o /dev/null

	echo "cleaned up: test enrolments ${E:-none} ${OE:-none}, test user ${OTHER:-none}"
}

trap cleanup EXIT

echo "== 1. the demo student exists, is active, is a site member, and can sign in"
U=$(lr "${H}/o/headless-admin-user/v1.0/user-accounts/by-email-address/${SE}")
SID=$(echo "${U}" | jq -r '.id // empty')
[ -n "${SID}" ] || { fail "no user ${SE}"; echo "${fails} failure(s)"; exit 1; }

if [ "$(echo "${U}" | jq -r .status)" != Active ]; then
	fail "${SE} (id ${SID}) exists but is $(echo "${U}" | jq -r .status); run scripts/demo-prep.sh first"
	echo "${fails} failure(s)"
	exit 1
fi

pass "${SE} exists and is active (id ${SID})"

lr "${H}/api/jsonws/user/get-group-user-ids?groupId=${G}" | jq -e --argjson id "${SID}" 'index($id) != null' >/dev/null \
	&& pass "member of site ${G}" || fail "not a member of site ${G}"

code=$(st --output /dev/null --write-out '%{http_code}' "${H}/o/headless-admin-user/v1.0/my-user-account")
[ "${code}" = 200 ] && pass "signs in (my-user-account ${code})" || fail "cannot sign in (my-user-account ${code})"

echo "== 2. the student can read every course object"
for plural in elearningcourses elearningmodules elearningteachers elearningsessions elearningblogs; do
	a=$(lr "${H}/o/c/${plural}/scopes/eLearning?pageSize=1" | jq -r '.totalCount // "err"')
	r=$(st --write-out '\n%{http_code}' "${H}/o/c/${plural}/scopes/eLearning?pageSize=1")
	code=${r##*$'\n'}
	s=$(echo "${r%$'\n'*}" | jq -r '.totalCount // "err"' 2>/dev/null)
	[ "${code}" = 200 ] && [ "${s}" = "${a}" ] && pass "${plural}: ${s}/${a}" || fail "${plural}: http ${code}, student sees ${s} of ${a}"
done

a=$(lr "${H}/o/c/mycoursesessions?pageSize=1" | jq -r '.totalCount')
s=$(st "${H}/o/c/mycoursesessions?pageSize=1" | jq -r '.totalCount // "err"')
[ "${s}" = "${a}" ] && pass "mycoursesessions (the register button's lookup): ${s}/${a}" \
	|| fail "mycoursesessions (the register button's lookup): student sees ${s} of ${a}; the button will report 'not linked'"

echo "== 3. demo-prep's course, then the full flow over REST"
n=$(st "${H}/o/c/mycourseenrollments?filter=r_courseToUser_userId%20eq%20'${SID}'" | jq -r '[.items[] | select(.enrollmentStatus.key == "Confirmed")] | length')
[ "${n}" -ge 1 ] 2>/dev/null && pass "Confirmed enrolment from demo-prep.sh visible to the student (${n})" \
	|| fail "no Confirmed enrolment visible to the student; run scripts/demo-prep.sh first"

MS=$(lr "${H}/o/c/mycoursesessions?pageSize=1&sort=id:desc" | jq -r '.items[0].id')
C2=$(lr "${H}/o/c/elearningcourses/scopes/eLearning?pageSize=1&sort=id:desc" | jq -r '.items[0].id')
R=$(st -X POST -H 'Content-Type: application/json' "${H}/o/c/mycourseenrollments" --write-out '\n%{http_code}' \
	-d "{\"enrollmentStatus\": \"Pending\", \"r_courseToUser_userId\": ${SID}, \"r_enrollmentToCourseSession_c_myCourseSessionId\": ${MS}, \"courseID\": ${C2}}")
E=$(echo "${R%$'\n'*}" | jq -r '.id // empty')
[ -n "${E}" ] && pass "enrol with the button's payload: ${R##*$'\n'}, entry ${E}" || fail "enrol with the button's payload: ${R##*$'\n'}"

if [ -n "${E}" ]; then
	code=$(st -X PUT --output /dev/null --write-out '%{http_code}' "${H}/o/c/mycourseenrollments/${E}/object-actions/approveACourse")
	s=$(lr "${H}/o/c/mycourseenrollments/${E}" | jq -r .enrollmentStatus.key)
	[ "${s}" = Pending ] && pass "student cannot approve themselves (${code})" || warn "student approved their own enrolment (${code} -> ${s}); ${KNOWN}"
	lr -X PATCH -H 'Content-Type: application/json' "${H}/o/c/mycourseenrollments/${E}" -d '{"enrollmentStatus": {"key": "Pending"}}' -o /dev/null

	code=$(st -X PATCH -H 'Content-Type: application/json' --output /dev/null --write-out '%{http_code}' "${H}/o/c/mycourseenrollments/${E}" -d '{"enrollmentStatus": {"key": "Completed"}}')
	s=$(lr "${H}/o/c/mycourseenrollments/${E}" | jq -r .enrollmentStatus.key)
	[ "${s}" = Pending ] && pass "student cannot set their own status (${code})" || warn "student set their own status (${code} -> ${s}); ${KNOWN}"
	lr -X PATCH -H 'Content-Type: application/json' "${H}/o/c/mycourseenrollments/${E}" -d '{"enrollmentStatus": {"key": "Pending"}}' -o /dev/null

	code=$(lr -X PUT --output /dev/null --write-out '%{http_code}' "${H}/o/c/mycourseenrollments/${E}/object-actions/approveACourse")
	s=$(lr "${H}/o/c/mycourseenrollments/${E}" | jq -r .enrollmentStatus.key)
	[ "${s}" = Approved ] && pass "admin approves (${code})" || fail "admin approve (${code} -> ${s})"

	code=$(st -X PUT --output /dev/null --write-out '%{http_code}' "${H}/o/c/mycourseenrollments/${E}/object-actions/confirmingEnrollment")
	s=$(lr "${H}/o/c/mycourseenrollments/${E}" | jq -r .enrollmentStatus.key)
	[ "${s}" = Confirmed ] && pass "student confirms (${code})" || fail "student cannot confirm (${code} -> ${s}): BUG"

	n=$(st -H 'Accept: text/html' "${H}/o/headless-delivery/v1.0/sites/${G}/site-pages/my-learning/rendered-page" | grep -c "c_elearningcourse")
	[ "${n}" -ge 2 ] && pass "My Learning shows demo-prep's and the confirmed course (${n} links)" || fail "My Learning shows ${n} course link(s), expected 2"
fi

echo "== 4. the student can't see or change other users' enrolments"
OTHER=$(lr -X POST -H 'Content-Type: application/json' "${H}/o/headless-admin-user/v1.0/user-accounts" \
	-d "{\"alternateName\": \"othertester\", \"emailAddress\": \"${OTHER_EMAIL}\", \"familyName\": \"Tester\", \"givenName\": \"Other\", \"password\": \"${OTHER_PASSWORD}\"}" | jq -r '.id // empty')
[ -z "${OTHER}" ] && OTHER=$(lr "${H}/o/headless-admin-user/v1.0/user-accounts/by-email-address/${OTHER_EMAIL}" | jq -r '.id // empty')
lr -X POST "${H}/api/jsonws/user/add-group-users" -d groupId="${G}" -d "userIds=[${OTHER}]" -o /dev/null

C=$(lr "${H}/o/c/elearningcourses/scopes/eLearning?pageSize=1&sort=id:asc" | jq -r '.items[0].id')
OE=$(curl --silent --user "${OTHER_EMAIL}:${OTHER_PASSWORD}" -X POST -H 'Content-Type: application/json' "${H}/o/c/mycourseenrollments" \
	-d "{\"courseID\": ${C}, \"enrollmentStatus\": {\"key\": \"Confirmed\"}, \"r_courseToUser_userId\": ${OTHER}}" | jq -r '.id // empty')
[ -n "${OE}" ] && pass "other user enrolled as themselves (entry ${OE})" || fail "other user could not enrol over REST"

n=$(st "${H}/o/c/mycourseenrollments?filter=r_courseToUser_userId%20eq%20'${OTHER}'" | jq -r '.totalCount // "err"')
[ "${n}" = 0 ] && pass "student lists other's enrolments: 0" || fail "student lists other's enrolments: ${n}"

if [ -n "${OE}" ]; then
	for m in GET PATCH DELETE; do
		body=()
		[ "${m}" = PATCH ] && body=(-H 'Content-Type: application/json' -d '{"enrollmentStatus": {"key": "Discarded"}}')
		code=$(st -X "${m}" ${body[@]+"${body[@]}"} --output /dev/null --write-out '%{http_code}' "${H}/o/c/mycourseenrollments/${OE}")
		case "${code}" in 403|404) pass "student ${m} other's enrolment: ${code}" ;; *) fail "student ${m} other's enrolment: ${code}" ;; esac
	done

	still=$(lr "${H}/o/c/mycourseenrollments/${OE}" | jq -r '.enrollmentStatus.key // "gone"')
	[ "${still}" = Confirmed ] && pass "other's enrolment unchanged (${still})" || fail "other's enrolment changed: ${still}"
fi

echo "== 5. no manual permission changes; the only allowed post-provision step is the scripted, documented user activation"
echo "this script granted nothing, so any FAIL above is a grant missing from the tree"
echo "${fails} failure(s), ${warns} warning(s)"
[ "${fails}" = 0 ] && echo "Ready for check 3: sign in as ${SE}, register for a session of a second course, then check it is Pending on Course Registrations and demo-prep's course is on My Learning."
