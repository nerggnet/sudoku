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
import sudoku/rules

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
  // The keys three times over, starting up twice over, and then a page on
  // each technique.
  assert list.length(game.pages()) == list.length(logic.techniques) + 5
}

pub fn paging_the_help_does_not_reach_the_board_test() {
  // The arrows turn pages while the help is up, so there is no reading about
  // a technique and moving the cursor by accident.
  let opened = helper.step(helper.fixture(), key.Char("?"))
  let paged = helper.step(helper.step(opened, key.Right), key.Left)

  assert paged.cursor == opened.cursor
  assert paged.board == opened.board

  // Quitting still works from the help, though.
  assert rules.update(opened, key.Char("q")) == game.Exit
}

pub fn giving_up_a_puzzle_under_way_is_asked_for_twice_test() {
  // n is next to m on the keyboard, and giving up throws away the saved game
  // as well as the one on screen.
  let played = helper.step(helper.fixture(), key.Digit(4))
  let asked = helper.step(played, key.Char("n"))

  assert string.contains(asked.message, "Press n again")
  assert asked.board == played.board

  assert rules.update(asked, key.Char("n")) == game.Restart
  assert rules.update(asked, key.Char("N")) == game.Restart
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

  assert rules.update(asked, key.Char("n")) == game.Restart

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
  assert rules.update(helper.fixture(), key.Char("n")) == game.Restart

  // And a puzzle already over is over.
  let done = helper.step(helper.fixture(), key.Char("R"))
  assert rules.update(done, key.Char("n")) == game.Restart
}

pub fn quit_and_restart_leave_the_loop_test() {
  assert rules.update(helper.fixture(), key.Char("q")) == game.Exit
  assert rules.update(helper.fixture(), key.Quit) == game.Exit
  assert rules.update(helper.fixture(), key.Char("n")) == game.Restart
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

pub fn revealing_a_puzzle_under_way_is_asked_for_twice_test() {
  // R is r with a thumb on shift, and r is pressed over and over walking
  // forward through undone moves. The slip ends the puzzle, and a game that
  // is over cannot be walked back out of.
  let played = helper.step(helper.fixture(), key.Digit(4))
  let asked = helper.step(played, key.Char("R"))

  assert !game.is_finished(asked)
  assert asked.board == played.board
  assert string.contains(asked.message, "Press R again")

  let shown = helper.step(asked, key.Char("R"))
  assert game.is_finished(shown)
  assert shown.ending == option.Some(game.Revealed)
}

pub fn a_puzzle_nothing_has_been_done_to_is_revealed_at_once_test() {
  // Nothing to lose by asking, the same as giving one up.
  let shown = helper.step(helper.fixture(), key.Char("R"))

  assert game.is_finished(shown)
  assert shown.ending == option.Some(game.Revealed)
}

pub fn an_offer_to_reveal_lapses_on_the_next_keystroke_test() {
  let asked =
    helper.fixture()
    |> helper.step(key.Digit(4))
    |> helper.step(key.Char("R"))
    |> helper.step(key.Down)

  assert !game.is_finished(helper.step(asked, key.Char("R")))
}

pub fn undo_goes_back_to_where_the_change_was_test() {
  let start = helper.fixture()
  let written = helper.step(start, key.Digit(4))

  // Wander off, so that undoing would otherwise happen out of sight.
  let away = written |> helper.step(key.Down) |> helper.step(key.Down)
  assert away.cursor != start.cursor

  let undone = helper.step(away, key.Char("u"))
  assert undone.cursor == start.cursor
  assert board.value(undone.board, start.cursor) == 0

  // And doing it again puts it back under the same cell, wherever the player
  // had got to in between.
  let wandered = helper.step(undone, key.Right)
  let again = helper.step(wandered, key.Char("r"))
  assert again.cursor == start.cursor
  assert board.value(again.board, start.cursor) == 4
}

pub fn what_the_undo_pile_holds_is_the_cell_it_is_about_test() {
  // A hint settles a cell of its own choosing, and the pile remembers where
  // the player was rather than where the hint went.
  let asked = helper.aided(helper.fixture())
  let hinted = asked |> helper.step(key.Char("H")) |> helper.step(key.Char("H"))

  let undone = helper.step(hinted, key.Char("u"))
  assert undone.cursor == asked.cursor
  assert undone.board == asked.board
}

/// Tab to the next cell with nothing in it, which is the one move the
/// arrows are bad at: a hard grid has its blanks in ones and twos with
/// clues between them, and walking to the next of them a cell at a time is
/// the part of a puzzle that is not thinking.
pub fn tab_goes_to_the_next_empty_cell_test() {
  let start = helper.fixture()
  let blanks = helper.blanks()

  let assert Ok(first) = list.first(blanks)
  let at_first = game.Game(..start, cursor: first)
  let next = helper.step(at_first, key.Tab).cursor

  // The next blank in reading order, with every clue between passed over.
  assert list.contains(blanks, next)
  assert next > first
  assert list.all(board.span(first + 1, next - 1), fn(index) {
    !list.contains(blanks, index)
  })
}

pub fn shift_tab_goes_back_the_same_way_test() {
  let start = helper.fixture()
  let assert Ok(first) = list.first(helper.blanks())
  let at_first = game.Game(..start, cursor: first)

  let there = helper.step(at_first, key.Tab)
  assert helper.step(there, key.BackTab).cursor == first
}

/// The last blank leads round to the first, which is the wrap the arrows
/// have at the edges.
pub fn tab_wraps_round_the_board_test() {
  let start = helper.fixture()
  let blanks = helper.blanks()
  let assert Ok(first) = list.first(blanks)
  let assert Ok(last) = list.last(blanks)

  assert helper.step(game.Game(..start, cursor: last), key.Tab).cursor == first
  assert helper.step(game.Game(..start, cursor: first), key.BackTab).cursor
    == last
}

/// Empty means empty. A cell with a wrong digit in it is somewhere to go
/// back to rather than somewhere left to work, and undo is the way back.
pub fn tab_passes_over_a_cell_that_is_filled_in_test() {
  let start = helper.fixture()
  let assert Ok(first) = list.first(helper.blanks())

  let filled = helper.step(game.Game(..start, cursor: first), key.Digit(1))
  assert board.value(filled.board, first) == 1

  // Standing on it and tabbing leaves it, and coming back round skips it.
  let onwards = helper.step(filled, key.Tab)
  assert onwards.cursor != first
  assert helper.step(onwards, key.BackTab).cursor != first
}

/// A board with nothing left empty has nowhere to send it, and says so: a
/// key that does nothing twice reads as a key that is broken.
pub fn tab_says_so_when_nothing_is_left_test() {
  let full = helper.solved(helper.fixture())
  let stuck = game.Game(..full, finished_ms: option.None, ending: option.None)
  let pressed = helper.step(stuck, key.Tab)

  assert pressed.cursor == stuck.cursor
  assert pressed.message != ""
}

pub fn home_and_end_go_to_the_ends_of_the_row_test() {
  let middle = game.Game(..helper.fixture(), cursor: board.at(4, 4))

  assert helper.step(middle, key.Home).cursor == board.at(4, 0)
  assert helper.step(middle, key.End).cursor == board.at(4, 8)

  // The row is the one the cursor is on, whichever that is.
  let elsewhere = game.Game(..helper.fixture(), cursor: board.at(7, 2))
  assert helper.step(elsewhere, key.Home).cursor == board.at(7, 0)
  assert helper.step(elsewhere, key.End).cursor == board.at(7, 8)
}
