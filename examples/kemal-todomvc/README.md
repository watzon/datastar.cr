# Kemal + Datastar TodoMVC Example

This example demonstrates how to use the Datastar Crystal SDK with the [Kemal](https://kemalcr.com/) web framework and [Blueprint](https://github.com/stephannv/blueprint) HTML builder to create a fully functional TodoMVC application with real-time multi-session synchronization.

## Features Demonstrated

- **SSE Streaming**: Live updates via Server-Sent Events
- **Pub/Sub Synchronization**: Changes sync across all connected browser sessions
- **Blueprint Components**: Type-safe HTML generation with Blueprint
- **Datastar Integration**: Using the Kemal adapter helpers
- **Signal Reading**: Reading reactive signals sent from the browser
- **Full TodoMVC Functionality**: Add, toggle, edit, delete, and filter todos

## Prerequisites

- Crystal >= 1.18.2
- Shards

## Installation

```bash
cd examples/kemal-todomvc
shards install
```

## Running

```bash
shards build
./bin/kemal-todomvc
```

Then open http://localhost:3000 in your browser.

**Multi-session sync:** Open multiple browser tabs to see changes synchronize in real-time across all sessions.

## Project Structure

```
├── src/
│   ├── app.cr                    # Main entry point with all routes
│   ├── store.cr                  # Todo store with thread-safe operations
│   └── components/
│       ├── todo_page.cr          # Full HTML page with Datastar setup
│       ├── todo_list.cr          # Todo list component
│       ├── todo_item.cr          # Individual todo item with edit mode
│       └── todo_footer.cr        # Footer with filters and counts
├── shard.yml
└── README.md
```

## How It Works

### 1. Pub/Sub Configuration

The app configures pub/sub at startup for multi-session synchronization:

```crystal
Datastar::PubSub.configure do |config|
  config.on_subscribe do |topic, conn_id|
    Log.info { "Client #{conn_id[0..7]}... subscribed to #{topic}" }
  end
  config.on_unsubscribe do |topic, conn_id|
    Log.info { "Client #{conn_id[0..7]}... unsubscribed from #{topic}" }
  end
end
```

### 2. SSE Subscription Endpoint

Clients connect to the `/updates` endpoint and subscribe to receive broadcasts:

```crystal
get "/updates" do |env|
  env.datastar_stream do |sse|
    # Subscribe to receive broadcasts
    sse.subscribe(TODOS_TOPIC)

    # Send initial state
    sse.patch_elements(TodoList.new(STORE.todos))
    sse.patch_elements(TodoFooter.new(STORE.pending_count, STORE.has_completed?, FilterMode::All))

    # Keep connection open
    loop do
      sleep 30.seconds
      break if sse.closed?
    end
  end
end
```

### 3. Broadcasting Updates

When a todo is modified, the change is broadcast to all connected clients:

```crystal
post "/todos/:id/toggle" do |env|
  id = env.params.url["id"]

  env.datastar_stream do |sse|
    STORE.toggle(id)

    # Update this client immediately
    if todo = STORE.todos.find { |t| t.id == id }
      sse.patch_elements(TodoItem.new(todo))
    end

    # Broadcast to all subscribed clients
    broadcast_todos
  end
end

def broadcast_todos
  Datastar::PubSub.broadcast(TODOS_TOPIC) do |sse|
    sse.patch_elements(TodoList.new(STORE.todos))
    sse.patch_elements(TodoFooter.new(STORE.pending_count, STORE.has_completed?, FilterMode::All))
  end
end
```

### 4. Blueprint Components with Datastar Attributes

Blueprint components use quoted keys for Datastar's colon-based attributes:

```crystal
class TodoItem
  include Blueprint::HTML

  def initialize(@todo : Todo, @editing : Bool = false); end

  private def blueprint
    li id: "todo-#{@todo.id}", class: build_class do
      div class: "view" do
        input class: "toggle",
              type: "checkbox",
              checked: @todo.completed,
              "data-on:change": "@post('/todos/#{@todo.id}/toggle')"

        label "data-on:dblclick": "@get('/todos/#{@todo.id}/edit')" do
          plain @todo.text
        end

        button class: "destroy",
               "data-on:click": "@delete('/todos/#{@todo.id}')"
      end
    end
  end
end
```

### 5. Reading Signals from the Browser

The controller reads signals sent from the browser:

```crystal
patch "/todos" do |env|
  env.datastar_stream do |sse|
    signals = sse.signals
    input = signals["input"]?.try(&.as_s?) || ""

    unless input.empty?
      STORE.add(input)
      sse.patch_elements(TodoList.new(STORE.todos))
      broadcast_todos
    end
  end
end
```

### 6. Kemal Adapter Helpers

The Kemal adapter provides several convenience methods on `env`:

- `env.datastar_stream { |sse| ... }` - Create an SSE streaming response
- `env.datastar_render(fragment)` - Render HTML (string or Blueprint component)
- `env.datastar_request?` - Check if request came from Datastar
- `env.datastar_broadcast(topic) { |sse| ... }` - Broadcast to subscribers

## License

MIT
