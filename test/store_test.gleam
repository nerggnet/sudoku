//// Writing a game down, reading it back, and keeping the times.

import gleam/dict
import gleam/list
import gleam/option
import gleam/string
import helper
import sudoku/board
import sudoku/editor
import sudoku/game
import sudoku/generator
import sudoku/key
import sudoku/store
import sudoku/term

pub fn a_game_survives_being_written_out_and_read_back_test() {
  let played =
    helper.fixture()
    |> helper.step(key.Digit(4))
    |> helper.step(key.Char("f"))
    |> helper.checked
    |> helper.step(key.Char("H"))
    |> helper.step(key.Right)

  let assert Ok(again) = store.decode(store.encode(played))

  // The puzzle, and everything done to it since.
  assert again.puzzle.solution == played.puzzle.solution
  assert again.puzzle.origin == played.puzzle.origin
  assert again.board.values == played.board.values
  assert again.board.givens == played.board.givens
  assert again.board.marks == played.board.marks
  assert again.cursor == played.cursor

  // And what the game has cost so far.
  assert again.checking == played.checking
  assert again.mistakes == played.mistakes
  assert again.hints == played.hints

  // The undo history is not kept: nobody walks a day-old puzzle backwards.
  assert again.history == []
}

pub fn the_clock_picks_up_where_it_left_off_test() {
  // A game an hour and a half old, put down and taken up again.
  let long = game.Game(..helper.fixture(), started_ms: term.now_ms() - 90_000)
  let assert Ok(again) = store.decode(store.encode(long))

  assert game.elapsed_ms(again) >= 89_000
  assert game.elapsed_ms(again) <= 91_000
}

pub fn what_a_game_cost_survives_too_test() {
  let assert [a, b, ..] = {
    use index <- list.filter(board.indices())
    board.value(helper.fixture().board, index) == 0
  }

  let costly = helper.checked(helper.fixture()) |> helper.blunder([a, b])
  let assert Ok(again) = store.decode(store.encode(costly))

  assert again.mistakes == 2
  assert again.checking
}

pub fn a_custom_puzzle_is_saved_as_one_test() {
  let assert editor.Ready(puzzle) =
    editor.update(helper.typed(helper.puzzle_text), key.Char("p"))

  let assert Ok(again) = store.decode(store.encode(game.new(puzzle)))
  assert again.puzzle.origin == generator.Handwritten
}

pub fn a_file_that_is_not_a_saved_game_is_refused_test() {
  assert store.decode("") == Error(Nil)
  assert store.decode("hello") == Error(Nil)

  // A file from a version this cannot read.
  let written = store.encode(helper.fixture())
  assert store.decode(string.replace(written, "sudoku 1", "sudoku 2"))
    == Error(Nil)
}

pub fn a_saved_game_that_does_not_hold_together_is_refused_test() {
  let written = store.encode(helper.fixture())

  // An answer that is not an answer.
  assert store.decode(string.replace(written, "answer 534", "answer 634"))
    == Error(Nil)

  // Clues that are not that answer's clues.
  assert store.decode(string.replace(written, "clues 53", "clues 13"))
    == Error(Nil)

  // A board that disagrees with its own clues.
  assert store.decode(string.replace(written, "board 53", "board 13"))
    == Error(Nil)
}

pub fn an_unaided_solve_is_timed_test() {
  let won = helper.solved(helper.fixture())

  assert game.is_finished(won)
  assert game.unaided(won)

  // Nothing on the books yet, so anything is the best there is.
  assert store.judge(won, dict.new()) == game.BestYet

  // And against a standing best, whichever is quicker.
  let quick = game.Game(..won, started_ms: won.started_ms - 60_000)
  assert store.judge(quick, dict.from_list([#(generator.Medium, 30_000)]))
    == game.Behind(30_000)
  assert store.judge(won, dict.from_list([#(generator.Medium, 30_000)]))
    == game.BestYet
}

pub fn a_solve_with_help_is_not_timed_test() {
  // Checking is asked for, and never switched off again, so it is still the
  // record that the game was asked when the puzzle is done.
  let checked = helper.solved(helper.checked(helper.fixture()))
  assert !game.unaided(checked)
  assert store.judge(checked, dict.new()) == game.Aided

  // A hint is help too, however small.
  let hinted =
    helper.solved(helper.step(
      helper.step(helper.aided(helper.fixture()), key.Char("H")),
      key.Char("H"),
    ))
  assert hinted.hints >= 1
  assert store.judge(hinted, dict.new()) == game.Aided
}

pub fn filling_the_candidates_in_is_not_help_test() {
  // It works out nothing the player could not have worked out with a pencil.
  let filled = helper.solved(helper.step(helper.fixture(), key.Char("f")))

  assert game.unaided(filled)
  assert store.judge(filled, dict.new()) == game.BestYet
}

pub fn a_game_not_won_is_not_timed_test() {
  let revealed = helper.step(helper.fixture(), key.Char("R"))
  assert store.judge(revealed, dict.new()) == game.Untimed

  // And a puzzle typed in has no difficulty to file a time under.
  let assert editor.Ready(puzzle) =
    editor.update(helper.typed(helper.puzzle_text), key.Char("p"))
  assert store.judge(helper.solved(game.new(puzzle)), dict.new())
    == game.Untimed
}

pub fn the_finished_panel_says_what_the_books_made_of_it_test() {
  let won = helper.solved(helper.fixture())

  let said = fn(verdict) {
    helper.visible_lines(game.Game(..won, verdict: option.Some(verdict)))
  }

  assert list.any(said(game.BestYet), string.contains(_, "Your best yet"))
  assert list.any(said(game.Behind(125_000)), string.contains(_, "02:05"))
  assert list.any(said(game.Aided), string.contains(_, "Not recorded"))

  // A record the books would not take still says it was one, and then says
  // plainly that it did not land.
  assert list.any(said(game.BestNotKept), string.contains(_, "Your best yet"))
  assert list.any(said(game.BestNotKept), string.contains(
    _,
    "could not be saved",
  ))

  // An untimed game says nothing about records at all.
  assert !list.any(said(game.Untimed), string.contains(_, "recorded"))
  assert !list.any(said(game.Untimed), string.contains(_, "best"))
}

pub fn the_verdict_outlives_a_look_at_the_help_test() {
  // The techniques are worth reading about once the puzzle is done, and the
  // page that explains the last hint is one keystroke away from the panel.
  let judged =
    game.Game(
      ..helper.solved(helper.fixture()),
      verdict: option.Some(game.BestYet),
    )

  let read_about_it =
    judged |> helper.step(key.Char("?")) |> helper.step(key.Char("x"))

  assert read_about_it.verdict == option.Some(game.BestYet)
  assert list.any(helper.visible_lines(read_about_it), string.contains(
    _,
    "Your best yet",
  ))
}

pub fn a_game_is_written_down_again_only_when_it_has_moved_on_test() {
  let start = helper.fixture()
  let written = store.written(start)

  // Nothing has happened since, so the file already says all of this.
  assert !store.moved_on(start, written)
  // Except the first time, when there is no file to say anything.
  assert store.moved_on(start, store.Unwritten)

  // Everything the file holds counts: the board, where the cursor was, the
  // marks, and what the game has been asked for.
  assert store.moved_on(helper.step(start, key.Digit(4)), written)
  assert store.moved_on(helper.step(start, key.Down), written)
  assert store.moved_on(helper.step(start, key.Char("f")), written)
  assert store.moved_on(helper.checked(start), written)

  // What it does not hold does not: a message is said once and gone.
  assert !store.moved_on(game.Game(..start, message: "anything"), written)
}

pub fn the_clock_alone_is_worth_a_write_once_it_runs_away_test() {
  let start = helper.fixture()
  let written = store.written(start)

  // Twenty seconds of staring at a grid is not worth a write of its own.
  let thinking = game.Game(..start, started_ms: start.started_ms - 20_000)
  assert !store.moved_on(thinking, written)

  // Longer than that and it is: a terminal that dies must not be a way of
  // stopping the clock, so what a crash can hand back is held to half a
  // minute whether anything was played in it or not.
  let away = game.Game(..start, started_ms: start.started_ms - 40_000)
  assert store.moved_on(away, written)
}
