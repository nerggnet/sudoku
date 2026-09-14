//// Game state and the rules for how a keystroke changes it.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import sudoku/board.{type Board}
import sudoku/generator.{type Puzzle}
import sudoku/key.{type Key}
import sudoku/logic
import sudoku/term

const max_undo = 200

/// How many wrong digits checking will call out before the puzzle is lost.
/// The one after that forfeits it.
///
/// Checking turns a guess into a free question, and without a price on it
/// there is nothing to stop a player asking the grid rather than reading it.
pub const mistake_limit = 3

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
    /// The page of help on show, if any.
    help: Option(Help),
    hints: Int,
    /// Wrong digits checking has caught, counting towards `mistake_limit`.
    mistakes: Int,
    /// How the game ended, once it has. Set together with `finished_ms`.
    ending: Option(Ending),
    started_ms: Int,
    finished_ms: Option(Int),
  )
}

/// The help, a page at a time: the keys, and then a page on each way of
/// working a digit out.
pub type Help {
  Keys
  About(logic.Technique)
}

/// Every page, in the order they are paged through.
pub fn pages() -> List(Help) {
  [Keys, ..list.map(logic.techniques, About)]
}

/// The three ways a game can be over.
pub type Ending {
  Solved
  /// The grid was revealed rather than worked out.
  Revealed
  /// One wrong digit too many while checking.
  Forfeited
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
    help: None,
    hints: 0,
    mistakes: 0,
    ending: None,
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
  case game.help {
    Some(page) -> browse(game, page, pressed)
    None -> play(game, pressed)
  }
}

/// While the help is up it has the keyboard to itself: the arrows turn the
/// pages and anything else puts it away. Nothing reaches the board, so there
/// is no reading about a technique and moving the cursor by accident.
fn browse(game: Game, page: Help, pressed: Key) -> Step {
  case pressed {
    key.Quit | key.Char("q") | key.Char("Q") -> Exit
    key.Right | key.Char("l") -> Continue(turn(game, page, 1))
    key.Left | key.Char("h") -> Continue(turn(game, page, -1))
    _ -> Continue(Game(..game, help: None))
  }
}

fn turn(game: Game, page: Help, by: Int) -> Game {
  let pages = pages()
  let count = list.length(pages)
  let at = case list.take_while(pages, fn(other) { other != page }) {
    before -> list.length(before)
  }

  let next = case list.drop(pages, { at + by + count } % count) {
    [page, ..] -> page
    [] -> Keys
  }

  Game(..game, help: Some(next))
}

fn play(game: Game, pressed: Key) -> Step {
  case pressed {
    key.Quit | key.Char("q") | key.Char("Q") -> Exit
    key.Char("n") | key.Char("N") -> Restart
    key.Char("?") -> Continue(Game(..game, help: Some(Keys)))

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
    key.Char("c") -> Continue(start_checking(game))
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
    False -> {
      let written = game |> remember |> with_board(written(game, digit))

      case caught(game, digit) {
        False -> settle(written)
        True -> count_against(written)
      }
    }
  }
}

/// Whether checking is about to call this digit out as wrong. Writing the
/// digit a cell already holds changes nothing, so it costs nothing either.
fn caught(game: Game, digit: Int) -> Bool {
  game.checking
  && digit != answer(game, game.cursor)
  && digit != board.value(game.board, game.cursor)
}

/// Put a caught digit on the tally, and end the game once the tally is past
/// what checking allows.
///
/// Undo takes the digit back but not the mistake. It was checking that told
/// the player the digit was wrong, and undo cannot untell them.
fn count_against(game: Game) -> Game {
  let mistakes = game.mistakes + 1

  case mistakes > mistake_limit {
    True -> forfeit(Game(..game, mistakes: mistakes))
    False ->
      Game(
        ..game,
        mistakes: mistakes,
        message: "Wrong. " <> allowance(mistake_limit - mistakes),
      )
  }
}

fn forfeit(game: Game) -> Game {
  Game(..game, ending: Some(Forfeited), finished_ms: Some(term.now_ms()))
}

/// What is left of the allowance, as the player is told it. Never called with
/// none left: running out is the end of the game, not a state to report.
fn allowance(left: Int) -> String {
  case left {
    0 -> "The next one forfeits the puzzle."
    1 -> "One more forfeits the puzzle."
    _ -> int.to_string(left) <> " more forfeit the puzzle."
  }
}

/// Writing a digit tidies up the marks around it, but not one that checking
/// is calling out as wrong in the same breath. Those marks are the reasoning
/// the wrong digit interrupted, and rubbing them out would cost the player
/// the work they need to put it right.
///
/// Only while checking: with it off the game is saying nothing about whether
/// a digit is right, and marks that quietly survived would be saying it.
fn written(game: Game, digit: Int) -> Board {
  case game.checking && digit != answer(game, game.cursor) {
    True -> board.write(game.board, game.cursor, digit)
    False -> board.place(game.board, game.cursor, digit)
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

/// Checking goes on and stays on.
///
/// It is a bargain rather than a switch: a player who could turn it off again
/// would be asking the grid one question at a time and paying for none of
/// them. So the wrong digits it finds on the way in go on the tally, along
/// with every one written after.
///
/// Finding more wrong than the allowance forfeits the puzzle there and then,
/// the same as writing one too many would. Being over the allowance is not a
/// state to go on playing in: the game would be asking the player to carry a
/// debt it will never let them pay off.
fn start_checking(game: Game) -> Game {
  case game.checking {
    True -> Game(..game, message: "Checking stays on now it is on.")
    False -> {
      let found = list.count(board.indices(), is_wrong(game, _))
      let mistakes = game.mistakes + found
      let checking = Game(..game, checking: True, mistakes: mistakes)

      case mistakes > mistake_limit {
        // No message: the finished panel says what happened, and how much.
        True -> forfeit(checking)
        False ->
          Game(
            ..checking,
            message: found_message(found)
              <> " "
              <> allowance(mistake_limit - mistakes),
          )
      }
    }
  }
}

fn found_message(found: Int) -> String {
  case found {
    0 -> "Checking on, for good."
    1 -> "Checking on: 1 digit is wrong."
    _ -> "Checking on: " <> int.to_string(found) <> " digits are wrong."
  }
}

/// The simplest step the reasoning can find, said out loud and then taken.
///
/// A hint used to name a digit and leave it at that, which answers the cell
/// and teaches nothing. Now it goes wherever the next move actually is and
/// says why it is there, so what the player takes away is the argument rather
/// than the digit.
fn hint(game: Game) -> Game {
  case board.empty_count(game.board) {
    0 -> Game(..game, message: "The grid is already full.")
    _ ->
      case here(game), sound_step(game) {
        // The cell being looked at is the cell being asked about.
        Ok(step), _ -> take(game, step)
        _, Ok(step) -> take(game, step)
        _, _ -> tell(game)
      }
  }
}

/// What can be said about the cell the player is on, if anything can.
///
/// A hint is asked for while staring at a particular cell more often than
/// not, so that is the cell it answers. Only when the board has nothing to
/// say about that one yet does the hint go looking elsewhere: better a move
/// somewhere else than an answer here it cannot account for.
fn here(game: Game) -> Result(logic.Step, Nil) {
  case board.value(game.board, game.cursor) {
    0 ->
      case logic.settles(game.board.values, game.cursor) {
        Ok(step) -> sound(game, step)
        Error(_) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

/// The reasoning's next step, but only where it agrees with the answer.
///
/// The reasoning works from what is on the board, and a wrong digit already
/// there can lead it somewhere the answer does not go. A hint that fills in
/// the wrong digit would be worse than no hint at all, so one that disagrees
/// with the answer is dropped and the plain telling takes over.
fn sound_step(game: Game) -> Result(logic.Step, Nil) {
  case logic.next(game.board.values) {
    Error(_) -> Error(Nil)
    Ok(step) -> sound(game, step)
  }
}

fn sound(game: Game, step: logic.Step) -> Result(logic.Step, Nil) {
  case step.move {
    logic.Settle(index, digit) ->
      case digit == answer(game, index) {
        True -> Ok(step)
        False -> Error(Nil)
      }

    // An elimination leaves the grid as it was, so the reasoning would hand
    // out the same one for ever. It is only worth offering when it rubs a
    // mark of the player's out: then something has moved, and the next hint
    // has something else to say.
    logic.RuleOut(cells, digits) ->
      case
        rules_out_the_answer(game, cells, digits),
        rubs_out(game, cells, digits)
      {
        False, True -> Ok(step)
        _, _ -> Error(Nil)
      }
  }
}

fn rules_out_the_answer(
  game: Game,
  cells: List(Int),
  digits: List(Int),
) -> Bool {
  use index <- list.any(cells)
  list.contains(digits, answer(game, index))
}

/// Whether any of it is pencilled in, and so whether rubbing it out would
/// show.
fn rubs_out(game: Game, cells: List(Int), digits: List(Int)) -> Bool {
  use index <- list.any(cells)
  let marks = board.marks_at(game.board, index)
  list.any(digits, set.contains(marks, _))
}

fn take(game: Game, step: logic.Step) -> Game {
  let #(what, why) = logic.explain(step)
  let said = what <> "\n" <> why

  case step.move {
    logic.Settle(index, digit) -> {
      let filled =
        game
        |> remember
        |> with_board(board.place(game.board, index, digit))

      Game(..filled, cursor: index, hints: filled.hints + 1, message: said)
      |> settle
    }

    // Nothing to write: a step that only rules candidates out rubs them out
    // of the player's marks instead, which is what they would do with it.
    logic.RuleOut(cells, digits) -> {
      let rubbed = {
        use current, index <- list.fold(cells, game.board)
        use current, digit <- list.fold(digits, current)
        board.erase_mark(current, index, digit)
      }

      let told = case rubbed == game.board {
        True -> game
        False -> game |> remember |> with_board(rubbed)
      }

      Game(
        ..told,
        cursor: list.first(cells) |> result.unwrap(game.cursor),
        hints: told.hints + 1,
        message: said,
      )
    }
  }
}

/// The hint of last resort: name the digit, as a hint always used to.
fn tell(game: Game) -> Game {
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
        message: board.name(index)
          <> " is a "
          <> int.to_string(answer(game, index))
          <> ".\nNothing simple to reason from here, so that one is from the answer.",
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
    ending: Some(Revealed),
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
    True ->
      Game(
        ..game,
        ending: Some(Solved),
        finished_ms: Some(term.now_ms()),
        checking: False,
      )
  }
}

fn first_empty(current: Board) -> Option(Int) {
  board.indices()
  |> list.find(fn(index) { board.value(current, index) == 0 })
  |> option.from_result
}
