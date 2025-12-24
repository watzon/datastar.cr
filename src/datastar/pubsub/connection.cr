require "uuid"

module Datastar::PubSub
  # Wraps a client connection for pub/sub tracking.
  # Holds reference to the output channel for sending broadcasts.
  class Connection
    getter id : String
    getter output_channel : Channel(String)

    def initialize(@id : String, @output_channel : Channel(String))
    end

    def initialize(@output_channel : Channel(String))
      @id = UUID.random.to_s
    end

    # Sends a message to this connection's output channel.
    # Raises Channel::ClosedError if the channel is closed.
    def send(message : String) : Nil
      @output_channel.send(message)
    end
  end
end
