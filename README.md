# sudoku

A Sudoku game for the terminal, written in Gleam.

```sh
gleam run                     # choose a puzzle from the menu
gleam run -- hard             # deal one at that difficulty
gleam run -- custom           # type a puzzle in
gleam run -- resume           # pick up the game you left
gleam run -- daily            # the puzzle everybody gets today
gleam run -- daily 2026-09-17 # the one belonging to that day
gleam run -- 53..7....6..1..  # play that puzzle, dots for the blanks
gleam run -- hard --seed 7    # deal the puzzle that seed deals
gleam run -- --plain          # draw without colour
gleam run -- --help           # say all this and stop
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
| `Home`, `End` | to the ends of the row |
| `Tab`, `Shift-Tab` | to the next cell left empty, or the one before |
| `1`–`9` | write a digit, or pencil one in while marking |
| `M` then `1`–`9` | pencil one digit in, or rub it out |
| `0`, space, backspace | clear the cell, or its marks while marking |
| `f` | pencil the candidates into every bare cell |
| `S` then `1`-`9` | mark out where that digit can still go |
| `m` | switch between writing and marking |
| `u` | undo |
| `r` | do it again |
| `c` | check what is filled in from here on, at a price (press twice) |
| `H` | take the next step, and say why |
| `R` | reveal the whole solution (press twice) |
| `p` | pause: put the board away and stop the clock |
| `X` | start this puzzle again (press twice) |
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

## Colour

The game asks the terminal how much colour it has and draws three different
ways.

| | washes | the column in front of a cell |
| --- | --- | --- |
| 256 colours | four, one per kind | a space |
| 16 colours | one grey, all four kinds | `›` for a hint, `+` for a scan |
| none | none | `›` for a hint, `+` for a scan |

The washes behind the board — the cursor's row and column, a hint's cells,
where a digit could still go — are 256-colour greys, and a terminal with
sixteen draws them as nothing at all. Not wrongly: simply not at all, which
is the worst way for a thing to go missing, since the screen still looks
coloured and the shading that was the answer is just not there.

Sixteen colours hold exactly one background that is neither the terminal's
own nor a shout, so under them the four washes become that one grey and stop
saying which kind they are. What the two that were saying something lose by
merging they get back as a mark in the column in front of the cell — the
same mark a terminal with no colour at all has always been given.

`TERM` naming 256 colours is how a terminal claims them, and `COLORTERM`
being `truecolor` is the newer way. A terminal that misdescribes itself is
common enough to be worth a way round:

```sh
SUDOKU_COLOURS=full   # or basic, or none
SUDOKU_COLORS=full    # spelled the other way, which also works
```

`NO_COLOR` wins over all of it, as does `--plain`.

### Changing the colours

All of this assumes a dark screen. On a pale one the dim greys are close to
invisible, and there is nothing to be done about that from inside the game —
so it can be done from outside it, in `~/.config/sudoku/palette`:

```
# A name and the SGR codes it should be drawn with.
dim     37
given   1;30
title   1;34

# The one grey a sixteen-colour terminal washes with.
wash    47
```

Blank lines and anything behind a `#` are passed over, and so is a line
naming a colour the game does not have. The names are:

```
given  entered  conflict  alarm  wrong  key  best  note
empty  dim  title  good  mark  cursor
peer_wash  match_wash  hint_wash  scan_wash  wash
```

The file is read once, when the game starts. Only colours can be set: `·`
and `›` and the rest stay where they are, because a colour that is wrong is
ugly and a character of the wrong width takes the grid apart.

## The daily puzzle

One puzzle a day, the same one for everybody, carved from the date.

```
   7  Daily     Thursday 2026-09-17, Medium        done in 08:41
```

Because everybody gets the same grid, it cannot ask which difficulty you
fancied, so it ramps through the week the way a newspaper's does:

| | Mon | Tue | Wed | Thu | Fri | Sat | Sun |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | Easy | Easy | Medium | Medium | Hard | Expert | Master |

An easy Monday for somebody on a train, and a Sunday that is an afternoon.
Every level turns up in a week, so playing nothing but the daily is not a way
of never meeting an X-wing.

The nine techniques fill the practice screen's digits exactly, which is the
ceiling on that screen rather than on the reasoning: a tenth would be one
nobody could press a key for.

Naming the date plays that day's, which is what two people use when their
calendars have already disagreed about what day it is — the day is taken from
the clock where the player is sitting, not from UTC, because a daily belongs
to somebody's morning rather than to a moment. It is also how you go back to
one you missed.

```
   8  Daily     Friday 2026-09-18, Hard    done in 01:01, 3 days running
```

The run of days is counted back from today, and it is the only number on
that line anybody can do anything about today. A day nobody has played yet
is not a day missed: a run that reached yesterday goes on standing while
today is still going on, since telling somebody their run had ended every
morning before they had had a chance to keep it would be the surest way to
make them stop. A day actually missed does end it.

Nothing is stored for it. The book of days already knows every day that was
done, so the run is worked out from it rather than kept beside it, and there
is no second number to come apart from the first.

Its times are kept in a book of their own rather than among the levels' best
times. A best is the quickest of many puzzles at a level and goes on being
beaten; a day is one puzzle that happened once, and its time is a fact about
that day rather than a record standing until something betters it. The first
run at a day is the one written down — a day played twice is a day you have
already seen the answer to, and a quicker second run at it is not a quicker
solve.

Everybody running this version, at any rate. The date steers the carving, and
changing how the carving works would steer it somewhere else: two people
comparing times should be on the same version, the same as they would be
comparing crosswords out of the same edition.

## Dealing the same puzzle twice

Every deal is carved from a seed, and the game says which as it leaves:

```
This puzzle:
3.5.89.7.47..5.2.89.264...112.....46...5.6...56.....392...354.76.1.2..83.4.96.1.5

Dealt at Easy from seed 42, which deals it again.
```

Hand the seed back beside a difficulty and the same puzzle comes out.
`--seed=42` says it the other way round, and either can sit on either side of
the difficulty, the way `--plain` can. A seed names a deal rather than a
puzzle, so it wants a difficulty beside it to name the deal of; `--seed 42
custom` is refused rather than quietly ignored, since the grid you then type
in would be nothing to do with the number you asked for.

Both halves of that line are worth having and they are for different people.
The eighty-one characters go to somebody who has never run this and never
will — they are a puzzle, and any program that takes one will take them. The
seed goes back to this game: it is shorter, it survives being read out over a
telephone, and it says what the puzzle *is for*, which is a deal at a
difficulty rather than a grid that happens to be hard.

It is also the only way to hand back a deal rather than its result. A deal
that took eight seconds, or came out a shade easier than its level promised,
cannot be looked into from the grid alone — the grid is what survived thirty
carvings, and the question is about the other twenty-nine. The seed carves
them again.

The game remembers the seed of a game you put down, so a puzzle picked up a
week later still knows how it was dealt. Nothing else has one: a grid typed
in was not dealt from anything, and a practice grid is the same grid every
time without any chance involved in it.

## Difficulty

A difficulty is not a clue count. It is the hardest reasoning a puzzle will
ask of you, which is the thing a clue count only gestures at: two puzzles with
the same number of clues can be a minute apart or an hour.

| | asks for | clues | carving |
| --- | --- | --- | --- |
| Easy | naked singles | 39–40 | instant |
| Medium | hidden singles | 31–32 | instant |
| Hard | locked candidates | 26–27 | about a third of a second |
| Expert | naked pairs and better | 22–27 | half a second or so |
| Master | XY-wings and better | 22–27 | a second or two |

Each level is what it says: measured over twenty-five puzzles apiece, every
Easy needed nothing but naked singles, every Medium wanted a hidden single
somewhere, every Hard a locked candidate, and every Expert a pair or better,
up to the occasional X-wing. Every Master wanted an XY-wing at least — the
first technique here that is not read off a single unit — and one of the
twenty-five wanted a swordfish.

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

Carving is greedy and takes what it is given, so a grid often lands easier
than its level wants and the answer is to carve another and keep the harder
of the two. Up to thirty of them, which is why a Master deal takes a second
or two where an Easy one arrives at once. The screen says so while it
happens, rather than sitting still and hoping you wait:

```
 Carving out an Expert puzzle...

 Grid 7 of 30, and the best so far asks for hidden singles.
 Each is carved as far as it will go, and the hardest of them kept.
```

The count moving says the game is working. What the best of them asks for so
far says what it is working towards, and why it has not stopped yet: this one
is still short of the naked pair an Expert puzzle promises. It stops the
moment a grid is hard enough, so the count is rarely thirty — twenty-three
was a bad day.

## Practice

The help explains every way of working a digit out and draws a small board
showing each one happening. What it could not do was hand you one to try. An
X-wing turns up in about one dealt Expert puzzle in fifteen, so reading the
page and then waiting for one to come round is not a plan.

```
 Practise which technique?

    1  Naked single        40 clues
    2  Hidden single       32 clues
    3  Locked candidates   48 clues
    4  Naked pair          53 clues
    5  Hidden pair         53 clues
    6  Naked triple        44 clues
    7  X-wing              57 clues
    8  XY-wing             51 clues
    9  Swordfish           60 clues
```

One grid apiece, the same one every time. Each was carved until the reasoning
needed its technique and needed nothing harder, and then given back every
clue it could take while that stayed true — so they are the gentlest grids
that still force their lesson. The X-wing one has fifty-seven clues and wants
its X-wing on the second step, rather than being a seventeen-clue monster
that happens to contain one somewhere in the middle.

Needing the technique is a guarantee rather than a hope. The reasoning always
takes the easiest step going, so if it had to reach for an X-wing, nothing
simpler was available at that moment, and you will have to reach for one too.

The clue counts are there because they are the other half of how hard a grid
is, and they are nothing to do with how hard its technique is: the X-wing
grid is the fullest of the lot and the hidden-single grid the barest.

Each technique page in the help ends with the two keys that reach its grid,
and while you are playing one, `?` opens the page about the technique you
picked rather than the key reference. Practice is not timed and no record is
kept of it — it is the same grid every time, so a time on it would be a
record of having seen it before.

## Looking for somewhere a digit can go

Pick a digit and sweep the grid asking "where can a 7 still go in this box?"
That is how hidden singles and locked candidates are actually found by eye,
and it is the one move the board gave no help with: standing on a 7 shades
every other 7, which is where they already are, not where one could go next.

`S` and then a digit shades every empty cell that digit could still go in,
and keeps them shaded while you move around looking at them. `S` again stops.

```
 S U D O K U    Custom    looking for 7

 A │ 3 · · │ + + 9 │ + 1 + │
 B │ · · 7 │ · · · │ 3 · 4 │
 C │ · · 5 │ 3 8 + │ + + + │

 Looking for somewhere a 7 can go.
 22 cells can take it. Press S again to stop looking.
```

Rows B, D and I have their 7 already, so nothing in them is shaded; nor is
anything in the three columns and the two boxes that have one. Move onto one
of the shaded cells and it keeps a `+` where the shading was, since the
cursor sits on top of any colour underneath it. The sevens
already on the board keep their own shading, so both halves of the answer are
on screen at once — where the digit has got to, and where it could still go.

While a scan is up, the shading behind the cursor's own row, column and box
goes away. Nine shaded cells and three shaded units at the same time is a
mess, and the scan is the thing that was asked for.

It reads the grid and nothing else. What you have pencilled in is your
reasoning, and reasoning can be wrong; where a digit can go is a fact, and a
mark made wrongly should not be able to turn it into an opinion.

And it costs nothing — no hint, no aided game, no time lost. What a cell can
take is there to be read off its row, its column and its box by anybody
willing to look, which is the same argument that makes `f` free. `f` gives
away rather more, in fact: once the candidates are pencilled in, every hidden
single in the grid can be found by counting.

Only the digit pressed straight after `S` chooses what to look for. Anything
else and the scan is forgotten, and that keystroke does what it always does —
a scan is a way of looking at the board, not a mode to be in. Digits written
while one is up are written as normal, and the shading follows the grid as it
changes.

## What is left to place

Under the board is a line saying how many of each digit are still to come:

```
 empty 41  │  clashes 0  │  time 00:01
 left  1×5   2×5   3×3   4×6   5×1   6×5   7×5   8×7   9×4
```

`5×1` is the useful one there. A digit down to its last cell is the one to
go hunting for, and the line puts that under your nose rather than leaving
you to count the fives for the fourth time. Counting them is the commonest
thing a player does that is not thinking, and counting them wrong sends you
looking for a five that is already on the board.

It is free by the same reckoning that makes `f` and `S` free: anybody can
count the fives. What it counts is what is on the board rather than what is
right about it — a wrong digit is still a digit somebody has to take back,
and a tally that quietly ignored one would be checking, which is not free.

Every digit keeps its place in the line whether it has any left or not, so
the one you are looking for is where it was a minute ago. A digit with none
left shows the dot an empty cell shows, which is the same thing said about a
digit rather than about a square:

```
 left  1×6   2×7   3×6   4·   5×6   6×4   7×6   8×4   9×5
```

The line goes when the puzzle is over, there being nothing left to place and
the panel saying how it went wanting the room.

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

If an empty cell has nothing left that can go in it — its row, its column and
its box holding all nine digits between them — `f` says so:

```
 Pencilled in 31 cells.
 Nothing can go in D7: something already written must be wrong.
```

That is the same kind of fact as the clash counter: anybody can see it by
looking at the cell, and it says the grid is broken without saying which
digit broke it. Naming the wrong digit is checking, and checking is not free.

Such a cell is not one waiting to be pencilled, so it no longer counts as
one. It used to: `f` reported filling it, put nothing in it because nothing
would go, and left it bare — so something was always still bare and the offer
to mark every cell afresh, which only comes when nothing is, could never
arrive.

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
playing, and eight pages is long enough that it would otherwise show. `p`
does the same thing on purpose — see below.

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

## Pausing

`p` puts the board away and stops the clock. Any key picks it up again.

```
 S U D O K U    Medium

 Paused

 The board is put away and the clock has stopped at 04:12.

 Press any key to carry on, or q to quit.
```

The board going away is not politeness, it is the whole reason this can be
offered at all. A pause that left the grid on screen would be a way of
thinking about a puzzle for nothing, and a best time is only worth having if
the clock cannot be talked out of running. You cannot work on a grid you
cannot see, so there is nothing to gain by pausing and nothing to lose by it
either.

The game never guesses at this. It only ever hears from you when you press a
key, so a long silence could be a phone call or it could be somebody staring
hard at the same box for five minutes, and it has no way to tell the two
apart. Rather than guess, it waits to be told. The cost is that you have to
remember to press `p` before the doorbell goes; the gain is that the clock
never stops for a reason the game invented.

The time shown on the paused screen is the time at the moment you pressed
`p`, and it stays there. Nothing is drawn again until a key arrives, and by
then the waiting has already been given back.

The clock on the board does move, on its own, once a second. It used to sit
still between keystrokes — the game drew a frame when it was given a key and
at no other time, so a player sitting and thinking watched a clock that had
stopped at whatever second they last typed in. The time was right all along,
being counted from when the puzzle was dealt; it was only the reading of it
that was old, which is the one way for a clock to be wrong that nobody
forgives.

It waits for whatever is left of the second and then draws, so the frame is
new exactly when the time on it would be. Nothing else about the game moves
in the meantime: no key is invented to go with the frame, so an offer made a
moment ago is still standing when you answer it.

## Putting a puzzle down

Quitting an unfinished game keeps it, and so does playing one: the file is
written as you go, whenever something has happened that it would say
differently. The menu offers it back next time:

```
    r  Resume    Hard, 24 to go, 12:04
```

Each game gets a file of its own, named for the second it started, the
process it was played in and a count — enough that two games being played in
two terminals cannot write over one another. A game picked up again goes back
into the file it came out of rather than forking into a second one.

Where there is more than one to come back to, `r` asks which:

```
 Which game do you want back?

    1  Hard, 24 to go, 12:04
    2  Easy, 40 to go, 03:20

    The one put down most recently is first.
```

The menu says `Resume    one of 2 games put down` rather than picking one of
them to describe. Nine are kept, that being how many a screen can put a digit
in front of; starting a tenth forgets the oldest. `gleam run -- resume` cannot
be asked which and takes the most recent.

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
aided yes
wrong 0
hints 0
```

Writing it as the game goes is what makes the file worth anything when the
game does not get to the end. A terminal closed on a whim, a laptop shut, a
connection dropped, a fault in here — none of them come by on the way out to
put the puzzle down, and an hour of somebody's work should not hang on the
game being allowed to finish its sentence.

Nothing is said about any of it while it happens. A game put down on purpose
is worth a line saying where it went, and there is one; a game written down
forty times an hour is worth nothing being said at all. A write that fails is
simply not counted as written, so the next move tries again, and the line on
the way out still answers for the last of them.

The clock is the one thing in the file that moves on its own, and it is not
worth a write by itself — except that leaving it would make a dead terminal
into a way of stopping the clock without pressing `p`. So the file is brought
up to date whenever it would otherwise hand back more than half a minute.
What a crash costs is thirty seconds of the clock and nothing of the grid.

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

`R` asks twice for the same reason, and with better cause: it is `r` with a
thumb on shift, and `r` is the key you press over and over walking forward
through undone moves. The slip fills the answer in and ends the puzzle, and
a game that is over cannot be walked back out of.

```
 Press R again to fill the answer in.
 That is the end of this puzzle.
```

`X` starts the same puzzle again: the grid goes back to the clues it was
dealt with, and the puzzle stays. It asks twice as well, since it throws away
exactly as much of the grid as giving up does.

```
 Press X again to start this puzzle over.
 The grid goes back to its clues. The clock does not go back.
```

That last line is the whole of the difference between starting the grid again
and starting the game again. The clock runs on, the mistakes stand, checking
is still on if it was on, and a game helped along is still an aided one — a
grid that could be wiped for a fresh clock would be a way of stopping time
without pressing `p`, and `p` puts the board away for a reason. What `X` gives
you is the puzzle back, not the hour back.

It is one `u` away all the same, the way marking everything afresh is. Asking
twice is for meaning it; it is not a reason to make a slip final.

On the way out the game prints the puzzle it was playing, as the same
81-character line `Custom` takes:

```
Thanks for playing.

Saved in /Users/you/.local/share/sudoku/game

This puzzle:
...5....3.4..6.82.75...86...3...5...8956.1374...4...9...69...38.28.1..6.3....6...
```

That sentence is the answer to whether the write happened, not a guess at it.
Where the file cannot be written — a directory that is not writable, a disk
with nothing left on it — the game says so instead, and the puzzle line is
still there to keep by hand:

```
Could not save in /Users/you/.local/share/sudoku/game.
```

The same goes for a record. A best time that the books would not take is
still a best time, and the panel says both halves of that rather than the
flattering half:

```
 Solved in 08:41! Your best yet, but it could not be saved.
```

That is the line to send someone when you want them to try the grid that beat
you — and `gleam run -- <the line>` is how they play it, rather than typing
eighty-one characters into `Custom` by hand. A line that is not a puzzle with
exactly one answer is refused with the same words the editor uses.

## What the command line answers with

`--help`, or `-h`, prints the ways to start the game — the block at the top
of this page — and stops. It is a question rather than a mistake, so it goes
to standard output and the game exits 0, and nothing typed beside it can turn
it into a mistake: neither a puzzle, nor a flag that would have been one on
its own.

A command line the game cannot read is the other way round: the same usage,
printed to standard error, and an exit code a shell can notice. Asking to
resume with nothing to resume is a refusal of that kind too, since something
was asked for and could not be given:

```sh
$ gleam run -- resume
There is no game waiting to be picked up.    # on standard error, exit 1
```

That matters for the one way this game gets scripted: `gleam run -- <puzzle>`
with a line somebody sent you. A puzzle that turns out not to be one now says
so where a script can hear it.

## When the terminal gets in the way

`Ctrl-L` wipes the screen and draws it again, which is the only thing to be
done about a mess made by something other than the game — a notification
painted over the board, or a multiplexer that has lost its place. It works
wherever it is pressed: the menu, the editor and the board are all drawn the
same way.

The game says so when the window is too small for a frame to land in
properly, since the alternative is a layout wrapped into nonsense with no
explanation. On the menu it goes under the choices; on the board and in the
editor it takes the bottom line, the one the keys are usually on:

```
 This window is 60 by 20, and the game wants 80 by 24.
```

The keys are a reminder, and the least missed line on the screen. A board
wrapped into nonsense is a puzzle about the terminal rather than about
Sudoku, and worth saying out loud.

Eighty by twenty-four is what a terminal has been by default since before
any of them had a screen, and the game keeps every line it draws inside it
with a column to spare. A frame's lines are written with a leading space, so
the longest of them — the wordiest a hint has: a hidden single named, argued
and accounted for — comes to seventy-nine.

The size is asked for afresh every frame, so a window resized in the middle
of a puzzle is noticed, and the line goes again when the room comes back.
Within a second of letting go of the window edge, that being how often a
frame lands while the clock is running. On a screen with no clock on it —
the menu, the editor, a pause — it waits for a keystroke, and `Ctrl-L`
counts as one.

A terminal that will not say how much room it has is taken at its word and
left alone. One that answers about its width but not its height is half
taken at its word — `This window is 60 by ?`.

## Without colour

`--plain` draws the game in no colour at all, and so does setting `NO_COLOR`
in the environment, which is the usual way of asking for that. The flag can
come before or after a puzzle, since it says how the game should look rather
than what it should deal.

What goes is hue; what stays is shape. Bold, dim, underline, reverse video
and strikethrough are not colours, and a terminal that will not show green
will still show those — so the board keeps every distinction it was making:

| | in colour | plain |
|---|---|---|
| a clue | bold white | bold |
| a digit you wrote | cyan | plain |
| a digit that clashes | red, struck through | struck through |
| a wrong digit, while checking | red, underlined | underlined |
| the cursor | reverse video | reverse video |

That was the reason for striking a clashing digit through rather than only
reddening it, and for underlining a wrong one: each of the three states a
digit can be in has a shape of its own, so none of them depends on the colour
being seen.

The one thing with no shape to fall back on is the wash behind the cells a
hint is arguing from. There is nothing to shade with, so the column in front
of each cell — a space, normally, which is what makes a wash read as a solid
block — points instead:

```
 A │ 8 · 5 │ · 1 · │ 4 6 · │
 B │ · 4 6 │ 8 5 · │ 3 7 1 │
 C │›·›7›3 │›·›·›4 │›8›5›· │
```

`Hidden single: C2 is the only cell in row C that can take a 7.` — and there
is row C. The pointer goes where the space was, so the grid is exactly as
wide either way.

A scan gets its own mark in the same column, `+`, since the two can be up at
once and a cell a hint is arguing from is not the same as a cell a digit
could go in.

One cell gets a mark in colour too: the one the cursor is on. Its colour is
spoken for by the cursor, which is reverse video and shows through nothing,
and it is the cell the player most wants an answer about — they went there to
look at it. Without the mark, the one cell a scan could not tell you about
was the one you were standing on.

The washes behind the cursor's row and column, and behind cells holding the
same digit as the one under it, simply go. They are there to help the eye
wander rather than to say anything, and an eye can wander without them.

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
the whole grid eighty-one, read straight off the page. `0`, space, `.` or `_`
leaves a gap; the arrow keys go back over anything mistyped.

Because a dot counts as a blank, a whole puzzle can be pasted in as the same
81-character line the game prints on its way out — the one somebody hands
you. Anything that is neither a digit nor a blank is ignored and does not
step the cursor on, so a line that arrives with a stray character in it does
not shunt everything after it along a cell. (Spaces do count as blanks, so a
grid pasted in with gaps between the bands is the one layout that will not
come out right; paste the unspaced line.)

| Key | |
| --- | --- |
| `←` `↑` `↓` `→`, `hjkl`, `wasd` | move the cursor |
| `Home`, `End` | to the ends of the row |
| `1`–`9` | type a clue in and step on to the next cell |
| `0`, space, backspace, `.`, `_` | leave the cell empty and step on |
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

`M` and a digit pencils one in without leaving writing, and rubs one out
without leaving marking, which saves a great deal of switching now that `f`
fills the candidates in and marking is mostly rubbing them out again. It asks
which digit and takes the next one as the answer, the way `S` does, and that
is the whole of it: anything but a digit means you have gone back to playing,
and `M` again takes the question back.

Shift and a digit does the same in one keystroke, where the keyboard is one
the game can read. What the shifted number row produces depends on the
layout, so both the Swedish row and the American one are read, and `!` is a 1
on either. Where the two disagree there is nothing in the byte that arrived to
say which key was pressed — `&` sits over 6 in Stockholm and 7 in Seattle — so
those are let go rather than guessed at. Guessing would be wrong for half the
keyboards in the world and quietly wrong at that: a 6 pencilled in where a 7
was asked for reads like a slip of the hand rather than a game that cannot
tell. `M` is the way in that no layout can get wrong, and `m` is still there
for a whole row of them at a time.

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
wrong guess does not cost you the reasoning behind it — and erasing gives the
digit back to the marks around it, since it was the game that took it out of
them when the digit went in. Without that, every digit written and thought
better of would leave a hole in the marks that nothing would ever fill, and
the holes would collect until the marks said things that could not be true. Undo covers marks as
well as digits, and `r` walks forward again through whatever was undone —
until something else is written, which makes a different way forward and
throws the old one away.

Both of them take the cursor to the cell that changes. The pile holds where
you were looking along with the board, so undoing a digit you wrote ten cells
ago puts you back at it rather than changing the board somewhere off screen
and leaving you to find out. Redo goes to the same cell, whichever way the
pile is being walked.

## How it works

| Module | |
| --- | --- |
| `sudoku/board` | the grid, its units, pencil marks, and what counts as a clash |
| `sudoku/solver` | backtracking search, and counting solutions |
| `sudoku/generator` | filling a grid at random, then carving clues out of it |
| `sudoku/logic` | solving the way a person does, and rating a puzzle by it |
| `sudoku/game` | the state of a game, and the plain facts about it |
| `sudoku/rules` | what each key does to it |
| `sudoku/hint` | turning the reasoning into a hint, and pointing it somewhere |
| `sudoku/invocation` | reading what the command line asked for |
| `sudoku/editor` | typing a puzzle in by hand |
| `sudoku/store` | writing a game down, reading it back, and keeping times |
| `sudoku/render` | drawing a screen: the menu, the board, the editor |
| `sudoku/help` | the keys, the techniques, and the pages that explain them |
| `sudoku/practice` | one grid per technique, kept to be practised on |
| `sudoku/grids` | drawing a nine by nine, for the board and the help alike |
| `sudoku/palette` | the colours it is all drawn in, and what each one means |
| `sudoku/key` | decoding bytes into keystrokes |
| `sudoku/term` | raw input and ANSI escapes |

Those first three used to be one module, and they split the way the sentence
that described it split: the state, the rules for how a keystroke changes it,
and the one rule long enough to want a module of its own. `rules` and `hint`
both reach into `game`; `game` reaches into neither, which is what lets the
three be three rather than a circle. Everything else — drawing, saving,
the record books — still talks to `game` alone and did not notice.

Every screen is drawn by `render` and every colour comes out of `palette`.
That was not always true — the menu drew itself in the main module out of
hardcoded escape codes, which is how it ended up with a slightly different
green from the rest of the game and a yellow complaint about the window where
the board's was red. Colour is a vocabulary, and a screen that keeps its own
copy of it drifts.

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
has to be followed by Enter, and it says so on the menu. The clock holds
still there, since a frame landing on a half-typed line would rub out what
was being typed before Enter handed it over.

The screen is given back whatever happens, the crash included. A game that
falls over on the alternate screen, in raw mode with the cursor hidden,
would otherwise print the report saying what went wrong onto a terminal
that cannot show it, over a shell that looks an hour out of date. The error
is still an error and still reported; it is only reported somewhere it can
be read. Whatever goes wrong while giving the screen back is let go, being
most likely the same thing that went wrong in the first place.

Bytes are read by a process of their own that does nothing else, and posts
each one to the game as it arrives. That is what lets a read give up: the
game waits on its mailbox rather than on the terminal, and a wait on a
mailbox can be given a deadline where `io:get_chars` cannot. A key pressed
while the screen is being drawn waits in the mailbox rather than being lost,
and every read goes through the one reader — two of them on one terminal
would take a byte each in whatever order they happened to be waiting.

## Development

```sh
gleam run   # Play
gleam test  # Run the tests
```

Tests live beside the subject they are about — `board_test`, `logic_test`,
`hint_test` and the rest — with the puzzles and fixtures they share in
`helper`. Gleeunit runs every function ending in `_test` anywhere under
`test`, so `sudoku_test` holds nothing but the call that starts them.

## Licence

MIT. Do what you like with it, and keep the copyright notice — the whole of
it is in [LICENSE](LICENSE), and it is nineteen lines.
