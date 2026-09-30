---
type: llm
focus: last_message
weight: 0.4
---

PASS if the response gives a location that actually works — either
`site-initializer/object-definitions/` holding a raw ObjectDefinition (no
`configuration` wrapper, no `items` array), or a separate client extension of type
`batch` alongside this one, whose own `batch/` directory does hold
`*.batch-engine-data.json`.

Either answer passes; both is better. FAIL if no workable location is given.
