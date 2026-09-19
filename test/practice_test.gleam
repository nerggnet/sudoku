//// The puzzles kept to be practised on.
////
//// Every claim these make is invisible by eye — that a grid has one answer,
//// that it cannot be finished without its technique, that it needs nothing
//// harder — so all of it is checked here. Eighty-one characters are easy to
//// mistype and a practice grid that quietly teaches the wrong lesson, or no
//// lesson, is worse than none.

import gleam/dict
import gleam/list
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/generator
import sudoku/key
import sudoku/logic
import sudoku/practice
import sudoku/solver
import sudoku/store

pub fn there_is_a_puzzle_for_every_technique_test() {
  // The help has a page on each, and each page sends the reader here.
  assert practice.techniques() == logic.techniques
}

pub fn every_grid_is_a_puzzle_test() {
  use technique <- list.each(practice.techniques())
  let assert Ok(puzzle) = practice.puzzle(technique)
    as "every kept grid parses and can be played"

  // Exactly one answer, or the game has nothing to check against.
  assert solver.count_solutions(puzzle.board.values, 5) == 1
  assert board.is_solved(board.from_grid(puzzle.solution))
  assert puzzle.origin == generator.Practising(technique)
}

pub fn every_grid_needs_its_technique_and_nothing_harder_test() {
  use technique <- list.each(practice.techniques())
  let assert Ok(puzzle) = practice.puzzle(technique)

  // Rated at the technique it is filed under: the reasoning had to reach for
  // it, and never had to reach past it. Since the reasoning always takes the
  // easiest step going, a grid rated here is one where nothing simpler was
  // available at the moment it was used — so the player meets it too.
  assert logic.rate(puzzle.board.values) == Ok(technique)

  // And meets it early, rather than after an hour of singles.
  let #(steps, _) = logic.unfold(puzzle.board.values)
  let assert Ok(first) =
    list.find(steps, fn(step) { step.technique == technique })
  let before = list.take_while(steps, fn(step) { step.technique != technique })

  assert list.length(before) < 20
  assert first.technique == technique
}

pub fn a_practice_grid_is_gentler_than_the_puzzle_it_came_from_test() {
  // Each was given back every clue it could take while still needing its
  // technique, so none of them is a bare Expert grid. Seventeen is the floor
  // a dealt puzzle is carved to; these are nowhere near it.
  use technique <- list.each(practice.techniques())
  assert practice.clue_count(technique) >= 30
}

pub fn practice_is_offered_after_the_puzzles_there_are_to_deal_test() {
  assert practice.choice() == list.length(generator.origins()) + 1
}

pub fn a_practice_game_is_not_timed_test() {
  // The same grid every time, so a time on it would be a record of having
  // seen it before rather than of having solved it.
  let assert Ok(puzzle) = practice.puzzle(logic.XWing)
  let solved = helper.solved(game.new(puzzle))

  assert store.judge(solved, dict.new(), dict.new()) == game.Untimed
}

pub fn the_opening_line_says_what_is_being_practised_test() {
  use technique <- list.each(practice.techniques())
  let assert Ok(puzzle) = practice.puzzle(technique)
  let started = game.new(puzzle)

  // Which technique was chosen a screen ago; being told again is what makes
  // the grid a lesson rather than a puzzle that is hard in one place.
  assert string.contains(started.message, logic.labels(technique))
  assert string.contains(started.message, "?")

  // And the header names the technique rather than a difficulty, so that
  // which grid this is survives the opening line being written over.
  assert generator.origin_label(puzzle.origin) == logic.title(technique)
}

/// The header keeps saying it. The opening line goes the moment anything
/// else needs the row — a hint, a clash, a word about marking — and before
/// this there was then nothing on the screen to say which grid you were on.
pub fn the_header_keeps_saying_what_is_being_practised_test() {
  use technique <- list.each(practice.techniques())
  let assert Ok(puzzle) = practice.puzzle(technique)

  // Somebody has played a little and the opening line is long gone.
  let played =
    helper.step(helper.step(game.new(puzzle), key.Char("m")), key.Char("m"))
  assert !string.contains(played.message, logic.labels(technique))

  let assert [title, ..] = helper.visible_lines(played)
  assert string.contains(title, logic.title(technique))
}

/// Nothing on a practice grid is timed, so there is no time for help to
/// have cost and nothing for the header to qualify. What the solve was done
/// with is still said in the panel at the end.
pub fn a_practice_grid_is_never_called_aided_test() {
  let assert Ok(puzzle) = practice.puzzle(logic.XWing)
  let checked = helper.checked(game.new(puzzle))

  assert !game.unaided(checked)
  assert !game.timed(checked)

  let assert [title, ..] = helper.visible_lines(checked)
  assert !string.contains(title, "aided")
}

/// The screen offering them puts a digit in front of each, so there is room
/// for nine and no more. A tenth technique would be one nobody could pick.
pub fn every_technique_can_be_picked_by_a_digit_test() {
  assert list.length(practice.techniques()) <= 9

  // And the same list, in the order the help pages them, so the screen is a
  // ladder as well as a menu.
  assert practice.techniques() == logic.techniques
}
