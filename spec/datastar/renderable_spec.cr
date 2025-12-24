require "../spec_helper"

class TestComponent
  include Datastar::Renderable

  def initialize(@name : String)
  end

  def to_datastar_html : String
    %(<div id="test">Hello, #{@name}!</div>)
  end
end

describe Datastar::Renderable do
  describe "#to_datastar_html" do
    it "returns HTML string from implementing class" do
      component = TestComponent.new("World")
      component.to_datastar_html.should eq %(<div id="test">Hello, World!</div>)
    end
  end
end
