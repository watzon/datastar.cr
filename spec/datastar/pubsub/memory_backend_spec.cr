require "../../spec_helper"

describe Datastar::PubSub::MemoryBackend do
  describe "#publish and #subscribe" do
    it "delivers messages to subscribers" do
      backend = Datastar::PubSub::MemoryBackend.new
      received = [] of String

      backend.subscribe("topic1") { |msg| received << msg }
      backend.publish("topic1", "hello")
      backend.publish("topic1", "world")

      received.should eq ["hello", "world"]
    end

    it "only delivers to matching topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      received1 = [] of String
      received2 = [] of String

      backend.subscribe("topic1") { |msg| received1 << msg }
      backend.subscribe("topic2") { |msg| received2 << msg }

      backend.publish("topic1", "for-1")
      backend.publish("topic2", "for-2")

      received1.should eq ["for-1"]
      received2.should eq ["for-2"]
    end

    it "supports multiple subscribers per topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      received1 = [] of String
      received2 = [] of String

      backend.subscribe("topic") { |msg| received1 << msg }
      backend.subscribe("topic") { |msg| received2 << msg }

      backend.publish("topic", "broadcast")

      received1.should eq ["broadcast"]
      received2.should eq ["broadcast"]
    end

    it "handles publish to empty topic" do
      backend = Datastar::PubSub::MemoryBackend.new
      # Should not raise
      backend.publish("empty", "message")
    end
  end

  describe "#unsubscribe" do
    it "stops delivering messages after unsubscribe" do
      backend = Datastar::PubSub::MemoryBackend.new
      received = [] of String

      sub_id = backend.subscribe("topic") { |msg| received << msg }
      backend.publish("topic", "before")

      backend.unsubscribe(sub_id)
      backend.publish("topic", "after")

      received.should eq ["before"]
    end

    it "handles unsubscribe of unknown id" do
      backend = Datastar::PubSub::MemoryBackend.new
      # Should not raise
      backend.unsubscribe("unknown-id")
    end
  end

  describe "#close" do
    it "clears all subscriptions" do
      backend = Datastar::PubSub::MemoryBackend.new
      received = [] of String

      backend.subscribe("topic") { |msg| received << msg }
      backend.close
      backend.publish("topic", "after-close")

      received.should be_empty
    end
  end
end
