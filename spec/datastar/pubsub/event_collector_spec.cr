require "../../spec_helper"

describe Datastar::PubSub::EventCollector do
  describe "#patch_elements" do
    it "collects patch_elements events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_elements(%(<div id="test">Hello</div>))

      payload = collector.to_payload
      payload.should contain "event: datastar-patch-elements"
      payload.should contain "data: elements <div id=\"test\">Hello</div>"
    end

    it "supports selector option" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_elements("<p>Text</p>", selector: "#container")

      payload = collector.to_payload
      payload.should contain "data: selector #container"
    end
  end

  describe "#patch_signals" do
    it "collects patch_signals events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_signals({count: 5, name: "test"})

      payload = collector.to_payload
      payload.should contain "event: datastar-patch-signals"
      payload.should contain "count"
      payload.should contain "5"
    end

    it "supports named tuple syntax" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_signals(foo: "bar")

      payload = collector.to_payload
      payload.should contain "foo"
      payload.should contain "bar"
    end
  end

  describe "#execute_script" do
    it "collects execute_script events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.execute_script("console.log('hello')")

      payload = collector.to_payload
      payload.should contain "event: datastar-execute-script"
      payload.should contain "console.log"
    end
  end

  describe "#remove_elements" do
    it "collects remove_elements events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.remove_elements("#old-element")

      payload = collector.to_payload
      payload.should contain "event: datastar-patch-elements"
      payload.should contain "data: selector #old-element"
      payload.should contain "data: mode remove"
    end
  end

  describe "#to_payload" do
    it "concatenates multiple events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.patch_elements("<div>1</div>")
      collector.patch_signals(count: 1)

      payload = collector.to_payload
      payload.should contain "datastar-patch-elements"
      payload.should contain "datastar-patch-signals"
    end

    it "returns empty string when no events" do
      collector = Datastar::PubSub::EventCollector.new
      collector.to_payload.should eq ""
    end
  end
end
