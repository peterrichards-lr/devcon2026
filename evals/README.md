# Skill Evals

Regression tests for the MD files in `.agents/`, run with `claude plugin eval`.

The subject is instructions for a non deterministic agent, so a single passing run
proves nothing. Each case runs N times against two arms — with the skill loaded and
without — and the number that matters is the **delta**, not the score. A case scoring
1.00 with a delta of 0.00 means the model already knew; that content is documentation,
not instruction.

## Check the instruments first

```bash
./evals/check.sh                 # before a run — structure only
./evals/check.sh /tmp/eval.json  # after a run  — structure, then results
```

**Two instrument failures have produced confident wrong conclusions here, and both looked
like results.** `skills` was committed as a text file rather than a symlink, so the manifest
resolved, every run reported `plugins: [devcon2026-liferay]`, and the plugin served nothing
— a week of deltas measured the model against itself. Later, a case with no `skill-fired`
grader made a summary print `0/5`, which reads exactly like a skill that never fired, and a
whole finding was built on it.

A delta near zero has three causes and they are not interchangeable:

| Indicator | Δ ≈ 0 means |
| --- | --- |
| absent | not measured — the number says nothing |
| dark | the content never arrived |
| lit | the content is redundant |

`check.sh` asserts that `skills/` resolves and serves skills, that every case carries a
`skill-fired` grader, and — given a results file — that the indicator was lit. It exits
non-zero when the instruments are unsound, so it can gate a run.

## Running

```bash
claude plugin eval . --eval-dir evals --runs 5 -j 2 \
	--trust-plugin --no-publish --scaffold --judge-model sonnet
```

Every flag is load bearing:

| Flag | Why |
| --- | --- |
| `--scaffold` | Without it `scaffold_script` never runs, every case executes against an **empty workspace**, and the run still scores — as zero |
| `--judge-model sonnet` | The default judge is haiku, and llm graders are noisy on long inputs |
| `--trust-plugin` | Skips the first-run trust prompt |
| `--no-publish` | Keeps the HTML report local |

Results land in `evals/results/`, which is gitignored.

Requires the repo to resolve as a plugin — `.claude-plugin/plugin.json` with components
at `skills/`. Without it the harness silently falls back to baseline and reports
`plugins: []`, so the suite appears to exercise a skill while measuring the model alone.

## Cases

| Case | Asserts | Last measured |
| --- | --- | --- |
| `fact-batch-directory` | `site-initializer/batch/` is never read by `BundleSiteInitializer` | **Δ +0.32** (7 Oct, after splitting a compound grader). The earlier **+0.76** was measured with no skill loaded |
| `fact-relationship-foreign-key` | The FK sits on the child but is named for the parent; a wrong key still returns `200` | Δ +0.18 |
| `plan-object-model-end-to-end` | Grades a whole migration plan: field types, and both reference rewrites | Δ −0.07 |

## What the measurements established

Seven cases have been run against this skill set. Everything covering **documented API
surface or ordinary data modelling** measured ~0 — scope constants, dangling object
references, token delimiters, resolving numbered fieldsets into a related object, the
DDM to object type mapping, the display page template rewrites. The model has all of it.

The only case measuring real uplift covers **undocumented implementation behaviour**:
that `BundleSiteInitializer` silently skips `batch/` appears in no published document.

So the test for new skill content, and for new cases, is: **could someone find this in
the documentation?** If yes, writing it down does not change what an agent does.

`.agent-state.md` at the repo root carries the full record — retired cases with their
deltas, grader conventions, and the harness gotchas that cost real money to discover.
Read it before adding a case.