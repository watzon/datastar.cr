# PubSub Multi-Session Sync Design

## Overview

Add topic-based pub/sub to datastar.cr, enabling real-time synchronization across multiple browser sessions. When one client makes a change, all clients subscribed to the same topic receive updates automatically.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Scope | Topic-based channels | Matches real-world use cases, efficient, global broadcast is just a special case |
| Backend | Pluggable with in-memory default | Zero dependencies for simple cases, scalable to Redis/NATS for multi-server |
| Subscribe API | Explicit in route handler | Maximum flexibility, clear security control |
| Broadcast API | Singleton + injectable | Convenient for Kemal, testable for Athena |
| Broadcast block | Same SSE generator API | Consistency with existing streaming API |
| Connection lifecycle | Automatic cleanup + callbacks | Handles common case, enables presence features |
| Backend interface | Two-layer (Backend + Manager) | Separates transport from connection tracking |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Public API                              │
│  Datastar::PubSub.broadcast(topic) { |sse| ... }            │
│  Datastar::PubSub::Broadcaster (injectable)                 │
└─────────────────────────────────┬───────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────┐
│                        Manager                               │
│  - Tracks local connections per topic                        │
│  - Routes incoming broadcasts to connections                 │
│  - Handles subscribe/unsubscribe lifecycle                   │
│  - Fires callbacks (on_subscribe, on_unsubscribe)           │
└─────────────────────────────────┬───────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────┐
│                    Backend (abstract)                        │
│  ├── MemoryBackend (default, single-server)                 │
│  └── RedisBackend (future, multi-server)                    │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

**Broadcast:**
```
Controller calls broadcast("todos:123")
    ↓
Broadcaster captures events from block into EventCollector
    ↓
Manager.broadcast(topic, serialized_events)
    ↓
Backend.publish (for distributed: sends to Redis/NATS)
    ↓
Backend.subscribe callback fires (on all servers)
    ↓
Manager.deliver routes to local subscribed connections
    ↓
Events written to each connection's output channel
```

**Subscribe:**
```
Client connects to /subscribe/:list_id
    ↓
Handler calls sse.subscribe("todos:123")
    ↓
Connection wrapper created, registered with Manager
    ↓
Manager subscribes to Backend (if first local subscriber)
    ↓
on_subscribe callback fires
    ↓
Connection stays open, broadcasts arrive via output channel
```

## Component Interfaces

### Backend (Abstract)

```crystal
module Datastar::PubSub
  abstract class Backend
    # Publish serialized events to a topic
    abstract def publish(topic : String, payload : String) : Nil

    # Subscribe to receive messages from other servers
    # Returns subscription ID for unsubscribing
    abstract def subscribe(topic : String, &block : String ->) : String

    # Unsubscribe from external messages
    abstract def unsubscribe(subscription_id : String) : Nil

    # Called on shutdown for cleanup
    def close : Nil
    end

    # Optional error callback for backends
    property on_error : Proc(Exception, Nil)?
  end
end
```

### MemoryBackend

```crystal
class Datastar::PubSub::MemoryBackend < Backend
  @mutex : Mutex
  @subscriptions : Hash(String, Hash(String, Proc(String, Nil)))

  def publish(topic : String, payload : String) : Nil
    @mutex.synchronize do
      @subscriptions[topic]?.try &.each_value(&.call(payload))
    end
  end

  def subscribe(topic : String, &block : String ->) : String
    id = UUID.random.to_s
    @mutex.synchronize do
      @subscriptions[topic] ||= {} of String => Proc(String, Nil)
      @subscriptions[topic][id] = block
    end
    id
  end

  def unsubscribe(subscription_id : String) : Nil
    @mutex.synchronize do
      @subscriptions.each_value(&.delete(subscription_id))
    end
  end
end
```

### Connection

```crystal
module Datastar::PubSub
  class Connection
    getter id : String
    getter output_channel : Channel(String)

    def initialize(@id : String, @output_channel : Channel(String))
    end
  end
end
```

### Manager

```crystal
module Datastar::PubSub
  class Manager
    @backend : Backend
    @mutex : Mutex
    @local_connections : Hash(String, Set(Connection))
    @connection_topics : Hash(String, Set(String))
    @backend_subscriptions : Hash(String, String)

    property on_subscribe : Proc(String, String, Nil)?
    property on_unsubscribe : Proc(String, String, Nil)?

    def initialize(@backend : Backend)
      @mutex = Mutex.new
      @local_connections = Hash(String, Set(Connection)).new
      @connection_topics = Hash(String, Set(String)).new
      @backend_subscriptions = Hash(String, String).new
    end

    def subscribe(topic : String, connection : Connection) : Nil
      @mutex.synchronize do
        @local_connections[topic] ||= Set(Connection).new
        @local_connections[topic] << connection
        @connection_topics[connection.id] ||= Set(String).new
        @connection_topics[connection.id] << topic

        # Subscribe to backend if first local subscriber
        if @local_connections[topic].size == 1
          sub_id = @backend.subscribe(topic) { |payload| deliver(topic, payload) }
          @backend_subscriptions[topic] = sub_id
        end
      end

      @on_subscribe.try &.call(topic, connection.id)
    end

    def unsubscribe_all(connection : Connection) : Nil
      topics = @mutex.synchronize do
        @connection_topics.delete(connection.id) || Set(String).new
      end

      topics.each do |topic|
        @mutex.synchronize do
          @local_connections[topic]?.try &.delete(connection)

          # Unsubscribe from backend if last local subscriber
          if @local_connections[topic]?.try(&.empty?)
            @local_connections.delete(topic)
            if sub_id = @backend_subscriptions.delete(topic)
              @backend.unsubscribe(sub_id)
            end
          end
        end

        @on_unsubscribe.try &.call(topic, connection.id)
      end
    end

    def broadcast(topic : String, payload : String) : Nil
      @backend.publish(topic, payload)
    end

    private def deliver(topic : String, payload : String) : Nil
      connections = @mutex.synchronize do
        @local_connections[topic]?.try(&.dup) || Set(Connection).new
      end

      connections.each do |conn|
        begin
          conn.output_channel.send(payload)
        rescue Channel::ClosedError
          # Connection already closed, cleanup will happen via stream's ensure block
        end
      end
    end
  end
end
```

### EventCollector

```crystal
module Datastar::PubSub
  # Collects events without writing to IO
  class EventCollector
    @events : Array(ServerSentEvent)

    def initialize
      @events = [] of ServerSentEvent
    end

    def patch_elements(selector : String, elements : String, **options) : Nil
      @events << ServerSentEvent.new(
        event_type: EventType::PatchElements,
        data: # ... build data lines
      )
    end

    def patch_signals(signals : Hash | NamedTuple, **options) : Nil
      @events << ServerSentEvent.new(
        event_type: EventType::PatchSignals,
        data: # ... build data lines
      )
    end

    def execute_script(script : String, **options) : Nil
      @events << ServerSentEvent.new(
        event_type: EventType::ExecuteScript,
        data: # ... build data lines
      )
    end

    def to_payload : String
      @events.map(&.to_s).join
    end
  end
end
```

### Public API

```crystal
module Datastar::PubSub
  class_property manager : Manager?

  class Configuration
    property backend : Backend = MemoryBackend.new
    property on_subscribe : Proc(String, String, Nil)?
    property on_unsubscribe : Proc(String, String, Nil)?
  end

  def self.configure(&block : Configuration ->) : Nil
    config = Configuration.new
    yield config
    mgr = Manager.new(config.backend)
    mgr.on_subscribe = config.on_subscribe
    mgr.on_unsubscribe = config.on_unsubscribe
    @@manager = mgr
  end

  def self.configure(backend : Backend = MemoryBackend.new) : Nil
    @@manager = Manager.new(backend)
  end

  def self.manager! : Manager
    @@manager || raise "Datastar::PubSub not configured. Call Datastar::PubSub.configure first."
  end

  def self.broadcast(topic : String, &block : EventCollector ->) : Nil
    collector = EventCollector.new
    yield collector
    manager!.broadcast(topic, collector.to_payload)
  end

  # Injectable broadcaster for DI frameworks
  class Broadcaster
    def initialize(@manager : Manager = PubSub.manager!)
    end

    def broadcast(topic : String, &block : EventCollector ->) : Nil
      collector = EventCollector.new
      yield collector
      @manager.broadcast(topic, collector.to_payload)
    end
  end
end
```

### EventStream Integration

```crystal
class Datastar::EventStream
  @pubsub_connection : PubSub::Connection?

  def subscribe(topic : String) : Nil
    @pubsub_connection ||= PubSub::Connection.new(
      id: UUID.random.to_s,
      output_channel: @output_channel
    )

    PubSub.manager!.subscribe(topic, @pubsub_connection.not_nil!)
  end

  # Updated stream method with cleanup
  def stream(&block) : Nil
    spawn do
      begin
        yield self
      ensure
        if conn = @pubsub_connection
          PubSub.manager!.unsubscribe_all(conn)
        end
      end
    end

    run_output_loop
  end
end
```

## Usage Examples

### Kemal

```crystal
require "datastar"
require "datastar/adapters/kemal"

# Configure at startup
Datastar::PubSub.configure do |config|
  config.backend = Datastar::PubSub::MemoryBackend.new
  config.on_subscribe do |topic, conn_id|
    Log.info { "Client #{conn_id} subscribed to #{topic}" }
  end
end

# Subscribe endpoint
get "/subscribe/:list_id" do |env|
  list_id = env.params.url["list_id"]

  env.datastar_stream do |sse|
    sse.subscribe("todos:#{list_id}")
    sse.patch_elements("#todo-list", render_todos(list_id))
    # Connection stays open, broadcasts arrive automatically
  end
end

# Create todo - broadcasts to all subscribers
post "/todos/:list_id" do |env|
  list_id = env.params.url["list_id"]
  todo = create_todo(env.params.json)

  Datastar::PubSub.broadcast("todos:#{list_id}") do |sse|
    sse.patch_elements("#todo-list", render_todos(list_id))
  end

  env.response.status_code = 201
end
```

### Athena

```crystal
require "datastar"
require "datastar/adapters/athena"

# Register broadcaster as service
@[ADI::Register]
class Datastar::PubSub::Broadcaster
end

class TodoController < ATH::Controller
  include Datastar::Athena::Controller

  def initialize(@pubsub : Datastar::PubSub::Broadcaster)
  end

  @[ARTA::Get("/subscribe/:list_id")]
  def subscribe(list_id : String, request : ATH::Request) : ATH::Response
    datastar(request) do |sse|
      sse.subscribe("todos:#{list_id}")
      sse.patch_elements("#todo-list", render_todos(list_id))
    end
  end

  @[ARTA::Post("/todos/:list_id")]
  def create(list_id : String, request : ATH::Request) : ATH::Response
    todo = create_todo(request)

    @pubsub.broadcast("todos:#{list_id}") do |sse|
      sse.patch_elements("#todo-list", render_todos(list_id))
    end

    ATH::Response.new(status: :created)
  end
end
```

### Client-Side HTML

```html
<div id="todo-app"
     data-signals="{todos: []}"
     data-init="@get('/subscribe/my-list-id')">

  <ul id="todo-list">
    <!-- Populated by SSE -->
  </ul>

  <form data-on:submit__prevent="@post('/todos/my-list-id')">
    <input data-bind:newTodo type="text" />
    <button type="submit">Add Todo</button>
  </form>
</div>
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Broadcast to empty topic | No-op, silently discards (fire-and-forget) |
| Connection dies mid-broadcast | Catches `Channel::ClosedError`, skips that connection |
| Backend failure (Redis down) | Invokes `backend.on_error` callback, broadcast fails silently |
| Subscribe before configured | Raises descriptive error |
| Duplicate subscribe to same topic | Idempotent, connection only added once |

## Future: Redis Backend

```crystal
class Datastar::PubSub::RedisBackend < Backend
  def initialize(@redis : Redis::PooledClient)
    @subscriptions = Hash(String, Fiber).new
  end

  def publish(topic : String, payload : String) : Nil
    @redis.publish("datastar:#{topic}", payload)
  rescue ex
    @on_error.try &.call(ex)
  end

  def subscribe(topic : String, &block : String ->) : String
    id = UUID.random.to_s
    @subscriptions[id] = spawn do
      @redis.subscribe("datastar:#{topic}") do |on|
        on.message { |_, msg| block.call(msg) }
      end
    end
    id
  end

  def unsubscribe(subscription_id : String) : Nil
    # Cancel the subscription fiber
  end
end
```

## File Structure

```
src/datastar/
├── pubsub/
│   ├── pubsub.cr          # Main module, configure, broadcast
│   ├── backend.cr         # Abstract Backend class
│   ├── memory_backend.cr  # In-memory implementation
│   ├── manager.cr         # Connection tracking, routing
│   ├── connection.cr      # Connection wrapper
│   ├── event_collector.cr # Event capture for broadcasts
│   ├── broadcaster.cr     # Injectable broadcaster class
│   └── configuration.cr   # Configuration class
├── event_stream.cr        # Add subscribe method
└── ...
```

## Testing Strategy

1. **Unit tests for MemoryBackend** - publish/subscribe/unsubscribe work correctly
2. **Unit tests for Manager** - connection tracking, cleanup, callbacks
3. **Unit tests for EventCollector** - captures events correctly
4. **Integration tests** - full flow from subscribe to broadcast to delivery
5. **Concurrency tests** - multiple connections, simultaneous broadcasts
