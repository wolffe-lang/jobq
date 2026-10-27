# jobq

**A durable job queue in a directory, in wolf: add commands, run them with N concurrent runners (several runner processes may share one queue), each job claimed exactly once, its status, timing and output recorded, with leases so a dead runner's job is retried — proven by racing runners and counting side effects.**

---

## 1. What & why

Every shop has a pile of commands to run: re-encode these files, rebuild these packages,
hit these URLs. A queue in a directory needs no server: `jobq add -- cmd args` drops a
file, `jobq run -j 4` works through them, and a second `jobq run` on another terminal
(or another machine over NFS, with care) joins in. The hard part is *exactly once*: two
runners must never run the same job, a runner killed mid-job must not lose it forever,
and a job that crashes must be recorded as such, not silently requeued.

The correctness claim is testable: with four runners racing over 500 jobs whose
side effect is a file write, exactly 500 files appear, each exactly once; kill a runner
mid-job and the job runs again after its lease expires, once.

### What this exercises

Atomic file-system primitives (`create_new` as a lock, rename as a commit), process
spawning with captured output, leases and clock reads, a small on-disk schema, a status
listing, and a racing test that must be deterministic in its outcome while
nondeterministic in its interleaving.

---

## 2. Background & core concepts

- **The queue** is a directory: `queue/` (pending jobs, one file each), `running/`
  (claimed), `done/`, `failed/`, `log/` (each job's stdout+stderr), `jobq.lock` is not
  used (no global lock).
- **A job file** `NNNNNN-<id>.job` holds lines `id=`, `cmd=` (the argv as a JSON array,
  your own emitter/parser), `added=` (unix ms), `tries=`, and after claiming `runner=`,
  `lease=` (unix ms until which the claim is valid), after completion `status=`,
  `started=`, `ended=`, `exit=`.
- **Claiming:** a runner lists `queue/` sorted, and for each candidate attempts
  `rename(queue/X, running/X)`; the rename is atomic within a filesystem and succeeds for
  exactly one runner (the loser gets `not_found`). The winner rewrites the file with its
  `runner=` and `lease=`. (Rename is the claim; `create_new` guards the id at `add` time.)
- **Leases:** a runner renews its job's lease every `lease/3` while the command runs. A
  runner scanning `running/` may reclaim a job whose lease is in the past (the owner
  died): it renames `running/X` to `queue/X` with `tries` incremented, and the job is
  retried up to `--max-tries` (default 3), after which it goes to `failed/` with
  `status=lease-expired`.
- **Completion:** when the command ends, the runner writes `status=ok|failed`, `exit=`,
  `ended=` and renames the file to `done/` or `failed/`. Output goes to `log/<id>.log`.
- **Ids:** `jobq add` takes the next sequence number from the highest existing file plus
  one, and creates the job with `create_new` (the `exists` row means another `add` won
  the number: retry with the next). The file name's sequence gives FIFO order.

---

## 3. Functional requirements (numbered, testable)

- **FR-1** `jobq init DIR` creates the layout; every command takes `--dir DIR` (default
  `./jobq`).
- **FR-2** `jobq add [--dir D] -- CMD ARGS...` creates one pending job and prints its id.
  `jobq add -f FILE` adds one job per line of FILE (each line split by a shell-free rule:
  whitespace, with single and double quotes honored).
- **FR-3** `jobq run [--dir D] [-j N] [--lease SECONDS] [--max-tries N] [--once]` claims
  and runs jobs with N workers until the queue is empty (then exits 0) or forever with
  `--follow`; each job runs through `std.process` with its stdout and stderr captured
  to `log/<id>.log`; the exit status recorded; leases renewed while running.
- **FR-4** Exactly-once: two or more concurrent `jobq run` processes on one directory
  never run the same job twice while its lease holds (§7 row R1).
- **FR-5** Lease expiry: a job whose runner died is requeued after its lease and runs
  again; `tries` counts; after `--max-tries` it fails with `lease-expired` (R2, R3).
- **FR-6** `jobq ls [--dir D] [--state pending|running|done|failed|all]` prints one line
  per job: `ID STATE TRIES EXIT STARTED ENDED CMD`, sorted by id; `jobq show ID` prints
  the job file and the log.
- **FR-7** `jobq retry ID|--failed` moves failed jobs back to pending with `tries` reset.
- **FR-8** `jobq stats` prints counts per state and the mean and p95 of (ended − started)
  over done jobs.
- **FR-9** A job file that is unreadable or malformed is reported and skipped (`jobq:
  queue/X: malformed (line N)`), never crashes a runner.
- **FR-10** Signals: a runner that receives TERM finishes its current jobs' bookkeeping
  (writes `status=killed`, exit absent, moves to `failed/`) if the std's signal surface
  allows catching TERM; if it does not at this pin, document it and rely on the lease
  (name the gap, WOLF-NOTES rule 10).
- **FR-11** 10,000 trivial jobs (`true`) run through `-j 8` in under 60 s on this Mac;
  the queue directory holds 10,000 files without pathological listing cost (the runner
  lists once per claim round, not once per job).
- **FR-12** Exit: 0 / 1 (a `run` that saw any job fail) / 2 usage or a broken queue dir.

---

## 4. Interface / CLI spec

```
jobq init DIR
jobq add [--dir D] -- CMD ARGS...   |   jobq add [--dir D] -f FILE
jobq run [--dir D] [-j N] [--lease S] [--max-tries N] [--follow]
jobq ls [--dir D] [--state S]   |   jobq show [--dir D] ID
jobq retry [--dir D] ID|--failed   |   jobq stats [--dir D]
jobq --help
```

---

## 5. Architecture guidance (described, not prescribed)

- `store.lu` — the layout, job file read/write (your own `key=value` lines plus a JSON
  array for `cmd`), `next_id` with `create_new`, `claim` by rename, `release`, `finish`.
- `runner.lu` — the worker loop: claim round, spawn via `std.process` (`command`,
  `push_arg`, `set_stdout`/`set_stderr` to a `fs.create` of the log; read
  `process.lu`'s header for the fd API), lease renewal (a renewal task or a check
  between `poll`s), the state transitions.
- `cli.lu`, `main.lu`, `*_test.lu` (the quoting rule for `-f`, the job file round trip,
  the claim semantics on a temp dir with two in-process claimers).
- The clock is `std.time.unix_ms`. Concurrency inside one runner: N tasks over a
  channel if the pin supports it for your shapes (wolf-lang#845: channels refuse List
  payloads; pass ids as ints), else a serial claim loop with N spawned children polled
  with `process.poll()`.

---

## 6. Build

```
wolf build main.lu -o jobq
wolf test .
./test.sh        # the rows, with racing runners; exit 0 on pass
wolf fmt --check *.lu
```

---

## 7. Testing & acceptance

### 7.1 Rows

| row | check |
|---|---|
| A1 | `jobq init q; jobq add --dir q -- printf hello` → `1`; `ls q/queue` has one file; `jobq ls --dir q` shows it pending |
| A2 | `jobq add -f jobs.txt` with 5 quoted lines → ids 2–6; `jobq show 3` prints the parsed argv as JSON |
| R0 | `jobq run --dir q -j 2` → all done, logs hold the outputs, `ls --state done` lists 6, exit 0 |
| R1 | **Exactly once:** 500 jobs each `sh -c 'echo $$ >> out/$ID'`… simpler: each job `touch out/<id>` then `printf x >> out/<id>`; start four `jobq run -j 4` processes at once; when all exit: 500 files, each containing exactly one `x` (the test checks every file's size is 1) |
| R2 | **Lease expiry:** `--lease 2`; a job `sleep 30`; start a runner, kill -9 it after 1 s; start another runner: after ≥ 2 s it reclaims the job (`tries=2`) and runs it; `ls` shows one job done, tries 2, and the log of the first attempt is kept as `log/<id>.1.log` |
| R3 | with `--max-tries 2` and a runner killed twice, the job ends in `failed/` with `status=lease-expired` |
| F1 | a job `sh -c 'exit 3'` → `failed/`, `exit=3`, `run` exits 1; `jobq retry --failed` moves it back with `tries=0` |
| M1 | a malformed job file (truncated) → reported and skipped, the runner continues |
| S1 | `jobq stats` after R0 prints counts and the two timings |
| P1 | 10,000 `true` jobs, `-j 8` → under 60 s; the runner's listing count ≤ jobs/… (count the `read_dir` calls with a `--stats` line) |
| T1 | FR-10: TERM to a running runner; the behaviour documented and tested, or the gap named with the issue number |

### 7.2 Definition of Done

1. `wolf build`, `wolf fmt --check`, `wolf test .` clean.
2. `./test.sh` exits 0: R1 run three times in a row with no duplicate and no missing job.
3. Every state transition is a rename or a `create_new`; no job file is ever rewritten in
   place while another process could rename it (the rewrite happens after the claim, by
   the claimant, in `running/`).

## 8. Milestones

1. **M1** `init`, `add` (with `create_new`), the job file format, `ls` (A1, A2).
2. **M2** a serial runner (`-j 1`): claim by rename, spawn, capture, finish (R0, F1).
3. **M3** `-j N` inside one runner; leases renewed; `retry`, `stats` (S1).
4. **M4** racing runners (R1), lease expiry (R2, R3), M1.
5. **M5** P1, T1, `test.sh`.

## 9. Stretch goals

- Per-job `--after ID` dependencies; priorities; `--timeout` per job.
- `jobq watch` (a live `ls`); a JSON log.

## 10. Constraints & non-goals

- One directory for the program; the queue is wherever `--dir` says.
- Not a cron, not a server; no network. NFS is out of scope (say so in the README's note).
