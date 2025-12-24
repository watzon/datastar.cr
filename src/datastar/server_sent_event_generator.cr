require "http/server"

require "./event_stream"
require "./signals"

module Datastar
  # Main class for generating Server-Sent Events for Datastar.
  #
  # This class handles the SSE protocol, concurrent streaming via fibers,
  # connection health monitoring, and lifecycle callbacks.
  class ServerSentEventGenerator < EventStream
    getter request : HTTP::Request
    getter response : HTTP::Server::Response

    @signals : JSON::Any?

    def initialize(
      @request : HTTP::Request,
      @response : HTTP::Server::Response,
      heartbeat : Time::Span | Bool = Datastar.config.heartbeat,
    )
      super(@response, heartbeat)
    end

    # Returns signals sent by the browser as JSON::Any.
    def signals : JSON::Any
      @signals ||= Signals.from_request(@request)
    end

    # Returns signals sent by the browser as a typed object.
    def signals(type : T.class) : T forall T
      Signals.from_request(@request, type)
    end

    protected def start_streaming : Nil
      return if @started

      @response.content_type = "text/event-stream"
      @response.headers["Cache-Control"] = "no-cache"
      @response.headers["Connection"] = "keep-alive"

      super
    end
  end
end
