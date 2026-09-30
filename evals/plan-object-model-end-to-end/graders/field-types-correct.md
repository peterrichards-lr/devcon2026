---
type: llm
focus: last_message
weight: 0.35
---

Every field in the DDM structure is declared `type=text dataType=string`, whatever
it actually holds. The stored values in the journal articles are what decide the
object field type.

PASS if the plan proposes a **numeric** object field type (`Integer`, or `Decimal`)
for at least two of `NumberOfLessons`, `Quizzes`, `MaxRetakes`, `PassPercentage` —
whose stored values are `"9"`, `"3"`, `"2"` and `"90%"` — rather than carrying them
across as text because DDM called them text.

Credit but do not require: keeping `Duration` (`"4 weeks"`) as text; using
`RichText` for the `rich_text` field; using `Attachment` for the `image` fields.

FAIL if every field is mapped to a text type, or if the plan does not say what type
each field becomes.
