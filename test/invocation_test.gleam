//// Reading a command line.

import gleam/list
import gleam/string
import helper
import sudoku/board
import sudoku/generator
import sudoku/help
import sudoku/invocation

fn read(arguments: List(String)) -> Result(invocation.Invocation, String) {
  invocation.read(arguments)
}

pub fn no_arguments_leave_it_to_the_menu_test() {
  assert read([]) == Ok(invocation.Invocation(invocation.Menu, False))
}

pub fn a_difficulty_is_dealt_straight_away_test() {
  use difficulty <- list.each(generator.difficulties)
  let name = generator.label(difficulty)

  // However it is capitalised: a command line is typed in a hurry.
  use spelling <- list.each([
    name,
    string.lowercase(name),
    string.uppercase(name),
  ])
  assert read([spelling])
    == Ok(invocation.Invocation(invocation.Deal(difficulty), False))
}

pub fn custom_and_resume_are_words_of_their_own_test() {
  assert read(["custom"])
    == Ok(invocation.Invocation(invocation.Compose, False))
  assert read(["Resume"]) == Ok(invocation.Invocation(invocation.Resume, False))
}

pub fn a_puzzle_is_taken_as_its_eighty_one_characters_test() {
  let clues = board.to_string(helper.grid(helper.puzzle_text))
  let assert Ok(invocation.Invocation(invocation.Play(puzzle), False)) =
    read([clues])

  assert puzzle.board.values == helper.grid(helper.puzzle_text)
  assert puzzle.origin == generator.Handwritten

  // And the answer came with it, since the game needs one to check against.
  assert puzzle.solution == helper.grid(helper.solution_text)
}

pub fn a_puzzle_that_is_not_one_is_refused_by_its_clues_test() {
  // The right length, so it was meant as a puzzle: the complaint should be
  // about the puzzle rather than about how to start the game.
  let assert Error(complaint) = read([string.repeat(".", 81)])

  assert !string.contains(complaint, "Usage:")
  assert string.contains(string.lowercase(complaint), "answer")
}

pub fn a_word_that_is_neither_gets_the_usage_test() {
  let assert Error(complaint) = read(["impossible"])
  assert complaint == help.usage()

  // As does more than one thing to play at once.
  assert read(["easy", "hard"]) == Error(help.usage())
}

pub fn the_plain_flag_can_come_on_either_side_test() {
  let dealt = invocation.Deal(generator.Hard)

  assert read(["--plain"]) == Ok(invocation.Invocation(invocation.Menu, True))
  assert read(["--plain", "hard"]) == Ok(invocation.Invocation(dealt, True))
  assert read(["hard", "--plain"]) == Ok(invocation.Invocation(dealt, True))
}

pub fn a_flag_the_game_does_not_know_gets_the_usage_test() {
  assert read(["--colour"]) == Error(help.usage())
  assert read(["--plain", "--colour"]) == Error(help.usage())
  assert read(["-p"]) == Error(help.usage())
}

pub fn the_usage_names_every_way_in_test() {
  // The flag is one of the invocations the help lists, so the two cannot
  // come to disagree about what the game accepts.
  assert list.any(help.invocations, fn(entry) {
    string.contains(entry.0, invocation.plain_flag)
  })
}

pub fn asking_what_the_command_line_takes_is_not_a_mistake_test() {
  use flag <- list.each(invocation.help_flags)
  let assert Ok(asked) = invocation.read([flag])
  assert asked.asked == invocation.Explain

  // Nothing beside it can turn the question into a mistake: not a puzzle,
  // not a difficulty, and not a flag that would have been one on its own.
  let assert Ok(beside) = invocation.read(["hard", flag])
  assert beside.asked == invocation.Explain

  let assert Ok(muddled) = invocation.read([flag, "--nonsense"])
  assert muddled.asked == invocation.Explain

  // And a flag that says how the game should look is still read.
  let assert Ok(plainly) = invocation.read([flag, invocation.plain_flag])
  assert plainly.asked == invocation.Explain
  assert plainly.plain
}

pub fn the_usage_says_how_to_ask_for_it_test() {
  // One row for the two spellings, since -h is the same question in fewer
  // letters and a second row saying so would be a row about nothing.
  assert string.contains(help.usage(), "--help")
  assert invocation.help_flags == ["--help", "-h"]
}
