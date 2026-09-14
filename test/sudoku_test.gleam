import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/set
import gleam/string
import gleeunit
import sudoku/board
import sudoku/editor
import sudoku/game
import sudoku/generator
import sudoku/help
import sudoku/key
import sudoku/logic
import sudoku/render
import sudoku/solver
import sudoku/store
import sudoku/term

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
// Solving by reasoning
// ---------------------------------------------------------------------------

pub fn reasoning_solves_an_ordinary_puzzle_test() {
  let #(steps, reasoned) = logic.unfold(grid(puzzle_text))

  assert board.to_string(reasoned) == board.to_string(grid(solution_text))
  assert steps != []
}

/// The test that carries the others: whatever a technique claims, it has to
/// agree with the answer the puzzle was carved from. A digit settled is the
/// digit that belongs there, and a digit ruled out is never the one that did.
pub fn every_step_agrees_with_the_answer_test() {
  use difficulty <- list.each(generator.difficulties)
  let puzzle = generator.generate(difficulty)
  let #(steps, _) = logic.unfold(puzzle.board.values)

  use step <- list.each(steps)
  case step.move {
    logic.Settle(index, digit) -> {
      assert dict.get(puzzle.solution, index) == Ok(digit)
    }
    logic.RuleOut(cells, digits) -> {
      use index <- list.each(cells)
      let assert Ok(answer) = dict.get(puzzle.solution, index)
      assert !list.contains(digits, answer)
    }
  }
}

pub fn a_step_always_changes_something_test() {
  // A technique that ruled nothing out would be reported for ever.
  let puzzle = generator.generate(generator.Hard)
  let #(steps, _) = logic.unfold(puzzle.board.values)

  use step <- list.each(steps)
  case step.move {
    logic.Settle(_, _) -> Nil
    logic.RuleOut(cells, digits) -> {
      assert cells != []
      assert digits != []
    }
  }
}

pub fn the_simplest_step_comes_first_test() {
  // One cell left blank can only be a naked single.
  let one_short = dict.insert(grid(solution_text), 40, 0)
  let assert Ok(step) = logic.next(one_short)

  assert step.technique == logic.NakedSingle
  assert step.move == logic.Settle(40, 5)
  assert step.evidence == [40]
}

pub fn a_hint_names_a_digit_that_belongs_test() {
  let assert Ok(step) = logic.next(grid(puzzle_text))
  let assert logic.Settle(index, digit) = step.move

  assert dict.get(grid(solution_text), index) == Ok(digit)
  // Nothing harder than a single is needed to get started here.
  assert logic.rank(step.technique) <= logic.rank(logic.HiddenSingle)
}

pub fn reasoning_runs_out_on_an_empty_grid_test() {
  // Every cell can take anything, so no technique has anything to say.
  let #(steps, reasoned) = logic.unfold(board.empty_grid())

  assert steps == []
  assert reasoned == board.empty_grid()
  assert logic.rate(board.empty_grid()) == Error(Nil)
}

pub fn a_finished_grid_asks_nothing_test() {
  assert logic.rate(grid(solution_text)) == Ok(logic.NakedSingle)
}

pub fn a_puzzle_is_rated_by_its_hardest_step_test() {
  let assert Ok(rating) = logic.rate(grid(puzzle_text))
  let #(steps, _) = logic.unfold(grid(puzzle_text))

  // Nothing harder was used, and the rating was really used.
  use step <- list.each(steps)
  assert logic.rank(step.technique) <= logic.rank(rating)
}

pub fn an_explanation_names_what_it_is_about_test() {
  let hard_cases = [
    #(needs_naked_pair, logic.NakedPair),
    #(needs_hidden_pair, logic.HiddenPair),
    #(needs_naked_triple, logic.NakedTriple),
    #(needs_x_wing, logic.XWing),
    #(puzzle_text, logic.NakedSingle),
  ]

  use #(text, technique) <- list.each(hard_cases)
  let #(steps, _) = logic.unfold(grid(text))
  let assert Ok(step) =
    list.find(steps, fn(step) { step.technique == technique })
  let #(what, why) = logic.explain(step)

  // It names the technique, so the player has something to look up and to
  // recognise the next time it comes round.
  assert string.starts_with(
    string.lowercase(what),
    string.lowercase(logic.label(technique)),
  )

  // Both rows read as sentences rather than a dump of the working, and both
  // fit the status line.
  assert string.ends_with(what, ".")
  assert string.ends_with(why, ".")
  assert string.length(what) < 78
  assert string.length(why) < 78

  // The second row says why, so it is never the first one over again.
  assert why != what

  use digit <- list.each(step.about)
  assert string.contains(what, int.to_string(digit))
}

pub fn techniques_are_listed_easiest_first_test() {
  let ranks = list.map(logic.techniques, logic.rank)

  assert ranks == list.sort(ranks, by: int.compare)
  assert list.unique(ranks) == ranks
  // Every technique is listed, and every one has a name.
  assert list.length(logic.techniques) == 7
  assert list.all(logic.techniques, fn(t) { logic.label(t) != "" })
}

/// Puzzles hunted out of generated ones until each of the rarer techniques
/// was called for. A generated puzzle needs them only now and then, so they
/// are kept here to make sure the techniques that find them stay honest.
const needs_naked_pair = "
  ... ... .51
  27. 8.. 46.
  ... 39. 2..
  ..6 1.. ..4
  ..9 ... ...
  3.. ..2 9..
  ..2 .73 ...
  .37 ..6 .12
  9.. ... ...
"

const needs_hidden_pair = "
  8.. ... 7..
  ..5 7.4 ...
  6.. .3. .9.
  93. ..5 ...
  56. ... .21
  ... 1.. .59
  .5. .7. ..2
  ... 8.2 4..
  ..6 ... ..7
"

const needs_naked_triple = "
  ... ..4 1.3
  ... 1.. ...
  9.. ..5 .46
  ..6 2.. ..9
  .5. 9.3 .2.
  2.8 .16 ...
  76. 5.. ..1
  ... ... ...
  1.5 6.. ...
"

const needs_x_wing = "
  .6. 32. .7.
  ... 5.8 42.
  ... 7.4 6..
  .14 ... ..2
  ... ... ...
  7.. ... 84.
  ..9 8.1 ...
  .71 4.6 ...
  ... ..3 .6.
"

pub fn the_rarer_techniques_are_used_where_they_are_needed_test() {
  let hard_cases = [
    #(needs_naked_pair, logic.NakedPair),
    #(needs_hidden_pair, logic.HiddenPair),
    #(needs_naked_triple, logic.NakedTriple),
    #(needs_x_wing, logic.XWing),
  ]

  use #(text, technique) <- list.each(hard_cases)
  let start = grid(text)
  let #(steps, _) = logic.unfold(start)
  let assert Ok(answer) = solver.solve(start) as "the fixtures are solvable"

  // The technique really is called for here...
  assert list.any(steps, fn(step) { step.technique == technique })

  // ...and every step of the way agrees with the answer the search finds,
  // which is the two solvers checking each other.
  use step <- list.each(steps)
  case step.move {
    logic.Settle(index, digit) -> {
      assert dict.get(answer, index) == Ok(digit)
    }
    logic.RuleOut(cells, digits) -> {
      use index <- list.each(cells)
      let assert Ok(right) = dict.get(answer, index)
      assert !list.contains(digits, right)
    }
  }
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

/// The promise a difficulty makes: a dealt puzzle can always be reasoned out,
/// and never asks for more reasoning than the level it came from allows.
pub fn generated_puzzles_can_be_reasoned_out_test() {
  use difficulty <- list.each(generator.difficulties)
  let puzzle = generator.generate(difficulty)

  let assert Ok(needed) = logic.rate(puzzle.board.values)
    as "a dealt puzzle never needs a guess"
  assert logic.rank(needed) <= logic.rank(generator.hardest(difficulty))

  // And it is still a puzzle: carving never goes below the 17-clue floor.
  assert 81 - board.empty_count(puzzle.board) >= 17
}

pub fn a_difficulty_can_be_named_test() {
  // What the command line takes, in any capitalisation.
  use difficulty <- list.each(generator.difficulties)
  let name = generator.label(difficulty)

  assert generator.named(name) == Ok(difficulty)
  assert generator.named(string.lowercase(name)) == Ok(difficulty)
  assert generator.named(string.uppercase(name)) == Ok(difficulty)
}

pub fn nothing_else_is_a_difficulty_test() {
  assert generator.named("custom") == Error(Nil)
  assert generator.named("") == Error(Nil)
  assert generator.named("hardest") == Error(Nil)
}

pub fn difficulty_ceilings_ascend_test() {
  let ceilings = {
    use difficulty <- list.map(generator.difficulties)
    logic.rank(generator.hardest(difficulty))
  }

  assert ceilings == list.sort(ceilings, by: int.compare)
  assert list.unique(ceilings) == ceilings
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

  // Twice over: the cell it starts on may not be one that can be worked out
  // yet, and the first ask is answered by saying so.
  let hinted = started |> step(key.Char("H")) |> step(key.Char("H"))
  assert hinted.hints >= 1
  assert nothing_wrong(hinted)
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

/// Decode a keystroke, and say what was left unread behind it.
fn press_leaving(bytes: List(Int)) -> #(key.Key, List(Int)) {
  use remaining <- key.decode(bytes)
  case remaining {
    [] -> #(-1, [])
    [byte, ..rest] -> #(byte, rest)
  }
}

pub fn a_numbered_sequence_is_read_to_its_end_test() {
  // Home, End and the page keys mean nothing here, but a sequence has to be
  // read to the end whatever it means, or its tail arrives as a keystroke
  // the player never made.
  assert press_leaving([0x1b, 0x5b, 0x31, 0x7e]) == #(key.Unknown, [])
  assert press_leaving([0x1b, 0x5b, 0x36, 0x7e]) == #(key.Unknown, [])

  // Two digits, as the function keys use.
  assert press_leaving([0x1b, 0x5b, 0x31, 0x35, 0x7e]) == #(key.Unknown, [])

  // What follows a sequence is the next key, and nothing else.
  assert press_leaving([0x1b, 0x5b, 0x31, 0x7e, 0x35]) == #(key.Unknown, [0x35])
}

pub fn the_delete_key_decodes_test() {
  assert press([0x1b, 0x5b, 0x33, 0x7e]) == key.Erase
}

pub fn shifted_digits_decode_test() {
  // The number row with shift held. Both rows are read, so ! is a 1 either
  // way and @ is a 2 on the keyboard that has one there.
  assert press([0x21]) == key.Shifted(1)
  assert press([0x22]) == key.Shifted(2)
  assert press([0x40]) == key.Shifted(2)
  assert press([0x29]) == key.Shifted(9)

  // Where the two rows disagree the first of them wins: ( sits over 8 on one
  // keyboard and 9 on another, and there is no telling which is in front of
  // the player.
  assert press([0x28]) == key.Shifted(8)

  // A character over no digit at all is still itself.
  assert press([0x3d]) == key.Char("=")
}

pub fn letter_case_is_kept_test() {
  // `h` moves the cursor and `H` asks for a hint, so they must stay distinct.
  assert press([0x68]) == key.Char("h")
  assert press([0x48]) == key.Char("H")
  assert press([0x72]) == key.Char("r")
  assert press([0x52]) == key.Char("R")
  assert press([0x3f]) == key.Char("?")
}

pub fn ctrl_l_asks_for_a_redraw_test() {
  assert press([0x0c]) == key.Redraw

  // It is not mistaken for a printable character, which is what it was.
  assert press([0x0c]) != key.Char("\u{c}")
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

pub fn redo_walks_forward_again_test() {
  let played =
    fixture() |> step(key.Digit(4)) |> step(key.Right) |> step(key.Digit(7))
  let back = played |> step(key.Char("u")) |> step(key.Char("u"))

  assert board.value(back.board, 2) == 0
  assert board.value(back.board, 3) == 0

  let forward = back |> step(key.Char("r")) |> step(key.Char("r"))
  assert board.value(forward.board, 2) == 4
  assert board.value(forward.board, 3) == 7
  assert forward.board == played.board

  // And there is nothing beyond where it started.
  assert string.contains(step(forward, key.Char("r")).message, "Nothing")
}

pub fn there_is_nothing_to_redo_until_something_is_undone_test() {
  assert string.contains(step(fixture(), key.Char("r")).message, "Nothing")
}

pub fn writing_something_else_throws_the_way_forward_away_test() {
  // The board is somewhere else now, and what was undone was the way forward
  // from where it used to be.
  let elsewhere =
    fixture()
    |> step(key.Digit(4))
    |> step(key.Char("u"))
    |> step(key.Digit(1))

  assert string.contains(step(elsewhere, key.Char("r")).message, "Nothing")
  assert board.value(elsewhere.board, 2) == 1
}

pub fn undo_says_how_to_take_it_back_test() {
  let undone = fixture() |> step(key.Digit(4)) |> step(key.Char("u"))
  assert string.contains(undone.message, "press r")
    || string.contains(undone.message, "Press r")
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
  assert string.contains(checked.message, "1 digit is wrong")

  // Pressing it again does not turn checking back off. It cannot be.
  let again = step(checked, key.Char("c"))
  assert again.checking
  assert string.contains(again.message, "stays on")
}

// ---------------------------------------------------------------------------
// What checking costs
// ---------------------------------------------------------------------------

/// Write a wrong digit into each of `cells` in turn.
fn blunder(current: game.Game, cells: List(Int)) -> game.Game {
  use played, index <- list.fold(cells, current)
  let wrong = { game.answer(played, index) % 9 } + 1
  game.Game(..played, cursor: index) |> step(key.Digit(wrong))
}

/// The empty cells of the fixture, in reading order.
fn blanks() -> List(Int) {
  let start = fixture()
  list.filter(board.indices(), fn(index) {
    board.value(start.board, index) == 0
  })
}

pub fn checking_allows_three_wrong_digits_test() {
  let assert [a, b, c, ..] = blanks()
  let checked = step(fixture(), key.Char("c"))

  let once = blunder(checked, [a])
  assert once.mistakes == 1
  assert !game.is_finished(once)
  assert string.contains(once.message, "2 more")

  let twice = blunder(once, [b])
  assert twice.mistakes == 2
  assert string.contains(twice.message, "One more")

  let thrice = blunder(twice, [c])
  assert thrice.mistakes == game.mistake_limit
  assert !game.is_finished(thrice)
  assert string.contains(thrice.message, "next one forfeits")
}

pub fn a_fourth_wrong_digit_forfeits_the_puzzle_test() {
  let assert [a, b, c, d, ..] = blanks()

  let lost = blunder(step(fixture(), key.Char("c")), [a, b, c, d])

  assert lost.mistakes == game.mistake_limit + 1
  assert game.is_finished(lost)
  assert lost.ending == option.Some(game.Forfeited)

  // A forfeited puzzle takes no more digits, and says how to start again.
  let poked = game.Game(..lost, cursor: a) |> step(key.Erase)
  assert board.value(poked.board, a) == board.value(lost.board, a)
  assert string.contains(poked.message, "new puzzle")
}

pub fn wrong_digits_are_free_until_checking_is_asked_for_test() {
  let assert [a, b, c, d, ..] = blanks()

  let unchecked = blunder(fixture(), [a, b, c, d])
  assert unchecked.mistakes == 0
  assert !game.is_finished(unchecked)
  assert !string.contains(unchecked.message, "forfeit")
}

pub fn switching_checking_on_charges_for_what_it_finds_test() {
  let assert [a, b, c, ..] = blanks()

  // Free while the game was saying nothing about them; asking puts all three
  // on the tally at once, or they could be banked up and cashed in for one
  // keystroke's worth of answers.
  let checked = step(blunder(fixture(), [a, b, c]), key.Char("c"))

  assert checked.mistakes == 3
  assert string.contains(checked.message, "3 digits are wrong")
  assert string.contains(checked.message, "next one forfeits")

  // Spent to the last of it, but still playing.
  assert !game.is_finished(checked)
}

pub fn switching_checking_on_to_too_many_forfeits_test() {
  let assert [a, b, c, d, e, ..] = blanks()
  let lost = step(blunder(fixture(), [a, b, c, d, e]), key.Char("c"))

  // Five wrong digits is past the allowance, so asking ends it there.
  assert lost.mistakes == 5
  assert game.is_finished(lost)
  assert lost.ending == option.Some(game.Forfeited)
  assert list.any(visible_lines(lost), string.contains(_, "5 wrong digits"))
}

pub fn spent_to_the_last_the_next_wrong_digit_ends_it_test() {
  let assert [a, b, c, d, ..] = blanks()
  let spent = step(blunder(fixture(), [a, b, c]), key.Char("c"))

  // Putting the three right again costs nothing, though the tally stands.
  let mended = {
    use current, index <- list.fold([a, b, c], spent)
    game.Game(..current, cursor: index)
    |> step(key.Digit(game.answer(current, index)))
  }
  assert !game.is_finished(mended)
  assert mended.mistakes == 3

  // One more wrong digit written, and it is over.
  let lost = blunder(mended, [d])
  assert game.is_finished(lost)
  assert lost.ending == option.Some(game.Forfeited)
}

pub fn right_digits_cost_nothing_test() {
  let checked = step(fixture(), key.Char("c"))

  let played = {
    use current, index <- list.fold(list.take(blanks(), 5), checked)
    game.Game(..current, cursor: index)
    |> step(key.Digit(game.answer(current, index)))
  }

  assert played.mistakes == 0
  assert !game.is_finished(played)
}

pub fn writing_the_same_wrong_digit_again_costs_nothing_test() {
  let assert [a, ..] = blanks()
  let once = blunder(step(fixture(), key.Char("c")), [a])

  // The cell already holds it, so nothing has changed and nothing is owed.
  let again =
    game.Game(..once, cursor: a) |> step(key.Digit(board.value(once.board, a)))
  assert again.mistakes == 1
}

pub fn undo_takes_back_the_digit_but_not_the_mistake_test() {
  let assert [a, ..] = blanks()
  let once = blunder(step(fixture(), key.Char("c")), [a])
  let undone = step(once, key.Char("u"))

  assert board.value(undone.board, a) == 0
  assert undone.mistakes == 1
}

pub fn the_tally_shows_on_the_title_line_test() {
  let assert [a, ..] = blanks()
  let checked = step(fixture(), key.Char("c"))

  // It appears as soon as checking is on, before anything is spent.
  assert list.any(visible_lines(checked), string.contains(_, "checking 0/3"))

  let once = blunder(checked, [a])
  assert list.any(visible_lines(once), string.contains(_, "checking 1/3"))

  // Checking cannot be switched off, so it and the tally stay up.
  let again = step(once, key.Char("c"))
  assert again.checking
  assert list.any(visible_lines(again), string.contains(_, "checking 1/3"))

  // A game that has never checked says nothing about it.
  assert !list.any(visible_lines(fixture()), string.contains(_, "checking"))
}

pub fn forfeiting_says_so_test() {
  let assert [a, b, c, d, ..] = blanks()
  let lost = blunder(step(fixture(), key.Char("c")), [a, b, c, d])
  let lines = visible_lines(lost)

  assert list.any(lines, string.contains(_, "forfeited"))
  assert list.any(lines, string.contains(_, "n new puzzle"))
  // The panel has the last word; no tally reading four out of three.
  assert !list.any(lines, string.contains(_, "checking"))
  // The board is left standing, so the mistakes can be seen.
  assert list.any(lines, is_grid_row)
}

/// Nothing on the board disagrees with the answer.
fn nothing_wrong(current: game.Game) -> Bool {
  use index <- list.all(board.indices())
  case board.value(current.board, index) {
    0 -> True
    digit -> digit == game.answer(current, index)
  }
}

pub fn a_hint_takes_the_next_step_and_says_why_test() {
  let hinted = fixture() |> step(key.Char("H")) |> step(key.Char("H"))

  assert hinted.hints >= 1
  assert nothing_wrong(hinted)

  // It moved to what it is about and named it in words, rather than leaving
  // the player to work out which cell it meant.
  assert string.contains(hinted.message, board.name(hinted.cursor))
  assert string.ends_with(hinted.message, ".")
}

pub fn a_hint_answers_the_cell_you_are_on_test() {
  let start = fixture()

  // A cell that can be worked out, but not the one the reasoning would have
  // picked of its own accord.
  let assert Ok(elsewhere) = {
    use index <- list.find(board.indices())
    index != step(start, key.Char("H")).cursor
    && board.value(start.board, index) == 0
    && logic.settles(start.board.values, index) != Error(Nil)
  }

  let hinted = step(game.Game(..start, cursor: elsewhere), key.Char("H"))

  assert hinted.cursor == elsewhere
  assert board.value(hinted.board, elsewhere) == game.answer(start, elsewhere)
  assert string.contains(hinted.message, board.name(elsewhere))
}

/// A cell of the fixture that nothing settles yet.
fn stuck_cell() -> Int {
  let start = fixture()
  let assert Ok(stuck) = {
    use index <- list.find(board.indices())
    board.value(start.board, index) == 0
    && logic.settles(start.board.values, index) == Error(Nil)
  }
  stuck
}

pub fn a_hint_says_so_rather_than_wandering_off_test() {
  let stuck = stuck_cell()
  let waiting = step(game.Game(..fixture(), cursor: stuck), key.Char("H"))

  // It stays where the player is looking and says why it has nothing.
  assert waiting.cursor == stuck
  assert waiting.board == fixture().board
  assert string.contains(waiting.message, board.name(stuck))
  assert string.contains(waiting.message, "Press H again")

  // Saying so is not a hint, and is not counted as one.
  assert waiting.hints == 0
}

pub fn asking_twice_at_a_stuck_cell_looks_elsewhere_test() {
  let stuck = stuck_cell()
  let moved_on =
    game.Game(..fixture(), cursor: stuck)
    |> step(key.Char("H"))
    |> step(key.Char("H"))

  assert moved_on.cursor != stuck
  assert moved_on.hints == 1
  assert nothing_wrong(moved_on)
  assert string.contains(moved_on.message, board.name(moved_on.cursor))
}

pub fn anything_in_between_starts_the_asking_over_test() {
  let stuck = stuck_cell()

  // Moving away and back is a fresh question, not a second asking of the old
  // one, so it is answered the same way as the first.
  let again =
    game.Game(..fixture(), cursor: stuck)
    |> step(key.Char("H"))
    |> step(key.Right)
    |> step(key.Left)
    |> step(key.Char("H"))

  assert again.cursor == stuck
  assert again.hints == 0
  assert string.contains(again.message, "Press H again")
}

pub fn a_hint_goes_where_the_reasoning_is_test() {
  // Not where the cursor happens to be: the cell under it may not be the one
  // that can be worked out next, and a hint that cannot explain itself is
  // just the answer again.
  let on_a_clue = game.Game(..fixture(), cursor: 0)
  let hinted = step(on_a_clue, key.Char("H"))

  assert hinted.cursor != 0
  assert nothing_wrong(hinted)
  assert string.contains(hinted.message, board.name(hinted.cursor))
}

/// A game of one of the frozen fixtures, answer and all.
fn playing(text: String) -> game.Game {
  let assert Ok(answer) = solver.solve(grid(text))
    as "the fixtures are solvable"
  game.new(generator.Puzzle(
    board: board.from_grid(grid(text)),
    solution: answer,
    origin: generator.Handwritten,
  ))
}

/// A player who has pencilled every candidate into every empty cell.
fn fully_marked(current: game.Game) -> game.Game {
  let peers = board.peers_table()
  let grid = current.board.values

  let marked = {
    use marked, index <- list.fold(board.indices(), current.board)
    case board.value(marked, index) {
      0 -> {
        use marked, digit <- list.fold(
          board.candidates(grid, peers, index),
          marked,
        )
        board.toggle_mark(marked, index, digit)
      }
      _ -> marked
    }
  }

  game.Game(..current, board: marked)
}

/// How much is written in, and how much is pencilled in.
fn written_and_marked(current: game.Game) -> #(Int, Int) {
  let marks = {
    use total, index <- list.fold(board.indices(), 0)
    total + list.length(board.sorted_marks(current.board, index))
  }
  #(81 - board.empty_count(current.board), marks)
}

pub fn a_hint_rubs_out_the_marks_it_rules_out_test() {
  // Somewhere in this one the reasoning has to rule something out before it
  // can settle anything, and a player with marks has somewhere for that to
  // land. Take hints until it comes round.
  let start = fully_marked(playing(needs_naked_pair))

  let #(last, ruled_something_out) = {
    use #(current, seen), _ <- list.fold(board.span(1, 25), #(start, False))
    let hinted = step(current, key.Char("H"))
    let #(written, marked) = written_and_marked(current)
    let #(written_after, marked_after) = written_and_marked(hinted)

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
  let start = playing(needs_naked_pair)

  let #(last, moves) = {
    use #(current, moves), _ <- list.fold(board.span(1, 8), #(start, 0))
    let hinted = step(current, key.Char("H"))
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
  assert nothing_wrong(last)
}

pub fn a_hint_checks_itself_against_the_answer_test() {
  // A wrong digit can lead the reasoning somewhere the answer does not go,
  // so a hint never writes a digit without checking it first.
  let astray = step(fixture(), key.Digit(1))
  let hinted = step(astray, key.Char("H"))

  assert hinted.hints == 1
  use index <- list.each(board.indices())
  case index == 2 || board.value(hinted.board, index) == 0 {
    True -> Nil
    False -> {
      assert board.value(hinted.board, index) == game.answer(hinted, index)
    }
  }
}

pub fn revealing_finishes_the_puzzle_test() {
  let revealed = step(fixture(), key.Char("R"))

  assert revealed.ending == option.Some(game.Revealed)
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
  assert won.ending == option.Some(game.Solved)
  assert board.is_solved(won.board)
}

pub fn a_finished_puzzle_ignores_further_edits_test() {
  let revealed = step(fixture(), key.Char("R"))
  let poked = step(game.Game(..revealed, cursor: 2), key.Erase)
  assert board.value(poked.board, 2) == 4
}

pub fn the_editor_help_survives_a_newline_test() {
  let reading = edit(editor.new(), key.Char("?"))
  assert edit(reading, key.Unknown).show_help
}

pub fn help_opens_and_any_key_closes_it_test() {
  let opened = step(fixture(), key.Char("?"))
  assert opened.help == option.Some(game.Keys)

  assert step(opened, key.Char("?")).help == option.None
  assert step(opened, key.Down).help == option.None
  // Dismissing help does not also move the cursor.
  assert step(opened, key.Down).cursor == opened.cursor
}

pub fn the_help_pages_through_the_techniques_test() {
  let opened = step(fixture(), key.Char("?"))

  // Right off the keys is the first technique, and left off it is the last.
  let assert [_keys, first, ..] = game.pages()
  let assert Ok(last) = list.last(game.pages())

  assert step(opened, key.Right).help == option.Some(first)
  assert step(opened, key.Left).help == option.Some(last)

  // Paging through every page comes back round to where it started.
  let round = {
    use current, _ <- list.fold(game.pages(), opened)
    step(current, key.Right)
  }
  assert round.help == opened.help

  // A page for every technique, two of keys, and one on starting up.
  assert list.length(game.pages()) == list.length(logic.techniques) + 3
}

pub fn paging_the_help_does_not_reach_the_board_test() {
  // The arrows turn pages while the help is up, so there is no reading about
  // a technique and moving the cursor by accident.
  let opened = step(fixture(), key.Char("?"))
  let paged = step(step(opened, key.Right), key.Left)

  assert paged.cursor == opened.cursor
  assert paged.board == opened.board

  // Quitting still works from the help, though.
  assert game.update(opened, key.Char("q")) == game.Exit
}

pub fn giving_up_a_puzzle_under_way_is_asked_for_twice_test() {
  // n is next to m on the keyboard, and giving up throws away the saved game
  // as well as the one on screen.
  let played = step(fixture(), key.Digit(4))
  let asked = step(played, key.Char("n"))

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
    fixture()
    |> step(key.Digit(4))
    |> step(key.Char("n"))
    |> step(key.Unknown)

  assert game.update(asked, key.Char("n")) == game.Restart

  let reading = step(fixture(), key.Char("?"))
  assert step(reading, key.Unknown).help == reading.help

  // And it leaves what a hint is pointing at where it was.
  let hinted = fixture() |> step(key.Char("H")) |> step(key.Char("H"))
  assert step(hinted, key.Unknown).showing == hinted.showing
}

pub fn an_offer_to_give_up_does_not_keep_test() {
  let asked =
    fixture()
    |> step(key.Digit(4))
    |> step(key.Char("n"))
    |> step(key.Right)

  // A fresh question, answered the same way as the first.
  assert string.contains(step(asked, key.Char("n")).message, "Press n again")
}

pub fn a_puzzle_with_nothing_in_it_is_given_up_at_once_test() {
  // Nothing has been done to it, so there is nothing to lose by asking.
  assert game.update(fixture(), key.Char("n")) == game.Restart

  // And a puzzle already over is over.
  let done = step(fixture(), key.Char("R"))
  assert game.update(done, key.Char("n")) == game.Restart
}

pub fn quit_and_restart_leave_the_loop_test() {
  assert game.update(fixture(), key.Char("q")) == game.Exit
  assert game.update(fixture(), key.Quit) == game.Exit
  assert game.update(fixture(), key.Char("n")) == game.Restart
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
  assert game.elapsed_ms(fixture()) >= 0
}

pub fn the_clock_waits_while_the_help_is_up_test() {
  let start = fixture()
  let reading = step(start, key.Char("?"))
  assert reading.resting_since != option.None

  // Closing the help gives back the time spent reading it, by moving the
  // start of the game along.
  let back = step(reading, key.Down)
  assert back.resting_since == option.None
  assert back.started_ms >= start.started_ms
  assert game.elapsed_ms(back) <= game.elapsed_ms(start)
}

pub fn a_finished_time_does_not_move_test() {
  // The clock has stopped, so reading the help afterwards cannot change what
  // it says.
  let done = step(fixture(), key.Char("R"))
  let after = done |> step(key.Char("?")) |> step(key.Down)

  assert after.started_ms == done.started_ms
  assert game.elapsed_ms(after) == game.elapsed_ms(done)
}

// ---------------------------------------------------------------------------
// Filling the candidates in
// ---------------------------------------------------------------------------

pub fn f_pencils_the_candidates_into_every_bare_cell_test() {
  let filled = step(fixture(), key.Char("f"))
  let peers = board.peers_table()

  use index <- list.each(board.indices())
  case board.value(filled.board, index) {
    // What is pencilled in is exactly what the grid still allows.
    0 -> {
      assert board.sorted_marks(filled.board, index)
        == board.candidates(fixture().board.values, peers, index)
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
    fixture()
    |> step(key.Char("m"))
    |> step(key.Digit(4))
    |> step(key.Char("m"))
  let cursor = thought_about.cursor

  let filled = step(thought_about, key.Char("f"))

  assert board.sorted_marks(filled.board, cursor) == [4]
  assert string.contains(filled.message, "left as")
}

pub fn filling_twice_over_offers_to_start_the_marks_again_test() {
  let filled = fixture() |> step(key.Char("f"))
  let again = step(filled, key.Char("f"))

  // Nothing bare left, so nothing done — but an offer made.
  assert string.contains(again.message, "already")
  assert string.contains(again.message, "Press f again")
  assert again.board == filled.board
}

/// Marks made by hand are the one thing filling will not touch, so a mark
/// made wrongly needs a way out. This is it, and it takes asking twice.
pub fn asking_a_third_time_marks_every_cell_afresh_test() {
  let peers = board.peers_table()
  let start = fixture()
  let assert Ok(empty) =
    list.find(board.indices(), fn(index) {
      board.value(start.board, index) == 0
    })

  // A cell marked wrongly by hand: one candidate, and the wrong one.
  let wrong = { game.answer(start, empty) % 9 } + 1
  let misled =
    game.Game(..start, cursor: empty)
    |> step(key.Char("m"))
    |> step(key.Digit(wrong))
    |> step(key.Char("m"))

  let afresh =
    misled
    |> step(key.Char("f"))
    |> step(key.Char("f"))
    |> step(key.Char("f"))

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
    fixture()
    |> step(key.Char("f"))
    |> step(key.Char("f"))
    |> step(key.Right)
    |> step(key.Char("f"))

  assert string.contains(held.message, "Press f again")
}

pub fn filling_is_one_undo_away_test() {
  let filled = step(fixture(), key.Char("f"))
  let undone = step(filled, key.Char("u"))

  assert undone.board == fixture().board
}

/// Marks that are pencilled in are what the reasoning then works from, which
/// is what lets a step that only rules candidates out lead to the next one.
pub fn the_hints_reason_from_the_marks_you_have_test() {
  // A grid whose reasoning needs an elimination somewhere along the way.
  let filled = step(playing(needs_naked_pair), key.Char("f"))

  // Take hints until one of them rules candidates out rather than settling a
  // digit: without marks to rub out, no such hint is ever offered.
  let #(_, ruled_out) = {
    use #(current, seen), _ <- list.fold(board.span(1, 30), #(filled, False))
    let hinted = step(current, key.Char("H"))
    #(
      hinted,
      seen
        || board.empty_count(hinted.board) == board.empty_count(current.board),
    )
  }

  assert ruled_out
}

// ---------------------------------------------------------------------------
// Marking during play
// ---------------------------------------------------------------------------

pub fn shift_and_a_digit_marks_either_way_round_test() {
  // Writing, and pencilling one in without leaving.
  let marked = step(fixture(), key.Shifted(4))
  assert board.sorted_marks(marked.board, 2) == [4]
  assert board.value(marked.board, 2) == 0
  assert !marked.marking

  // The same key rubs it out again, and does so while marking too.
  assert board.sorted_marks(step(marked, key.Shifted(4)).board, 2) == []
  let while_marking = step(step(marked, key.Char("m")), key.Shifted(4))
  assert board.sorted_marks(while_marking.board, 2) == []
  assert while_marking.marking
}

pub fn shift_and_a_digit_types_a_clue_in_test() {
  // In the editor there is nothing to distinguish them, so the shifted row
  // types digits like the unshifted one.
  let typed = editor.new() |> edit(key.Shifted(5)) |> edit(key.Digit(3))

  assert editor.value(typed, 0) == 5
  assert editor.value(typed, 1) == 3
}

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

/// Mark a 4 in A3 (where the answer is a 4) and in A9, which can see it.
fn marked_around_a3() -> game.Game {
  let marked =
    game.Game(..fixture(), cursor: board.at(0, 8))
    |> step(key.Char("m"))
    |> step(key.Digit(4))
    |> step(key.Char("m"))

  game.Game(..marked, cursor: 2)
  |> step(key.Char("m"))
  |> step(key.Digit(4))
  |> step(key.Char("m"))
}

pub fn a_wrong_digit_while_checking_leaves_marks_alone_test() {
  // A3 is a 4 in the solution, so a 1 there is wrong and checking says so.
  let played = marked_around_a3() |> step(key.Char("c")) |> step(key.Digit(1))

  assert board.value(played.board, 2) == 1
  assert game.is_wrong(played, 2)

  // The reasoning that led here survives, on the cell and around it.
  assert board.sorted_marks(played.board, 2) == [4]
  assert board.sorted_marks(played.board, board.at(0, 8)) == [4]
}

pub fn a_right_digit_while_checking_still_tidies_up_test() {
  let played = marked_around_a3() |> step(key.Char("c")) |> step(key.Digit(4))

  assert board.sorted_marks(played.board, 2) == []
  assert board.sorted_marks(played.board, board.at(0, 8)) == []
}

pub fn a_wrong_digit_tidies_up_as_usual_when_not_checking_test() {
  // With checking off the game is saying nothing about the digit, so marks
  // surviving would be saying it for them.
  let played = marked_around_a3() |> step(key.Digit(1))

  assert !played.checking
  assert board.sorted_marks(played.board, 2) == []
  // A9's 4 is only retracted by a 4; a 1 leaves it be either way.
  assert board.sorted_marks(played.board, board.at(0, 8)) == [4]
}

pub fn correcting_a_wrong_digit_tidies_up_after_it_test() {
  let corrected =
    marked_around_a3()
    |> step(key.Char("c"))
    |> step(key.Digit(1))
    |> step(key.Digit(4))

  assert !game.is_wrong(corrected, 2)
  assert board.sorted_marks(corrected.board, 2) == []
  assert board.sorted_marks(corrected.board, board.at(0, 8)) == []
}

pub fn writing_a_digit_leaves_every_mark_alone_test() {
  let marked =
    board.from_grid(grid(puzzle_text))
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
    fixture()
    |> step(key.Char("m"))
    |> step(key.Digit(1))
    |> step(key.Digit(4))
    |> step(key.Char("m"))

  assert board.sorted_marks(step(marked, key.Char("R")).board, 2) == []
}

pub fn a_hint_tidies_up_the_marks_where_it_settles_test() {
  // A cell the reasoning can settle, marked up before the hint settles it.
  let assert Ok(settles) = {
    use index <- list.find(board.indices())
    board.value(fixture().board, index) == 0
    && logic.settles(fixture().board.values, index) != Error(Nil)
  }
  // Pencilled with the digit that belongs there. A mark of the wrong digit
  // would make the cell look like a naked single for a digit that is not the
  // answer, and a hint checks before it writes.
  let digit = game.answer(fixture(), settles)
  let marked =
    game.Game(..fixture(), cursor: settles)
    |> step(key.Char("m"))
    |> step(key.Digit(digit))
    |> step(key.Char("m"))

  assert board.sorted_marks(marked.board, settles) == [digit]
  assert board.sorted_marks(step(marked, key.Char("H")).board, settles) == []
}

pub fn a_hint_will_not_write_what_your_marks_say_wrongly_test() {
  // One wrong candidate pencilled in makes the cell look settled, and settled
  // wrongly. The hint declines rather than writing it.
  let assert Ok(settles) = {
    use index <- list.find(board.indices())
    board.value(fixture().board, index) == 0
    && logic.settles(fixture().board.values, index) != Error(Nil)
  }

  let wrong = { game.answer(fixture(), settles) % 9 } + 1
  let misled =
    game.Game(..fixture(), cursor: settles)
    |> step(key.Char("m"))
    |> step(key.Digit(wrong))
    |> step(key.Char("m"))
    |> step(key.Char("H"))

  assert board.value(misled.board, settles) == 0
  assert string.contains(misled.message, "Press H again")
}

// ---------------------------------------------------------------------------
// Putting a game down and picking it up
// ---------------------------------------------------------------------------

pub fn a_game_survives_being_written_out_and_read_back_test() {
  let played =
    fixture()
    |> step(key.Digit(4))
    |> step(key.Char("f"))
    |> step(key.Char("c"))
    |> step(key.Char("H"))
    |> step(key.Right)

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
  let long = game.Game(..fixture(), started_ms: term.now_ms() - 90_000)
  let assert Ok(again) = store.decode(store.encode(long))

  assert game.elapsed_ms(again) >= 89_000
  assert game.elapsed_ms(again) <= 91_000
}

pub fn what_a_game_cost_survives_too_test() {
  let assert [a, b, ..] = {
    use index <- list.filter(board.indices())
    board.value(fixture().board, index) == 0
  }

  let costly = step(fixture(), key.Char("c")) |> blunder([a, b])
  let assert Ok(again) = store.decode(store.encode(costly))

  assert again.mistakes == 2
  assert again.checking
}

pub fn a_custom_puzzle_is_saved_as_one_test() {
  let assert editor.Ready(puzzle) =
    editor.update(typed(puzzle_text), key.Char("p"))

  let assert Ok(again) = store.decode(store.encode(game.new(puzzle)))
  assert again.puzzle.origin == generator.Handwritten
}

pub fn a_file_that_is_not_a_saved_game_is_refused_test() {
  assert store.decode("") == Error(Nil)
  assert store.decode("hello") == Error(Nil)

  // A file from a version this cannot read.
  let written = store.encode(fixture())
  assert store.decode(string.replace(written, "sudoku 1", "sudoku 2"))
    == Error(Nil)
}

pub fn a_saved_game_that_does_not_hold_together_is_refused_test() {
  let written = store.encode(fixture())

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

// ---------------------------------------------------------------------------
// The record books
// ---------------------------------------------------------------------------

/// The fixture, solved by writing in every answer.
fn solved(current: game.Game) -> game.Game {
  use current, index <- list.fold(board.indices(), current)
  case board.value(current.board, index) {
    0 ->
      game.Game(..current, cursor: index)
      |> step(key.Digit(game.answer(current, index)))
    _ -> current
  }
}

pub fn an_unaided_solve_is_timed_test() {
  let won = solved(fixture())

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
  let checked = solved(step(fixture(), key.Char("c")))
  assert !game.unaided(checked)
  assert store.judge(checked, dict.new()) == game.Aided

  // A hint is help too, however small.
  let hinted = solved(step(step(fixture(), key.Char("H")), key.Char("H")))
  assert hinted.hints >= 1
  assert store.judge(hinted, dict.new()) == game.Aided
}

pub fn filling_the_candidates_in_is_not_help_test() {
  // It works out nothing the player could not have worked out with a pencil.
  let filled = solved(step(fixture(), key.Char("f")))

  assert game.unaided(filled)
  assert store.judge(filled, dict.new()) == game.BestYet
}

pub fn a_game_not_won_is_not_timed_test() {
  let revealed = step(fixture(), key.Char("R"))
  assert store.judge(revealed, dict.new()) == game.Untimed

  // And a puzzle typed in has no difficulty to file a time under.
  let assert editor.Ready(puzzle) =
    editor.update(typed(puzzle_text), key.Char("p"))
  assert store.judge(solved(game.new(puzzle)), dict.new()) == game.Untimed
}

pub fn the_finished_panel_says_what_the_books_made_of_it_test() {
  let won = solved(fixture())

  let said = fn(verdict) {
    visible_lines(game.Game(..won, verdict: option.Some(verdict)))
  }

  assert list.any(said(game.BestYet), string.contains(_, "Your best yet"))
  assert list.any(said(game.Behind(125_000)), string.contains(_, "02:05"))
  assert list.any(said(game.Aided), string.contains(_, "Not recorded"))

  // An untimed game says nothing about records at all.
  assert !list.any(said(game.Untimed), string.contains(_, "recorded"))
  assert !list.any(said(game.Untimed), string.contains(_, "best"))
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
  // The board's keys on the first page, and what can be asked for on the
  // second: too many for one page, once there were enough of them.
  let first = visible_lines(step(fixture(), key.Char("?")))
  assert list.any(first, string.contains(_, "write a digit"))
  assert list.any(first, string.contains(_, "pencil the candidates"))

  let second = visible_lines(step(step(fixture(), key.Char("?")), key.Right))
  assert list.any(second, string.contains(_, "reveal the whole solution"))
  assert list.any(second, string.contains(_, "draw the screen again"))

  // Help takes the screen over rather than sharing it with the board.
  assert !list.any(first, is_grid_row)
  assert !list.any(second, is_grid_row)
}

/// The status line is two rows whatever it has to say, so the board above it
/// never shifts by a row between one message and the next.
pub fn the_message_is_always_two_rows_test() {
  let height = fn(current: game.Game) { list.length(visible_lines(current)) }

  let quiet = game.Game(..fixture(), message: "")
  let hinted = step(fixture(), key.Char("H"))
  let undone = step(fixture(), key.Char("u"))

  assert height(quiet) == height(hinted)
  assert height(undone) == height(hinted)

  // The hint really does fill both rows, and the second says why.
  let assert [what, why] = string.split(hinted.message, "\n")
  assert what != ""
  assert why != ""
}

/// The technique pages are drawn by hand, so the guard that they fit has to
/// be a test rather than the eye that drew them.
pub fn every_help_page_fits_the_screen_test() {
  use page <- list.each(game.pages())
  let showing = game.Game(..fixture(), help: option.Some(page))
  let lines = visible_lines(showing)

  assert list.length(lines) <= 24
  use line <- list.each(lines)
  assert string.length(line) <= 78
}

pub fn the_help_says_how_to_start_the_game_test() {
  let showing = game.Game(..fixture(), help: option.Some(game.Starting))
  let lines = visible_lines(showing)

  // Every way in that the command line takes, and what a puzzle looks like.
  use #(invocation, _) <- list.each(help.invocations)
  assert list.any(lines, string.contains(_, invocation))
  assert list.any(lines, string.contains(_, "81 characters"))
}

pub fn the_help_and_the_command_line_say_the_same_thing_test() {
  // One list behind both, so that the page and the complaint cannot drift.
  let complaint = help.usage()

  use #(invocation, meaning) <- list.each(help.invocations)
  assert string.contains(complaint, invocation)
  assert string.contains(complaint, meaning)
}

pub fn every_technique_has_a_page_that_names_it_test() {
  use technique <- list.each(logic.techniques)
  let showing = game.Game(..fixture(), help: option.Some(game.About(technique)))
  let lines = visible_lines(showing)

  // The page is titled with the technique, and says which page it is.
  assert list.any(lines, fn(line) {
    string.contains(
      string.lowercase(line),
      string.lowercase(logic.label(technique)),
    )
  })
  assert list.any(lines, string.contains(_, "page "))

  // And it draws something, rather than only describing it.
  assert list.any(lines, string.contains(_, "\u{2500}"))
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

/// The wash behind the cells a hint is arguing from. Checking for it means
/// reaching for the escape itself: a background leaves no mark on the text.
const hint_wash = "48;5;22;"

pub fn the_board_points_at_what_a_hint_rests_on_test() {
  let assert Ok(row) = list.first(board.units())
  let shown =
    logic.Step(
      technique: logic.HiddenSingle,
      move: logic.Settle(2, 4),
      evidence: [2],
      about: [4],
      unit: row,
    )

  assert string.contains(
    render.frame(game.Game(..fixture(), showing: option.Some(shown))),
    hint_wash,
  )

  // And nothing is lit up when nothing has been hinted.
  assert !string.contains(render.frame(fixture()), hint_wash)
}

pub fn what_a_hint_points_at_goes_out_on_the_next_keystroke_test() {
  // Twice: the cell it starts on may not be one that can be worked out yet,
  // and being told so is not a hint.
  let hinted = fixture() |> step(key.Char("H")) |> step(key.Char("H"))
  assert hinted.showing != option.None

  let moved = step(hinted, key.Down)
  assert moved.showing == option.None
  assert !string.contains(render.frame(moved), hint_wash)
}

pub fn the_help_opens_at_what_the_last_hint_was_about_test() {
  let hinted = fixture() |> step(key.Char("H")) |> step(key.Char("H"))
  let assert option.Some(shown) = hinted.showing

  assert step(hinted, key.Char("?")).help
    == option.Some(game.About(shown.technique))

  // With no hint behind it, the help opens where it always did.
  assert step(fixture(), key.Char("?")).help == option.Some(game.Keys)
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
