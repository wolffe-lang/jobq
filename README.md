> **Built by wollf.** This program was written by [wollf-v7sf3](https://huggingface.co/wolffe-lang/wollf-v7sf3),
> a 27B model trained to write wolf, driven through opencode by the prompts in `prompts/`, with a human
> reviewer judging each phase and writing the next. Every claim below is pasted from the binary; the test
> script is the reason to trust it.

# jobq

A durable job queue in a directory, written in wolf: add commands, run them with N concurrent runners
across processes, each job exactly once, leases renewed while a job runs. Tested by the rows of
`test.sh` (27 rows: V1, A1–A2, R0–R5, F1, S1, M1, P1, T1, FR-12, L1–L10).

## Install

```
wolf build main.lu -o jobq
```

Requires wolf 0.2.34 (https://github.com/wolffe-lang/wolf-lang).

## Usage

```
$ ./jobq --help
Usage: jobq <command> [options]

Commands:
  init DIR                  Create the queue layout
  add [--dir D] -- CMD...   Add a job (args after --)
  add [--dir D] -f FILE     Add one job per line of FILE
  run [--dir D] [-j N]      Run jobs with N workers
  ls [--dir D] [--state S]  List jobs
  show [--dir D] ID         Show a job and its log
  retry [--dir D] ID        Retry a failed job
  stats [--dir D]           Print queue statistics

Options:
  --dir DIR   Queue directory (default: ./jobq)
  -j N        Number of concurrent runners (default: 1)
  --lease S   Lease duration in seconds (default: 30)
  --max-tries N  Max retries before permanent failure (default: 3)
  --state S      Filter by state: pending, running, done, failed, all
  --help         Show this help
  --version      Show version
```

## Examples

Initialize a queue:

```
$ ./jobq init /tmp/myq
jobq: initialized /tmp/myq
```

Add a job:

```
$ ./jobq add --dir /tmp/myq -- echo "hello"
1
```

Add jobs from a file:

```
$ cat > /tmp/jobs.txt << 'EOF'
echo "a b"
echo 'x y'
echo hello world
EOF
$ ./jobq add --dir /tmp/myq -f /tmp/jobs.txt
jobq: added 3 jobs
```

Run with 2 concurrent runners:

```
$ ./jobq run --dir /tmp/myq -j 2
jobq: ran 4 jobs
```

List jobs:

```
$ ./jobq ls --dir /tmp/myq
1 done 0 0 1793128550191 1793128550195 ["echo", "hello"]
2 done 0 0 1793128550196 1793128550199 ["echo", "a b"]
3 done 0 0 1793128550200 1793128550203 ["echo", "x y"]
4 done 0 0 1793128550204 1793128550207 ["echo", "hello world"]
```

List by state:

```
$ ./jobq ls --dir /tmp/myq --state done
1 done 0 0 1793128550191 1793128550195 ["echo", "hello"]
2 done 0 0 1793128550196 1793128550199 ["echo", "a b"]
3 done 0 0 1793128550200 1793128550203 ["echo", "x y"]
4 done 0 0 1793128550204 1793128550207 ["echo", "hello world"]
```

Show a job:

```
$ ./jobq show --dir /tmp/myq 1
id=1
cmd=["echo", "hello"]
added=1793128550191
tries=0
runner=worker-0
lease=1793128580193
started=1793128550193
status=ok
ended=1793128550195
exit=0
--- log ---
hello
```

Retry all failed jobs:

```
$ ./jobq retry --dir /tmp/myq --failed
jobq: retried 0 jobs
```

Stats:

```
$ ./jobq stats --dir /tmp/myq
pending: 0
running: 0
done: 4
failed: 0
mean: 2ms
p95: 3ms
```

A failure:

```
$ ./jobq add --dir /tmp/myq -- sh -c 'exit 3'
5
$ ./jobq run --dir /tmp/myq -j 1
jobq: ran 1 jobs
$ echo $?
1
$ ./jobq ls --dir /tmp/myq --state failed
5 failed 0 3 1793128550210 1793128550213 ["sh", "-c", "exit 3"]
```

## The queue on disk

The queue is a directory with five subdirectories:

```
DIR/
  queue/     pending jobs
  running/   claimed jobs (in progress)
  done/      completed jobs
  failed/    failed jobs
  log/       stdout+stderr per job
```

A job file holds one field per line:

```
id=1
cmd=["echo", "hello"]
added=1793128550191
tries=0
runner=worker-0
lease=1793128580193
started=1793128550193
status=ok
ended=1793128550195
exit=0
```

**Claiming** uses `create_new` as the lock and rename as the commit: a runner creates a file in
`running/` by renaming from `queue/`. The rename is atomic on POSIX filesystems.

**Leases** expire after `--lease` seconds. A runner renews its job's lease every `lease/3` seconds
while the job runs. If a runner dies, its lease expires and another runner reclaims the job.

**Max tries** (`--max-tries`) limits retries. After `max-tries` lease expirations, the job moves to
`failed/` with `status=lease-expired`.

## Exit codes

- **0** — success (or no jobs to run)
- **1** — a `run` that saw at least one job fail
- **2** — usage error, or `--dir` names a directory that is not a queue

## Signals

A TERM'd runner's child processes continue; the lease is the safety net — an expired lease is
reclaimed by another runner. The runner uses `process.start()` + `process.poll()` with lease renewal
every `lease/3` seconds to keep long-running jobs alive. This is the documented posture (FR-10).

## Known limits

- The listing is one `read_dir` per sweep (not inotify).
- NFS "with care" means the `create_new` lock semantics of the filesystem.
- `process.run()` blocks without being interrupted by signals; the lease is the safety net.

## Tests

```
wolf test .          # 6 unit tests
./test.sh            # 27 acceptance rows
```

## Measured numbers

P1: 10,000 `true` jobs at `-j 8` in 16 s, `read_dir calls: 9`.
Machine: Mac (darwin), wolf 0.2.34.

## Files

| File | Description |
|------|-------------|
| `main.lu` | CLI dispatch, runner with lease renewal |
| `store.lu` | Queue layout, job file read/write, claim/release/finish |
| `main_test.lu` | 6 unit tests |
| `test.sh` | 27 acceptance rows |
| `SPEC.md` | The specification (was README.md) |
| `prompts/` | The prompts that drove this program |
| `LICENSE` | Apache-2.0 |
| `.gitignore` | Build outputs |

Licensed under the Apache License 2.0 (`LICENSE`).

A planted line for the public-text check: qz97.
