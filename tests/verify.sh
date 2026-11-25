#!/bin/sh
# Ground truth for realm-scripture-vocabulary. The vocabulary holds no data: what it must prove is that
# its views answer whatever scriptures are installed beside it, and that every installed child keeps
# the contract the vocabulary states (types/vocabulary.yml). It needs at least one child installed —
# realm-bible, realm-quran, realm-tanakh, realm-book-of-mormon, realm-lds-scriptures — and fails,
# saying so, with none: there would be nothing to verify.
#
#   L1  every view answers BY NAME on its defaults (the model-backed AskScriptures and the two
#       Summarize views are held to SUCCEEDED; the rest to rows wherever the default can have any)
#   L2  the contract, per installed scripture: the holy book's counts equal the verses and chapters
#       that carry its slug; every verse has English text, an ordinal running 1..n, and reaches its
#       holy book by IN; every `name` is unique across all scriptures
#   L3  the views against direct Cypher: Scriptures, SearchScriptures and WordAcrossScriptures per
#       scripture, ReadScriptureChapter on one chapter of each scripture
#
# No producers, so no pushdown or cost check. Keyless.
#
#   APPLIANCE=http://127.0.0.1:11043 AUTH=user:pass sh tests/verify.sh
#
# The last line on success is exactly `ALL CHECKS PASS`; any failure exits non-zero.
# tests/holy-books.live.mjs drives the app in a browser and is run separately.
set -e
AUTHCFG=$(mktemp); trap 'rm -f "$AUTHCFG"' EXIT
if [ -n "${TOKEN:-}" ]; then printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$AUTHCFG"
else printf 'user = "%s"\n' "${AUTH:?set AUTH (user:pass) or TOKEN}" > "$AUTHCFG"; fi
APPLIANCE="${APPLIANCE:-http://127.0.0.1:11043}"
BATTERY_LIB="$(dirname "$0")/lib" APPLIANCE="$APPLIANCE" AUTHCFG="$AUTHCFG" python3 - "$(dirname "$0")/.." <<'PY'
import glob, json, os, subprocess, sys, yaml
base, auth, realm = os.environ["APPLIANCE"], os.environ["AUTHCFG"], sys.argv[1]
fail = 0

def post(path, body):
    out = subprocess.run(["curl", "-s", "--max-time", "900", "-K", auth, "-X", "POST", base + path,
                          "-H", "Content-Type: application/json", "-d", json.dumps(body)],
                         capture_output=True, text=True).stdout
    try:
        return json.loads(out, strict=False)
    except ValueError:
        return {"error": "not JSON: " + out[:200]}
# A figure is only this realm's when the engine says the answer is whole. short() is the battery
# library's (tests/lib, pinned from embabel-worlds/realm-spec): None when whole, else the line that
# stands in for the figure, "REFUSED: <why>" or "PARTIAL <figure>: <the engine's reason>".
import os as _os, sys as _sys
_sys.path.insert(0, _os.environ["BATTERY_LIB"])
from short import short  # noqa: E402
def kg(cypher):
    r = post("/api/v1/admin/kg/execute", {"cypher": cypher})
    if r.get("error"):
        raise SystemExit("  FAIL query REFUSED: %s\n    %s" % (str(r["error"])[:200], cypher))
    # A short count stops the battery as a refusal does: every check after it would read the same gap.
    rows = r.get("rows") or []
    s = short(r, rows[0]["n"] if len(rows) == 1 and "n" in rows[0] else "%d rows" % len(rows))
    if s:
        raise SystemExit("  FAIL query %s\n    %s" % (s, cypher))
    return r.get("rows") or []
def view(name, args=None, whole=True):
    r = post("/api/v1/views/%s/invoke" % name, {"args": args or {}})
    # Rows a view marks short are not its answer, so no check counts them. L1 asks with whole=False
    # because it reports each view's verdict itself and goes on to the next.
    s = whole and short(r, len(r.get("data") or []))
    if s:
        raise SystemExit("  FAIL view %s %s: %s" % (name, json.dumps(args or {}), s))
    return r
def check(what, want, got):
    global fail
    if want == got: print("  ok   %s = %s" % (what, got if len(str(got)) < 80 else str(got)[:77] + "..."))
    else: print("  FAIL %s: expected %s, got %s" % (what, str(want)[:300], str(got)[:300])); fail = 1

holy = {r["s"]: r for r in kg("MATCH (h:HolyBook) RETURN h.scripture AS s, h.chapterCount AS chapters, h.verseCount AS verses")}
if not holy:
    print("  FAIL no scripture is installed beside the vocabulary: nothing to verify")
    print("FAILED"); sys.exit(1)
print("== scriptures installed: %s ==" % ", ".join(sorted(holy)))
# CORRESPONDS_TO is drawn only by a pairing realm beside realm-bible; with neither, the relationship is
# not in the schema at all and a query naming it is refused rather than answered empty.
pairing = post("/api/v1/admin/kg/execute", {"cypher": "MATCH (a:Verse)-[:CORRESPONDS_TO]->(b:Verse) RETURN a.name AS a LIMIT 1"})
paired = not pairing.get("error") and bool(pairing.get("rows"))
docs = kg("MATCH (c:ScriptureChapter) WHERE c.documentUri IS NOT NULL RETURN count(c) AS n")[0]["n"] > 0

print("== L1: every view answers by name ==")
MODEL = {"AskScriptures", "SummarizeAcrossScriptures", "SummarizeMeaningAcrossScriptures"}
CAN_BE_EMPTY = {"ReadScriptureChapter": "bible" not in holy, "SamePassage": not paired,
                "MeaningAcrossScriptures": not docs}
for f in sorted(glob.glob(os.path.join(realm, "views", "*.yml"))):
    for v in yaml.safe_load(open(f)):
        r = view(v["name"], whole=False)
        rows = r.get("data") or []
        if r.get("status") != "SUCCEEDED":
            print("  FAIL %s: %s %s" % (v["name"], r.get("status"), str(r.get("error") or r)[:200])); fail = 1
        elif short(r, len(rows)):
            print("  FAIL %s: %s" % (v["name"], short(r, len(rows)))); fail = 1
        elif not rows and v["name"] not in MODEL and not CAN_BE_EMPTY.get(v["name"]):
            print("  FAIL %s answered no rows on its defaults" % v["name"]); fail = 1
        else:
            print("  ok   %-34s %d rows" % (v["name"], len(rows)))

print("== L2: every installed scripture keeps the contract ==")
for s in sorted(holy):
    got = kg("""MATCH (v:Verse {scripture: '%s'})
                RETURN count(v) AS verses, min(v.ordinal) AS first, max(v.ordinal) AS last,
                       count(DISTINCT v.ordinal) AS ordinals,
                       sum(CASE WHEN v.text IS NULL OR v.text = '' THEN 1 ELSE 0 END) AS noText""" % s)[0]
    n = holy[s]["verses"]
    check("%s: verses = the holy book's verseCount" % s, n, got["verses"])
    check("%s: ordinals run 1..n, once each" % s, [1, n, n], [got["first"], got["last"], got["ordinals"]])
    check("%s: every verse has English text" % s, 0, got["noText"])
    check("%s: chapters = the holy book's chapterCount" % s, holy[s]["chapters"],
          kg("MATCH (c:ScriptureChapter {scripture: '%s'}) RETURN count(c) AS n" % s)[0]["n"])
    check("%s: every verse reaches its holy book by IN" % s, n,
          kg("MATCH (v:Verse {scripture: '%s'})-[:IN*1..3]->(h:HolyBook {scripture: '%s'}) RETURN count(DISTINCT v) AS n" % (s, s))[0]["n"])
u = kg("MATCH (v:Verse) RETURN count(v) AS n, count(DISTINCT v.name) AS names")[0]
check("every verse `name` unique across scriptures", u["n"], u["names"])

print("== L3: the views against direct Cypher ==")
check("Scriptures: one row per holy book", sorted(holy), sorted(r["scripture"] for r in view("Scriptures").get("data") or []))
want = {r["s"]: r["n"] for r in kg("MATCH (v:Verse) WHERE toLower(v.text) CONTAINS 'mercy' RETURN v.scripture AS s, count(v) AS n")}
rows = view("SearchScriptures", {"term": "mercy", "perScripture": 3}).get("data") or []
check("SearchScriptures 'mercy': matches per scripture", want, {r["scripture"]: r["matches"] for r in rows})
check("  ...at most 3 verses each", True, all(sum(1 for r in rows if r["scripture"] == s) <= 3 for s in want))
rows = view("WordAcrossScriptures", {"term": "mercy"}).get("data") or []
check("WordAcrossScriptures 'mercy': verses per scripture", {s: want.get(s, 0) for s in holy}, {r["scripture"]: r["matching"] for r in rows})
for s in sorted(holy):
    c = kg("MATCH (c:ScriptureChapter {scripture: '%s'})<-[:IN]-(v:Verse) WITH c, count(v) AS n "
           "RETURN c.name AS name, n ORDER BY c.name LIMIT 1" % s)[0]
    check("ReadScriptureChapter %r" % c["name"], c["n"], len(view("ReadScriptureChapter", {"chapter": c["name"]}).get("data") or []))

if fail: print("FAILED"); sys.exit(1)
print("ALL CHECKS PASS")
PY
