//// Pencil marks: making them, filling them in, and tidying them away.

import gleam/list
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/key

pub fn f_pencils_the_candidates_into_every_bare_cell_test() {
  let filled = helper.step(helper.fixture(), key.Char("f"))
  let peers = board.peers_table()

  use index <- list.each(board.indices())
  case board.value(filled.board, index) {
    // What is pencilled in is exactly what the grid still allows.
    0 -> {
      assert board.sorted_marks(filled.board, index)
        == board.candidates(helper.fixture().board.values, peers, index)
    }
    // And nothing is pencilled into a cell that already has a digit.
    _ -> {
      assert board.sorted_marks(filled.board, index) == []
    }
  }
}

pub fn filling_leaves_the_cells_you_have_marked_alone_test() {
  // A cell marked by hand is where the player has been thinking.
  let thought_about =
    helper.fixture()
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(4))
    |> helper.step(key.Char("m"))
  let cursor = thought_about.cursor

  let filled = helper.step(thought_about, key.Char("f"))

  assert board.sorted_marks(filled.board, cursor) == [4]
  assert string.contains(filled.message, "left as")
}

pub fn filling_twice_over_offers_to_start_the_marks_again_test() {
  let filled = helper.fixture() |> helper.step(key.Char("f"))
  let again = helper.step(filled, key.Char("f"))

  // Nothing bare left, so nothing done — but an offer made.
  assert string.contains(again.message, "already")
  assert string.contains(again.message, "Press f again")
  assert again.board == filled.board
}

/// Marks made by hand are the one thing filling will not touch, so a mark
/// made wrongly needs a way out. This is it, and it takes asking twice.
pub fn asking_a_third_time_marks_every_cell_afresh_test() {
  let peers = board.peers_table()
  let start = helper.fixture()
  let assert Ok(empty) =
    list.find(board.indices(), fn(index) {
      board.value(start.board, index) == 0
    })

  // A cell marked wrongly by hand: one candidate, and the wrong one.
  let wrong = { game.answer(start, empty) % 9 } + 1
  let misled =
    game.Game(..start, cursor: empty)
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(wrong))
    |> helper.step(key.Char("m"))

  let afresh =
    misled
    |> helper.step(key.Char("f"))
    |> helper.step(key.Char("f"))
    |> helper.step(key.Char("f"))

  assert board.sorted_marks(afresh.board, empty)
    == board.candidates(start.board.values, peers, empty)
  assert string.contains(afresh.message, "afresh")

  // Every other empty cell says what it could still take, as before.
  use index <- list.each(board.indices())
  case board.value(afresh.board, index) {
    0 -> {
      assert board.sorted_marks(afresh.board, index)
        == board.candidates(start.board.values, peers, index)
    }
    _ -> Nil
  }
}

pub fn an_offer_to_start_the_marks_again_does_not_keep_test() {
  // Anything done in between makes the next ask a fresh one, so marks are
  // never thrown away by a keystroke the player has forgotten the reason for.
  let held =
    helper.fixture()
    |> helper.step(key.Char("f"))
    |> helper.step(key.Char("f"))
    |> helper.step(key.Right)
    |> helper.step(key.Char("f"))

  assert string.contains(held.message, "Press f again")
}

pub fn filling_is_one_undo_away_test() {
  let filled = helper.step(helper.fixture(), key.Char("f"))
  let undone = helper.step(filled, key.Char("u"))

  assert undone.board == helper.fixture().board
}

pub fn shift_and_a_digit_marks_either_way_round_test() {
  // Writing, and pencilling one in without leaving.
  let marked = helper.step(helper.fixture(), key.Shifted(4))
  assert board.sorted_marks(marked.board, 2) == [4]
  assert board.value(marked.board, 2) == 0
  assert !marked.marking

  // The same key rubs it out again, and does so while marking too.
  assert board.sorted_marks(helper.step(marked, key.Shifted(4)).board, 2) == []
  let while_marking =
    helper.step(helper.step(marked, key.Char("m")), key.Shifted(4))
  assert board.sorted_marks(while_marking.board, 2) == []
  assert while_marking.marking
}

pub fn m_switches_between_writing_and_marking_test() {
  let start = helper.fixture()
  assert !start.marking

  let marking = helper.step(start, key.Char("m"))
  assert marking.marking
  assert !helper.step(marking, key.Char("m")).marking
}

pub fn digits_pencil_marks_in_while_marking_test() {
  let marked =
    helper.fixture()
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(4))
    |> helper.step(key.Digit(1))

  assert board.sorted_marks(marked.board, 2) == [1, 4]
  // The cell is still empty as far as the puzzle is concerned.
  assert board.value(marked.board, 2) == 0
}

pub fn marking_the_same_digit_twice_rubs_it_out_test() {
  let marked =
    helper.fixture()
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(4))
    |> helper.step(key.Digit(4))

  assert board.sorted_marks(marked.board, 2) == []
}

pub fn erase_clears_every_mark_on_the_cell_test() {
  let cleared =
    helper.fixture()
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(4))
    |> helper.step(key.Digit(1))
    |> helper.step(key.Erase)

  assert board.sorted_marks(cleared.board, 2) == []
}

pub fn marking_a_filled_cell_is_refused_test() {
  let played =
    helper.fixture()
    |> helper.step(key.Digit(4))
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(1))

  assert board.sorted_marks(played.board, 2) == []
  assert board.value(played.board, 2) == 4
  assert string.contains(played.message, "already")
}

pub fn marking_a_clue_is_refused_test() {
  let played =
    game.Game(..helper.fixture(), cursor: 0)
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(1))

  assert board.sorted_marks(played.board, 0) == []
  assert string.contains(played.message, "clue")
}

pub fn undo_walks_back_through_marks_test() {
  let marked =
    helper.fixture()
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(4))
    |> helper.step(key.Digit(1))

  let once = helper.step(marked, key.Char("u"))
  assert board.sorted_marks(once.board, 2) == [4]

  let twice = helper.step(once, key.Char("u"))
  assert board.sorted_marks(twice.board, 2) == []
}

pub fn writing_a_digit_during_play_tidies_up_marks_test() {
  // Mark a 4 two cells along the top row, then write a 4 in the first.
  let marked =
    game.Game(..helper.fixture(), cursor: board.at(0, 8))
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(4))
    |> helper.step(key.Char("m"))

  let placed =
    game.Game(..marked, cursor: board.at(0, 2)) |> helper.step(key.Digit(4))

  assert board.sorted_marks(placed.board, board.at(0, 8)) == []
}

pub fn a_wrong_digit_while_checking_leaves_marks_alone_test() {
  // A3 is a 4 in the solution, so a 1 there is wrong and checking says so.
  let played =
    helper.marked_around_a3()
    |> helper.checked
    |> helper.step(key.Digit(1))

  assert board.value(played.board, 2) == 1
  assert game.is_wrong(played, 2)

  // The reasoning that led here survives, on the cell and around it.
  assert board.sorted_marks(played.board, 2) == [4]
  assert board.sorted_marks(played.board, board.at(0, 8)) == [4]
}

pub fn a_right_digit_while_checking_still_tidies_up_test() {
  let played =
    helper.marked_around_a3()
    |> helper.checked
    |> helper.step(key.Digit(4))

  assert board.sorted_marks(played.board, 2) == []
  assert board.sorted_marks(played.board, board.at(0, 8)) == []
}

pub fn a_wrong_digit_tidies_up_as_usual_when_not_checking_test() {
  // With checking off the game is saying nothing about the digit, so marks
  // surviving would be saying it for them.
  let played = helper.marked_around_a3() |> helper.step(key.Digit(1))

  assert !played.checking
  assert board.sorted_marks(played.board, 2) == []
  // A9's 4 is only retracted by a 4; a 1 leaves it be either way.
  assert board.sorted_marks(played.board, board.at(0, 8)) == [4]
}

pub fn correcting_a_wrong_digit_tidies_up_after_it_test() {
  let corrected =
    helper.marked_around_a3()
    |> helper.checked
    |> helper.step(key.Digit(1))
    |> helper.step(key.Digit(4))

  assert !game.is_wrong(corrected, 2)
  assert board.sorted_marks(corrected.board, 2) == []
  assert board.sorted_marks(corrected.board, board.at(0, 8)) == []
}

pub fn writing_a_digit_leaves_every_mark_alone_test() {
  let marked =
    board.from_grid(helper.grid(helper.puzzle_text))
    |> board.toggle_mark(2, 4)
    |> board.toggle_mark(board.at(0, 8), 4)

  let written = board.write(marked, 2, 4)
  assert board.value(written, 2) == 4
  assert board.sorted_marks(written, 2) == [4]
  assert board.sorted_marks(written, board.at(0, 8)) == [4]

  // Givens still refuse to change.
  assert board.value(board.write(marked, 0, 9), 0) == 5
}

pub fn reveals_tidy_up_marks_too_test() {
  let marked =
    helper.fixture()
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(1))
    |> helper.step(key.Digit(4))
    |> helper.step(key.Char("m"))

  assert board.sorted_marks(helper.revealed(marked).board, 2) == []
}
