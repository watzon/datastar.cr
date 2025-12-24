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
end
