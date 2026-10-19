# DevCon 2026 — Masterclass LMS Modernization

This repository contains the source code, client extensions, site initializer definitions, and field notes for the **DevCon 2026** presentation: **Migrating Masterclass LMS from Legacy Web Content to Modern Headless CMS and Liferay Objects**.

---

## Overview

The project demonstrates two distinct migration methodologies:

1. **Approach 1: Site Initializer to Site Initializer**  
   Rebuilding the legacy 2024 Masterclass site initializer into modern declarative assets: Headless CMS Spaces, depot-scoped Content Structures, Liferay Objects, and batch client extensions.
2. **Approach 2: In-Place Live Site Migration**  
   Migrating an active, running Liferay instance using Headless REST APIs and the Liferay MCP Server without deploying an initializer.

---

## Tags: where each stage of the talk lives

| Tag | State |
| --- | --- |
| `devcon-start` | The starting point: the 2024 Masterclass site initializer on web content (DDM structures, journal articles), renamed to Masterclass CMS and nothing else. Both approaches start here. |
| `devcon-approach-1` | Approach 1's final state: the site initializer rebuilt on the Headless CMS, with the data batch, the demo student and the test scripts. The Approach 1 demo and its backup video were recorded from a provision of this state. |
| `devcon-approach-2` | Approach 2's final state: the live site migrated in place. |

```bash
git checkout devcon-start        # before
git checkout devcon-approach-1   # after, Approach 1
```

`step-01-initial` and `step-02-aiconversion` are earlier checkpoints from 6 October and are
kept for history.

---

## Running Approach 1

Approach 1 builds and runs on **Liferay DXP 2026.Q3** (verified on 2026.q3.5), starting from
an instance with no Masterclass data.

### Feature flags

None. Approach 1 uses only APIs that are on by default: a clean run with `LPD-35443` and
`LPS-178052` switched off created the site, loaded the data, and rendered every page.

Approach 2 edits page specifications over REST, and those calls need `LPD-74328`; see
[LESSONS-LEARNT.md](LESSONS-LEARNT.md).

### Build

From the workspace root:

```bash
blade gw clean \
	:modules:masterclass-cms-workarounds:jar \
	:modules:masterclass-cms-site-initializer:jar \
	:client-extensions:liferay-masterclassobj-simplerheadlesscallsjs:assemble \
	:client-extensions:liferay-masterclass-custom-css:assemble \
	:client-extensions:masterclass-cms-data-batch:assemble
```

The jars land in each module's `build/libs/`, and the client extension zips in each
project's `dist/`.

### Deploy, in this order

Nothing enforces the order, and getting it wrong fails quietly. Copy each artifact into
`osgi/modules/` and wait for its `STARTED` line before the next step.

1. `com.liferay.masterclass.cms.workarounds-1.0.0.jar`,
   `liferay-masterclassobj-simplerheadlesscallsjs.zip` and
   `liferay-masterclass-custom-css.zip`, in any order.
2. `com.liferay.site.initializer.masterclass.cms-1.0.0.jar`.
3. Create the site: **Control Panel → Sites → Add**, then choose **Masterclass CMS**. Or
   over REST:

   ```bash
   curl \
   	--data '{"membershipType": "open", "name": "Masterclass CMS", "templateKey": "com.liferay.site.initializer.masterclass.cms", "templateType": "site-initializer"}' \
   	--header "Content-Type: application/json" \
   	--request POST \
   	--url "http://localhost:8080/o/headless-admin-site/v1.0/sites" \
   	--user "test@liferay.com:test"
   ```

   Wait for `Initialized com.liferay.site.initializer.masterclass.cms` in the log.
4. `masterclass-cms-data-batch.zip`. It loads into the Space that step 3 creates, so it
   fails if deployed earlier.

Why the order matters, step by step:
[client-extensions/masterclass-cms-data-batch/README.md](client-extensions/masterclass-cms-data-batch/README.md).

### Check the result

The site initializer can drop a page's collection depending on the order its handlers run
in ([UPSTREAM-FEEDBACK.md](UPSTREAM-FEEDBACK.md), item 7), and it still reports success.
After creating the site, open **Home**, **Blog** and **Courses**. If any of them lists
nothing, delete the site and create it again.

### Activate the demo student

Users created by a site initializer are inactive by design: `BundleSiteInitializer` sets each
user to inactive right after creating it (LPS-184738), so that an initializer can't silently
create accounts that can sign in. An administrator must activate `student.one@liferay.com`
before it can sign in: **Control Panel → Users and Organizations**, then the user's
**Actions → Activate**. Or run `scripts/demo-prep.sh`, which does this first and
then gives the student one confirmed course.

### Test it end to end

[TESTING-APPROACH-1.md](TESTING-APPROACH-1.md) is the full procedure: provision from a clean
snapshot, check collections, the guest view and the demo student, take the snapshot, and
how to roll back when any stage fails.

---

## Upstream Feedback & Platform Tracking

During the end-to-end implementation and automation of both approaches, several product gaps, race conditions, and architectural improvement opportunities were identified and logged with Liferay engineering and the community.

Eight items are tracked: three for Headless CMS and the data engine, two for layouts and the Info framework, and three for site initializers.

For the summary table, descriptions, steps to reproduce, and technical pointers for each item, see **[UPSTREAM-FEEDBACK.md](UPSTREAM-FEEDBACK.md)**.

---

## Documentation Index

* **[UPSTREAM-FEEDBACK.md](UPSTREAM-FEEDBACK.md)** — Detailed breakdown of reported bugs, feature requests, and engineering clues.
* **[LESSONS-LEARNT.md](LESSONS-LEARNT.md)** — Chronological engineering log of discoveries, empirical measurements, and slide takeaways for the DevCon talk.
* **[GETTING_STARTED.md](GETTING_STARTED.md)** — Local bundle initialization and workspace setup instructions.
* **[GEMINI.md](GEMINI.md)** — Liferay Workspace standards, architectural principles, and AI agent execution rules.

---

## Repository Structure

```
devcon2026/
├── client-extensions/       # Client Extensions (Custom CSS, JS headless helpers, batch data)
├── fragments/               # Reusable Page Editor Fragments (HTML/CSS/JS)
├── modules/                 # OSGi modules and site initializer bundle
│   ├── masterclass-cms-site-initializer/
│   └── masterclass-cms-workarounds/
├── configs/                 # Environment configurations (local, dev, uat, prod, docker)
├── evals/                   # Automated evaluation suite
└── scripts/                 # Quality guard rails and verification scripts
```
