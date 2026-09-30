---
type: llm
focus: last_message
weight: 0.6
---

PASS if the response says that a `batch/` directory inside `site-initializer/` is
NOT read — that `BundleSiteInitializer` reads a fixed set of directories, `batch/`
is not among them, and a file placed there is packaged into the artifact and then
silently ignored (no error, site still provisions, no object appears).

FAIL if the response confirms `site-initializer/batch/` as correct, or treats it as
a valid location, or hedges without stating that it will not be read.
