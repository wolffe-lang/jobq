# WOLF-NOTES — the wolf surface a model needs for these projects

This file is shared by every wolf project in this directory. Each `prompt.md` copies it
beside the project README; read it once before writing a line. It is a map of the
language and toolchain **as installed on this machine**, not the spec. When this file
and the compiler disagree, the compiler wins: run the thing.

## 1. The toolchain, as installed

- `wolf --version` → `wolf 0.2.34 (wolfgang, pin 9da7bdc)` with `lupin 0.1.55` beside it, both
  from the `wolffe-lang/wolf` Homebrew tap (`brew upgrade wolffe-lang/wolf/wolf` moves them).
  The spec these projects assume is **wolf 0.2.34 or later**; everything in this file was
  measured on 0.2.34 (and on 0.2.28, where it behaves the same).
- **A directory is a module.** Every `.lu` file beside the entry file is part of the same
  module, and a second `main` in one directory is E0302. One program, one directory.
- `wolf run main.lu [args…]` builds and runs; extra words are the program's arguments.
- `wolf build main.lu -o NAME` makes a native binary. `--release` goes through LLVM.
- `wolf test .` discovers `*_test.lu` files; each top-level zero-parameter `fn test_*` is one
  test. A test file with a `main` and no `test_*` runs black-box as one test. Exit 0 when
  every row is `ok`.
- `wolf fmt --check FILE` is the one style; CI-grade projects pass it. Run `wolf fmt FILE`
  before you claim done.
- `wolf --explain E0401` explains any diagnostic by code.
- A `pub` signature with three or more error tags should name them through an alias
  (`error io_errors = {not_found, denied, io}` then `-> str ! io_errors`; W0602 otherwise;
  the alias is lowercase, W0603 otherwise). Inside a `match e` on a row, `return io` resolves
  only in an arm that names `io`: write the arms by name, not `_`.
- A literal `}` or `{` inside a string is `}}` / `{{` (every literal interpolates).
- An enum variant reached through a module path inside `if c then X else Y` (e.g.
  `cmp.Ordering.Less`) is refused by the compiled tiers at 0.2.34 ("a member access without
  a recorded type"); write the branches as statements with `return`. A tuple member on a
  call result (`f(x).1`) is refused the same way: bind it first, `let (a, b) = f(x)`.
- A function value literal has no return type: `fn(a: str, b: str) { a > b }` (E0201 with `-> bool`);
  a named `fn` passed by name works everywhere.
- **Every `pub` item needs a `///` doc comment** (W0313 otherwise), and a `wrapping[u32]`
  shift count must itself be `wrapping[u32]` (`x << (n as wrapping[u32])`). "Warning-free"
  in a README means zero warnings, these included.
- A build error exits **2**; a test failure exits **1**. A script that reads "exit 2" as a
  skip passes vacuously: check for exit 0.

## 2. The shape of the language (the parts that bite)

- `let` is immutable (fields included); `var` is mutable. Mutation is spelled at the call
  site: `f(mut x)`, `f(take x)`, `(mut xs).push(v)`.
- Generics use `[]`: `List[int]`, `Map[str, int]`, `fn id[T](x: T) -> T`.
- **Every string literal interpolates**: `"{x}"` is a hole; `{{` `}}` are literal braces.
  `r"…"` is raw. `str + int` is an error; interpolate the number.
- `str` is immutable and `Copy`. `s.len` is **bytes**. There is no `s[i]`; slices are
  `s[a..b]` on byte offsets (must land on code-point boundaries) and `s.get(a..b)` gives the
  `none` row instead of trapping. Methods: `find`/`rfind`/`contains`/`starts_with`/
  `ends_with`/`count`, `split` (keeps empty fields)/`words`/`lines`/`trim`/`trim_start`/
  `trim_end`/`strip_prefix`/`strip_suffix`, `chars()`, `bytes()`, `to_int() -> int ! {parse}`.
- A value in statement position that is not `()` is **E0401**: write `let _ = f(mut m)`
  when you ignore a result.
- **Errors are rows, not exceptions.** A function declares `-> T ! {a, b}`. Handle with `?`
  (propagate), `else expr` (default), `else |e| { … }` (block; may `return`), or
  `else |e| match e { a => { … }, b => { … } }`. `"{e}"` renders a row's name.
- `match` arms: `Enum.Variant(x) => …`, ranges `1..=9 =>`, `_ =>`. Two-way expression:
  `if c then a else b`.
- Enums carry payloads, **but every compiled tier refuses an enum whose variants carry
  payloads of different types** (`enum V { Int(int), Text(str) }` → "cannot compile this
  yet — enum payload slots with conflicting types across variants (spilled union layout,
  c06)", exit 4; wolf-lang#268 inventories it). Unit variants plus payloads of ONE type
  are fine (`enum Tok { Num(int), Count(int), End }`). So a value tree (JSON, TOML, a
  template AST) is **a tagged struct in an arena**, not a recursive enum:

  ```wolf
  struct Node {
      kind: int,          // 0 null, 1 bool, 2 int, 3 float, 4 str, 5 list, 6 table
      b: bool,
      i: int,
      f: f64,
      s: str,
      kids: List[int],    // indices into the arena, for lists and tables
      keys: List[str],    // parallel to kids, for tables
  }
  // var arena = List[Node](); a node's id is its index; the root is 0.
  ```

  `std.json`'s `Value` is such an enum, so **`std.json` does not compile natively** at this
  pin: write your own JSON emitter (it is twenty lines) and never import `std.json`.
- Lists: `List[T]()`, `xs.push(v)` via `(mut xs).push(v)`, `xs.len`, `xs[i]`, `for x in xs`.
  List literals `[1, 2, 3]` need an element type from context.
- Maps: `Map[str, int]()`; use `std.map` (`map.set`, `map.get(m, k) -> V ! {none}`,
  `map.get_or`, `map.has`, `map.keys`, `map.tally(mut m, k) -> int`). Keys are `str`, `int`,
  `char` or `bool`.
- Arithmetic is checked (overflow traps). Intended wraparound is `wrapping[T]`, e.g. a
  hash accumulator is `var h: wrapping[u32] = 0`. Bitwise not is `!`.
- Reserved words that bite as names: `handle`, `spawn`, `copy`, `move`, `in`, `type`,
  `proc`, `region`, `take`, `scope`, `use`, `impl`.
- `defer f(x)` runs at scope end. No lifetimes, no region syntax unless a loop's scratch
  must die per iteration (`region scratch { … }`), and at 0.2.34 that works only when
  nothing declared outside the region is mutated inside it: `sha2.update256(mut st, chunk)`
  or `(mut xs).push(…)` inside a `region` is E1010 (wolf-lang#856/#839; fixed for 0.2.35).
  Until then, name the gap and let the scratch live to the end of the call.

## 3. The std, imported as `use std.NAME`, called as `NAME.fn(...)`

| module | what you will reach for |
|---|---|
| `std.fs` | `read_text`, `write_text`, `append_text`, `read_bytes`, `write_bytes`, `exists`, `is_file`, `is_dir`, `size`, `modified_ms`, `read_dir -> List[str]`, `entries -> List[Entry]`, `create_dir_all`, `remove`, `stat`/`lstat -> Info`, `open`/`create`/`create_new`, `read_chunk`, `write_chunk`, `close`, `realpath`, `stdin()` |
| `std.io` | `write`, `write_line`, `write_err`, `write_err_line`, `input_line -> str ! {eof, io, utf8}`, `input_all` |
| `std.env` | `args()` (no argv[0]), `get(name) ! {missing, utf8}`, `cwd()`, `set_cwd` |
| `std.str` | `split`, `splitn`, `split_once ! {none}`, `replace`, `lower`, `upper`, `trim*`, `lines`, `words`, `join(sep, parts)`, `repeat`, `find_all`, `char_count` |
| `std.strbuf` | `new()`, `push_str(mut b, s)`, `push(mut b, c)`, `to_str(b)` — **build long output here, never with `+=` in a loop** |
| `std.fmt` | `pad_left`, `pad_right`, `to_hex`, `to_str_base`, `parse_int ! {parse}`, `parse_int_base` |
| `std.list` | `push`, `pop`, `sort_by`, `sorted_by`, `map`, `filter`, `fold`, `any`, `all`, `index_where`, `extend`, `reverse` |
| `std.sort` | `sort_strs`, `sort_ints`; its `sort_by` wants a `cmp.Ordering` comparator, and `cmp.Ordering.Less` through the module path is refused natively at 0.2.34: use `std.list.sort_by(mut xs, less)` with a `fn(T, T) -> bool` instead |
| `std.map` | see above |
| `std.json` | **do not import** (its `Value` enum is refused by the compiled tiers; see §2) |
| `std.bytes` | `from_str`, `to_str ! {utf8}`, `slice`, `find`, `starts_with` |
| `std.base64`, `std.hex` | `encode`/`decode ! {parse}` |
| `std.x.crypto.sha2` | SHA-256 (read `std/x/crypto/sha2/sha2.lu` for the exact names before use) |
| `std.process` | `command(prog)`, `push_arg(mut c, a)`, `start -> Child`, `wait_status(take ch) -> int`, `run(c) -> int`, `set_stdout`, `pipe()` |
| `std.time` | `unix_ms()`, `monotonic_ns()`, `now()`, `elapsed`, `sleep(millis(n))` |
| `std.testing` | `assert_eq`, `assert_ne`, `fail(msg)`; the builtin `assert(cond, msg)` works anywhere |
| `std.rand` | `new(seed)`, `below(mut r, n)` — deterministic, for test data |

Builtins that need no import: `print(s)` (adds `\n`), `print_raw`, `eprint`, `env_args()`,
`read_line() -> str ! {eof, io, utf8}`, `fs_read_bytes`, `fs_open`, `fs_read_chunk`,
`fs_write_chunk`, `os_exit(n)`, `assert(cond, msg)`.

## 4. Process edge rules (measured, not folklore)

- `print` is one `write(2)` per call. For more than a few thousand lines, build bytes in a
  `List[byte]` and `fs_write_chunk` them per 64 KiB, or at least build a `StrBuf` and print
  once.
- Open `/dev/stdout` with `fs_open_mode("/dev/stdout", 2)` (append) **before** opening any
  input file, if you need a byte-exact stdout.
- `read_line` strips `\n`/`\r\n` and refuses non-UTF-8 (the `utf8` row). Byte-exact input
  is `fs_open("/dev/stdin")` + `fs_read_chunk`; end of input is the `eof` **row**.
- SIGPIPE kills a wolf program silently (status 141), as it kills `cat`. Fine.
- `main -> int` returns the exit status. Usage errors in these projects exit **2** unless the
  README says otherwise.
- The std's `fs.read_dir` answers names only; `fs.entries` answers `Entry` records; `stat`
  follows links and `lstat` does not.

## 5. How to work (the habits that finish projects)

1. `mkdir` nothing outside the current directory. The build is `wolf build main.lu -o NAME`,
   the tests are `wolf test .` plus the project's `test.sh`.
2. Write the smallest program that compiles, run it, then grow it. A file that has not
   compiled for twenty minutes is a file to cut back.
3. Keep the logic in functions that take `str`/`List[byte]` and return values; keep `main`
   thin. Those functions are what `*_test.lu` can test.
4. When the compiler names a row you did not handle, handle it by name. Do not reach for a
   catch-all `else |_|` until you have read which rows the function raises.
5. Every claim of "passes" is a command you ran and its exit status. Paste the status.
