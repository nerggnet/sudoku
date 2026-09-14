//// The grid itself: its geometry, what goes on it, and what clashes.

import gleam/dict
import gleam/list
import gleam/set
import gleam/string
import helper
import sudoku/board

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

pub fn parse_ignores_layout_test() {
  let parsed = helper.grid(helper.puzzle_text)
  assert dict.get(parsed, 0) == Ok(5)
  assert dict.get(parsed, 2) == Ok(0)
  assert dict.get(parsed, 75) == Ok(0)
  assert dict.get(parsed, 80) == Ok(9)
}

pub fn parse_round_trips_test() {
  let text = board.to_string(helper.grid(helper.solution_text))
  assert string.length(text) == 81
  assert board.to_string(helper.grid(text)) == text
}

pub fn parse_rejects_the_wrong_number_of_cells_test() {
  assert board.parse("123") == Error(Nil)
  assert board.parse(helper.solution_text <> "5") == Error(Nil)
}

pub fn candidates_exclude_peers_test() {
  let peers = board.peers_table()
  let start = helper.grid(helper.puzzle_text)

  // A1 holds a 5, and the empty cell A3 sees it along with 3, 7, 6, 9 and 8.
  assert board.candidates(start, peers, board.at(0, 2)) == [1, 2, 4]
}

pub fn a_solved_grid_has_no_conflicts_test() {
  let solved = board.from_grid(helper.grid(helper.solution_text))
  assert set.is_empty(board.conflicts(solved))
  assert board.is_solved(solved)
}

pub fn duplicates_in_a_unit_are_conflicts_test() {
  // Two 5s in the top row.
  let clashing =
    board.from_grid(helper.grid(helper.solution_text))
    |> fn(solved) {
      board.Board(..solved, values: dict.insert(solved.values, 1, 5))
    }

  let clashes = board.conflicts(clashing)
  assert set.contains(clashes, 0)
  assert set.contains(clashes, 1)
  assert !board.is_solved(clashing)
}

pub fn an_incomplete_grid_is_not_solved_test() {
  assert !board.is_solved(board.from_grid(helper.grid(helper.puzzle_text)))
}

pub fn givens_cannot_be_edited_test() {
  let start = board.from_grid(helper.grid(helper.puzzle_text))

  assert board.is_given(start, 0)
  assert board.value(board.place(start, 0, 9), 0) == 5
  assert board.value(board.erase(start, 0), 0) == 5
}

pub fn blank_cells_can_be_written_and_cleared_test() {
  let start = board.from_grid(helper.grid(helper.puzzle_text))
  let empty_before = board.empty_count(start)

  let filled = board.place(start, 2, 4)
  assert board.value(filled, 2) == 4
  assert board.empty_count(filled) == empty_before - 1

  assert board.value(board.erase(filled, 2), 2) == 0
  assert board.empty_count(board.erase(filled, 2)) == empty_before
}

pub fn cells_start_unmarked_test() {
  let start = board.from_grid(helper.grid(helper.puzzle_text))
  assert set.is_empty(board.marks_at(start, 2))
  assert board.sorted_marks(start, 2) == []
}

pub fn marks_toggle_on_and_off_test() {
  let start = board.from_grid(helper.grid(helper.puzzle_text))

  let marked = board.toggle_mark(start, 2, 4)
  assert board.sorted_marks(marked, 2) == [4]

  let more = marked |> board.toggle_mark(2, 1) |> board.toggle_mark(2, 9)
  assert board.sorted_marks(more, 2) == [1, 4, 9]

  // Marking a digit that is already there rubs it out again.
  assert board.sorted_marks(board.toggle_mark(more, 2, 4), 2) == [1, 9]
}

pub fn marks_do_not_count_as_digits_test() {
  let start = board.from_grid(helper.grid(helper.puzzle_text))
  let marked = board.toggle_mark(start, 2, 4)

  assert board.value(marked, 2) == 0
  assert board.empty_count(marked) == board.empty_count(start)
  assert set.is_empty(board.conflicts(marked))
}

pub fn clues_cannot_be_marked_test() {
  let start = board.from_grid(helper.grid(helper.puzzle_text))
  assert board.sorted_marks(board.toggle_mark(start, 0, 4), 0) == []
}

pub fn marks_can_be_cleared_test() {
  let marked =
    board.from_grid(helper.grid(helper.puzzle_text))
    |> board.toggle_mark(2, 1)
    |> board.toggle_mark(2, 4)

  assert board.sorted_marks(board.clear_marks(marked, 2), 2) == []
}

pub fn writing_a_digit_clears_that_cell_s_marks_test() {
  let marked =
    board.from_grid(helper.grid(helper.puzzle_text))
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
      board.from_grid(helper.grid(helper.puzzle_text)),
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
