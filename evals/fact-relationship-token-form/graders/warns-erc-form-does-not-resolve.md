---
type: llm
focus: last_message
weight: 0.25
---

The batch file names both ends by external reference code —
`objectDefinitionExternalReferenceCode1` and `objectDefinitionExternalReferenceCode2`.

PASS if the response says, in any wording, that those external reference code fields will
not work in the site initializer file and that the numeric object definition ID form is
required instead.

FAIL if it only produces the correct file without saying why the external reference code
form fails, or if it keeps those fields, or offers them as an equally valid option.
