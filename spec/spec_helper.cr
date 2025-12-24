require "spec"
require "../src/datastar"
require "../src/datastar/pubsub/connection"
require "../src/datastar/pubsub/backend"
require "../src/datastar/pubsub/memory_backend"
require "../src/datastar/pubsub/manager"

# Test helper component for Renderable tests
class TestComponent
  include Datastar::Renderable

  def initialize(@name : String)
  end

  def to_datastar_html : String
    %(<div id="test">Hello, #{@name}!</div>)
  end
end
