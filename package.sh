#!/bin/sh
# Build a single-file, self-contained `sudoku` executable.
#
# The result needs Erlang/OTP 27 or later on the machine that runs it, but
# not Gleam and not this repository. Ctrl-C handling is baked in; see
# scripts/package.escript for why that is a flag and not a wrapper.
set -eu

output="${1:-build/sudoku}"

gleam export erlang-shipment
exec ./scripts/package.escript build/erlang-shipment "$output"
