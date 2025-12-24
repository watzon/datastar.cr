module Datastar
  # Represents a single Server-Sent Event.
  #
  # This class handles the formatting of SSE events according to the
  # SSE specification and Datastar protocol.
  class ServerSentEvent
    getter event_type : String
    getter data_lines : Array(String)
    getter id : String?
    getter retry_duration : Int32?

    def initialize(
      @event_type : String,
      @data_lines : Array(String),
      @id : String? = nil,
      @retry_duration : Int32? = nil
    )
    end

    # Formats the event as an SSE string ready to be sent over the wire.
    def to_s(io : IO) : Nil
      io << "event: " << @event_type << "\n"

      if id = @id
        io << "id: " << id << "\n"
      end

      if retry = @retry_duration
        io << "retry: " << retry << "\n"
      end

      @data_lines.each do |line|
        io << "data: " << line << "\n"
      end

      io << "\n"
    end

    def to_s : String
      String.build { |io| to_s(io) }
    end
  end
end
