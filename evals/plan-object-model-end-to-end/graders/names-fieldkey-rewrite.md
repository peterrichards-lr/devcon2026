---
type: llm
focus: last_message
weight: 0.35
---

The display page template's `page-definition.json` maps fragment fields to DDM field
names — `"fieldKey": "Duration"`, `"fieldKey": "Module1Name"` and so on.

PASS if the plan says those `fieldKey` values must be rewritten to the object field
form, i.e. prefixed `ObjectField_` (`ObjectField_duration`), or otherwise states
explicitly that every field mapping on the page has to be repointed at object
fields.

FAIL if the plan proposes the object model and the content type change but never
addresses the per field mappings on the page — which is what actually leaves the
rendered page blank.
