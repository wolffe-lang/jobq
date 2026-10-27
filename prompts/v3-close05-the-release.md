# jobq — closeout 5: the release shape (0.1.0)

Closeout 4 landed whole: 26 rows green, R4 verbatim, P1 under 60 s with `read_dir calls` ≤ 10, M1's line, the header, the two
helpers, the ten L rows, one commit per section. The judge re-ran it from a fresh copy: build 0, fmt 0, 6 unit tests, R4 by hand
exactly once, P1 26 s with 9 listings. **The code is done. The repository is not in the shape spell, mk and tomlq were
published in.** This session writes no `.lu` code except `--version`. **First run `./test.sh; echo "exit=$?"`; if it does not
end `exit=0`, stop and paste it.**

## 1. The specification and the prompts — commit "Add the specification and the prompts"
- `git mv README.md SPEC.md` (the README in this tree IS the specification the build followed; it becomes `SPEC.md`, as
  spell and mk ship it).
- `mkdir prompts && git mv prompt.md prompts/prompt.md && cp ../../_prompts/*.md prompts/` (the closeouts 01–05 and the
  phase prompts `../../v1.md` … `../../v4.md` → `prompts/v1.md` …). `git add prompts`.
- `.gitignore` gains `WOLF-NOTES.md`; `git rm --cached WOLF-NOTES.md` (the shared notes are not this program's).

## 2. `--version` — commit "jobq --version"
`jobq --version` prints `jobq 0.1.0 (built with wolf 0.2.34)` and exits 0 (`wolf --version` tells you the toolchain line;
paste what it says); `--help` lists it. A row `V1` in test.sh checks the exact line.

## 3. Diagnostics to stderr — commit "Diagnostics on stderr"
`jobq: queue/<name>: malformed (line K)` and `read_dir calls: N` go to **stderr** (`eprint`), never stdout; `jobq: ran N jobs`
stays on stdout. M1's and P1's rows read them from stderr. `./test.sh` green after.

## 4. `LICENSE` — commit "Apache-2.0"
`curl -sS https://www.apache.org/licenses/LICENSE-2.0.txt -o LICENSE && shasum -a 256 LICENSE` — the digest must start
`cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`; never retype the text.

## 5. `README.md`, written fresh in parts (≤60 lines per edit) — commit "Write the README for the release"
Every example is a command you run in this session with its output pasted unchanged. Follow tomlq's layout:
1. The banner, verbatim, as the first lines:
   ```
   > **Built by wollf.** This program was written by [wollf-v7sf3](https://huggingface.co/wolffe-lang/wollf-v7sf3),
   > a 27B model trained to write wolf, driven through opencode by the prompts in `prompts/`, with a human
   > reviewer judging each phase and writing the next. Every claim below is pasted from the binary; the test
   > script is the reason to trust it.
   ```
2. `# jobq`, then two sentences: what it is (a durable job queue in a directory, in wolf: add commands, run them with N
   concurrent runners across processes, each job exactly once, leases renewed while a job runs) and how it is tested (the
   rows of `test.sh`, named).
3. **Install:** `wolf build main.lu -o jobq`; "Requires wolf 0.2.34 (https://github.com/wolffe-lang/wolf-lang)".
4. **Usage:** `./jobq --help` pasted.
5. **Examples:** `init`, `add -- cmd`, `add -f`, `run -j 2`, `ls`, `ls --state done`, `show ID`, `retry --failed`, `stats`,
   and one failure (`sh -c 'exit 3'` → `failed/`, exit 1) — commands and outputs pasted.
6. **The queue on disk:** the layout (`queue/ running/ done/ failed/ log/`), the job file's fields (one per line, as
   `render_job` writes them), the claim (`create_new` as the lock, rename as the commit), the lease and its renewal every
   `lease/3`, what a killed runner leaves and how the next runner reclaims it, `max-tries`.
7. **Exit codes:** 0; 1 a `run` that saw a job fail; 2 usage or a directory that is not a queue.
8. **Signals:** FR-10's posture as main.lu's header states it, in one paragraph, honestly.
9. **Known limits:** the listing is one `read_dir` per sweep (not inotify); NFS "with care" means the `create_new` lock
   semantics of the filesystem; anything else test.sh does not cover that you know of. Nothing else.
10. **Tests:** the commands; the row count of test.sh and the unit-test count (counted, pasted).
11. **Measured numbers:** the P1 line (seconds, `read_dir calls`) and the machine (this Mac).
12. **Files:** a table of every tracked file (`git ls-files`) and what it holds; `prompts/` one row.
13. The last line: `Licensed under the Apache License 2.0 (`LICENSE`).`

## 6. `CHANGELOG.md` — commit "Write the 0.1.0 changelog"
`## 0.1.0 (YYYY-MM-DD)`: what it does, the row count, the P1 numbers; no other claim.

## Verify (paste)
`./test.sh; echo "exit=$?"` (27 rows with V1); `./jobq --version`; `wolf fmt --check *.lu; echo fmt=$?`; `git status --short`
(nothing); `git ls-files` (prompts/ tracked, WOLF-NOTES.md not, no binary); `head -n 8 README.md`; `shasum -a 256 LICENSE`;
`git log --oneline | head -8`. The maintainer creates the repository and pushes; do not run `git remote` or `git push`. Stop.
