# sudoku

A Sudoku game for the terminal, written in Gleam.

```sh
gleam run                     # choose a puzzle from the menu
gleam run -- hard             # deal one at that difficulty
gleam run -- custom           # type a puzzle in
gleam run -- resume           # pick up the game you left
gleam run -- 53..7....6..1..  # play that puzzle, dots for the blanks
```

Pick a difficulty, then play. Puzzles are generated fresh each time, always
have exactly one solution, and can always be reasoned out — none of them ever
needs a guess. Or pick `Custom` and type a puzzle in yourself, out of a
newspaper.

```
 S U D O K U    Medium    marking

   board                          marks
     1 2 3   4 5 6   7 8 9          1 2 3   4 5 6   7 8 9
   ┌───────┬───────┬───────┐      ┌───────┬───────┬───────┐
 A │ · · 1 │ 8 3 · │ 9 5 · │    A │ * · · │ · · · │ · · · │
 B │ · · · │ 9 · · │ 7 3 6 │    B │ · · · │ · · · │ · · · │
 C │ · · 7 │ · · · │ · 8 · │    C │ · · · │ · · · │ · · · │
   ├───────┼───────┼───────┤      ├───────┼───────┼───────┤
 D │ · · 3 │ 2 1 · │ · 4 · │    D │ 7 · · │ · · · │ · · · │
 E │ 9 2 8 │ · · · │ 3 1 7 │    E │ · · · │ · · · │ · · · │
 F │ · 5 · │ · 7 9 │ 6 · · │    F │ · · · │ · · · │ · · · │
   ├───────┼───────┼───────┤      ├───────┼───────┼───────┤
 G │ · 1 · │ · · · │ 8 · · │    G │ · · · │ · · · │ · · · │
 H │ 4 7 9 │ · · 3 │ · · · │    H │ · · · │ · · · │ · · · │
 I │ · 3 2 │ · 5 6 │ 4 · · │    I │ · · · │ · · · │ · · · │
   └───────┴───────┴───────┘      └───────┴───────┴───────┘

 empty 45  │  clashes 0  │  time 00:00  │  A1 marked 1 3 5
```

## Keys

| Key | |
| --- | --- |
| `←` `↑` `↓` `→`, `hjkl`, `wasd` | move the cursor |
| `1`–`9` | write a digit, or pencil one in while marking |
| shift `1`–`9` | pencil a digit in either way round |
| `0`, space, backspace | clear the cell, or its marks while marking |
| `f` | pencil the candidates into every bare cell |
| `m` | switch between writing and marking |
| `u` | undo |
| `r` | do it again |
| `c` | check what is filled in from here on, at a price (press twice) |
| `H` | take the next step, and say why |
| `R` | reveal the whole solution |
| `n` | start a new puzzle |
| `?` | help, and the techniques a page at a time |
| `q` | quit |
| `Ctrl-L` | draw the screen again |

Clues are fixed and cannot be overwritten. Digits that clash with another in
the same row, column or box turn red and are struck through as you type them,
and the cells sharing a row, column or box with the cursor are shaded so it is
easier to see what a cell can still be.

The striking through is not decoration. A terminal without colour still draws
attributes, so clues stay bold, a wrong digit stays underlined, the cursor
stays in reverse video — and a clash, which had only its redness to go on,
would otherwise have looked exactly like a clue. There is a test that any two
things the player must tell apart differ by more than their colour.

## Difficulty

A difficulty is not a clue count. It is the hardest reasoning a puzzle will
ask of you, which is the thing a clue count only gestures at: two puzzles with
the same number of clues can be a minute apart or an hour.

| | asks for | clues | carving |
| --- | --- | --- | --- |
| Easy | naked singles | 39–40 | instant |
| Medium | hidden singles | 31–32 | instant |
| Hard | locked candidates | 26–27 | about a third of a second |
| Expert | naked pairs and better | 22–27 | about a second |

Each level is what it says: measured over twenty-five puzzles apiece, every
Easy needed nothing but naked singles, every Medium wanted a hidden single
somewhere, every Hard a locked candidate, and every Expert a pair or better,
up to the occasional X-wing.

Clues still come into it, because two different things make a puzzle hard.
The reasoning is one — a grid that never asks for more than a naked single is
easy whatever else is true of it. The other is how much of the grid is
missing, which is not reasoning at all but hunting: a singles-only puzzle with
twenty clues is still a long stare before the first digit goes in. So a level
sets both, and carving stops at whichever comes first.

Nothing dealt ever needs a guess. Carving only takes a cell out if what is
left can still be reasoned to the end, so a puzzle that could not be is never
carved that far. That also does the work of checking the answer is unique:
reasoning never guesses, so a grid it can finish has exactly one answer.

## Filling the candidates in

`f` pencils every candidate into every empty cell that has none: what that
cell could still take, read off its row, its column and its box.

It costs nothing, because it works out nothing you could not have worked out
yourself with a pencil and some patience. What it buys is the rest of the
game. Every technique past a naked single is an argument about candidates, so
the hints have nothing to point at until some are on the board — press `f` and
the same forty hints turn up five or six eliminations that were never offered
before, because there was nothing for them to rub out.

Cells you have already marked are left alone: that is where you have been
thinking, and this is not the place to rub it out. Writing a digit keeps the
rest tidy on its own, retracting that digit from every cell that can see it,
so `f` is usually a thing you press once.

Which leaves the marks you made wrongly. A cell you pencilled a single digit
into looks as settled as any other, and nothing will shift it — filling steps
around it by design. So when `f` finds nothing bare left to do, it offers:

```
 Every empty cell is marked up already.
 Press f again to mark them all afresh.
```

Ask again and every empty cell is marked over from the grid, your own
pencilling included. It takes two asks because what it throws away is your
work, and the offer does not keep: do anything in between and the next `f` is
a fresh question.

Marks made wrongly cannot make the game lie to you in the meantime. A mark
too wide — a digit that cannot go there — leaves the reasoning with more to
choose from, so the hints go quieter rather than wrong. A mark too narrow can
lead the reasoning somewhere the answer does not go, and there the hint checks
itself, declines, and says that nothing settles the cell yet.

## Hints that explain themselves

`H` used to name a digit and leave it at that, which answers the cell and
teaches nothing. Now it works out the next move the way a person would and
says what it did:

```
 Naked single: C6 can only be a 4.
 Every other digit is already in its row, column or box.

 Hidden single: A2 is the only cell in row A that can take a 9.
 The other empty cells in row A can all see a 9 already.

 Locked candidates: every 1 in the top-left box is in row C.
 So no 1 anywhere else in row C — C6 loses it.

 Naked pair: C8 and F8 take 7 and 8 between them.
 One each, whichever way round, so D8 and E8 lose both.

 X-wing: a 9 in rows B and F keeps to columns 2 and 9.
 One in each row means one in each column, so 4 cells lose it.
```

The names are the ones Sudoku players use, so they are worth learning: a
player told that C8 and F8 take 7 and 8 between them has been given this one
move, and a player told it is a naked pair has been given every naked pair
they will ever meet. The first row names the technique and states the crux;
the second says why that settles it and what has just changed on the board.

The status line keeps both rows whether or not there is anything for the
second, so the board above it never shifts by a row between one message and
the next.

The first hint of a game says what it will cost before it costs it:

```
 A hint makes this an aided game, and aided games are not timed.
 Press H again to go ahead.
```

Ask again and the game is aided from then on, which it says beside the
difficulty for the rest of the puzzle — `Hard (aided)` — since that is what
the difficulty no longer quite means. The asking comes once: after that, hints
are given as soon as they are asked for. Checking makes a game aided in the
same way and by the same reasoning, so a game that has already been checked
is not asked twice about a hint. A puzzle typed in is never warned about a
hint at all, having no time to lose — though it is still warned about
checking, which is irreversible and can forfeit whatever the puzzle came
from.

A hint answers the cell you are on. You asked while looking at it, so that is
the cell it takes first — and only two techniques settle a cell rather than
ruling candidates out, so whether this one will go yet is a quick question to
ask.

When it will not go yet, the hint says so and stays where you are:

```
 Nothing settles A2 yet.
 Press H again to look elsewhere.
```

You were looking there for a reason, and an answer three rows away is not the
one you asked for. Ask a second time and it goes looking; do anything else in
between and the next ask is a fresh question, answered the same way. Saying
there is nothing to say is not a hint, and is not counted as one.

The hints reason from the marks you have made, not only from the digits on
the board. Narrowing a cell by hand narrows what the reasoning has to work
with, and rubbing a candidate out is a real change to the position — which is
what lets a step that only rules candidates out lead to the next one instead
of coming round again. Marks that are wrong can lead the reasoning astray;
they cannot lead you astray, because every step is still checked against the
answer before a hint acts on it.

A hint points as well as talks. The cells its argument rests on are lit up on
the board until the next keystroke — the two cells of a pair, the four corners
of an X-wing, the unit a hidden single is hidden in — so an elimination can be
seen and not only read. And `?` after a hint opens the help at the technique
it named, rather than at the keys, since that is what somebody who has just
read one is asking after.

A hint always moves something. Where the next step settles a digit it writes
it in; where the step only rules candidates out it rubs them out of your
marks, which is what you would do with it yourself. An elimination you have no
marks for would change nothing on the screen and be offered again for ever, so
in that case the hint falls back to naming a digit, the way it always did.
That is also the fallback for a puzzle beyond the reasoning, and for a grid
with a wrong digit already in it: a hint checks every digit against the answer
before writing it, because reasoning from a wrong digit leads somewhere the
answer does not go.

## The help, and the techniques

`?` opens the help on the keys. `←` and `→` page from there through what the
command line takes, and then through the seven ways of working a digit out,
one to a page: what it is, a small board showing
it happening, and what it settles. Anything else puts the help away, and while
it is up the arrows turn pages rather than moving the cursor, so there is no
reading about a technique and losing your place on the board.

```
 Naked pair

 Two cells in a unit holding the same two candidates take one each
 between them, whichever way round, so nothing else can have either.

        1     2     3     4     5     6     7     8     9
     ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
   C │  79 │  4  │  79 │ 1379│  3  │  5  │  8  │  6  │  2  │
     └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘

 C1 and C3 take 7 and 9, so C4 is down to a 1 or a 3.

 ← →  page 5 of 8     any other key returns
```

The strips show what the cells of one unit have left in them. Where a
technique is about one digit's whereabouts rather than one cell's contents,
the page draws a board instead, marking where that digit can still go and
where the reasoning has just shut it out:

```
 Locked candidates

       1 2 3   4 5 6   7 8 9
     ┌───────┬───────┬───────┐
   A │ 1 1 · │ 1 · 1 │ · 1 · │
   B │ · · · │ · 1 · │ 1 · · │
   C │ · · · │ · · 1 │ · · 1 │
     └───────┴───────┴───────┘

 Every 1 in the left box is in row A, so A4, A6 and A8 lose theirs.
```

The clock waits while the help is up. Reading about a technique is not
playing, and eight pages is long enough that it would otherwise show.

The examples are drawn by hand rather than lifted from a real grid, since a
real one comes with sixty other cells to look past. The names are the ones
Sudoku players use, so a page is also somewhere to start if you want to read
more about one elsewhere.

## Checking, and what it costs

`c` calls out the digits that disagree with the answer. It turns a guess into
a free question, so it is not free, and it is not a switch either: checking
goes on and stays on for the rest of the puzzle.

Because of that, the first `c` only says what the second one would do:

```
 Checking stays on for good, and an aided game is not timed.
 Press c again to switch it on.
```

Where there are already more wrong digits than the allowance covers, it says
so plainly instead, since the second `c` would end the puzzle rather than
start anything:

```
 Checking would find 5 wrong, which forfeits the puzzle.
 Press c again if you mean it.
```

Unlike the warning about hints, this one comes every time checking is asked
for, which is once: it is the last chance to not do it.

```
 S U D O K U    Hard    checking 2/3
```

Three wrong digits are yours to spend. The fourth forfeits the puzzle, which
ends where it stands, with the board left as it was so you can see where it
went. The tally sits on the title line from the moment checking is switched
on, and turns red when there is nothing left to spend.

Wrong digits written before checking is asked for are free — with it off the
game is saying nothing about whether a digit is right, so nothing is owed.
Switching checking on charges for every wrong digit it finds sitting there,
all at once: without that, guesses could be banked up and cashed in for a
keystroke's worth of answers, and the price would be no price at all.

Finding more than the allowance forfeits the puzzle on the spot, the same as
writing one too many would — there is no carrying a debt the game will not let
you pay off. So checking is worth asking for early, while there is nothing to
find, rather than saving it up for a grid gone wrong.

Spending the last of the allowance is not the end: at `checking 3/3`, in red,
you are still playing, and putting the grid right costs nothing, though the
tally stands. It is the next wrong digit that ends it.

Undo takes back the digit but not the mistake: it was checking that told you
the digit was wrong, and undo cannot untell you. A wrong digit caught this way
also keeps the marks around it, which is the other half of the same bargain —
see below.

## Putting a puzzle down

Quitting an unfinished game keeps it. The menu offers it back next time:

```
    r  Resume    Hard, 24 to go, 12:04
```

Everything that cannot be worked out again goes into the file: the clues, the
answer, what has been written and pencilled in since, where the cursor was,
how long it has taken, and what the game has cost in mistakes and hints. The
undo history does not — it is the longest thing in a game by far and the least
missed, and nobody picks up a day-old puzzle in order to walk it backwards.

The file is a few lines of text under `XDG_DATA_HOME`, or `~/.local/share` if
the environment does not name one, and it is meant to be readable:

```
sudoku 1
origin medium
clues ...5....3.4..6.82.75...86...3...5...8956.1374...4...9...69...38.28.1..6.3....6...
answer 682549713943167825751238649134795286895621374267483591476952138528314967319876452
board ...5....3.4..6.82.75...86...3...5...8956.1374...4...9...69...38.28.1..6.3....6...
marks 0:1269 1:168 2:129 4:2479 5:2479 6:1479 7:14 9:19 11:139
cursor 19
clock 4
checking yes
wrong 0
hints 0
```

Being readable cuts both ways, so a file is checked before it is trusted: the
answer has to be an answer, the clues have to be that answer's clues, and what
has been written in has to agree with them. A file that fails is not a saved
game, and the menu simply does not offer one.

Finishing a puzzle clears it, and so does asking for another with `n` — that
abandons a puzzle rather than putting it down, and there is nothing to come
back to. Which is why `n` asks twice while a puzzle is under way:

```
 Press n again to give up this puzzle.
 Nothing of it is kept.
```

`n` is next to `m` on the keyboard, and reaching for marking and missing
should not cost an hour. A puzzle nothing has been done to, or one already
over, is given up at once — there is nothing to lose by asking.

On the way out the game prints the puzzle it was playing, as the same
81-character line `Custom` takes:

```
Thanks for playing.

Saved in /Users/you/.local/share/sudoku/game

This puzzle:
...5....3.4..6.82.75...86...3...5...8956.1374...4...9...69...38.28.1..6.3....6...
```

That is the line to send someone when you want them to try the grid that beat
you — and `gleam run -- <the line>` is how they play it, rather than typing
eighty-one characters into `Custom` by hand. A line that is not a puzzle with
exactly one answer is refused with the same words the editor uses.

## When the terminal gets in the way

`Ctrl-L` wipes the screen and draws it again, which is the only thing to be
done about a mess made by something other than the game — a notification
painted over the board, or a multiplexer that has lost its place. It works
wherever it is pressed: the menu, the editor and the board are all drawn the
same way.

The menu says so when the window is too small for the game to land in
properly, since the alternative is a layout wrapped into nonsense with no
explanation:

```
 This window is 60 by 20, and the game wants 78 by 24.
```

A terminal that will not say how much room it has is taken at its word and
left alone.

## Best times

A puzzle solved unaided is timed, and the menu shows what there is to beat:

```
    1  Easy      naked singles           best 09:12
    2  Medium    hidden singles
    3  Hard      locked candidates       best 21:21
```

Unaided means the game was never asked for anything: no hints, and checking
never switched on. The game says which it is while you play, beside the
difficulty, rather than leaving it to the panel at the end. Both of those work from the answer, and a time set with the
answer to hand is not a time. Filling the candidates in with `f` is another
matter and does not count against you, since it works out nothing you could
not have worked out yourself with a pencil.

A solve with help says so rather than quietly going unrecorded:

```
 Solved in 12:04, with one hint. Not recorded: unaided solves only.
 n new puzzle  │  q quit
```

A puzzle typed in is not timed either: `Custom` has no difficulty to file a
time under. Which is the point of the levels meaning something — two Hard
times are worth comparing now that every Hard asks for locked candidates and
nothing worse.

## Typing a puzzle in

`Custom` on the menu opens an empty grid to type a puzzle into instead of
dealing one:

```
 S U D O K U    Custom    editing

   clues
     1 2 3   4 5 6   7 8 9
   ┌───────┬───────┬───────┐
 A │ 5 3 · │ · 7 · │ · · · │
 B │ 6 · · │ 1 9 5 │ · · · │
 C │ · 9 8 │ · · · │ · 6 · │
   ├───────┼───────┼───────┤
 D │ 8 · · │ · 6 · │ · · 3 │
 E │ 4 · · │ 8 · 3 │ · · 1 │
 F │ 7 · · │ · 2 · │ · · 6 │
   ├───────┼───────┼───────┤
 G │ · 6 · │ · · · │ 2 8 · │
 H │ · · · │ 4 1 9 │ · · 5 │
 I │ · · · │ · 8 · │ · 7 9 │
   └───────┴───────┴───────┘

 clues 30  │  clashes 0  │  cell A1
 arrows/hjkl move  │  1-9 type  │  0 gap  │  p play  │  ? help  │  q quit
```

The cursor steps on by itself after every key, so a row is nine keystrokes and
the whole grid eighty-one, read straight off the page. `0` or space leaves a
gap; the arrow keys go back over anything mistyped.

| Key | |
| --- | --- |
| `←` `↑` `↓` `→`, `hjkl`, `wasd` | move the cursor |
| `1`–`9` | type a clue in and step on to the next cell |
| `0`, space, backspace | leave the cell empty and step on |
| `u` | undo |
| `x` | clear the grid and start over |
| `p` | play the puzzle |
| `n` | back to the menu |
| `?` | help, and the techniques a page at a time |
| `q` | quit |

`p` starts the game, but only once the clues hold together. Two of the same
digit in a row, column or box turn red as they are typed, and the puzzle has
to have exactly one answer before it can be played — the game needs to know
the answer for checking and hints, and insisting on one catches the usual
slips in copying a puzzle down. A mistyped digit leaves the grid with no
answer at all, and a missed one leaves it with several; either way the status
line says which it is and the clues stay put to be fixed.

Once play starts, a typed-in puzzle is like any other: the clues are fixed,
and undo, marks, checking, hints and the clock all work the same. The header
says `Custom` where it would otherwise name a difficulty.

## Pencil marks

Press `m` to switch to marking, then `1`–`9` to pencil candidates into a cell
and the same key again to rub one out. `m` switches back to writing digits;
the header and the key hints along the bottom say which mode you are in.

Shift and a digit pencils one in without leaving writing, and rubs one out
without leaving marking, which saves a great deal of switching now that `f`
fills the candidates in and marking is mostly rubbing them out again. What
the shifted number row produces depends on the keyboard, so both the Swedish
row and the American one are read: `!` is a 1 on either. Where the two
disagree — `(` sits over 8 on one and 9 on the other — the Swedish reading
wins, there being no way to tell which keyboard is in front of the player.
Anyone whose row is neither still has `m`.

Marks get a grid of their own beside the board rather than being squeezed into
it, which leaves the board as compact and readable as it was without them. The
two grids are the same shape and share the cursor and its shading, so a cell in
one is easy to find in the other. A cell given a single reading shows that
digit; a cell given several shows `*`. Move onto it and the status line spells
its marks out in full:

```
 empty 45  │  clashes 0  │  time 00:00  │  A1 marked 1 3 5
```

Writing a digit tidies up after itself: the cell's own marks go, and so does
that digit's mark in every cell that can see it. Not while checking is on and
the digit is wrong, though — the marks around a digit the game is calling out
in the same breath are the reasoning you need to put it right, so they stay
where they are. Erasing a digit leaves marks alone too, so taking back a
wrong guess does not cost you the reasoning behind it. Undo covers marks as
well as digits, and `r` walks forward again through whatever was undone —
until something else is written, which makes a different way forward and
throws the old one away.

## How it works

| Module | |
| --- | --- |
| `sudoku/board` | the grid, its units, pencil marks, and what counts as a clash |
| `sudoku/solver` | backtracking search, and counting solutions |
| `sudoku/generator` | filling a grid at random, then carving clues out of it |
| `sudoku/logic` | solving the way a person does, and rating a puzzle by it |
| `sudoku/game` | game state and what each key does to it |
| `sudoku/editor` | typing a puzzle in by hand |
| `sudoku/store` | writing a game down, reading it back, and keeping times |
| `sudoku/render` | drawing a frame |
| `sudoku/help` | the keys, the techniques, and the pages that explain them |
| `sudoku/grids` | drawing a nine by nine, for the board and the help alike |
| `sudoku/palette` | the colours it is all drawn in |
| `sudoku/key` | decoding bytes into keystrokes |
| `sudoku/term` | raw input and ANSI escapes |

Pencil marks live on the board rather than in the game around it, which is
what lets undo capture them without any extra bookkeeping. Both grids come out
of one function that takes the cell renderer as an argument, so they cannot
drift apart in shape, and the editor draws its grid with the same function
again.

A puzzle carries where it came from, `Dealt(difficulty)` or `Handwritten`,
which is all that separates a typed-in puzzle from a generated one once play
begins. Generating one carves clues out of a solution; typing one in works the
other way round, solving the clues to find the answer the game will check
against, and refusing them if there is not exactly one.

There are two solvers, because there are two questions. `sudoku/solver`
searches, expanding the empty cell with the fewest candidates first, and
answers what the digits are; it is what fills a grid at random to start a
puzzle off. `sudoku/logic` reasons, trying naked singles, hidden singles,
locked candidates, pairs, triples and X-wings in that order, and answers how
the digits can be worked out and how hard that is. Rating a grid that way
takes about a millisecond, which is what makes it affordable to ask the
question after every single cell carving takes out.

Generation fills a grid at random and then removes cells in rotationally
symmetric pairs, and singly where a pair will not go, for as long as the
puzzle stays inside its difficulty. Carving is greedy and often lands easier
than the level wants, so it carves up to thirty grids and keeps the hardest —
which is why an Expert puzzle takes about a second to deal and an Easy one
arrives at once.

Keyboard input needs OTP 26 or later, which is where
`shell:start_interactive({noshell, raw})` arrived. Without it — on older OTP,
or when input is piped rather than typed — the game still runs, but each key
has to be followed by Enter, and it says so on the menu.

## Development

```sh
gleam run   # Play
gleam test  # Run the tests
```

Tests live beside the subject they are about — `board_test`, `logic_test`,
`hint_test` and the rest — with the puzzles and fixtures they share in
`helper`. Gleeunit runs every function ending in `_test` anywhere under
`test`, so `sudoku_test` holds nothing but the call that starts them.
