import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import gleeunit
import sudoku/board
import sudoku/editor
import sudoku/game
import sudoku/generator
import sudoku/key
import sudoku/render
import sudoku/solver

pub fn main() -> Nil {
  gleeunit.main()
}

// A puzzle with a single solution, and that solution.
const puzzle_text = "
  53. .7. ...
  6.. 195 ...
  .98 ... .6.
  8.. .6. ..3
  4.. 8.3 ..1
  7.. .2. ..6
  .6. ... 28.
  ... 419 ..5
  ... .8. .79
"

const solution_text = "
  534 678 912
  672 195 348
  198 342 567
  859 761 423
  426 853 791
  713 924 856
  961 537 284
  287 419 635
  345 286 179
"

fn grid(text: String) -> board.Grid {
  let assert Ok(parsed) = board.parse(text) as "test fixture should parse"
  parsed
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

pub fn span_is_inclusive_test() {
  assert board.span(0, 3) == [0, 1, 2, 3]
  assert board.span(4, 4) == [4]
}

pub fn indices_cover_the_grid_test() {
  assert list.length(board.indices()) == 81
  assert list.first(board.indices()) == Ok(0)
  assert list.last(board.indices()) == Ok(80)
}

pub fn cell_coordinates_round_trip_test() {
  use index <- list.each(board.indices())
  assert board.at(board.row_of(index), board.col_of(index)) == index
}

pub fn boxes_are_three_by_three_test() {
  assert board.box_of(board.at(0, 0)) == 0
  assert board.box_of(board.at(2, 2)) == 0
  assert board.box_of(board.at(0, 3)) == 1
  assert board.box_of(board.at(4, 4)) == 4
  assert board.box_of(board.at(8, 8)) == 8
}

pub fn there_are_twenty_seven_units_of_nine_test() {
  let units = board.units()
  assert list.length(units) == 27

  use unit <- list.each(units)
  assert list.length(unit) == 9
  // No cell appears twice within a unit.
  assert set.size(set.from_list(unit)) == 9
}

pub fn every_cell_has_twenty_peers_test() {
  let peers = board.peers_table()

  use index <- list.each(board.indices())
  let assert Ok(cells) = dict.get(peers, index)
  assert set.size(cells) == 20
  assert !set.contains(cells, index)
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

pub fn parse_ignores_layout_test() {
  let parsed = grid(puzzle_text)
  assert dict.get(parsed, 0) == Ok(5)
  assert dict.get(parsed, 2) == Ok(0)
  assert dict.get(parsed, 75) == Ok(0)
  assert dict.get(parsed, 80) == Ok(9)
}

pub fn parse_round_trips_test() {
  let text = board.to_string(grid(solution_text))
  assert string.length(text) == 81
  assert board.to_string(grid(text)) == text
}

pub fn parse_rejects_the_wrong_number_of_cells_test() {
  assert board.parse("123") == Error(Nil)
  assert board.parse(solution_text <> "5") == Error(Nil)
}

// ---------------------------------------------------------------------------
// Candidates and conflicts
// ---------------------------------------------------------------------------

pub fn candidates_exclude_peers_test() {
  let peers = board.peers_table()
  let start = grid(puzzle_text)

  // A1 holds a 5, and the empty cell A3 sees it along with 3, 7, 6, 9 and 8.
  assert board.candidates(start, peers, board.at(0, 2)) == [1, 2, 4]
}

pub fn a_solved_grid_has_no_conflicts_test() {
  let solved = board.from_grid(grid(solution_text))
  assert set.is_empty(board.conflicts(solved))
  assert board.is_solved(solved)
}

pub fn duplicates_in_a_unit_are_conflicts_test() {
  // Two 5s in the top row.
  let clashing =
    board.from_grid(grid(solution_text))
    |> fn(solved) {
      board.Board(..solved, values: dict.insert(solved.values, 1, 5))
    }

  let clashes = board.conflicts(clashing)
  assert set.contains(clashes, 0)
  assert set.contains(clashes, 1)
  assert !board.is_solved(clashing)
}

pub fn an_incomplete_grid_is_not_solved_test() {
  assert !board.is_solved(board.from_grid(grid(puzzle_text)))
}

// ---------------------------------------------------------------------------
// Board editing
// ---------------------------------------------------------------------------

pub fn givens_cannot_be_edited_test() {
  let start = board.from_grid(grid(puzzle_text))

  assert board.is_given(start, 0)
  assert board.value(board.place(start, 0, 9), 0) == 5
  assert board.value(board.erase(start, 0), 0) == 5
}

pub fn blank_cells_can_be_written_and_cleared_test() {
  let start = board.from_grid(grid(puzzle_text))
  let empty_before = board.empty_count(start)

  let filled = board.place(start, 2, 4)
  assert board.value(filled, 2) == 4
  assert board.empty_count(filled) == empty_before - 1

  assert board.value(board.erase(filled, 2), 2) == 0
  assert board.empty_count(board.erase(filled, 2)) == empty_before
}

// ---------------------------------------------------------------------------
// Pencil marks
// ---------------------------------------------------------------------------

pub fn cells_start_unmarked_test() {
  let start = board.from_grid(grid(puzzle_text))
  assert set.is_empty(board.marks_at(start, 2))
  assert board.sorted_marks(start, 2) == []
}

pub fn marks_toggle_on_and_off_test() {
  let start = board.from_grid(grid(puzzle_text))

  let marked = board.toggle_mark(start, 2, 4)
  assert board.sorted_marks(marked, 2) == [4]

  let more = marked |> board.toggle_mark(2, 1) |> board.toggle_mark(2, 9)
  assert board.sorted_marks(more, 2) == [1, 4, 9]

  // Marking a digit that is already there rubs it out again.
  assert board.sorted_marks(board.toggle_mark(more, 2, 4), 2) == [1, 9]
}

pub fn marks_do_not_count_as_digits_test() {
  let start = board.from_grid(grid(puzzle_text))
  let marked = board.toggle_mark(start, 2, 4)

  assert board.value(marked, 2) == 0
  assert board.empty_count(marked) == board.empty_count(start)
  assert set.is_empty(board.conflicts(marked))
}

pub fn clues_cannot_be_marked_test() {
  let start = board.from_grid(grid(puzzle_text))
  assert board.sorted_marks(board.toggle_mark(start, 0, 4), 0) == []
}

pub fn marks_can_be_cleared_test() {
  let marked =
    board.from_grid(grid(puzzle_text))
    |> board.toggle_mark(2, 1)
    |> board.toggle_mark(2, 4)

  assert board.sorted_marks(board.clear_marks(marked, 2), 2) == []
}

pub fn writing_a_digit_clears_that_cell_s_marks_test() {
  let marked =
    board.from_grid(grid(puzzle_text))
    |> board.toggle_mark(2, 1)
    |> board.toggle_mark(2, 4)

  assert board.sorted_marks(board.place(marked, 2, 4), 2) == []
}

pub fn writing_a_digit_retracts_it_from_cells_that_see_it_test() {
  // Empty cells that can all see A3: A9 shares its row, D3 its column and B2
  // its box. E5 can see none of them. Mark a 4 and a 7 in each.
  let seen = [board.at(0, 8), board.at(3, 2), board.at(1, 1)]
  let unseen = board.at(4, 4)

  let marked = {
    use current, index <- list.fold(
      [unseen, ..seen],
      board.from_grid(grid(puzzle_text)),
    )
    current |> board.toggle_mark(index, 4) |> board.toggle_mark(index, 7)
  }

  // Every cell really did take both marks, or the test proves nothing.
  use index <- list.each([unseen, ..seen])
  assert board.sorted_marks(marked, index) == [4, 7]

  let placed = board.place(marked, board.at(0, 2), 4)

  // The 4s that the new digit rules out are gone, and only those.
  use index <- list.each(seen)
  assert board.sorted_marks(placed, index) == [7]
  assert board.sorted_marks(placed, unseen) == [4, 7]
  assert board.sorted_marks(placed, board.at(0, 2)) == []
}

pub fn peers_of_a_cell_are_its_twenty_neighbours_test() {
  use index <- list.each(board.indices())
  let peers = board.peers_of(index)

  assert list.length(peers) == 20
  assert !list.contains(peers, index)
  // The arithmetic version agrees with the table the solver uses.
  let assert Ok(tabled) = dict.get(board.peers_table(), index)
  assert set.from_list(peers) == tabled
}

// ---------------------------------------------------------------------------
// Solving
// ---------------------------------------------------------------------------

pub fn solver_finds_the_solution_test() {
  let assert Ok(solved) = solver.solve(grid(puzzle_text))
  assert board.to_string(solved) == board.to_string(grid(solution_text))
}

pub fn solver_leaves_a_finished_grid_alone_test() {
  let assert Ok(solved) = solver.solve(grid(solution_text))
  assert board.to_string(solved) == board.to_string(grid(solution_text))
}

pub fn solver_rejects_a_contradictory_grid_test() {
  // Two 1s in the top row. Rejected up front rather than searched for.
  let clashing = dict.insert(dict.insert(board.empty_grid(), 0, 1), 1, 1)
  assert solver.solve(clashing) == Error(Nil)
  assert solver.solve_random(clashing) == Error(Nil)
  assert solver.count_solutions(clashing, 5) == 0
}

pub fn solver_rejects_a_dead_end_test() {
  // Consistent so far, but A1 is left with no legal digit: the rest of its
  // row, column and box between them use up all nine.
  let dead_end =
    grid(
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
  assert solver.solve(dead_end) == Error(Nil)
}

pub fn solver_fills_the_empty_grid_test() {
  let assert Ok(filled) = solver.solve_random(board.empty_grid())
  assert board.is_solved(board.from_grid(filled))
}

pub fn a_proper_puzzle_has_exactly_one_solution_test() {
  assert solver.count_solutions(grid(puzzle_text), 5) == 1
}

pub fn too_few_clues_allow_many_solutions_test() {
  // Blanking every 1 and every 2 leaves a grid that can be finished two ways,
  // since the two digits can be swapped throughout.
  let loosened =
    grid(solution_text)
    |> dict.map_values(fn(_index, digit) {
      case digit {
        1 | 2 -> 0
        _ -> digit
      }
    })

  assert solver.count_solutions(loosened, 5) == 2
}

pub fn counting_stops_at_the_limit_test() {
  assert solver.count_solutions(board.empty_grid(), 3) == 3
}

// ---------------------------------------------------------------------------
// Generating
// ---------------------------------------------------------------------------

pub fn generated_puzzles_are_well_formed_test() {
  use difficulty <- list.each([generator.Easy, generator.Hard])
  let puzzle = generator.generate(difficulty)

  assert puzzle.origin == generator.Dealt(difficulty)
  assert board.is_solved(board.from_grid(puzzle.solution))
  assert set.is_empty(board.conflicts(puzzle.board))

  // Every clue agrees with the solution it was carved from.
  use index <- list.each(board.indices())
  case board.value(puzzle.board, index) {
    0 -> Nil
    digit -> {
      assert Ok(digit) == dict.get(puzzle.solution, index)
    }
  }
}

pub fn generated_puzzles_have_one_answer_test() {
  let puzzle = generator.generate(generator.Medium)
  assert solver.count_solutions(puzzle.board.values, 5) == 1
}

pub fn generated_puzzles_hit_their_clue_target_test() {
  use difficulty <- list.each(generator.difficulties)
  let puzzle = generator.generate(difficulty)
  let clues = 81 - board.empty_count(puzzle.board)

  assert clues <= generator.target_clues(difficulty)
  // Carving never goes below the 17-clue floor for a unique Sudoku.
  assert clues >= 17
}

pub fn difficulty_targets_descend_test() {
  let targets = list.map(generator.difficulties, generator.target_clues)
  assert targets == list.reverse(list.sort(targets, by: int.compare))
}

// ---------------------------------------------------------------------------
// Typing a puzzle in
// ---------------------------------------------------------------------------

fn edit(current: editor.Editor, pressed: key.Key) -> editor.Editor {
  let assert editor.Continue(next) = editor.update(current, pressed)
  next
}

/// Type a grid in one keystroke per cell, the way a puzzle is copied off a
/// page. Layout is ignored, just as `board.parse` ignores it.
fn typed(text: String) -> editor.Editor {
  use current, character <- list.fold(string.to_graphemes(text), editor.new())
  case character {
    "." | "_" | "0" -> edit(current, key.Erase)
    _ ->
      case int.parse(character) {
        Ok(digit) -> edit(current, key.Digit(digit))
        Error(_) -> current
      }
  }
}

pub fn an_editor_starts_empty_at_the_first_cell_test() {
  let start = editor.new()

  assert editor.clue_count(start) == 0
  assert start.cursor == 0
  assert board.to_string(start.clues) == string.repeat(".", 81)
}

pub fn typing_a_digit_steps_on_to_the_next_cell_test() {
  let typing = editor.new() |> edit(key.Digit(5)) |> edit(key.Digit(3))

  assert editor.value(typing, 0) == 5
  assert editor.value(typing, 1) == 3
  assert typing.cursor == 2
  assert editor.clue_count(typing) == 2
}

pub fn a_gap_key_steps_on_without_writing_test() {
  let typing = editor.new() |> edit(key.Erase) |> edit(key.Digit(4))

  assert editor.value(typing, 0) == 0
  assert editor.value(typing, 1) == 4
  assert typing.cursor == 2
}

pub fn typing_over_a_cell_replaces_the_clue_test() {
  let fixed =
    editor.new() |> edit(key.Digit(5)) |> edit(key.Left) |> edit(key.Digit(6))

  assert editor.value(fixed, 0) == 6
  assert editor.clue_count(fixed) == 1
}

pub fn typing_a_whole_grid_lands_every_clue_test() {
  let entered = typed(puzzle_text)

  assert board.to_string(entered.clues) == board.to_string(grid(puzzle_text))
  assert editor.clue_count(entered) == 30
  // Eighty-one keystrokes bring the cursor back round to where it started.
  assert entered.cursor == 0
}

pub fn the_editor_cursor_wraps_around_the_edges_test() {
  let start = editor.new()

  assert edit(start, key.Left).cursor == board.at(0, 8)
  assert edit(start, key.Up).cursor == board.at(8, 0)
  assert edit(start, key.Down).cursor == board.at(1, 0)
}

pub fn undo_walks_back_through_typing_test() {
  let typing = editor.new() |> edit(key.Digit(5)) |> edit(key.Digit(3))

  let once = edit(typing, key.Char("u"))
  assert editor.value(once, 1) == 0
  assert editor.value(once, 0) == 5

  let twice = edit(once, key.Char("u"))
  assert editor.clue_count(twice) == 0
  assert edit(twice, key.Char("u")).message == "Nothing left to undo."
}

pub fn clearing_empties_the_grid_test() {
  let cleared = typed(puzzle_text) |> edit(key.Char("x"))

  assert editor.clue_count(cleared) == 0
  assert cleared.cursor == 0
  // And it is one undo away, so it cannot be pressed by mistake.
  assert editor.clue_count(edit(cleared, key.Char("u"))) == 30
  assert string.contains(edit(cleared, key.Char("x")).message, "already empty")
}

pub fn typed_clues_become_a_playable_puzzle_test() {
  let assert editor.Ready(puzzle) =
    editor.update(typed(puzzle_text), key.Char("p"))

  assert puzzle.origin == generator.Handwritten
  assert board.to_string(puzzle.solution)
    == board.to_string(grid(solution_text))

  // Every typed digit is a clue, and the rest of the grid is there to play.
  assert board.to_string(puzzle.board.values)
    == board.to_string(grid(puzzle_text))
  assert board.is_given(puzzle.board, 0)
  assert !board.is_given(puzzle.board, 2)
}

pub fn a_typed_puzzle_plays_like_any_other_test() {
  let assert editor.Ready(puzzle) =
    editor.update(typed(puzzle_text), key.Char("p"))
  let started = game.new(puzzle)

  // A3 is a 4 in the answer, so checking and hints know that much.
  assert game.answer(started, 2) == 4
  assert board.value(step(started, key.Char("H")).board, 2) == 4
}

pub fn an_empty_grid_cannot_be_played_test() {
  let assert editor.Continue(refused) =
    editor.update(editor.new(), key.Char("p"))

  assert string.contains(refused.message, "Type the clues in first")
}

pub fn clashing_clues_cannot_be_played_test() {
  // A second 5 in the top row, alongside the one already at A1.
  let clashing = typed(puzzle_text) |> edit(key.Right) |> edit(key.Digit(5))

  let assert editor.Continue(refused) = editor.update(clashing, key.Char("p"))
  assert refused.message == editor.refusal(generator.Clashes)
  assert string.contains(refused.message, "clash")
}

pub fn clues_with_no_answer_cannot_be_played_test() {
  // Consistent so far, but A1 is left with no legal digit.
  let dead_end =
    typed(
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
    typed(string.replace(string.replace(solution_text, "1", "."), "2", "."))

  let assert editor.Continue(refused) = editor.update(loose, key.Char("p"))
  assert refused.message == editor.refusal(generator.Ambiguous)
  assert string.contains(refused.message, "missing")
}

pub fn from_clues_reports_why_it_refused_test() {
  let clashing = dict.insert(grid(puzzle_text), 1, 5)
  assert generator.from_clues(clashing) == Error(generator.Clashes)
  assert generator.from_clues(board.empty_grid()) == Error(generator.Ambiguous)

  let assert Ok(puzzle) = generator.from_clues(grid(puzzle_text))
  assert puzzle.origin == generator.Handwritten
}

pub fn the_editor_help_opens_and_any_key_closes_it_test() {
  let opened = edit(editor.new(), key.Char("?"))
  assert opened.show_help

  assert !edit(opened, key.Char("?")).show_help
  // Dismissing help does not also type a digit in.
  let dismissed = edit(opened, key.Digit(5))
  assert !dismissed.show_help
  assert editor.clue_count(dismissed) == 0
}

pub fn the_editor_can_be_left_test() {
  assert editor.update(editor.new(), key.Char("q")) == editor.Exit
  assert editor.update(editor.new(), key.Quit) == editor.Exit
  assert editor.update(editor.new(), key.Char("n")) == editor.Cancel
}

// ---------------------------------------------------------------------------
// Decoding keystrokes
// ---------------------------------------------------------------------------

/// Decode a keystroke from a fixed run of bytes.
fn press(bytes: List(Int)) -> key.Key {
  let #(pressed, _) = {
    use remaining <- key.decode(bytes)
    case remaining {
      [] -> #(-1, [])
      [byte, ..rest] -> #(byte, rest)
    }
  }
  pressed
}

pub fn digits_decode_test() {
  assert press([0x31]) == key.Digit(1)
  assert press([0x39]) == key.Digit(9)
}

pub fn erasing_keys_decode_test() {
  // 0, space, backspace, delete.
  assert press([0x30]) == key.Erase
  assert press([0x20]) == key.Erase
  assert press([0x08]) == key.Erase
  assert press([0x7f]) == key.Erase
}

pub fn arrow_keys_decode_test() {
  assert press([0x1b, 0x5b, 0x41]) == key.Up
  assert press([0x1b, 0x5b, 0x42]) == key.Down
  assert press([0x1b, 0x5b, 0x43]) == key.Right
  assert press([0x1b, 0x5b, 0x44]) == key.Left
  // Some terminals send the application-mode form, `ESC O A`.
  assert press([0x1b, 0x4f, 0x41]) == key.Up
}

pub fn the_delete_key_decodes_test() {
  assert press([0x1b, 0x5b, 0x33, 0x7e]) == key.Erase
}

pub fn letter_case_is_kept_test() {
  // `h` moves the cursor and `H` asks for a hint, so they must stay distinct.
  assert press([0x68]) == key.Char("h")
  assert press([0x48]) == key.Char("H")
  assert press([0x72]) == key.Char("r")
  assert press([0x52]) == key.Char("R")
  assert press([0x3f]) == key.Char("?")
}

pub fn a_lone_escape_does_not_eat_the_next_key_test() {
  assert press([0x1b, 0x71]) == key.Char("q")
}

pub fn running_out_of_input_quits_test() {
  assert press([]) == key.Quit
  assert press([0x1b]) == key.Quit
  assert press([0x1b, 0x5b]) == key.Quit
  // Ctrl-C.
  assert press([0x03]) == key.Quit
}

pub fn enter_does_nothing_test() {
  // Line mode delivers a newline after every key; it must not be a command.
  assert press([0x0d]) == key.Unknown
  assert press([0x0a]) == key.Unknown
}

// ---------------------------------------------------------------------------
// Game rules
// ---------------------------------------------------------------------------

fn fixture() -> game.Game {
  game.new(generator.Puzzle(
    board: board.from_grid(grid(puzzle_text)),
    solution: grid(solution_text),
    origin: generator.Dealt(generator.Medium),
  ))
}

fn step(current: game.Game, pressed: key.Key) -> game.Game {
  let assert game.Continue(next) = game.update(current, pressed)
  next
}

pub fn a_new_game_starts_on_the_first_empty_cell_test() {
  let started = fixture()
  assert started.cursor == 2
  assert !game.is_finished(started)
}

pub fn the_cursor_wraps_around_the_edges_test() {
  let at_start = game.Game(..fixture(), cursor: board.at(0, 0))

  assert step(at_start, key.Left).cursor == board.at(0, 8)
  assert step(at_start, key.Up).cursor == board.at(8, 0)
  assert step(at_start, key.Right).cursor == board.at(0, 1)
  assert step(at_start, key.Down).cursor == board.at(1, 0)
}

pub fn vim_and_wasd_keys_move_too_test() {
  let middle = game.Game(..fixture(), cursor: board.at(4, 4))

  assert step(middle, key.Char("k")).cursor == board.at(3, 4)
  assert step(middle, key.Char("j")).cursor == board.at(5, 4)
  assert step(middle, key.Char("a")).cursor == board.at(4, 3)
  assert step(middle, key.Char("d")).cursor == board.at(4, 5)
}

pub fn digits_land_in_the_cell_under_the_cursor_test() {
  let played = step(fixture(), key.Digit(4))
  assert board.value(played.board, 2) == 4
}

pub fn clues_refuse_to_change_test() {
  let on_a_clue = game.Game(..fixture(), cursor: 0)
  let played = step(on_a_clue, key.Digit(9))

  assert board.value(played.board, 0) == 5
  assert played.message != ""
  // A refused move is not worth undoing.
  assert played.history == []
}

pub fn undo_walks_back_through_edits_test() {
  let played =
    fixture()
    |> step(key.Digit(4))
    |> step(key.Right)
    |> step(key.Digit(7))

  let once = step(played, key.Char("u"))
  assert board.value(once.board, 3) == 0
  assert board.value(once.board, 2) == 4

  let twice = step(once, key.Char("u"))
  assert board.value(twice.board, 2) == 0
  assert twice.history == []

  // Undoing past the beginning is harmless.
  assert step(twice, key.Char("u")).history == []
}

pub fn erasing_clears_a_filled_cell_test() {
  let played = fixture() |> step(key.Digit(4)) |> step(key.Erase)
  assert board.value(played.board, 2) == 0
}

pub fn checking_counts_wrong_digits_test() {
  // A3 is a 4 in the solution, so a 1 there is wrong.
  let played = step(fixture(), key.Digit(1))
  assert game.is_wrong(played, 2)

  let checked = step(played, key.Char("c"))
  assert checked.checking
  assert checked.message == "1 digit is wrong."

  // Pressing it again turns checking back off.
  assert !step(checked, key.Char("c")).checking
}

pub fn a_hint_fills_the_cell_under_the_cursor_test() {
  let hinted = step(fixture(), key.Char("H"))
  assert board.value(hinted.board, 2) == 4
  assert hinted.hints == 1
}

pub fn a_hint_on_a_filled_cell_moves_to_the_next_gap_test() {
  let on_a_clue = game.Game(..fixture(), cursor: 0)
  let hinted = step(on_a_clue, key.Char("H"))

  assert hinted.cursor == 2
  assert board.value(hinted.board, 2) == 4
}

pub fn revealing_finishes_the_puzzle_test() {
  let revealed = step(fixture(), key.Char("R"))

  assert revealed.revealed
  assert game.is_finished(revealed)
  assert board.is_solved(revealed.board)
  assert board.to_string(revealed.board.values)
    == board.to_string(grid(solution_text))
}

pub fn filling_the_last_cell_wins_test() {
  let start = fixture()
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
        |> step(key.Digit(game.answer(current, index)))
    }
  }

  assert !game.is_finished(almost)
  assert board.empty_count(almost.board) == 1

  let won =
    game.Game(..almost, cursor: last)
    |> step(key.Digit(game.answer(almost, last)))

  assert game.is_finished(won)
  assert !won.revealed
  assert board.is_solved(won.board)
}

pub fn a_finished_puzzle_ignores_further_edits_test() {
  let revealed = step(fixture(), key.Char("R"))
  let poked = step(game.Game(..revealed, cursor: 2), key.Erase)
  assert board.value(poked.board, 2) == 4
}

pub fn help_opens_and_any_key_closes_it_test() {
  let opened = step(fixture(), key.Char("?"))
  assert opened.show_help

  assert !step(opened, key.Char("?")).show_help
  assert !step(opened, key.Down).show_help
  // Dismissing help does not also move the cursor.
  assert step(opened, key.Down).cursor == opened.cursor
}

pub fn quit_and_restart_leave_the_loop_test() {
  assert game.update(fixture(), key.Char("q")) == game.Exit
  assert game.update(fixture(), key.Quit) == game.Exit
  assert game.update(fixture(), key.Char("n")) == game.Restart
}

pub fn the_clock_runs_from_the_start_test() {
  assert game.elapsed_ms(fixture()) >= 0
}

// ---------------------------------------------------------------------------
// Marking during play
// ---------------------------------------------------------------------------

pub fn m_switches_between_writing_and_marking_test() {
  let start = fixture()
  assert !start.marking

  let marking = step(start, key.Char("m"))
  assert marking.marking
  assert !step(marking, key.Char("m")).marking
}

pub fn digits_pencil_marks_in_while_marking_test() {
  let marked =
    fixture() |> step(key.Char("m")) |> step(key.Digit(4)) |> step(key.Digit(1))

  assert board.sorted_marks(marked.board, 2) == [1, 4]
  // The cell is still empty as far as the puzzle is concerned.
  assert board.value(marked.board, 2) == 0
}

pub fn marking_the_same_digit_twice_rubs_it_out_test() {
  let marked =
    fixture() |> step(key.Char("m")) |> step(key.Digit(4)) |> step(key.Digit(4))

  assert board.sorted_marks(marked.board, 2) == []
}

pub fn erase_clears_every_mark_on_the_cell_test() {
  let cleared =
    fixture()
    |> step(key.Char("m"))
    |> step(key.Digit(4))
    |> step(key.Digit(1))
    |> step(key.Erase)

  assert board.sorted_marks(cleared.board, 2) == []
}

pub fn marking_a_filled_cell_is_refused_test() {
  let played =
    fixture()
    |> step(key.Digit(4))
    |> step(key.Char("m"))
    |> step(key.Digit(1))

  assert board.sorted_marks(played.board, 2) == []
  assert board.value(played.board, 2) == 4
  assert string.contains(played.message, "already")
}

pub fn marking_a_clue_is_refused_test() {
  let played =
    game.Game(..fixture(), cursor: 0)
    |> step(key.Char("m"))
    |> step(key.Digit(1))

  assert board.sorted_marks(played.board, 0) == []
  assert string.contains(played.message, "clue")
}

pub fn undo_walks_back_through_marks_test() {
  let marked =
    fixture() |> step(key.Char("m")) |> step(key.Digit(4)) |> step(key.Digit(1))

  let once = step(marked, key.Char("u"))
  assert board.sorted_marks(once.board, 2) == [4]

  let twice = step(once, key.Char("u"))
  assert board.sorted_marks(twice.board, 2) == []
}

pub fn writing_a_digit_during_play_tidies_up_marks_test() {
  // Mark a 4 two cells along the top row, then write a 4 in the first.
  let marked =
    game.Game(..fixture(), cursor: board.at(0, 8))
    |> step(key.Char("m"))
    |> step(key.Digit(4))
    |> step(key.Char("m"))

  let placed = game.Game(..marked, cursor: board.at(0, 2)) |> step(key.Digit(4))

  assert board.sorted_marks(placed.board, board.at(0, 8)) == []
}

pub fn hints_and_reveals_tidy_up_marks_too_test() {
  let marked =
    fixture()
    |> step(key.Char("m"))
    |> step(key.Digit(1))
    |> step(key.Digit(4))
    |> step(key.Char("m"))

  assert board.sorted_marks(step(marked, key.Char("H")).board, 2) == []
  assert board.sorted_marks(step(marked, key.Char("R")).board, 2) == []
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// One grid's worth of columns, and the whole frame's worth: two grids and
/// the gap between them.
const grid_columns = 27

const frame_width = 59

/// The board half of a line, and the marks half beside it.
fn board_half(line: String) -> String {
  string.slice(line, 1, grid_columns)
}

fn marks_half(line: String) -> String {
  string.slice(line, 1 + grid_columns + 4, grid_columns)
}

/// Drop ANSI escape sequences so that the layout underneath can be checked.
fn plain(text: String) -> String {
  strip(string.to_graphemes(text), [], Text)
}

type Scan {
  Text
  SawEscape
  InSequence
}

fn strip(characters: List(String), kept: List(String), scan: Scan) -> String {
  case characters, scan {
    [], _ -> kept |> list.reverse |> string.concat
    ["\u{1b}", ..rest], _ -> strip(rest, kept, SawEscape)
    // The `[` introducing a control sequence.
    [_, ..rest], SawEscape -> strip(rest, kept, InSequence)
    [character, ..rest], InSequence ->
      case string.contains("0123456789;?", character) {
        True -> strip(rest, kept, InSequence)
        False -> strip(rest, kept, Text)
      }
    [character, ..rest], Text -> strip(rest, [character, ..kept], Text)
  }
}

fn visible_lines(current: game.Game) -> List(String) {
  render.frame(current)
  |> plain
  |> string.split("\r\n")
  |> list.map(string.trim_end)
}

fn is_grid_row(line: String) -> Bool {
  ["A", "B", "C", "D", "E", "F", "G", "H", "I"]
  |> list.any(fn(label) {
    string.starts_with(line, " " <> label <> " \u{2502}")
  })
}

pub fn escape_stripping_leaves_the_text_test() {
  assert plain("\u{1b}[1;95mS U D O K U\u{1b}[0m") == "S U D O K U"
  // `H` and `J` end sequences just as `m` does, and text can contain an `m`.
  assert plain("\u{1b}[H\u{1b}[Jtime\u{1b}[0m") == "time"
}

pub fn the_frame_draws_a_grid_test() {
  let lines = visible_lines(fixture())

  assert list.contains(
    lines,
    "     1 2 3   4 5 6   7 8 9          1 2 3   4 5 6   7 8 9",
  )
  assert list.contains(
    lines,
    "   ┌───────┬───────┬───────┐      ┌───────┬───────┬───────┐",
  )
  assert list.contains(
    lines,
    " A │ 5 3 · │ · 7 · │ · · · │    A │ · · · │ · · · │ · · · │",
  )
  assert list.contains(
    lines,
    " I │ · · · │ · 8 · │ · 7 9 │    I │ · · · │ · · · │ · · · │",
  )
  assert list.contains(
    lines,
    "   └───────┴───────┴───────┘      └───────┴───────┴───────┘",
  )
}

pub fn the_two_grids_are_labelled_test() {
  let lines = visible_lines(fixture())
  let assert Ok(caption) =
    list.first(list.filter(lines, string.contains(_, "board")))

  // Each caption sits over the left edge of the grid it names.
  assert string.starts_with(caption, "   board")
  assert string.slice(caption, 1 + grid_columns + 4 + 2, 5) == "marks"
}

pub fn all_nine_rows_are_drawn_test() {
  let rows = visible_lines(fixture()) |> list.filter(is_grid_row)
  assert list.length(rows) == 9

  // Every row is drawn twice over, once in each grid, to the same shape.
  use row <- list.each(rows)
  assert string.length(board_half(row)) == grid_columns
  assert string.length(marks_half(row)) == grid_columns
  assert string.starts_with(marks_half(row), string.slice(row, 1, 4))
}

pub fn grid_lines_all_have_the_same_width_test() {
  let widths =
    visible_lines(fixture())
    |> list.filter(fn(line) { is_grid_row(line) || string.contains(line, "─") })
    |> list.map(string.length)
    |> list.unique

  assert widths == [frame_width]
}

pub fn the_column_ruler_lines_up_with_the_cells_test() {
  let lines = visible_lines(fixture())
  // The ruler is the line just above the top of the box.
  let assert Ok(ruler) =
    lines
    |> list.take_while(fn(line) { !string.contains(line, "┌") })
    |> list.last
  let assert Ok(row) = list.first(list.filter(lines, is_grid_row))

  // The first column's heading sits directly above the first cell's digit,
  // in the grid of marks just as in the board.
  assert string.slice(ruler, 5, 1) == "1"
  assert string.slice(row, 5, 1) == "5"
  assert string.slice(ruler, 5 + grid_columns + 4, 1) == "1"
}

// ---------------------------------------------------------------------------
// The grid of marks
// ---------------------------------------------------------------------------

/// Pencil `digits` into the cell under the cursor and return to writing.
fn with_marks(current: game.Game, digits: List(Int)) -> game.Game {
  digits
  |> list.fold(step(current, key.Char("m")), fn(marking, digit) {
    step(marking, key.Digit(digit))
  })
  |> step(key.Char("m"))
}

pub fn a_lone_mark_shows_as_itself_test() {
  // A3 is the cursor cell, so the mark lands in the third column of row A.
  let lines = visible_lines(with_marks(fixture(), [4]))
  let assert Ok(row) = list.first(list.filter(lines, is_grid_row))

  assert marks_half(row) == "A │ · · 4 │ · · · │ · · · │"
  // The board itself is untouched: A3 is still empty.
  assert board_half(row) == "A │ 5 3 · │ · 7 · │ · · · │"
}

pub fn several_marks_show_as_an_asterisk_test() {
  let lines = visible_lines(with_marks(fixture(), [4, 1]))
  let assert Ok(row) = list.first(list.filter(lines, is_grid_row))

  assert marks_half(row) == "A │ · · * │ · · · │ · · · │"
}

pub fn an_asterisk_can_be_read_back_from_the_status_line_test() {
  let crowded = with_marks(fixture(), [9, 1, 5, 3, 7])
  let lines = visible_lines(crowded)
  let assert Ok(row) = list.first(list.filter(lines, is_grid_row))

  assert string.contains(marks_half(row), "*")
  assert list.any(lines, string.contains(_, "A3 marked 1 3 5 7 9"))
}

pub fn unmarked_cells_stay_empty_in_the_marks_grid_test() {
  let rows = visible_lines(fixture()) |> list.filter(is_grid_row)

  use row <- list.each(rows)
  assert !string.contains(marks_half(row), "*")
  assert marks_half(row) == string.slice(row, 1, 4) <> "· · · │ · · · │ · · · │"
}

pub fn the_status_line_names_the_cursor_cell_test() {
  let marked = game.Game(..fixture(), cursor: board.at(6, 3)) |> with_marks([7])
  assert list.any(visible_lines(marked), string.contains(_, "G4 marked 7"))

  // An unmarked cell says nothing at all.
  assert !list.any(visible_lines(fixture()), string.contains(_, "marked"))
}

pub fn marking_mode_is_announced_test() {
  let marking = step(fixture(), key.Char("m"))
  let lines = visible_lines(marking)

  assert list.any(lines, string.contains(_, "S U D O K U    Medium    marking"))
  assert list.any(lines, string.contains(_, "1-9 mark"))
  assert list.any(lines, string.contains(_, "m write"))

  // Writing mode says the opposite, and never says "marking" in the header.
  let writing = visible_lines(fixture())
  assert list.any(writing, string.contains(_, "1-9 place"))
  assert !list.any(writing, string.contains(_, "marking"))
}

pub fn marks_do_not_change_the_grid_width_test() {
  let widths =
    visible_lines(with_marks(fixture(), [1, 2, 3, 4, 5]))
    |> list.filter(fn(line) { is_grid_row(line) || string.contains(line, "─") })
    |> list.map(string.length)
    |> list.unique

  assert widths == [frame_width]
}

pub fn the_status_line_reports_progress_test() {
  let lines = visible_lines(fixture())
  assert list.any(lines, string.contains(_, "empty 51"))
  assert list.any(lines, string.contains(_, "clashes 0"))
  assert list.any(lines, string.contains(_, "time 00:"))
}

pub fn the_status_line_counts_clashes_test() {
  // A 6 at C1 clashes twice over: with the 6 above it at B1, and with the 6
  // further along row C. All three cells are counted.
  let clashing =
    game.Game(..fixture(), cursor: board.at(2, 0)) |> step(key.Digit(6))

  assert list.any(visible_lines(clashing), string.contains(_, "clashes 3"))
}

pub fn the_help_screen_lists_the_keys_test() {
  let lines = visible_lines(step(fixture(), key.Char("?")))
  assert list.any(lines, string.contains(_, "write a digit"))
  assert list.any(lines, string.contains(_, "reveal the whole solution"))

  // Help takes the screen over rather than sharing it with the board.
  assert !list.any(lines, is_grid_row)
}

pub fn every_frame_fits_a_short_terminal_test() {
  let start = fixture()
  let frames = [
    start,
    step(start, key.Char("?")),
    step(start, key.Char("R")),
    with_marks(start, [1, 2, 3, 4, 5]),
  ]

  use current <- list.each(frames)
  assert list.length(visible_lines(current)) <= 24
}

pub fn finishing_shows_a_result_test() {
  let lines = visible_lines(step(fixture(), key.Char("R")))
  assert list.any(lines, string.contains(_, "Solution revealed."))
  assert list.any(lines, string.contains(_, "n new puzzle"))
}

pub fn the_cursor_is_highlighted_test() {
  // Reverse video, then the empty cell the cursor starts on.
  assert string.contains(render.frame(fixture()), "7;90m \u{b7}")
}

pub fn the_frame_starts_at_the_top_of_the_screen_test() {
  assert string.starts_with(render.frame(fixture()), "\u{1b}[H")
}

// ---------------------------------------------------------------------------
// Rendering a puzzle being typed in
// ---------------------------------------------------------------------------

fn editor_lines(current: editor.Editor) -> List(String) {
  render.editor_frame(current)
  |> plain
  |> string.split("\r\n")
  |> list.map(string.trim_end)
}

pub fn the_editor_draws_the_clues_as_they_are_typed_test() {
  let lines = editor_lines(typed(puzzle_text))

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
  let rows = editor_lines(typed(puzzle_text)) |> list.filter(is_grid_row)

  assert list.length(rows) == 9
  // One grid's worth of columns, and no marks grid beside it.
  use row <- list.each(rows)
  assert string.length(row) == 1 + grid_columns
}

pub fn the_editor_counts_clashing_clues_test() {
  let clashing = typed(puzzle_text) |> edit(key.Right) |> edit(key.Digit(5))
  assert list.any(editor_lines(clashing), string.contains(_, "clashes 2"))
}

pub fn the_editor_help_lists_its_own_keys_test() {
  let lines = editor_lines(edit(editor.new(), key.Char("?")))

  assert list.any(lines, string.contains(_, "type a clue in and step on"))
  assert list.any(lines, string.contains(_, "play the puzzle"))
  assert !list.any(lines, is_grid_row)
}

pub fn every_editor_frame_fits_a_short_terminal_test() {
  let frames = [
    editor.new(),
    typed(puzzle_text),
    edit(editor.new(), key.Char("?")),
  ]

  use current <- list.each(frames)
  assert list.length(editor_lines(current)) <= 24
}
