require "../spec_helper"

describe Datastar::EventStream do
  it "streams events over an IO" do
    io = IO::Memory.new
    stream = Datastar::EventStream.new(io, heartbeat: false)

    stream.stream do |sse|
      sse.patch_elements(%(<div id="test">Hello</div>))
    end

    output = io.to_s
    output.should contain "event: datastar-patch-elements"
    output.should contain "data: elements <div id=\"test\">Hello</div>"
  end

  it "supports one-off mode" do
    io = IO::Memory.new
    stream = Datastar::EventStream.new(io, heartbeat: false)

    stream.patch_signals(count: 1)
    stream.finish

    output = io.to_s
    output.should contain "event: datastar-patch-signals"
    output.should contain "count"
  end

  describe "#subscribe" do
    after_each do
      Datastar::PubSub.reset!
    end

    it "subscribes to a topic and receives broadcasts" do
      Datastar::PubSub.configure

      io = IO::Memory.new
      stream = Datastar::EventStream.new(io, heartbeat: false)

      stream.stream do |sse|
        sse.subscribe("room-1")

        # Broadcast from another "client"
        spawn do
          sleep 10.milliseconds
          Datastar::PubSub.broadcast("room-1") do |bc|
            bc.patch_elements("<div>broadcast msg</div>")
          end
        end

        # Wait a bit for broadcast
        sleep 50.milliseconds
      end

      output = io.to_s
      output.should contain "broadcast msg"
    end

    it "automatically unsubscribes when stream ends" do
      Datastar::PubSub.configure

      unsubscribe_events = [] of String
      Datastar::PubSub.manager!.on_unsubscribe = ->(topic : String, conn_id : String) {
        unsubscribe_events << topic
        nil
      }

      io = IO::Memory.new
      stream = Datastar::EventStream.new(io, heartbeat: false)

      stream.stream do |sse|
        sse.subscribe("auto-cleanup")
      end

      unsubscribe_events.should eq ["auto-cleanup"]
    end

    it "supports multiple topic subscriptions" do
      Datastar::PubSub.configure

      io = IO::Memory.new
      stream = Datastar::EventStream.new(io, heartbeat: false)

      stream.stream do |sse|
        sse.subscribe("topic-a")
        sse.subscribe("topic-b")

        spawn do
          sleep 10.milliseconds
          Datastar::PubSub.broadcast("topic-a") do |bc|
            bc.patch_signals(from_a: true)
          end
          Datastar::PubSub.broadcast("topic-b") do |bc|
            bc.patch_signals(from_b: true)
          end
        end

        sleep 50.milliseconds
      end

      output = io.to_s
      output.should contain "from_a"
      output.should contain "from_b"
    end
  end
end
