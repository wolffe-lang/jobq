# jobq — v3 (multi-phase, low give-away)

This build is delivered as **phases**, pasted one at a time. Do **only** the current
phase, make its **verification** pass, then stop and wait for the next. Keep earlier
phases working. One directory, one wolf module, one `main`.

---

### PHASE 0 — Setup & spec

First run `cp ../../README.md ./README.md && cp ../../../WOLF-NOTES.md ./WOLF-NOTES.md`,
then read both fully, and `std/fs/fs.lu`'s `create_new`, `move_file`, `entries` docs and
`std/process/process.lu`'s header. Write `main.lu` with README §4's dispatch (`--help`
0; unknown 2) and your file layout as a comment.

**Verify:** `wolf build main.lu -o jobq` warning-free; `./jobq --help; echo $?` → `0`;
`wolf fmt --check *.lu`.

--- END PHASE 0 ---

---

### PHASE 1 — The store (M1; FR-1, FR-2, FR-6)

`init`, the job file format with your own JSON-array argv, `add` with `create_new`
(retry on `exists`), `add -f` with the quoting rule, `ls`, `show`. Tests for the quoting
and the round trip.

**Verify:** A1, A2.

--- END PHASE 1 ---

---

### PHASE 2 — A serial runner (M2; FR-3, FR-12)

`run -j 1`: claim by rename, spawn with captured output to `log/<id>.log`, finish to
`done/` or `failed/` with the exit status; `run` exits 1 when any job failed.

**Verify:** R0, F1 (without `retry` yet).

--- END PHASE 2 ---

---

### PHASE 3 — Concurrency inside one runner, leases, retry, stats (M3)

`-j N`, lease renewal every lease/3, `retry`, `stats`. Tests: two in-process claimers
over a temp directory.

**Verify:** R0 with `-j 4`; S1; `retry --failed` (F1's second half); `wolf test .` green.

--- END PHASE 3 ---

---

### PHASE 4 — Racing runners and lease expiry (M4; FR-4, FR-5, FR-9)

`reclaim_expired` with `tries` and `--max-tries`; the malformed-file skip. `test.sh`
with R1 (four runners, 500 jobs, three repetitions), R2, R3, M1.

**Verify:** R1 (500 files of size 1, three times), R2, R3, M1.

--- END PHASE 4 ---

---

### PHASE 5 — Finish (M5; FR-10, FR-11)

P1 with the listing count; T1 (TERM handling or the named gap with its issue); every row
in `test.sh`.

**Verify:** `./test.sh; echo $?` → `0`; `wolf test .` and `wolf fmt --check *.lu` clean.
Paste the last lines and statuses.

--- END PHASE 5 ---
