//// Turning the reasoning into a hint.
////
//// `logic` works out what can be settled next and why. This decides which of
//// those the player is actually asking about, checks it against the answer
//// before acting on it, and puts it on the board with the argument beside
//// it. The reasoning is kept apart from the asking on purpose: a technique
//// is a fact about a grid, and which cell to point it at is a question about
//// a person.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import sudoku/board
import sudoku/game
import sudoku/logic

/// The simplest step the reasoning can find, said out loud and then taken.
///
/// A hint used to name a digit and leave it at that, which answers the cell
/// and teaches nothing. Now it goes wherever the next move actually is and
/// says why it is there, so what the player takes away is the argument rather
/// than the digit.
pub fn hint(current: game.Game) -> game.Game {
  case warning_due(current) {
    True -> warn(current)
    False -> asked_for(game.Game(..current, aided: True))
  }
}

/// Whether to say what a hint costs before giving one.
///
/// Once, and only while there is something to lose by it: a game already
/// helped along has nothing left to spend, and a puzzle typed in was never
/// going to be timed.
fn warning_due(current: game.Game) -> Bool {
  game.at_stake(current) && current.offered != Some(game.TakeHint)
}

fn warn(current: game.Game) -> game.Game {
  game.Game(
    ..current,
    offered: Some(game.TakeHint),
    message: "A hint makes this an aided game, and aided games are not timed.\nPress H again to go ahead.",
  )
}

fn asked_for(current: game.Game) -> game.Game {
  case board.empty_count(current.board) {
    0 -> game.Game(..current, message: "The grid is already full.")
    _ ->
      case here(current) {
        // The cell being looked at is the cell being asked about.
        Ok(step) -> take(game.Game(..current, offered: None), step)

        Error(_) ->
          case waiting(current) {
            // Nothing to say about this one yet, and nothing said about it
            // yet either. Say so, and stay: the player is looking here for a
            // reason, and an answer three rows away is not one they asked
            // for.
            True -> hold(current)
            False -> elsewhere(game.Game(..current, offered: None))
          }
      }
  }
}

/// Whether this cell is worth waiting at: an empty one the player has not
/// already been told about.
fn waiting(current: game.Game) -> Bool {
  board.value(current.board, current.cursor) == 0
  && current.offered != Some(game.LookElsewhere(current.cursor))
}

fn hold(current: game.Game) -> game.Game {
  game.Game(
    ..current,
    offered: Some(game.LookElsewhere(current.cursor)),
    message: "Nothing settles "
      <> board.name(current.cursor)
      <> " yet.\nPress H again to look elsewhere.",
  )
}

fn elsewhere(current: game.Game) -> game.Game {
  case sound_step(current) {
    Ok(step) -> take(current, step)
    Error(_) -> tell(current)
  }
}

/// What can be said about the cell the player is on, if anything can.
///
/// A hint is asked for while staring at a particular cell more often than
/// not, so that is the cell it answers. Only when the board has nothing to
/// say about that one yet does the hint go looking elsewhere: better a move
/// somewhere else than an answer here it cannot account for.
fn here(current: game.Game) -> Result(logic.Step, Nil) {
  case board.value(current.board, current.cursor) {
    0 ->
      case logic.settles_from(game.reading(current), current.cursor) {
        Ok(step) -> sound(current, step)
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
fn sound_step(current: game.Game) -> Result(logic.Step, Nil) {
  case logic.next_from(current.board.values, game.reading(current)) {
    Error(_) -> Error(Nil)
    Ok(step) -> sound(current, step)
  }
}

/// The candidates as the player has them: their own marks wherever they have
/// made any, and everything the grid allows where they have not.
///
/// This is what stops a hint repeating itself. An elimination changes no
/// digit, so a hint that rubs marks out leaves the grid looking exactly as it
/// did and the same step waiting; read the marks instead and the position has
/// moved on, with the next step to show for it.
///
/// Marks that are wrong, or left behind, can lead the reasoning astray. They
/// cannot lead the player astray: every step is still checked against the
fn sound(current: game.Game, step: logic.Step) -> Result(logic.Step, Nil) {
  case step.move {
    logic.Settle(index, digit) ->
      case digit == game.answer(current, index) {
        True -> Ok(step)
        False -> Error(Nil)
      }

    // An elimination leaves the grid as it was, so the reasoning would hand
    // out the same one for ever. It is only worth offering when it rubs a
    // mark of the player's out: then something has moved, and the next hint
    // has something else to say.
    logic.RuleOut(cells, digits) ->
      case
        rules_out_the_answer(current, cells, digits),
        rubs_out(current, cells, digits)
      {
        False, True -> Ok(step)
        _, _ -> Error(Nil)
      }
  }
}

fn rules_out_the_answer(
  current: game.Game,
  cells: List(Int),
  digits: List(Int),
) -> Bool {
  use index <- list.any(cells)
  list.contains(digits, game.answer(current, index))
}

/// Whether any of it is pencilled in, and so whether rubbing it out would
/// show.
fn rubs_out(current: game.Game, cells: List(Int), digits: List(Int)) -> Bool {
  use index <- list.any(cells)
  let marks = board.marks_at(current.board, index)
  list.any(digits, set.contains(marks, _))
}

fn take(current: game.Game, step: logic.Step) -> game.Game {
  let #(what, why) = logic.explain(step)
  let said = what <> "\n" <> why

  case step.move {
    logic.Settle(index, digit) -> {
      let filled =
        current
        |> game.remember
        |> game.with_board(board.place(current.board, index, digit))

      game.Game(
        ..filled,
        cursor: index,
        hints: filled.hints + 1,
        message: said,
        showing: Some(step),
      )
      |> game.settle
    }

    // Nothing to write: a step that only rules candidates out rubs them out
    // of the player's marks instead, which is what they would do with it.
    logic.RuleOut(cells, digits) -> {
      let rubbed = {
        use grid, index <- list.fold(cells, current.board)
        use grid, digit <- list.fold(digits, grid)
        board.erase_mark(grid, index, digit)
      }

      let told = case rubbed == current.board {
        True -> current
        False -> current |> game.remember |> game.with_board(rubbed)
      }

      game.Game(
        ..told,
        cursor: list.first(cells) |> result.unwrap(current.cursor),
        hints: told.hints + 1,
        message: said,
        showing: Some(step),
      )
    }
  }
}

/// The hint of last resort: name the digit, as a hint always used to.
fn tell(current: game.Game) -> game.Game {
  let target = case board.value(current.board, current.cursor) {
    0 -> Some(current.cursor)
    _ -> game.first_empty(current.board)
  }

  case target {
    None -> game.Game(..current, message: "The grid is already full.")
    Some(index) -> {
      let filled =
        current
        |> game.remember
        |> game.with_board(board.place(
          current.board,
          index,
          game.answer(current, index),
        ))

      game.Game(
        ..filled,
        cursor: index,
        hints: filled.hints + 1,
        message: board.name(index)
          <> " is a "
          <> int.to_string(game.answer(current, index))
          <> ".\nNothing simple to reason from here, so that one is from the answer.",
      )
      |> game.settle
    }
  }
}
