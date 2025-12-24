require "kemal"
require "datastar/adapters/kemal"

require "./store"
require "./components/todo_page"
require "./components/todo_list"
require "./components/todo_item"
require "./components/todo_footer"

# Global store (resets on server restart)
STORE = TodoStore.new

# Configure pub/sub for multi-session sync
Datastar::PubSub.configure do |config|
  config.on_subscribe do |topic, conn_id|
    Log.info { "Client #{conn_id[0..7]}... subscribed to #{topic}" }
  end
  config.on_unsubscribe do |topic, conn_id|
    Log.info { "Client #{conn_id[0..7]}... unsubscribed from #{topic}" }
  end
end

# Topic for broadcasting todo updates
TODOS_TOPIC = "todos"

# Helper to broadcast UI updates to all connected clients
def broadcast_todos
  Datastar::PubSub.broadcast(TODOS_TOPIC) do |sse|
    sse.patch_elements(TodoList.new(STORE.filtered_todos))
    sse.patch_elements(TodoFooter.new(
      STORE.pending_count,
      STORE.has_completed?,
      STORE.mode
    ))
  end
end

# Serve the main HTML page
get "/" do |env|
  env.datastar_render(TodoPage.new)
end

# SSE endpoint - streams initial state and subscribes to updates
# Multiple browser sessions will all receive updates when any session makes changes
get "/updates" do |env|
  env.datastar_stream do |sse|
    # Subscribe to receive broadcasts from other sessions
    sse.subscribe(TODOS_TOPIC)

    # Send the current todo list
    sse.patch_elements(TodoList.new(STORE.filtered_todos))

    # Send the footer
    sse.patch_elements(TodoFooter.new(
      STORE.pending_count,
      STORE.has_completed?,
      STORE.mode
    ))

    # Keep connection open to receive broadcasts
    # The connection stays alive until the client disconnects
    loop do
      sleep 30.seconds
      break if sse.closed?
    end
  end
end

# Add a new todo
patch "/todos" do |env|
  env.datastar_stream do |sse|
    # Get the input signal from the request
    signals = sse.signals
    input = signals["input"]?.try(&.as_s?) || ""

    unless input.empty?
      STORE.add(input)

      # Broadcast update to all connected clients
      broadcast_todos
    end
  end
end

# Toggle a specific todo
post "/todos/:id/toggle" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    STORE.toggle(id)

    # Broadcast update to all connected clients
    broadcast_todos
  end
end

# Toggle all todos
post "/todos/toggle-all" do |env|
  env.datastar_stream do |sse|
    STORE.toggle_all

    # Broadcast update to all connected clients
    broadcast_todos
  end
end

# Delete a specific todo
delete "/todos/:id" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    STORE.remove(id)

    # Broadcast update to all connected clients
    broadcast_todos
  end
end

# Delete all completed todos
delete "/todos/completed" do |env|
  env.datastar_stream do |sse|
    STORE.remove_completed

    # Broadcast update to all connected clients
    broadcast_todos
  end
end

# Enter edit mode for a todo
get "/todos/:id/edit" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    if todo = STORE.todos.find { |t| t.id == id }
      sse.patch_elements(TodoItem.new(todo, editing: true))
    end
  end
end

# Cancel editing a todo
get "/todos/:id/cancel" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    if todo = STORE.todos.find { |t| t.id == id }
      sse.patch_elements(TodoItem.new(todo, editing: false))
    end
  end
end

# Update a todo's text
patch "/todos/:id" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    signals = sse.signals
    # Signal name is dynamic: edit{uuid without hyphens}
    signal_name = "edit#{id.gsub("-", "")}"
    new_text = signals[signal_name]?.try(&.as_s?) || ""

    if todo = STORE.todos.find { |t| t.id == id }
      unless new_text.empty?
        todo.text = new_text
      end

      # Broadcast update to all connected clients
      broadcast_todos
    end
  end
end

# Change filter mode
put "/mode/:mode" do |env|
  mode = env.params.url["mode"].to_i

  env.datastar_stream do |sse|
    STORE.set_mode(mode)

    # Broadcast update to all connected clients
    broadcast_todos
  end
end

# Reset to default todos
put "/reset" do |env|
  env.datastar_stream do |sse|
    STORE.reset_to_defaults

    # Broadcast update to all connected clients
    broadcast_todos
  end
end

Kemal.run
