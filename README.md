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

### Executive Summary

| # | Item Title | Team / Domain | Classification | Primary Beneficiary | Tracking / Status |
|---|---|---|---|---|---|
| **1** | **Headless REST API for Collections / Asset Lists (CRUD & Criteria)** | Headless CMS & Data Engine | Feature Request | Headless CMS APIs, MCP, External CI/CD & AI Agents | [Discuss #1075](https://discuss.liferay.com/t/headless-rest-api-for-managing-collections-asset-lists-crud-criteria/1075) |
| **2** | **Lightweight REST Endpoint to Publish Site Page Drafts** | Headless CMS & Data Engine | Bug / FR | Headless Site API (`headless-admin-site`) consumers | *Pending* |
| **3** | **Object Actions on Versioned/Draft Content Structures Fire on Empty Draft Shells** | Headless CMS & Data Engine | Bug / FR | Headless CMS Content Structures & Automation | [LPD-110575](https://liferay.atlassian.net/browse/LPD-110575) |
| **4** | **Custom Display Templates (Info Templates) Not Available for Related Collections** | Layouts & Info Framework | Bug | Page Editor, Headless CMS rendering & Site Initializers | [LPD-110572](https://liferay.atlassian.net/browse/LPD-110572) |
| **5** | **Page Layout Import Requires Internal Database Primary Key for Attachment Fields** | Layouts & Info Framework | Bug | Site Initializer portability & REST Page Specifications | [LPD-110573](https://liferay.atlassian.net/browse/LPD-110573) |
| **6** | **Display Page Templates Fail on Clean Site Initializer Deployments Due to Template Dependency Timing** | Site Initializers & DevEx | Bug | Clean bundle provisioning, CI/CD pipelines | [LPD-110574](https://liferay.atlassian.net/browse/LPD-110574) |
| **7** | **Collections in Page Definitions Are Inconsistently Resolved or Dropped on Clean Site Initializer Provisioning** | Site Initializers & DevEx | Bug | Site Initializer predictability and automation | [LPD-110315](https://liferay.atlassian.net/browse/LPD-110315) |
| **8** | **Support Object Validation Rules in Site Initializers** | Site Initializers & DevEx | Feature Request | Site Initializers & Infrastructure-as-Code | [Discuss #1074](https://discuss.liferay.com/t/better-support-for-object-validation-rules-in-site-initializers/1074) |

For comprehensive descriptions, steps to reproduce, and technical pointers for each item, see **[UPSTREAM-FEEDBACK.md](UPSTREAM-FEEDBACK.md)**.

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
