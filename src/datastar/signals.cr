require "json"
require "uri"

module Datastar
  # Handles parsing of signals sent from the browser.
  #
  # Signals can be sent via the `Datastar-Signal` header as JSON (possibly URL-encoded).
  module Signals
    extend self

    # Parses a JSON string into JSON::Any.
    def parse(json : String?) : JSON::Any
      return JSON::Any.new({} of String => JSON::Any) if json.nil? || json.empty?
      JSON.parse(json)
    end

    # Parses a JSON string into a typed object.
    def parse(json : String?, type : T.class) : T forall T
      raise ArgumentError.new("Cannot parse nil or empty string to #{T}") if json.nil? || json.empty?
      T.from_json(json)
    end

    # Extracts signals from an HTTP request.
    #
    # Looks for the `Datastar-Signal` header and parses it as JSON.
    # The header value may be URL-encoded.
    def from_request(request : HTTP::Request) : JSON::Any
      header = request.headers[DATASTAR_SIGNAL_HEADER]?
      return JSON::Any.new({} of String => JSON::Any) if header.nil? || header.empty?

      # Try to URL-decode if it looks encoded
      decoded = begin
        URI.decode_www_form(header)
      rescue
        header
      end

      parse(decoded)
    end

    # Extracts signals from an HTTP request into a typed object.
    def from_request(request : HTTP::Request, type : T.class) : T forall T
      header = request.headers[DATASTAR_SIGNAL_HEADER]?
      raise ArgumentError.new("No #{DATASTAR_SIGNAL_HEADER} header found") if header.nil? || header.empty?

      decoded = begin
        URI.decode_www_form(header)
      rescue
        header
      end

      parse(decoded, type)
    end
  end
end
