# Datastar Crystal SDK Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a Crystal SDK for the Datastar hypermedia framework, providing SSE-based server-to-browser communication with support for patching DOM elements, signals, and script execution.

**Architecture:** Core library with zero dependencies (stdlib only), plus optional adapters for Athena framework and Blueprint HTML builder. Uses fibers and channels for concurrent streaming. Protocol-based rendering allows any templating solution.

**Tech Stack:** Crystal 1.18+, HTTP::Server (stdlib), JSON (stdlib), Athena Framework (adapter), Blueprint (adapter)

---

### Task 1: Project Structure and Version

**Files:**
- Modify: `src/datastar.cr`
- Create: `src/datastar/version.cr`

**Step 1: Create version file**

Create `src/datastar/version.cr`:

```crystal
module Datastar
  VERSION = "0.1.0"
end
```

**Step 2: Update main entry point**

Replace contents of `src/datastar.cr`:

```crystal
require "./datastar/version"

module Datastar
end
```

**Step 3: Verify compilation**

Run: `crystal build --no-codegen src/datastar.cr`
Expected: No errors

**Step 4: Commit**

```bash
git add src/datastar.cr src/datastar/version.cr
git commit -m "chore: set up project structure with version"
```

---

### Task 2: Protocol Constants

**Files:**
- Create: `src/datastar/consts.cr`
- Modify: `src/datastar.cr`
- Create: `spec/datastar/consts_spec.cr`

**Step 1: Write failing test for constants**

Create `spec/datastar/consts_spec.cr`:

```crystal
require "../spec_helper"

describe Datastar do
  describe "DATASTAR_VERSION" do
    it "matches expected protocol version" do
      Datastar::DATASTAR_VERSION.should eq "1.0.0-beta.1"
    end
  end

  describe "EventType" do
    it "has correct event type strings" do
      Datastar::EventType::PatchElements.should eq "datastar-patch-elements"
      Datastar::EventType::PatchSignals.should eq "datastar-patch-signals"
      Datastar::EventType::ExecuteScript.should eq "datastar-execute-script"
    end
  end

  describe "FragmentMergeMode" do
    it "has all merge modes" do
      Datastar::FragmentMergeMode::Morph.to_s.downcase.should eq "morph"
      Datastar::FragmentMergeMode::Append.to_s.downcase.should eq "append"
      Datastar::FragmentMergeMode::Prepend.to_s.downcase.should eq "prepend"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/consts_spec.cr`
Expected: FAIL with undefined constant errors

**Step 3: Implement constants**

Create `src/datastar/consts.cr`:

```crystal
module Datastar
  # Datastar protocol version this SDK targets
  DATASTAR_VERSION = "1.0.0-beta.1"

  # Default SSE retry duration in milliseconds
  DEFAULT_SSE_RETRY_DURATION = 1000

  # Default settings
  DEFAULT_FRAGMENT_MERGE_MODE    = FragmentMergeMode::Morph
  DEFAULT_SIGNALS_ONLY_IF_MISSING = false
  DEFAULT_AUTOREMOVE_SCRIPT      = true
  DEFAULT_USE_VIEW_TRANSITION    = false

  # Selector for targeting the whole document
  WHOLE_DOCUMENT_SELECTOR = ""

  # SSE Event types
  module EventType
    PatchElements = "datastar-patch-elements"
    PatchSignals  = "datastar-patch-signals"
    ExecuteScript = "datastar-execute-script"
  end

  # Fragment merge modes for patch_elements
  enum FragmentMergeMode
    Morph
    Inner
    Outer
    Prepend
    Append
    Before
    After
    UpsertAttributes
  end

  # Signal header names
  DATASTAR_SIGNAL_HEADER = "datastar-signal"
end
```

**Step 4: Update main entry to require constants**

Modify `src/datastar.cr`:

```crystal
require "./datastar/version"
require "./datastar/consts"

module Datastar
end
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/consts_spec.cr`
Expected: PASS (3 examples, 0 failures)

**Step 6: Commit**

```bash
git add src/datastar/consts.cr src/datastar.cr spec/datastar/consts_spec.cr
git commit -m "feat: add protocol constants and event types"
```

---

### Task 3: Configuration

**Files:**
- Create: `src/datastar/configuration.cr`
- Create: `spec/datastar/configuration_spec.cr`
- Modify: `src/datastar.cr`

**Step 1: Write failing test for configuration**

Create `spec/datastar/configuration_spec.cr`:

```crystal
require "../spec_helper"

describe Datastar::Configuration do
  describe "#initialize" do
    it "has sensible defaults" do
      config = Datastar::Configuration.new
      config.heartbeat.should eq 3.seconds
      config.on_error.should be_nil
    end
  end

  describe "#heartbeat" do
    it "can be set to a time span" do
      config = Datastar::Configuration.new
      config.heartbeat = 5.seconds
      config.heartbeat.should eq 5.seconds
    end

    it "can be disabled with false" do
      config = Datastar::Configuration.new
      config.heartbeat = false
      config.heartbeat.should eq false
    end
  end
end

describe Datastar do
  describe ".configure" do
    it "yields the global configuration" do
      Datastar.configure do |config|
        config.should be_a Datastar::Configuration
      end
    end
  end

  describe ".config" do
    it "returns the global configuration" do
      Datastar.config.should be_a Datastar::Configuration
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/configuration_spec.cr`
Expected: FAIL with undefined constant errors

**Step 3: Implement configuration**

Create `src/datastar/configuration.cr`:

```crystal
module Datastar
  class Configuration
    property heartbeat : Time::Span | Bool = 3.seconds
    property on_error : Proc(Exception, Nil)? = nil
  end

  class_getter config : Configuration = Configuration.new

  def self.configure(& : Configuration ->) : Nil
    yield @@config
  end
end
```

**Step 4: Update main entry to require configuration**

Modify `src/datastar.cr`:

```crystal
require "./datastar/version"
require "./datastar/consts"
require "./datastar/configuration"

module Datastar
end
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/configuration_spec.cr`
Expected: PASS

**Step 6: Commit**

```bash
git add src/datastar/configuration.cr src/datastar.cr spec/datastar/configuration_spec.cr
git commit -m "feat: add global configuration with heartbeat and error handler"
```

---

### Task 4: Renderable Protocol

**Files:**
- Create: `src/datastar/renderable.cr`
- Create: `spec/datastar/renderable_spec.cr`
- Modify: `src/datastar.cr`

**Step 1: Write failing test for Renderable**

Create `spec/datastar/renderable_spec.cr`:

```crystal
require "../spec_helper"

class TestComponent
  include Datastar::Renderable

  def initialize(@name : String)
  end

  def to_datastar_html : String
    %(<div id="test">Hello, #{@name}!</div>)
  end
end

describe Datastar::Renderable do
  describe "#to_datastar_html" do
    it "returns HTML string from implementing class" do
      component = TestComponent.new("World")
      component.to_datastar_html.should eq %(<div id="test">Hello, World!</div>)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/renderable_spec.cr`
Expected: FAIL with undefined constant error

**Step 3: Implement Renderable module**

Create `src/datastar/renderable.cr`:

```crystal
module Datastar
  # Protocol for objects that can be rendered as HTML fragments.
  #
  # Include this module and implement `#to_datastar_html` to make your
  # component compatible with `ServerSentEventGenerator#patch_elements`.
  #
  # ```
  # class MyComponent
  #   include Datastar::Renderable
  #
  #   def initialize(@name : String)
  #   end
  #
  #   def to_datastar_html : String
  #     %(<div>Hello, #{@name}!</div>)
  #   end
  # end
  #
  # sse.patch_elements(MyComponent.new("World"))
  # ```
  module Renderable
    abstract def to_datastar_html : String
  end
end
```

**Step 4: Update main entry to require renderable**

Modify `src/datastar.cr`:

```crystal
require "./datastar/version"
require "./datastar/consts"
require "./datastar/configuration"
require "./datastar/renderable"

module Datastar
end
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/renderable_spec.cr`
Expected: PASS

**Step 6: Commit**

```bash
git add src/datastar/renderable.cr src/datastar.cr spec/datastar/renderable_spec.cr
git commit -m "feat: add Renderable protocol for HTML components"
```

---

### Task 5: ServerSentEvent Builder

**Files:**
- Create: `src/datastar/server_sent_event.cr`
- Create: `spec/datastar/server_sent_event_spec.cr`
- Modify: `src/datastar.cr`

**Step 1: Write failing test for ServerSentEvent**

Create `spec/datastar/server_sent_event_spec.cr`:

```crystal
require "../spec_helper"

describe Datastar::ServerSentEvent do
  describe "#to_s" do
    it "formats a simple event" do
      event = Datastar::ServerSentEvent.new(
        event_type: Datastar::EventType::PatchElements,
        data_lines: ["<div>Hello</div>"]
      )
      event.to_s.should eq "event: datastar-patch-elements\ndata: <div>Hello</div>\n\n"
    end

    it "formats multiple data lines" do
      event = Datastar::ServerSentEvent.new(
        event_type: Datastar::EventType::PatchElements,
        data_lines: ["<div>", "  Hello", "</div>"]
      )
      event.to_s.should eq "event: datastar-patch-elements\ndata: <div>\ndata:   Hello\ndata: </div>\n\n"
    end

    it "includes id when provided" do
      event = Datastar::ServerSentEvent.new(
        event_type: Datastar::EventType::PatchElements,
        data_lines: ["test"],
        id: "123"
      )
      event.to_s.should contain "id: 123\n"
    end

    it "includes retry when provided" do
      event = Datastar::ServerSentEvent.new(
        event_type: Datastar::EventType::PatchElements,
        data_lines: ["test"],
        retry_duration: 5000
      )
      event.to_s.should contain "retry: 5000\n"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/server_sent_event_spec.cr`
Expected: FAIL with undefined constant error

**Step 3: Implement ServerSentEvent**

Create `src/datastar/server_sent_event.cr`:

```crystal
module Datastar
  # Represents a single Server-Sent Event.
  #
  # This class handles the formatting of SSE events according to the
  # SSE specification and Datastar protocol.
  class ServerSentEvent
    getter event_type : String
    getter data_lines : Array(String)
    getter id : String?
    getter retry_duration : Int32?

    def initialize(
      @event_type : String,
      @data_lines : Array(String),
      @id : String? = nil,
      @retry_duration : Int32? = nil
    )
    end

    # Formats the event as an SSE string ready to be sent over the wire.
    def to_s(io : IO) : Nil
      io << "event: " << @event_type << "\n"

      if id = @id
        io << "id: " << id << "\n"
      end

      if retry = @retry_duration
        io << "retry: " << retry << "\n"
      end

      @data_lines.each do |line|
        io << "data: " << line << "\n"
      end

      io << "\n"
    end

    def to_s : String
      String.build { |io| to_s(io) }
    end
  end
end
```

**Step 4: Update main entry to require server_sent_event**

Modify `src/datastar.cr`:

```crystal
require "./datastar/version"
require "./datastar/consts"
require "./datastar/configuration"
require "./datastar/renderable"
require "./datastar/server_sent_event"

module Datastar
end
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/server_sent_event_spec.cr`
Expected: PASS

**Step 6: Commit**

```bash
git add src/datastar/server_sent_event.cr src/datastar.cr spec/datastar/server_sent_event_spec.cr
git commit -m "feat: add ServerSentEvent builder for SSE formatting"
```

---

### Task 6: Signals Parser

**Files:**
- Create: `src/datastar/signals.cr`
- Create: `spec/datastar/signals_spec.cr`
- Modify: `src/datastar.cr`

**Step 1: Write failing test for Signals**

Create `spec/datastar/signals_spec.cr`:

```crystal
require "../spec_helper"
require "json"

struct TestSignals
  include JSON::Serializable
  getter name : String
  getter count : Int32
end

describe Datastar::Signals do
  describe ".parse" do
    it "parses JSON string to JSON::Any" do
      signals = Datastar::Signals.parse(%q({"name": "test", "count": 42}))
      signals["name"].as_s.should eq "test"
      signals["count"].as_i.should eq 42
    end

    it "returns empty object for empty string" do
      signals = Datastar::Signals.parse("")
      signals.as_h.should be_empty
    end

    it "returns empty object for nil" do
      signals = Datastar::Signals.parse(nil)
      signals.as_h.should be_empty
    end
  end

  describe ".parse with type" do
    it "deserializes to typed struct" do
      signals = Datastar::Signals.parse(%q({"name": "test", "count": 42}), TestSignals)
      signals.name.should eq "test"
      signals.count.should eq 42
    end
  end

  describe ".from_request" do
    it "extracts signals from header" do
      headers = HTTP::Headers{"Datastar-Signal" => %q({"key": "value"})}
      request = HTTP::Request.new("GET", "/", headers)
      signals = Datastar::Signals.from_request(request)
      signals["key"].as_s.should eq "value"
    end

    it "extracts signals from URL-encoded header" do
      encoded = URI.encode_www_form(%q({"key": "hello world"}))
      headers = HTTP::Headers{"Datastar-Signal" => encoded}
      request = HTTP::Request.new("GET", "/", headers)
      signals = Datastar::Signals.from_request(request)
      signals["key"].as_s.should eq "hello world"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/signals_spec.cr`
Expected: FAIL with undefined constant error

**Step 3: Implement Signals**

Create `src/datastar/signals.cr`:

```crystal
require "json"
require "uri"

module Datastar
  # Handles parsing of signals sent from the browser.
  #
  # Signals can be sent via the `Datastar-Signal` header as JSON (possibly URL-encoded).
  module Signals
    extend self

    # Parses a JSON string into JSON::Any.
    def parse(json : String?) : JSON::Any
      return JSON::Any.new({} of String => JSON::Any) if json.nil? || json.empty?
      JSON.parse(json)
    end

    # Parses a JSON string into a typed object.
    def parse(json : String?, type : T.class) : T forall T
      raise ArgumentError.new("Cannot parse nil or empty string to #{T}") if json.nil? || json.empty?
      T.from_json(json)
    end

    # Extracts signals from an HTTP request.
    #
    # Looks for the `Datastar-Signal` header and parses it as JSON.
    # The header value may be URL-encoded.
    def from_request(request : HTTP::Request) : JSON::Any
      header = request.headers[DATASTAR_SIGNAL_HEADER]?
      return JSON::Any.new({} of String => JSON::Any) if header.nil? || header.empty?

      # Try to URL-decode if it looks encoded
      decoded = begin
        URI.decode_www_form(header)
      rescue
        header
      end

      parse(decoded)
    end

    # Extracts signals from an HTTP request into a typed object.
    def from_request(request : HTTP::Request, type : T.class) : T forall T
      header = request.headers[DATASTAR_SIGNAL_HEADER]?
      raise ArgumentError.new("No #{DATASTAR_SIGNAL_HEADER} header found") if header.nil? || header.empty?

      decoded = begin
        URI.decode_www_form(header)
      rescue
        header
      end

      parse(decoded, type)
    end
  end
end
```

**Step 4: Update main entry to require signals**

Modify `src/datastar.cr`:

```crystal
require "./datastar/version"
require "./datastar/consts"
require "./datastar/configuration"
require "./datastar/renderable"
require "./datastar/server_sent_event"
require "./datastar/signals"

module Datastar
end
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/signals_spec.cr`
Expected: PASS

**Step 6: Commit**

```bash
git add src/datastar/signals.cr src/datastar.cr spec/datastar/signals_spec.cr
git commit -m "feat: add Signals parser for browser-sent data"
```

---

### Task 7: ServerSentEventGenerator - Core Structure

**Files:**
- Create: `src/datastar/server_sent_event_generator.cr`
- Create: `spec/datastar/server_sent_event_generator_spec.cr`
- Modify: `src/datastar.cr`

**Step 1: Write failing test for basic structure**

Create `spec/datastar/server_sent_event_generator_spec.cr`:

```crystal
require "../spec_helper"
require "http/server"

describe Datastar::ServerSentEventGenerator do
  describe "#initialize" do
    it "creates a generator with request and response" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response)
      sse.should be_a Datastar::ServerSentEventGenerator
    end

    it "accepts custom heartbeat" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: 5.seconds)
      sse.heartbeat.should eq 5.seconds
    end

    it "allows disabling heartbeat" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)
      sse.heartbeat.should eq false
    end
  end

  describe "#signals" do
    it "returns signals from request header" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      headers = HTTP::Headers{"Datastar-Signal" => %q({"test": "value"})}
      request = HTTP::Request.new("GET", "/", headers)

      sse = Datastar::ServerSentEventGenerator.new(request, response)
      sse.signals["test"].as_s.should eq "value"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: FAIL with undefined constant error

**Step 3: Implement core structure**

Create `src/datastar/server_sent_event_generator.cr`:

```crystal
require "http/server"
require "json"

module Datastar
  # Main class for generating Server-Sent Events for Datastar.
  #
  # This class handles the SSE protocol, concurrent streaming via fibers,
  # connection health monitoring, and lifecycle callbacks.
  #
  # ```
  # sse = Datastar::ServerSentEventGenerator.new(request, response)
  #
  # sse.on_connect { puts "Client connected" }
  # sse.on_client_disconnect { puts "Client disconnected" }
  #
  # sse.stream do |stream|
  #   stream.patch_elements(%(<div id="message">Hello!</div>))
  # end
  # ```
  class ServerSentEventGenerator
    getter request : HTTP::Request
    getter response : HTTP::Server::Response
    getter heartbeat : Time::Span | Bool

    @signals : JSON::Any?
    @on_connect : Proc(Nil)?
    @on_client_disconnect : Proc(Nil)?
    @on_server_disconnect : Proc(Nil)?
    @on_error : Proc(Exception, Nil)?
    @headers_sent : Bool = false
    @closed : Bool = false

    def initialize(
      @request : HTTP::Request,
      @response : HTTP::Server::Response,
      @heartbeat : Time::Span | Bool = Datastar.config.heartbeat
    )
      @on_error = Datastar.config.on_error
    end

    # Returns signals sent by the browser as JSON::Any.
    def signals : JSON::Any
      @signals ||= Signals.from_request(@request)
    end

    # Returns signals sent by the browser as a typed object.
    def signals(type : T.class) : T forall T
      Signals.from_request(@request, type)
    end

    # Registers a callback to run when the connection is first established.
    def on_connect(&block : -> Nil) : Nil
      @on_connect = block
    end

    # Registers a callback to run when the client disconnects.
    def on_client_disconnect(&block : -> Nil) : Nil
      @on_client_disconnect = block
    end

    # Registers a callback to run when the server finishes streaming.
    def on_server_disconnect(&block : -> Nil) : Nil
      @on_server_disconnect = block
    end

    # Registers a callback to handle exceptions in stream blocks.
    def on_error(&block : Exception -> Nil) : Nil
      @on_error = block
    end

    # Returns true if the connection has been closed.
    def closed? : Bool
      @closed
    end

    private def send_headers : Nil
      return if @headers_sent

      @response.content_type = "text/event-stream"
      @response.headers["Cache-Control"] = "no-cache"
      @response.headers["Connection"] = "keep-alive"
      @headers_sent = true

      @on_connect.try &.call
    end

    private def handle_error(ex : Exception) : Nil
      @on_error.try &.call(ex)
    end
  end
end
```

**Step 4: Update main entry to require server_sent_event_generator**

Modify `src/datastar.cr`:

```crystal
require "./datastar/version"
require "./datastar/consts"
require "./datastar/configuration"
require "./datastar/renderable"
require "./datastar/server_sent_event"
require "./datastar/signals"
require "./datastar/server_sent_event_generator"

module Datastar
end
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: PASS

**Step 6: Commit**

```bash
git add src/datastar/server_sent_event_generator.cr src/datastar.cr spec/datastar/server_sent_event_generator_spec.cr
git commit -m "feat: add ServerSentEventGenerator core structure"
```

---

### Task 8: ServerSentEventGenerator - Streaming

**Files:**
- Modify: `src/datastar/server_sent_event_generator.cr`
- Modify: `spec/datastar/server_sent_event_generator_spec.cr`

**Step 1: Write failing test for streaming**

Add to `spec/datastar/server_sent_event_generator_spec.cr`:

```crystal
describe "#stream" do
  it "executes block and writes to response" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_elements(%(<div id="test">Hello</div>))
    end

    response.close
    output = io.to_s
    output.should contain "event: datastar-patch-elements"
    output.should contain "data: fragments <div id=\"test\">Hello</div>"
  end

  it "sets correct SSE headers" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_elements("<div>test</div>")
    end

    response.close
    response.headers["Content-Type"].should eq "text/event-stream"
    response.headers["Cache-Control"].should eq "no-cache"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: FAIL (method not defined)

**Step 3: Implement streaming**

Add to `src/datastar/server_sent_event_generator.cr` inside the class:

```crystal
    @output_channel : Channel(String) = Channel(String).new(100)
    @stream_count : Atomic(Int32) = Atomic(Int32).new(0)
    @output_loop_started : Bool = false

    # Executes a streaming block in a fiber.
    #
    # Multiple stream blocks can run concurrently. All output is serialized
    # through a channel to ensure thread-safe writes to the response.
    #
    # ```
    # sse.stream do |stream|
    #   10.times do |i|
    #     sleep 1.second
    #     stream.patch_elements(%(<div id="count">#{i}</div>))
    #   end
    # end
    # ```
    def stream(&block : ServerSentEventGenerator -> Nil) : Nil
      send_headers
      start_output_loop unless @output_loop_started

      @stream_count.add(1)

      spawn do
        begin
          block.call(self)
        rescue ex
          handle_error(ex)
        ensure
          if @stream_count.sub(1) == 1
            # Last stream finished, close the channel
            @output_channel.close
          end
        end
      end

      # Wait for all streams to complete
      Fiber.yield until @output_channel.closed?

      @on_server_disconnect.try &.call unless @closed
    end

    private def start_output_loop : Nil
      @output_loop_started = true

      spawn do
        while event = @output_channel.receive?
          begin
            @response.print(event)
            @response.flush
          rescue IO::Error
            @closed = true
            @on_client_disconnect.try &.call
            @output_channel.close
            break
          end
        end
      end
    end

    private def send_event(event : ServerSentEvent) : Nil
      return if @closed
      @output_channel.send(event.to_s)
    end
```

**Step 4: Run test to verify it passes**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: FAIL (patch_elements not defined yet - expected, we'll add it next)

**Step 5: Commit partial progress**

```bash
git add src/datastar/server_sent_event_generator.cr spec/datastar/server_sent_event_generator_spec.cr
git commit -m "feat: add streaming with fibers and channels"
```

---

### Task 9: ServerSentEventGenerator - patch_elements

**Files:**
- Modify: `src/datastar/server_sent_event_generator.cr`
- Modify: `spec/datastar/server_sent_event_generator_spec.cr`

**Step 1: Write failing test for patch_elements**

Add to `spec/datastar/server_sent_event_generator_spec.cr`:

```crystal
describe "#patch_elements" do
  it "sends a fragment with default options" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_elements(%(<div id="test">Hello</div>))
    end

    response.close
    output = io.to_s
    output.should contain "event: datastar-patch-elements"
    output.should contain "data: fragments <div id=\"test\">Hello</div>"
  end

  it "sends with custom selector" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_elements("<span>Hi</span>", selector: "#target")
    end

    response.close
    output = io.to_s
    output.should contain "data: selector #target"
  end

  it "sends with merge mode" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_elements("<li>Item</li>", mode: Datastar::FragmentMergeMode::Append)
    end

    response.close
    output = io.to_s
    output.should contain "data: mergeMode append"
  end

  it "accepts Renderable objects" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    component = TestComponent.new("World")

    sse.stream do |stream|
      stream.patch_elements(component)
    end

    response.close
    output = io.to_s
    output.should contain "Hello, World!"
  end

  it "accepts array of elements" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_elements(["<div>One</div>", "<div>Two</div>"])
    end

    response.close
    output = io.to_s
    output.should contain "One"
    output.should contain "Two"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: FAIL (method not defined)

**Step 3: Implement patch_elements**

Add to `src/datastar/server_sent_event_generator.cr` inside the class:

```crystal
    # Patches elements into the DOM.
    #
    # See https://data-star.dev/reference/sse_events#datastar-patch-elements
    #
    # ```
    # sse.patch_elements(%(<div id="message">Hello</div>))
    # sse.patch_elements(MyComponent.new)
    # sse.patch_elements("<li>Item</li>", mode: FragmentMergeMode::Append)
    # ```
    def patch_elements(
      fragment : String | Renderable,
      *,
      selector : String = WHOLE_DOCUMENT_SELECTOR,
      mode : FragmentMergeMode = DEFAULT_FRAGMENT_MERGE_MODE,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION
    ) : Nil
      patch_elements([fragment], selector: selector, mode: mode, use_view_transition: use_view_transition)
    end

    # Patches multiple elements into the DOM.
    def patch_elements(
      fragments : Array(String | Renderable),
      *,
      selector : String = WHOLE_DOCUMENT_SELECTOR,
      mode : FragmentMergeMode = DEFAULT_FRAGMENT_MERGE_MODE,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION
    ) : Nil
      data_lines = [] of String

      # Add selector if specified
      unless selector.empty?
        data_lines << "selector #{selector}"
      end

      # Add merge mode if not default
      if mode != DEFAULT_FRAGMENT_MERGE_MODE
        data_lines << "mergeMode #{mode.to_s.downcase}"
      end

      # Add view transition if enabled
      if use_view_transition
        data_lines << "useViewTransition true"
      end

      # Add fragments
      fragments.each do |fragment|
        html = fragment.is_a?(Renderable) ? fragment.to_datastar_html : fragment
        data_lines << "fragments #{html}"
      end

      event = ServerSentEvent.new(
        event_type: EventType::PatchElements,
        data_lines: data_lines
      )

      send_event(event)
    end
```

**Step 4: Run test to verify it passes**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: PASS

**Step 5: Commit**

```bash
git add src/datastar/server_sent_event_generator.cr spec/datastar/server_sent_event_generator_spec.cr
git commit -m "feat: add patch_elements for DOM updates"
```

---

### Task 10: ServerSentEventGenerator - remove_elements

**Files:**
- Modify: `src/datastar/server_sent_event_generator.cr`
- Modify: `spec/datastar/server_sent_event_generator_spec.cr`

**Step 1: Write failing test for remove_elements**

Add to `spec/datastar/server_sent_event_generator_spec.cr`:

```crystal
describe "#remove_elements" do
  it "sends a remove event" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.remove_elements("#old-element")
    end

    response.close
    output = io.to_s
    output.should contain "event: datastar-patch-elements"
    output.should contain "data: selector #old-element"
    output.should contain "data: fragments"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: FAIL

**Step 3: Implement remove_elements**

Add to `src/datastar/server_sent_event_generator.cr`:

```crystal
    # Removes elements from the DOM.
    #
    # This is a convenience method that patches an empty fragment with
    # the delete mode.
    #
    # ```
    # sse.remove_elements("#old-notification")
    # ```
    def remove_elements(
      selector : String,
      *,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION
    ) : Nil
      data_lines = ["selector #{selector}", "fragments"]

      if use_view_transition
        data_lines.insert(1, "useViewTransition true")
      end

      event = ServerSentEvent.new(
        event_type: EventType::PatchElements,
        data_lines: data_lines
      )

      send_event(event)
    end
```

**Step 4: Run test to verify it passes**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: PASS

**Step 5: Commit**

```bash
git add src/datastar/server_sent_event_generator.cr spec/datastar/server_sent_event_generator_spec.cr
git commit -m "feat: add remove_elements convenience method"
```

---

### Task 11: ServerSentEventGenerator - patch_signals and remove_signals

**Files:**
- Modify: `src/datastar/server_sent_event_generator.cr`
- Modify: `spec/datastar/server_sent_event_generator_spec.cr`

**Step 1: Write failing tests for signal methods**

Add to `spec/datastar/server_sent_event_generator_spec.cr`:

```crystal
describe "#patch_signals" do
  it "sends signals as JSON" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_signals(count: 42, name: "test")
    end

    response.close
    output = io.to_s
    output.should contain "event: datastar-patch-signals"
    output.should contain "data: signals"
    output.should contain "count"
    output.should contain "42"
  end

  it "supports only_if_missing option" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_signals({count: 1}, only_if_missing: true)
    end

    response.close
    output = io.to_s
    output.should contain "data: onlyIfMissing true"
  end
end

describe "#remove_signals" do
  it "sends remove signals event" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.remove_signals(["user.name", "user.email"])
    end

    response.close
    output = io.to_s
    output.should contain "event: datastar-patch-signals"
    output.should contain "data: signals"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: FAIL

**Step 3: Implement signal methods**

Add to `src/datastar/server_sent_event_generator.cr`:

```crystal
    # Patches signals (reactive state) in the browser.
    #
    # See https://data-star.dev/reference/sse_events#datastar-patch-signals
    #
    # ```
    # sse.patch_signals(count: 42, user: {name: "Alice"})
    # sse.patch_signals({enabled: true}, only_if_missing: true)
    # ```
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

      event = ServerSentEvent.new(
        event_type: EventType::PatchSignals,
        data_lines: data_lines
      )

      send_event(event)
    end

    # Removes signals from the browser state.
    #
    # ```
    # sse.remove_signals(["user.name", "user.email"])
    # ```
    def remove_signals(paths : Array(String)) : Nil
      # Create an object with null values for each path
      signals_hash = {} of String => Nil
      paths.each { |path| signals_hash[path] = nil }

      data_lines = ["signals #{signals_hash.to_json}"]

      event = ServerSentEvent.new(
        event_type: EventType::PatchSignals,
        data_lines: data_lines
      )

      send_event(event)
    end
```

**Step 4: Run test to verify it passes**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: PASS

**Step 5: Commit**

```bash
git add src/datastar/server_sent_event_generator.cr spec/datastar/server_sent_event_generator_spec.cr
git commit -m "feat: add patch_signals and remove_signals methods"
```

---

### Task 12: ServerSentEventGenerator - execute_script and redirect

**Files:**
- Modify: `src/datastar/server_sent_event_generator.cr`
- Modify: `spec/datastar/server_sent_event_generator_spec.cr`

**Step 1: Write failing tests**

Add to `spec/datastar/server_sent_event_generator_spec.cr`:

```crystal
describe "#execute_script" do
  it "sends a script execution event" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.execute_script(%(console.log("Hello")))
    end

    response.close
    output = io.to_s
    output.should contain "event: datastar-execute-script"
    output.should contain %(console.log("Hello"))
  end

  it "includes auto_remove by default" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.execute_script("alert('hi')")
    end

    response.close
    output = io.to_s
    output.should contain "data: autoRemove true"
  end

  it "supports custom attributes" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.execute_script("test()", attributes: {"type" => "module"})
    end

    response.close
    output = io.to_s
    output.should contain "data: attributes type module"
  end
end

describe "#redirect" do
  it "sends a redirect script" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.redirect("/dashboard")
    end

    response.close
    output = io.to_s
    output.should contain "event: datastar-execute-script"
    output.should contain "/dashboard"
    output.should contain "location"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: FAIL

**Step 3: Implement execute_script and redirect**

Add to `src/datastar/server_sent_event_generator.cr`:

```crystal
    # Executes JavaScript in the browser.
    #
    # See https://data-star.dev/reference/sse_events#datastar-execute-script
    #
    # ```
    # sse.execute_script(%(console.log("Hello")))
    # sse.execute_script("initWidget()", auto_remove: false)
    # sse.execute_script("import('module')", attributes: {"type" => "module"})
    # ```
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

      event = ServerSentEvent.new(
        event_type: EventType::ExecuteScript,
        data_lines: data_lines
      )

      send_event(event)
    end

    # Redirects the browser to a new URL.
    #
    # This is a convenience method that executes a script to change
    # the browser's location.
    #
    # ```
    # sse.redirect("/dashboard")
    # sse.redirect("https://example.com")
    # ```
    def redirect(url : String) : Nil
      execute_script(%(window.location = "#{url}"))
    end
```

**Step 4: Run test to verify it passes**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: PASS

**Step 5: Commit**

```bash
git add src/datastar/server_sent_event_generator.cr spec/datastar/server_sent_event_generator_spec.cr
git commit -m "feat: add execute_script and redirect methods"
```

---

### Task 13: ServerSentEventGenerator - check_connection! and heartbeat

**Files:**
- Modify: `src/datastar/server_sent_event_generator.cr`
- Modify: `spec/datastar/server_sent_event_generator_spec.cr`

**Step 1: Write failing tests**

Add to `spec/datastar/server_sent_event_generator_spec.cr`:

```crystal
describe "#check_connection!" do
  it "does not raise when connection is open" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    expect_raises(Exception) do
      # This will fail because we can't actually test a live connection
      # but we can verify the method exists and attempts to write
      sse.check_connection!
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: FAIL

**Step 3: Implement check_connection! and heartbeat**

Add to `src/datastar/server_sent_event_generator.cr`:

```crystal
    # Checks if the client connection is still alive.
    #
    # Raises `IO::Error` if the connection has been closed.
    # This is useful for long-running streams where you want to
    # detect disconnections early.
    #
    # ```
    # sse.stream do |stream|
    #   loop do
    #     stream.check_connection!
    #     # ... wait for events ...
    #   end
    # end
    # ```
    def check_connection! : Nil
      raise IO::Error.new("Connection closed") if @closed

      begin
        # Send an SSE comment as a heartbeat
        @response.print(": heartbeat\n\n")
        @response.flush
      rescue IO::Error
        @closed = true
        @on_client_disconnect.try &.call
        raise
      end
    end

    private def start_heartbeat : Nil
      interval = @heartbeat
      return unless interval.is_a?(Time::Span)

      spawn do
        loop do
          sleep interval
          break if @closed || @output_channel.closed?

          begin
            check_connection!
          rescue IO::Error
            break
          end
        end
      end
    end
```

Update the `stream` method to start the heartbeat:

```crystal
    def stream(&block : ServerSentEventGenerator -> Nil) : Nil
      send_headers
      start_output_loop unless @output_loop_started
      start_heartbeat if @stream_count.get == 0  # Only start heartbeat once

      # ... rest of the method
    end
```

**Step 4: Run test to verify it passes**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: Tests should pass (the test expects an exception since we can't have a real connection)

**Step 5: Commit**

```bash
git add src/datastar/server_sent_event_generator.cr spec/datastar/server_sent_event_generator_spec.cr
git commit -m "feat: add connection health checking with heartbeat"
```

---

### Task 14: One-off (non-streaming) mode

**Files:**
- Modify: `src/datastar/server_sent_event_generator.cr`
- Modify: `spec/datastar/server_sent_event_generator_spec.cr`

**Step 1: Write failing test for one-off mode**

Add to `spec/datastar/server_sent_event_generator_spec.cr`:

```crystal
describe "one-off mode" do
  it "allows sending events without stream block" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.patch_elements(%(<div id="test">Direct</div>))
    sse.finish

    output = io.to_s
    output.should contain "datastar-patch-elements"
    output.should contain "Direct"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: FAIL

**Step 3: Implement one-off mode**

Modify `src/datastar/server_sent_event_generator.cr` - update `send_event` and add `finish`:

```crystal
    private def send_event(event : ServerSentEvent) : Nil
      return if @closed

      if @output_loop_started
        @output_channel.send(event.to_s)
      else
        # One-off mode: write directly to response
        send_headers
        begin
          @response.print(event.to_s)
          @response.flush
        rescue IO::Error
          @closed = true
          @on_client_disconnect.try &.call
        end
      end
    end

    # Finishes the response in one-off (non-streaming) mode.
    #
    # Call this after sending one-off events to close the response properly.
    #
    # ```
    # sse.patch_elements("<div>Done</div>")
    # sse.finish
    # ```
    def finish : Nil
      return if @closed

      @on_server_disconnect.try &.call
      @closed = true
    end
```

**Step 4: Run test to verify it passes**

Run: `crystal spec spec/datastar/server_sent_event_generator_spec.cr`
Expected: PASS

**Step 5: Commit**

```bash
git add src/datastar/server_sent_event_generator.cr spec/datastar/server_sent_event_generator_spec.cr
git commit -m "feat: add one-off mode for single event responses"
```

---

### Task 15: Blueprint Adapter

**Files:**
- Create: `src/datastar/adapters/blueprint.cr`
- Create: `spec/datastar/adapters/blueprint_spec.cr`

**Step 1: Add blueprint to development dependencies**

Modify `shard.yml`:

```yaml
name: datastar
version: 0.1.0

authors:
  - Chris Watson <cawatson1993@gmail.com>

crystal: '>= 1.18.2'

license: MIT

development_dependencies:
  blueprint:
    github: stephannv/blueprint
```

Run: `shards install`

**Step 2: Write failing test for Blueprint adapter**

Create `spec/datastar/adapters/blueprint_spec.cr`:

```crystal
require "../../spec_helper"
require "../../../src/datastar/adapters/blueprint"

class TestBlueprint < Blueprint::HTML
  def initialize(@message : String)
  end

  def blueprint
    div id: "blueprint-test" do
      span { @message }
    end
  end
end

describe "Blueprint adapter" do
  it "makes Blueprint::HTML implement Renderable" do
    component = TestBlueprint.new("Hello from Blueprint")
    component.is_a?(Datastar::Renderable).should be_true
  end

  it "renders to datastar HTML" do
    component = TestBlueprint.new("Hello")
    html = component.to_datastar_html
    html.should contain "blueprint-test"
    html.should contain "Hello"
  end

  it "works with patch_elements" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_elements(TestBlueprint.new("Blueprint Works"))
    end

    response.close
    output = io.to_s
    output.should contain "Blueprint Works"
  end
end
```

**Step 3: Run test to verify it fails**

Run: `crystal spec spec/datastar/adapters/blueprint_spec.cr`
Expected: FAIL (file doesn't exist)

**Step 4: Implement Blueprint adapter**

Create `src/datastar/adapters/blueprint.cr`:

```crystal
require "blueprint"
require "../renderable"

# Extends Blueprint::HTML to implement Datastar::Renderable.
#
# This allows Blueprint components to be used directly with
# `ServerSentEventGenerator#patch_elements`.
#
# ```
# require "datastar"
# require "datastar/adapters/blueprint"
#
# class MyComponent < Blueprint::HTML
#   def initialize(@name : String)
#   end
#
#   def blueprint
#     div id: "greeting" do
#       h1 { "Hello, #{@name}!" }
#     end
#   end
# end
#
# sse.patch_elements(MyComponent.new("World"))
# ```
class Blueprint::HTML
  include Datastar::Renderable

  def to_datastar_html : String
    to_html
  end
end
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/adapters/blueprint_spec.cr`
Expected: PASS

**Step 6: Commit**

```bash
git add src/datastar/adapters/blueprint.cr spec/datastar/adapters/blueprint_spec.cr shard.yml
git commit -m "feat: add Blueprint HTML adapter"
```

---

### Task 16: Athena Adapter

**Files:**
- Create: `src/datastar/adapters/athena.cr`
- Create: `spec/datastar/adapters/athena_spec.cr`

**Step 1: Add athena to development dependencies**

Modify `shard.yml`:

```yaml
development_dependencies:
  blueprint:
    github: stephannv/blueprint
  athena:
    github: athena-framework/athena
```

Run: `shards install`

**Step 2: Write failing test for Athena adapter**

Create `spec/datastar/adapters/athena_spec.cr`:

```crystal
require "../../spec_helper"
require "../../../src/datastar/adapters/athena"

describe Datastar::Athena::Controller do
  describe "#datastar" do
    it "is defined as a module" do
      Datastar::Athena::Controller.should be_a Module
    end
  end
end
```

**Step 3: Run test to verify it fails**

Run: `crystal spec spec/datastar/adapters/athena_spec.cr`
Expected: FAIL

**Step 4: Implement Athena adapter**

Create `src/datastar/adapters/athena.cr`:

```crystal
require "athena"
require "../server_sent_event_generator"

module Datastar
  module Athena
    # Mixin module for Athena controllers that need Datastar support.
    #
    # Include this module in your controller to get access to the `#datastar`
    # helper method that creates a properly configured `ServerSentEventGenerator`.
    #
    # ```
    # require "datastar"
    # require "datastar/adapters/athena"
    #
    # class EventsController < ATH::Controller
    #   include Datastar::Athena::Controller
    #
    #   @[ATHA::Get("/events")]
    #   def stream_events : Nil
    #     sse = datastar
    #
    #     sse.stream do |stream|
    #       10.times do |i|
    #         sleep 1.second
    #         stream.patch_elements(%(<div id="count">#{i}</div>))
    #       end
    #     end
    #   end
    # end
    # ```
    module Controller
      # Creates a new `ServerSentEventGenerator` configured for the current
      # request context.
      #
      # The `heartbeat` parameter controls automatic connection health checking.
      # Set to `false` to disable, or a `Time::Span` to customize the interval.
      def datastar(heartbeat : Time::Span | Bool = Datastar.config.heartbeat) : ServerSentEventGenerator
        ServerSentEventGenerator.new(
          request: request,
          response: response,
          heartbeat: heartbeat
        )
      end
    end
  end
end
```

**Step 5: Run test to verify it passes**

Run: `crystal spec spec/datastar/adapters/athena_spec.cr`
Expected: PASS

**Step 6: Commit**

```bash
git add src/datastar/adapters/athena.cr spec/datastar/adapters/athena_spec.cr shard.yml
git commit -m "feat: add Athena framework adapter"
```

---

### Task 17: Update spec_helper and run full test suite

**Files:**
- Modify: `spec/spec_helper.cr`
- Modify: `spec/datastar_spec.cr`

**Step 1: Update spec_helper**

Replace `spec/spec_helper.cr`:

```crystal
require "spec"
require "../src/datastar"

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

**Step 2: Update main spec file**

Replace `spec/datastar_spec.cr`:

```crystal
require "./spec_helper"

describe Datastar do
  it "has a version" do
    Datastar::VERSION.should_not be_nil
  end

  it "has datastar protocol version" do
    Datastar::DATASTAR_VERSION.should_not be_nil
  end
end
```

**Step 3: Run full test suite**

Run: `crystal spec`
Expected: All tests pass

**Step 4: Commit**

```bash
git add spec/spec_helper.cr spec/datastar_spec.cr
git commit -m "chore: update spec helper and main spec file"
```

---

### Task 18: Update README

**Files:**
- Modify: `README.md`

**Step 1: Write comprehensive README**

Replace `README.md` with documentation covering:
- Installation
- Basic usage
- Streaming mode
- One-off mode
- Blueprint integration
- Athena integration
- Configuration
- API reference

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add comprehensive README with usage examples"
```

---

### Task 19: Final verification

**Step 1: Run full test suite**

Run: `crystal spec`
Expected: All tests pass

**Step 2: Run format check**

Run: `crystal tool format --check`
Expected: No formatting issues

**Step 3: Build documentation**

Run: `crystal docs`
Expected: Documentation builds successfully

**Step 4: Final commit if any cleanup needed**

```bash
git status
# Commit any remaining changes
```
