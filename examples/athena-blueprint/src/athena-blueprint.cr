# Athena + Blueprint + Datastar Example
#
# This example demonstrates how to use Datastar with the Athena web framework
# and Blueprint HTML builder to create reactive server-rendered UIs.
#
# Features demonstrated:
# - SSE streaming with live updates (counter, clock)
# - One-off SSE events (greet, stop)
# - Blueprint components for type-safe HTML generation
# - Datastar integration with Athena controllers
#
# Run with:
#   shards install
#   shards build
#   ./bin/athena-blueprint
#
# Then open http://localhost:3000 in your browser.

require "./controllers/*"

ATH.run
