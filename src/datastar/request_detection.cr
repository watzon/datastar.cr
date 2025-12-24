require "uri"

module Datastar
  # Helpers for identifying Datastar-initiated requests.
  module RequestDetection
    DEFAULT_HEADER_NAMES = ["Datastar-Request"]
    DEFAULT_HEADER_VALUES = [] of String

    def self.datastar_request?(
      request : HTTP::Request,
      *,
      header_names : Array(String) = DEFAULT_HEADER_NAMES,
      header_values : Array(String) = DEFAULT_HEADER_VALUES,
      check_query : Bool = true,
    ) : Bool
      headers = request.headers

      header_names.each do |name|
        if value = headers[name]?
          return true if header_values.empty?

          normalized = value.downcase
          return true if header_values.any? { |expected| normalized == expected }
        end
      end

      if check_query && request.method == "GET"
        if query = request.query
          params = URI::Params.parse(query)
          return true if params.has_key?(DATASTAR_QUERY_PARAM)
        end
      end

      false
    end
  end
end
