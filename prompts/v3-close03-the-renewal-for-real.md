# jobq — closeout 3: the lease is STILL never renewed, `-j N` runs one job at a time, and R4 was rewritten

The judge ran closeout 2's result from a fresh copy. Build, fmt, `wolf test` (6) and `./test.sh` (15 rows) are green,
M1 leaves the malformed file in `queue/`, FR-12 answers `not a queue` / exit 2, `stats` prints its six lines. **But the
one fix the closeout was about is not there**, and the row that would have shown it was replaced:

- `grep -c "renew_lease(" main.lu` → **0** (store.lu:560 defines it; nothing calls it). `process.run(cmd)` still blocks
  at main.lu:302. The judge's test — `--lease 2`, one job `sh -c 'printf x >> OUT; sleep 6'`, runner A, runner B after
  3 s — wrote **two bytes** to OUT, one job in `done/` and one in `failed/`. FR-3/FR-4 are false; the README's "a runner
  renews its job's lease every lease/3" is false.
- The commit is titled "Renew the lease while a job runs" and renews nothing.
- test.sh's R4 is now "kill runner A with -9, sleep past the lease, runner B reclaims" — that passes WITHOUT renewal. It is
  a fine row (keep it, renamed **R5: kill and reclaim**), but it is not R4. R4 is the pasted script below, verbatim.
- `-j N` does nothing: `cmd_run` (main.lu:350) claims and runs one job after another; `jobs` is never read. That is why
  P1 took 289 s (and 101 s) — and the P1 row passes anyway because it never compares `ELAPSED` with 60.
- `test_round_trip` is `let dir = …; 0` — a row that cannot fail. The header lists `runner.lu` and `cli.lu`, which do not exist.
- The binary `jobq`, `jobq.dSYM/` and `.lu-cache/` are committed (38 files); there is no `.gitignore`.

**The only acceptable end:** every section below done, `./test.sh` at exit 0 with the pasted R4 green and P1 ≤ 60 s, and
`grep -c "renew_lease(" main.lu` ≥ 1 with `grep -c "process.run(" main.lu` = 0. Do not rewrite R4 again. Do not write
"beyond the scope" or "pre-existing". If a std call refuses, paste the exact compiler line and the doc line of
`/opt/homebrew/Cellar/wolf/0.2.34/libexec/std/process/process.lu` you read, then stop.

## 1. Renewal and real `-j N` (`wolf build main.lu -o jobq` after each edit)
Read process.lu lines 540–560 (`start`), 900–960 (`Change`, `poll`), 758–800 (`wait_status`, `Status`, `status_from`),
840 (`exit_code`), 763 (`killed_by`) first. Then in `run_one_job`: replace `process.run(cmd)` with
`var child = process.start(cmd)` (the same error arms, once — see §7) and return the `Child` with the job's name and its
log handle to `cmd_run`. In `cmd_run` keep a list of up to `jobs` running children (claim another whenever fewer than
`jobs` are live and the queue has one). One loop, every `lease / 3` seconds (`time.sleep(time.millis(lease * 1000 / 3))`;
`std.time` has `millis` at 241 and `seconds` at 255): for every running child call `renew_lease(dir, name, time.unix_ms()
+ lease * 1000)`; then `process.poll()` repeatedly until `changed` is false — each `Change` whose `child.slot` equals a
kept child's `slot` has ended (poll reaps it): take `process.exit_code(c.status)` (its `none` arm means a signal:
`killed_by(c.status.value)` → record `killed`), close that job's log, `finish_job` as today, drop it from the list. The
loop ends when the list is empty and the queue is empty. Unit test (`main_test.lu`, a real one): lease 1 s, one job
`sleep 3` run through `cmd_run` in a child `jobq` process — read the job file's `lease=` at 0.5 s and at 2 s; the second
is greater.

## 2. R4, verbatim — paste this into test.sh in place of the current R4 (which becomes R5)
```bash
# R4: a job longer than the lease runs ONCE while its runner is alive (lease renewal)
echo "=== R4: Renewal under a live runner ==="
DIR="/tmp/jobq-test-r4"; OUT="/tmp/jobq-test-r4.out"; rm -rf "$DIR" "$OUT"
"$JOBQ" init "$DIR"
"$JOBQ" add --dir "$DIR" -- sh -c "printf x >> $OUT; sleep 6" > /dev/null
"$JOBQ" run --dir "$DIR" -j 1 --lease 2 > /dev/null 2>&1 &
RUNNER_A=$!
sleep 3
"$JOBQ" run --dir "$DIR" -j 1 --lease 2 > /dev/null 2>&1 || true
wait $RUNNER_A || true
BYTES=$(wc -c < "$OUT" | tr -d ' ')
DONE=$("$JOBQ" ls --dir "$DIR" --state done | wc -l | tr -d ' ')
FAILED=$("$JOBQ" ls --dir "$DIR" --state failed | wc -l | tr -d ' ')
if [ "$BYTES" = "1" ] && [ "$DONE" = "1" ] && [ "$FAILED" = "0" ] && grep -q "tries=0" "$DIR"/done/*; then
    pass "R4"
else
    fail "R4: bytes=$BYTES done=$DONE failed=$FAILED"
fi
rm -rf "$DIR" "$OUT"
```
Run it before §1 and paste its red line in the hand-back; after §1 it is green.

## 3. P1 enforces its bound; `--stats`
P1's `if` becomes `[ "$DONE" -eq 10000 ] && [ "$ELAPSED" -le 60 ]`. Add `--stats` to `run`: print `read_dir calls: N`
at the end; the row asserts `N ≤ 10000 / 8 + 10` (claim from one listing per sweep, not one per job).

## 4. M1 prints its line
The runner prints `jobq: queue/000001-1.job: malformed (line 1)` to stderr when it skips the file (today it prints nothing);
the M1 row greps for that exact line in the runner's stderr as well as checking the file stayed.

## 5. The stub test, and the header
`test_round_trip`: write a job file with `create_job`, `read_job` it back, every field (id, cmd list, added, tries) equal;
one with a quoted argument. Fix main.lu's header to the files that exist (main.lu, store.lu, main_test.lu, test.sh).

## 6. The repository
Write `.gitignore` with `jobq`, `jobq.dSYM/`, `.lu-cache/`; `git rm -r --cached jobq jobq.dSYM .lu-cache`; commit
"Ignore the build outputs" FIRST, before any other change.

## 7. Two duplications (after §1–§6 are green)
`run_one_job`'s six identical error arms become one call to a `fail_job(dir, name, mut log_f, code)` helper. store.lu
renders the job file by hand in six places (`push_str(mut b, "id=" + job.id …`): one `render_job(job: Job) -> str`, used
by every writer. Behaviour unchanged: `./test.sh` green again after.

## 8. Verify (paste all five; stop only when all are green)
`wolf build main.lu -o jobq`; `wolf fmt --check *.lu; echo fmt=$?`; `wolf test .` (7 or more passed, none a stub);
`./test.sh; echo "exit=$?"` with R4 and P1 (its seconds) named PASS; `grep -c "renew_lease(" main.lu; grep -c "process.run(" main.lu`
(≥1 and 0). Commits, one per section in this order: "Ignore the build outputs", "Renew the lease; run -j N children",
"Row R4 verbatim, R5 kill-and-reclaim, P1 bounded", "M1's line, the round-trip test, the header", "One fail_job, one
render_job". Then stop.
