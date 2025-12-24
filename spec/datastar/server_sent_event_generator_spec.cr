require "../spec_helper"
require "http/server"

describe Datastar::ServerSentEventGenerator do
  describe "#initialize" do
    it "creates a generator with request and response" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response)
      sse.should be_a Datastar::ServerSentEventGenerator
    end

    it "accepts custom heartbeat" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: 5.seconds)
      sse.heartbeat.should eq 5.seconds
    end

    it "allows disabling heartbeat" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)
      sse.heartbeat.should eq false
    end
  end

  describe "#signals" do
    it "returns signals from request header" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      headers = HTTP::Headers{"Datastar-Signal" => %q({"test": "value"})}
      request = HTTP::Request.new("GET", "/", headers)

      sse = Datastar::ServerSentEventGenerator.new(request, response)
      sse.signals["test"].as_s.should eq "value"
    end
  end

  describe "#stream" do
    it "executes block and sets SSE headers" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        # Just verify the stream block is called
        stream.should be_a Datastar::ServerSentEventGenerator
      end

      response.close
      response.headers["Content-Type"].should eq "text/event-stream"
      response.headers["Cache-Control"].should eq "no-cache"
    end

    it "allows spawning multiple concurrent streams" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)
      counter = Atomic(Int32).new(0)

      sse.stream do |stream|
        spawn do
          counter.add(1)
        end
        spawn do
          counter.add(1)
        end
      end

      response.close
      counter.get.should eq 2
    end
  end

  describe "#patch_elements" do
    it "sends a fragment with default options" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.patch_elements(%(<div id="test">Hello</div>))
      end

      response.close
      output = io.to_s
      output.should contain "event: datastar-patch-elements"
      output.should contain "data: fragments <div id=\"test\">Hello</div>"
    end

    it "sends with custom selector" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.patch_elements("<span>Hi</span>", selector: "#target")
      end

      response.close
      output = io.to_s
      output.should contain "data: selector #target"
    end

    it "sends with merge mode" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.patch_elements("<li>Item</li>", mode: Datastar::FragmentMergeMode::Append)
      end

      response.close
      output = io.to_s
      output.should contain "data: mergeMode append"
    end

    it "accepts Renderable objects" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      component = TestComponent.new("World")

      sse.stream do |stream|
        stream.patch_elements(component)
      end

      response.close
      output = io.to_s
      output.should contain "Hello, World!"
    end

    it "accepts array of elements" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.patch_elements(["<div>One</div>", "<div>Two</div>"])
      end

      response.close
      output = io.to_s
      output.should contain "One"
      output.should contain "Two"
    end
  end

  describe "#remove_elements" do
    it "sends a remove event" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.remove_elements("#old-element")
      end

      response.close
      output = io.to_s
      output.should contain "event: datastar-patch-elements"
      output.should contain "data: selector #old-element"
      output.should contain "data: fragments"
    end

    it "supports use_view_transition option" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.remove_elements("#old-element", use_view_transition: true)
      end

      response.close
      output = io.to_s
      output.should contain "data: useViewTransition true"
    end
  end

  describe "#patch_signals" do
    it "sends signals as JSON" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.patch_signals(count: 42, name: "test")
      end

      response.close
      output = io.to_s
      output.should contain "event: datastar-patch-signals"
      output.should contain "data: signals"
      output.should contain "count"
      output.should contain "42"
    end

    it "supports only_if_missing option" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.patch_signals({count: 1}, only_if_missing: true)
      end

      response.close
      output = io.to_s
      output.should contain "data: onlyIfMissing true"
    end
  end

  describe "#remove_signals" do
    it "sends remove signals event" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.remove_signals(["user.name", "user.email"])
      end

      response.close
      output = io.to_s
      output.should contain "event: datastar-patch-signals"
      output.should contain "data: signals"
    end
  end

  describe "#execute_script" do
    it "sends a script execution event" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.execute_script(%(console.log("Hello")))
      end

      response.close
      output = io.to_s
      output.should contain "event: datastar-execute-script"
      output.should contain %(console.log("Hello"))
    end

    it "includes auto_remove by default" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.execute_script("alert('hi')")
      end

      response.close
      output = io.to_s
      output.should contain "data: autoRemove true"
    end

    it "supports custom attributes" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.execute_script("test()", attributes: {"type" => "module"})
      end

      response.close
      output = io.to_s
      output.should contain "data: attributes type module"
    end
  end

  describe "#redirect" do
    it "sends a redirect script" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.redirect("/dashboard")
      end

      response.close
      output = io.to_s
      output.should contain "event: datastar-execute-script"
      output.should contain "/dashboard"
      output.should contain "location"
    end
  end

  describe "#check_connection!" do
    it "sends a heartbeat comment when connection is open" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.stream do |stream|
        stream.check_connection!
      end

      response.close
      output = io.to_s
      output.should contain ": heartbeat"
    end

    it "raises IO::Error if connection is already closed" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      # Close the response first
      response.close

      expect_raises(IO::Error) do
        sse.check_connection!
      end
    end
  end

  describe "one-off mode" do
    it "allows sending events without stream block" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.patch_elements(%(<div id="test">Direct</div>))
      sse.finish

      response.close
      output = io.to_s
      output.should contain "datastar-patch-elements"
      output.should contain "Direct"
    end

    it "allows multiple one-off events before finish" do
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      request = HTTP::Request.new("GET", "/")

      sse = Datastar::ServerSentEventGenerator.new(request, response, heartbeat: false)

      sse.patch_elements(%(<div id="one">First</div>))
      sse.patch_signals(count: 42)
      sse.execute_script("console.log('test')")
      sse.finish

      response.close
      output = io.to_s
      output.should contain "First"
      output.should contain "count"
      output.should contain "console.log"
    end
  end
end
