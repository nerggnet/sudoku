//// Starting the same puzzle again.

import gleam/list
import gleam/option
import gleam/set
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/key

/// A game with work on it: digits, marks, and a wrong one caught by checking.
fn under_way() -> game.Game {
  helper.blunder(helper.checked(helper.fixture()), helper.some_blanks(1))
  |> helper.step(key.Char("f"))
}

pub fn starting_again_is_asked_for_twice_test() {
  let asked = helper.step(under_way(), key.Char("X"))

  assert asked.offered == option.Some(game.StartAgain)
  assert string.contains(asked.message, "Press X again")
  // Nothing has happened to the grid yet.
  assert asked.board == under_way().board

  let again = helper.step(asked, key.Char("X"))
  assert again.board.values == again.puzzle.board.values
}

pub fn the_offer_lapses_like_any_other_test() {
  // Anything but X puts it away, so a key pressed a minute later cannot turn
  // out to have meant this.
  let wandered =
    under_way() |> helper.step(key.Char("X")) |> helper.step(key.Down)

  assert wandered.offered == option.None
  assert helper.step(wandered, key.Char("X")).board == wandered.board
}

pub fn a_puzzle_with_nothing_on_it_starts_again_at_once_test() {
  // Nothing to lose, nothing to ask about.
  let untouched = helper.step(helper.fixture(), key.Char("X"))

  assert untouched.offered == option.None
  assert untouched.board.values == untouched.puzzle.board.values
}

pub fn starting_again_leaves_the_clues_and_nothing_else_test() {
  let again =
    under_way() |> helper.step(key.Char("X")) |> helper.step(key.Char("X"))

  // The clues, no marks, and the cursor back where a new game would put it.
  assert again.board == again.puzzle.board
  assert again.cursor == option.unwrap(game.first_empty(again.puzzle.board), 0)

  use index <- list.each(board.indices())
  assert set.is_empty(board.marks_at(again.board, index))
}

pub fn what_the_game_has_cost_does_not_start_again_test() {
  let spent = under_way()
  let again = spent |> helper.step(key.Char("X")) |> helper.step(key.Char("X"))

  // The clock runs on: a grid that could be wiped for a fresh clock would be
  // a way of stopping time without pressing p.
  assert again.started_ms == spent.started_ms

  // And so does everything else that was spent getting here.
  assert again.checking
  assert again.mistakes == spent.mistakes
  assert again.mistakes > 0
  assert !game.unaided(again)
}

pub fn starting_again_is_one_undo_away_test() {
  // Asking twice is for meaning it, not for making a slip final.
  let spent = under_way()
  let again = spent |> helper.step(key.Char("X")) |> helper.step(key.Char("X"))

  assert helper.step(again, key.Char("u")).board == spent.board
}

pub fn a_finished_puzzle_is_not_started_again_test() {
  let over = helper.revealed(helper.fixture())
  let asked = helper.step(over, key.Char("X"))

  assert asked.board == over.board
  assert string.contains(asked.message, "new puzzle")
}
