require "blueprint/html"

# A counter display component that shows a count value.
# This component can be patched into the DOM via Datastar SSE.
class Counter
  include Blueprint::HTML

  def initialize(@count : Int32); end

  private def blueprint
    div id: "counter", class: "counter" do
      plain @count.to_s
    end
  end
end

# A status message component that displays informational text.
class StatusMessage
  include Blueprint::HTML

  def initialize(@message : String); end

  private def blueprint
    div id: "status", class: "status" do
      plain @message
    end
  end
end

# A clock component showing the current time.
class Clock
  include Blueprint::HTML

  def initialize(@time : Time); end

  private def blueprint
    div id: "clock", class: "time" do
      plain "Server time: #{@time.to_s("%H:%M:%S")}"
    end
  end
end

# A greeting component that displays a personalized message.
class Greeting
  include Blueprint::HTML

  def initialize(@name : String); end

  private def blueprint
    div id: "greeting", class: "card" do
      h2 { "Hello, #{@name}!" }
      p { "Welcome to the Datastar demo." }
    end
  end
end
