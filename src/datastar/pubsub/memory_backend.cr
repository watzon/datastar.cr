require "uuid"
require "./backend"

module Datastar::PubSub
  # In-memory pub/sub backend for single-server deployments.
  #
  # Messages are delivered synchronously within the same process.
  # For multi-server deployments, use a distributed backend like Redis.
  class MemoryBackend < Backend
    @mutex : Mutex
    @subscriptions : Hash(String, Hash(String, Proc(String, Nil)))

    def initialize
      @mutex = Mutex.new
      @subscriptions = Hash(String, Hash(String, Proc(String, Nil))).new
    end

    def publish(topic : String, payload : String) : Nil
      subscribers = @mutex.synchronize do
        @subscriptions[topic]?.try(&.values.dup)
      end

      subscribers.try &.each do |callback|
        begin
          callback.call(payload)
        rescue ex
          @on_error.try &.call(ex)
        end
      end
    end

    def subscribe(topic : String, &block : String ->) : String
      id = UUID.random.to_s

      @mutex.synchronize do
        @subscriptions[topic] ||= Hash(String, Proc(String, Nil)).new
        @subscriptions[topic][id] = block
      end

      id
    end

    def unsubscribe(subscription_id : String) : Nil
      @mutex.synchronize do
        @subscriptions.each_value do |topic_subs|
          topic_subs.delete(subscription_id)
        end
      end
    end

    def close : Nil
      @mutex.synchronize do
        @subscriptions.clear
      end
    end
  end
end
