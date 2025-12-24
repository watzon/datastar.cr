require "blueprint/html"
require "../renderable"

# Extends Blueprint::HTML to implement Datastar::Renderable.
#
# This allows Blueprint components to be used directly with
# `ServerSentEventGenerator#patch_elements`.
#
# ```
# require "datastar"
# require "datastar/adapters/blueprint"
#
# class MyComponent
#   include Blueprint::HTML
#
#   def initialize(@name : String)
#   end
#
#   def blueprint
#     div id: "greeting" do
#       h1 { "Hello, #{@name}!" }
#     end
#   end
# end
#
# sse.patch_elements(MyComponent.new("World"))
# ```
module Blueprint::HTML
  include Datastar::Renderable

  def to_datastar_html : String
    to_s
  end
end
