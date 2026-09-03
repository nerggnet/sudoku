//// Game state and the rules for how a keystroke changes it.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import sudoku/board.{type Board}
import sudoku/generator.{type Puzzle}
import sudoku/key.{type Key}
import sudoku/term

const max_undo = 200

pub type Game {
  Game(
    puzzle: Puzzle,
    board: Board,
    cursor: Int,
    history: List(Board),
    message: String,
    /// Whether wrong digits are being called out.
    checking: Bool,
    /// Whether the digit keys write pencil marks instead of answers.
    marking: Bool,
    show_help: Bool,
    hints: Int,
    /// Set when the grid was revealed rather than solved by the player.
    revealed: Bool,
    started_ms: Int,
    finished_ms: Option(Int),
  )
}

/// What the main loop should do after handling a key.
pub type Step {
  Continue(Game)
  Restart
  Exit
}

pub fn new(puzzle: Puzzle) -> Game {
  Game(
    puzzle: puzzle,
    board: puzzle.board,
    cursor: first_empty(puzzle.board) |> option.unwrap(0),
    history: [],
    message: "Press ? for help.",
    checking: False,
    marking: False,
    show_help: False,
    hints: 0,
    revealed: False,
    started_ms: term.now_ms(),
    finished_ms: None,
  )
}

pub fn is_finished(game: Game) -> Bool {
  game.finished_ms != None
}

pub fn elapsed_ms(game: Game) -> Int {
  case game.finished_ms {
    Some(finished) -> finished - game.started_ms
    None -> term.now_ms() - game.started_ms
  }
}

/// The digit the solution has for a cell.
pub fn answer(game: Game, index: Int) -> Int {
  case dict.get(game.puzzle.solution, index) {
    Ok(digit) -> digit
    Error(_) -> 0
  }
}

/// A filled-in, non-clue cell that disagrees with the solution.
pub fn is_wrong(game: Game, index: Int) -> Bool {
  let digit = board.value(game.board, index)
  digit != 0
  && !board.is_given(game.board, index)
  && digit != answer(game, index)
}

pub fn update(game: Game, pressed: Key) -> Step {
  case pressed {
    key.Quit | key.Char("q") | key.Char("Q") -> Exit
    key.Char("n") | key.Char("N") -> Restart
    key.Char("?") -> Continue(Game(..game, show_help: !game.show_help))

    // While the help overlay is up, any other key dismisses it.
    _ if game.show_help -> Continue(Game(..game, show_help: False))

    _ if game.finished_ms != None ->
      Continue(Game(..game, message: "Press n for a new puzzle, or q to quit."))

    key.Up | key.Char("k") | key.Char("w") -> Continue(move(game, -1, 0))
    key.Down | key.Char("j") | key.Char("s") -> Continue(move(game, 1, 0))
    key.Left | key.Char("h") | key.Char("a") -> Continue(move(game, 0, -1))
    key.Right | key.Char("l") | key.Char("d") -> Continue(move(game, 0, 1))

    key.Digit(digit) if game.marking -> Continue(mark(game, digit))
    key.Digit(digit) -> Continue(place(game, digit))

    key.Erase if game.marking -> Continue(unmark(game))
    key.Erase -> Continue(erase(game))

    key.Char("m") -> Continue(toggle_marking(game))
    key.Char("u") -> Continue(undo(game))
    key.Char("c") -> Continue(toggle_check(game))
    key.Char("H") -> Continue(hint(game))
    key.Char("R") -> Continue(reveal(game))

    _ -> Continue(game)
  }
}

fn move(game: Game, rows: Int, cols: Int) -> Game {
  let row = { board.row_of(game.cursor) + rows + board.side } % board.side
  let col = { board.col_of(game.cursor) + cols + board.side } % board.side
  Game(..game, cursor: board.at(row, col), message: "")
}

fn place(game: Game, digit: Int) -> Game {
  case board.is_given(game.board, game.cursor) {
    True -> Game(..game, message: "That cell is a clue and cannot change.")
    False ->
      game
      |> remember
      |> with_board(board.place(game.board, game.cursor, digit))
      |> settle
  }
}

fn toggle_marking(game: Game) -> Game {
  case game.marking {
    True -> Game(..game, marking: False, message: "Back to writing digits.")
    False ->
      Game(
        ..game,
        marking: True,
        message: "Marking: 1-9 pencils a digit in, 0 clears the cell.",
      )
  }
}

/// Pencil a digit into the cell, or rub it out if it is already there.
fn mark(game: Game, digit: Int) -> Game {
  case
    board.is_given(game.board, game.cursor),
    board.value(game.board, game.cursor)
  {
    True, _ -> Game(..game, message: "That cell is a clue and cannot change.")
    _, 0 ->
      game
      |> remember
      |> with_board(board.toggle_mark(game.board, game.cursor, digit))
    _, _ ->
      Game(
        ..game,
        message: "There is a digit here already. Press 0 to clear it first.",
      )
  }
}

fn unmark(game: Game) -> Game {
  case set.is_empty(board.marks_at(game.board, game.cursor)) {
    True -> Game(..game, message: "")
    False ->
      game
      |> remember
      |> with_board(board.clear_marks(game.board, game.cursor))
  }
}

fn erase(game: Game) -> Game {
  case
    board.is_given(game.board, game.cursor),
    board.value(game.board, game.cursor)
  {
    True, _ -> Game(..game, message: "That cell is a clue and cannot change.")
    False, 0 -> Game(..game, message: "")
    False, _ ->
      game
      |> remember
      |> with_board(board.erase(game.board, game.cursor))
  }
}

/// Only reachable while the puzzle is unfinished, so there is no finished
/// state to walk back out of.
fn undo(game: Game) -> Game {
  case game.history {
    [] -> Game(..game, message: "Nothing left to undo.")
    [previous, ..rest] ->
      Game(..game, board: previous, history: rest, message: "Undone.")
  }
}

fn toggle_check(game: Game) -> Game {
  case game.checking {
    True -> Game(..game, checking: False, message: "Checking off.")
    False -> {
      let wrong = list.count(board.indices(), is_wrong(game, _))
      let message = case wrong {
        0 -> "Nothing wrong so far."
        1 -> "1 digit is wrong."
        _ -> int.to_string(wrong) <> " digits are wrong."
      }
      Game(..game, checking: True, message: message)
    }
  }
}

/// Fill in the cursor cell, or the first empty cell if the cursor is already
/// on a filled one.
fn hint(game: Game) -> Game {
  let target = case board.value(game.board, game.cursor) {
    0 -> Some(game.cursor)
    _ -> first_empty(game.board)
  }

  case target {
    None -> Game(..game, message: "The grid is already full.")
    Some(index) -> {
      let filled =
        game
        |> remember
        |> with_board(board.place(game.board, index, answer(game, index)))

      Game(
        ..filled,
        cursor: index,
        hints: filled.hints + 1,
        message: "Hint: that cell is a " <> int.to_string(answer(game, index)),
      )
      |> settle
    }
  }
}

fn reveal(game: Game) -> Game {
  let solved =
    list.fold(board.indices(), game.board, fn(current, index) {
      board.place(current, index, answer(game, index))
    })

  let shown = game |> remember |> with_board(solved)

  // No message: the finished panel already says what happened.
  Game(
    ..shown,
    revealed: True,
    checking: False,
    finished_ms: Some(term.now_ms()),
  )
}

fn with_board(game: Game, next: Board) -> Game {
  Game(..game, board: next, message: "")
}

fn remember(game: Game) -> Game {
  Game(..game, history: list.take([game.board, ..game.history], max_undo))
}

/// Notice when the last keystroke completed the puzzle.
fn settle(game: Game) -> Game {
  case board.is_solved(game.board) {
    False -> game
    True -> Game(..game, finished_ms: Some(term.now_ms()), checking: False)
  }
}

fn first_empty(current: Board) -> Option(Int) {
  board.indices()
  |> list.find(fn(index) { board.value(current, index) == 0 })
  |> option.from_result
}
