require "json"
require "uri"

module Datastar
  # Handles parsing of signals sent from the browser.
  #
  # For GET requests, signals are sent via the `datastar` query parameter.
  # For other HTTP methods, signals are sent in the request body as JSON.
  module Signals
    extend self

    # Parses a JSON string into JSON::Any.
    def parse(json : String?) : JSON::Any
      return JSON::Any.new({} of String => JSON::Any) if json.nil? || json.empty?
      JSON.parse(json)
    rescue JSON::ParseException
      JSON::Any.new({} of String => JSON::Any)
    end

    # Parses a JSON string into a typed object.
    def parse(json : String?, type : T.class) : T forall T
      raise ArgumentError.new("Cannot parse nil or empty string to #{T}") if json.nil? || json.empty?
      T.from_json(json)
    end

    # Extracts signals from an HTTP request.
    #
    # For GET requests, looks for the `datastar` query parameter.
    # For other methods, parses the request body as JSON.
    def from_request(request : HTTP::Request) : JSON::Any
      if request.method == "GET"
        # For GET requests, signals are in the query parameter
        if query = request.query
          params = URI::Params.parse(query)
          if datastar_param = params[DATASTAR_QUERY_PARAM]?
            return parse(datastar_param)
          end
        end
        JSON::Any.new({} of String => JSON::Any)
      else
        # For other methods, parse the body
        if body = request.body
          content = body.gets_to_end
          return parse(content) unless content.empty?
        end
        JSON::Any.new({} of String => JSON::Any)
      end
    end

    # Extracts signals from an HTTP request into a typed object.
    def from_request(request : HTTP::Request, type : T.class) : T forall T
      if request.method == "GET"
        if query = request.query
          params = URI::Params.parse(query)
          if datastar_param = params[DATASTAR_QUERY_PARAM]?
            return parse(datastar_param, type)
          end
        end
        raise ArgumentError.new("No #{DATASTAR_QUERY_PARAM} query parameter found")
      else
        if body = request.body
          content = body.gets_to_end
          return parse(content, type) unless content.empty?
        end
        raise ArgumentError.new("No request body found")
      end
    end
  end
end
