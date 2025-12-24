require "../../spec_helper"

# Test implementation to verify abstract class works
class TestBackend < Datastar::PubSub::Backend
  getter published : Array(Tuple(String, String)) = [] of Tuple(String, String)
  getter subscriptions : Hash(String, Proc(String, Nil)) = {} of String => Proc(String, Nil)

  def publish(topic : String, payload : String) : Nil
    @published << {topic, payload}
    @subscriptions[topic]?.try &.call(payload)
  end

  def subscribe(topic : String, &block : String ->) : String
    id = "sub-#{@subscriptions.size}"
    @subscriptions[topic] = block
    id
  end

  def unsubscribe(subscription_id : String) : Nil
    # Simple implementation for test
  end
end

describe Datastar::PubSub::Backend do
  it "can be subclassed and used" do
    backend = TestBackend.new

    received = [] of String
    backend.subscribe("test") { |msg| received << msg }
    backend.publish("test", "hello")

    backend.published.should eq [{"test", "hello"}]
    received.should eq ["hello"]
  end

  it "supports on_error callback" do
    backend = TestBackend.new
    errors = [] of Exception

    backend.on_error = ->(ex : Exception) { errors << ex; nil }
    backend.on_error.should_not be_nil
  end

  it "close is a no-op by default" do
    backend = TestBackend.new
    backend.close # Should not raise
  end
end
