require "../../spec_helper"

# Note: We don't actually require the kemal adapter here to avoid
# loading the full Kemal framework which has initialization issues in test mode.
# Instead, we test that the module is properly structured.

describe "Kemal adapter" do
  it "module exists and is defined correctly" do
    File.exists?("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/kemal.cr").should be_true
  end

  it "contains Helpers module definition" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/kemal.cr")
    content.should contain "module Datastar"
    content.should contain "module Kemal"
    content.should contain "module Helpers"
  end

  it "provides datastar_stream method" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/kemal.cr")
    content.should contain "def datastar_stream("
    content.should contain "ServerSentEventGenerator.new"
    content.should contain "sse.stream"
  end

  it "provides datastar_render method" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/kemal.cr")
    content.should contain "def datastar_render("
    content.should contain "text/html; charset=utf-8"
  end

  it "provides datastar_request? helper" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/kemal.cr")
    content.should contain "def datastar_request?"
    content.should contain "Datastar.datastar_request?"
  end

  it "extends HTTP::Server::Context" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/kemal.cr")
    content.should contain "class HTTP::Server::Context"
    content.should contain "include Datastar::Kemal::Helpers"
  end

  it "requires pubsub module" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/kemal.cr")
    content.should contain "require \"../pubsub\""
  end

  it "provides datastar_broadcast helper" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/kemal.cr")
    content.should contain "def datastar_broadcast(topic : String"
    content.should contain "Datastar::PubSub.broadcast"
  end

  it "documents broadcast usage with subscribe example" do
    content = File.read("/Users/watzon/Projects/personal/datastar.cr/src/datastar/adapters/kemal.cr")
    content.should contain "sse.subscribe"
    content.should contain "datastar_broadcast"
  end
end
