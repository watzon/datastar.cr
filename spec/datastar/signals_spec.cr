require "../spec_helper"
require "json"
require "http"

struct TestSignals
  include JSON::Serializable
  getter name : String
  getter count : Int32
end

describe Datastar::Signals do
  describe ".parse" do
    it "parses JSON string to JSON::Any" do
      signals = Datastar::Signals.parse(%q({"name": "test", "count": 42}))
      signals["name"].as_s.should eq "test"
      signals["count"].as_i.should eq 42
    end

    it "returns empty object for empty string" do
      signals = Datastar::Signals.parse("")
      signals.as_h.should be_empty
    end

    it "returns empty object for nil" do
      signals = Datastar::Signals.parse(nil)
      signals.as_h.should be_empty
    end
  end

  describe ".parse with type" do
    it "deserializes to typed struct" do
      signals = Datastar::Signals.parse(%q({"name": "test", "count": 42}), TestSignals)
      signals.name.should eq "test"
      signals.count.should eq 42
    end
  end

  describe ".from_request" do
    it "extracts signals from query params for GET requests" do
      # URL-encoded JSON: {"key": "value"}
      request = HTTP::Request.new("GET", "/?datastar=%7B%22key%22%3A%22value%22%7D")
      signals = Datastar::Signals.from_request(request)
      signals["key"].as_s.should eq "value"
    end

    it "extracts signals from body for POST requests" do
      body = IO::Memory.new(%q({"key": "value"}))
      request = HTTP::Request.new("POST", "/", body: body)
      signals = Datastar::Signals.from_request(request)
      signals["key"].as_s.should eq "value"
    end

    it "returns empty object when no signals present" do
      request = HTTP::Request.new("GET", "/")
      signals = Datastar::Signals.from_request(request)
      signals.as_h.should be_empty
    end
  end
end
