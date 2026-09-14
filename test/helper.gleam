//// What the tests are made of: the puzzles they work from, the games they
//// build out of them, and the reading of a screen once one has been drawn.
////
//// Here rather than beside any one subject's tests, since a fixture is
//// wanted by whichever of them happens to need a game to poke at.

import gleam/int
import gleam/list
import gleam/string
import sudoku/board
import sudoku/editor
import sudoku/game
import sudoku/generator
import sudoku/key
import sudoku/logic
import sudoku/render
import sudoku/rules
import sudoku/solver

// A puzzle with a single solution, and that solution.
pub const puzzle_text = "
  53. .7. ...
  6.. 195 ...
  .98 ... .6.
  8.. .6. ..3
  4.. 8.3 ..1
  7.. .2. ..6
  .6. ... 28.
  ... 419 ..5
  ... .8. .79
"

pub const solution_text = "
  534 678 912
  672 195 348
  198 342 567
  859 761 423
  426 853 791
  713 924 856
  961 537 284
  287 419 635
  345 286 179
"

pub fn grid(text: String) -> board.Grid {
  let assert Ok(parsed) = board.parse(text) as "test fixture should parse"
  parsed
}

/// Puzzles hunted out of generated ones until each of the rarer techniques
/// was called for. A generated puzzle needs them only now and then, so they
/// are kept here to make sure the techniques that find them stay honest.
pub const needs_naked_pair = "
  ... ... .51
  27. 8.. 46.
  ... 39. 2..
  ..6 1.. ..4
  ..9 ... ...
  3.. ..2 9..
  ..2 .73 ...
  .37 ..6 .12
  9.. ... ...
"

pub const needs_hidden_pair = "
  8.. ... 7..
  ..5 7.4 ...
  6.. .3. .9.
  93. ..5 ...
  56. ... .21
  ... 1.. .59
  .5. .7. ..2
  ... 8.2 4..
  ..6 ... ..7
"

pub const needs_naked_triple = "
  ... ..4 1.3
  ... 1.. ...
  9.. ..5 .46
  ..6 2.. ..9
  .5. 9.3 .2.
  2.8 .16 ...
  76. 5.. ..1
  ... ... ...
  1.5 6.. ...
"

pub const needs_x_wing = "
  .6. 32. .7.
  ... 5.8 42.
  ... 7.4 6..
  .14 ... ..2
  ... ... ...
  7.. ... 84.
  ..9 8.1 ...
  .71 4.6 ...
  ... ..3 .6.
"

pub fn edit(current: editor.Editor, pressed: key.Key) -> editor.Editor {
  let assert editor.Continue(next) = editor.update(current, pressed)
  next
}

/// Type a grid in one keystroke per cell, the way a puzzle is copied off a
/// page. Layout is ignored, just as `board.parse` ignores it.
pub fn typed(text: String) -> editor.Editor {
  use current, character <- list.fold(string.to_graphemes(text), editor.new())
  case character {
    "." | "_" | "0" -> edit(current, key.Erase)
    _ ->
      case int.parse(character) {
        Ok(digit) -> edit(current, key.Digit(digit))
        Error(_) -> current
      }
  }
}

/// A game on a puzzle typed in by hand, which has no difficulty and so no
/// time to lose.
pub fn handwritten() -> game.Game {
  let assert editor.Ready(puzzle) =
    editor.update(typed(puzzle_text), key.Char("p"))
  game.new(puzzle)
}

/// Decode a keystroke from a fixed run of bytes.
pub fn press(bytes: List(Int)) -> key.Key {
  let #(pressed, _) = {
    use remaining <- key.decode(bytes)
    case remaining {
      [] -> #(-1, [])
      [byte, ..rest] -> #(byte, rest)
    }
  }
  pressed
}

/// Decode a keystroke, and say what was left unread behind it.
pub fn press_leaving(bytes: List(Int)) -> #(key.Key, List(Int)) {
  use remaining <- key.decode(bytes)
  case remaining {
    [] -> #(-1, [])
    [byte, ..rest] -> #(byte, rest)
  }
}

/// Checking switched on, which takes two asks: one to hear what it costs and
/// one to go ahead.
pub fn checked(current: game.Game) -> game.Game {
  current |> step(key.Char("c")) |> step(key.Char("c"))
}

/// A game that has already agreed to being helped, so that a test about what
/// a hint says need not first press H to hear what a hint costs.
pub fn aided(current: game.Game) -> game.Game {
  game.Game(..current, aided: True)
}

pub fn fixture() -> game.Game {
  game.new(generator.Puzzle(
    board: board.from_grid(grid(puzzle_text)),
    solution: grid(solution_text),
    origin: generator.Dealt(generator.Medium),
  ))
}

pub fn step(current: game.Game, pressed: key.Key) -> game.Game {
  let assert game.Continue(next) = rules.update(current, pressed)
  next
}

/// Write a wrong digit into each of `cells` in turn.
pub fn blunder(current: game.Game, cells: List(Int)) -> game.Game {
  use played, index <- list.fold(cells, current)
  let wrong = { game.answer(played, index) % 9 } + 1
  game.Game(..played, cursor: index) |> step(key.Digit(wrong))
}

/// The empty cells of the fixture, in reading order.
pub fn blanks() -> List(Int) {
  let start = fixture()
  list.filter(board.indices(), fn(index) {
    board.value(start.board, index) == 0
  })
}

/// Nothing on the board disagrees with the answer.
pub fn nothing_wrong(current: game.Game) -> Bool {
  use index <- list.all(board.indices())
  case board.value(current.board, index) {
    0 -> True
    digit -> digit == game.answer(current, index)
  }
}

/// A cell of the fixture that nothing settles yet.
pub fn stuck_cell() -> Int {
  let start = fixture()
  let assert Ok(stuck) = {
    use index <- list.find(board.indices())
    board.value(start.board, index) == 0
    && logic.settles(start.board.values, index) == Error(Nil)
  }
  stuck
}

/// A game of one of the frozen fixtures, answer and all.
pub fn playing(text: String) -> game.Game {
  let assert Ok(answer) = solver.solve(grid(text))
    as "the fixtures are solvable"
  game.new(generator.Puzzle(
    board: board.from_grid(grid(text)),
    solution: answer,
    origin: generator.Handwritten,
  ))
}

/// A player who has pencilled every candidate into every empty cell.
pub fn fully_marked(current: game.Game) -> game.Game {
  let peers = board.peers_table()
  let grid = current.board.values

  let marked = {
    use marked, index <- list.fold(board.indices(), current.board)
    case board.value(marked, index) {
      0 -> {
        use marked, digit <- list.fold(
          board.candidates(grid, peers, index),
          marked,
        )
        board.toggle_mark(marked, index, digit)
      }
      _ -> marked
    }
  }

  game.Game(..current, board: marked)
}

/// How much is written in, and how much is pencilled in.
pub fn written_and_marked(current: game.Game) -> #(Int, Int) {
  let marks = {
    use total, index <- list.fold(board.indices(), 0)
    total + list.length(board.sorted_marks(current.board, index))
  }
  #(81 - board.empty_count(current.board), marks)
}

/// Mark a 4 in A3 (where the answer is a 4) and in A9, which can see it.
pub fn marked_around_a3() -> game.Game {
  let marked =
    game.Game(..fixture(), cursor: board.at(0, 8))
    |> step(key.Char("m"))
    |> step(key.Digit(4))
    |> step(key.Char("m"))

  game.Game(..marked, cursor: 2)
  |> step(key.Char("m"))
  |> step(key.Digit(4))
  |> step(key.Char("m"))
}

/// The fixture, solved by writing in every answer.
pub fn solved(current: game.Game) -> game.Game {
  use current, index <- list.fold(board.indices(), current)
  case board.value(current.board, index) {
    0 ->
      game.Game(..current, cursor: index)
      |> step(key.Digit(game.answer(current, index)))
    _ -> current
  }
}

/// One grid's worth of columns, and the whole frame's worth: two grids and
/// the gap between them.
pub const grid_columns = 27

pub const frame_width = 59

/// The board half of a line, and the marks half beside it.
pub fn board_half(line: String) -> String {
  string.slice(line, 1, grid_columns)
}

pub fn marks_half(line: String) -> String {
  string.slice(line, 1 + grid_columns + 4, grid_columns)
}

/// Drop ANSI escape sequences so that the layout underneath can be checked.
pub fn plain(text: String) -> String {
  strip(string.to_graphemes(text), [], Text)
}

type Scan {
  Text
  SawEscape
  InSequence
}

fn strip(characters: List(String), kept: List(String), scan: Scan) -> String {
  case characters, scan {
    [], _ -> kept |> list.reverse |> string.concat
    ["\u{1b}", ..rest], _ -> strip(rest, kept, SawEscape)
    // The `[` introducing a control sequence.
    [_, ..rest], SawEscape -> strip(rest, kept, InSequence)
    [character, ..rest], InSequence ->
      case string.contains("0123456789;?", character) {
        True -> strip(rest, kept, InSequence)
        False -> strip(rest, kept, Text)
      }
    [character, ..rest], Text -> strip(rest, [character, ..kept], Text)
  }
}

pub fn visible_lines(current: game.Game) -> List(String) {
  render.frame(current)
  |> plain
  |> string.split("\r\n")
  |> list.map(string.trim_end)
}

pub fn is_grid_row(line: String) -> Bool {
  ["A", "B", "C", "D", "E", "F", "G", "H", "I"]
  |> list.any(fn(label) {
    string.starts_with(line, " " <> label <> " \u{2502}")
  })
}

/// Pencil `digits` into the cell under the cursor and return to writing.
pub fn with_marks(current: game.Game, digits: List(Int)) -> game.Game {
  digits
  |> list.fold(step(current, key.Char("m")), fn(marking, digit) {
    step(marking, key.Digit(digit))
  })
  |> step(key.Char("m"))
}

/// The wash behind the cells a hint is arguing from. Checking for it means
/// reaching for the escape itself: a background leaves no mark on the text.
pub const hint_wash = "48;5;22;"

pub fn editor_lines(current: editor.Editor) -> List(String) {
  render.editor_frame(current)
  |> plain
  |> string.split("\r\n")
  |> list.map(string.trim_end)
}
