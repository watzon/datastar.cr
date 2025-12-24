require "json"

require "./configuration"
require "./consts"
require "./renderable"
require "./server_sent_event"
require "./pubsub/pubsub"

module Datastar
  # Shared SSE stream implementation backed by an IO.
  #
  # This class provides the core Datastar event API, streaming
  # concurrency, heartbeats, and lifecycle callbacks. It is used by
  # both the HTTP server generator and framework adapters.
  class EventStream
    getter io : IO
    getter heartbeat : Time::Span | Bool

    @on_connect : Proc(Nil)?
    @on_client_disconnect : Proc(Nil)?
    @on_server_disconnect : Proc(Nil)?
    @on_error : Proc(Exception, Nil)?
    @started : Bool = false
    @closed : Bool = false
    @output_channel : Channel(String) = Channel(String).new(100)
    @stream_count : Atomic(Int32) = Atomic(Int32).new(0)
    @output_loop_started : Bool = false
    @completion_channel : Channel(Nil) = Channel(Nil).new
    @pubsub_connection : PubSub::Connection?
    @pubsub_mutex : Mutex = Mutex.new

    def initialize(
      @io : IO,
      @heartbeat : Time::Span | Bool = Datastar.config.heartbeat,
    )
      @on_error = Datastar.config.on_error
    end

    # Registers a callback to run when the connection is first established.
    def on_connect(&block : -> Nil) : Nil
      @on_connect = block
      block.call if @started && !@closed
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

    # Subscribes this stream to a pub/sub topic.
    #
    # The connection will receive all broadcasts to the topic.
    # Automatically unsubscribes when the stream ends.
    def subscribe(topic : String) : Nil
      conn = @pubsub_mutex.synchronize do
        @pubsub_connection ||= PubSub::Connection.new(
          output_channel: @output_channel
        )
      end

      PubSub.manager!.subscribe(topic, conn)
    end

    # Returns true if the connection has been closed.
    def closed? : Bool
      @closed
    end

    # Executes a streaming block in a fiber.
    #
    # Multiple stream blocks can run concurrently. All output is serialized
    # through a channel to ensure thread-safe writes to the response.
    def stream(&block : self -> Nil) : Nil
      start_streaming
      start_output_loop unless @output_loop_started
      start_heartbeat if @stream_count.get == 0

      @stream_count.add(1)

      spawn do
        begin
          block.call(self)
        rescue ex
          handle_error(ex)
        ensure
          old_count = @stream_count.sub(1)
          if old_count == 1
            # Cleanup pub/sub subscriptions when last stream ends
            conn = @pubsub_mutex.synchronize { @pubsub_connection }
            if conn
              PubSub.manager!.unsubscribe_all(conn)
            end

            @output_channel.close
          end
        end
      end

      @completion_channel.receive
      @on_server_disconnect.try &.call unless @closed
    end

    # Patches elements into the DOM.
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

      unless selector.empty?
        data_lines << "selector #{selector}"
      end

      if mode != DEFAULT_FRAGMENT_MERGE_MODE
        data_lines << "mode #{mode.to_s.downcase}"
      end

      if use_view_transition
        data_lines << "useViewTransition true"
      end

      fragments.each do |fragment|
        html = fragment.is_a?(Renderable) ? fragment.to_datastar_html : fragment
        html.each_line do |line|
          data_lines << "elements #{line}"
        end
      end

      send_event(ServerSentEvent.new(
        event_type: EventType::PatchElements,
        data_lines: data_lines
      ))
    end

    # Removes elements from the DOM.
    def remove_elements(
      selector : String,
      *,
      use_view_transition : Bool = DEFAULT_USE_VIEW_TRANSITION,
    ) : Nil
      data_lines = ["selector #{selector}", "mode remove"]

      if use_view_transition
        data_lines.insert(1, "useViewTransition true")
      end

      send_event(ServerSentEvent.new(
        event_type: EventType::PatchElements,
        data_lines: data_lines
      ))
    end

    # Patches signals (reactive state) in the browser.
    def patch_signals(**signals) : Nil
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

      send_event(ServerSentEvent.new(
        event_type: EventType::PatchSignals,
        data_lines: data_lines
      ))
    end

    # Removes signals from the browser state.
    def remove_signals(paths : Array(String)) : Nil
      signals_hash = {} of String => Nil
      paths.each { |path| signals_hash[path] = nil }

      send_event(ServerSentEvent.new(
        event_type: EventType::PatchSignals,
        data_lines: ["signals #{signals_hash.to_json}"]
      ))
    end

    # Executes JavaScript in the browser.
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

      send_event(ServerSentEvent.new(
        event_type: EventType::ExecuteScript,
        data_lines: data_lines
      ))
    end

    # Redirects the browser to a new URL.
    def redirect(url : String) : Nil
      execute_script(%(window.location = "#{url}"))
    end

    # Checks if the client connection is still alive.
    #
    # Raises `IO::Error` if the connection has been closed.
    def check_connection! : Nil
      raise IO::Error.new("Connection closed") if @closed

      begin
        @io.print(": heartbeat\n\n")
        @io.flush
      rescue ex : IO::Error
        @closed = true
        @on_client_disconnect.try &.call
        raise ex
      end
    end

    # Finishes the response in one-off (non-streaming) mode.
    def finish : Nil
      return if @closed

      @on_server_disconnect.try &.call
      @closed = true
    end

    protected def start_streaming : Nil
      return if @started

      @started = true
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
            @io.print(event)
            @io.flush
          rescue IO::Error
            @closed = true
            @on_client_disconnect.try &.call
            @output_channel.close
            break
          end
        end
        @completion_channel.send(nil)
      end
    end

    protected def send_event(event : ServerSentEvent) : Nil
      return if @closed

      if @output_loop_started
        @output_channel.send(event.to_s)
      else
        start_streaming
        begin
          @io.print(event.to_s)
          @io.flush
        rescue IO::Error
          @closed = true
          @on_client_disconnect.try &.call
        end
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
  end
end
