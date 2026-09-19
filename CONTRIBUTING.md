# Contributing

Patches are welcome. Fork the repository, work on a branch of your fork, and
open a pull request against `master`. Only the owner can merge, so nothing
you do can land without being looked at first.

Small fixes need no warning. For anything larger — a new technique, a change
to how puzzles are carved, a new screen — open an issue first and say what
you have in mind, because a few of the things this game does are promises
rather than implementation details and it would be a shame to find that out
after the work.

## Before you open it

```sh
gleam test                    # 432 of them, about half a minute
gleam format src test         # CI refuses a diff, so run it
```

The suite is slow for a reason: it deals thirty-five real puzzles to check
that the drill positions are still where the table says they are. There is
no way to run one test through `gleam test` — [CLAUDE.md](CLAUDE.md) has the
incantation for running a single module, along with the rest of what this
repository expects.

Read that file. It is written for Claude Code and is the right thing for a
person to read too: it is the conventions rather than the contents, and it
is shorter than this paragraph suggests.

Continuous integration runs the suite on five combinations of operating
system, Erlang and Gleam, and checks the formatting once. Your first pull
request will wait for the owner to let the workflow run, which is GitHub
being careful with strangers rather than anybody being careful with you.

## How the code is written

**Deciding is kept apart from doing.** Reading a command line, working out
what a keystroke means, judging what the record books make of a game — none
of those needs a terminal, a file or a clock, and none of them has one. It
is not a style: a test cannot read a key, write a frame or open a file, so
anything that decides something has to be reachable without doing any of
them. When you add something that needs the world, split off the part that
does not.

**Comments explain why, in sentences.** This is most of the value in the
repository and the thing a newcomer is likeliest to sand off without
noticing it was load-bearing. Where a decision was made and something else
rejected, the comment says so. Read a few before you write any. Commit
messages are the same: a short imperative subject, then prose saying what
was wrong and why the fix is shaped as it is.

If that is not how you like to write, a pull request that says what it does
and lets the owner reword it is entirely welcome. Do not leave the comments
out and do not copy the tone badly; either is worse than asking.

## Things that will bite

**The screen is eighty by twenty-four and the tests enforce it.** Several
help pages sit at exactly twenty-four rows, so a new key row costs a line of
notes somewhere, or a page has to split. The title row above the board is
the tightest line in the game.

**Nine techniques fill the practice screen's nine digits.** A tenth would be
one nobody could press a key for.

**Generation is a promise.** A seed names a deal and a date names the one
puzzle everybody playing that day is handed, so changing a difficulty band,
the carving, or the daily's weekday ramp changes puzzles people may already
have played. `repeatable_test` pins a shuffle, a seeded deal and a daily to
written-down values and is meant to be read as a promise: if it fails, that
is the question being asked, not a number to update without thinking.

Adding a technique *above* every band's ceiling is safe, because carving
only accepts a removal while the grid still rates at or under the ceiling.
Changing a ceiling is not.

**Tests never touch the filesystem and never depend on the terminal.** The
record books have `_read` and `_written` halves so their round trip can be
tested without a disk, and the suite fixes its colour depth where it starts,
because the palette answers to `TERM`.

## Licence

The game is MIT, and anything you contribute goes in under the same terms.
There is no agreement to sign.
