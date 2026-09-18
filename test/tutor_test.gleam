//// Being walked up to a technique.
////
//// Every grid here is one of the nine kept for practising, so the positions
//// are the same every time and the ladder can be asserted word for word.

import gleam/int
import gleam/list
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/key
import sudoku/logic
import sudoku/practice
import sudoku/rules
import sudoku/tutor

/// A practice game with the candidates pencilled in, which is where an
/// argument about candidates has to start.
fn practising(technique: logic.Technique) -> game.Game {
  let assert Ok(puzzle) = practice.puzzle(technique)
  let assert game.Continue(filled) =
    rules.update(game.new(puzzle), key.Char("f"))

  filled
}

/// Do what a player following the reasoning does — play the settles, rub out
/// the marks that are ruled out — until the technique being practised is the
/// step that comes next.
fn at_the_moment(technique: logic.Technique) -> game.Game {
  advanced(practising(technique), technique, 60)
}

fn advanced(
  current: game.Game,
  technique: logic.Technique,
  left: Int,
) -> game.Game {
  case left, logic.next_from(current.board.values, game.reading(current)) {
    0, _ -> current
    _, Error(_) -> current
    _, Ok(step) ->
      case step.technique == technique {
        True -> current
        False ->
          advanced(
            game.with_board(current, played(current, step)),
            technique,
            left - 1,
          )
      }
  }
}

fn played(current: game.Game, step: logic.Step) -> board.Board {
  case step.move {
    logic.Settle(index, digit) -> board.place(current.board, index, digit)
    logic.RuleOut(cells, digits) -> {
      use board, index <- list.fold(cells, current.board)
      use board, digit <- list.fold(digits, board)
      board.erase_mark(board, index, digit)
    }
  }
}

fn said(current: game.Game, asked: Int) -> String {
  let lesson = tutor.lesson(current, asked)
  lesson.what <> " " <> lesson.why
}

// ---------------------------------------------------------------------------
// The ladder
// ---------------------------------------------------------------------------

/// Each rung says a little more than the one before it, and the first says
/// the least that is still worth knowing: that this is the moment.
pub fn the_ladder_says_more_a_rung_at_a_time_test() {
  let at = at_the_moment(logic.XWing)

  let first = tutor.lesson(at, 1)
  assert string.contains(first.what, "X-wing")
  assert string.contains(first.what, "the moment")
  assert string.contains(first.why, "Nothing simpler")
  // The digit the step is about, and nothing about where it is.
  let assert Ok(step) = logic.next_from(at.board.values, game.reading(at))
  use digit <- list.each(step.about)
  assert string.contains(first.why, int.to_string(digit))
  assert first.lit == []

  let second = tutor.lesson(at, 2)
  assert string.contains(second.what, "row")
  assert second.lit == []

  let third = tutor.lesson(at, 3)
  use corner <- list.each(step.evidence)
  assert string.contains(third.what, board.name(corner))
  assert third.lit == step.evidence

  let fourth = tutor.lesson(at, 4)
  assert #(fourth.what, fourth.why) == explained(at)
}

fn explained(current: game.Game) -> #(String, String) {
  let assert Ok(step) =
    logic.next_from(current.board.values, game.reading(current))
  logic.explain(step)
}

/// The cells only light once the tutor has got as far as naming them.
/// Lighting them at the first nudge would be the answer rather than a nudge.
pub fn the_cells_light_only_once_they_are_named_test() {
  use technique <- list.each(practice.techniques())
  let at = at_the_moment(technique)

  assert tutor.lesson(at, 1).lit == []
  assert tutor.lesson(at, 2).lit == []
  assert tutor.lesson(at, 3).lit != []
  assert tutor.lesson(at, 4).lit != []
}

/// Asking past the bottom says the same thing rather than starting over.
pub fn asking_past_the_bottom_stays_there_test() {
  let at = at_the_moment(logic.NakedPair)

  assert said(at, tutor.rungs) == said(at, tutor.rungs + 5)
}

// ---------------------------------------------------------------------------
// Every technique
// ---------------------------------------------------------------------------

/// The ladder is worked out from the step rather than written down, so it
/// has something to say about all nine — including the three whose argument
/// is not read off a single unit.
pub fn the_moment_is_reachable_on_every_grid_test() {
  let missed = {
    use technique <- list.filter(practice.techniques())
    let at = at_the_moment(technique)
    case logic.next_from(at.board.values, game.reading(at)) {
      Ok(step) -> step.technique != technique
      Error(_) -> True
    }
  }

  assert list.map(missed, logic.label) == []
}

pub fn every_technique_gets_a_whole_ladder_test() {
  use technique <- list.each(practice.techniques())
  let at = at_the_moment(technique)
  let named = string.lowercase(logic.label(technique))

  use asked <- list.each([1, 2, 3, 4])
  let lesson = tutor.lesson(at, asked)

  // Nothing is empty, nothing is a placeholder, and the technique is named
  // at every rung so there is always something to look up.
  assert lesson.what != ""
  assert lesson.why != ""
  assert !string.contains(lesson.what, "nowhere")
  assert !string.contains(lesson.what, "those cells")
  assert string.contains(string.lowercase(lesson.what), named) || asked == 4

  // And both rows fit the two the board has under it. A frame writes each
  // line with a leading space into eighty columns, so seventy-eight is the
  // most there is room for; that a whole frame really fits is asked next
  // door, where frames are what is being looked at.
  assert string.length(lesson.what) <= 78
  assert string.length(lesson.why) <= 78
}

/// Where to look is the one rung that depends on the shape of the argument,
/// and there are four shapes rather than one: a unit for the five read off
/// one, the cell itself for a naked single, which has no unit in it at all,
/// the lines that cross for the two fish, and the pivot for the XY-wing,
/// whose three cells need share nothing.
pub fn where_to_look_suits_the_shape_of_the_argument_test() {
  let unit_shaped = [
    logic.HiddenSingle,
    logic.LockedCandidates,
    logic.NakedPair,
    logic.HiddenPair,
    logic.NakedTriple,
  ]

  use technique <- list.each(unit_shaped)
  let where = tutor.lesson(at_the_moment(technique), 2).what
  assert string.contains(where, "row")
    || string.contains(where, "column")
    || string.contains(where, "box")
}

/// A naked single rests on the one cell and is named by it. There is no
/// nudge short of the answer to be given about a cell that can only be one
/// thing, and pretending otherwise would be a rung that said nothing.
pub fn a_naked_single_is_pointed_at_by_its_cell_test() {
  let at = at_the_moment(logic.NakedSingle)
  let assert Ok(step) = logic.next_from(at.board.values, game.reading(at))
  let assert [only] = step.evidence

  assert string.contains(tutor.lesson(at, 2).what, board.name(only))
}

pub fn a_fish_is_pointed_at_by_its_lines_test() {
  use technique <- list.each([logic.XWing, logic.Swordfish])
  let where = tutor.lesson(at_the_moment(technique), 2).what

  assert string.contains(where, "row")
  assert string.contains(where, "column")
}

pub fn an_xy_wing_is_pointed_at_by_its_pivot_test() {
  let lesson = tutor.lesson(at_the_moment(logic.XYWing), 2)

  assert string.contains(lesson.what, "turns on")
}

// ---------------------------------------------------------------------------
// When it is not the moment
// ---------------------------------------------------------------------------

/// Being sent to do the easy thing first is a lesson of its own: the
/// reasoning always takes the simplest step going, and so should the person.
pub fn before_the_moment_it_sends_you_to_the_simpler_step_test() {
  // Fresh, before anything has been taken: the X-wing grid wants a locked
  // candidate first.
  let lesson = tutor.lesson(practising(logic.XWing), 1)

  assert string.contains(lesson.what, "something simpler")
  assert string.contains(string.lowercase(lesson.why), "locked candidates")
  assert string.contains(lesson.why, "X-wing")
  assert lesson.lit == []
}

pub fn it_says_so_away_from_a_practice_grid_test() {
  let lesson = tutor.lesson(helper.fixture(), 1)

  assert string.contains(lesson.what, "practice grid")
  assert lesson.lit == []
}

// ---------------------------------------------------------------------------
// What it costs
// ---------------------------------------------------------------------------

/// Nothing. The tutor never touches the board, which is the whole of why it
/// is worth having beside `H`: `H` plays the step and spends the one chance
/// the grid had to teach its technique, and this leaves it there.
pub fn the_tutor_never_touches_the_board_test() {
  let at = at_the_moment(logic.Swordfish)

  use asked <- list.each([1, 2, 3, 4, 5])
  let _ = tutor.lesson(at, asked)

  let assert game.Continue(pressed) = rules.update(at, key.Char("t"))
  assert pressed.board == at.board
  assert pressed.hints == at.hints
  assert pressed.aided == at.aided
  assert game.unaided(pressed)
}
