require "../spec_helper"

describe Datastar::ServerSentEvent do
  describe "#to_s" do
    it "formats a simple event" do
      event = Datastar::ServerSentEvent.new(
        event_type: Datastar::EventType::PatchElements,
        data_lines: ["<div>Hello</div>"]
      )
      event.to_s.should eq "event: datastar-patch-elements\ndata: <div>Hello</div>\n\n"
    end

    it "formats multiple data lines" do
      event = Datastar::ServerSentEvent.new(
        event_type: Datastar::EventType::PatchElements,
        data_lines: ["<div>", "  Hello", "</div>"]
      )
      event.to_s.should eq "event: datastar-patch-elements\ndata: <div>\ndata:   Hello\ndata: </div>\n\n"
    end

    it "includes id when provided" do
      event = Datastar::ServerSentEvent.new(
        event_type: Datastar::EventType::PatchElements,
        data_lines: ["test"],
        id: "123"
      )
      event.to_s.should contain "id: 123\n"
    end

    it "includes retry when provided" do
      event = Datastar::ServerSentEvent.new(
        event_type: Datastar::EventType::PatchElements,
        data_lines: ["test"],
        retry_duration: 5000
      )
      event.to_s.should contain "retry: 5000\n"
    end
  end
end
