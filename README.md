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
