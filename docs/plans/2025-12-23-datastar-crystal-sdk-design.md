# Datastar Crystal SDK Design

## Overview

A Crystal implementation of the [Datastar](https://data-star.dev/) hypermedia framework SDK, based on the official [Ruby SDK](https://github.com/starfederation/datastar-ruby).

Datastar is a lightweight (~10KB) framework that combines:
- **Backend reactivity** (like htmx) - server sends HTML/signals via SSE
- **Frontend reactivity** (like Alpine.js) - reactive signals using `data-*` attributes

## Design Decisions

| Decision | Choice |
|----------|--------|
| Framework support | Core + adapters, starting with Athena |
| Shard structure | Monorepo with optional requires (`datastar/adapters/*`) |
| Concurrency | Fibers + Channels for concurrent streaming |
| Rendering | Protocol-based (`Datastar::Renderable`), Blueprint adapter |
| Signals | Both `JSON::Any` and typed `signals(T)` |
| Heartbeat | Configurable fiber (default 3s), plus manual `check_connection!` |
| Callbacks | Block-based (`on_connect`, `on_error`, etc.) |
| Constants | Manually maintained |

## Project Structure

```
datastar.cr/
├── src/
│   ├── datastar.cr                    # Main entry, requires core
│   └── datastar/
│       ├── version.cr
│       ├── consts.cr                  # Protocol constants (event types, defaults)
│       ├── renderable.cr              # Renderable protocol
│       ├── server_sent_event.cr       # Individual SSE event builder
│       ├── server_sent_event_generator.cr  # Main SSE streaming class
│       ├── signals.cr                 # Signal parsing (JSON::Any + typed)
│       ├── configuration.cr           # Global config (heartbeat, on_error)
│       └── adapters/
│           ├── athena.cr              # Athena framework adapter
│           └── blueprint.cr           # Blueprint HTML adapter
├── spec/
└── shard.yml
```

## Core API

### ServerSentEventGenerator

The main class for SSE streaming:

```crystal
module Datastar
  class ServerSentEventGenerator
    # Initialize with raw IO (framework adapters wrap this)
    def initialize(
      request : HTTP::Request,
      response : HTTP::Server::Response,
      heartbeat : Time::Span | Bool = 3.seconds
    )

    # --- SSE Methods ---
    def patch_elements(html : String | Renderable, **options)
    def patch_elements(elements : Array(String | Renderable), **options)
    def remove_elements(selector : String, **options)

    def patch_signals(signals : Hash | NamedTuple, **options)
    def remove_signals(paths : Array(String), **options)

    def execute_script(script : String, **options)
    def redirect(url : String)

    # --- Signals from browser ---
    def signals : JSON::Any
    def signals(type : T.class) : T forall T

    # --- Streaming ---
    def stream(&block : SSE -> Nil)

    # --- Connection health ---
    def check_connection!

    # --- Lifecycle callbacks ---
    def on_connect(&block)
    def on_client_disconnect(&block)
    def on_server_disconnect(&block)
    def on_error(&block : Exception -> Nil)
  end
end
```

### Options

`patch_elements` options:
- `selector : String` - CSS selector for target element
- `mode : PatchMode` - morph, inner, outer, prepend, append, before, after, upsert_attributes
- `use_view_transition : Bool` - enable view transitions

`patch_signals` options:
- `only_if_missing : Bool` - only patch if signal doesn't exist

`execute_script` options:
- `auto_remove : Bool` - remove script tag after execution (default: true)
- `attributes : Hash` - additional attributes for script tag

## Renderable Protocol

```crystal
module Datastar
  module Renderable
    abstract def to_datastar_html : String
  end
end
```

Any object implementing this protocol can be passed to `patch_elements`.

## Blueprint Adapter

```crystal
# src/datastar/adapters/blueprint.cr
require "blueprint"

class Blueprint::HTML
  include Datastar::Renderable

  def to_datastar_html : String
    to_html
  end
end
```

## Athena Adapter

```crystal
# src/datastar/adapters/athena.cr
require "athena"

module Datastar
  module Athena
    module Controller
      def datastar(heartbeat : Time::Span | Bool = 3.seconds) : ServerSentEventGenerator
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

Usage:

```crystal
class EventsController < ATH::Controller
  include Datastar::Athena::Controller

  @[ATHA::Get("/updates")]
  def updates : Nil
    sse = datastar

    sse.on_client_disconnect { Log.info { "Client left" } }

    sse.stream do |stream|
      10.times do |i|
        sleep 1.second
        stream.patch_elements(%(<div id="count">#{i}</div>))
      end
    end
  end
end
```

## Concurrency Model

- Multiple `stream` blocks run concurrently in separate fibers
- All output serialized through a `Channel(String)`
- Output loop fiber reads from channel and writes to response
- Heartbeat fiber (if enabled) periodically checks connection health

```crystal
class ServerSentEventGenerator
  @output_channel : Channel(String)
  @stream_fibers : Array(Fiber)
  @heartbeat_fiber : Fiber?

  def stream(&block : SSE -> Nil)
    fiber = spawn do
      begin
        block.call(self)
      rescue ex
        handle_error(ex)
      end
    end
    @stream_fibers << fiber
  end

  private def write_event(data : String)
    @output_channel.send(data)
  end

  private def start_output_loop
    spawn do
      while event = @output_channel.receive?
        @response.print(event)
        @response.flush
      end
    end
  end
end
```

## Global Configuration

```crystal
module Datastar
  class Configuration
    property heartbeat : Time::Span | Bool = 3.seconds
    property on_error : Proc(Exception, Nil)? = nil
  end

  class_getter config = Configuration.new

  def self.configure(&block : Configuration -> Nil)
    yield config
  end
end
```

## Protocol Constants

```crystal
module Datastar
  DATASTAR_VERSION = "1.0.0-RC.7"

  module EventType
    PATCH_ELEMENTS  = "datastar-patch-elements"
    REMOVE_ELEMENTS = "datastar-remove-elements"
    PATCH_SIGNALS   = "datastar-patch-signals"
    REMOVE_SIGNALS  = "datastar-remove-signals"
    EXECUTE_SCRIPT  = "datastar-execute-script"
  end

  enum PatchMode
    Morph
    Inner
    Outer
    Prepend
    Append
    Before
    After
    UpsertAttributes
  end
end
```

## Adapters Planned

- `datastar/adapters/athena` - Athena framework integration
- `datastar/adapters/blueprint` - Blueprint HTML builder

Future adapters:
- Lucky framework
- Kemal
- Water templates
- ECR templates

## References

- [Datastar Documentation](https://data-star.dev/)
- [Datastar SSE Events Reference](https://data-star.dev/reference/sse_events)
- [Ruby SDK](https://github.com/starfederation/datastar-ruby)
- [Blueprint](https://github.com/stephannv/blueprint)
- [Athena Framework](https://athenaframework.org/)
