module Datastar
  # Protocol for objects that can be rendered as HTML fragments.
  #
  # Include this module and implement `#to_datastar_html` to make your
  # component compatible with `ServerSentEventGenerator#patch_elements`.
  #
  # ```
  # class MyComponent
  #   include Datastar::Renderable
  #
  #   def initialize(@name : String)
  #   end
  #
  #   def to_datastar_html : String
  #     %(<div>Hello, #{@name}!</div>)
  #   end
  # end
  #
  # sse.patch_elements(MyComponent.new("World"))
  # ```
  module Renderable
    abstract def to_datastar_html : String
  end
end
