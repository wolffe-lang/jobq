# jobq — closeout 4: closeout 3's §2–§5 and §7 were not done, and P1 is 219 s against a 60 s bound

The judge ran closeout 3's result from a fresh copy. **What landed:** §1 is real — `process.start` + one `poll` loop, leases
renewed every `lease/3`, up to `-j N` children live; the judge's own renewal test (a 6 s job under `--lease 2`, a second runner
joining at 3 s) now writes ONE byte, one job in `done/` with `tries=0`, the second runner finds nothing. §6 is real (`.gitignore`,
nothing tracked). `test_round_trip` is a real test now. **What did not land, although your summary said "all tests pass":**
- §2: test.sh's R4 is still your kill-and-reclaim row. The pasted R4 (renewal under a LIVE runner, the one row that proves
  the README's claim) is not in test.sh. Nothing in your suite would catch a lease that stops renewing.
- §3: P1 still never compares `ELAPSED` with 60. Your own log says `PASS: P1 (219s)`; the judge measured 218 s. FR-11 says
  under 60 s. The cause: every claim lists the whole queue (`claim_job` → `read_dir` of 10,000 names), so 10,000 claims read
  the directory 10,000 times; `--stats` and its `read_dir calls: N` line do not exist.
- §4: no `jobq: queue/000001-1.job: malformed (line 1)` line anywhere in main.lu (M1 only checks the file stayed).
- §5 half: the header still lists `runner.lu` and `cli.lu`, which do not exist.
- §7: `run_one_job`'s six identical error arms and store.lu's six hand renderers are still there (`fail_job` 0, `render_job` 0).
- 3 commits where the closeout named 5, one per section.
**The only acceptable end:** every section below committed under the named message, `./test.sh` exit 0 with R4 (verbatim)
and P1 (≤ 60 s) green, and a summary that lists each section with its commit sha. Do not write "beyond the scope" or
"pre-existing", and do not summarise before every section is committed.

## 1. R4 verbatim (red first), R5 the old row — commit "Row R4 verbatim; R5 kill-and-reclaim"
Rename the current R4 block to R5 (its echo line and pass/fail names say R5). Then paste this block, unchanged, as R4 above it:
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
DONE=$("$JOBQ" ls --dir "$DIR" --state done | grep -c '^[0-9]')
if [ "$BYTES" = "1" ] && [ "$DONE" = "1" ] && grep -q "tries=0" "$DIR"/done/*; then
    pass "R4"
else
    fail "R4: bytes=$BYTES done=$DONE"
fi
rm -rf "$DIR" "$OUT"
```
Prove it is red by temporarily commenting out the `renew_lease` call, running `./test.sh 2>&1 | grep R4` (FAIL, bytes=2),
and restoring the call. Paste both lines.

## 2. P1 under 60 s, with `--stats` — commit "One listing per sweep; run --stats"
`claim_job` takes the listing from its caller: `cmd_run` lists `queue/` ONCE per sweep (sorted), claims from that list until it
is empty or `-j N` are live, and lists again only when the list is exhausted. Count the listings; `run --stats` prints
`read_dir calls: N` on stderr at the end. P1's `if` becomes `[ "$DONE" -eq 10000 ] && [ "$ELAPSED" -le 60 ]`, and a second
assertion reads N from the stderr line and requires `N ≤ 10000 / 8 + 10`. Paste P1's two lines from `./test.sh`.

## 3. M1's line — commit "Name a malformed job file"
When the runner skips a malformed file it prints `jobq: queue/<name>: malformed (line K)` on stderr, K the first bad line
(README FR-9's form). The M1 row captures the runner's stderr and greps for that exact line as well as the file staying put.

## 4. The header — commit "The header names the files that exist"
main.lu's file list: main.lu, store.lu, main_test.lu, test.sh, nothing else.

## 5. The two duplications — commit "One fail_job, one render_job"
`run_one_job`/`start_one_job`: the six identical error arms become one `fail_job(dir, name, mut log_f, code)` call per arm
(the arm keeps only its code: 127, 126, 130, 1, 1, 1). store.lu: one `fn render_job(job: Job) -> str` used by every writer
(`create_job`'s builder, `update_job`, `finish_job`, `renew_lease`, `retry_job`, the retry-all path). `./test.sh` green after.

## 6. A broader suite — commit "Rows for the rest of the README"
One row each, named as here, each checking stdout/stderr/exit exactly: **L1** `--once` runs one job and exits 0 with one
`done`; **L2** `--max-tries 1` + a runner killed once → `failed/` with `status=lease-expired`; **L3** `retry ID` on one failed job
among two → that one pending with `tries=0`, the other still failed; **L4** `ls --state all` lists pending+running+done+failed
with the state column; **L5** `show ID` of a done job prints the argv JSON and `exit=`; **L6** a job writing to stderr → its
`log/<id>.log` holds both streams in order; **L7** stats on three jobs of known durations (`sleep 0.1/0.2/0.3`) → `mean`
within 50 ms of 200 and `p95` ≤ 300+50; **L8** FR-12: `run` with one failed job exits 1, usage exits 2, `--dir` not a queue
exits 2 — three sub-asserts; **L9** quoting: `add -- sh -c 'printf "%s|%s" "a b" "c"'` → the log holds `a b|c`; **L10** two
runner processes on 200 `true` jobs → every job done once, `done/` has 200 files, no file in `running/`.

## 7. Verify (paste all; stop only when all are green)
`wolf build main.lu -o jobq`; `wolf fmt --check *.lu; echo fmt=$?`; `wolf test .`; `./test.sh; echo "exit=$?"` with R4, P1
(seconds and `read_dir calls`), M1 and L1–L10 named PASS; `git log --oneline | head -8` showing the six commits above.
Then the summary: one line per section with its sha. Then stop.
