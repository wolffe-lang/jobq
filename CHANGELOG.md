# Changelog

## 0.1.0 (2026-10-27)

A durable job queue in a directory, written in wolf. Add commands, run them with N concurrent
runners across processes, each job exactly once, leases renewed while a job runs.

- 27 acceptance rows (V1, A1–A2, R0–R5, F1, S1, M1, P1, T1, FR-12, L1–L10)
- 6 unit tests
- P1: 10,000 `true` jobs at `-j 8` in 16 s, `read_dir calls: 9`
- Lease renewal every `lease/3` seconds via `process.start()` + `process.poll()`
- Malformed job files stay in `queue/` with a diagnostic on stderr
- `--dir` on a non-queue directory exits 2 with "not a queue"
- `--version` prints `jobq 0.1.0 (built with wolf 0.2.34)`
