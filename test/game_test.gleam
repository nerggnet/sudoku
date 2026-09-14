//// The rules: moving, writing, undoing, and how a game ends.

import gleam/list
import gleam/option
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/key
import sudoku/logic
import sudoku/render

pub fn a_new_game_starts_on_the_first_empty_cell_test() {
  let started = helper.fixture()
  assert started.cursor == 2
  assert !game.is_finished(started)
}

pub fn the_cursor_wraps_around_the_edges_test() {
  let at_start = game.Game(..helper.fixture(), cursor: board.at(0, 0))

  assert helper.step(at_start, key.Left).cursor == board.at(0, 8)
  assert helper.step(at_start, key.Up).cursor == board.at(8, 0)
  assert helper.step(at_start, key.Right).cursor == board.at(0, 1)
  assert helper.step(at_start, key.Down).cursor == board.at(1, 0)
}

pub fn vim_and_wasd_keys_move_too_test() {
  let middle = game.Game(..helper.fixture(), cursor: board.at(4, 4))

  assert helper.step(middle, key.Char("k")).cursor == board.at(3, 4)
  assert helper.step(middle, key.Char("j")).cursor == board.at(5, 4)
  assert helper.step(middle, key.Char("a")).cursor == board.at(4, 3)
  assert helper.step(middle, key.Char("d")).cursor == board.at(4, 5)
}

pub fn digits_land_in_the_cell_under_the_cursor_test() {
  let played = helper.step(helper.fixture(), key.Digit(4))
  assert board.value(played.board, 2) == 4
}

pub fn clues_refuse_to_change_test() {
  let on_a_clue = game.Game(..helper.fixture(), cursor: 0)
  let played = helper.step(on_a_clue, key.Digit(9))

  assert board.value(played.board, 0) == 5
  assert played.message != ""
  // A refused move is not worth undoing.
  assert played.history == []
}

pub fn undo_walks_back_through_edits_test() {
  let played =
    helper.fixture()
    |> helper.step(key.Digit(4))
    |> helper.step(key.Right)
    |> helper.step(key.Digit(7))

  let once = helper.step(played, key.Char("u"))
  assert board.value(once.board, 3) == 0
  assert board.value(once.board, 2) == 4

  let twice = helper.step(once, key.Char("u"))
  assert board.value(twice.board, 2) == 0
  assert twice.history == []

  // Undoing past the beginning is harmless.
  assert helper.step(twice, key.Char("u")).history == []
}

pub fn redo_walks_forward_again_test() {
  let played =
    helper.fixture()
    |> helper.step(key.Digit(4))
    |> helper.step(key.Right)
    |> helper.step(key.Digit(7))
  let back = played |> helper.step(key.Char("u")) |> helper.step(key.Char("u"))

  assert board.value(back.board, 2) == 0
  assert board.value(back.board, 3) == 0

  let forward = back |> helper.step(key.Char("r")) |> helper.step(key.Char("r"))
  assert board.value(forward.board, 2) == 4
  assert board.value(forward.board, 3) == 7
  assert forward.board == played.board

  // And there is nothing beyond where it started.
  assert string.contains(helper.step(forward, key.Char("r")).message, "Nothing")
}

pub fn there_is_nothing_to_redo_until_something_is_undone_test() {
  assert string.contains(
    helper.step(helper.fixture(), key.Char("r")).message,
    "Nothing",
  )
}

pub fn writing_something_else_throws_the_way_forward_away_test() {
  // The board is somewhere else now, and what was undone was the way forward
  // from where it used to be.
  let elsewhere =
    helper.fixture()
    |> helper.step(key.Digit(4))
    |> helper.step(key.Char("u"))
    |> helper.step(key.Digit(1))

  assert string.contains(
    helper.step(elsewhere, key.Char("r")).message,
    "Nothing",
  )
  assert board.value(elsewhere.board, 2) == 1
}

pub fn undo_says_how_to_take_it_back_test() {
  let undone =
    helper.fixture() |> helper.step(key.Digit(4)) |> helper.step(key.Char("u"))
  assert string.contains(undone.message, "press r")
    || string.contains(undone.message, "Press r")
}

pub fn erasing_clears_a_filled_cell_test() {
  let played =
    helper.fixture() |> helper.step(key.Digit(4)) |> helper.step(key.Erase)
  assert board.value(played.board, 2) == 0
}

pub fn revealing_finishes_the_puzzle_test() {
  let revealed = helper.step(helper.fixture(), key.Char("R"))

  assert revealed.ending == option.Some(game.Revealed)
  assert game.is_finished(revealed)
  assert board.is_solved(revealed.board)
  assert board.to_string(revealed.board.values)
    == board.to_string(helper.grid(helper.solution_text))
}

pub fn filling_the_last_cell_wins_test() {
  let start = helper.fixture()
  let blanks =
    list.filter(board.indices(), fn(index) {
      board.value(start.board, index) == 0
    })
  let assert Ok(last) = list.last(blanks)

  let almost = {
    use current, index <- list.fold(blanks, start)
    case index == last {
      True -> current
      False ->
        game.Game(..current, cursor: index)
        |> helper.step(key.Digit(game.answer(current, index)))
    }
  }

  assert !game.is_finished(almost)
  assert board.empty_count(almost.board) == 1

  let won =
    game.Game(..almost, cursor: last)
    |> helper.step(key.Digit(game.answer(almost, last)))

  assert game.is_finished(won)
  assert won.ending == option.Some(game.Solved)
  assert board.is_solved(won.board)
}

pub fn a_finished_puzzle_ignores_further_edits_test() {
  let revealed = helper.step(helper.fixture(), key.Char("R"))
  let poked = helper.step(game.Game(..revealed, cursor: 2), key.Erase)
  assert board.value(poked.board, 2) == 4
}

pub fn help_opens_and_any_key_closes_it_test() {
  let opened = helper.step(helper.fixture(), key.Char("?"))
  assert opened.help == option.Some(game.Keys)

  assert helper.step(opened, key.Char("?")).help == option.None
  assert helper.step(opened, key.Down).help == option.None
  // Dismissing help does not also move the cursor.
  assert helper.step(opened, key.Down).cursor == opened.cursor
}

pub fn the_help_pages_through_the_techniques_test() {
  let opened = helper.step(helper.fixture(), key.Char("?"))

  // Right off the keys is the first technique, and left off it is the last.
  let assert [_keys, first, ..] = game.pages()
  let assert Ok(last) = list.last(game.pages())

  assert helper.step(opened, key.Right).help == option.Some(first)
  assert helper.step(opened, key.Left).help == option.Some(last)

  // Paging through every page comes back round to where it started.
  let round = {
    use current, _ <- list.fold(game.pages(), opened)
    helper.step(current, key.Right)
  }
  assert round.help == opened.help

  // A page for every technique, two of keys, and one on starting up.
  assert list.length(game.pages()) == list.length(logic.techniques) + 3
}

pub fn paging_the_help_does_not_reach_the_board_test() {
  // The arrows turn pages while the help is up, so there is no reading about
  // a technique and moving the cursor by accident.
  let opened = helper.step(helper.fixture(), key.Char("?"))
  let paged = helper.step(helper.step(opened, key.Right), key.Left)

  assert paged.cursor == opened.cursor
  assert paged.board == opened.board

  // Quitting still works from the help, though.
  assert game.update(opened, key.Char("q")) == game.Exit
}

pub fn giving_up_a_puzzle_under_way_is_asked_for_twice_test() {
  // n is next to m on the keyboard, and giving up throws away the saved game
  // as well as the one on screen.
  let played = helper.step(helper.fixture(), key.Digit(4))
  let asked = helper.step(played, key.Char("n"))

  assert string.contains(asked.message, "Press n again")
  assert asked.board == played.board

  assert game.update(asked, key.Char("n")) == game.Restart
  assert game.update(asked, key.Char("N")) == game.Restart
}

pub fn a_newline_is_not_a_keystroke_test() {
  // A terminal in line mode sends one after every key, and the player did
  // not press it. Counting it would cancel an offer before it could be taken
  // up, and close the help the moment it opened.
  let asked =
    helper.fixture()
    |> helper.step(key.Digit(4))
    |> helper.step(key.Char("n"))
    |> helper.step(key.Unknown)

  assert game.update(asked, key.Char("n")) == game.Restart

  let reading = helper.step(helper.fixture(), key.Char("?"))
  assert helper.step(reading, key.Unknown).help == reading.help

  // And it leaves what a hint is pointing at where it was.
  let hinted =
    helper.aided(helper.fixture())
    |> helper.step(key.Char("H"))
    |> helper.step(key.Char("H"))
  assert helper.step(hinted, key.Unknown).showing == hinted.showing
}

pub fn an_offer_to_give_up_does_not_keep_test() {
  let asked =
    helper.fixture()
    |> helper.step(key.Digit(4))
    |> helper.step(key.Char("n"))
    |> helper.step(key.Right)

  // A fresh question, answered the same way as the first.
  assert string.contains(
    helper.step(asked, key.Char("n")).message,
    "Press n again",
  )
}

pub fn a_puzzle_with_nothing_in_it_is_given_up_at_once_test() {
  // Nothing has been done to it, so there is nothing to lose by asking.
  assert game.update(helper.fixture(), key.Char("n")) == game.Restart

  // And a puzzle already over is over.
  let done = helper.step(helper.fixture(), key.Char("R"))
  assert game.update(done, key.Char("n")) == game.Restart
}

pub fn quit_and_restart_leave_the_loop_test() {
  assert game.update(helper.fixture(), key.Char("q")) == game.Exit
  assert game.update(helper.fixture(), key.Quit) == game.Exit
  assert game.update(helper.fixture(), key.Char("n")) == game.Restart
}

pub fn the_clock_grows_an_hour_hand_test() {
  assert render.clock(0) == "00:00"
  assert render.clock(59_000) == "00:59"
  assert render.clock(3_599_000) == "59:59"

  // Rather than counting minutes past sixty and reading 104:23.
  assert render.clock(3_600_000) == "1:00:00"
  assert render.clock(6_263_000) == "1:44:23"
}

pub fn the_clock_runs_from_the_start_test() {
  assert game.elapsed_ms(helper.fixture()) >= 0
}

pub fn the_clock_waits_while_the_help_is_up_test() {
  let start = helper.fixture()
  let reading = helper.step(start, key.Char("?"))
  assert reading.resting_since != option.None

  // Closing the help gives back the time spent reading it, by moving the
  // start of the game along.
  let back = helper.step(reading, key.Down)
  assert back.resting_since == option.None
  assert back.started_ms >= start.started_ms
  assert game.elapsed_ms(back) <= game.elapsed_ms(start)
}

pub fn a_finished_time_does_not_move_test() {
  // The clock has stopped, so reading the help afterwards cannot change what
  // it says.
  let done = helper.step(helper.fixture(), key.Char("R"))
  let after = done |> helper.step(key.Char("?")) |> helper.step(key.Down)

  assert after.started_ms == done.started_ms
  assert game.elapsed_ms(after) == game.elapsed_ms(done)
}
