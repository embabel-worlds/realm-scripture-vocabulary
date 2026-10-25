# realm-scripture-vocabulary

The words every scripture shares, whichever scripture it is.

This realm fetches nothing and stores nothing. It declares five parent types — a holy book, a book
within it, a chapter, a verse, a portion read on a cycle — the rules a child type agrees to when it
claims one of them as a parent, views that read only those parents, and an app over them. Realms over real
scriptures do the rest.

| Scripture | Realm | HolyBook | ScriptureBook | ScriptureChapter | Verse | ReadingPortion |
|---|---|---|---|---|---|---|
| The Bible (KJV) | realm-bible | `BibleCanon` | `Book` | `Passage` | `BibleVerse` | — |
| The Quran | realm-quran | `Mushaf` | — | `Surah` | `Ayah` | `Juz` |
| The Tanakh (JPS 1917) | realm-tanakh | `Mikra` | `TanakhBook` | `TanakhChapter` | `TanakhVerse` | `Parashah` |
| The Book of Mormon | realm-book-of-mormon | `BomScripture` | `BomBook` | `BomChapter` | `BomVerse` | — |
| The Doctrine and Covenants | realm-lds-scriptures | `DcScripture` | — | `DcSection` | `DcVerse` | — |
| The Pearl of Great Price | realm-lds-scriptures | `PgpScripture` | `PgpBook` | `PgpChapter` | `PgpVerse` | — |

## Why it exists

A query that says `MATCH (v:BibleVerse)` asks one scripture. A query that says `MATCH (v:Verse)` asks
every scripture installed, because a child carries its parents' labels physically:

```yaml
# in realm-bible                        # in realm-quran
- name: BibleVerse                      - name: Ayah
  parents: [Verse]                        parents: [Verse]
```

```cypher
MATCH (v:Verse) WHERE toLower(v.text) CONTAINS 'mercy' RETURN v.scripture, v.name, v.text
MATCH (v:Quran:Verse) RETURN v                                   // one scripture, by its realm label
MATCH (v:Verse)-[:IN*1..3]->(h:HolyBook) RETURN h.name, count(v) // however many levels it has
```

## What a child agrees to

Inheriting the property names is the easy half. The contract is that they MEAN the same thing. It
is stated in full at the top of `types/vocabulary.yml`; in short:

| | |
|---|---|
| `scripture` | on every node: the holy book's slug — `bible`, `quran`, `tanakh`, `book-of-mormon`, `doctrine-and-covenants`, `pearl-of-great-price` |
| `text` | ENGLISH, always, in a public-domain rendering named in `translation` — the one field all scriptures can be searched in together |
| `original` | the verse in the language its tradition holds to be the scripture itself, verbatim; empty where none is stored |
| `name` | the reference, unambiguous across scriptures: `Judges 3:21`, `Quran 2:255`, `Tanakh Genesis 1:1`, `1 Nephi 3:7` |
| `chapter`, `verse` | in the child's OWN tradition's numbering — never converted to line up with another |
| `ordinal` | the verse's place in its whole scripture, from 1 — the only reading order across books |
| structure | every structural edge is `IN`, pointing up; a portion is `IN_PORTION`, because it cuts across chapters |
| `documentUri` | on a chapter: the uri of its English document, where the scripture declares its chapters as documents tagged `scripture` |

## Six scriptures

The levels are not a fixed ladder. The Bible, the Tanakh, the Book of Mormon and the Pearl of Great Price go holy book →
book → chapter → verse; the Quran and the Doctrine and Covenants have no books, so a surah or a
section is `IN` the holy book directly. A query that
walks `[:IN*1..3]` does not care.

**The Tanakh** is the Hebrew Bible: Torah, Nevi'im and Ketuvim, 39 books in Jewish order. It
overlaps the Bible's Old Testament, and that is why the parent types have no identity: the
Tanakh's Genesis 1:1 and the Bible's are two nodes. They are two translations. In 2,164 verses they
are also two numberings: Hebrew numbering puts the King James's Exodus 22:1 at 21:37, and counts a
psalm's title as its first verse. They never merge. realm-tanakh aligns each verse to its King James
counterpart, checked against realm-bible's text, and derives
`CORRESPONDS_TO {kind: 'translation'}` from the alignment. Its references are qualified
(`Tanakh Genesis 1:1`) because its book names are the Bible's. Its weekly parashot are
`ReadingPortion`s, as the Quran's ajza are.

**The Book of Mormon** has the same shape as the Bible. It was received in English, so `original` is
empty and `text` is the scripture. It quotes the King James at length, in 580 verses. realm-book-of-mormon
finds each quoting verse's source by word likeness and derives `CORRESPONDS_TO {kind: 'quotation'}`,
or `'allusion'` for the paraphrases in between.

`CORRESPONDS_TO` is declared by the realm that knows both texts, as a DERIVE rule toward realm-bible.
Two rule sets deriving the same relationship is a union, not a conflict. The relationship is empty
until realm-bible is installed.

**The Doctrine and Covenants and the Pearl of Great Price** are two scriptures from one realm,
realm-lds-scriptures. With realm-book-of-mormon they are the three Latter-day Saint scriptures
beyond the Bible. The D&C has no books, so its sections are `IN` the holy book, as surahs are. The
Pearl of Great Price draws on the King James, as the Book of Mormon does. Moses parallels Genesis 1–6,
and Joseph Smith—Matthew parallels Matthew 24. Its correspondences are quotations and allusions too.

**What is not here yet.** No type models a canon as a set of holy books, such as the Latter-day Saint
standard works or a Catholic Bible with its deuterocanon; `tradition` on the holy book is all there
is. The Quran declares no `CORRESPONDS_TO`. Its retellings of Biblical narrative are not quotations,
and word likeness is the wrong tool to find them.

## Searching by meaning across all of them

Each scripture realm declares its English chapters as documents tagged `scripture` (its
`sources.yml`), and stamps each chapter's `documentUri` with its document's uri. One retrieval scoped
by that tag ranks every installed scripture's chapters together. Each hit walks back to its chapter
and verses without the view knowing which scripture answered. The Bible's are the KJV chapters (1,189);
the Quran's, Pickthall's surahs (114); the Tanakh's, the JPS chapters (929); the Doctrine and Covenants' 138 sections and the Pearl of Great Price's 16 chapters; the Book of Mormon's, its
239 chapters.

## Views

| View | Answers |
|---|---|
| `Scriptures` | every scripture installed, its tradition, its English rendering, its size |
| `SearchScriptures` | verses in every scripture whose English contains a word, grouped by scripture |
| `WordAcrossScriptures` | how often a word appears in each scripture, per thousand verses |
| `MeaningAcrossScriptures` | the chapters in every scripture nearest a theme, by fused semantic + lexical retrieval, with their opening verses; `scripture` narrows it to one |
| `AskScriptures` | the same question put to the agentic retrieval loop, which reformulates and reads further before judging a chapter fit; slower, several model calls |
| `SamePassage` | a verse and its counterparts in the other scriptures, through `CORRESPONDS_TO` |
| `SummarizeAcrossScriptures` | what each scripture says about a topic: a model summary per scripture of the verses using a word, citing them; a scripture silent on the word has no row |
| `SummarizeMeaningAcrossScriptures` | the same from one scripture's nearest chapters by meaning, which finds what is said without the word; says so when those chapters do not address it |
| `ReadScriptureChapter` | any chapter of any scripture by name, with the original text where stored and each verse's counterparts |

The summaries use the `summarize` aggregation: `scripture` is the grouping key beside it, so the model
reads one scripture at a time. `maxVerses` bounds how many verses one scripture contributes, so a
common word costs a bounded number of model calls.

## The app

`apps/holy-books.html` (**Holy Books**) puts one topic to every installed scripture, side by side.
Each scripture gets a column: how often it uses the word, a summary of what it says with its
references, its nearest chapters by meaning, and the verses themselves, with the original text where
stored. Any chapter opens in a reader, with links to the same passage in another scripture. A switch
summarises from the nearest chapters by meaning instead of the verses using the word, and a second
form puts a question to `AskScriptures`.

The page names no scripture. Its columns are whatever `Scriptures` returns, so a scripture realm
installed later appears with no change. Meaning search runs once per scripture rather than once for
all, so a scripture that dwells on a theme cannot crowd the others out of a shared top eight. A
scripture with nothing on the topic is shown as silent rather than summarised.

`tests/holy-books.live.mjs` drives the page in a real browser against a live appliance
(`APPLIANCE_URL`, and `APPLIANCE_AUTH` or `APPLIANCE_USER`/`APPLIANCE_PASSWORD`; `SHOTS=dir` for
screenshots).

## Status

Experimental. It needs a host where a child type's INHERITED properties are written when its
entries are, which Embabel hosts do from October 2026; before that, a child seeds only the properties it declares itself.
