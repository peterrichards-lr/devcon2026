# Masterclass CMS Data Batch

Loads **data only**: 25 documents, 42 content entries, and the entry folders they live in.

The model it loads into — the Space, the object definitions, their picklist and their
relationships — belongs to `modules/masterclass-cms-site-initializer`, not here.

## Deploy order matters, and nothing enforces it

```
1. deploy modules/masterclass-cms-site-initializer
2. create the site from it
3. deploy this client extension
```

A client extension runs its batch files **when it deploys**. The site initializer runs
**when a site is created from it**. The Space is created by the initializer, so it does not
exist until step 2 — and every file here is scoped to it.

Deploy this before the site exists and the import fails:

```text
Unable to deploy batch engine file .../00-02-cms-folder...json:
    com.liferay.portal.kernel.exception.NoSuchGroupException
Unable to deploy batch engine file .../00-03-cms-basic-document...json:
    No ObjectEntryFolder exists with the key {externalReferenceCode=COURSES, groupId=0, ...}
```

It fails loudly rather than importing nothing, so the symptom is visible — but the fix is
to redeploy this after the site exists, not to change anything here.

## Scope key is the Space name, not an external reference code

Every file here scopes with `"scopeKey": "eLearning"`.

The initializer creates the Space from `depot-entries.json`, and that format has **no
`externalReferenceCode` field** — the handler matches on group name and Liferay generates a
UUID. So the Space has no stable code to scope by. `GroupUtil.getGroupId` resolves a scope
key by name first, then numeric id, then external reference code, which makes the name the
one value that is stable across bundles.

Do not change these back to `ELEARNING-SPACE`; it only resolves on an instance where the
Space happens to carry that code.
