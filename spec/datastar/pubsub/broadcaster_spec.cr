require "../../spec_helper"

describe Datastar::PubSub::Broadcaster do
  after_each do
    Datastar::PubSub.reset!
  end

  describe "#broadcast" do
    it "broadcasts to subscribed connections" do
      Datastar::PubSub.configure

      broadcaster = Datastar::PubSub::Broadcaster.new

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)
      Datastar::PubSub.manager!.subscribe("topic", conn)

      broadcaster.broadcast("topic") do |sse|
        sse.patch_signals(updated: true)
      end

      payload = channel.receive
      payload.should contain "datastar-patch-signals"
      payload.should contain "updated"
    end

    it "can be initialized with custom manager" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)
      broadcaster = Datastar::PubSub::Broadcaster.new(manager)

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)
      manager.subscribe("custom", conn)

      broadcaster.broadcast("custom") do |sse|
        sse.patch_elements("<span>test</span>")
      end

      payload = channel.receive
      payload.should contain "test"
    end
  end
end
