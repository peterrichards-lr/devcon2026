@.agents/liferay-rules.md

## Skill Rules & Overrides

- **Superpowers Skills:** Superpowers skills (`using-superpowers`, `finishing-a-development-branch`, `brainstorming`, `systematic-debugging`, `writing-plans`, `executing-plans`, `subagent-driven-development`, etc.) are **explicitly deactivated** in this workspace by user directive. Do NOT activate or invoke any superpowers skills.

## Gemini-only Skills

`.gemini/skills/` also carries skills the other agents do not have. Gemini discovers them
from that directory; the one worth routing to by name:

| User Intent | Skill |
| --- | --- |
| Convert Figma designs (URLs, prototypes, screenshots) to Page Fragments | `figma-to-liferay-fragment` |
