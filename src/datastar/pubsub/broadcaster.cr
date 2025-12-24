require "./manager"
require "./event_collector"
require "./pubsub"

module Datastar::PubSub
  # Injectable broadcaster for dependency injection frameworks.
  #
  # In Athena, this can be registered as a service:
  # ```
  # @[ADI::Register]
  # class Datastar::PubSub::Broadcaster
  # end
  # ```
  class Broadcaster
    @manager : Manager

    def initialize(@manager : Manager = PubSub.manager!)
    end

    # Broadcasts events to all connections subscribed to a topic.
    def broadcast(topic : String, &block : EventCollector ->) : Nil
      collector = EventCollector.new
      yield collector
      @manager.broadcast(topic, collector.to_payload)
    end
  end
end
