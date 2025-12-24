require "../../spec_helper"

describe Datastar::PubSub do
  # Reset manager after each test
  after_each do
    Datastar::PubSub.reset!
  end

  describe ".configure" do
    it "sets up manager with default backend" do
      Datastar::PubSub.configure
      Datastar::PubSub.manager!.should_not be_nil
    end

    it "accepts custom backend" do
      backend = Datastar::PubSub::MemoryBackend.new
      Datastar::PubSub.configure(backend: backend)
      Datastar::PubSub.manager!.should_not be_nil
    end

    it "accepts block for configuration" do
      events = [] of Tuple(String, String)

      Datastar::PubSub.configure do |config|
        config.on_subscribe = ->(topic : String, id : String) {
          events << {topic, id}
          nil
        }
      end

      # Trigger a subscribe to verify callback is wired
      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new("test-conn", channel)
      Datastar::PubSub.manager!.subscribe("topic", conn)

      events.should eq [{"topic", "test-conn"}]
    end
  end

  describe ".manager!" do
    it "raises if not configured" do
      expect_raises(Exception, /not configured/) do
        Datastar::PubSub.manager!
      end
    end
  end

  describe ".broadcast" do
    it "broadcasts to subscribed connections" do
      Datastar::PubSub.configure

      channel = Channel(String).new(10)
      conn = Datastar::PubSub::Connection.new(channel)
      Datastar::PubSub.manager!.subscribe("updates", conn)

      Datastar::PubSub.broadcast("updates") do |sse|
        sse.patch_elements("<div>new</div>")
      end

      payload = channel.receive
      payload.should contain "datastar-patch-elements"
      payload.should contain "new"
    end
  end
end
