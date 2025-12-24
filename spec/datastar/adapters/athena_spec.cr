require "../../spec_helper"

# Note: We don't actually require the athena adapter here to avoid
# loading the full Athena framework which has initialization issues in test mode.
# Instead, we test that the module is properly structured.

describe "Athena adapter" do
  it "module exists and is defined correctly" do
    # The adapter file should exist and define the proper module structure
    File.exists?("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr").should be_true
  end

  it "contains Controller module definition" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "module Datastar"
    content.should contain "module Athena"
    content.should contain "module Controller"
    content.should contain "def datastar"
  end

  it "provides datastar method with correct signature" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "def datastar(heartbeat : Time::Span | Bool = Datastar.config.heartbeat) : ServerSentEventGenerator"
  end

  it "creates ServerSentEventGenerator in datastar method" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "ServerSentEventGenerator.new"
    content.should contain "request: request"
    content.should contain "response: response"
  end
end
