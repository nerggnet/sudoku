//// Drawing the screen, and what it says.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import helper
import sudoku/board
import sudoku/game
import sudoku/generator
import sudoku/help
import sudoku/key
import sudoku/logic
import sudoku/palette
import sudoku/render

pub fn escape_stripping_leaves_the_text_test() {
  assert helper.plain("\u{1b}[1;95mS U D O K U\u{1b}[0m") == "S U D O K U"
  // `H` and `J` end sequences just as `m` does, and text can contain an `m`.
  assert helper.plain("\u{1b}[H\u{1b}[Jtime\u{1b}[0m") == "time"
}

pub fn the_frame_draws_a_grid_test() {
  let lines = helper.visible_lines(helper.fixture())

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
  let lines = helper.visible_lines(helper.fixture())
  let assert Ok(caption) =
    list.first(list.filter(lines, string.contains(_, "board")))

  // Each caption sits over the left edge of the grid it names.
  assert string.starts_with(caption, "   board")
  assert string.slice(caption, 1 + helper.grid_columns + 4 + 2, 5) == "marks"
}

pub fn all_nine_rows_are_drawn_test() {
  let rows =
    helper.visible_lines(helper.fixture()) |> list.filter(helper.is_grid_row)
  assert list.length(rows) == 9

  // Every row is drawn twice over, once in each grid, to the same shape.
  use row <- list.each(rows)
  assert string.length(helper.board_half(row)) == helper.grid_columns
  assert string.length(helper.marks_half(row)) == helper.grid_columns
  assert string.starts_with(helper.marks_half(row), string.slice(row, 1, 4))
}

pub fn grid_lines_all_have_the_same_width_test() {
  let widths =
    helper.visible_lines(helper.fixture())
    |> list.filter(fn(line) {
      helper.is_grid_row(line) || string.contains(line, "─")
    })
    |> list.map(string.length)
    |> list.unique

  assert widths == [helper.frame_width]
}

pub fn the_column_ruler_lines_up_with_the_cells_test() {
  let lines = helper.visible_lines(helper.fixture())
  // The ruler is the line just above the top of the box.
  let assert Ok(ruler) =
    lines
    |> list.take_while(fn(line) { !string.contains(line, "┌") })
    |> list.last
  let assert Ok(row) = list.first(list.filter(lines, helper.is_grid_row))

  // The first column's heading sits directly above the first cell's digit,
  // in the grid of marks just as in the board.
  assert string.slice(ruler, 5, 1) == "1"
  assert string.slice(row, 5, 1) == "5"
  assert string.slice(ruler, 5 + helper.grid_columns + 4, 1) == "1"
}

pub fn a_lone_mark_shows_as_itself_test() {
  // A3 is the cursor cell, so the mark lands in the third column of row A.
  let lines = helper.visible_lines(helper.with_marks(helper.fixture(), [4]))
  let assert Ok(row) = list.first(list.filter(lines, helper.is_grid_row))

  assert helper.marks_half(row) == "A │ · · 4 │ · · · │ · · · │"
  // The board itself is untouched: A3 is still empty.
  assert helper.board_half(row) == "A │ 5 3 · │ · 7 · │ · · · │"
}

pub fn several_marks_show_as_an_asterisk_test() {
  let lines = helper.visible_lines(helper.with_marks(helper.fixture(), [4, 1]))
  let assert Ok(row) = list.first(list.filter(lines, helper.is_grid_row))

  assert helper.marks_half(row) == "A │ · · * │ · · · │ · · · │"
}

pub fn an_asterisk_can_be_read_back_from_the_status_line_test() {
  let crowded = helper.with_marks(helper.fixture(), [9, 1, 5, 3, 7])
  let lines = helper.visible_lines(crowded)
  let assert Ok(row) = list.first(list.filter(lines, helper.is_grid_row))

  assert string.contains(helper.marks_half(row), "*")
  assert list.any(lines, string.contains(_, "A3 marked 1 3 5 7 9"))
}

pub fn unmarked_cells_stay_empty_in_the_marks_grid_test() {
  let rows =
    helper.visible_lines(helper.fixture()) |> list.filter(helper.is_grid_row)

  use row <- list.each(rows)
  assert !string.contains(helper.marks_half(row), "*")
  assert helper.marks_half(row)
    == string.slice(row, 1, 4) <> "· · · │ · · · │ · · · │"
}

pub fn the_status_line_names_the_cursor_cell_test() {
  let marked =
    game.Game(..helper.fixture(), cursor: board.at(6, 3))
    |> helper.with_marks([7])
  assert list.any(helper.visible_lines(marked), string.contains(
    _,
    "G4 marked 7",
  ))

  // An unmarked cell says nothing at all.
  assert !list.any(helper.visible_lines(helper.fixture()), string.contains(
    _,
    "marked",
  ))
}

pub fn marking_mode_is_announced_test() {
  let marking = helper.step(helper.fixture(), key.Char("m"))
  let lines = helper.visible_lines(marking)

  assert list.any(lines, string.contains(_, "S U D O K U    Medium    marking"))
  assert list.any(lines, string.contains(_, "1-9 mark"))
  assert list.any(lines, string.contains(_, "m write"))

  // Writing mode says the opposite, and never says "marking" in the header.
  let writing = helper.visible_lines(helper.fixture())
  assert list.any(writing, string.contains(_, "1-9 place"))
  assert !list.any(writing, string.contains(_, "marking"))
}

pub fn marks_do_not_change_the_grid_width_test() {
  let widths =
    helper.visible_lines(helper.with_marks(helper.fixture(), [1, 2, 3, 4, 5]))
    |> list.filter(fn(line) {
      helper.is_grid_row(line) || string.contains(line, "─")
    })
    |> list.map(string.length)
    |> list.unique

  assert widths == [helper.frame_width]
}

pub fn the_status_line_reports_progress_test() {
  let lines = helper.visible_lines(helper.fixture())
  assert list.any(lines, string.contains(_, "empty 51"))
  assert list.any(lines, string.contains(_, "clashes 0"))
  assert list.any(lines, string.contains(_, "time 00:"))
}

pub fn the_status_line_counts_clashes_test() {
  // A 6 at C1 clashes twice over: with the 6 above it at B1, and with the 6
  // further along row C. All three cells are counted.
  let clashing =
    game.Game(..helper.fixture(), cursor: board.at(2, 0))
    |> helper.step(key.Digit(6))

  assert list.any(helper.visible_lines(clashing), string.contains(
    _,
    "clashes 3",
  ))
}

pub fn the_help_screen_lists_the_keys_test() {
  // The board's keys on the first page, and what can be asked for on the
  // second: too many for one page, once there were enough of them.
  let first = helper.visible_lines(helper.step(helper.fixture(), key.Char("?")))
  assert list.any(first, string.contains(_, "write a digit"))
  assert list.any(first, string.contains(_, "pencil the candidates"))

  let second =
    helper.visible_lines(helper.step(
      helper.step(helper.fixture(), key.Char("?")),
      key.Right,
    ))
  assert list.any(second, string.contains(_, "reveal the whole solution"))
  assert list.any(second, string.contains(_, "draw the screen again"))

  // Help takes the screen over rather than sharing it with the board.
  assert !list.any(first, helper.is_grid_row)
  assert !list.any(second, helper.is_grid_row)
}

/// The status line is two rows whatever it has to say, so the board above it
/// never shifts by a row between one message and the next.
pub fn the_message_is_always_two_rows_test() {
  let height = fn(current: game.Game) {
    list.length(helper.visible_lines(current))
  }

  let quiet = game.Game(..helper.fixture(), message: "")
  let hinted = helper.step(helper.aided(helper.fixture()), key.Char("H"))
  let undone = helper.step(helper.fixture(), key.Char("u"))

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
  let showing = game.Game(..helper.fixture(), help: option.Some(page))
  let lines = helper.visible_lines(showing)

  assert list.length(lines) <= 24
  use line <- list.each(lines)
  assert string.length(line) <= 78
}

pub fn the_help_says_how_to_start_the_game_test() {
  let showing = game.Game(..helper.fixture(), help: option.Some(game.Starting))
  let lines = helper.visible_lines(showing)

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
  let showing =
    game.Game(..helper.fixture(), help: option.Some(game.About(technique)))
  let lines = helper.visible_lines(showing)

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
  let start = helper.fixture()
  let frames = [
    start,
    helper.step(start, key.Char("?")),
    helper.step(start, key.Char("R")),
    helper.with_marks(start, [1, 2, 3, 4, 5]),
  ]

  use current <- list.each(frames)
  assert list.length(helper.visible_lines(current)) <= render.rows
}

pub fn the_title_line_fits_with_everything_on_it_test() {
  // Marking, looking for a digit, and a tally of wrong ones, all at once and
  // beside the longest name a puzzle has.
  let loaded =
    helper.blunder(helper.fixture(), helper.some_blanks(3))
    |> helper.checked
    |> helper.step(key.Char("m"))
    |> helper.step(key.Char("S"))
    |> helper.step(key.Digit(7))

  let assert [title, ..] = helper.visible_lines(loaded)

  assert string.contains(title, "marking")
  assert string.contains(title, "looking for 7")
  assert string.contains(title, "checking 3/3")
  assert string.length(title) <= render.columns
}

pub fn finishing_shows_a_result_test() {
  let lines = helper.visible_lines(helper.step(helper.fixture(), key.Char("R")))
  assert list.any(lines, string.contains(_, "Solution revealed."))
  assert list.any(lines, string.contains(_, "n new puzzle"))
}

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
    render.frame(game.Game(..helper.fixture(), showing: option.Some(shown))),
    helper.hint_wash,
  )

  // And nothing is lit up when nothing has been hinted.
  assert !string.contains(render.frame(helper.fixture()), helper.hint_wash)
}

pub fn what_a_hint_points_at_goes_out_on_the_next_keystroke_test() {
  // Twice: the cell it starts on may not be one that can be worked out yet,
  // and being told so is not a hint.
  let hinted =
    helper.aided(helper.fixture())
    |> helper.step(key.Char("H"))
    |> helper.step(key.Char("H"))
  assert hinted.showing != option.None

  let moved = helper.step(hinted, key.Down)
  assert moved.showing == option.None
  assert !string.contains(render.frame(moved), helper.hint_wash)
}

pub fn the_help_opens_at_what_the_last_hint_was_about_test() {
  let hinted =
    helper.aided(helper.fixture())
    |> helper.step(key.Char("H"))
    |> helper.step(key.Char("H"))
  let assert option.Some(shown) = hinted.showing

  assert helper.step(hinted, key.Char("?")).help
    == option.Some(game.About(shown.technique))

  // With no hint behind it, the help opens where it always did.
  assert helper.step(helper.fixture(), key.Char("?")).help
    == option.Some(game.Keys)
}

/// What is left of a style once the colours are taken out of it: the
/// attributes, which a terminal without colour still draws.
fn without_colour(style: String) -> List(String) {
  use kept, parameter <- list.fold(string.split(style, ";"), [])
  case int.parse(parameter) {
    // 0 to 29 are attributes — bold, underline, struck through. Above that
    // is colour, and 38 and 48 take two more parameters with them.
    Ok(code) if code < 30 -> [parameter, ..kept]
    _ -> kept
  }
}

pub fn the_board_can_be_read_without_colour_test() {
  // A terminal with no colour draws the attributes and nothing else, so any
  // two things the player has to tell apart must differ in those alone.
  let given = without_colour(palette.given)
  let entered = without_colour(palette.entered)
  let conflict = without_colour(palette.conflict)
  let wrong = without_colour(palette.wrong)

  assert given != entered
  assert conflict != given
  assert conflict != entered
  assert conflict != wrong
  assert wrong != given
  assert wrong != entered

  // The cursor is reverse video, which is no colour at all.
  assert without_colour(palette.cursor) == ["7"]
}

pub fn words_are_not_struck_through_test() {
  // Striking a digit out says it cannot stand. Striking out a sentence says
  // it should not be read, which is the opposite of what a panel is for.
  assert !list.contains(without_colour(palette.alarm), "9")
  assert list.contains(without_colour(palette.conflict), "9")
}

pub fn the_cursor_is_highlighted_test() {
  // Reverse video, then the empty cell the cursor starts on.
  assert string.contains(render.frame(helper.fixture()), "7;90m \u{b7}")
}

pub fn the_frame_starts_at_the_top_of_the_screen_test() {
  assert string.starts_with(render.frame(helper.fixture()), "\u{1b}[H")
}

pub fn a_window_with_no_room_is_complained_about_test() {
  // Both ways of being short, and either one on its own.
  assert string.contains(render.cramped_at(60, 20), "60 by 20")
  assert string.contains(render.cramped_at(60, 20), "78 by 24")
  assert render.cramped_at(60, 40) != ""
  assert render.cramped_at(100, 20) != ""

  // Exactly enough is enough.
  assert render.cramped_at(render.columns, render.rows) == ""
  assert render.cramped_at(200, 60) == ""
}

pub fn a_terminal_that_will_not_say_is_left_alone_test() {
  // -1 is the terminal declining to answer, which is not the same as a window
  // with no room in it.
  assert render.cramped_at(-1, -1) == ""

  // One answer and one refusal still counts, with the refusal left as a
  // question mark rather than guessed at.
  assert string.contains(render.cramped_at(60, -1), "60 by ?")
  assert string.contains(render.cramped_at(-1, 20), "? by 20")
}

// ---------------------------------------------------------------------------
// The opening menu
// ---------------------------------------------------------------------------

/// The menu as it is drawn with nothing saved and no times to beat.
fn opening() -> List(String) {
  helper.lines_of(render.menu_frame(True, Error(Nil), dict.new()))
}

pub fn the_menu_offers_every_kind_of_puzzle_test() {
  let lines = opening()

  // Numbered from one, in the order the digits are read back in.
  use origin, index <- list.index_map(generator.origins())
  let wanted = int.to_string(index + 1)
  assert list.any(lines, fn(line) {
    string.contains(line, wanted)
    && string.contains(line, generator.origin_label(origin))
  })
}

pub fn the_menu_says_what_each_level_asks_for_test() {
  let lines = opening()

  use difficulty <- list.each(generator.difficulties)
  assert list.any(lines, string.contains(_, generator.asks_for(difficulty)))
}

pub fn the_menu_shows_a_time_to_beat_where_there_is_one_test() {
  let bests = dict.from_list([#(generator.Hard, 125_000)])
  let lines = helper.lines_of(render.menu_frame(True, Error(Nil), bests))

  assert list.any(lines, fn(line) {
    string.contains(line, "Hard") && string.contains(line, "best 02:05")
  })

  // And nothing at all for the levels with no time behind them.
  assert !list.any(opening(), string.contains(_, "best"))
}

pub fn the_menu_offers_a_saved_game_back_test() {
  let waiting = helper.step(helper.fixture(), key.Digit(4))
  let lines = helper.lines_of(render.menu_frame(True, Ok(waiting), dict.new()))

  // What it was, how much is left of it, and how long it has taken.
  assert list.any(lines, fn(line) {
    string.contains(line, "Resume")
    && string.contains(line, "Medium")
    && string.contains(line, "to go")
  })

  // With nothing put down, there is nothing to pick up.
  assert !list.any(opening(), string.contains(_, "Resume"))
}

pub fn the_menu_says_when_the_terminal_is_in_line_mode_test() {
  let lines = helper.lines_of(render.menu_frame(False, Error(Nil), dict.new()))

  assert list.any(lines, string.contains(_, "press Enter after each key"))
  assert !list.any(opening(), string.contains(_, "press Enter"))
}

pub fn the_menu_fits_the_screen_test() {
  let lines =
    helper.lines_of(render.menu_frame(
      False,
      Ok(helper.fixture()),
      dict.from_list([
        #(generator.Easy, 1),
        #(generator.Medium, 2),
        #(generator.Hard, 3),
        #(generator.Expert, 4),
      ]),
    ))

  assert list.length(lines) <= render.rows
  use line <- list.each(lines)
  assert string.length(line) <= render.columns
}

pub fn a_puzzle_being_dealt_is_named_with_the_right_article_test() {
  let said = fn(difficulty) {
    helper.lines_of(render.generating(difficulty)) |> string.join(" ")
  }

  assert string.contains(said(generator.Easy), "an Easy puzzle")
  assert string.contains(said(generator.Expert), "an Expert puzzle")
  assert string.contains(said(generator.Hard), "a Hard puzzle")
  assert string.contains(said(generator.Medium), "a Medium puzzle")
}
