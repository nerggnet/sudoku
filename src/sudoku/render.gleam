//// Drawing the board.
////
//// A frame is built as a list of single lines and printed in one write, so
//// the screen never tears. Each line ends with an erase-to-end-of-line and
//// the frame ends with an erase-to-end-of-screen, which means the previous
//// frame does not have to be cleared first.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleam/string
import sudoku/board
import sudoku/editor.{type Editor}
import sudoku/game.{type Game}
import sudoku/generator.{type Difficulty, type Origin}
import sudoku/grids
import sudoku/help
import sudoku/logic
import sudoku/palette
import sudoku/practice
import sudoku/store
import sudoku/term

/// How much room a frame needs: a window this wide and this tall, which is
/// the eighty by twenty-four a terminal has been by default since before any
/// of them had a screen.
///
/// Every line drawn has to be shorter than this rather than as long, on two
/// counts. A frame's lines are written with a leading space, so a line of
/// eighty characters would be eighty-one columns and wrap. And a line that
/// fills the last column leaves a terminal in a wrapping-any-moment-now
/// state, which the escape that ends the line happens to settle — a thing to
/// be right about on purpose rather than by luck.
pub const columns = 80

pub const rows = 24

/// How many columns one grid takes up. Cells are two columns wide, so a band
/// of three plus its trailing space is seven, four box rules bring the row to
/// 25, and the row label and its space make 27.
const grid_columns = 27

/// What separates the board from the marks beside it.
const grid_gap = "    "

/// Render the whole screen.
///
/// The help takes over the screen rather than sitting under the board: the
/// two together are taller than a 24-row terminal.
pub fn frame(current: Game) -> String {
  let mode =
    [
      case current.marking {
        True -> "marking"
        False -> ""
      },
      case current.scan {
        game.ScanningFor(digit) -> "looking for " <> int.to_string(digit)
        _ -> ""
      },
    ]
    |> list.filter(fn(said) { said != "" })
    |> string.join("    ")
  // A game helped along says so beside its difficulty, since that is what
  // the difficulty no longer quite means.
  let named = case game.unaided(current) {
    True -> generator.origin_label(current.puzzle.origin)
    False -> generator.origin_label(current.puzzle.origin) <> " (aided)"
  }

  let head = header(named, mode) |> tallied(current)

  case current.paused, current.help {
    True, _ -> term.screen(list.flatten([head, resting(current)]))
    _, Some(page) -> term.screen(list.flatten([head, help.page(page)]))
    _, None -> {
      let clashes = board.conflicts(current.board)
      term.screen(
        list.flatten([
          head,
          grids(current, clashes),
          status(current, clashes),
          footer(current),
        ]),
      )
    }
  }
}

/// A paused game, which is a screen with no board on it.
///
/// The board going away is the whole point: a pause that left the grid up
/// would be a way of thinking about it for nothing. The time shown is the
/// time at the moment of pausing, and stays that way — nothing is drawn
/// again until a key arrives, and by then the clock has been given the
/// waiting back.
fn resting(current: Game) -> List(String) {
  [
    term.styled(palette.title, "Paused"),
    "",
    term.styled(
      palette.dim,
      "The board is put away and the clock has stopped at "
        <> clock(game.elapsed_ms(current))
        <> ".",
    ),
    "",
    term.styled(palette.dim, "Press any key to carry on, or q to quit."),
  ]
}

/// The title line: what puzzle this is, and which mode it is being worked on
/// in when that is worth saying.
fn header(name: String, mode: String) -> List(String) {
  let badge = case mode {
    "" -> ""
    _ -> term.styled(palette.mark, "    " <> mode)
  }

  [
    term.styled(palette.title, "S U D O K U")
      <> term.styled(palette.dim, "    " <> name)
      <> badge,
    "",
  ]
}

/// Put the count of wrong digits checking has caught on the title line, where
/// the player can see what is left of their allowance before spending it.
///
/// There is nothing to show before checking has been asked for, and nothing
/// worth showing once the game is over: the panel below the board has the
/// last word there.
fn tallied(head: List(String), current: Game) -> List(String) {
  let hidden =
    game.is_finished(current) || { !current.checking && current.mistakes == 0 }

  case head, hidden {
    _, True -> head
    [], _ -> head
    [title, ..rest], False -> {
      let colour = case current.mistakes >= game.mistake_limit {
        True -> palette.alarm
        False -> palette.mark
      }
      let tally =
        "    checking "
        <> int.to_string(current.mistakes)
        <> "/"
        <> int.to_string(game.mistake_limit)

      [title <> term.styled(colour, tally), ..rest]
    }
  }
}

fn footer(current: Game) -> List(String) {
  case game.is_finished(current) {
    True -> finished(current)
    // The window being too small takes the bottom line. The keys are a
    // reminder; a board wrapped into nonsense is a puzzle about the terminal
    // rather than about Sudoku, and worth saying out loud.
    False ->
      case cramped() {
        "" -> [term.styled(palette.dim, key_hints(current))]
        complaint -> [term.styled(palette.alarm, complaint)]
      }
  }
}

/// Whether the window is too small for a frame to land in properly, said in
/// a line, and empty where there is nothing to complain about.
///
/// A terminal that will not say how much room it has is taken at its word and
/// left alone. Asked afresh every frame, so a window resized mid-puzzle is
/// noticed — on the next keystroke, since that is when the next frame is
/// drawn, and `Ctrl-L` counts.
pub fn cramped() -> String {
  cramped_at(term.columns(), term.rows())
}

/// The same, for a window of a given size. Kept apart from the asking so that
/// it can be thought about, and tested, without a terminal to hand.
pub fn cramped_at(across: Int, down: Int) -> String {
  case across > 0 && across < columns, down > 0 && down < rows {
    False, False -> ""
    _, _ ->
      "This window is "
      <> measured(across)
      <> " by "
      <> measured(down)
      <> ", and the game wants "
      <> int.to_string(columns)
      <> " by "
      <> int.to_string(rows)
      <> "."
  }
}

fn measured(count: Int) -> String {
  case count > 0 {
    True -> int.to_string(count)
    False -> "?"
  }
}

// ---------------------------------------------------------------------------
// The grids
// ---------------------------------------------------------------------------

/// The board, and beside it a grid of the same shape holding the pencil
/// marks. Keeping the two apart lets the board stay as compact and readable
/// as it was before there were any marks to show.
fn grids(current: Game, clashes: Set(Int)) -> List(String) {
  let washes = washes(current)
  let board_grid =
    grids.grid(fn(index) { board_cell(current, clashes, washes, index) })
  let marks_grid = grids.grid(fn(index) { mark_cell(current, washes, index) })

  [
    caption("board", "marks"),
    ..list.map2(board_grid, marks_grid, fn(left, right) {
      left <> grid_gap <> right
    })
  ]
}

fn caption(left: String, right: String) -> String {
  term.styled(
    palette.dim,
    string.pad_end("  " <> left, grid_columns, " ") <> grid_gap <> "  " <> right,
  )
}

/// A cell of the board itself.
/// The cells the last hint was arguing from, if one is still up.
///
/// A hint that rests on a single cell is usually resting on the unit around
/// it as well — the only cell in row C that can take a 4 is a claim about
/// row C — so the unit comes with it. A hint about two or three cells has
/// named them, and lighting up their whole unit would bury them.
fn pointed_at(current: Game) -> Set(Int) {
  case current.showing {
    None -> set.new()
    Some(step) ->
      case step.evidence {
        [_] -> set.from_list(list.append(step.evidence, step.unit))
        cells -> set.from_list(cells)
      }
  }
}

fn board_cell(
  current: Game,
  clashes: Set(Int),
  washes: Washes,
  index: Int,
) -> String {
  let digit = board.value(current.board, index)
  let glyph = case digit {
    0 -> palette.empty_cell
    _ -> int.to_string(digit)
  }

  // Normally the digit under the cursor is the one picked out wherever else
  // it appears. While a scan is up it is the scanned digit instead: the whole
  // question is where that one has got to and where it could still go, and
  // both halves of the answer belong on screen at once.
  let focus = case current.scan {
    game.ScanningFor(scanned) -> scanned
    _ -> board.value(current.board, current.cursor)
  }
  let colour = board_colour(current, clashes, index, digit)

  painted(washes, index, digit != 0 && digit == focus, glyph, colour)
}

/// A cell of the grid of marks: the digit itself where a cell has been given
/// exactly one reading, an asterisk where it has been given several.
fn mark_cell(current: Game, washes: Washes, index: Int) -> String {
  let #(glyph, colour) = case board.sorted_marks(current.board, index) {
    [] -> #(palette.empty_cell, palette.empty)
    [only] -> #(int.to_string(only), palette.mark)
    _ -> #(palette.crowded_cell, palette.mark)
  }

  painted(washes, index, False, glyph, colour)
}

/// Two columns: a leading space so that a highlight reads as a solid block,
/// then the character itself.
fn painted(
  washes: Washes,
  index: Int,
  matching: Bool,
  glyph: String,
  colour: String,
) -> String {
  let styles =
    [background(washes, index, matching), colour]
    |> list.filter(fn(style) { style != "" })
    |> string.join(";")

  term.styled(styles, lead(washes, index) <> glyph)
}

/// The column in front of a cell. It is a space, so that a wash reads as a
/// solid block — except where the wash cannot be seen, and the column has to
/// say what it was going to say instead.
///
/// Two ways it cannot be seen. There is no colour at all, and then nothing is
/// shaded. Or the cell is the one the cursor is on, whose colour is spoken
/// for by the cursor — and that is the cell the player most wants an answer
/// about, since it is the one they have gone to look at.
///
/// Only what is being said gets a column. The washes behind the cursor's row,
/// its column and the digit it is sitting on are there to help the eye wander
/// rather than to say anything, and an eye can wander without them.
fn lead(washes: Washes, index: Int) -> String {
  let unseen = term.plain() || index == washes.cursor

  case
    unseen,
    set.contains(washes.lit, index),
    set.contains(washes.scanned, index)
  {
    True, True, _ -> palette.pointer
    True, _, True -> palette.could_go
    _, _, _ -> " "
  }
}

fn board_colour(
  current: Game,
  clashes: Set(Int),
  index: Int,
  digit: Int,
) -> String {
  case
    digit == 0,
    current.checking && game.is_wrong(current, index),
    set.contains(clashes, index),
    board.is_given(current.board, index)
  {
    True, _, _, _ -> palette.empty
    _, True, _, _ -> palette.wrong
    _, _, True, _ -> palette.conflict
    _, _, _, True -> palette.given
    _, _, _, _ -> palette.entered
  }
}

/// The cursor and the cells it can see are shaded the same way in both grids,
/// which is what ties one to the other.
/// What the board is shading, beyond the digits themselves: where the cursor
/// is, which cells a hint is arguing from, which a scan says its digit could
/// still go in, and whether the cursor's own row, column and box are picked
/// out at all.
type Washes {
  Washes(cursor: Int, lit: Set(Int), scanned: Set(Int), peers: Bool)
}

fn washes(current: Game) -> Washes {
  let scanned = case current.scan {
    game.ScanningFor(digit) ->
      set.from_list(board.could_take(current.board, digit))
    _ -> set.new()
  }

  Washes(
    cursor: current.cursor,
    lit: pointed_at(current),
    scanned: scanned,
    // A scan already shades nine cells or so. Shading the cursor's row, its
    // column and its box on top buries them, and the scan is what the player
    // asked to look at.
    peers: set.is_empty(scanned),
  )
}

fn background(washes: Washes, index: Int, matching: Bool) -> String {
  case
    index == washes.cursor,
    set.contains(washes.lit, index),
    set.contains(washes.scanned, index),
    matching,
    washes.peers && shares_unit(index, washes.cursor)
  {
    // The cursor stays visible through a hint: it is where the player is,
    // and a hint is only passing.
    True, _, _, _, _ -> palette.cursor
    _, True, _, _, _ -> palette.hint_wash
    _, _, True, _, _ -> palette.scan_wash
    _, _, _, True, _ -> palette.match_wash
    _, _, _, _, True -> palette.peer_wash
    _, _, _, _, _ -> ""
  }
}

fn shares_unit(one: Int, other: Int) -> Bool {
  board.row_of(one) == board.row_of(other)
  || board.col_of(one) == board.col_of(other)
  || board.box_of(one) == board.box_of(other)
}

// ---------------------------------------------------------------------------
// Everything below the grids
// ---------------------------------------------------------------------------

fn status(current: Game, clashes: Set(Int)) -> List(String) {
  let facts =
    [
      "empty " <> int.to_string(board.empty_count(current.board)),
      "clashes " <> int.to_string(set.size(clashes)),
      "time " <> clock(game.elapsed_ms(current)),
    ]
    |> string.join("  \u{2502}  ")

  let marks = case cursor_marks(current) {
    "" -> ""
    text -> term.styled(palette.dim, "  \u{2502}  ") <> text
  }

  // Nothing to place, or nothing more to be done about it: the row goes,
  // and on a finished board it has to, the panel saying how it went being
  // two rows where the key hints are one.
  let tally = case
    game.is_finished(current) || board.empty_count(current.board) == 0
  {
    True -> []
    False -> [remaining(current)]
  }

  list.flatten([
    ["", term.styled(palette.dim, facts) <> marks],
    tally,
    said(current.message),
  ])
}

/// What is left to place, a digit at a time.
///
/// The commonest thing a player does that is not thinking is counting the
/// sevens, and counting them wrong sends them hunting for a seven that is
/// already on the board. It is free by this game's own reckoning — anybody
/// can count them, the same as anybody can read off what a cell could still
/// take — so the game counts them rather than leaving a chore of it.
///
/// Every digit keeps its place in the line whether it has any left or not,
/// so the one being looked for is where it was a minute ago. A digit with
/// none left shows the dot an empty cell shows, which is the same thing said
/// about a digit rather than about a square: nothing here.
fn remaining(current: Game) -> String {
  let entries = {
    use digit <- list.map(board.span(1, board.side))

    let said = case board.left_to_place(current.board, digit) {
      0 ->
        term.styled(palette.empty, int.to_string(digit) <> palette.empty_cell)
      left ->
        term.styled(palette.entered, int.to_string(digit))
        <> term.styled(palette.dim, "\u{00d7}" <> int.to_string(left))
    }

    said
  }

  term.styled(palette.dim, "left  ") <> string.join(entries, "   ")
}

/// What the message says, over two rows.
///
/// The second row is where a hint puts why its reasoning settles anything,
/// which will not fit on the first alongside the name of the technique. It is
/// kept whether or not there is anything to put in it, so that the board
/// above never shifts a row between one message and the next.
fn said(message: String) -> List(String) {
  case string.split(message, "\n") {
    [what] -> [what, ""]
    [what, why, ..] -> [what, term.styled(palette.dim, why)]
    [] -> ["", ""]
  }
}

/// The cursor cell's marks, written out in full. This is where an asterisk in
/// the grid of marks can be read back as the digits behind it.
fn cursor_marks(current: Game) -> String {
  case board.sorted_marks(current.board, current.cursor) {
    [] -> ""
    marks ->
      term.styled(palette.dim, board.name(current.cursor) <> " marked ")
      <> term.styled(
        palette.mark,
        marks |> list.map(int.to_string) |> string.join(" "),
      )
  }
}

/// Milliseconds as `mm:ss`.
/// `mm:ss`, and `h:mm:ss` once there is an hour to say.
///
/// Minutes padded to two digits would go on counting past sixty and read
/// `104:33`, which is a puzzle in itself.
pub fn clock(milliseconds: Int) -> String {
  let seconds = milliseconds / 1000
  let minutes = seconds / 60

  case minutes / 60 {
    0 -> pad(minutes) <> ":" <> pad(seconds % 60)
    hours ->
      int.to_string(hours)
      <> ":"
      <> pad(minutes % 60)
      <> ":"
      <> pad(seconds % 60)
  }
}

/// How long until the clock would say something else, in milliseconds.
///
/// The frame is drawn again when the time on it changes and not otherwise,
/// so a player sitting still watching the seconds go by costs one frame a
/// second rather than as many as the loop can manage. On the second, too:
/// what is left of this one is what there is to wait.
///
/// Never nothing, whatever the moment: a wait of nothing at all is a loop
/// that draws as fast as it can, which is a busy terminal and a clock no
/// more right for it.
pub fn until_clock_moves(milliseconds: Int) -> Int {
  1000 - milliseconds % 1000
}

fn pad(value: Int) -> String {
  int.to_string(value) |> string.pad_start(2, "0")
}

fn key_hints(current: Game) -> String {
  let digits = case current.marking {
    True -> "1-9 mark"
    False -> "1-9 place"
  }

  [
    "arrows/hjkl move",
    digits,
    "0 clear",
    "m " <> other_mode(current),
    "? help",
    "q quit",
  ]
  |> string.join("  \u{2502}  ")
}

fn other_mode(current: Game) -> String {
  case current.marking {
    True -> "write"
    False -> "mark"
  }
}

fn finished(current: Game) -> List(String) {
  let headline = case current.ending {
    Some(game.Revealed) -> term.styled(palette.dim, "Solution revealed.")
    // However the allowance ran out, saying how many were wrong covers both
    // writing one too many and asking and being told about several.
    Some(game.Forfeited) ->
      term.styled(
        palette.alarm,
        int.to_string(current.mistakes) <> " wrong digits: forfeited.",
      )
      <> term.styled(palette.dim, "  They are the ones in red.")
    _ ->
      term.styled(palette.good, "Solved in " <> clock(game.elapsed_ms(current)))
      <> term.styled(palette.good, with_hints(current.hints))
      <> recorded(current)
  }

  // No blank line above: the message's second row is nearly always the gap,
  // and a 24-row terminal has none to spare once the panel is up.
  [headline, term.styled(palette.dim, "n new puzzle  \u{2502}  q quit")]
}

/// What the record books made of it, said on the same line: the panel has
/// only the two, and the one below it is spoken for.
fn recorded(current: Game) -> String {
  case current.verdict {
    Some(game.BestYet) -> term.styled(palette.good, " Your best yet.")
    Some(game.BestNotKept) ->
      term.styled(palette.good, " Your best yet,")
      <> term.styled(palette.alarm, " but it could not be saved.")
    Some(game.Behind(best)) ->
      term.styled(palette.dim, " Your best is " <> clock(best) <> ".")
    Some(game.Aided) ->
      term.styled(palette.dim, " Not recorded: unaided solves only.")
    _ -> ""
  }
}

/// What a solve cost in hints, tacked onto the time it took.
fn with_hints(hints: Int) -> String {
  case hints {
    0 -> "!"
    1 -> ", with one hint."
    _ -> ", with " <> int.to_string(hints) <> " hints."
  }
}

// --------------------------------------------------------------------------
// The opening menu
// --------------------------------------------------------------------------

/// The game left behind last time, said in a line: what it was, how much of
/// it is left, and how long it took to get that far.
fn summary(current: game.Game) -> String {
  generator.origin_label(current.puzzle.origin)
  <> ", "
  <> int.to_string(board.empty_count(current.board))
  <> " to go, "
  <> clock(game.elapsed_ms(current))
}

pub fn menu_frame(
  raw: Bool,
  saved: List(game.Game),
  bests: store.Bests,
) -> String {
  let options = {
    use origin, index <- list.index_map(generator.origins())
    "   "
    <> term.styled(palette.key, int.to_string(index + 1))
    <> "  "
    <> string.pad_end(generator.origin_label(origin), 10, " ")
    <> term.styled(palette.dim, string.pad_end(aside(origin), 24, " "))
    <> term.styled(palette.best, best(origin, bests))
  }

  let practice =
    "   "
    <> term.styled(palette.key, int.to_string(practice.choice()))
    <> "  "
    <> string.pad_end("Practice", 10, " ")
    <> term.styled(palette.dim, "one technique, on a grid that needs it")

  let room = case cramped() {
    "" -> []
    complaint -> ["", term.styled(palette.alarm, complaint)]
  }

  let note = case raw {
    True -> []
    False -> [
      "",
      term.styled(
        palette.note,
        "This terminal is in line mode: press Enter after each key.",
      ),
    ]
  }

  term.screen(
    list.flatten([
      [term.styled(palette.title, "S U D O K U"), "", "Choose a puzzle:", ""],
      options,
      [practice],
      [
        "",
        "   "
          <> term.styled(
          palette.dim,
          "Each level names the hardest reasoning its puzzles ask for.",
        ),
      ],
      case saved {
        [] -> []
        // One is no question and is offered as itself. Several is a
        // question, and the answer to it does not fit on this line.
        [only] -> [resuming(summary(only))]
        several -> [
          resuming(
            "one of "
            <> int.to_string(list.length(several))
            <> " games put down",
          ),
        ]
      },
      ["", "   " <> term.styled(palette.key, "q") <> "  quit"],
      room,
      note,
    ]),
  )
}

fn resuming(said: String) -> String {
  "\n   "
  <> term.styled(palette.key, "r")
  <> "  "
  <> string.pad_end("Resume", 10, " ")
  <> term.styled(palette.dim, said)
}

/// The games put down, to pick one of them back up.
///
/// Reached only where there is more than one, which is what two terminals
/// with a puzzle each leaves behind. They are told apart by what they are —
/// which puzzle, how much of it is left, how long it has taken — rather than
/// by which file they landed in, a file being the game's business and not
/// the player's.
pub fn saved_frame(saved: List(game.Game)) -> String {
  let options = {
    use current, index <- list.index_map(saved)
    "   "
    <> term.styled(palette.key, int.to_string(index + 1))
    <> "  "
    <> term.styled(palette.dim, summary(current))
  }

  term.screen(
    list.flatten([
      [
        term.styled(palette.title, "S U D O K U"),
        "",
        "Which game do you want back?",
        "",
      ],
      options,
      [
        "",
        "   "
          <> term.styled(
          palette.dim,
          "The one put down most recently is first.",
        ),
        "",
        "   "
          <> term.styled(palette.key, "q")
          <> "  quit"
          <> term.styled(palette.dim, "        any other key goes back"),
      ],
    ]),
  )
}

/// What each menu entry gets you: for a dealt puzzle, the hardest reasoning
/// it will ask of you, and for a custom one, a grid to type a puzzle of your
/// own into.
fn aside(origin: Origin) -> String {
  case origin {
    generator.Dealt(difficulty) -> generator.asks_for(difficulty)
    generator.Handwritten -> "type in a puzzle from a newspaper"
    generator.Practising(technique) -> logic.labels(technique)
  }
}

/// The time to beat at this difficulty, where there is one. A puzzle typed
/// in has no difficulty to have a best at.
fn best(origin: Origin, bests: store.Bests) -> String {
  case origin {
    generator.Handwritten | generator.Practising(_) -> ""
    generator.Dealt(difficulty) ->
      case dict.get(bests, difficulty) {
        Error(_) -> ""
        Ok(taken) -> "best " <> clock(taken)
      }
  }
}

/// The techniques there is a puzzle for, to pick one from.
///
/// In the order the help pages them, easiest first, which makes the list a
/// ladder as well as a menu. Each says how many clues its grid is dealt
/// with, since that is the difference between an afternoon and ten minutes
/// and is nothing to do with how hard the technique itself is — the X-wing
/// grid is the fullest of the lot.
pub fn practice_frame() -> String {
  let options = {
    use technique, index <- list.index_map(practice.techniques())
    let clues = practice.clue_count(technique)

    "   "
    <> term.styled(palette.key, int.to_string(index + 1))
    <> "  "
    <> string.pad_end(capitalised(logic.label(technique)), 20, " ")
    <> term.styled(palette.dim, int.to_string(clues) <> " clues")
  }

  term.screen(
    list.flatten([
      [
        term.styled(palette.title, "S U D O K U"),
        "",
        "Practise which technique?",
        "",
      ],
      options,
      [
        "",
        "   "
          <> term.styled(
          palette.dim,
          "Each grid needs its technique and nothing harder. Press ? while",
        ),
        "   "
          <> term.styled(
          palette.dim,
          "playing for the page explaining the one you picked.",
        ),
        "",
        "   "
          <> term.styled(palette.key, "q")
          <> "  quit"
          <> term.styled(palette.dim, "        any other key goes back"),
      ],
    ]),
  )
}

fn capitalised(name: String) -> String {
  string.uppercase(string.slice(name, 0, 1))
  <> string.slice(name, 1, string.length(name) - 1)
}

/// The screen while a puzzle is being carved, which is a moment at the easy
/// levels and can be a few seconds at Expert.
///
/// It says which grid is being cut and what the best of them asks for so
/// far, because that is what the waiting is: carving is greedy and often
/// lands easier than the level wants, so it carves another and keeps the
/// harder. A count that moves says the game is working; saying what it has
/// so far says what it is working towards.
pub fn generating(
  difficulty: Difficulty,
  carving: generator.Carving,
) -> String {
  term.screen([
    term.styled(palette.title, "S U D O K U"),
    "",
    term.styled(
      palette.dim,
      "Carving out " <> article(generator.label(difficulty)) <> " puzzle...",
    ),
    "",
    term.styled(palette.dim, counted(carving)),
    term.styled(
      palette.dim,
      "Each is carved as far as it will go, and the hardest of them kept.",
    ),
  ])
}

fn counted(carving: generator.Carving) -> String {
  let so_far =
    "Grid "
    <> int.to_string(carving.attempt)
    <> " of "
    <> int.to_string(carving.of)

  case carving.asks {
    // The first grid, before there is any best to be the best of.
    Error(_) -> so_far <> "."
    Ok(technique) ->
      so_far
      <> ", and the best so far asks for "
      <> logic.labels(technique)
      <> "."
  }
}

/// `a` or `an`, so that dealing an Expert puzzle does not read as dealing
/// "a Expert" one.
fn article(word: String) -> String {
  case string.starts_with(string.lowercase(word), "e") {
    True -> "an " <> word
    False -> "a " <> word
  }
}

// ---------------------------------------------------------------------------
// Typing a puzzle in
// ---------------------------------------------------------------------------

/// The editor's screen: one grid, since a puzzle being typed in has no marks
/// yet, drawn by the same code as the board so that the two look alike.
pub fn editor_frame(current: Editor) -> String {
  let head = header(generator.origin_label(generator.Handwritten), "editing")

  case current.show_help {
    True ->
      term.screen(
        list.flatten([
          head,
          help.editor_keys(),
          ["", term.styled(palette.dim, "Any key returns to the board.")],
        ]),
      )
    False -> {
      let clashes = board.grid_conflicts(current.clues)
      term.screen(
        list.flatten([
          head,
          [term.styled(palette.dim, "  clues")],
          grids.grid(fn(index) { clue_cell(current, clashes, index) }),
          editor_status(current, clashes),
          [
            case cramped() {
              "" -> term.styled(palette.dim, editor_key_hints)
              complaint -> term.styled(palette.alarm, complaint)
            },
          ],
        ]),
      )
    }
  }
}

/// A cell being typed in. Clues are drawn the way they will look once the
/// game starts, so what is on screen is what will be played.
fn clue_cell(current: Editor, clashes: Set(Int), index: Int) -> String {
  let digit = editor.value(current, index)
  let glyph = case digit {
    0 -> palette.empty_cell
    _ -> int.to_string(digit)
  }

  let colour = case digit == 0, set.contains(clashes, index) {
    True, _ -> palette.empty
    _, True -> palette.conflict
    _, _ -> palette.given
  }

  let focus = editor.value(current, current.cursor)

  // Nothing lit and nothing scanned: a puzzle being typed in has no hints to
  // point with and no answer yet to look for a digit in.
  painted(
    Washes(current.cursor, set.new(), set.new(), True),
    index,
    digit != 0 && digit == focus,
    glyph,
    colour,
  )
}

fn editor_status(current: Editor, clashes: Set(Int)) -> List(String) {
  let facts =
    [
      "clues " <> int.to_string(editor.clue_count(current)),
      "clashes " <> int.to_string(set.size(clashes)),
      "cell " <> board.name(current.cursor),
    ]
    |> string.join("  \u{2502}  ")

  ["", term.styled(palette.dim, facts), current.message]
}

const editor_key_hints = "arrows/hjkl move  \u{2502}  1-9 type  \u{2502}  0 gap  \u{2502}  p play  \u{2502}  ? help  \u{2502}  q quit"
