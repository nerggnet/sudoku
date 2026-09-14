//// Typing a puzzle in by hand.

import gleam/dict
import gleam/list
import gleam/string
import helper
import sudoku/board
import sudoku/editor
import sudoku/game
import sudoku/generator
import sudoku/key

pub fn an_editor_starts_empty_at_the_first_cell_test() {
  let start = editor.new()

  assert editor.clue_count(start) == 0
  assert start.cursor == 0
  assert board.to_string(start.clues) == string.repeat(".", 81)
}

pub fn typing_a_digit_steps_on_to_the_next_cell_test() {
  let typing =
    editor.new() |> helper.edit(key.Digit(5)) |> helper.edit(key.Digit(3))

  assert editor.value(typing, 0) == 5
  assert editor.value(typing, 1) == 3
  assert typing.cursor == 2
  assert editor.clue_count(typing) == 2
}

pub fn a_gap_key_steps_on_without_writing_test() {
  let typing =
    editor.new() |> helper.edit(key.Erase) |> helper.edit(key.Digit(4))

  assert editor.value(typing, 0) == 0
  assert editor.value(typing, 1) == 4
  assert typing.cursor == 2
}

pub fn typing_over_a_cell_replaces_the_clue_test() {
  let fixed =
    editor.new()
    |> helper.edit(key.Digit(5))
    |> helper.edit(key.Left)
    |> helper.edit(key.Digit(6))

  assert editor.value(fixed, 0) == 6
  assert editor.clue_count(fixed) == 1
}

pub fn typing_a_whole_grid_lands_every_clue_test() {
  let entered = helper.typed(helper.puzzle_text)

  assert board.to_string(entered.clues)
    == board.to_string(helper.grid(helper.puzzle_text))
  assert editor.clue_count(entered) == 30
  // Eighty-one keystrokes bring the cursor back round to where it started.
  assert entered.cursor == 0
}

pub fn the_editor_cursor_wraps_around_the_edges_test() {
  let start = editor.new()

  assert helper.edit(start, key.Left).cursor == board.at(0, 8)
  assert helper.edit(start, key.Up).cursor == board.at(8, 0)
  assert helper.edit(start, key.Down).cursor == board.at(1, 0)
}

pub fn undo_walks_back_through_typing_test() {
  let typing =
    editor.new() |> helper.edit(key.Digit(5)) |> helper.edit(key.Digit(3))

  let once = helper.edit(typing, key.Char("u"))
  assert editor.value(once, 1) == 0
  assert editor.value(once, 0) == 5

  let twice = helper.edit(once, key.Char("u"))
  assert editor.clue_count(twice) == 0
  assert helper.edit(twice, key.Char("u")).message == "Nothing left to undo."
}

pub fn clearing_empties_the_grid_test() {
  let cleared = helper.typed(helper.puzzle_text) |> helper.edit(key.Char("x"))

  assert editor.clue_count(cleared) == 0
  assert cleared.cursor == 0
  // And it is one undo away, so it cannot be pressed by mistake.
  assert editor.clue_count(helper.edit(cleared, key.Char("u"))) == 30
  assert string.contains(
    helper.edit(cleared, key.Char("x")).message,
    "already empty",
  )
}

pub fn typed_clues_become_a_playable_puzzle_test() {
  let assert editor.Ready(puzzle) =
    editor.update(helper.typed(helper.puzzle_text), key.Char("p"))

  assert puzzle.origin == generator.Handwritten
  assert board.to_string(puzzle.solution)
    == board.to_string(helper.grid(helper.solution_text))

  // Every typed digit is a clue, and the rest of the grid is there to play.
  assert board.to_string(puzzle.board.values)
    == board.to_string(helper.grid(helper.puzzle_text))
  assert board.is_given(puzzle.board, 0)
  assert !board.is_given(puzzle.board, 2)
}

pub fn a_typed_puzzle_plays_like_any_other_test() {
  let assert editor.Ready(puzzle) =
    editor.update(helper.typed(helper.puzzle_text), key.Char("p"))
  let started = game.new(puzzle)

  // A3 is a 4 in the answer, so checking and hints know that much.
  assert game.answer(started, 2) == 4

  // Twice over: the cell it starts on may not be one that can be worked out
  // yet, and the first ask is answered by saying so.
  let hinted =
    started |> helper.step(key.Char("H")) |> helper.step(key.Char("H"))
  assert hinted.hints >= 1
  assert helper.nothing_wrong(hinted)
}

pub fn an_empty_grid_cannot_be_played_test() {
  let assert editor.Continue(refused) =
    editor.update(editor.new(), key.Char("p"))

  assert string.contains(refused.message, "Type the clues in first")
}

pub fn clashing_clues_cannot_be_played_test() {
  // A second 5 in the top row, alongside the one already at A1.
  let clashing =
    helper.typed(helper.puzzle_text)
    |> helper.edit(key.Right)
    |> helper.edit(key.Digit(5))

  let assert editor.Continue(refused) = editor.update(clashing, key.Char("p"))
  assert refused.message == editor.refusal(generator.Clashes)
  assert string.contains(refused.message, "clash")
}

pub fn clues_with_no_answer_cannot_be_played_test() {
  // Consistent so far, but A1 is left with no legal digit.
  let dead_end =
    helper.typed(
      ".23 456 789
       1.. ... ...
       4.. ... ...
       7.. ... ...
       2.. ... ...
       5.. ... ...
       8.. ... ...
       3.. ... ...
       6.. ... ...",
    )

  let assert editor.Continue(refused) = editor.update(dead_end, key.Char("p"))
  assert refused.message == editor.refusal(generator.Unsolvable)
  assert string.contains(refused.message, "mistyped")
}

pub fn clues_with_several_answers_cannot_be_played_test() {
  // Leaving out every 1 and 2 leaves a grid that can be finished two ways.
  let loose =
    helper.typed(string.replace(
      string.replace(helper.solution_text, "1", "."),
      "2",
      ".",
    ))

  let assert editor.Continue(refused) = editor.update(loose, key.Char("p"))
  assert refused.message == editor.refusal(generator.Ambiguous)
  assert string.contains(refused.message, "missing")
}

pub fn from_clues_reports_why_it_refused_test() {
  let clashing = dict.insert(helper.grid(helper.puzzle_text), 1, 5)
  assert generator.from_clues(clashing) == Error(generator.Clashes)
  assert generator.from_clues(board.empty_grid()) == Error(generator.Ambiguous)

  let assert Ok(puzzle) = generator.from_clues(helper.grid(helper.puzzle_text))
  assert puzzle.origin == generator.Handwritten
}

pub fn the_editor_help_opens_and_any_key_closes_it_test() {
  let opened = helper.edit(editor.new(), key.Char("?"))
  assert opened.show_help

  assert !helper.edit(opened, key.Char("?")).show_help
  // Dismissing help does not also type a digit in.
  let dismissed = helper.edit(opened, key.Digit(5))
  assert !dismissed.show_help
  assert editor.clue_count(dismissed) == 0
}

pub fn the_editor_can_be_left_test() {
  assert editor.update(editor.new(), key.Char("q")) == editor.Exit
  assert editor.update(editor.new(), key.Quit) == editor.Exit
  assert editor.update(editor.new(), key.Char("n")) == editor.Cancel
}

pub fn the_editor_draws_the_clues_as_they_are_typed_test() {
  let lines = helper.editor_lines(helper.typed(helper.puzzle_text))

  assert list.any(lines, string.contains(_, "S U D O K U    Custom    editing"))
  assert list.contains(
    lines,
    " A \u{2502} 5 3 \u{b7} \u{2502} \u{b7} 7 \u{b7} \u{2502} \u{b7} \u{b7} \u{b7} \u{2502}",
  )
  assert list.any(lines, string.contains(_, "clues 30"))
  assert list.any(lines, string.contains(_, "clashes 0"))
  assert list.any(lines, string.contains(_, "cell A1"))
  assert list.any(lines, string.contains(_, "p play"))
}

pub fn the_editor_shows_one_grid_test() {
  let rows =
    helper.editor_lines(helper.typed(helper.puzzle_text))
    |> list.filter(helper.is_grid_row)

  assert list.length(rows) == 9
  // One grid's worth of columns, and no marks grid beside it.
  use row <- list.each(rows)
  assert string.length(row) == 1 + helper.grid_columns
}

pub fn the_editor_counts_clashing_clues_test() {
  let clashing =
    helper.typed(helper.puzzle_text)
    |> helper.edit(key.Right)
    |> helper.edit(key.Digit(5))
  assert list.any(helper.editor_lines(clashing), string.contains(_, "clashes 2"))
}

pub fn the_editor_help_lists_its_own_keys_test() {
  let lines = helper.editor_lines(helper.edit(editor.new(), key.Char("?")))

  assert list.any(lines, string.contains(_, "type a clue in and step on"))
  assert list.any(lines, string.contains(_, "play the puzzle"))
  assert !list.any(lines, helper.is_grid_row)
}

pub fn every_editor_frame_fits_a_short_terminal_test() {
  let frames = [
    editor.new(),
    helper.typed(helper.puzzle_text),
    helper.edit(editor.new(), key.Char("?")),
  ]

  use current <- list.each(frames)
  assert list.length(helper.editor_lines(current)) <= 24
}

pub fn the_editor_help_survives_a_newline_test() {
  let reading = helper.edit(editor.new(), key.Char("?"))
  assert helper.edit(reading, key.Unknown).show_help
}

pub fn shift_and_a_digit_types_a_clue_in_test() {
  // In the editor there is nothing to distinguish them, so the shifted row
  // types digits like the unshifted one.
  let typed =
    editor.new() |> helper.edit(key.Shifted(5)) |> helper.edit(key.Digit(3))

  assert editor.value(typed, 0) == 5
  assert editor.value(typed, 1) == 3
}
