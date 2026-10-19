---
type: llm
focus: last_message
weight: 0.6
---

The tree has `object-relationships/` but **no `object-definitions/` directory**.

`_addObjectDefinitions` registers company wide tokens for custom object definitions, then
returns early when `getResourcePaths("/site-initializer/object-definitions")` is empty —
**before** the loop that registers system object definitions such as `User`. So
`[$OBJECT_DEFINITION_ID:User$]` resolves to nothing and the relationship is never created.

PASS if the response identifies that the missing `object-definitions/` directory is why the
`User` token does not resolve, and that adding a definition file there is the fix.

FAIL if it blames something else — handler ordering, a wrong token name, the sibling batch
extension, publication status, permissions, a malformed file — or if it only suggests
checking logs without naming the cause.
