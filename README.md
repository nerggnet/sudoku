# sudoku

A Sudoku game for the terminal, written in Gleam.

```sh
gleam run
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
| `0`, space, backspace | clear the cell, or its marks while marking |
| `m` | switch between writing and marking |
| `u` | undo |
| `c` | check what is filled in from here on, at a price |
| `H` | take the next step, and say why |
| `R` | reveal the whole solution |
| `n` | start a new puzzle |
| `?` | help |
| `q` | quit |

Clues are fixed and cannot be overwritten. Digits that clash with another in
the same row, column or box turn red as you type them, and the cells sharing a
row, column or box with the cursor are shaded so it is easier to see what a
cell can still be.

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

## Hints that explain themselves

`H` used to name a digit and leave it at that, which answers the cell and
teaches nothing. Now it works out the next move the way a person would and
says what it did:

```
 Naked single: C6 can only be a 4.
 Hidden single: A2 is the only cell in row A that can take a 9.
 Locked candidates: every 1 in the top-left box is in row C.
 Naked pair: C8 and F8 take 7 and 8 between them.
 Hidden pair: only C2 and C3 can take 4 or 7 in their row.
 Naked triple: A2, A3 and A4 take 2, 7 and 8 between them.
 X-wing: a 9 in rows B and F keeps to columns 2 and 9.
```

The names are the ones Sudoku players use, so they are worth learning: a
player told that C8 and F8 take 7 and 8 between them has been given this one
move, and a player told it is a naked pair has been given every naked pair
they will ever meet. What follows the name is the crux rather than the whole
argument, because the consequence happens on the screen as it is said — the
digit goes in, or the marks come out.

The hint goes wherever the next move actually is rather than wherever the
cursor happens to be, because the cell you are staring at may not be the one that
can be worked out yet — and a hint that cannot explain itself is only the
answer again.

A hint always moves something. Where the next step settles a digit it writes
it in; where the step only rules candidates out it rubs them out of your
marks, which is what you would do with it yourself. An elimination you have no
marks for would change nothing on the screen and be offered again for ever, so
in that case the hint falls back to naming a digit, the way it always did.
That is also the fallback for a puzzle beyond the reasoning, and for a grid
with a wrong digit already in it: a hint checks every digit against the answer
before writing it, because reasoning from a wrong digit leads somewhere the
answer does not go.

## Checking, and what it costs

`c` calls out the digits that disagree with the answer. It turns a guess into
a free question, so it is not free, and it is not a switch either: checking
goes on and stays on for the rest of the puzzle.

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
| `?` | help |
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
well as digits.

## How it works

| Module | |
| --- | --- |
| `sudoku/board` | the grid, its units, pencil marks, and what counts as a clash |
| `sudoku/solver` | backtracking search, and counting solutions |
| `sudoku/generator` | filling a grid at random, then carving clues out of it |
| `sudoku/logic` | solving the way a person does, and rating a puzzle by it |
| `sudoku/game` | game state and what each key does to it |
| `sudoku/editor` | typing a puzzle in by hand |
| `sudoku/render` | drawing a frame |
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
