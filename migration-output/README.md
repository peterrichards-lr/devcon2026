# What an automatic migration of Masterclass actually produces

Generated from `master` — the four DDM structures and their 20 journal articles. Nothing
here was invented; every field and every entry is derived from the source.

## Output

| Object | Derived from | Entries |
| --- | --- | --- |
| `MCCourse` | `course.xml` + the `Features` fieldset, flattened | 3 |
| `MCTeacher` | `teacher.xml` | 5 |
| `MCBlog` | `blog.xml` | 9 |
| `MCModule` | **`course.xml`'s `Module1/2/3` repeating fieldsets, normalised** | **9** |
| `MCCourse -> MCModule` | implied by those fieldsets | one-to-many |

## The module normalisation is the real work

Every Masterclass course hard codes three modules as repeating fieldsets:

```
Module1 (fieldset)   Module1Name, Module1Description, Module1Duration, Module1NumberOfLessons
Module2 (fieldset)   Module2Name, ...
Module3 (fieldset)   Module3Name, ...
```

A migration splits those into child entries carrying the ordinal, which is exactly what
`migrate-cms-to-objects` specifies: *"a repeating group becomes N child entries carrying
the ordinal."* The ordinal becomes `moduleNumber`.

The nine entries that fall out, with their real names:

| Course | # | Module |
| --- | --- | --- |
| Product Design Bootcamp | 1 | Design Fundamentals |
| Product Design Bootcamp | 2 | Research and Strategy |
| Product Design Bootcamp | 3 | User Interface Design |
| Project Manager Certification | 1 | Exploration & Strategy |
| Project Manager Certification | 2 | Agile Product Development |
| Project Manager Certification | 3 | Refining Products |
| Digital Marketing Bootcamp | 1 | Marketing Planning |
| Digital Marketing Bootcamp | 2 | Content Marketing |
| Digital Marketing Bootcamp | 3 | Social Media Marketing |

**So `Module` is not an invention.** It is the one part of the model that could not be
reached by renaming fields, and the one part worth showing live.

## What this does NOT produce

| Missing | Why it cannot be derived |
| --- | --- |
| `Session` | Nothing in Masterclass resembles it |
| `Course -> Teacher` | `teacher.xml` has only Name, Image, Info — no link to a course |
| `Course -> Session` | Follows from Session |
| Real copy | `ProgramDescription` and every `Module*Description` are lorem ipsum |
| A 4th course, a 6th teacher | The source has 3 and 5 |

## Classroom

`classroom.xml` carries `CourseName` plus its own `Module1/2/3`, each with a
**`Module*VideoURL`** that `course.xml` does not have. It is unused in the site, but it is
the only source for a module's video. Decide whether to drop it or to fold `VideoURL` into
`MCModule` before deleting it.

## Field typing

One judgement the source does not settle: `Module*NumberOfLessons` holds `"2 lessons"`,
not `2`. Kept as `Text` here. The hand built model made it `Integer`, which means stripping
the word — a transformation, not a mapping.
