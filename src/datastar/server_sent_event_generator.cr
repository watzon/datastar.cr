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
          if @stream_count.sub(1) == 0
            # Last stream finished, close the channel
            @output_channel.close
          end
        end
      end

      # Wait for all streams to complete
      until @output_channel.closed?
        Fiber.yield
      end

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
      end
    end

    private def send_event(event : ServerSentEvent) : Nil
      return if @closed
      @output_channel.send(event.to_s)
    end
  end
end
