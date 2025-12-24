require "./backend"
require "./memory_backend"
require "./connection"
require "./manager"
require "./event_collector"

module Datastar::PubSub
  # Configuration class for pub/sub setup.
  class Configuration
    property backend : Backend = MemoryBackend.new
    property on_subscribe : Proc(String, String, Nil)?
    property on_unsubscribe : Proc(String, String, Nil)?
  end

  # The global manager instance.
  class_property manager : Manager?

  # Configures pub/sub with a block.
  def self.configure(&block : Configuration ->) : Nil
    config = Configuration.new
    yield config

    mgr = Manager.new(config.backend)
    mgr.on_subscribe = config.on_subscribe
    mgr.on_unsubscribe = config.on_unsubscribe
    @@manager = mgr
  end

  # Configures pub/sub with a backend.
  def self.configure(backend : Backend = MemoryBackend.new) : Nil
    @@manager = Manager.new(backend)
  end

  # Returns the manager, raising if not configured.
  def self.manager! : Manager
    @@manager || raise "Datastar::PubSub not configured. Call Datastar::PubSub.configure first."
  end

  # Broadcasts events to all connections subscribed to a topic.
  def self.broadcast(topic : String, &block : EventCollector ->) : Nil
    collector = EventCollector.new
    yield collector
    manager!.broadcast(topic, collector.to_payload)
  end

  # Resets the manager (for testing).
  def self.reset! : Nil
    @@manager = nil
  end
end
