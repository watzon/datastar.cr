# Athena + Blueprint + Datastar Example

This example demonstrates how to use the Datastar Crystal SDK with the [Athena](https://athenaframework.org/) web framework and [Blueprint](https://github.com/stephannv/blueprint) HTML builder.

## Features Demonstrated

- **SSE Streaming**: Live counter and clock updates via Server-Sent Events
- **Blueprint Components**: Type-safe HTML generation with Blueprint
- **Layout Inheritance**: Using Blueprint's `around_render` for layouts
- **Datastar Integration**: Using the `Datastar::Athena::Controller` mixin
- **Signal Reading**: Reading reactive signals sent from the browser

## Prerequisites

- Crystal >= 1.18.2
- Shards

## Installation

```bash
cd examples/athena-blueprint
shards install
```

## Running

```bash
shards build
./bin/athena-blueprint
```

Then open http://localhost:3000 in your browser.

## Project Structure

```
├── src/
│   ├── athena-blueprint.cr    # Main entry point
│   ├── components/
│   │   ├── layout.cr          # MainLayout with around_render
│   │   ├── index_page.cr      # Index page extending MainLayout
│   │   └── counter.cr         # Counter, Clock, and Greeting components
│   └── controllers/
│       └── demo_controller.cr # Athena controller with SSE endpoints
├── shard.yml
└── README.md
```

## How It Works

### 1. Layout with around_render

Blueprint's `around_render` method wraps page content. Pages inherit from the layout:

```crystal
class MainLayout
  include Blueprint::HTML

  def page_title : String
    "Datastar Demo"
  end

  private def around_render(&)
    doctype
    html lang: "en" do
      head do
        title { page_title }
        script type: "module", defer: true,
               src: "https://cdn.jsdelivr.net/npm/@starfederation/datastar@1.0.0-beta.11/dist/datastar.min.js"
      end
      body do
        yield
      end
    end
  end
end

class IndexPage < MainLayout
  def page_title : String
    "My Page Title"
  end

  private def blueprint
    h1 { "Hello World" }
  end
end
```

### 2. Datastar Controller Integration

The `DemoController` uses the `Datastar::Athena::LiveController` mixin which provides `datastar_render` and `datastar_stream` helpers:

```crystal
class DemoController < ATH::Controller
  include Datastar::Athena::LiveController

  @[ARTA::Get("/")]
  def index : ATH::Response
    datastar_render(IndexPage.new)
  end

  @[ARTA::Get("/counter/start")]
  def start_counter(request : ATH::Request) : ATH::StreamedResponse
    datastar_stream(request) do |sse|
      20.times do |count|
        break if sse.closed?
        sse.patch_elements(Counter.new(count))
        sleep 1.second
      end
    end
  end
end
```

### 3. Datastar Attributes with Colons

Datastar uses colons in attribute names like `data-on:click`. In Blueprint, use quoted keys:

```crystal
# Regular attributes use underscores (converted to hyphens)
div data_signals: "{count: 0}" do
  # ...
end

# Attributes with colons use quoted keys
button "data-on:click": "@get('/endpoint')" do
  plain "Click me"
end

# Two-way binding
input type: "text", "data-bind": "name"

# With modifiers
button "data-on:click__debounce.500ms": "@get('/search')" do
  plain "Search"
end
```

### 4. Blueprint Components as Fragments

Blueprint components implement `Datastar::Renderable` automatically when you require the Blueprint adapter:

```crystal
require "datastar/adapters/blueprint"

class Counter
  include Blueprint::HTML

  def initialize(@count : Int32); end

  private def blueprint
    div id: "counter", class: "counter" do
      plain @count.to_s
    end
  end
end

# Use with SSE
sse.patch_elements(Counter.new(42))
```

## Demo Features

1. **Counter Demo**: Click "Start Counter" to stream a counter from 0-19
2. **Live Clock**: Shows the server time, updated every second
3. **Greeting Demo**: Enter your name and click "Greet Me!" to see a personalized greeting

## License

MIT
