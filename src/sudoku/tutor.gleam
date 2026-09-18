//// Being walked up to a technique on a grid that needs one.
////
//// The practice grids each want their technique exactly once — a naked pair
//// or an X-wing or a swordfish turns up on the third or fourth step and
//// never again, and the thirty steps after it are singles. So there is one
//// moment to learn from per grid, and the only help there was took it: `H`
//// works the step out and plays it, and the moment is gone. Somebody who
//// has never seen an X-wing got one look at one, from the far side of
//// having it done for them.
////
//// This says things instead. It never touches the board, which is what
//// makes it free to ask and free to ask again: the moment is still there
//// afterwards, and so is the grid.
////
//// It teaches whatever step is in front of you rather than only the one the
//// grid was kept for. A grid that wants an X-wing wants a dozen other things
//// on the way to it, and somebody who has never seen an X-wing has most
//// likely never seen a hidden pair either — so being told to go and work the
//// easy ones out alone is being told no at the one moment they asked. Every
//// rung still opens with "nothing simpler works from here", which is true of
//// every step there is: the reasoning always takes the simplest one going,
//// and that lesson is now in each of them rather than in a refusal.
////
//// Answers are worked out from `logic` rather than written down. What a
//// step rests on, which digits it is about and which unit it was read in
//// are all carried on a `Step` already, and they turn out to be exactly the
//// rungs somebody wants in that order: the digit, then where, then which
//// cells, then why.

import gleam/int
import gleam/list
import gleam/string
import sudoku/board
import sudoku/game.{type Game}
import sudoku/generator
import sudoku/logic

/// What the tutor has to say, and the cells it is saying it about.
///
/// Two lines, because that is what the board has room for under it and what
/// a hint already says: the thing, and the reason or the way on.
pub type Lesson {
  Lesson(what: String, why: String, lit: List(Int))
}

/// How many times the tutor can usefully be asked before it has said
/// everything it knows.
pub const rungs = 4

/// What to say about this position, having been asked this many times over.
///
/// Asked afresh every frame rather than remembered, so moving the cursor
/// about under a lesson leaves the lesson where it was.
pub fn lesson(current: Game, asked: Int) -> Lesson {
  case wanted(current) {
    Error(_) ->
      Lesson(
        what: "The tutor works on a practice grid.",
        why: "Pick a technique from the menu and it will walk you up to one.",
        lit: [],
      )
    Ok(technique) -> about(current, technique, asked)
  }
}

/// The technique this grid was kept to teach, if it was kept to teach one.
fn wanted(current: Game) -> Result(logic.Technique, Nil) {
  case current.puzzle.origin {
    generator.Practising(technique) -> Ok(technique)
    _ -> Error(Nil)
  }
}

fn about(current: Game, technique: logic.Technique, asked: Int) -> Lesson {
  case logic.next_from(current.board.values, game.reading(current)) {
    // Nothing follows from what is on the board. On a practice grid that
    // means the player has written something in that cannot be true.
    Error(_) ->
      Lesson(
        what: "Nothing follows from the board as it stands.",
        why: "Something written in is wrong. u takes it back, X starts over.",
        lit: [],
      )

    // Whatever the step turns out to be, not only the one the grid was kept
    // for. A grid that wants an X-wing wants a dozen other things on the way
    // to it, and being sent away to work those out alone is being sent away
    // at the one moment somebody asked for help.
    Ok(step) -> rung(step, step.technique == technique, asked)
  }
}

/// The ladder, a rung at a time.
///
/// Each says less than the one after it on purpose. Somebody who can find an
/// X-wing once they know which digit to look for has learnt more than
/// somebody shown four cells, and much more than somebody shown the answer.
///
/// The first rung says whether this is the technique the grid was kept for,
/// since that is the one somebody came to meet and is worth knowing when it
/// arrives. The rest of the ladder is the same either way: a step is a step.
fn rung(step: logic.Step, came_for: Bool, asked: Int) -> Lesson {
  let named = capitalised(logic.label(step.technique))

  case asked {
    1 ->
      Lesson(
        what: named
          <> case came_for {
          True -> ": this is the moment."
          False -> ": there is one here."
        },
        why: "Nothing simpler works from here. Look for "
          <> written(step.about)
          <> ". Press t again for where.",
        lit: [],
      )

    2 ->
      Lesson(
        what: named <> ": look " <> where(step) <> ".",
        why: "Press t again for the cells it rests on.",
        lit: [],
      )

    3 ->
      Lesson(
        what: named <> ": " <> cell_names(step.evidence) <> ".",
        why: "Those are the cells. Press t again for the argument.",
        lit: step.evidence,
      )

    // Everything there is to say. The board is still untouched: H will play
    // the step, and X will put the grid back to try it again.
    _ -> {
      let #(what, why) = logic.explain(step)
      Lesson(what: what, why: why, lit: step.evidence)
    }
  }
}

/// Where to look, preposition and all, which is the one rung that depends
/// on the shape of the argument rather than on what a `Step` carries. You
/// look *in* a unit and *at* a cell, and which of those it is is part of the
/// shape rather than part of the sentence.
fn where(step: logic.Step) -> String {
  case step.technique, step.unit {
    // Three cells that need share no unit at all. The pivot is the one to
    // look at: the two wings follow from it.
    logic.XYWing, _ ->
      case step.evidence {
        [pivot, ..] -> "at the cell it turns on, " <> board.name(pivot)
        [] -> "at the cells it rests on"
      }

    // Read off one unit, and the step carries which.
    _, [_, ..] -> "in " <> unit_named(step.unit)

    // A naked single rests on the one cell and carries no unit, there being
    // nothing about a unit in it. Naming the cell is the whole of where.
    _, [] if step.evidence == [] -> "at the cells it rests on"

    // A fish, which is read off a rectangle rather than a unit. Both sets of
    // lines are named: which is the base and which the cover is the thing
    // being learnt, and saying it here would be saying the answer.
    _, [] ->
      case step.evidence {
        [only] -> "at " <> board.name(only)
        _ -> crossing(step)
      }
  }
}

fn crossing(step: logic.Step) -> String {
  "where "
  <> lines("row", step.evidence, board.row_of, board.row_letter)
  <> " cross "
  <> lines("column", step.evidence, board.col_of, fn(at) {
    int.to_string(at + 1)
  })
}

/// What to call a unit, worked out from the cells in it.
fn unit_named(unit: List(Int)) -> String {
  case unit {
    [] -> "nowhere"
    [first, ..] ->
      case
        alike(unit, board.row_of),
        alike(unit, board.col_of),
        alike(unit, board.box_of)
      {
        True, _, _ -> board.row_name(first)
        _, True, _ -> board.column_name(first)
        _, _, True -> board.box_name(first)
        _, _, _ -> "those cells"
      }
  }
}

fn alike(cells: List(Int), of: fn(Int) -> Int) -> Bool {
  case list.map(cells, of) {
    [] -> False
    [first, ..rest] -> list.all(rest, fn(other) { other == first })
  }
}

/// `rows B and F`, `columns 1, 4 and 8`.
fn lines(
  what: String,
  cells: List(Int),
  of: fn(Int) -> Int,
  naming: fn(Int) -> String,
) -> String {
  let named =
    cells
    |> list.map(of)
    |> list.unique
    |> list.sort(int.compare)
    |> list.map(naming)

  case named {
    [one] -> what <> " " <> one
    _ -> what <> "s " <> joined(named)
  }
}

fn cell_names(cells: List(Int)) -> String {
  cells |> list.map(board.name) |> joined
}

fn written(digits: List(Int)) -> String {
  digits
  |> list.unique
  |> list.sort(int.compare)
  |> list.map(int.to_string)
  |> joined
}

/// `A1`, `A1 and B2`, `A1, B2 and C3`.
fn joined(words: List(String)) -> String {
  case list.reverse(words) {
    [] -> "nothing"
    [only] -> only
    [last, ..rest] ->
      { rest |> list.reverse |> string.join(", ") } <> " and " <> last
  }
}

fn capitalised(name: String) -> String {
  string.uppercase(string.slice(name, 0, 1))
  <> string.slice(name, 1, string.length(name) - 1)
}
