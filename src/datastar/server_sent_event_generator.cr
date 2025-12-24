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
    @output_channel : Channel(String) = Channel(String).new(100)
    @stream_count : Atomic(Int32) = Atomic(Int32).new(0)
    @output_loop_started : Bool = false
    @completion_channel : Channel(Nil) = Channel(Nil).new

    def initialize(
      @request : HTTP::Request,
      @response : HTTP::Server::Response,
      @heartbeat : Time::Span | Bool = Datastar.config.heartbeat,
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
      start_heartbeat if @stream_count.get == 0 # Only start heartbeat once

      @stream_count.add(1)

      spawn do
        begin
          block.call(self)
        rescue ex
          handle_error(ex)
        ensure
          # Atomic#sub returns the OLD value, so if it was 1, it's now 0
          old_count = @stream_count.sub(1)
          if old_count == 1
            # Last stream finished, close the output channel
            @output_channel.close
          end
        end
      end

      # Wait for completion signal from output loop
      @completion_channel.receive

      @on_server_disconnect.try &.call unless @closed
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
        # Signal completion when channel is closed and all events processed
        @completion_channel.send(nil)
      end
    end

    private def send_event(event : ServerSentEvent) : Nil
      return if @closed

      if @output_loop_started
        # Streaming mode: send through channel
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
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION,
    ) : Nil
      patch_elements([fragment], selector: selector, mode: mode, use_view_transition: use_view_transition)
    end

    # Patches multiple elements into the DOM.
    def patch_elements(
      fragments : Array(String | Renderable),
      *,
      selector : String = WHOLE_DOCUMENT_SELECTOR,
      mode : FragmentMergeMode = DEFAULT_FRAGMENT_MERGE_MODE,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION,
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
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION,
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

    # Patches signals (reactive state) in the browser.
    #
    # See https://data-star.dev/reference/sse_events#datastar-patch-signals
    #
    # ```
    # sse.patch_signals(count: 42, user: {name: "Alice"})
    # sse.patch_signals({enabled: true}, only_if_missing: true)
    # ```
    def patch_signals(
      **signals,
    ) : Nil
      patch_signals(signals, only_if_missing: DEFAULT_SIGNALS_ONLY_IF_MISSING)
    end

    # :ditto:
    def patch_signals(
      signals : Hash | NamedTuple,
      *,
      only_if_missing : Bool = DEFAULT_SIGNALS_ONLY_IF_MISSING,
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
      attributes : Hash(String, String) = {} of String => String,
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
      rescue ex : IO::Error
        @closed = true
        @on_client_disconnect.try &.call
        raise ex
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
  end
end
