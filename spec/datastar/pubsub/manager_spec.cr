require "../../spec_helper"

describe Datastar::PubSub::Manager do
  describe "#subscribe" do
    it "registers a connection for a topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)

      manager.subscribe("topic1", conn)

      # Verify by broadcasting - connection should receive
      manager.broadcast("topic1", "hello")
      channel.receive.should eq "hello"
    end

    it "supports multiple connections per topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel1 = Channel(String).new(10)
      channel2 = Channel(String).new(10)
      conn1 = Datastar::PubSub::Connection.new(channel1)
      conn2 = Datastar::PubSub::Connection.new(channel2)

      manager.subscribe("topic", conn1)
      manager.subscribe("topic", conn2)
      manager.broadcast("topic", "broadcast")

      channel1.receive.should eq "broadcast"
      channel2.receive.should eq "broadcast"
    end

    it "fires on_subscribe callback" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      events = [] of Tuple(String, String)
      manager.on_subscribe = ->(topic : String, conn_id : String) {
        events << {topic, conn_id}
        nil
      }

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new("conn-1", channel)
      manager.subscribe("my-topic", conn)

      events.should eq [{"my-topic", "conn-1"}]
    end
  end

  describe "#unsubscribe_all" do
    it "removes connection from all topics" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)

      manager.subscribe("topic1", conn)
      manager.subscribe("topic2", conn)
      manager.unsubscribe_all(conn)

      # Broadcasts should not be received
      manager.broadcast("topic1", "msg1")
      manager.broadcast("topic2", "msg2")

      select
      when msg = channel.receive
        fail "Should not receive: #{msg}"
      when timeout(10.milliseconds)
        # Expected - no message received
      end
    end

    it "fires on_unsubscribe callback for each topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      events = [] of Tuple(String, String)
      manager.on_unsubscribe = ->(topic : String, conn_id : String) {
        events << {topic, conn_id}
        nil
      }

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new("conn-1", channel)

      manager.subscribe("topic1", conn)
      manager.subscribe("topic2", conn)
      manager.unsubscribe_all(conn)

      events.size.should eq 2
      events.should contain({"topic1", "conn-1"})
      events.should contain({"topic2", "conn-1"})
    end
  end

  describe "#broadcast" do
    it "delivers to all subscribers of a topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel1 = Channel(String).new(10)
      channel2 = Channel(String).new(10)
      conn1 = Datastar::PubSub::Connection.new(channel1)
      conn2 = Datastar::PubSub::Connection.new(channel2)

      manager.subscribe("room", conn1)
      manager.subscribe("room", conn2)
      manager.broadcast("room", "hello everyone")

      channel1.receive.should eq "hello everyone"
      channel2.receive.should eq "hello everyone"
    end

    it "handles broadcast to empty topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      # Should not raise
      manager.broadcast("empty", "message")
    end

    it "handles closed channels gracefully" do
      backend = Datastar::PubSub::MemoryBackend.new
      manager = Datastar::PubSub::Manager.new(backend)

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)

      manager.subscribe("topic", conn)
      channel.close

      # Should not raise
      manager.broadcast("topic", "message")
    end
  end
end
