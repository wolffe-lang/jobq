# jobq — closeout 2: closeout 1 did its §1 only; §2–§6 are still owed

The judge re-ran your tree from a fresh copy after closeout 1. **§1 is done and right**: with `--lease 2` a second runner
joining a live 6-second job at 3 s found no job and the file holds one byte; a runner killed at 1 s is reclaimed after the
lease (`tries=1`, `status=ok`). **Nothing else in closeout 1 was done**: `test.sh` is the same 154-line file with the same
four rows (R1, R2, R3, M1) and the same loose checks; `main_test.lu` has the same three tests; there is no git repository;
a malformed job file is still claimed into `running/` and stranded; `--dir` on a missing directory still exits 0 with "no
jobs found". You ran the old tests, saw "6 passed", and stopped. That is the failure shape this closeout exists to end.

**The only acceptable end state is: every row named below present in `test.sh` and PASS, `wolf test .` with at least six
tests, `./test.sh; echo exit=$?` → 0, and the four commits.** Do not write "beyond the scope", "pre-existing" or "the
remaining rows"; do not stop after any one section; after each section run `./test.sh | grep -E 'PASS|FAIL|Results'` and
paste it. Work the sections in order, 2 → 3 → 4 → 5 → 6. When a std surface refuses, paste the exact error and stop; nothing
else ends the session before §6's four lines are green.

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
