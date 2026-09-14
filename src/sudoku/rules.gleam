//// What each keystroke does to a game.
////
//// One function to a key, near enough: the dispatch says which, and the
//// rules below say what. Everything here takes a game and gives one back,
//// so a key that turns out to change nothing changes nothing.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import sudoku/board.{type Board}
import sudoku/game
import sudoku/generator
import sudoku/hint
import sudoku/key.{type Key}
import sudoku/logic
import sudoku/term

pub fn update(current: game.Game, pressed: Key) -> game.Step {
  case pressed, current.paused, current.help {
    // A terminal in line mode sends a newline after every key. The player
    // did not press it, so it must not count as having pressed something:
    // it would close the help as soon as it opened, and cancel every offer
    // before it could be taken up.
    key.Unknown, _, _ -> game.Continue(current)
    _, True, _ -> resting(current, pressed)
    _, _, Some(page) -> browse(current, page, pressed)
    _, _, None -> play(current, pressed)
  }
}

// --------------------------------------------------------------------------
// Reading the help
// --------------------------------------------------------------------------

/// A paused game has the keyboard to itself, and there is only one thing to
/// say to it: carry on. Quitting still works, since a game put down is kept
/// either way.
fn resting(current: game.Game, pressed: Key) -> game.Step {
  case pressed {
    key.Quit | key.Char("q") | key.Char("Q") -> game.Exit
    _ -> game.Continue(wake(current))
  }
}

/// Put the board away and stop the clock.
fn pause(current: game.Game) -> game.Game {
  game.Game(
    ..current,
    paused: True,
    resting_since: Some(term.now_ms()),
    message: "",
  )
}

/// While the help is up it has the keyboard to itself: the arrows turn the
/// pages and anything else puts it away. Nothing reaches the board, so there
/// is no reading about a technique and moving the cursor by accident.
fn browse(current: game.Game, page: game.Help, pressed: Key) -> game.Step {
  case pressed {
    key.Quit | key.Char("q") | key.Char("Q") -> game.Exit
    key.Right | key.Char("l") -> game.Continue(turn(current, page, 1))
    key.Left | key.Char("h") -> game.Continue(turn(current, page, -1))
    _ -> game.Continue(wake(current))
  }
}

fn turn(current: game.Game, page: game.Help, by: Int) -> game.Game {
  let all = game.pages()
  let count = list.length(all)
  let at = case list.take_while(all, fn(other) { other != page }) {
    before -> list.length(before)
  }

  let next = case list.drop(all, { at + by + count } % count) {
    [page, ..] -> page
    [] -> game.Keys
  }

  game.Game(..current, help: Some(next))
}

/// Put the help away and give back the time spent reading it, by moving the
/// start of the game along by as long as the help was up.
///
/// Not once the game is over: the time then is a result, and a result does
/// not move.
fn wake(current: game.Game) -> game.Game {
  let rested = case current.resting_since, current.finished_ms {
    Some(since), None -> term.now_ms() - since
    _, _ -> 0
  }

  game.Game(
    ..current,
    help: None,
    paused: False,
    resting_since: None,
    offered: None,
    verdict: None,
    showing: None,
    started_ms: current.started_ms + rested,
  )
}

fn asked_about(showing: Option(logic.Step)) -> game.Help {
  case showing {
    Some(step) -> game.About(step.technique)
    None -> game.Keys
  }
}

// --------------------------------------------------------------------------
// Playing
// --------------------------------------------------------------------------

fn play(current: game.Game, pressed: Key) -> game.Step {
  // An offer only stands for the very next keystroke, and only for the key
  // that made it.
  let offered = case current.offered {
    None -> None
    Some(offer) ->
      case list.contains(game.asked_by(offer), pressed) {
        True -> current.offered
        False -> None
      }
  }

  // What the last hint marked out on the board stands for one keystroke too,
  // whatever that keystroke turns out to be.
  let showing = current.showing
  let current =
    game.Game(
      ..current,
      offered: offered,
      showing: None,
      scan: still_asking(current.scan, pressed),
    )

  case pressed {
    key.Quit | key.Char("q") | key.Char("Q") -> game.Exit
    key.Char("n") | key.Char("N") -> giving_up(current)
    // Straight to the page for whatever the last hint was about, since that
    // is what somebody who has just read one is asking after.
    key.Char("?") ->
      game.Continue(
        game.Game(
          ..current,
          help: Some(asked_about(showing)),
          resting_since: Some(term.now_ms()),
        ),
      )

    _ if current.finished_ms != None ->
      game.Continue(
        game.Game(..current, message: "Press n for a new puzzle, or q to quit."),
      )

    key.Up | key.Char("k") | key.Char("w") ->
      game.Continue(move(current, -1, 0))
    key.Down | key.Char("j") | key.Char("s") ->
      game.Continue(move(current, 1, 0))
    key.Left | key.Char("h") | key.Char("a") ->
      game.Continue(move(current, 0, -1))
    key.Right | key.Char("l") | key.Char("d") ->
      game.Continue(move(current, 0, 1))

    // A digit straight after S says which digit to look for, rather than
    // writing anything. Only that one: a scan is a way of looking at the
    // board, not a mode to be in.
    key.Digit(digit) if current.scan == game.Picking ->
      game.Continue(scan_for(current, digit))

    key.Digit(digit) if current.marking -> game.Continue(mark(current, digit))
    key.Digit(digit) -> game.Continue(place(current, digit))

    // Shift and a digit pencils one in without leaving writing, and rubs one
    // out without leaving marking. Now that the candidates can be filled in
    // wholesale, marking is mostly rubbing out, and a mode switch each way
    // round for every one of them is a great deal of switching.
    key.Shifted(digit) -> game.Continue(mark(current, digit))

    key.Erase if current.marking -> game.Continue(unmark(current))
    key.Erase -> game.Continue(erase(current))

    key.Char("p") -> game.Continue(pause(current))
    key.Char("f") -> game.Continue(fill(current))
    key.Char("m") -> game.Continue(toggle_marking(current))
    key.Char("u") -> game.Continue(undo(current))
    key.Char("r") -> game.Continue(redo(current))
    key.Char("S") -> game.Continue(scanning(current))
    key.Char("c") -> game.Continue(start_checking(current))
    key.Char("H") -> game.Continue(hint.hint(current))
    key.Char("R") -> game.Continue(revealing(current))

    _ -> game.Continue(current)
  }
}

/// Starting another puzzle throws this one away, and the game saved for it
/// with it. `n` is next to `m` on the keyboard, so reaching for marking and
/// missing would cost the player the hour they have spent. It is asked for
/// twice where there is anything to lose, and once where there is not.
fn giving_up(current: game.Game) -> game.Step {
  case under_way(current), current.offered == Some(game.GiveUp) {
    False, _ | _, True -> game.Restart
    True, False ->
      game.Continue(
        game.Game(
          ..current,
          offered: Some(game.GiveUp),
          message: "Press n again to give up this puzzle.\nNothing of it is kept.",
        ),
      )
  }
}

/// Whether there is a puzzle here to lose: one begun, and not yet over.
fn under_way(current: game.Game) -> Bool {
  !game.is_finished(current) && current.board != current.puzzle.board
}

fn move(current: game.Game, rows: Int, cols: Int) -> game.Game {
  let row = { board.row_of(current.cursor) + rows + board.side } % board.side
  let col = { board.col_of(current.cursor) + cols + board.side } % board.side
  game.Game(..current, cursor: board.at(row, col), message: "")
}

// --------------------------------------------------------------------------
// Writing a digit
// --------------------------------------------------------------------------

fn place(current: game.Game, digit: Int) -> game.Game {
  case board.is_given(current.board, current.cursor) {
    True ->
      game.Game(..current, message: "That cell is a clue and cannot change.")
    False -> {
      let written =
        current |> game.remember |> game.with_board(written(current, digit))

      case caught(current, digit) {
        False -> game.settle(written)
        True -> count_against(written)
      }
    }
  }
}

/// Writing a digit tidies up the marks around it, but not one that checking
/// is calling out as wrong in the same breath. Those marks are the reasoning
/// the wrong digit interrupted, and rubbing them out would cost the player
/// the work they need to put it right.
///
/// Only while checking: with it off the game is saying nothing about whether
/// a digit is right, and marks that quietly survived would be saying it.
fn written(current: game.Game, digit: Int) -> Board {
  case current.checking && digit != game.answer(current, current.cursor) {
    True -> board.write(current.board, current.cursor, digit)
    False -> board.place(current.board, current.cursor, digit)
  }
}

/// Whether checking is about to call this digit out as wrong. Writing the
/// digit a cell already holds changes nothing, so it costs nothing either.
fn caught(current: game.Game, digit: Int) -> Bool {
  current.checking
  && digit != game.answer(current, current.cursor)
  && digit != board.value(current.board, current.cursor)
}

/// Put a caught digit on the tally, and end the game once the tally is past
/// what checking allows.
///
/// Undo takes the digit back but not the mistake. It was checking that told
/// the player the digit was wrong, and undo cannot untell them.
fn count_against(current: game.Game) -> game.Game {
  let mistakes = current.mistakes + 1

  case mistakes > game.mistake_limit {
    True -> forfeit(game.Game(..current, mistakes: mistakes))
    False ->
      game.Game(
        ..current,
        mistakes: mistakes,
        message: "Wrong. " <> allowance(game.mistake_limit - mistakes),
      )
  }
}

fn forfeit(current: game.Game) -> game.Game {
  game.Game(
    ..current,
    ending: Some(game.Forfeited),
    finished_ms: Some(term.now_ms()),
  )
}

/// What is left of the allowance, as the player is told it. Never called with
/// none left: running out is the end of the game, not a state to report.
fn allowance(left: Int) -> String {
  case left {
    0 -> "The next one forfeits the puzzle."
    1 -> "One more forfeits the puzzle."
    _ -> int.to_string(left) <> " more forfeit the puzzle."
  }
}

fn erase(current: game.Game) -> game.Game {
  case
    board.is_given(current.board, current.cursor),
    board.value(current.board, current.cursor)
  {
    True, _ ->
      game.Game(..current, message: "That cell is a clue and cannot change.")
    False, 0 -> game.Game(..current, message: "")
    False, _ ->
      current
      |> game.remember
      |> game.with_board(board.erase(current.board, current.cursor))
  }
}

// --------------------------------------------------------------------------
// Pencil marks
// --------------------------------------------------------------------------

/// Pencil a digit into the cell, or rub it out if it is already there.
fn mark(current: game.Game, digit: Int) -> game.Game {
  case
    board.is_given(current.board, current.cursor),
    board.value(current.board, current.cursor)
  {
    True, _ ->
      game.Game(..current, message: "That cell is a clue and cannot change.")
    _, 0 ->
      current
      |> game.remember
      |> game.with_board(board.toggle_mark(current.board, current.cursor, digit))
    _, _ ->
      game.Game(
        ..current,
        message: "There is a digit here already. Press 0 to clear it first.",
      )
  }
}

fn unmark(current: game.Game) -> game.Game {
  case set.is_empty(board.marks_at(current.board, current.cursor)) {
    True -> game.Game(..current, message: "")
    False ->
      current
      |> game.remember
      |> game.with_board(board.clear_marks(current.board, current.cursor))
  }
}

fn toggle_marking(current: game.Game) -> game.Game {
  case current.marking {
    True ->
      game.Game(..current, marking: False, message: "Back to writing digits.")
    False ->
      game.Game(
        ..current,
        marking: True,
        message: "Marking: 1-9 pencils a digit in, 0 clears the cell.",
      )
  }
}

/// Pencil every candidate into the empty cells that have none.
///
/// This is bookkeeping rather than insight — what a cell could still take is
/// there to be read off its row, its column and its box by anyone willing to
/// look — so it costs nothing. What it buys is the rest of the game: every
/// technique past a naked single is an argument about candidates, and an
/// argument about candidates needs some on the board to be about.
///
/// Cells already marked are left alone. That is where the player has been
/// thinking, and thinking is not for rubbing out.
fn fill(current: game.Game) -> game.Game {
  let peers = board.peers_table()
  let grid = current.board.values

  let bare = {
    use index <- list.filter(board.indices())
    board.value(current.board, index) == 0
    && set.is_empty(board.marks_at(current.board, index))
  }

  case bare, current.offered == Some(game.RedoMarks) {
    // Asked a second time with nothing bare left: mark the lot afresh, which
    // is the only way to be rid of marks made wrongly by hand.
    [], True -> afresh(current)

    [], False ->
      game.Game(
        ..current,
        offered: Some(game.RedoMarks),
        message: "Every empty cell is marked up already.\nPress f again to mark them all afresh.",
      )

    _, _ -> {
      let pencilled = {
        use marked, index <- list.fold(bare, current.board)
        use marked, digit <- list.fold(
          board.candidates(grid, peers, index),
          marked,
        )
        board.toggle_mark(marked, index, digit)
      }

      let filled = current |> game.remember |> game.with_board(pencilled)
      let left = board.empty_count(current.board) - list.length(bare)

      game.Game(
        ..filled,
        message: "Pencilled in "
          <> int.to_string(list.length(bare))
          <> " cells.\n"
          <> case left {
            0 -> "Every empty cell now shows what it could still take."
            1 -> "The one you had marked already is left as it was."
            _ ->
              "The "
              <> int.to_string(left)
              <> " you had marked already are left as they were."
          },
      )
    }
  }
}

/// Mark every empty cell afresh, whatever was there before.
///
/// Marks made by hand are left alone by filling, which is the right way round
/// while they are being reasoned with. But a mark made wrongly, or made and
/// forgotten, then sits there looking as settled as any other, and nothing
/// else will shift it. This is the way out, and it takes asking twice because
/// what it throws away is the player's own work.
fn afresh(current: game.Game) -> game.Game {
  let peers = board.peers_table()
  let grid = current.board.values

  let empty = {
    use index <- list.filter(board.indices())
    board.value(current.board, index) == 0
  }

  let marked = {
    use so_far, index <- list.fold(empty, current.board)
    use marked, digit <- list.fold(
      board.candidates(grid, peers, index),
      board.clear_marks(so_far, index),
    )
    board.toggle_mark(marked, index, digit)
  }

  let done = current |> game.remember |> game.with_board(marked)

  game.Game(
    ..done,
    offered: None,
    verdict: None,
    showing: None,
    message: "Marked all "
      <> int.to_string(list.length(empty))
      <> " empty cells afresh.\n"
      <> "What you had pencilled in yourself is gone.",
  )
}

// --------------------------------------------------------------------------
// Looking for somewhere a digit can go
// --------------------------------------------------------------------------

/// Ask which digit to look for, or put away the scan already up.
fn scanning(current: game.Game) -> game.Game {
  case current.scan {
    game.NotScanning ->
      game.Game(
        ..current,
        scan: game.Picking,
        message: "Look for which digit?\nPress 1 to 9, or anything else to forget it.",
      )
    _ -> game.Game(..current, scan: game.NotScanning, message: "")
  }
}

fn scan_for(current: game.Game, digit: Int) -> game.Game {
  let room = list.length(board.could_take(current.board, digit))

  game.Game(
    ..current,
    scan: game.ScanningFor(digit),
    message: "Looking for somewhere a "
      <> int.to_string(digit)
      <> " can go.\n"
      <> room_for(room, digit)
      <> " Press S again to stop looking.",
  )
}

fn room_for(cells: Int, digit: Int) -> String {
  case cells {
    0 -> "Nowhere: every " <> int.to_string(digit) <> " is already placed."
    1 -> "One cell can take it."
    _ -> int.to_string(cells) <> " cells can take it."
  }
}

/// A scan asked for and not answered lapses on the next keystroke, the same
/// way an offer does. Anything but a digit means the player has gone back to
/// playing, and that keystroke should do what it always does.
fn still_asking(scan: game.Scan, pressed: Key) -> game.Scan {
  case scan, pressed {
    game.Picking, key.Digit(_) | game.Picking, key.Char("S") -> scan
    game.Picking, _ -> game.NotScanning
    _, _ -> scan
  }
}

// --------------------------------------------------------------------------
// Going back, and forward again
// --------------------------------------------------------------------------

/// Only reachable while the puzzle is unfinished, so there is no finished
/// state to walk back out of.
fn undo(current: game.Game) -> game.Game {
  case current.history {
    [] -> game.Game(..current, message: "Nothing left to undo.")
    [previous, ..rest] ->
      game.Game(
        ..current,
        board: previous.board,
        // Back to where the change was made, so that it can be watched being
        // taken back rather than happening off where nobody is looking.
        cursor: previous.cursor,
        history: rest,
        // The board to come forward to again, tagged with the same cell: it
        // is the one that will change, whichever way it is walked.
        undone: [
          game.Moment(board: current.board, cursor: previous.cursor),
          ..current.undone
        ],
        message: "Undone. Press r to do it again.",
      )
  }
}

/// Walk forward again through what was undone.
///
/// Only until something else is written. A board arrived at by another route
/// has no way forward from here, and offering one would be offering to undo
/// what the player has just done.
fn redo(current: game.Game) -> game.Game {
  case current.undone {
    [] -> game.Game(..current, message: "Nothing to do again.")
    [next, ..rest] ->
      game.Game(
        ..current,
        board: next.board,
        cursor: next.cursor,
        history: [
          game.Moment(board: current.board, cursor: next.cursor),
          ..current.history
        ],
        undone: rest,
        message: "Done again.",
      )
  }
}

// --------------------------------------------------------------------------
// Asking the game
// --------------------------------------------------------------------------

/// Checking goes on and stays on.
///
/// It is a bargain rather than a switch: a player who could turn it off again
/// would be asking the grid one question at a time and paying for none of
/// them. So the wrong digits it finds on the way in go on the tally, along
/// with every one written after.
///
/// Finding more wrong than the allowance forfeits the puzzle there and then,
/// the same as writing one too many would. Being over the allowance is not a
/// state to go on playing in: the game would be asking the player to carry a
/// debt it will never let them pay off.
fn start_checking(current: game.Game) -> game.Game {
  case current.checking, current.offered == Some(game.StartChecking) {
    True, _ -> game.Game(..current, message: "Checking stays on now it is on.")

    // Checking cannot be undone, it costs the game its timing, and where
    // there are wrong digits waiting it can end the puzzle on the spot. All
    // of that is worth hearing before it happens rather than after.
    False, False ->
      game.Game(
        ..current,
        offered: Some(game.StartChecking),
        message: about_to_check(current),
      )

    False, True -> {
      let found = list.count(board.indices(), game.is_wrong(current, _))
      let mistakes = current.mistakes + found
      let checking =
        game.Game(..current, checking: True, aided: True, mistakes: mistakes)

      case mistakes > game.mistake_limit {
        // No message: the finished panel says what happened, and how much.
        True -> forfeit(checking)
        False ->
          game.Game(
            ..checking,
            message: found_message(found)
              <> " "
              <> allowance(game.mistake_limit - mistakes),
          )
      }
    }
  }
}

/// What switching checking on would do from here, said before it is done.
fn about_to_check(current: game.Game) -> String {
  let found = list.count(board.indices(), game.is_wrong(current, _))
  let timed = case current.puzzle.origin {
    generator.Dealt(_) -> game.unaided(current)
    generator.Handwritten -> False
  }

  case current.mistakes + found > game.mistake_limit, timed {
    True, _ ->
      "Checking would find "
      <> int.to_string(found)
      <> " wrong, which forfeits the puzzle.\nPress c again if you mean it."
    False, True ->
      "Checking stays on for good, and an aided game is not timed.\nPress c again to switch it on."
    False, False ->
      "Checking stays on for good once it is on.\nPress c again to switch it on."
  }
}

fn found_message(found: Int) -> String {
  case found {
    0 -> "Checking on, for good."
    1 -> "Checking on: 1 digit is wrong."
    _ -> "Checking on: " <> int.to_string(found) <> " digits are wrong."
  }
}

/// Fill the answer in, which is the end of the puzzle.
///
/// Asked for twice while there is a puzzle here to lose. `R` is `r` with a
/// thumb on shift, and `r` is pressed over and over walking forward through
/// undone moves, so the slip is an easy one to make and there is no undoing
/// it: a game that is over cannot be walked back out of.
fn revealing(current: game.Game) -> game.Game {
  case under_way(current), current.offered == Some(game.Reveal) {
    False, _ | _, True -> reveal(current)
    True, False ->
      game.Game(
        ..current,
        offered: Some(game.Reveal),
        message: "Press R again to fill the answer in.\nThat is the end of this puzzle.",
      )
  }
}

fn reveal(current: game.Game) -> game.Game {
  let solved =
    list.fold(board.indices(), current.board, fn(grid, index) {
      board.place(grid, index, game.answer(current, index))
    })

  let shown = current |> game.remember |> game.with_board(solved)

  // No message: the finished panel already says what happened.
  game.Game(
    ..shown,
    ending: Some(game.Revealed),
    finished_ms: Some(term.now_ms()),
  )
}
