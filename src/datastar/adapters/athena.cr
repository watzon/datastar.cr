require "athena"
require "../event_stream"
require "../signals"
require "../pubsub"

module Datastar
  module Athena
    # A Datastar SSE writer for use with Athena's StreamedResponse.
    class SSEWriter < Datastar::EventStream
      getter request : ATH::Request

      @signals : JSON::Any?

      def initialize(
        @io : IO,
        @request : ATH::Request,
        heartbeat : Time::Span | Bool = Datastar.config.heartbeat,
      )
        super(@io, heartbeat)
      end

      # Returns signals sent by the browser as JSON::Any.
      def signals : JSON::Any
        @signals ||= Signals.from_request(@request.request)
      end

      # Returns signals sent by the browser as a typed object.
      def signals(type : T.class) : T forall T
        Signals.from_request(@request.request, type)
      end
    end

    # Mixin module for Athena controllers that need Datastar support.
    #
    # Include this module in your controller to get access to the `#datastar`
    # helper method that creates an SSE streaming response.
    module Controller
      # Creates a streaming SSE response for Datastar.
      def datastar(
        request : ATH::Request,
        heartbeat : Time::Span | Bool = Datastar.config.heartbeat,
        &block : SSEWriter -> Nil
      ) : ATH::StreamedResponse
        ATH::StreamedResponse.new(
          headers: HTTP::Headers{
            "content-type"  => "text/event-stream",
            "cache-control" => "no-cache",
            "connection"    => "keep-alive",
          }
        ) do |io|
          writer = SSEWriter.new(io, request, heartbeat)
          writer.stream do |stream|
            block.call(stream)
          end
        end
      end

      # Returns true if the request looks like a Datastar client request.
      def datastar_request?(
        request : ATH::Request,
        *,
        header_names : Array(String) = Datastar::RequestDetection::DEFAULT_HEADER_NAMES,
        header_values : Array(String) = Datastar::RequestDetection::DEFAULT_HEADER_VALUES,
        check_query : Bool = true,
      ) : Bool
        Datastar.datastar_request?(
          request.request,
          header_names: header_names,
          header_values: header_values,
          check_query: check_query
        )
      end

      # Broadcasts events to all clients subscribed to a topic.
      #
      # This is a convenience wrapper around `Datastar::PubSub.broadcast`.
      # Use this to push real-time updates to multiple connected clients.
      #
      # Example:
      # ```
      # class ChatController < ATH::Controller
      #   include Datastar::Athena::Controller
      #
      #   @[ARTA::Get("/subscribe/:room")]
      #   def subscribe(room : String, request : ATH::Request) : ATH::StreamedResponse
      #     datastar(request) do |sse|
      #       sse.subscribe("chat:#{room}")
      #     end
      #   end
      #
      #   @[ARTA::Post("/message/:room")]
      #   def send_message(room : String, request : ATH::Request) : ATH::Response
      #     message = request.request.body.try(&.gets_to_end) || ""
      #     datastar_broadcast("chat:#{room}") do |sse|
      #       sse.patch_elements(%(<div id="messages">#{message}</div>))
      #     end
      #     ATH::Response.new(status: :created)
      #   end
      # end
      # ```
      #
      # For dependency injection, you can also use `Datastar::PubSub::Broadcaster`:
      # ```
      # @[ADI::Register]
      # class MyBroadcaster < Datastar::PubSub::Broadcaster
      # end
      # ```
      def datastar_broadcast(topic : String, &block : PubSub::EventCollector ->) : Nil
        Datastar::PubSub.broadcast(topic, &block)
      end
    end

    # Opinionated controller mixin that layers Datastar convenience helpers.
    module LiveController
      include Datastar::Athena::Controller

      # Renders a Datastar-compatible HTML response.
      def datastar_render(
        fragment : String | Renderable,
        *,
        status : Int32 = 200,
        headers : HTTP::Headers = HTTP::Headers{"content-type" => "text/html; charset=utf-8"},
      ) : ATH::Response
        html = fragment.is_a?(Renderable) ? fragment.to_datastar_html : fragment
        ATH::Response.new(html, status: status, headers: headers)
      end

      # Convenience wrapper around `#datastar` for live streaming responses.
      def datastar_stream(
        request : ATH::Request,
        heartbeat : Time::Span | Bool = Datastar.config.heartbeat,
        &block : SSEWriter -> Nil
      ) : ATH::StreamedResponse
        datastar(request, heartbeat, &block)
      end
    end
  end
end
