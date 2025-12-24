# Athena + Datastar TodoMVC Example
#
# This example demonstrates how to use Datastar with the Athena web framework
# and Blueprint HTML builder to create a reactive TodoMVC implementation.
#
# Features demonstrated:
# - SSE streaming with live updates
# - Pub/Sub for multi-session synchronization
# - Blueprint components for type-safe HTML generation
# - Full TodoMVC functionality (add, toggle, edit, delete, filter)
#
# Run with:
#   shards install
#   shards build
#   ./bin/athena-todomvc
#
# Then open http://localhost:3000 in your browser.

require "./controllers/*"

ATH.run
