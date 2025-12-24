require "blueprint/html"
require "../renderable"

# Monkey-patch Blueprint's AttributesRenderer to preserve double underscores.
#
# Blueprint converts underscores to hyphens in attribute names (e.g., `data_foo` → `data-foo`).
# However, Datastar uses double underscores for modifiers (e.g., `data-on:click__prevent`).
# This patch ensures `__` is preserved while single `_` still becomes `-`.
# See: https://github.com/stephannv/blueprint/issues/118
module Blueprint::HTML::AttributesRenderer
  private def parse_name(name) : String
    # First, protect double underscores with a placeholder
    result = name.to_s.gsub("__", "\x00\x01\x00")
    # Convert single underscores to hyphens
    result = result.gsub("_", "-")
    # Restore double underscores
    result.gsub("\x00\x01\x00", "__")
  end
end

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
