---
type: llm
focus: last_message
weight: 0.3
---

PASS if the response says `site-initializer/batch/` is **not** a location the site
initializer reads — that `BundleSiteInitializer` reads a fixed set of directories and
`batch/` is not among them.

FAIL if it confirms `site-initializer/batch/` as correct, treats it as valid, or hedges
without saying it will not be read.
