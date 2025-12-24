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
end
