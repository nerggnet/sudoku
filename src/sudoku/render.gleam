//// Drawing the board.
////
//// A frame is built as a list of single lines and printed in one write, so
//// the screen never tears. Each line ends with an erase-to-end-of-line and
//// the frame ends with an erase-to-end-of-screen, which means the previous
//// frame does not have to be cleared first.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleam/string
import sudoku/board
import sudoku/editor.{type Editor}
import sudoku/game.{type Game}
import sudoku/generator
import sudoku/grids
import sudoku/help
import sudoku/palette
import sudoku/term

/// How much room a frame needs: the widest line it draws, and the most rows.
pub const columns = 78

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
  let mode = case current.marking {
    True -> "marking"
    False -> ""
  }
  let head =
    header(generator.origin_label(current.puzzle.origin), mode)
    |> tallied(current)

  case current.help {
    Some(page) -> term.screen(list.flatten([head, help.page(page)]))
    None -> {
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
        True -> palette.conflict
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
    False -> [term.styled(palette.dim, key_hints(current))]
  }
}

// ---------------------------------------------------------------------------
// The grids
// ---------------------------------------------------------------------------

/// The board, and beside it a grid of the same shape holding the pencil
/// marks. Keeping the two apart lets the board stay as compact and readable
/// as it was before there were any marks to show.
fn grids(current: Game, clashes: Set(Int)) -> List(String) {
  let lit = pointed_at(current)
  let board_grid =
    grids.grid(fn(index) { board_cell(current, clashes, lit, index) })
  let marks_grid = grids.grid(fn(index) { mark_cell(current, lit, index) })

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
  lit: Set(Int),
  index: Int,
) -> String {
  let digit = board.value(current.board, index)
  let glyph = case digit {
    0 -> palette.empty_cell
    _ -> int.to_string(digit)
  }

  let focus = board.value(current.board, current.cursor)
  let colour = board_colour(current, clashes, index, digit)

  painted(
    current.cursor,
    lit,
    index,
    digit != 0 && digit == focus,
    glyph,
    colour,
  )
}

/// A cell of the grid of marks: the digit itself where a cell has been given
/// exactly one reading, an asterisk where it has been given several.
fn mark_cell(current: Game, lit: Set(Int), index: Int) -> String {
  let #(glyph, colour) = case board.sorted_marks(current.board, index) {
    [] -> #(palette.empty_cell, palette.empty)
    [only] -> #(int.to_string(only), palette.mark)
    _ -> #(palette.crowded_cell, palette.mark)
  }

  painted(current.cursor, lit, index, False, glyph, colour)
}

/// Two columns: a leading space so that a highlight reads as a solid block,
/// then the character itself.
fn painted(
  cursor: Int,
  lit: Set(Int),
  index: Int,
  matching: Bool,
  glyph: String,
  colour: String,
) -> String {
  let styles =
    [background(cursor, lit, index, matching), colour]
    |> list.filter(fn(style) { style != "" })
    |> string.join(";")

  term.styled(styles, " " <> glyph)
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
fn background(
  cursor: Int,
  lit: Set(Int),
  index: Int,
  matching: Bool,
) -> String {
  case
    index == cursor,
    set.contains(lit, index),
    matching,
    shares_unit(index, cursor)
  {
    // The cursor stays visible through a hint: it is where the player is,
    // and a hint is only passing.
    True, _, _, _ -> palette.cursor
    _, True, _, _ -> palette.hint_wash
    _, _, True, _ -> palette.match_wash
    _, _, _, True -> palette.peer_wash
    _, _, _, _ -> ""
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

  ["", term.styled(palette.dim, facts) <> marks, ..said(current.message)]
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
        palette.conflict,
        int.to_string(current.mistakes) <> " wrong digits: forfeited.",
      )
      <> term.styled(palette.dim, "  They are the ones in red.")
    _ ->
      term.styled(palette.good, "Solved in " <> clock(game.elapsed_ms(current)))
      <> term.styled(palette.good, aside(current.hints))
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
    Some(game.Behind(best)) ->
      term.styled(palette.dim, " Your best is " <> clock(best) <> ".")
    Some(game.Aided) ->
      term.styled(palette.dim, " Not recorded: unaided solves only.")
    _ -> ""
  }
}

fn aside(hints: Int) -> String {
  case hints {
    0 -> "!"
    1 -> ", with one hint."
    _ -> ", with " <> int.to_string(hints) <> " hints."
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
          [term.styled(palette.dim, editor_key_hints)],
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

  // Nothing lit: a puzzle being typed in has no hints to point with.
  painted(
    current.cursor,
    set.new(),
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
