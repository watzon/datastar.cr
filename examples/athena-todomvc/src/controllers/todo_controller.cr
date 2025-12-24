require "athena"
require "datastar"
require "datastar/adapters/athena"
require "datastar/adapters/blueprint"
require "../store"
require "../components/todo_page"
require "../components/todo_list"
require "../components/todo_item"
require "../components/todo_footer"

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

# Topic for broadcasting todo data changes
TODOS_TOPIC = "todos"

# TodoMVC controller with all routes matching the Kemal implementation
class TodoController < ATH::Controller
  include Datastar::Athena::LiveController

  # Helper to broadcast data updates to all connected clients.
  # Sends ALL todos (unfiltered) since each session has its own filter mode.
  # Also sends updated counts for the footer.
  private def broadcast_todos
    Datastar::PubSub.broadcast(TODOS_TOPIC) do |sse|
      # Send all todos - each client will see them according to their own filter
      sse.patch_elements(TodoList.new(STORE.todos))
      # Send updated counts (mode-independent data)
      sse.patch_elements(TodoFooter.new(
        STORE.pending_count,
        STORE.has_completed?,
        FilterMode::All # Footer shows All mode for broadcasts
      ))
    end
  end

  # Serve the main HTML page
  @[ARTA::Get("/")]
  def index : ATH::Response
    datastar_render(TodoPage.new)
  end

  # SSE endpoint - streams initial state and subscribes to updates
  # Multiple browser sessions will all receive updates when any session makes changes
  @[ARTA::Get("/updates")]
  def updates(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      # Subscribe to receive broadcasts from other sessions
      sse.subscribe(TODOS_TOPIC)

      # Send the current todo list (all todos - session starts with All filter)
      sse.patch_elements(TodoList.new(STORE.todos))

      # Send the footer (starting with All mode)
      sse.patch_elements(TodoFooter.new(
        STORE.pending_count,
        STORE.has_completed?,
        FilterMode::All
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
  @[ARTA::Patch("/todos")]
  def add_todo(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      # Get the input signal from the request
      signals = sse.signals
      input = signals["input"]?.try(&.as_s?) || ""

      unless input.empty?
        STORE.add(input)

        # Send updated list to this client
        sse.patch_elements(TodoList.new(STORE.todos))

        # Broadcast update to all connected clients
        broadcast_todos
      end
    end
  end

  # Toggle a specific todo
  @[ARTA::Post("/todos/{id}/toggle")]
  def toggle_todo(request : ATH::Request, id : String) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      STORE.toggle(id)

      # Send updated state to this client (acknowledges the action)
      if todo = STORE.todos.find { |t| t.id == id }
        sse.patch_elements(TodoItem.new(todo))
      end

      # Broadcast update to all connected clients
      broadcast_todos
    end
  end

  # Toggle all todos
  @[ARTA::Post("/todos/toggle-all")]
  def toggle_all(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      STORE.toggle_all

      # Send updated list and footer to this client
      sse.patch_elements(TodoList.new(STORE.todos))
      sse.patch_elements(TodoFooter.new(
        STORE.pending_count,
        STORE.has_completed?,
        FilterMode::All
      ))

      # Broadcast update to all connected clients
      broadcast_todos
    end
  end

  # Delete a specific todo
  @[ARTA::Delete("/todos/{id}")]
  def delete_todo(request : ATH::Request, id : String) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      STORE.remove(id)

      # Send updated list to this client
      sse.patch_elements(TodoList.new(STORE.todos))

      # Broadcast update to all connected clients
      broadcast_todos
    end
  end

  # Delete all completed todos
  @[ARTA::Post("/todos/clear-completed")]
  def clear_completed(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      STORE.remove_completed

      # Send updated list and footer to this client
      sse.patch_elements(TodoList.new(STORE.todos))
      sse.patch_elements(TodoFooter.new(
        STORE.pending_count,
        STORE.has_completed?,
        FilterMode::All
      ))

      # Broadcast update to all connected clients
      broadcast_todos
    end
  end

  # Enter edit mode for a todo
  @[ARTA::Get("/todos/{id}/edit")]
  def edit_todo(request : ATH::Request, id : String) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      if todo = STORE.todos.find { |t| t.id == id }
        sse.patch_elements(TodoItem.new(todo, editing: true))
      end
    end
  end

  # Cancel editing a todo
  @[ARTA::Get("/todos/{id}/cancel")]
  def cancel_edit(request : ATH::Request, id : String) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      if todo = STORE.todos.find { |t| t.id == id }
        sse.patch_elements(TodoItem.new(todo, editing: false))
      end
    end
  end

  # Update a todo's text
  @[ARTA::Patch("/todos/{id}")]
  def update_todo(request : ATH::Request, id : String) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      signals = sse.signals
      # Signal name is dynamic: edit{uuid without hyphens}
      signal_name = "edit#{id.gsub("-", "")}"
      new_text = signals[signal_name]?.try(&.as_s?) || ""

      if todo = STORE.todos.find { |t| t.id == id }
        unless new_text.empty?
          todo.text = new_text
        end

        # Send updated todo to this client (exits edit mode)
        sse.patch_elements(TodoItem.new(todo))

        # Broadcast update to all connected clients
        broadcast_todos
      end
    end
  end

  # Change filter mode (local to this session only - not broadcast)
  @[ARTA::Put("/mode/{mode}")]
  def change_mode(request : ATH::Request, mode : Int32) : ATH::StreamedResponse
    filter_mode = FilterMode.from_value(mode)

    datastar_stream(request) do |sse|
      # Filter is per-session, so just update this client's view
      filtered = case filter_mode
                 when FilterMode::Pending
                   STORE.todos.reject(&.completed)
                 when FilterMode::Completed
                   STORE.todos.select(&.completed)
                 else
                   STORE.todos
                 end

      sse.patch_elements(TodoList.new(filtered))
      sse.patch_elements(TodoFooter.new(
        STORE.pending_count,
        STORE.has_completed?,
        filter_mode
      ))
    end
  end

  # Reset to default todos
  @[ARTA::Put("/reset")]
  def reset(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      STORE.reset_to_defaults

      # Send updated list to this client
      sse.patch_elements(TodoList.new(STORE.todos))

      # Broadcast update to all connected clients
      broadcast_todos
    end
  end
end
