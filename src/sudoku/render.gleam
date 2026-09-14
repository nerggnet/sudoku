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
import sudoku/logic
import sudoku/term

const empty_cell = "\u{00b7}"

/// Stands in for a cell carrying more than one pencil mark. Which digits
/// those are is spelled out in the status line when the cursor reaches it.
const crowded_cell = "*"

/// How much room a frame needs: the widest line it draws, and the most rows.
pub const columns = 78

pub const rows = 24

/// How many columns one grid takes up. Cells are two columns wide, so a band
/// of three plus its trailing space is seven, four box rules bring the row to
/// 25, and the row label and its space make 27.
const grid_columns = 27

/// What separates the board from the marks beside it.
const grid_gap = "    "

// Foreground colours.
const given_style = "1;97"

const entered_style = "96"

const conflict_style = "1;91"

const wrong_style = "1;91;4"

const empty_style = "90"

const dim_style = "90"

const title_style = "1;95"

const good_style = "1;92"

const mark_style = "33"

// A wash behind the cells sharing a unit with the cursor, and behind cells
// holding the same digit as the one under the cursor.
const peer_background = "48;5;236"

const match_background = "48;5;238"

/// Behind the cells a hint is resting its argument on, so that it can point
/// as well as talk.
const hint_background = "48;5;22"

const cursor_style = "7"

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
    Some(page) -> term.screen(list.flatten([head, help(page)]))
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
    _ -> term.styled(mark_style, "    " <> mode)
  }

  [
    term.styled(title_style, "S U D O K U")
      <> term.styled(dim_style, "    " <> name)
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
        True -> conflict_style
        False -> mark_style
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
    False -> [term.styled(dim_style, key_hints(current))]
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
  let board_grid = grid(fn(index) { board_cell(current, clashes, lit, index) })
  let marks_grid = grid(fn(index) { mark_cell(current, lit, index) })

  [
    caption("board", "marks"),
    ..list.map2(board_grid, marks_grid, fn(left, right) {
      left <> grid_gap <> right
    })
  ]
}

fn caption(left: String, right: String) -> String {
  term.styled(
    dim_style,
    string.pad_end("  " <> left, grid_columns, " ") <> grid_gap <> "  " <> right,
  )
}

/// Lay nine cells out as `│abc │def │ghi │`, with every cell two columns wide
/// so that a highlight reads as a solid block. The column ruler is built with
/// the same helper, which is what keeps it aligned with the cells.
fn banded(cells: List(String), separator: String) -> String {
  chunked(cells, 3, separator)
}

/// The same in bands of whatever size, which is what lets a diagram of one
/// digit's whereabouts drop the box rules it has no use for.
fn chunked(cells: List(String), size: Int, separator: String) -> String {
  cells
  |> list.sized_chunk(size)
  |> list.map(fn(band) { string.concat(band) <> " " })
  |> string.join(separator)
  |> fn(bands) { separator <> bands <> separator }
}

/// One grid, from its column ruler down to its bottom rule. What goes in each
/// cell is left to the caller, which is how the board and the marks beside it
/// come out exactly the same shape.
fn grid(cell: fn(Int) -> String) -> List(String) {
  let ruler =
    board.span(1, board.side)
    |> list.map(fn(column) { " " <> int.to_string(column) })
    |> banded(" ")

  let bands =
    board.row_labels
    |> list.index_map(fn(label, row) { row_line(cell, row, label) })
    |> list.sized_chunk(3)
    |> list.intersperse([rule("\u{251c}", "\u{253c}", "\u{2524}")])
    |> list.flatten

  list.flatten([
    [term.styled(dim_style, "  " <> ruler)],
    [rule("\u{250c}", "\u{252c}", "\u{2510}")],
    bands,
    [rule("\u{2514}", "\u{2534}", "\u{2518}")],
  ])
}

fn rule(left: String, join: String, right: String) -> String {
  banded_rule(left, join, right, 3, "  ")
}

/// A rule across however many bands of however many cells, with the same
/// margin as the rows it belongs to.
fn banded_rule(
  left: String,
  join: String,
  right: String,
  size: Int,
  margin: String,
) -> String {
  let bars =
    list.repeat(string.repeat("\u{2500}", size * 2 + 1), 9 / size)
    |> string.join(join)

  margin <> term.styled(dim_style, left <> bars <> right)
}

fn row_line(cell: fn(Int) -> String, row: Int, label: String) -> String {
  let cells =
    board.span(0, board.side - 1)
    |> list.map(fn(column) { cell(board.at(row, column)) })

  term.styled(dim_style, label)
  <> " "
  <> banded(cells, term.styled(dim_style, "\u{2502}"))
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
    0 -> empty_cell
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
    [] -> #(empty_cell, empty_style)
    [only] -> #(int.to_string(only), mark_style)
    _ -> #(crowded_cell, mark_style)
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
    True, _, _, _ -> empty_style
    _, True, _, _ -> wrong_style
    _, _, True, _ -> conflict_style
    _, _, _, True -> given_style
    _, _, _, _ -> entered_style
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
    True, _, _, _ -> cursor_style
    _, True, _, _ -> hint_background
    _, _, True, _ -> match_background
    _, _, _, True -> peer_background
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
    text -> term.styled(dim_style, "  \u{2502}  ") <> text
  }

  ["", term.styled(dim_style, facts) <> marks, ..said(current.message)]
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
    [what, why, ..] -> [what, term.styled(dim_style, why)]
    [] -> ["", ""]
  }
}

/// The cursor cell's marks, written out in full. This is where an asterisk in
/// the grid of marks can be read back as the digits behind it.
fn cursor_marks(current: Game) -> String {
  case board.sorted_marks(current.board, current.cursor) {
    [] -> ""
    marks ->
      term.styled(dim_style, board.name(current.cursor) <> " marked ")
      <> term.styled(
        mark_style,
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

/// Getting about the board, and putting things on it.
const board_keys = [
  #("\u{2190} \u{2191} \u{2193} \u{2192}, hjkl, wasd", "move the cursor"),
  #("1 - 9", "write a digit, or pencil one in while marking"),
  #("shift 1 - 9", "pencil a digit in either way round"),
  #("0, space, backspace", "clear the cell, or its marks while marking"),
  #("f", "pencil the candidates into every bare cell"),
  #("m", "switch between writing and marking"),
  #("u", "undo"),
  #("r", "do it again"),
]

/// How the game can be started, which the help says and the command line
/// says back when it is handed something it does not know. One list, so that
/// the two cannot come to disagree.
pub const invocations = [
  #("gleam run", "choose a puzzle from the menu"),
  #("gleam run -- hard", "deal one at that difficulty"),
  #("gleam run -- custom", "type a puzzle in"),
  #("gleam run -- resume", "pick up the game you left"),
  #("gleam run -- <puzzle>", "play that puzzle"),
]

const starting_notes = [
  "A puzzle is 81 characters, a digit for each clue and a dot for each blank.",
  "The game prints the one it was playing as it leaves, which is the line to",
  "hand to somebody else — and the line they hand to this.",
]

/// The same, for a terminal that has not been taken over.
pub fn usage() -> String {
  let lines = {
    use #(invocation, meaning) <- list.map(invocations)
    "  " <> string.pad_end(invocation, 24, " ") <> meaning
  }

  string.join(["Usage:", ..lines], "\n")
}

/// Asking the game for something, and leaving.
const asking_keys = [
  #("c", "check for good; a fourth wrong digit forfeits"),
  #("H", "take the next step, and say why"),
  #("R", "reveal the whole solution"),
  #("n", "start a new puzzle"),
  #("Ctrl-L", "draw the screen again"),
  #("?", "close this help"),
  #("q", "quit, keeping a game in progress"),
]

const ask_notes = [
  "A hint takes the cell you are on whenever that cell can be worked out, and",
  "names the technique that settled it. The pages after this one are those",
  "techniques, one to a page, with a small board apiece showing them at work.",
]

const mark_notes = [
  "Marks show in the grid beside the board: the digit itself where a cell",
  "has one, an asterisk where it has several. Move onto a cell to read",
  "all of its marks in the status line. Writing a digit rubs out the marks",
  "it rules out, but not while checking is on and the digit is wrong.",
]

/// A key reference, with a paragraph under it. Used for both the game's help
/// and the editor's.
fn keys(
  title: String,
  reference: List(#(String, String)),
  notes: List(String),
) -> List(String) {
  // Wide enough for the longest of them, and never so narrow that the pages
  // stop looking like one another.
  let column =
    list.fold(reference, 22, fn(widest, entry) {
      int.max(widest, string.length(entry.0) + 2)
    })

  let entries = {
    use #(pressed, meaning) <- list.map(reference)
    "  "
    <> term.styled(entered_style, string.pad_end(pressed, column, " "))
    <> term.styled(dim_style, meaning)
  }

  list.flatten([
    [term.styled("1", title), ""],
    entries,
    [""],
    list.map(notes, term.styled(dim_style, _)),
  ])
}

// ---------------------------------------------------------------------------
// The help, page by page
// ---------------------------------------------------------------------------

/// The keys on the first page, and then a page on each way of working a digit
/// out: what it is, a small board showing it happening, and what it settles.
///
/// The examples are drawn by hand rather than lifted out of a real grid. A
/// real one comes with sixty other cells to look past, and the whole point of
/// a page is the one thing it is about.
fn help(page: game.Help) -> List(String) {
  let body = case page {
    game.Keys -> keys("Keys: the board", board_keys, mark_notes)
    game.MoreKeys -> keys("Keys: asking and finishing", asking_keys, ask_notes)
    game.Starting -> keys("Starting up", invocations, starting_notes)
    game.About(technique) -> about(technique)
  }

  list.append(body, [
    "",
    term.styled(
      dim_style,
      "\u{2190} \u{2192}  " <> paging(page) <> "     any other key returns",
    ),
  ])
}

fn paging(page: game.Help) -> String {
  let pages = game.pages()
  let at = list.length(list.take_while(pages, fn(other) { other != page })) + 1

  "page " <> int.to_string(at) <> " of " <> int.to_string(list.length(pages))
}

fn about(technique: logic.Technique) -> List(String) {
  let #(what, example, so) = teaching(technique)

  list.flatten([
    [term.styled("1", capitalised(logic.label(technique))), ""],
    list.map(what, term.styled(dim_style, _)),
    [""],
    example,
    [""],
    [term.styled(entered_style, so)],
  ])
}

fn capitalised(name: String) -> String {
  string.uppercase(string.slice(name, 0, 1))
  <> string.slice(name, 1, string.length(name) - 1)
}

/// What each technique is, what it looks like, and what it settles.
///
/// The strips show what the cells of one unit have left in them. The maps
/// show one digit at a time: where it can still go, and where this way of
/// looking at it has just shut it out.
fn teaching(
  technique: logic.Technique,
) -> #(List(String), List(String), String) {
  case technique {
    logic.NakedSingle -> #(
      [
        "A cell with one candidate left has to take it. Everything else that",
        "could have gone there is already spoken for by a peer.",
      ],
      strip("C", ["18", "4", "79", "28", "3", "5", "18", "6", "79"], [4], []),
      "C5 has one candidate left, so that is what it is: a 3.",
    )

    logic.HiddenSingle -> #(
      [
        "A digit with one cell left in a unit has to go there, however much",
        "else that cell could still have taken.",
      ],
      strip(
        "C",
        ["27", "279", "89", "89", "1279", "27", "89", "89", "279"],
        [4],
        [],
      ),
      "Only C5 can take a 1, so that is where the row's 1 goes.",
    )

    logic.LockedCandidates -> #(
      [
        "A digit shut into one line of a box has to be somewhere along that",
        "line, so it cannot be anywhere else along it.",
      ],
      // The left box can only take its 1 in row A, so the rest of row A
      // cannot have one. A hash is a cell the digit can still go in, a bang
      // one this has just shut it out of.
      map("1", ["##.!.!.!.", "....#.#..", ".....#..#"], True),
      "Every 1 in the left box is in row A, so A4, A6 and A8 lose theirs.",
    )

    logic.NakedPair -> #(
      [
        "Two cells in a unit holding the same two candidates take one each",
        "between them, whichever way round, so nothing else can have either.",
      ],
      strip("C", ["79", "4", "79", "1379", "3", "5", "8", "6", "2"], [0, 2], [3]),
      "C1 and C3 take 7 and 9, so C4 is down to a 1 or a 3.",
    )

    logic.HiddenPair -> #(
      [
        "Two digits in a unit with the same two cells to go in take one each,",
        "so those two cells can hold nothing else.",
      ],
      strip(
        "C",
        ["123", "34", "124", "34", "5", "6", "7", "8", "9"],
        [0, 2],
        [],
      ),
      "Only C1 and C3 can take a 1 or a 2, so both lose their other digits.",
    )

    logic.NakedTriple -> #(
      [
        "Three cells between them holding three candidates take one each, on",
        "the same reasoning as two cells holding two.",
      ],
      strip(
        "C",
        ["27", "79", "29", "1", "2579", "6", "8", "3", "4"],
        [0, 1, 2],
        [4],
      ),
      "C1, C2 and C3 take 2, 7 and 9, so C5 has to be the 5.",
    )

    logic.XWing -> #(
      [
        "A digit down to the same two columns in two rows takes one corner in",
        "each row, and so one in each column. Or the other way about.",
      ],
      // Rows B and F can only take their 9 in column 2 or column 9. The
      // corners make a rectangle, and every other 9 in those two columns
      // has to go.
      map(
        "9",
        [
          ".!.......", ".#......#", "........!", ".........", ".!.......",
          ".#......#", ".........", "........!", ".........",
        ],
        False,
      ),
      "The 9s in rows B and F keep to columns 2 and 9, so four others go.",
    )
  }
}

/// One unit's worth of cells and what each of them has left in it.
fn strip(
  label: String,
  cells: List(String),
  lit: List(Int),
  out: List(Int),
) -> List(String) {
  let wall = term.styled(dim_style, "\u{2502}")
  let wide = 5

  let ruler =
    "    "
    <> term.styled(
      dim_style,
      " "
        <> {
        use column <- list.map(board.span(1, 9))
        centred(int.to_string(column), wide) <> " "
      }
      |> string.concat,
    )

  let rules = fn(left, join, right) {
    "    "
    <> term.styled(
      dim_style,
      left
        <> {
        list.repeat(string.repeat("\u{2500}", wide), 9) |> string.join(join)
      }
        <> right,
    )
  }

  let row =
    "  "
    <> term.styled(dim_style, label)
    <> " "
    <> wall
    <> {
      use cell, at <- list.index_map(cells)
      let colour = case list.contains(lit, at), list.contains(out, at) {
        True, _ -> given_style
        _, True -> conflict_style
        _, _ -> empty_style
      }
      term.styled(colour, centred(cell, wide)) <> wall
    }
    |> string.concat

  [
    ruler,
    rules("\u{250c}", "\u{252c}", "\u{2510}"),
    row,
    rules("\u{2514}", "\u{2534}", "\u{2518}"),
  ]
}

/// Where one digit can still go, drawn as the board is drawn: `#` for a cell
/// it can take, `!` for one this reasoning has just shut it out of, and a dot
/// for the rest.
///
/// Box rules are drawn only where the technique is about boxes. For one about
/// rows and columns they are three lines of noise, and three lines is the
/// difference between the page fitting and not.
fn map(digit: String, rows: List(String), boxed: Bool) -> List(String) {
  let size = case boxed {
    True -> 3
    False -> 9
  }

  let ruler =
    "    "
    <> term.styled(
      dim_style,
      chunked(
        list.map(board.span(1, 9), fn(column) { " " <> int.to_string(column) }),
        size,
        " ",
      ),
    )

  let lines = {
    use line, at <- list.index_map(rows)
    let cells = {
      use marker <- list.map(string.to_graphemes(line))
      case marker {
        "#" -> term.styled(given_style, " " <> digit)
        "!" -> term.styled(conflict_style, " " <> digit)
        _ -> term.styled(empty_style, " \u{b7}")
      }
    }

    "  "
    <> term.styled(dim_style, board.row_letter(at))
    <> " "
    <> chunked(cells, size, term.styled(dim_style, "\u{2502}"))
  }

  let rules = fn(left, join, right) {
    banded_rule(left, join, right, size, "    ")
  }

  list.flatten([
    [ruler],
    [rules("\u{250c}", "\u{252c}", "\u{2510}")],
    lines,
    [rules("\u{2514}", "\u{2534}", "\u{2518}")],
  ])
}

/// Text in the middle of a field that wide, leaning left where it cannot sit
/// exactly in the middle.
fn centred(text: String, wide: Int) -> String {
  let left = { wide - string.length(text) + 1 } / 2
  string.pad_end(string.repeat(" ", left) <> text, wide, " ")
}

fn finished(current: Game) -> List(String) {
  let headline = case current.ending {
    Some(game.Revealed) -> term.styled(dim_style, "Solution revealed.")
    // However the allowance ran out, saying how many were wrong covers both
    // writing one too many and asking and being told about several.
    Some(game.Forfeited) ->
      term.styled(
        conflict_style,
        int.to_string(current.mistakes) <> " wrong digits: forfeited.",
      )
      <> term.styled(dim_style, "  They are the ones in red.")
    _ ->
      term.styled(good_style, "Solved in " <> clock(game.elapsed_ms(current)))
      <> term.styled(good_style, aside(current.hints))
      <> recorded(current)
  }

  // No blank line above: the message's second row is nearly always the gap,
  // and a 24-row terminal has none to spare once the panel is up.
  [headline, term.styled(dim_style, "n new puzzle  \u{2502}  q quit")]
}

/// What the record books made of it, said on the same line: the panel has
/// only the two, and the one below it is spoken for.
fn recorded(current: Game) -> String {
  case current.verdict {
    Some(game.BestYet) -> term.styled(good_style, " Your best yet.")
    Some(game.Behind(best)) ->
      term.styled(dim_style, " Your best is " <> clock(best) <> ".")
    Some(game.Aided) ->
      term.styled(dim_style, " Not recorded: unaided solves only.")
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
          keys("Keys", editor_key_reference, editor_notes),
          ["", term.styled(dim_style, "Any key returns to the board.")],
        ]),
      )
    False -> {
      let clashes = board.grid_conflicts(current.clues)
      term.screen(
        list.flatten([
          head,
          [term.styled(dim_style, "  clues")],
          grid(fn(index) { clue_cell(current, clashes, index) }),
          editor_status(current, clashes),
          [term.styled(dim_style, editor_key_hints)],
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
    0 -> empty_cell
    _ -> int.to_string(digit)
  }

  let colour = case digit == 0, set.contains(clashes, index) {
    True, _ -> empty_style
    _, True -> conflict_style
    _, _ -> given_style
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

  ["", term.styled(dim_style, facts), current.message]
}

const editor_key_hints = "arrows/hjkl move  \u{2502}  1-9 type  \u{2502}  0 gap  \u{2502}  p play  \u{2502}  ? help  \u{2502}  q quit"

const editor_key_reference = [
  #("\u{2190} \u{2191} \u{2193} \u{2192}, hjkl, wasd", "move the cursor"),
  #("1 - 9", "type a clue in and step on to the next cell"),
  #("0, space, backspace", "leave the cell empty and step on"),
  #("u", "undo"),
  #("x", "clear the grid and start over"),
  #("p", "play the puzzle"),
  #("n", "back to the menu"),
  #("?", "close this help"),
  #("q", "quit"),
]

const editor_notes = [
  "Digits step the cursor on by themselves, so a row is nine keystrokes and",
  "the whole grid eighty-one, read straight off the page. Clues that clash",
  "turn red, and p checks the puzzle has exactly one answer before play.",
]
