#!/usr/bin/env bash
#
# Assert the instruments before trusting any number.
#
#   ./evals/check.sh                 before a run — structure only
#   ./evals/check.sh /tmp/eval.json  after a run  — structure, then the results
#
# Two instrument failures have produced confident wrong conclusions here, and
# both looked like results:
#
#   * `skills` committed as a text file rather than a symlink. The manifest still
#     resolved, every run reported `plugins: [devcon2026-liferay]`, and the plugin
#     served nothing. A week of deltas measured the model against itself.
#   * A case with no `skill-fired` grader. The summary counted a grader that did
#     not exist and printed 0/5, which reads exactly like a skill that never fired.
#
# Delta near zero has three causes and they are not interchangeable:
#
#   indicator absent  ->  not measured
#   indicator dark    ->  the content never arrived
#   indicator lit     ->  the content is redundant
#
set -o errexit
set -o nounset
set -o pipefail

cd "$(dirname "$0")/.."

fail=0
note() { printf '  %-10s %s\n' "$1" "$2"; }

echo "Structure"

# 1. The plugin has to actually serve skills.
if [ ! -d skills ]; then
	mode=$(git ls-files -s skills 2>/dev/null | awk '{print $1}')
	note FAIL "skills/ is not a directory (git mode ${mode:-untracked}; want 120000)"
	fail=1
else
	count=$(find skills/ -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
	if [ "$count" -eq 0 ]; then
		note FAIL "skills/ resolves but is empty"
		fail=1
	else
		note ok "skills/ serves ${count} skills"
	fi
fi

# 2. Every case has to carry the indicator, or its delta cannot be read.
for dir in evals/*/; do
	case_name=$(basename "$dir")
	[ -f "${dir}case.yaml" ] || continue
	if [ -f "${dir}graders/skill-fired.md" ]; then
		note ok "${case_name}"
	else
		note FAIL "${case_name} has no skill-fired grader — its delta cannot be interpreted"
		fail=1
	fi
done

# 3. Results, when a run is handed over.
if [ $# -ge 1 ]; then
	echo
	echo "Results: $1"
	python3 - "$1" <<'PY' || fail=1
import json, sys

data = json.load(open(sys.argv[1]))
bad = 0

for case in data.get("cases", []):
	arms = case.get("arms", {}).get("with", [])
	names = {g["name"] for run in arms for g in run.get("graders", [])}
	delta = case["aggregates"]["delta"]

	if "skill-fired" not in names:
		print(f"  FAIL       {case['name']}: no skill-fired grader, delta {delta:+.2f} is unreadable")
		bad += 1
		continue

	lit = sum(
		1 for run in arms
		for g in run.get("graders", [])
		if g["name"] == "skill-fired" and g["passed"]
	)
	if lit == 0:
		print(f"  FAIL       {case['name']}: indicator dark {lit}/{len(arms)} — the skill never arrived")
		bad += 1
	elif lit < len(arms):
		print(f"  warn       {case['name']}: indicator lit {lit}/{len(arms)}, delta {delta:+.2f}")
	else:
		print(f"  ok         {case['name']}: lit {lit}/{len(arms)}, delta {delta:+.2f}")

sys.exit(1 if bad else 0)
PY
fi

echo
if [ "$fail" -ne 0 ]; then
	echo "Instruments are not sound. Do not trust the numbers."
	exit 1
fi
echo "Instruments sound."
