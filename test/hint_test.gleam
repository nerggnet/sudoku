//// What a hint offers, and what it refuses to.

import gleam/list
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/key
import sudoku/logic

pub fn the_first_hint_says_what_it_will_cost_test() {
  let asked = helper.step(helper.fixture(), key.Char("H"))

  // Nothing given away yet: a warning, and the game still the player's own.
  assert string.contains(asked.message, "aided")
  assert string.contains(asked.message, "Press H again")
  assert asked.hints == 0
  assert game.unaided(asked)
  assert asked.board == helper.fixture().board
}

pub fn asking_again_takes_the_hint_and_the_game_with_it_test() {
  let taken =
    helper.fixture() |> helper.step(key.Char("H")) |> helper.step(key.Char("H"))

  assert !game.unaided(taken)

  // And it says so beside the difficulty, since that is what the difficulty
  // no longer quite means.
  assert list.any(helper.visible_lines(taken), string.contains(_, "(aided)"))
  assert !list.any(helper.visible_lines(helper.fixture()), string.contains(
    _,
    "(aided)",
  ))
}

pub fn the_warning_comes_once_and_then_not_again_test() {
  let taken =
    helper.fixture() |> helper.step(key.Char("H")) |> helper.step(key.Char("H"))

  // The game is already aided, so the next hint is given straight away.
  let again = helper.step(taken, key.Char("H"))
  assert !string.contains(again.message, "not timed")
}

pub fn a_warning_not_taken_up_does_not_keep_test() {
  let asked =
    helper.fixture() |> helper.step(key.Char("H")) |> helper.step(key.Right)

  assert game.unaided(helper.step(asked, key.Char("H")))
  assert string.contains(helper.step(asked, key.Char("H")).message, "not timed")
}

pub fn checking_makes_a_game_aided_too_test() {
  // Checking works from the answer just as a hint does, so it costs the same
  // thing, and says so in the same place.
  let checked = helper.checked(helper.fixture())

  assert !game.unaided(checked)
  assert list.any(helper.visible_lines(checked), string.contains(_, "(aided)"))

  // With nothing left to lose, a hint is given without asking twice.
  assert !string.contains(
    helper.step(checked, key.Char("H")).message,
    "not timed",
  )
}

pub fn a_puzzle_typed_in_is_not_warned_about_test() {
  // It was never going to be timed, so a hint costs it nothing.
  let hinted = helper.step(helper.handwritten(), key.Char("H"))

  assert !string.contains(hinted.message, "not timed")
}

pub fn a_hint_takes_the_next_step_and_says_why_test() {
  let hinted =
    helper.aided(helper.fixture())
    |> helper.step(key.Char("H"))
    |> helper.step(key.Char("H"))

  assert hinted.hints >= 1
  assert helper.nothing_wrong(hinted)

  // It moved to what it is about and named it in words, rather than leaving
  // the player to work out which cell it meant.
  assert string.contains(hinted.message, board.name(hinted.cursor))
  assert string.ends_with(hinted.message, ".")
}

pub fn a_hint_answers_the_cell_you_are_on_test() {
  let start = helper.aided(helper.fixture())

  // A cell that can be worked out, but not the one the reasoning would have
  // picked of its own accord.
  let assert Ok(elsewhere) = {
    use index <- list.find(board.indices())
    index != helper.step(start, key.Char("H")).cursor
    && board.value(start.board, index) == 0
    && logic.settles(start.board.values, index) != Error(Nil)
  }

  let hinted = helper.step(game.Game(..start, cursor: elsewhere), key.Char("H"))

  assert hinted.cursor == elsewhere
  assert board.value(hinted.board, elsewhere) == game.answer(start, elsewhere)
  assert string.contains(hinted.message, board.name(elsewhere))
}

pub fn a_hint_says_so_rather_than_wandering_off_test() {
  let stuck = helper.stuck_cell()
  let waiting =
    helper.step(
      game.Game(..helper.aided(helper.fixture()), cursor: stuck),
      key.Char("H"),
    )

  // It stays where the player is looking and says why it has nothing.
  assert waiting.cursor == stuck
  assert waiting.board == helper.aided(helper.fixture()).board
  assert string.contains(waiting.message, board.name(stuck))
  assert string.contains(waiting.message, "Press H again")

  // Saying so is not a hint, and is not counted as one.
  assert waiting.hints == 0
}

pub fn asking_twice_at_a_stuck_cell_looks_elsewhere_test() {
  let stuck = helper.stuck_cell()
  let moved_on =
    game.Game(..helper.aided(helper.fixture()), cursor: stuck)
    |> helper.step(key.Char("H"))
    |> helper.step(key.Char("H"))

  assert moved_on.cursor != stuck
  assert moved_on.hints == 1
  assert helper.nothing_wrong(moved_on)
  assert string.contains(moved_on.message, board.name(moved_on.cursor))
}

pub fn anything_in_between_starts_the_asking_over_test() {
  let stuck = helper.stuck_cell()

  // Moving away and back is a fresh question, not a second asking of the old
  // one, so it is answered the same way as the first.
  let again =
    game.Game(..helper.aided(helper.fixture()), cursor: stuck)
    |> helper.step(key.Char("H"))
    |> helper.step(key.Right)
    |> helper.step(key.Left)
    |> helper.step(key.Char("H"))

  assert again.cursor == stuck
  assert again.hints == 0
  assert string.contains(again.message, "Press H again")
}

pub fn a_hint_goes_where_the_reasoning_is_test() {
  // Not where the cursor happens to be: the cell under it may not be the one
  // that can be worked out next, and a hint that cannot explain itself is
  // just the answer again.
  let on_a_clue = game.Game(..helper.aided(helper.fixture()), cursor: 0)
  let hinted = helper.step(on_a_clue, key.Char("H"))

  assert hinted.cursor != 0
  assert helper.nothing_wrong(hinted)
  assert string.contains(hinted.message, board.name(hinted.cursor))
}

pub fn a_hint_rubs_out_the_marks_it_rules_out_test() {
  // Somewhere in this one the reasoning has to rule something out before it
  // can settle anything, and a player with marks has somewhere for that to
  // land. Take hints until it comes round.
  let start = helper.fully_marked(helper.playing(helper.needs_naked_pair))

  let #(last, ruled_something_out) = {
    use #(current, seen), _ <- list.fold(board.span(1, 25), #(start, False))
    let hinted = helper.step(current, key.Char("H"))
    let #(written, marked) = helper.written_and_marked(current)
    let #(written_after, marked_after) = helper.written_and_marked(hinted)

    // A hint that wrote nothing and rubbed marks out handed over an
    // elimination rather than an answer.
    #(hinted, seen || { written == written_after && marked_after < marked })
  }

  assert ruled_something_out

  // And nothing was ever rubbed out that belonged there.
  use index <- list.each(board.indices())
  case board.sorted_marks(last.board, index) {
    [] -> Nil
    marks -> {
      assert list.contains(marks, game.answer(last, index))
    }
  }
}

pub fn asking_over_and_over_keeps_moving_test() {
  // Without marks an elimination has nowhere to land and nothing to show, so
  // the hints fall back to naming digits rather than offering the same advice
  // for ever. Some asks only say a cell will not go yet; the rest must move.
  let start = helper.playing(helper.needs_naked_pair)

  let #(last, moves) = {
    use #(current, moves), _ <- list.fold(board.span(1, 8), #(start, 0))
    let hinted = helper.step(current, key.Char("H"))
    let moved =
      board.empty_count(hinted.board) < board.empty_count(current.board)

    #(
      hinted,
      moves
        + case moved {
        True -> 1
        False -> 0
      },
    )
  }

  assert moves >= 4
  assert helper.nothing_wrong(last)
}

pub fn a_hint_checks_itself_against_the_answer_test() {
  // A wrong digit can lead the reasoning somewhere the answer does not go,
  // so a hint never writes a digit without checking it first.
  let astray = helper.step(helper.aided(helper.fixture()), key.Digit(1))
  let hinted = helper.step(astray, key.Char("H"))

  assert hinted.hints == 1
  use index <- list.each(board.indices())
  case index == 2 || board.value(hinted.board, index) == 0 {
    True -> Nil
    False -> {
      assert board.value(hinted.board, index) == game.answer(hinted, index)
    }
  }
}

/// Marks that are pencilled in are what the reasoning then works from, which
/// is what lets a step that only rules candidates out lead to the next one.
pub fn the_hints_reason_from_the_marks_you_have_test() {
  // A grid whose reasoning needs an elimination somewhere along the way.
  let filled =
    helper.step(helper.playing(helper.needs_naked_pair), key.Char("f"))

  // Take hints until one of them rules candidates out rather than settling a
  // digit: without marks to rub out, no such hint is ever offered.
  let #(_, ruled_out) = {
    use #(current, seen), _ <- list.fold(board.span(1, 30), #(filled, False))
    let hinted = helper.step(current, key.Char("H"))
    #(
      hinted,
      seen
        || board.empty_count(hinted.board) == board.empty_count(current.board),
    )
  }

  assert ruled_out
}

pub fn a_hint_tidies_up_the_marks_where_it_settles_test() {
  // A cell the reasoning can settle, marked up before the hint settles it.
  let assert Ok(settles) = {
    use index <- list.find(board.indices())
    board.value(helper.aided(helper.fixture()).board, index) == 0
    && logic.settles(helper.aided(helper.fixture()).board.values, index)
    != Error(Nil)
  }
  // Pencilled with the digit that belongs there. A mark of the wrong digit
  // would make the cell look like a naked single for a digit that is not the
  // answer, and a hint checks before it writes.
  let digit = game.answer(helper.aided(helper.fixture()), settles)
  let marked =
    game.Game(..helper.aided(helper.fixture()), cursor: settles)
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(digit))
    |> helper.step(key.Char("m"))

  assert board.sorted_marks(marked.board, settles) == [digit]
  assert board.sorted_marks(helper.step(marked, key.Char("H")).board, settles)
    == []
}

pub fn a_hint_will_not_write_what_your_marks_say_wrongly_test() {
  // One wrong candidate pencilled in makes the cell look settled, and settled
  // wrongly. The hint declines rather than writing it.
  let assert Ok(settles) = {
    use index <- list.find(board.indices())
    board.value(helper.aided(helper.fixture()).board, index) == 0
    && logic.settles(helper.aided(helper.fixture()).board.values, index)
    != Error(Nil)
  }

  let wrong = { game.answer(helper.aided(helper.fixture()), settles) % 9 } + 1
  let misled =
    game.Game(..helper.aided(helper.fixture()), cursor: settles)
    |> helper.step(key.Char("m"))
    |> helper.step(key.Digit(wrong))
    |> helper.step(key.Char("m"))
    |> helper.step(key.Char("H"))

  assert board.value(misled.board, settles) == 0
  assert string.contains(misled.message, "Press H again")
}
