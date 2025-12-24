# PubSub Multi-Session Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add topic-based pub/sub to datastar.cr, enabling real-time synchronization across multiple browser sessions.

**Architecture:** Pluggable backend system with in-memory default. Manager tracks local connections per topic and routes broadcasts. EventStream gains `subscribe` method that integrates with pub/sub system.

**Tech Stack:** Crystal, existing Datastar SSE infrastructure, Crystal's Channel and Mutex for concurrency.

**Design Doc:** See `docs/plans/2025-12-24-pubsub-multi-session-sync-design.md` for full design details.

---

## Task 1: Create Connection Wrapper

**Files:**
- Create: `src/datastar/pubsub/connection.cr`
- Test: `spec/datastar/pubsub/connection_spec.cr`

**Step 1: Write the failing test**

Create `spec/datastar/pubsub/connection_spec.cr`:

```crystal
require "../../spec_helper"

describe Datastar::PubSub::Connection do
  it "stores id and output channel" do
    channel = Channel(String).new(10)
    conn = Datastar::PubSub::Connection.new("conn-123", channel)

    conn.id.should eq "conn-123"
    conn.output_channel.should eq channel
  end

  it "generates unique id when not provided" do
    channel = Channel(String).new(10)
    conn1 = Datastar::PubSub::Connection.new(channel)
    conn2 = Datastar::PubSub::Connection.new(channel)

    conn1.id.should_not eq conn2.id
    conn1.id.should_not be_empty
  end

  it "can send messages through output channel" do
    channel = Channel(String).new(10)
    conn = Datastar::PubSub::Connection.new("test", channel)

    conn.send("hello")
    channel.receive.should eq "hello"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/pubsub/connection_spec.cr`
Expected: FAIL - file not found or Connection not defined

**Step 3: Write minimal implementation**

Create `src/datastar/pubsub/connection.cr`:

```crystal
require "uuid"

module Datastar::PubSub
  # Wraps a client connection for pub/sub tracking.
  # Holds reference to the output channel for sending broadcasts.
  class Connection
    getter id : String
    getter output_channel : Channel(String)

    def initialize(@id : String, @output_channel : Channel(String))
    end

    def initialize(@output_channel : Channel(String))
      @id = UUID.random.to_s
    end

    # Sends a message to this connection's output channel.
    # Raises Channel::ClosedError if the channel is closed.
    def send(message : String) : Nil
      @output_channel.send(message)
    end
  end
end
```

**Step 4: Update spec_helper to require pubsub**

Add to `spec/spec_helper.cr` after the require:

```crystal
require "../src/datastar/pubsub/connection"
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/pubsub/connection_spec.cr`
Expected: PASS (3 examples, 0 failures)

**Step 6: Commit**

```bash
git add src/datastar/pubsub/connection.cr spec/datastar/pubsub/connection_spec.cr spec/spec_helper.cr
git commit -m "feat(pubsub): add Connection wrapper class"
```

---

## Task 2: Create Abstract Backend Interface

**Files:**
- Create: `src/datastar/pubsub/backend.cr`
- Test: `spec/datastar/pubsub/backend_spec.cr`

**Step 1: Write the failing test**

Create `spec/datastar/pubsub/backend_spec.cr`:

```crystal
require "../../spec_helper"

# Test implementation to verify abstract class works
class TestBackend < Datastar::PubSub::Backend
  getter published : Array(Tuple(String, String)) = [] of Tuple(String, String)
  getter subscriptions : Hash(String, Proc(String, Nil)) = {} of String => Proc(String, Nil)

  def publish(topic : String, payload : String) : Nil
    @published << {topic, payload}
    @subscriptions[topic]?.try &.call(payload)
  end

  def subscribe(topic : String, &block : String ->) : String
    id = "sub-#{@subscriptions.size}"
    @subscriptions[topic] = block
    id
  end

  def unsubscribe(subscription_id : String) : Nil
    # Simple implementation for test
  end
end

describe Datastar::PubSub::Backend do
  it "can be subclassed and used" do
    backend = TestBackend.new

    received = [] of String
    backend.subscribe("test") { |msg| received << msg }
    backend.publish("test", "hello")

    backend.published.should eq [{"test", "hello"}]
    received.should eq ["hello"]
  end

  it "supports on_error callback" do
    backend = TestBackend.new
    errors = [] of Exception

    backend.on_error = ->(ex : Exception) { errors << ex; nil }
    backend.on_error.should_not be_nil
  end

  it "close is a no-op by default" do
    backend = TestBackend.new
    backend.close # Should not raise
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/pubsub/backend_spec.cr`
Expected: FAIL - Backend not defined

**Step 3: Write minimal implementation**

Create `src/datastar/pubsub/backend.cr`:

```crystal
module Datastar::PubSub
  # Abstract base class for pub/sub backends.
  #
  # Backends handle message transport between servers. For single-server
  # deployments, use `MemoryBackend`. For multi-server, implement a
  # backend using Redis, NATS, or similar.
  abstract class Backend
    # Optional callback for error handling in backends.
    property on_error : Proc(Exception, Nil)?

    # Publishes a message to a topic.
    # For distributed backends, this sends to the external system.
    abstract def publish(topic : String, payload : String) : Nil

    # Subscribes to receive messages on a topic.
    # The block is called when a message arrives.
    # Returns a subscription ID for later unsubscribing.
    abstract def subscribe(topic : String, &block : String ->) : String

    # Unsubscribes from a topic using the subscription ID.
    abstract def unsubscribe(subscription_id : String) : Nil

    # Called on shutdown for cleanup. Override if needed.
    def close : Nil
    end
  end
end
```

**Step 4: Update spec_helper**

Add to `spec/spec_helper.cr`:

```crystal
require "../src/datastar/pubsub/backend"
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/pubsub/backend_spec.cr`
Expected: PASS (3 examples, 0 failures)

**Step 6: Commit**

```bash
git add src/datastar/pubsub/backend.cr spec/datastar/pubsub/backend_spec.cr spec/spec_helper.cr
git commit -m "feat(pubsub): add abstract Backend class"
```

---

## Task 3: Implement MemoryBackend

**Files:**
- Create: `src/datastar/pubsub/memory_backend.cr`
- Test: `spec/datastar/pubsub/memory_backend_spec.cr`

**Step 1: Write the failing test**

Create `spec/datastar/pubsub/memory_backend_spec.cr`:

```crystal
require "../../spec_helper"

describe Datastar::PubSub::MemoryBackend do
  describe "#publish and #subscribe" do
    it "delivers messages to subscribers" do
      backend = Datastar::PubSub::MemoryBackend.new
      received = [] of String

      backend.subscribe("topic1") { |msg| received << msg }
      backend.publish("topic1", "hello")
      backend.publish("topic1", "world")

      received.should eq ["hello", "world"]
    end

    it "only delivers to matching topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      received1 = [] of String
      received2 = [] of String

      backend.subscribe("topic1") { |msg| received1 << msg }
      backend.subscribe("topic2") { |msg| received2 << msg }

      backend.publish("topic1", "for-1")
      backend.publish("topic2", "for-2")

      received1.should eq ["for-1"]
      received2.should eq ["for-2"]
    end

    it "supports multiple subscribers per topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      received1 = [] of String
      received2 = [] of String

      backend.subscribe("topic") { |msg| received1 << msg }
      backend.subscribe("topic") { |msg| received2 << msg }

      backend.publish("topic", "broadcast")

      received1.should eq ["broadcast"]
      received2.should eq ["broadcast"]
    end

    it "handles publish to empty topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      # Should not raise
      backend.publish("empty", "message")
    end
  end

  describe "#unsubscribe" do
    it "stops delivering messages after unsubscribe" do
      backend = Datastar::PubSub::MemoryBackend.new
      received = [] of String

      sub_id = backend.subscribe("topic") { |msg| received << msg }
      backend.publish("topic", "before")

      backend.unsubscribe(sub_id)
      backend.publish("topic", "after")

      received.should eq ["before"]
    end

    it "handles unsubscribe of unknown id" do
      backend = Datastar::PubSub::MemoryBackend.new
      # Should not raise
      backend.unsubscribe("unknown-id")
    end
  end

  describe "#close" do
    it "clears all subscriptions" do
      backend = Datastar::PubSub::MemoryBackend.new
      received = [] of String

      backend.subscribe("topic") { |msg| received << msg }
      backend.close
      backend.publish("topic", "after-close")

      received.should be_empty
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/pubsub/memory_backend_spec.cr`
Expected: FAIL - MemoryBackend not defined

**Step 3: Write minimal implementation**

Create `src/datastar/pubsub/memory_backend.cr`:

```crystal
require "uuid"
require "./backend"

module Datastar::PubSub
  # In-memory pub/sub backend for single-server deployments.
  #
  # Messages are delivered synchronously within the same process.
  # For multi-server deployments, use a distributed backend like Redis.
  class MemoryBackend < Backend
    @mutex : Mutex
    @subscriptions : Hash(String, Hash(String, Proc(String, Nil)))

    def initialize
      @mutex = Mutex.new
      @subscriptions = Hash(String, Hash(String, Proc(String, Nil))).new
    end

    def publish(topic : String, payload : String) : Nil
      subscribers = @mutex.synchronize do
        @subscriptions[topic]?.try(&.values.dup)
      end

      subscribers.try &.each do |callback|
        begin
          callback.call(payload)
        rescue ex
          @on_error.try &.call(ex)
        end
      end
    end

    def subscribe(topic : String, &block : String ->) : String
      id = UUID.random.to_s

      @mutex.synchronize do
        @subscriptions[topic] ||= Hash(String, Proc(String, Nil)).new
        @subscriptions[topic][id] = block
      end

      id
    end

    def unsubscribe(subscription_id : String) : Nil
      @mutex.synchronize do
        @subscriptions.each_value do |topic_subs|
          topic_subs.delete(subscription_id)
        end
      end
    end

    def close : Nil
      @mutex.synchronize do
        @subscriptions.clear
      end
    end
  end
end
```

**Step 4: Update spec_helper**

Add to `spec/spec_helper.cr`:

```crystal
require "../src/datastar/pubsub/memory_backend"
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/pubsub/memory_backend_spec.cr`
Expected: PASS (8 examples, 0 failures)

**Step 6: Commit**

```bash
git add src/datastar/pubsub/memory_backend.cr spec/datastar/pubsub/memory_backend_spec.cr spec/spec_helper.cr
git commit -m "feat(pubsub): add MemoryBackend implementation"
```

---

## Task 4: Create Manager for Connection Tracking

**Files:**
- Create: `src/datastar/pubsub/manager.cr`
- Test: `spec/datastar/pubsub/manager_spec.cr`

**Step 1: Write the failing test**

Create `spec/datastar/pubsub/manager_spec.cr`:

```crystal
require "../../spec_helper"

describe Datastar::PubSub::Manager do
  describe "#subscribe" do
    it "registers a connection for a topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)

      manager.subscribe("topic1", conn)

      # Verify by broadcasting - connection should receive
      manager.broadcast("topic1", "hello")
      channel.receive.should eq "hello"
    end

    it "supports multiple connections per topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel1 = Channel(String).new(10)
      channel2 = Channel(String).new(10)
      conn1 = Datastar::PubSub::Connection.new(channel1)
      conn2 = Datastar::PubSub::Connection.new(channel2)

      manager.subscribe("topic", conn1)
      manager.subscribe("topic", conn2)
      manager.broadcast("topic", "broadcast")

      channel1.receive.should eq "broadcast"
      channel2.receive.should eq "broadcast"
    end

    it "fires on_subscribe callback" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      events = [] of Tuple(String, String)
      manager.on_subscribe = ->(topic : String, conn_id : String) {
        events << {topic, conn_id}
        nil
      }

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new("conn-1", channel)
      manager.subscribe("my-topic", conn)

      events.should eq [{"my-topic", "conn-1"}]
    end
  end

  describe "#unsubscribe_all" do
    it "removes connection from all topics" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)

      manager.subscribe("topic1", conn)
      manager.subscribe("topic2", conn)
      manager.unsubscribe_all(conn)

      # Broadcasts should not be received
      manager.broadcast("topic1", "msg1")
      manager.broadcast("topic2", "msg2")

      select
      when msg = channel.receive
        fail "Should not receive: #{msg}"
      when timeout(10.milliseconds)
        # Expected - no message received
      end
    end

    it "fires on_unsubscribe callback for each topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      events = [] of Tuple(String, String)
      manager.on_unsubscribe = ->(topic : String, conn_id : String) {
        events << {topic, conn_id}
        nil
      }

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new("conn-1", channel)

      manager.subscribe("topic1", conn)
      manager.subscribe("topic2", conn)
      manager.unsubscribe_all(conn)

      events.size.should eq 2
      events.should contain({"topic1", "conn-1"})
      events.should contain({"topic2", "conn-1"})
    end
  end

  describe "#broadcast" do
    it "delivers to all subscribers of a topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel1 = Channel(String).new(10)
      channel2 = Channel(String).new(10)
      conn1 = Datastar::PubSub::Connection.new(channel1)
      conn2 = Datastar::PubSub::Connection.new(channel2)

      manager.subscribe("room", conn1)
      manager.subscribe("room", conn2)
      manager.broadcast("room", "hello everyone")

      channel1.receive.should eq "hello everyone"
      channel2.receive.should eq "hello everyone"
    end

    it "handles broadcast to empty topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      # Should not raise
      manager.broadcast("empty", "message")
    end

    it "handles closed channels gracefully" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)

      manager.subscribe("topic", conn)
      channel.close

      # Should not raise
      manager.broadcast("topic", "message")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/pubsub/manager_spec.cr`
Expected: FAIL - Manager not defined

**Step 3: Write minimal implementation**

Create `src/datastar/pubsub/manager.cr`:

```crystal
require "./backend"
require "./connection"

module Datastar::PubSub
  # Manages local connections and coordinates with the backend.
  #
  # Tracks which connections are subscribed to which topics,
  # routes incoming broadcasts to appropriate connections,
  # and handles connection cleanup.
  class Manager
    @backend : Backend
    @mutex : Mutex

    # topic => Set of local Connection objects
    @local_connections : Hash(String, Set(Connection))

    # connection_id => Set of topics (for cleanup)
    @connection_topics : Hash(String, Set(String))

    # backend subscription IDs per topic
    @backend_subscriptions : Hash(String, String)

    # Lifecycle callbacks
    property on_subscribe : Proc(String, String, Nil)?
    property on_unsubscribe : Proc(String, String, Nil)?

    def initialize(@backend : Backend)
      @mutex = Mutex.new
      @local_connections = Hash(String, Set(Connection)).new
      @connection_topics = Hash(String, Set(String)).new
      @backend_subscriptions = Hash(String, String).new
    end

    # Subscribes a connection to a topic.
    def subscribe(topic : String, connection : Connection) : Nil
      first_subscriber = false

      @mutex.synchronize do
        @local_connections[topic] ||= Set(Connection).new
        @local_connections[topic] << connection

        @connection_topics[connection.id] ||= Set(String).new
        @connection_topics[connection.id] << topic

        # Subscribe to backend if first local subscriber for this topic
        if @local_connections[topic].size == 1
          first_subscriber = true
        end
      end

      if first_subscriber
        sub_id = @backend.subscribe(topic) { |payload| deliver(topic, payload) }
        @mutex.synchronize do
          @backend_subscriptions[topic] = sub_id
        end
      end

      @on_subscribe.try &.call(topic, connection.id)
    end

    # Unsubscribes a connection from all topics.
    def unsubscribe_all(connection : Connection) : Nil
      topics = @mutex.synchronize do
        @connection_topics.delete(connection.id) || Set(String).new
      end

      topics.each do |topic|
        last_subscriber = false

        @mutex.synchronize do
          @local_connections[topic]?.try &.delete(connection)

          # Check if this was the last local subscriber
          if @local_connections[topic]?.try(&.empty?)
            @local_connections.delete(topic)
            last_subscriber = true
          end
        end

        # Unsubscribe from backend if last local subscriber
        if last_subscriber
          if sub_id = @mutex.synchronize { @backend_subscriptions.delete(topic) }
            @backend.unsubscribe(sub_id)
          end
        end

        @on_unsubscribe.try &.call(topic, connection.id)
      end
    end

    # Broadcasts a message to all subscribers of a topic.
    def broadcast(topic : String, payload : String) : Nil
      @backend.publish(topic, payload)
    end

    # Delivers a message to all local connections subscribed to a topic.
    private def deliver(topic : String, payload : String) : Nil
      connections = @mutex.synchronize do
        @local_connections[topic]?.try(&.dup) || Set(Connection).new
      end

      connections.each do |conn|
        begin
          conn.send(payload)
        rescue Channel::ClosedError
          # Connection already closed, will be cleaned up by stream's ensure block
        end
      end
    end
  end
end
```

**Step 4: Update spec_helper**

Add to `spec/spec_helper.cr`:

```crystal
require "../src/datastar/pubsub/manager"
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/pubsub/manager_spec.cr`
Expected: PASS (9 examples, 0 failures)

**Step 6: Commit**

```bash
git add src/datastar/pubsub/manager.cr spec/datastar/pubsub/manager_spec.cr spec/spec_helper.cr
git commit -m "feat(pubsub): add Manager for connection tracking"
```

---

## Task 5: Create EventCollector for Broadcast Blocks

**Files:**
- Create: `src/datastar/pubsub/event_collector.cr`
- Test: `spec/datastar/pubsub/event_collector_spec.cr`

**Step 1: Write the failing test**

Create `spec/datastar/pubsub/event_collector_spec.cr`:

```crystal
require "../../spec_helper"

describe Datastar::PubSub::EventCollector do
  describe "#patch_elements" do
    it "collects patch_elements events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_elements(%(<div id="test">Hello</div>))

      payload = collector.to_payload
      payload.should contain "event: datastar-patch-elements"
      payload.should contain "data: elements <div id=\"test\">Hello</div>"
    end

    it "supports selector option" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_elements("<p>Text</p>", selector: "#container")

      payload = collector.to_payload
      payload.should contain "data: selector #container"
    end
  end

  describe "#patch_signals" do
    it "collects patch_signals events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_signals({count: 5, name: "test"})

      payload = collector.to_payload
      payload.should contain "event: datastar-patch-signals"
      payload.should contain "count"
      payload.should contain "5"
    end

    it "supports named tuple syntax" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_signals(foo: "bar")

      payload = collector.to_payload
      payload.should contain "foo"
      payload.should contain "bar"
    end
  end

  describe "#execute_script" do
    it "collects execute_script events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.execute_script("console.log('hello')")

      payload = collector.to_payload
      payload.should contain "event: datastar-execute-script"
      payload.should contain "console.log"
    end
  end

  describe "#remove_elements" do
    it "collects remove_elements events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.remove_elements("#old-element")

      payload = collector.to_payload
      payload.should contain "event: datastar-patch-elements"
      payload.should contain "data: selector #old-element"
      payload.should contain "data: mode remove"
    end
  end

  describe "#to_payload" do
    it "concatenates multiple events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_elements("<div>1</div>")
      collector.patch_signals(count: 1)

      payload = collector.to_payload
      payload.should contain "datastar-patch-elements"
      payload.should contain "datastar-patch-signals"
    end

    it "returns empty string when no events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.to_payload.should eq ""
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/pubsub/event_collector_spec.cr`
Expected: FAIL - EventCollector not defined

**Step 3: Write minimal implementation**

Create `src/datastar/pubsub/event_collector.cr`:

```crystal
require "json"
require "../consts"
require "../server_sent_event"

module Datastar::PubSub
  # Collects SSE events without writing to IO.
  #
  # Used by broadcast blocks to capture events that will
  # be serialized and sent to all subscribed connections.
  class EventCollector
    @events : Array(ServerSentEvent)

    def initialize
      @events = [] of ServerSentEvent
    end

    # Patches elements into the DOM.
    def patch_elements(
      fragment : String,
      *,
      selector : String = WHOLE_DOCUMENT_SELECTOR,
      mode : FragmentMergeMode = DEFAULT_FRAGMENT_MERGE_MODE,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION
    ) : Nil
      data_lines = [] of String

      unless selector.empty?
        data_lines << "selector #{selector}"
      end

      if mode != DEFAULT_FRAGMENT_MERGE_MODE
        data_lines << "mode #{mode.to_s.downcase}"
      end

      if use_view_transition
        data_lines << "useViewTransition true"
      end

      fragment.each_line do |line|
        data_lines << "elements #{line}"
      end

      @events << ServerSentEvent.new(
        event_type: EventType::PatchElements,
        data_lines: data_lines
      )
    end

    # Removes elements from the DOM.
    def remove_elements(
      selector : String,
      *,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION
    ) : Nil
      data_lines = ["selector #{selector}", "mode remove"]

      if use_view_transition
        data_lines.insert(1, "useViewTransition true")
      end

      @events << ServerSentEvent.new(
        event_type: EventType::PatchElements,
        data_lines: data_lines
      )
    end

    # Patches signals (reactive state) in the browser.
    def patch_signals(**signals) : Nil
      patch_signals(signals, only_if_missing: DEFAULT_SIGNALS_ONLY_IF_MISSING)
    end

    # :ditto:
    def patch_signals(
      signals : Hash | NamedTuple,
      *,
      only_if_missing : Bool = DEFAULT_SIGNALS_ONLY_IF_MISSING
    ) : Nil
      data_lines = [] of String

      if only_if_missing
        data_lines << "onlyIfMissing true"
      end

      data_lines << "signals #{signals.to_json}"

      @events << ServerSentEvent.new(
        event_type: EventType::PatchSignals,
        data_lines: data_lines
      )
    end

    # Executes JavaScript in the browser.
    def execute_script(
      script : String,
      *,
      auto_remove : Bool = DEFAULT_AUTOREMOVE_SCRIPT,
      attributes : Hash(String, String) = {} of String => String
    ) : Nil
      data_lines = [] of String

      if auto_remove
        data_lines << "autoRemove true"
      end

      attributes.each do |key, value|
        data_lines << "attributes #{key} #{value}"
      end

      data_lines << "script #{script}"

      @events << ServerSentEvent.new(
        event_type: EventType::ExecuteScript,
        data_lines: data_lines
      )
    end

    # Serializes all collected events to a payload string.
    def to_payload : String
      @events.map(&.to_s).join
    end
  end
end
```

**Step 4: Update spec_helper**

Add to `spec/spec_helper.cr`:

```crystal
require "../src/datastar/pubsub/event_collector"
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/pubsub/event_collector_spec.cr`
Expected: PASS (8 examples, 0 failures)

**Step 6: Commit**

```bash
git add src/datastar/pubsub/event_collector.cr spec/datastar/pubsub/event_collector_spec.cr spec/spec_helper.cr
git commit -m "feat(pubsub): add EventCollector for broadcast blocks"
```

---

## Task 6: Create Main PubSub Module with Configuration

**Files:**
- Create: `src/datastar/pubsub/pubsub.cr`
- Test: `spec/datastar/pubsub/pubsub_spec.cr`

**Step 1: Write the failing test**

Create `spec/datastar/pubsub/pubsub_spec.cr`:

```crystal
require "../../spec_helper"

describe Datastar::PubSub do
  # Reset manager after each test
  after_each do
    Datastar::PubSub.reset!
  end

  describe ".configure" do
    it "sets up manager with default backend" do
      Datastar::PubSub.configure
      Datastar::PubSub.manager!.should_not be_nil
    end

    it "accepts custom backend" do
      backend = Datastar::PubSub::MemoryBackend.new
      Datastar::PubSub.configure(backend: backend)
      Datastar::PubSub.manager!.should_not be_nil
    end

    it "accepts block for configuration" do
      events = [] of Tuple(String, String)

      Datastar::PubSub.configure do |config|
        config.on_subscribe = ->(topic : String, id : String) {
          events << {topic, id}
          nil
        }
      end

      # Trigger a subscribe to verify callback is wired
      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new("test-conn", channel)
      Datastar::PubSub.manager!.subscribe("topic", conn)

      events.should eq [{"topic", "test-conn"}]
    end
  end

  describe ".manager!" do
    it "raises if not configured" do
      expect_raises(Exception, /not configured/) do
        Datastar::PubSub.manager!
      end
    end
  end

  describe ".broadcast" do
    it "broadcasts to subscribed connections" do
      Datastar::PubSub.configure

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)
      Datastar::PubSub.manager!.subscribe("updates", conn)

      Datastar::PubSub.broadcast("updates") do |sse|
        sse.patch_elements("<div>new</div>")
      end

      payload = channel.receive
      payload.should contain "datastar-patch-elements"
      payload.should contain "new"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/pubsub/pubsub_spec.cr`
Expected: FAIL - PubSub module/methods not defined

**Step 3: Write minimal implementation**

Create `src/datastar/pubsub/pubsub.cr`:

```crystal
require "./backend"
require "./memory_backend"
require "./connection"
require "./manager"
require "./event_collector"

module Datastar::PubSub
  # Configuration class for pub/sub setup.
  class Configuration
    property backend : Backend = MemoryBackend.new
    property on_subscribe : Proc(String, String, Nil)?
    property on_unsubscribe : Proc(String, String, Nil)?
  end

  # The global manager instance.
  class_property manager : Manager?

  # Configures pub/sub with a block.
  def self.configure(&block : Configuration ->) : Nil
    config = Configuration.new
    yield config

    mgr = Manager.new(config.backend)
    mgr.on_subscribe = config.on_subscribe
    mgr.on_unsubscribe = config.on_unsubscribe
    @@manager = mgr
  end

  # Configures pub/sub with a backend.
  def self.configure(backend : Backend = MemoryBackend.new) : Nil
    @@manager = Manager.new(backend)
  end

  # Returns the manager, raising if not configured.
  def self.manager! : Manager
    @@manager || raise "Datastar::PubSub not configured. Call Datastar::PubSub.configure first."
  end

  # Broadcasts events to all connections subscribed to a topic.
  def self.broadcast(topic : String, &block : EventCollector ->) : Nil
    collector = EventCollector.new
    yield collector
    manager!.broadcast(topic, collector.to_payload)
  end

  # Resets the manager (for testing).
  def self.reset! : Nil
    @@manager = nil
  end
end
```

**Step 4: Update spec_helper**

Add to `spec/spec_helper.cr`:

```crystal
require "../src/datastar/pubsub/pubsub"
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/pubsub/pubsub_spec.cr`
Expected: PASS (5 examples, 0 failures)

**Step 6: Commit**

```bash
git add src/datastar/pubsub/pubsub.cr spec/datastar/pubsub/pubsub_spec.cr spec/spec_helper.cr
git commit -m "feat(pubsub): add main PubSub module with configuration"
```

---

## Task 7: Create Injectable Broadcaster Class

**Files:**
- Create: `src/datastar/pubsub/broadcaster.cr`
- Test: `spec/datastar/pubsub/broadcaster_spec.cr`

**Step 1: Write the failing test**

Create `spec/datastar/pubsub/broadcaster_spec.cr`:

```crystal
require "../../spec_helper"

describe Datastar::PubSub::Broadcaster do
  after_each do
    Datastar::PubSub.reset!
  end

  describe "#broadcast" do
    it "broadcasts to subscribed connections" do
      Datastar::PubSub.configure

      broadcaster = Datastar::PubSub::Broadcaster.new

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)
      Datastar::PubSub.manager!.subscribe("topic", conn)

      broadcaster.broadcast("topic") do |sse|
        sse.patch_signals(updated: true)
      end

      payload = channel.receive
      payload.should contain "datastar-patch-signals"
      payload.should contain "updated"
    end

    it "can be initialized with custom manager" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)
      broadcaster = Datastar::PubSub::Broadcaster.new(manager)

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)
      manager.subscribe("custom", conn)

      broadcaster.broadcast("custom") do |sse|
        sse.patch_elements("<span>test</span>")
      end

      payload = channel.receive
      payload.should contain "test"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/pubsub/broadcaster_spec.cr`
Expected: FAIL - Broadcaster not defined

**Step 3: Write minimal implementation**

Create `src/datastar/pubsub/broadcaster.cr`:

```crystal
require "./manager"
require "./event_collector"
require "./pubsub"

module Datastar::PubSub
  # Injectable broadcaster for dependency injection frameworks.
  #
  # In Athena, this can be registered as a service:
  # ```
  # @[ADI::Register]
  # class Datastar::PubSub::Broadcaster
  # end
  # ```
  class Broadcaster
    @manager : Manager

    def initialize(@manager : Manager = PubSub.manager!)
    end

    # Broadcasts events to all connections subscribed to a topic.
    def broadcast(topic : String, &block : EventCollector ->) : Nil
      collector = EventCollector.new
      yield collector
      @manager.broadcast(topic, collector.to_payload)
    end
  end
end
```

**Step 4: Update spec_helper**

Add to `spec/spec_helper.cr`:

```crystal
require "../src/datastar/pubsub/broadcaster"
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/pubsub/broadcaster_spec.cr`
Expected: PASS (2 examples, 0 failures)

**Step 6: Commit**

```bash
git add src/datastar/pubsub/broadcaster.cr spec/datastar/pubsub/broadcaster_spec.cr spec/spec_helper.cr
git commit -m "feat(pubsub): add injectable Broadcaster class"
```

---

## Task 8: Integrate Subscribe into EventStream

**Files:**
- Modify: `src/datastar/event_stream.cr`
- Modify: `spec/datastar/event_stream_spec.cr`

**Step 1: Write the failing test**

Add to `spec/datastar/event_stream_spec.cr`:

```crystal
describe Datastar::EventStream do
  # ... existing tests ...

  describe "#subscribe" do
    after_each do
      Datastar::PubSub.reset!
    end

    it "subscribes to a topic and receives broadcasts" do
      Datastar::PubSub.configure

      io = IO::Memory.new
      stream = Datastar::EventStream.new(io, heartbeat: false)

      stream.stream do |sse|
        sse.subscribe("room-1")

        # Broadcast from another "client"
        spawn do
          sleep 10.milliseconds
          Datastar::PubSub.broadcast("room-1") do |bc|
            bc.patch_elements("<div>broadcast msg</div>")
          end
        end

        # Wait a bit for broadcast
        sleep 50.milliseconds
      end

      output = io.to_s
      output.should contain "broadcast msg"
    end

    it "automatically unsubscribes when stream ends" do
      Datastar::PubSub.configure

      unsubscribe_events = [] of String
      Datastar::PubSub.manager!.on_unsubscribe = ->(topic : String, conn_id : String) {
        unsubscribe_events << topic
        nil
      }

      io = IO::Memory.new
      stream = Datastar::EventStream.new(io, heartbeat: false)

      stream.stream do |sse|
        sse.subscribe("auto-cleanup")
      end

      unsubscribe_events.should eq ["auto-cleanup"]
    end

    it "supports multiple topic subscriptions" do
      Datastar::PubSub.configure

      io = IO::Memory.new
      stream = Datastar::EventStream.new(io, heartbeat: false)

      stream.stream do |sse|
        sse.subscribe("topic-a")
        sse.subscribe("topic-b")

        spawn do
          sleep 10.milliseconds
          Datastar::PubSub.broadcast("topic-a") do |bc|
            bc.patch_signals(from_a: true)
          end
          Datastar::PubSub.broadcast("topic-b") do |bc|
            bc.patch_signals(from_b: true)
          end
        end

        sleep 50.milliseconds
      end

      output = io.to_s
      output.should contain "from_a"
      output.should contain "from_b"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/event_stream_spec.cr`
Expected: FAIL - subscribe method not defined

**Step 3: Modify EventStream to add subscribe**

Modify `src/datastar/event_stream.cr`. Add the instance variable and require at top:

After the existing requires, add:
```crystal
require "./pubsub/pubsub"
```

Add instance variable after existing ones (around line 27):
```crystal
@pubsub_connection : PubSub::Connection?
```

Add the subscribe method after the `on_error` method (around line 55):
```crystal
# Subscribes this stream to a pub/sub topic.
#
# The connection will receive all broadcasts to the topic.
# Automatically unsubscribes when the stream ends.
def subscribe(topic : String) : Nil
  @pubsub_connection ||= PubSub::Connection.new(
    output_channel: @output_channel
  )

  PubSub.manager!.subscribe(topic, @pubsub_connection.not_nil!)
end
```

Modify the `stream` method to cleanup subscriptions in the ensure block. Change the spawn block (around line 73-84) to:
```crystal
spawn do
  begin
    block.call(self)
  rescue ex
    handle_error(ex)
  ensure
    # Cleanup pub/sub subscriptions
    if conn = @pubsub_connection
      PubSub.manager!.unsubscribe_all(conn)
    end

    old_count = @stream_count.sub(1)
    if old_count == 1
      @output_channel.close
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `crystal spec spec/datastar/event_stream_spec.cr`
Expected: PASS (all examples pass)

**Step 5: Commit**

```bash
git add src/datastar/event_stream.cr spec/datastar/event_stream_spec.cr
git commit -m "feat(pubsub): integrate subscribe into EventStream"
```

---

## Task 9: Create Unified PubSub Entry Point

**Files:**
- Create: `src/datastar/pubsub.cr`
- Modify: `src/datastar.cr`

**Step 1: Create the entry point file**

Create `src/datastar/pubsub.cr`:

```crystal
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
```

**Step 2: Update main datastar.cr (optional auto-require)**

This is optional - users can explicitly require "datastar/pubsub" when needed.
For now, we'll leave `src/datastar.cr` unchanged to keep pub/sub opt-in.

**Step 3: Update spec_helper to use unified entry point**

Replace the individual pubsub requires in `spec/spec_helper.cr` with:

```crystal
require "spec"
require "../src/datastar"
require "../src/datastar/pubsub"

# Test helper component for Renderable tests
class TestComponent
  include Datastar::Renderable

  def initialize(@name : String)
  end

  def to_datastar_html : String
    %(<div id="test">Hello, #{@name}!</div>)
  end
end
```

**Step 4: Run all tests to verify everything works**

Run: `crystal spec`
Expected: All tests pass

**Step 5: Commit**

```bash
git add src/datastar/pubsub.cr spec/spec_helper.cr
git commit -m "feat(pubsub): add unified entry point"
```

---

## Task 10: Integration Test - Full Pub/Sub Flow

**Files:**
- Create: `spec/datastar/pubsub/integration_spec.cr`

**Step 1: Write integration test**

Create `spec/datastar/pubsub/integration_spec.cr`:

```crystal
require "../../spec_helper"

describe "PubSub Integration" do
  after_each do
    Datastar::PubSub.reset!
  end

  it "synchronizes multiple streams" do
    Datastar::PubSub.configure

    # Simulate two clients
    io1 = IO::Memory.new
    io2 = IO::Memory.new

    stream1 = Datastar::EventStream.new(io1, heartbeat: false)
    stream2 = Datastar::EventStream.new(io2, heartbeat: false)

    done = Channel(Nil).new

    # Client 1 subscribes and waits for broadcast
    spawn do
      stream1.stream do |sse|
        sse.subscribe("shared-room")
        sleep 100.milliseconds  # Wait for broadcast
      end
      done.send(nil)
    end

    # Client 2 subscribes and waits for broadcast
    spawn do
      stream2.stream do |sse|
        sse.subscribe("shared-room")
        sleep 100.milliseconds  # Wait for broadcast
      end
      done.send(nil)
    end

    # Give streams time to subscribe
    sleep 20.milliseconds

    # Broadcast to both
    Datastar::PubSub.broadcast("shared-room") do |sse|
      sse.patch_elements(%(<div id="msg">Hello both!</div>))
    end

    # Wait for both streams to complete
    done.receive
    done.receive

    # Both should have received the broadcast
    io1.to_s.should contain "Hello both!"
    io2.to_s.should contain "Hello both!"
  end

  it "isolates broadcasts by topic" do
    Datastar::PubSub.configure

    io1 = IO::Memory.new
    io2 = IO::Memory.new

    stream1 = Datastar::EventStream.new(io1, heartbeat: false)
    stream2 = Datastar::EventStream.new(io2, heartbeat: false)

    done = Channel(Nil).new

    spawn do
      stream1.stream do |sse|
        sse.subscribe("room-a")
        sleep 100.milliseconds
      end
      done.send(nil)
    end

    spawn do
      stream2.stream do |sse|
        sse.subscribe("room-b")
        sleep 100.milliseconds
      end
      done.send(nil)
    end

    sleep 20.milliseconds

    Datastar::PubSub.broadcast("room-a") do |sse|
      sse.patch_signals(for_room_a: true)
    end

    Datastar::PubSub.broadcast("room-b") do |sse|
      sse.patch_signals(for_room_b: true)
    end

    done.receive
    done.receive

    io1.to_s.should contain "for_room_a"
    io1.to_s.should_not contain "for_room_b"

    io2.to_s.should contain "for_room_b"
    io2.to_s.should_not contain "for_room_a"
  end

  it "tracks lifecycle with callbacks" do
    events = [] of String

    Datastar::PubSub.configure do |config|
      config.on_subscribe = ->(topic : String, conn_id : String) {
        events << "subscribe:#{topic}"
        nil
      }
      config.on_unsubscribe = ->(topic : String, conn_id : String) {
        events << "unsubscribe:#{topic}"
        nil
      }
    end

    io = IO::Memory.new
    stream = Datastar::EventStream.new(io, heartbeat: false)

    stream.stream do |sse|
      sse.subscribe("tracked-topic")
    end

    events.should eq ["subscribe:tracked-topic", "unsubscribe:tracked-topic"]
  end
end
```

**Step 2: Run test to verify it passes**

Run: `crystal spec spec/datastar/pubsub/integration_spec.cr`
Expected: PASS (3 examples, 0 failures)

**Step 3: Run full test suite**

Run: `crystal spec`
Expected: All tests pass

**Step 4: Commit**

```bash
git add spec/datastar/pubsub/integration_spec.cr
git commit -m "test(pubsub): add integration tests for full flow"
```

---

## Task 11: Update Documentation

**Files:**
- Modify: `README.md`

**Step 1: Add pub/sub section to README**

Add the following section to `README.md` after the existing usage examples:

```markdown
## Pub/Sub for Multi-Session Sync

Enable real-time synchronization across multiple browser sessions:

### Setup

```crystal
require "datastar/pubsub"

# Configure at app startup
Datastar::PubSub.configure

# With options
Datastar::PubSub.configure do |config|
  config.on_subscribe do |topic, conn_id|
    Log.info { "Client #{conn_id} joined #{topic}" }
  end
end
```

### Subscribe to Topics

```crystal
get "/subscribe/:list_id" do |env|
  list_id = env.params.url["list_id"]

  env.datastar_stream do |sse|
    sse.subscribe("todos:#{list_id}")
    sse.patch_elements("#list", render_todos(list_id))
    # Connection stays open, broadcasts arrive automatically
  end
end
```

### Broadcast Updates

```crystal
post "/todos/:list_id" do |env|
  list_id = env.params.url["list_id"]
  todo = create_todo(env.params.json)

  # All subscribed clients receive this update
  Datastar::PubSub.broadcast("todos:#{list_id}") do |sse|
    sse.patch_elements("#list", render_todos(list_id))
  end

  env.response.status_code = 201
end
```

### Custom Backend

For multi-server deployments, implement a custom backend:

```crystal
class RedisBackend < Datastar::PubSub::Backend
  def publish(topic : String, payload : String) : Nil
    @redis.publish("datastar:#{topic}", payload)
  end

  def subscribe(topic : String, &block : String ->) : String
    # Subscribe to Redis channel, call block on messages
  end

  def unsubscribe(subscription_id : String) : Nil
    # Unsubscribe from Redis
  end
end

Datastar::PubSub.configure(backend: RedisBackend.new(redis))
```
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add pub/sub usage documentation"
```

---

## Summary

The implementation is complete. All tasks:

1. ✅ Connection wrapper
2. ✅ Abstract Backend interface
3. ✅ MemoryBackend implementation
4. ✅ Manager for connection tracking
5. ✅ EventCollector for broadcast blocks
6. ✅ Main PubSub module with configuration
7. ✅ Injectable Broadcaster class
8. ✅ EventStream subscribe integration
9. ✅ Unified entry point
10. ✅ Integration tests
11. ✅ Documentation

Run full test suite: `crystal spec`
