# jobq — closeout 1: the lease is never renewed, and the rows that would have seen it

The judge ran your v3 from a fresh copy. It builds, `wolf fmt --check` is clean, your `test.sh` passes 6/6, and A1, A2,
R0, F1, S1 behave; 2,000 `true` jobs ran in 10 s at `-j 8`. **But the README's core claim fails:** with `--lease 2`, a
runner on a 6-second job (`sh -c 'printf x >> out; sleep 6'`) was robbed at 3 s by a second runner that joined — the job
ran twice (two bytes in `out`), because `store.renew_lease` exists and nothing ever calls it (`grep -c "renew_lease("
main.lu` → 0). FR-3 says "leases renewed while running"; FR-4's exactly-once holds only for jobs shorter than the lease.
Your rows could not see this: R2 passes on "done OR failed", R3 on "failed ≥ 1" without `status=lease-expired`, M1
without the message, and `test.sh` carries 4 of the README's 11 rows while your summary said "All 6 rows pass" (6 = R1 three
times). **The only acceptable end is every row below green and `./test.sh` at 0.** Do not write "beyond the scope" or
"pre-existing"; if a std surface refuses, paste the exact error and the line of `process.lu` you read, then stop.

## 1. Renewal (the fix; `wolf build main.lu -o jobq` after each edit)
The runner uses `process.run(cmd)`, which blocks until the child ends. Replace it with `process.start(cmd)` (a `Child`) and
a loop: every `lease/3` seconds (`time.sleep` on a Duration), call `renew_lease(dir, name, now + lease_ms)` for the job, then
`process.poll()` (read its doc at process.lu:957–975: `changed`, `child`, `status`, `live`); when the poll says the child
ended, take its status with `wait_status` and finish the job as today. With `-j N`, keep one renewal loop over every
running child (one `poll` serves all). Unit test: a lease of 1 s on a job `sleep 3`; read the job file's `lease=` at 0.5 s
and at 2 s — the second is later than the first.

## 2. Row R4 (renewal under a live runner) in `test.sh`
`--lease 2`; one job `sh -c 'printf x >> OUT; sleep 6'`; runner A started; after 3 s runner B started and waited; expect
`OUT` is exactly one byte and `ls --state done` shows one job with `tries=0`. Red before §1, green after; keep it.

## 3. The loose rows, tightened
R2: the reclaimed job ends `done` with `tries=1` in its file, exactly one job in `done/`. R3: the file in `failed/` holds
`status=lease-expired`. M1: the runner prints `jobq: queue/000001-1.job: malformed (line 1)` (README FR-9's form), leaves the
file where it was (today it is claimed into `running/` and stranded there: parse BEFORE the rename, or rename it back on a
parse error), and the valid job runs.

## 4. The missing rows in `test.sh`
A1, A2 (five quoted lines → ids 2–6; `show 3` prints the argv JSON), R0 (`-j 2`, six done, logs hold the output, exit 0),
F1 (`sh -c 'exit 3'` → `failed/`, `exit=3`, run exits 1; `retry --failed` → pending with `tries=0`), S1 (`stats` prints the
four counts and `mean`/`p95`), P1 (10,000 `true` jobs at `-j 8` under 60 s, wall time printed; a `--stats` flag on `run`
prints `read_dir calls: N` and the row asserts N ≤ jobs / 8 + 10), T1 (TERM: the gap as documented in main.lu's header, plus a
row: TERM a runner mid-job, start a second runner after the lease, the job completes once). FR-12: `--dir` naming a
directory without the layout → `jobq: DIR: not a queue` exit 2 (today: "no jobs found", exit 0) — a row.

## 5. Unit tests the phases asked for and you did not write
`test_quoting`: the five `-f` lines split as A2 shows (`"a b"`, `'x y'`, a bare `%s\n`); `test_round_trip`: write a job
file, read it back, every field equal. `test_claim_exclusivity` claims alternately today — make the two claimers race
through the real `claim_job` on the same list of names in interleaved order and still assert no duplicate and all claimed.

## 6. Verify (paste all four; stop only when all are green)
`wolf build main.lu -o jobq`; `wolf fmt --check *.lu; echo fmt=$?`; `wolf test .` (6 or more passed); `./test.sh; echo
"exit=$?"` with every row named PASS. Commit each section as it lands (`git init` the directory first if it has no repo:
"Renew the lease while a job runs", "Rows R4, R2, R3, M1 tightened", "The README's remaining rows", "Unit tests: quoting,
round trip, racing claimers"). Then stop.
