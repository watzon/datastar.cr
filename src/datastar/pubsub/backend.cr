module Datastar::PubSub
  # Abstract base class for pub/sub backends.
  #
  # Backends handle message transport between servers. For single-server
  # deployments, use `MemoryBackend`. For multi-server, implement a
  # backend using Redis, NATS, or similar.
  abstract class Backend
    # Optional callback for error handling in backends.
    property on_error : Proc(Exception, Nil)?

    # Publishes a message to a topic.
    # For distributed backends, this sends to the external system.
    abstract def publish(topic : String, payload : String) : Nil

    # Subscribes to receive messages on a topic.
    # The block is called when a message arrives.
    # Returns a subscription ID for later unsubscribing.
    abstract def subscribe(topic : String, &block : String ->) : String

    # Unsubscribes from a topic using the subscription ID.
    abstract def unsubscribe(subscription_id : String) : Nil

    # Called on shutdown for cleanup. Override if needed.
    def close : Nil
    end
  end
end
