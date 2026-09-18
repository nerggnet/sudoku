//// Looking for somewhere a digit can still go.

import gleam/list
import gleam/set
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/key
import sudoku/palette
import sudoku/render
import sudoku/term

/// A game looking for sevens.
fn looking_for(digit: Int) -> game.Game {
  helper.fixture()
  |> helper.step(key.Char("S"))
  |> helper.step(key.Digit(digit))
}

pub fn asking_for_a_scan_asks_which_digit_test() {
  let asked = helper.step(helper.fixture(), key.Char("S"))

  assert asked.asking == game.WhichToLookFor
  assert asked.scan == game.NotScanning
  assert string.contains(asked.message, "which digit")
  assert string.contains(asked.message, "1 to 9")

  // Nothing is shaded yet: no digit has been named.
  assert !string.contains(render.frame(asked), palette.scan_wash())
}

pub fn a_digit_after_s_says_what_to_look_for_test() {
  let looking = looking_for(7)
  let room = board.could_take(looking.board, 7)

  assert looking.scan == game.ScanningFor(7)
  assert string.contains(looking.message, "a 7 can go")
  assert string.contains(looking.message, helper.count_said(list.length(room)))
}

pub fn the_board_shades_exactly_the_cells_that_could_take_it_test() {
  let looking = looking_for(7)
  let room = set.from_list(board.could_take(looking.board, 7))

  // The pointer stands in for the wash where there is no colour, and it goes
  // in both grids, so the marker turns up twice for every cell.
  let plain = helper.without_colour(fn() { render.frame(looking) })
  assert helper.occurrences(plain, palette.could_go) == 2 * set.size(room)

  // And every one of them is a cell that could really take a 7.
  use index <- list.each(board.indices())
  let shaded =
    board.value(looking.board, index) == 0 && could_take(looking, index)
  assert set.contains(room, index) == shaded
}

fn could_take(current: game.Game, index: Int) -> Bool {
  list.contains(board.could_take(current.board, 7), index)
}

pub fn a_scan_reads_the_grid_and_not_the_marks_test() {
  // A 7 pencilled out of a cell by hand, wrongly or otherwise, is the
  // player's reasoning. Where a 7 can go is a fact, and stays one.
  let assert [first, ..] = board.could_take(helper.fixture().board, 7)
  let marked =
    game.Game(..helper.fixture(), cursor: first)
    |> helper.with_marks([1, 2, 3])

  let looking =
    marked |> helper.step(key.Char("S")) |> helper.step(key.Digit(7))

  assert list.contains(board.could_take(looking.board, 7), first)
  assert string.contains(render.frame(looking), palette.scan_wash())
}

pub fn a_scan_puts_the_cursor_s_own_row_and_column_away_test() {
  // Nine shaded cells and three shaded units at once is a mess, and the scan
  // is the thing that was asked for.
  assert string.contains(render.frame(helper.fixture()), palette.peer_wash())
  assert !string.contains(render.frame(looking_for(7)), palette.peer_wash())
}

pub fn the_title_says_what_is_being_looked_for_test() {
  assert list.any(helper.visible_lines(looking_for(7)), string.contains(
    _,
    "looking for 7",
  ))
}

pub fn asking_again_stops_looking_test() {
  let stopped = helper.step(looking_for(7), key.Char("S"))

  assert stopped.scan == game.NotScanning
  assert !string.contains(render.frame(stopped), palette.scan_wash())
}

pub fn a_scan_asked_for_and_not_answered_lapses_test() {
  // Anything but a digit means the player has gone back to playing, and that
  // keystroke does what it always does rather than being swallowed.
  let moved =
    helper.fixture() |> helper.step(key.Char("S")) |> helper.step(key.Down)

  assert moved.asking == game.NotAsking
  assert moved.scan == game.NotScanning
  assert moved.cursor != helper.fixture().cursor
}

pub fn asking_and_asking_again_takes_the_question_back_test() {
  // S while it is still waiting to hear which digit, which is a player who
  // has thought better of it rather than one asking twice.
  let forgotten =
    helper.fixture() |> helper.step(key.Char("S")) |> helper.step(key.Char("S"))

  assert forgotten.asking == game.NotAsking
  assert forgotten.scan == game.NotScanning
  assert forgotten.message == ""
}

pub fn the_two_questions_do_not_overlap_test() {
  // M while S is waiting puts S's question away and asks its own: a digit
  // can only answer one of them.
  let pencilling =
    helper.fixture() |> helper.step(key.Char("S")) |> helper.step(key.Char("M"))

  assert pencilling.asking == game.WhichToPencil
  assert pencilling.scan == game.NotScanning

  let marked = helper.step(pencilling, key.Digit(4))
  assert board.sorted_marks(marked.board, marked.cursor) == [4]
  assert marked.scan == game.NotScanning
}

pub fn a_digit_written_while_looking_is_still_written_test() {
  // Only the digit straight after S is a choice of digit. A scan is a way of
  // looking at the board, not a mode to be in.
  let written = helper.step(looking_for(7), key.Digit(4))

  assert board.value(written.board, written.cursor) == 4
  assert written.scan == game.ScanningFor(7)
}

pub fn looking_costs_nothing_test() {
  // What a cell can take is there to be read off its row, its column and its
  // box, the same as pencilling the candidates in. So it is not aid.
  let looking = looking_for(7)

  assert game.unaided(looking)
  assert looking.hints == 0
  assert !looking.checking
}

pub fn a_digit_with_nowhere_left_to_go_says_so_test() {
  // Every seven written in, and the puzzle still unfinished — a game that is
  // over answers every key with how to start another one.
  let placed = {
    use current, index <- list.fold(board.indices(), helper.fixture())
    case game.answer(current, index) == 7 {
      False -> current
      True -> game.Game(..current, cursor: index) |> helper.step(key.Digit(7))
    }
  }

  let looking =
    placed |> helper.step(key.Char("S")) |> helper.step(key.Digit(7))

  assert !game.is_finished(looking)
  assert board.could_take(looking.board, 7) == []
  assert string.contains(looking.message, "already placed")
}

pub fn the_cell_under_the_cursor_says_whether_it_could_take_it_test() {
  // The cursor's colour is spoken for by the cursor, so the one cell the
  // player has gone to look at was the one cell the scan could not answer
  // about. It gets a mark in the column instead, in colour as well as plain.
  let looking = looking_for(7)
  let assert [candidate, ..] = board.could_take(looking.board, 7)
  let room = list.length(board.could_take(looking.board, 7))

  let on_it = game.Game(..looking, cursor: candidate)
  let plain = helper.without_colour(fn() { render.frame(on_it) })

  // Every cell that could take a 7, the cursor's own included.
  assert helper.occurrences(plain, palette.could_go) == 2 * room
  assert helper.occurrences(render.frame(on_it), palette.could_go) == 2

  // And nothing is marked when the cursor is somewhere a 7 cannot go.
  let assert Ok(elsewhere) =
    list.find(board.indices(), fn(index) {
      !list.contains(board.could_take(looking.board, 7), index)
    })
  let away = game.Game(..looking, cursor: elsewhere)
  assert helper.occurrences(render.frame(away), palette.could_go) == 0
}

/// What a scan looks like on each of the three terminals.
///
/// The washes are 256-colour greys, so a terminal with sixteen draws them as
/// nothing at all unless it is told to do something else. This is the thing
/// that used to go quietly missing: colour enough to look coloured, and no
/// shading where the shading was the answer.
pub fn a_scan_is_marked_out_on_every_terminal_test() {
  let looking = looking_for(7)

  // With the 256, the wash says it and the column in front stays a space.
  let full = helper.with_colours(term.Full, fn() { render.frame(looking) })
  assert string.contains(full, "48;5;17")
  assert !string.contains(full, palette.could_go)

  // With sixteen, the one grey says a cell is marked out and the column in
  // front says which kind of marking it is.
  let basic = helper.with_colours(term.Basic, fn() { render.frame(looking) })
  assert string.contains(basic, "100")
  assert !string.contains(basic, "48;5;")
  assert string.contains(basic, palette.could_go)

  // With none, the column carries it alone.
  let plain = helper.with_colours(term.Plain, fn() { render.frame(looking) })
  assert !string.contains(plain, "48;5;")
  assert string.contains(plain, palette.could_go)
}

/// However little colour there is, a cell a digit could go in is told apart
/// from one it could not. That is the whole of what a scan is for.
pub fn a_scan_says_as_much_on_sixteen_colours_as_on_256_test() {
  let looking = looking_for(7)
  let room = board.could_take(looking.board, 7)

  use colours <- list.each([term.Full, term.Basic, term.Plain])
  let drawn = helper.with_colours(colours, fn() { render.frame(looking) })

  // Something marks them out, whatever it is.
  assert room != []
  assert string.contains(drawn, "100")
    || string.contains(drawn, "48;5;17")
    || string.contains(drawn, palette.could_go)
}
