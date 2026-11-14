#!/usr/bin/env bash
#
# Puts the tests' failures where GitHub shows them without opening the log:
# an annotation on the failing line, which the pull request shows in its
# Files tab, and a table on the run's summary page. It reads the event stream
# Swift Testing wrote and runs nothing itself. The step that ran the tests is
# the one that fails the job for a failing test; this fails only when it can't
# read the events, so that a change in their format is seen, not skipped.
#
# Usage: Scripts/test_report.sh <Swift Testing's event stream, version 6.4> [the test step's log]
#
# The log, when given, is read only for a crash's message, which the events
# don't carry.
#
# Outside GitHub Actions the summary goes to standard output, so a run can be
# read the same way on a Mac:
#
#   swift test --parallel --quiet --event-stream-output-path /tmp/tests.jsonl --event-stream-version 6.4
#   Scripts/test_report.sh /tmp/tests.jsonl
#
# The event stream is pinned to version 6.4: version 6.5 leaves the messages
# out unless asked and moves the source location, which this reads. Moving to
# a newer one means changing ci.yml and this together.

set -euo pipefail

summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# The tests Swift Testing found, then what happened to them. Each failure is
# said short where people look, in the summary's table and the annotation on
# its line: what was expected, and what came instead. When both sides of ==
# are text of several lines, what came instead is the first line that differs,
# as the first line of each is often the same. Swift Testing also lists
# every value it could see, the parts of a regex included; those stay in this
# step's log, folded into a group per failure. GitHub keeps 10 error
# annotations a step, so the first 10 failures are annotated and the summary
# lists them all. Text in an annotation is escaped as GitHub's workflow
# commands want it, and text in a table cell as Markdown wants it.
read -r -d '' program <<'JQ' || true
def data: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
def property: data | gsub(":"; "%3A") | gsub(","; "%2C");
def cell: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub("(?<mark>[\\\\`*_~|\\[\\]])"; "\\\(.mark)") | gsub("\r?\n"; "<br>");
def count($n; $word): "\($n) \($word)\(if $n == 1 then "" else "s" end)";
def cut($n): if length > $n then .[:$n - 1] + "…" else . end;
# Code in a table cell: no Markdown escapes inside, but a | still ends the cell.
def code: gsub("\\|"; "\\|") | if test("`") then "`` \(.) ``" else "`\(.)`" end;
# A value's first line, with "…" when there is more.
def short($n): split("\n") | (.[0] + (if length > 1 then " …" else "" end)) | cut($n);
# "x → 2": what was evaluated, and what it came to.
def parts: capture("^(?<expression>[\\s\\S]*?) → (?<value>[\\s\\S]*)$");
# A string's lines, from the way Swift Testing quotes it; null for anything else.
def text_lines: if test("^\"[\\s\\S]*\"$") then .[1:-1] | split("\n") else null end;

# A run that was killed can leave half a line behind: lines that don't parse are skipped.
[inputs | fromjson?] as $records
| [$records[] | select(.kind == "test") | .payload] as $tests
| [$records[] | select(.kind == "event") | .payload] as $events
| ($tests | INDEX(.id)) as $byID
| [$tests[] | select(.kind == "suite")] as $suites
# "Suite › Test", with every suite the test is in.
| def named($id):
    $byID[$id // ""] as $test
    | if $test == null then "Outside any test" else
        [$suites[] | select(.id as $suite | $id | startswith($suite + "/"))]
        | sort_by(.id | length) | map(.displayName // .name)
        | . + [$test.displayName // $test.name] | join(" › ")
      end;
  def functions($kind): [$events[] | select(.kind == $kind) | .testID | select($byID[.].kind == "function")];
  [$events[] | select(.kind == "issueRecorded" and (.issue.isKnown | not))
    | (.issue.sourceLocation // {}) as $at
    | { level: (if .issue.severity == "warning" then "warning" else "error" end),
        id: .testID, test: named(.testID),
        path: (($at.filePath // "") | ltrimstr($root)), line: ($at.line // 1), column: ($at.column // 1),
        message: ([.messages[]?.text] | join("\n")) }
      # "Expectation failed: x == 1", then any comment above it, x == 1 → false,
      # x → 2 and the parts of x: the expectation, and the first value that
      # isn't the expectation again. Issue.record("…") says "Issue recorded",
      # then its words.
      + ([.messages[]?.text] as $texts
        | ($texts[0] // "" | split("\n")[0]) as $headline
        | ($headline | ltrimstr("Expectation failed: ")) as $expected
        | ($texts[0] // "" | ltrimstr("Expectation failed: ")) as $whole
        | [$texts[1:][] | select(parts | .expression != $whole or (.value != "false" and .value != "true"))] as $values
        | { headline: (if $headline == "Issue recorded" and $texts[1] then $texts[1] else $headline end),
            expected: (if $headline | startswith("Expectation failed: ") then $expected else null end),
            got: $values[0],
            # Text of several lines on both sides of ==: the first line that
            # differs says more than the first line of each.
            differs: (first($values | map(parts) | select(length == 2) as [$got, $want]
              | ($got.value | text_lines) as $a | ($want.value | text_lines) as $b
              | select($a and $b and ($a + $b | length) > 2
                and $whole == "\($got.expression) == \($want.expression)")
              | first(range([$a, $b | length] | max) | select($a[.] != $b[.])
                | {line: (. + 1), got: $a[.], expected: $b[.]})) // null) })] as $issues
# The same failure again, as from a parameterized test's cases, is one row
# that says how many times.
| def once: group_by([.id, .path, .line, .column, .message]) | map(.[0] + {times: length});
  [$issues[] | select(.level == "error")] as $failures
| ([$failures[].id] | unique | length) as $failed
| functions("testEnded") as $ended
| (functions("testStarted") - $ended | unique) as $unfinished
| ([$events[] | select(.kind == "testSkipped")] | length) as $skipped
| (reduce $events[] as $event ({seconds: 0};
    if $event.kind == "runStarted" then .start = $event.instant.absolute
    elif $event.kind == "runEnded" and .start then .seconds += $event.instant.absolute - .start | .start = null
    else . end)) as $clock
# A run that started and never ended was killed, or crashed.
| ($clock.start != null) as $stopped
# Nothing in the events says which test crashed. Run in parallel, many were
# still running, so they are named only when there are few; the Test step's
# log has the crash's message.
| ((if $unfinished == [] then ["No test was running when they stopped."]
   elif ($unfinished | length) <= 5 then ["Still running when they stopped:"] + ($unfinished | map(named(.)))
   else ["\($unfinished | length) tests were still running, in parallel, so which one crashed isn't known."] end)
  + (if $crash == "" then [] else ["The crash: \($crash)"] end)) as $left
# What failed, short: for a table cell, and for the annotation, which has room
# for a few lines of the value.
| def line(f): if . == null then "nothing" else @json | f end;
  def said:
    if .expected then
      "**Expected** \(.expected | short(140) | code)"
      + if .differs then
          "<br>**Got** line \(.differs.line): \(.differs.got | line(cut(120) | code))"
          + "<br>**Instead of** \(.differs.expected | line(cut(120) | code))"
        elif .got then "<br>**Got** \(.got | short(120) | code)"
        else "" end
    else .headline | short(160) | cell end;
  def times: if .times > 1 then " (\(.times) times)" else "" end;
  def note:
    if .expected then
      "Expected \(.expected | cut(300))"
      + if .differs then
          "\nGot line \(.differs.line): \(.differs.got | line(cut(300)))\ninstead of: \(.differs.expected | line(cut(300)))"
        elif .got then "\nGot \(.got | split("\n")[:8] | join("\n") | cut(600))"
        else "" end
    else .headline end;
  if $out == "annotations" then
    ($issues[] | "::group::\(.test) (\(.path):\(.line):\(.column))", .message, "::endgroup::"),
    ($failures | once) as $rows
    | ($rows[:10][], ($issues[] | select(.level == "warning") | . + {times: 1})
      | "::\(.level) file=\(.path | property),line=\(.line),col=\(.column),title=\(.test + times | property)::\(note | data)"),
    (select(($rows | length) > 10)
      | "::notice title=More failures::\(($rows | length) - 10) more are in the job's summary"),
    (select($stopped)
      | "::error title=The tests stopped before they finished::\($left | join("\n") | data)")
  else
    (if $failed > 0 then "### \($failed) of \(count($ended | length; "test")) failed"
     elif $stopped then "### The tests stopped before they finished"
     else "### \(count($ended | length; "test")) passed in \($clock.seconds * 10 | round / 10) seconds" end)
    + (if $skipped > 0 then ", \($skipped) skipped" else "" end),
    (select(($failures | length) > 0)
      | "", "| Test | Where | What failed |", "|---|---|---|",
        ($failures | once[]
          | (.path | split("/") | map(@uri) | join("/")) as $link
          | "| \(.test + times | cell) | [\(.path | split("/") | last):\(.line)](\($blob)\($link)#L\(.line)) | \(said) |")),
    (select($stopped)
      | "", "**The tests stopped before they finished.** \($left[0] | cell)", "", ($left[1:][] | "- \(cell)"))
  end
JQ

file="${1:-}" log="${2:-}"
[[ -n "$file" ]] || { echo "test_report.sh: the event stream to read" >&2; exit 2; }
# A crash's message, as Swift prints it: "Fatal error: Index out of range".
crash="$( { [[ -n "$log" && -s "$log" ]] && grep -m 1 'Fatal error: ' "$log"; } || true)"
# Nothing to read: the build failed first, and that is the failure to show.
[[ -s "$file" ]] || { echo "test_report.sh: no test results at $file"; exit 0; }

# Every record says which version of the format it is in.
version="$(jq -Rrn '[inputs | fromjson? | .version // "none"] | unique | join(", ")' "$file")"
if [[ ! "$version" =~ ^6\.4(\.[0-9]+)?$ ]]; then
  echo "::error title=The test report can't read this run::Swift Testing wrote version $version, and test_report.sh reads 6.4. Update the version in ci.yml and the script together."
  exit 1
fi

blob="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/blob/${GITHUB_SHA:-}/"
arguments=(-Rrn --arg root "${GITHUB_WORKSPACE:-$PWD}/" --arg blob "$blob" --arg crash "$crash")
jq "${arguments[@]}" --arg out annotations "$program" "$file"
jq "${arguments[@]}" --arg out summary "$program" "$file" >> "$summary"
