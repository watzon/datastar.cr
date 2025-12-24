# Datastar.cr

[![Standard Readme](https://img.shields.io/badge/readme%20style-standard-brightgreen.svg)](https://github.com/RichardLitt/standard-readme)
[![Crystal](https://img.shields.io/badge/crystal-%3E%3D1.18.2-black)](https://crystal-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Crystal SDK for the Datastar hypermedia framework.

Datastar is a lightweight (~10KB) framework that brings reactive UI updates to server-rendered applications using Server-Sent Events (SSE) and HTML data attributes. This SDK provides a type-safe Crystal API for streaming DOM updates, managing reactive signals, and executing scripts in the browser—all from your server-side code.

## Table of Contents

- [Datastar.cr](#datastarcr)
  - [Table of Contents](#table-of-contents)
  - [Background](#background)
  - [Install](#install)
  - [Usage](#usage)
    - [Quick Start](#quick-start)
    - [Streaming Mode](#streaming-mode)
    - [One-Off Mode](#one-off-mode)
  - [API](#api)
    - [DOM Manipulation](#dom-manipulation)
      - [`#patch_elements`](#patch_elements)
      - [`#remove_elements`](#remove_elements)
    - [Signal Management](#signal-management)
      - [`#patch_signals`](#patch_signals)
      - [`#remove_signals`](#remove_signals)
      - [Reading Signals](#reading-signals)
    - [Script Execution](#script-execution)
      - [`#execute_script`](#execute_script)
      - [`#redirect`](#redirect)
    - [Connection Management](#connection-management)
  - [Framework Integration](#framework-integration)
    - [Blueprint](#blueprint)
    - [Athena](#athena)
    - [Request Detection](#request-detection)
    - [Custom Components](#custom-components)
  - [Configuration](#configuration)
    - [Global](#global)
    - [Per-Instance](#per-instance)
  - [Maintainers](#maintainers)
  - [Contributing](#contributing)
  - [License](#license)

## Background

[Datastar](https://data-star.dev) combines the simplicity of server-side rendering with the interactivity of modern frontend frameworks. Instead of sending JSON and rebuilding the UI in JavaScript, Datastar streams HTML fragments directly from the server using SSE.

This SDK implements the [Datastar SSE protocol](https://data-star.dev/reference/sse_events) for Crystal, inspired by the official [Ruby SDK](https://github.com/starfederation/datastar-ruby).

**Key features:**

- Stream real-time UI updates via SSE
- Concurrent streaming with fiber-based concurrency
- Automatic heartbeat and connection health monitoring
- Built-in adapters for Blueprint and Athena frameworks
- Flexible rendering with the `Renderable` protocol

## Install

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  datastar:
    github: watzon/datastar.cr
```

Then run:

```bash
shards install
```

## Usage

### Quick Start

```crystal
require "datastar"

def handle_events(request, response)
  sse = Datastar::ServerSentEventGenerator.new(request, response)

  sse.stream do |stream|
    stream.patch_elements(%(<div id="greeting">Hello, Datastar!</div>))
  end
end
```

### Streaming Mode

Use `stream` for long-lived connections with multiple updates:

```crystal
sse.stream do |stream|
  10.times do |i|
    sleep 1.second
    stream.patch_elements(%(<div id="count">#{i}</div>))
  end
end
```

The stream block sets SSE headers, manages concurrency, and handles cleanup automatically.

### One-Off Mode

For single updates without persistent connections:

```crystal
sse.patch_elements(%(<div id="notification">Task completed!</div>))
sse.finish
```

## API

### DOM Manipulation

#### `#patch_elements`

Patch HTML fragments into the DOM:

```crystal
# Basic usage
sse.patch_elements(%(<div id="message">Hello!</div>))

# Target a specific element
sse.patch_elements(%(<p>Updated</p>), selector: "#target")

# Append to a list
sse.patch_elements(%(<li>New item</li>), selector: "#list", mode: Datastar::FragmentMergeMode::Append)

# Multiple fragments
sse.patch_elements([%(<div id="a">A</div>), %(<div id="b">B</div>)])
```

**Merge modes:** `Morph` (default), `Inner`, `Outer`, `Prepend`, `Append`, `Before`, `After`, `UpsertAttributes`

#### `#remove_elements`

```crystal
sse.remove_elements("#notification")
```

### Signal Management

#### `#patch_signals`

Update reactive signals:

```crystal
sse.patch_signals(count: 42, user: {name: "Alice"})
sse.patch_signals({enabled: true}, only_if_missing: true)
```

#### `#remove_signals`

```crystal
sse.remove_signals(["user.name", "user.email"])
```

#### Reading Signals

```crystal
# As JSON::Any
signals = sse.signals
count = signals["count"].as_i

# As typed struct
user = sse.signals(UserSignals)
```

### Script Execution

#### `#execute_script`

```crystal
sse.execute_script(%(console.log("Hello!")))
sse.execute_script("initWidget()", auto_remove: false)
sse.execute_script(%(import('./mod.js')), attributes: {"type" => "module"})
```

#### `#redirect`

```crystal
sse.redirect("/dashboard")
```

### Connection Management

```crystal
# Lifecycle callbacks
sse.on_connect { puts "Connected" }
sse.on_client_disconnect { puts "Client left" }
sse.on_server_disconnect { puts "Done streaming" }
sse.on_error { |ex| Log.error { ex.message } }

# Manual connection check
sse.check_connection!  # Raises IO::Error if closed

# Check connection state
sse.closed?
```

## Framework Integration

### Blueprint

```crystal
require "datastar"
require "datastar/adapters/blueprint"

class GreetingCard
  include Blueprint::HTML

  def initialize(@name : String); end

  def blueprint
    div id: "greeting" do
      h1 { "Hello, #{@name}!" }
    end
  end
end

sse.patch_elements(GreetingCard.new("World"))
```

### Athena

```crystal
require "athena"
require "datastar"
require "datastar/adapters/athena"

class EventsController < ATH::Controller
  include Datastar::Athena::LiveController

  @[ARTA::Get("/events")]
  def stream_events(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |stream|
      10.times do |i|
        sleep 1.second
        stream.patch_elements(%(<div id="count">#{i}</div>))
      end
    end
  end
end
```

The `LiveController` mixin also provides `datastar_render` for HTML responses:

```crystal
@[ARTA::Get("/")]
def index : ATH::Response
  datastar_render("<h1>Hello</h1>")
end
```

### Request Detection

Use `Datastar::RequestDetection` to tell whether a request came from Datastar:

```crystal
request = HTTP::Request.new("GET", "/?datastar=%7B%7D")
Datastar.datastar_request?(request) # => true
```

The Athena adapter exposes the same helper:

```crystal
if datastar_request?(request)
  datastar_render("<div>Datastar response</div>")
else
  datastar_render("<html>Full page</html>")
end
```

### Custom Components

Implement `Datastar::Renderable`:

```crystal
class MyComponent
  include Datastar::Renderable

  def initialize(@title : String); end

  def to_datastar_html : String
    %(<h1>#{@title}</h1>)
  end
end

sse.patch_elements(MyComponent.new("Hello"))
```

## Configuration

### Global

```crystal
Datastar.configure do |config|
  config.heartbeat = 5.seconds
  config.on_error = ->(ex : Exception) { Log.error { ex.message } }
end
```

### Per-Instance

```crystal
sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: 10.seconds)
sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)
```

## Maintainers

[@watzon](https://github.com/watzon)

## Contributing

PRs accepted.

1. Fork it (<https://github.com/watzon/datastar.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`crystal spec`)
5. Format your code (`crystal tool format`)
6. Commit your changes (`git commit -am 'Add some feature'`)
7. Push to the branch (`git push origin my-new-feature`)
8. Create a new Pull Request

See the [Datastar documentation](https://data-star.dev) for more information about the protocol.

## License

MIT © Chris Watson
