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
    #   @[ARTA::Get("/events")]
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
