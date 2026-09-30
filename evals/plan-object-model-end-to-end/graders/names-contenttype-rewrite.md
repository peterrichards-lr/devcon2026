---
type: llm
focus: last_message
weight: 0.3
---

`layout-page-templates/display-page-templates/course/display-page-template.json`
binds to `"className": "com.liferay.journal.model.JournalArticle"`.

PASS if the plan says that binding must change to the new object — by any correct
means, whether the `[$OBJECT_DEFINITION_CLASS_NAME:…$]` token or an object
definition class name.

FAIL if the plan covers the object model but never mentions that the display page
template's content type binding has to change. Renaming files or moving directories
is not the same thing.
