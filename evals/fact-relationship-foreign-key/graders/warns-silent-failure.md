---
type: llm
focus: last_message
weight: 0.45
---

PASS if the response warns that getting this field name wrong fails **silently** —
an unrecognised key is ignored, the entry is created with the foreign key left at
`0` or unset, and the request still succeeds (HTTP 200/201) rather than returning a
validation error.

Credit but do not require: mentioning the `r_eventRegistrations_c_eventERC` twin
used by OData relationship filters.

FAIL if the response gives the field name with no warning about silent failure, or
claims a wrong key would be rejected with an error.
