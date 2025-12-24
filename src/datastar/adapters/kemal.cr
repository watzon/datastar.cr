require "kemal"
require "../server_sent_event_generator"

module Datastar
  module Kemal
    # Mixin module for Kemal routes that adds Datastar SSE support.
    #
    # This module is automatically included in HTTP::Server::Context
    # when you require this adapter, giving you access to `datastar_stream`,
    # `datastar_render`, and `datastar_request?` helper methods.
    #
    # Example:
    # ```
    # require "kemal"
    # require "datastar/adapters/kemal"
    #
    # get "/events" do |env|
    #   env.datastar_stream do |sse|
    #     sse.patch_elements("<div id='message'>Hello!</div>")
    #   end
    # end
    # ```
    module Helpers
      # Creates a streaming SSE response for Datastar.
      #
      # This method sets up the proper SSE headers and yields a
      # `ServerSentEventGenerator` that you can use to send events.
      #
      # Example:
      # ```
      # get "/counter" do |env|
      #   env.datastar_stream do |sse|
      #     10.times do |i|
      #       sse.patch_elements(%(<div id="count">#{i}</div>))
      #       sleep 1.second
      #     end
      #   end
      # end
      # ```
      def datastar_stream(
        heartbeat : Time::Span | Bool = Datastar.config.heartbeat,
        &block : ServerSentEventGenerator ->
      ) : Nil
        sse = ServerSentEventGenerator.new(request, response, heartbeat)
        sse.stream do |stream|
          block.call(stream)
        end
      end

      # Renders a Datastar-compatible HTML response.
      #
      # Accepts either a raw HTML string or any object implementing
      # the `Renderable` protocol (like Blueprint components).
      #
      # Example:
      # ```
      # get "/" do |env|
      #   env.datastar_render(MyPage.new)
      # end
      # ```
      def datastar_render(
        fragment : String | Renderable,
        *,
        status : Int32 = 200,
      ) : String
        response.status_code = status
        response.content_type = "text/html; charset=utf-8"
        fragment.is_a?(Renderable) ? fragment.to_datastar_html : fragment
      end

      # Returns true if the request looks like a Datastar client request.
      #
      # This checks for the Datastar-Request header or the datastar query
      # parameter, indicating the request came from the Datastar frontend.
      #
      # Example:
      # ```
      # get "/" do |env|
      #   if env.datastar_request?
      #     # Return fragment for Datastar
      #     env.datastar_render("<div>Fragment</div>")
      #   else
      #     # Return full page
      #     render "views/index.ecr"
      #   end
      # end
      # ```
      def datastar_request?(
        *,
        header_names : Array(String) = Datastar::RequestDetection::DEFAULT_HEADER_NAMES,
        header_values : Array(String) = Datastar::RequestDetection::DEFAULT_HEADER_VALUES,
        check_query : Bool = true,
      ) : Bool
        Datastar.datastar_request?(
          request,
          header_names: header_names,
          header_values: header_values,
          check_query: check_query
        )
      end
    end
  end
end

# Extend HTTP::Server::Context with Datastar helpers
class HTTP::Server::Context
  include Datastar::Kemal::Helpers
end
