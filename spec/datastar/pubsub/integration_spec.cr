require "../../spec_helper"

describe "PubSub Integration" do
  after_each do
    Datastar::PubSub.reset!
  end

  it "synchronizes multiple streams" do
    Datastar::PubSub.configure

    # Simulate two clients
    io1 = IO::Memory.new
    io2 = IO::Memory.new

    stream1 = Datastar::EventStream.new(io1, heartbeat: false)
    stream2 = Datastar::EventStream.new(io2, heartbeat: false)

    done = Channel(Nil).new

    # Client 1 subscribes and waits for broadcast
    spawn do
      stream1.stream do |sse|
        sse.subscribe("shared-room")
        sleep 100.milliseconds # Wait for broadcast
      end
      done.send(nil)
    end

    # Client 2 subscribes and waits for broadcast
    spawn do
      stream2.stream do |sse|
        sse.subscribe("shared-room")
        sleep 100.milliseconds # Wait for broadcast
      end
      done.send(nil)
    end

    # Give streams time to subscribe
    sleep 20.milliseconds

    # Broadcast to both
    Datastar::PubSub.broadcast("shared-room") do |sse|
      sse.patch_elements(%(<div id="msg">Hello both!</div>))
    end

    # Wait for both streams to complete
    done.receive
    done.receive

    # Both should have received the broadcast
    io1.to_s.should contain "Hello both!"
    io2.to_s.should contain "Hello both!"
  end

  it "isolates broadcasts by topic" do
    Datastar::PubSub.configure

    io1 = IO::Memory.new
    io2 = IO::Memory.new

    stream1 = Datastar::EventStream.new(io1, heartbeat: false)
    stream2 = Datastar::EventStream.new(io2, heartbeat: false)

    done = Channel(Nil).new

    spawn do
      stream1.stream do |sse|
        sse.subscribe("room-a")
        sleep 100.milliseconds
      end
      done.send(nil)
    end

    spawn do
      stream2.stream do |sse|
        sse.subscribe("room-b")
        sleep 100.milliseconds
      end
      done.send(nil)
    end

    sleep 20.milliseconds

    Datastar::PubSub.broadcast("room-a") do |sse|
      sse.patch_signals(for_room_a: true)
    end

    Datastar::PubSub.broadcast("room-b") do |sse|
      sse.patch_signals(for_room_b: true)
    end

    done.receive
    done.receive

    io1.to_s.should contain "for_room_a"
    io1.to_s.should_not contain "for_room_b"

    io2.to_s.should contain "for_room_b"
    io2.to_s.should_not contain "for_room_a"
  end

  it "tracks lifecycle with callbacks" do
    events = [] of String

    Datastar::PubSub.configure do |config|
      config.on_subscribe = ->(topic : String, conn_id : String) {
        events << "subscribe:#{topic}"
        nil
      }
      config.on_unsubscribe = ->(topic : String, conn_id : String) {
        events << "unsubscribe:#{topic}"
        nil
      }
    end

    io = IO::Memory.new
    stream = Datastar::EventStream.new(io, heartbeat: false)

    stream.stream do |sse|
      sse.subscribe("tracked-topic")
    end

    events.should eq ["subscribe:tracked-topic", "unsubscribe:tracked-topic"]
  end

  it "handles concurrent broadcasts correctly" do
    Datastar::PubSub.configure

    io = IO::Memory.new
    stream = Datastar::EventStream.new(io, heartbeat: false)

    done = Channel(Nil).new

    spawn do
      stream.stream do |sse|
        sse.subscribe("concurrent")
        sleep 150.milliseconds
      end
      done.send(nil)
    end

    sleep 20.milliseconds

    # Fire multiple broadcasts in parallel
    5.times do |i|
      spawn do
        Datastar::PubSub.broadcast("concurrent") do |sse|
          sse.patch_signals(msg: i)
        end
      end
    end

    done.receive

    output = io.to_s
    # All broadcasts should have been received
    output.scan(/datastar-patch-signals/).size.should eq 5
  end

  it "handles subscriber joining after broadcast" do
    Datastar::PubSub.configure

    # Broadcast first (no subscribers yet)
    Datastar::PubSub.broadcast("late-topic") do |sse|
      sse.patch_elements("<div>early message</div>")
    end

    # Now subscribe
    io = IO::Memory.new
    stream = Datastar::EventStream.new(io, heartbeat: false)

    done = Channel(Nil).new

    spawn do
      stream.stream do |sse|
        sse.subscribe("late-topic")

        # Wait for a new broadcast
        sleep 50.milliseconds
      end
      done.send(nil)
    end

    sleep 20.milliseconds

    # This broadcast should be received
    Datastar::PubSub.broadcast("late-topic") do |sse|
      sse.patch_elements("<div>late message</div>")
    end

    done.receive

    output = io.to_s
    output.should_not contain "early message"
    output.should contain "late message"
  end
end
