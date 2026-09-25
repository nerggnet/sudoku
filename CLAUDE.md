# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
gleam run                     # play; see README for the arguments
gleam test                    # all of them, 384 at the time of writing
gleam format src test         # CI runs `gleam format --check src test`
gleam docs build              # uses the metadata in gleam.toml
./package.sh                  # one self-contained executable, build/sudoku
```

There is no way to run one test through `gleam test` — gleeunit finds every
`*_test` function under `test/` and runs the lot. To run one module:

```sh
gleam test >/dev/null                     # build the test target first
erl -pa build/dev/erlang/*/ebin -noshell -eval \
  'sudoku@term:colouring(full), eunit:test(menu_test, [verbose]), halt(0).'
```

The `colouring(full)` is not optional. `test/sudoku_test.gleam` sets it before
gleeunit runs, because the palette answers to `TERM`; going in through eunit
skips that and colour-dependent tests then pass or fail by whatever terminal
you are sitting at.

The same trick is the way to probe anything without a terminal to drive —
`gleam export erlang-shipment` then `erl -pa build/erlang-shipment/*/ebin`,
calling `sudoku@generator:deal_daily/2` and friends directly. Gleam modules
are `sudoku@name`, constructors with no arguments are lowercase atoms
(`Full` → `full`), and `gleam/dict` is an Erlang map.

## Where things are

The project is one game, not a library, and the module names are the
vocabulary:

- **`board`** — the 9×9 grid, cells indexed 0..80. Geometry (`rows`, `units`,
  `peers_of`) is memoised in `persistent_term`; it is a constant of Sudoku,
  not of a puzzle.
- **`solver`** — backtracking search. Answers *whether* and *what*.
- **`logic`** — the same question answered the way a person answers it: nine
  techniques, easiest first. This is what rates a puzzle and what a hint
  needs. `rate` is the hardest technique a grid demands.
- **`generator`** — carves a solution down while `logic` can still finish it.
  A `Difficulty` is a band: a floor and ceiling of reasoning plus a clue
  target.
- **`game`** — what a game *is*. **`rules`** — what a keystroke does to one.
  **`hint`** — what `logic` makes of one. The latter two reach into `game`
  and `game` reaches into neither, which is what lets the three be three
  rather than a circle.
- **`store`** — three files under XDG data: `game*` (one per game put
  down), `bests` (per difficulty: quickest, how many, total), `dailies` (one
  time per date). The palette lives under XDG *config* instead, being the
  player's to write rather than the game's.
- **`render`** + **`palette`** + **`term`** — drawing, colours, and the
  terminal.
- **`menu`** — what a keystroke means on the screens that choose a puzzle.
- **`tutor`** — what to say to somebody being walked up to a technique on a
  practice grid. Pure, and it never touches the board: every rung is worked
  out from the `logic.Step` the position wants.
- **`practice`** — the nine grids kept to teach a technique, and the drill
  positions to meet it again on. A drill is `#(difficulty, seed, taken)`,
  not a grid: deals are reproducible, so replaying one and walking its
  reasoning `taken` steps lands on the same position every time. Building
  one means dealing a puzzle, so `drill_test` is the slowest thing in the
  suite and the only thing that can tell you the table is right.
- **`date`** — a day and its weekday, which is all the calendar the daily
  needs. Day arithmetic goes through the day count, not through subtraction.
- **`sudoku.gleam`** — the loop: draw, read, act. Deliberately thin.
- **`sudoku_escript`** + **`scripts/package.escript`** — how the game leaves
  the repository: a zip of every compiled module with a shebang on the front,
  which is what a release is. Nothing else imports either of them and nothing
  in the game knows they exist.

## The convention that matters most

**Deciding is kept apart from doing**, everywhere, and it is what makes the
code testable at all:

| decides | does |
| --- | --- |
| `invocation.read` | acting on it, in `sudoku.gleam` |
| `menu.answered` | drawing the screen and reading the key |
| `logic` | `rules` |
| `store.judge` | `store.settle` |
| `store.bests_read` / `bests_written` | `bests()` / `write_bests()` |
| `render.cramped_at` | `render.cramped` |

When you add something that needs a terminal, a file or a clock, split the
part that does not. **Tests never touch the filesystem** — that is why the
books have `_read`/`_written` halves. The main loop's IO shell is the one
thing still untested, and that is exactly where the one bug of this kind
turned up: three menu screens read a line-mode newline as "anything else",
which on two of them meant "go back", so a keystroke silently undid itself
and the game dealt a different puzzle than the one asked for.

## Prose

Comments explain *why*, in full sentences, at length, in a distinctive
register. This is not incidental — it is most of the value in the repo. Match
it. Commit messages are the same: a short imperative subject, then prose
paragraphs explaining what was wrong and why the fix is shaped as it is.

Where a decision was made and rejected, the comment says so. Read a few
before writing any.

## Things that will bite

**Help pages must fit 24 rows** and `render_test` enforces it. Several pages
sit at exactly 24. Adding a key row or a line of notes means taking one away
somewhere, or splitting a page. `Keys`/`Marking`/`Asking` are three for
this reason and `Starting`/`Repeating` two.

**The practice screen numbers techniques 1–9** and there are exactly nine. A
tenth would be unreachable; a test says so.

**Menu numbering is computed, never written down** (`practice.choice()`,
`menu.daily_choice()`). Adding a difficulty shifts everything after it.

**Generation is a promise, not an implementation detail.** A seed names a
deal and a date names the one puzzle everybody playing that day gets.
`repeatable_test` pins a shuffle, a seeded deal and a daily to written-down
values — it is meant to be read as a promise, and it fails if the carving
changes. Adding a technique *above* every band's ceiling is safe (carving
accepts a removal only when the grid still rates at or under the ceiling);
changing a ceiling, a band or the daily's weekday ramp changes puzzles people
may have played. Snapshot before and diff after.

**Colour has three levels**, not two: `term.Full` (256, where the washes
live), `term.Basic` (sixteen, one grey for all four washes plus the `›`/`+`
marks), `term.Plain`. `palette` colours are functions because
`~/.config/sudoku/palette` can override them; the characters are constants
because a glyph of the wrong width breaks the grid.

**A packaged game reads its command line differently**, and this is the one
thing about the executable that is not plumbing. `init:get_plain_arguments/0`
is where `term.arguments` looks, and under escript it answers with the path
the executable was invoked by on the front of the list — which this game,
being strict about what a word on its command line may be, refuses as a
puzzle that is not one. So `sudoku_escript:main/1` puts what it was actually
handed into a `persistent_term` and `arguments/0` prefers that. Anything that
changes how arguments are read has to be tried against `./build/sudoku` and
not only against `gleam run`, because the two do not agree.

**A release is a tag and nothing else.** `v1.2.3` pushed to GitHub builds the
executable and publishes it; a push to master does not. The workflow refuses
a tag that disagrees with the version in `gleam.toml`, since the executable
reports that version and a binary calling itself something other than what it
was downloaded as is the exact confusion `--version` exists to prevent. So
bumping `gleam.toml` is part of making a release rather than a thing to
remember afterwards.

**Floors are OTP 27 and Gleam 1.15**, neither of them ours — stdlib sets
both. CI is a matrix over those and macOS precisely because a local
`gleam test` proves nothing about them.
