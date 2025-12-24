require "../../spec_helper"
require "../../../src/datastar/adapters/blueprint"

class TestBlueprint
  include Blueprint::HTML

  def initialize(@message : String)
  end

  def blueprint
    div id: "blueprint-test" do
      span { @message }
    end
  end
end

describe "Blueprint adapter" do
  it "makes Blueprint::HTML implement Renderable" do
    component = TestBlueprint.new("Hello from Blueprint")
    component.is_a?(Datastar::Renderable).should be_true
  end

  it "renders to datastar HTML" do
    component = TestBlueprint.new("Hello")
    html = component.to_datastar_html
    html.should contain "blueprint-test"
    html.should contain "Hello"
  end

  it "works with patch_elements" do
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    request = HTTP::Request.new("GET", "/")

    sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

    sse.stream do |stream|
      stream.patch_elements(TestBlueprint.new("Blueprint Works"))
    end

    response.close
    output = io.to_s
    output.should contain "Blueprint Works"
  end
end
