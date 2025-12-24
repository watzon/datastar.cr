# Pub/Sub module for multi-session synchronization.
#
# Usage:
# ```
# require "datastar/pubsub"
#
# # Configure at startup
# Datastar::PubSub.configure
#
# # Subscribe in stream handlers
# env.datastar_stream do |sse|
#   sse.subscribe("todos:#{list_id}")
# end
#
# # Broadcast from anywhere
# Datastar::PubSub.broadcast("todos:#{list_id}") do |sse|
#   sse.patch_elements("#list", render_todos)
# end
# ```

require "./pubsub/backend"
require "./pubsub/memory_backend"
require "./pubsub/connection"
require "./pubsub/manager"
require "./pubsub/event_collector"
require "./pubsub/broadcaster"
require "./pubsub/pubsub"
