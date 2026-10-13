@.agents/liferay-rules.md

## Gemini-only Skills

`.gemini/skills/` also carries skills the other agents do not have. Gemini discovers them
from that directory; the one worth routing to by name:

| User Intent | Skill |
| --- | --- |
| Convert Figma designs (URLs, prototypes, screenshots) to Page Fragments | `figma-to-liferay-fragment` |
