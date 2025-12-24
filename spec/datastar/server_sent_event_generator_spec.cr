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
end
