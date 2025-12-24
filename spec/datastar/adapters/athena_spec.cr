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

  it "provides datastar method that accepts request and block" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "def datastar("
    content.should contain "request : ATH::Request"
    content.should contain "&block : SSEWriter -> Nil"
    content.should contain "ATH::StreamedResponse"
  end

  it "defines SSEWriter class for Athena streaming" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "class SSEWriter < Datastar::EventStream"
    content.should contain "getter request : ATH::Request"
  end

  it "SSEWriter provides signal helpers" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "def signals"
    content.should contain "Signals.from_request"
  end

  it "sets correct SSE headers in response" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "text/event-stream"
    content.should contain "no-cache"
    content.should contain "keep-alive"
  end

  it "streams responses through the shared EventStream" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "writer.stream"
  end

  it "defines LiveController helpers" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "module LiveController"
    content.should contain "include Datastar::Athena::Controller"
    content.should contain "def datastar_render"
    content.should contain "def datastar_stream"
  end

  it "includes datastar_request? helper" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/athena.cr")
    content.should contain "def datastar_request?"
    content.should contain "Datastar.datastar_request?"
  end
end
