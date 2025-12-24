# Datastar.cr

A Crystal SDK for [Datastar](https://data-star.dev), the hypermedia framework that extends HTML with reactive signals and server-sent events.

Datastar enables you to build interactive web applications using server-side rendering with minimal JavaScript. This SDK provides a type-safe, ergonomic API for streaming UI updates to the browser using Server-Sent Events (SSE).

## Features

- **Server-Sent Events** - Stream real-time updates to the browser
- **Concurrent Streaming** - Run multiple stream blocks in parallel with fiber-based concurrency
- **Connection Health Monitoring** - Automatic heartbeat and client disconnection detection
- **Type-Safe API** - Full Crystal type safety with compile-time guarantees
- **Framework Integration** - Built-in adapters for Blueprint and Athena
- **Flexible Rendering** - Support for HTML strings, custom components, and template engines
- **Signal Management** - Patch and remove reactive signals in the browser
- **DOM Manipulation** - Patch, merge, append, and remove DOM elements
- **Script Execution** - Execute JavaScript in the browser context

## Installation

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

## Quick Start

```crystal
require "datastar"

# In your HTTP handler
def handle_events(request, response)
  sse = Datastar::ServerSentEventGenerator.new(request, response)

  sse.stream do |stream|
    stream.patch_elements(%(<div id="greeting">Hello, Datastar!</div>))
  end
end
```

## Basic Usage

### Creating a ServerSentEventGenerator

The `ServerSentEventGenerator` is the main interface for streaming updates to the browser:

```crystal
require "datastar"

# Basic initialization
sse = Datastar::ServerSentEventGenerator.new(request, response)

# Custom heartbeat interval (default: 3 seconds)
sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: 5.seconds)

# Disable heartbeat
sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)
```

### Streaming Mode

Use `stream` for long-lived connections that send multiple updates:

```crystal
sse.stream do |stream|
  10.times do |i|
    sleep 1.second
    stream.patch_elements(%(<div id="count">#{i}</div>))
  end
end
```

The stream block automatically:
- Sets proper SSE headers (`text/event-stream`, `Cache-Control`, etc.)
- Manages concurrent access through channels
- Handles connection lifecycle events
- Cleans up resources when the block completes

### One-Off Mode

For single updates without a persistent connection:

```crystal
sse.patch_elements(%(<div id="notification">Task completed!</div>))
sse.finish
```

## API Reference

### DOM Manipulation

#### `#patch_elements`

Patch HTML fragments into the DOM with various merge strategies:

```crystal
# Basic usage - morphs the entire document
sse.patch_elements(%(<div id="message">Hello!</div>))

# Target a specific element
sse.patch_elements(
  %(<p>Updated content</p>),
  selector: "#target"
)

# Append to a list
sse.patch_elements(
  %(<li>New item</li>),
  selector: "#list",
  mode: Datastar::FragmentMergeMode::Append
)

# Multiple fragments at once
sse.patch_elements([
  %(<div id="header">Header</div>),
  %(<div id="footer">Footer</div>)
])

# Use view transitions for smooth animations
sse.patch_elements(
  %(<div id="card">Updated card</div>),
  use_view_transition: true
)
```

**Merge Modes:**
- `Morph` (default) - Intelligently merge with existing DOM
- `Inner` - Replace inner HTML
- `Outer` - Replace entire element
- `Prepend` - Insert at the beginning
- `Append` - Insert at the end
- `Before` - Insert before element
- `After` - Insert after element
- `UpsertAttributes` - Merge attributes only

#### `#remove_elements`

Remove elements from the DOM:

```crystal
# Remove a specific element
sse.remove_elements("#notification")

# Remove with view transition
sse.remove_elements("#old-content", use_view_transition: true)
```

### Signal Management

Signals are Datastar's reactive state system. Update signals on the server to reactively update the UI.

#### `#patch_signals`

Update reactive signals in the browser:

```crystal
# Using named arguments
sse.patch_signals(count: 42, user: {name: "Alice", email: "alice@example.com"})

# Using a hash
sse.patch_signals({
  "isLoading" => false,
  "items" => [1, 2, 3]
})

# Only set if signal doesn't exist
sse.patch_signals({enabled: true}, only_if_missing: true)
```

#### `#remove_signals`

Remove signals from the browser state:

```crystal
sse.remove_signals(["user.name", "user.email"])
```

#### Reading Signals

Access signals sent from the browser:

```crystal
# As JSON::Any
signals = sse.signals
count = signals["count"].as_i

# As typed object
struct UserSignals
  include JSON::Serializable

  property name : String
  property email : String
end

user_signals = sse.signals(UserSignals)
puts user_signals.name
```

### Script Execution

#### `#execute_script`

Execute JavaScript in the browser:

```crystal
# Basic script execution
sse.execute_script(%(console.log("Hello from server!")))

# Keep the script tag in the DOM
sse.execute_script("initializeWidget()", auto_remove: false)

# Add custom attributes (e.g., for ES modules)
sse.execute_script(
  %(import('./module.js')),
  attributes: {"type" => "module"}
)
```

#### `#redirect`

Redirect the browser to a new URL:

```crystal
sse.redirect("/dashboard")
sse.redirect("https://example.com")
```

### Connection Management

#### Lifecycle Callbacks

Register callbacks for connection events:

```crystal
sse.on_connect do
  puts "Client connected"
end

sse.on_client_disconnect do
  puts "Client disconnected"
end

sse.on_server_disconnect do
  puts "Server finished streaming"
end

sse.on_error do |ex|
  puts "Error: #{ex.message}"
end
```

#### `#check_connection!`

Manually verify the connection is still alive:

```crystal
sse.stream do |stream|
  loop do
    stream.check_connection!  # Raises IO::Error if closed
    # ... wait for events ...
  end
end
```

#### `#closed?`

Check if the connection has been closed:

```crystal
if sse.closed?
  puts "Connection is closed"
end
```

## Concurrent Streaming

Multiple stream blocks can run concurrently using Crystal's fibers:

```crystal
sse.stream do |stream|
  # Spawn concurrent updates
  spawn do
    10.times do |i|
      sleep 1.second
      stream.patch_signals(counter1: i)
    end
  end

  spawn do
    5.times do |i|
      sleep 2.seconds
      stream.patch_signals(counter2: i)
    end
  end
end
```

All output is safely serialized through channels to ensure thread-safe writes to the response.

## Framework Integration

### Blueprint Integration

Use Blueprint components directly with Datastar:

```crystal
require "datastar"
require "datastar/adapters/blueprint"

class GreetingCard
  include Blueprint::HTML

  def initialize(@name : String)
  end

  def blueprint
    div id: "greeting", class: "card" do
      h1 { "Hello, #{@name}!" }
      p { "Welcome to Datastar" }
    end
  end
end

sse.stream do |stream|
  stream.patch_elements(GreetingCard.new("World"))
end
```

### Athena Integration

Use the Athena adapter for seamless integration with the Athena web framework:

```crystal
require "athena"
require "datastar"
require "datastar/adapters/athena"

class EventsController < ATH::Controller
  include Datastar::Athena::Controller

  @[ARTA::Get("/events")]
  def stream_events : Nil
    sse = datastar

    sse.stream do |stream|
      10.times do |i|
        sleep 1.second
        stream.patch_elements(%(<div id="count">#{i}</div>))
      end
    end
  end

  @[ARTA::Post("/notify")]
  def one_off_notification : Nil
    sse = datastar
    sse.patch_elements(%(<div id="notification">Done!</div>))
    sse.finish
  end
end
```

### Custom Component Integration

Implement the `Datastar::Renderable` protocol for custom components:

```crystal
class CustomComponent
  include Datastar::Renderable

  def initialize(@title : String, @items : Array(String))
  end

  def to_datastar_html : String
    String.build do |str|
      str << %(<div class="custom">)
      str << %(<h2>#{@title}</h2>)
      str << %(<ul>)
      @items.each do |item|
        str << %(<li>#{item}</li>)
      end
      str << %(</ul></div>)
    end
  end
end

sse.patch_elements(CustomComponent.new("Tasks", ["Buy milk", "Walk dog"]))
```

## Configuration

### Global Configuration

Configure global defaults:

```crystal
Datastar.configure do |config|
  # Set default heartbeat interval
  config.heartbeat = 5.seconds

  # Global error handler
  config.on_error = ->(ex : Exception) {
    Log.error { "Datastar error: #{ex.message}" }
  }
end
```

### Per-Instance Configuration

Override settings per instance:

```crystal
# Custom heartbeat
sse = Datastar::ServerSentEventGenerator.new(
  request,
  response,
  heartbeat: 10.seconds
)

# Disable heartbeat
sse = Datastar::ServerSentEventGenerator.new(
  request,
  response,
  heartbeat: false
)

# Custom error handler
sse.on_error do |ex|
  puts "Connection error: #{ex.message}"
end
```

## Examples

### Real-Time Counter

```crystal
sse.stream do |stream|
  100.times do |i|
    sleep 0.1.seconds
    stream.patch_elements(%(<div id="counter">Count: #{i}</div>))
  end
end
```

### Live Search Results

```crystal
sse.stream do |stream|
  query = sse.signals["searchQuery"].as_s

  results = search_database(query)

  html = String.build do |str|
    results.each do |result|
      str << %(<div class="result">#{result.title}</div>)
    end
  end

  stream.patch_elements(html, selector: "#results")
end
```

### Progress Indicator

```crystal
sse.stream do |stream|
  total_steps = 10

  total_steps.times do |step|
    # Perform work
    process_step(step)

    # Update progress
    progress = ((step + 1) / total_steps * 100).to_i
    stream.patch_signals(progress: progress)
    stream.patch_elements(
      %(<div class="progress-bar" style="width: #{progress}%"></div>),
      selector: "#progress"
    )
  end

  stream.patch_elements(%(<div class="success">Complete!</div>))
end
```

### Chat Application

```crystal
sse.stream do |stream|
  channel = subscribe_to_chat_room(room_id)

  channel.each do |message|
    stream.patch_elements(
      %(<div class="message">
        <strong>#{message.author}:</strong> #{message.text}
      </div>),
      selector: "#messages",
      mode: Datastar::FragmentMergeMode::Append
    )
  end
end
```

### Form Validation

```crystal
sse.stream do |stream|
  email = sse.signals["email"].as_s

  if valid_email?(email)
    stream.patch_elements(
      %(<span class="valid">✓ Email is valid</span>),
      selector: "#email-validation"
    )
    stream.patch_signals(emailValid: true)
  else
    stream.patch_elements(
      %(<span class="error">Invalid email format</span>),
      selector: "#email-validation"
    )
    stream.patch_signals(emailValid: false)
  end

  stream.finish
end
```

## Development

### Running Tests

```bash
crystal spec
```

### Building

```bash
shards build
```

### Code Style

This project follows the [Crystal coding style guide](https://crystal-lang.org/reference/conventions/coding_style.html).

Format your code with:

```bash
crystal tool format
```

## Contributing

1. Fork it (https://github.com/watzon/datastar.cr/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`crystal spec`)
5. Format your code (`crystal tool format`)
6. Commit your changes (`git commit -am 'Add some feature'`)
7. Push to the branch (`git push origin my-new-feature`)
8. Create a new Pull Request

## Resources

- [Datastar Documentation](https://data-star.dev)
- [API Documentation](https://watzon.github.io/datastar.cr)
- [Examples](https://github.com/watzon/datastar.cr/tree/main/examples)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributors

- [Chris Watson](https://github.com/watzon) - creator and maintainer
