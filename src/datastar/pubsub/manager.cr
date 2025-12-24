require "./backend"
require "./connection"

module Datastar::PubSub
  # Manages local connections and coordinates with the backend.
  #
  # Tracks which connections are subscribed to which topics,
  # routes incoming broadcasts to appropriate connections,
  # and handles connection cleanup.
  class Manager
    @backend : Backend
    @mutex : Mutex

    # topic => Set of local Connection objects
    @local_connections : Hash(String, Set(Connection))

    # connection_id => Set of topics (for cleanup)
    @connection_topics : Hash(String, Set(String))

    # backend subscription IDs per topic
    @backend_subscriptions : Hash(String, String)

    # Lifecycle callbacks
    property on_subscribe : Proc(String, String, Nil)?
    property on_unsubscribe : Proc(String, String, Nil)?

    def initialize(@backend : Backend)
      @mutex = Mutex.new
      @local_connections = Hash(String, Set(Connection)).new
      @connection_topics = Hash(String, Set(String)).new
      @backend_subscriptions = Hash(String, String).new
    end

    # Subscribes a connection to a topic.
    def subscribe(topic : String, connection : Connection) : Nil
      should_call_callback = false

      @mutex.synchronize do
        @local_connections[topic] ||= Set(Connection).new

        # Idempotency check: if connection is already subscribed, return early
        if @local_connections[topic].includes?(connection)
          return
        end

        first_subscriber = @local_connections[topic].empty?
        @local_connections[topic] << connection

        @connection_topics[connection.id] ||= Set(String).new
        @connection_topics[connection.id] << topic

        # Subscribe to backend if first local subscriber for this topic
        if first_subscriber
          sub_id = @backend.subscribe(topic) { |payload| deliver(topic, payload) }
          @backend_subscriptions[topic] = sub_id
        end

        should_call_callback = true
      end

      @on_subscribe.try &.call(topic, connection.id) if should_call_callback
    end

    # Unsubscribes a connection from all topics.
    def unsubscribe_all(connection : Connection) : Nil
      topics = @mutex.synchronize do
        @connection_topics.delete(connection.id) || Set(String).new
      end

      topics.each do |topic|
        last_subscriber = false

        @mutex.synchronize do
          @local_connections[topic]?.try &.delete(connection)

          # Check if this was the last local subscriber
          if @local_connections[topic]?.try(&.empty?)
            @local_connections.delete(topic)
            last_subscriber = true
          end
        end

        # Unsubscribe from backend if last local subscriber
        if last_subscriber
          if sub_id = @mutex.synchronize { @backend_subscriptions.delete(topic) }
            @backend.unsubscribe(sub_id)
          end
        end

        @on_unsubscribe.try &.call(topic, connection.id)
      end
    end

    # Broadcasts a message to all subscribers of a topic.
    def broadcast(topic : String, payload : String) : Nil
      @backend.publish(topic, payload)
    end

    # Delivers a message to all local connections subscribed to a topic.
    private def deliver(topic : String, payload : String) : Nil
      connections = @mutex.synchronize do
        @local_connections[topic]?.try(&.dup) || Set(Connection).new
      end

      connections.each do |conn|
        begin
          conn.send(payload)
        rescue Channel::ClosedError
          # Connection already closed, will be cleaned up by stream's ensure block
        end
      end
    end
  end
end
