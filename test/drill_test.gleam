//// The positions kept to drill a technique on.
////
//// A drill is three numbers rather than a grid, so what is written down
//// cannot be read to see whether it is right. Only building it can, which
//// is what this does: every position in the table, dealt and walked to, and
//// asked whether its technique really is the step that comes next.
////
//// Split by difficulty because building them means dealing them, and a
//// Master deal takes a second or two.

import gleam/dict
import gleam/list
import gleam/option
import sudoku/board
import sudoku/game
import sudoku/generator
import sudoku/logic
import sudoku/practice
import sudoku/solver

fn built(
  technique: logic.Technique,
  drill: practice.Drill,
) -> generator.Puzzle {
  practice.drilled(technique, drill, fn(_) { Nil })
}

/// What every drill has to be: at the moment, honest, and playable on.
fn sound(technique: logic.Technique, drill: practice.Drill) -> Nil {
  let position = built(technique, drill)
  let started = game.new(position)

  // The technique is the very next step. This is the whole promise.
  let assert Ok(step) =
    logic.next_from(started.board.values, game.reading(started))
  assert step.technique == technique

  // The candidates are already pencilled in, an argument about candidates
  // needing some on the board to be about.
  assert dict.size(position.board.marks) > 0

  // What is already filled in was put there by the reasoning, so it is right
  // and it is a clue.
  assert board.is_consistent(position.board.values)
  use index <- list.each(board.indices())
  case board.value(position.board, index) {
    0 -> {
      assert !board.is_given(position.board, index)
    }
    digit -> {
      assert board.is_given(position.board, index)
      assert dict.get(position.solution, index) == Ok(digit)
    }
  }
}

fn all_of(techniques: List(logic.Technique)) -> Nil {
  use technique <- list.each(techniques)
  use drill <- list.each(practice.drills_for(technique))
  sound(technique, drill)
}

pub fn the_singles_and_locked_candidates_drills_are_sound_test() {
  all_of([logic.NakedSingle, logic.HiddenSingle, logic.LockedCandidates])
}

pub fn the_pair_and_triple_drills_are_sound_test() {
  all_of([logic.NakedPair, logic.HiddenPair, logic.NakedTriple])
}

pub fn the_x_wing_drills_are_sound_test() {
  all_of([logic.XWing])
}

pub fn the_xy_wing_drills_are_sound_test() {
  all_of([logic.XYWing])
}

pub fn the_swordfish_drills_are_sound_test() {
  all_of([logic.Swordfish])
}

// ---------------------------------------------------------------------------
// The table itself
// ---------------------------------------------------------------------------

/// Every technique has somewhere to go after its one kept grid, which is
/// the whole reason the table exists.
pub fn every_technique_has_positions_to_drill_test() {
  use technique <- list.each(practice.techniques())
  assert practice.drills_for(technique) != []
}

/// More than one, or it is the kept grid over again under another name.
pub fn every_technique_has_more_than_one_test() {
  use technique <- list.each(practice.techniques())
  assert list.length(practice.drills_for(technique)) >= 2
}

/// No position is written down twice. A drill that came round again when
/// the table said it would not is a drill nobody is learning from.
pub fn no_position_is_kept_twice_test() {
  let every = {
    use technique <- list.flat_map(practice.techniques())
    practice.drills_for(technique)
  }

  assert list.unique(every) == every
}

/// A position is only worth drilling if the puzzle it came out of had one
/// answer, which is the same thing this game asks of every puzzle.
pub fn a_drill_is_a_position_in_a_real_puzzle_test() {
  let assert [drill, ..] = practice.drills_for(logic.XWing)
  let position = built(logic.XWing, drill)

  assert solver.count_solutions(position.board.values, 2) == 1
  assert board.is_solved(board.from_grid(position.solution))
}

/// Nothing about a drill is timed or written down, the same as the grid it
/// comes after: it is a position handed out to be looked at.
pub fn a_drill_is_not_timed_test() {
  let assert [drill, ..] = practice.drills_for(logic.Swordfish)
  let position = built(logic.Swordfish, drill)

  assert position.origin == generator.Practising(logic.Swordfish)
  assert position.seed == option.None
}
