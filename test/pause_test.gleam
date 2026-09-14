//// Putting the game down for a minute.

import gleam/list
import gleam/option
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/key
import sudoku/rules
import sudoku/term

pub fn pausing_puts_the_board_away_test() {
  let paused = helper.step(helper.fixture(), key.Char("p"))
  let lines = helper.visible_lines(paused)

  assert paused.paused
  assert paused.resting_since != option.None
  assert list.any(lines, string.contains(_, "Paused"))
  assert list.any(lines, string.contains(_, "clock has stopped"))

  // Not a single row of it: a pause that left the grid up would be a way of
  // thinking about it for nothing.
  assert !list.any(lines, helper.is_grid_row)
}

pub fn the_clock_waits_while_it_is_paused_test() {
  // Ten minutes into a game, paused five minutes ago.
  let playing =
    game.Game(..helper.fixture(), started_ms: term.now_ms() - 600_000)
  assert game.elapsed_ms(playing) >= 600_000

  let paused =
    game.Game(
      ..helper.step(playing, key.Char("p")),
      resting_since: option.Some(term.now_ms() - 300_000),
    )

  let carried_on = helper.step(paused, key.Down)
  let elapsed = game.elapsed_ms(carried_on)

  assert !carried_on.paused
  assert carried_on.resting_since == option.None
  assert elapsed >= 299_000 && elapsed <= 301_000
}

pub fn any_key_carries_on_test() {
  let paused = helper.step(helper.fixture(), key.Char("p"))
  let back = helper.step(paused, key.Char("z"))

  assert !back.paused
  assert list.any(helper.visible_lines(back), helper.is_grid_row)
}

pub fn nothing_reaches_the_board_while_it_is_paused_test() {
  // The key that carries on is spent doing only that, so coming back to the
  // board cannot write on it by accident.
  let paused = helper.step(helper.fixture(), key.Char("p"))
  let back = helper.step(paused, key.Digit(4))

  assert back.board == helper.fixture().board
  assert !back.paused
}

pub fn quitting_still_works_while_paused_test() {
  let paused = helper.step(helper.fixture(), key.Char("p"))

  assert rules.update(paused, key.Char("q")) == game.Exit
  assert rules.update(paused, key.Quit) == game.Exit
}

pub fn a_game_that_is_over_cannot_be_paused_test() {
  // There is no clock left to stop: the time is a result by then.
  let done = helper.revealed(helper.step(helper.fixture(), key.Digit(4)))
  let poked = helper.step(done, key.Char("p"))

  assert !poked.paused
  assert string.contains(poked.message, "new puzzle")
}

pub fn a_paused_game_keeps_what_was_on_the_board_test() {
  let played =
    helper.fixture()
    |> helper.step(key.Digit(4))
    |> helper.step(key.Down)
    |> helper.with_marks([1, 2, 3])

  let back = helper.step(helper.step(played, key.Char("p")), key.Up)

  assert back.board == played.board
  assert board.sorted_marks(back.board, played.cursor) == [1, 2, 3]
}
