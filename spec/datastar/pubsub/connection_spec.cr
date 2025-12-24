require "../../spec_helper"

describe Datastar::PubSub::Connection do
  it "stores id and output channel" do
    channel = Channel(String).new(10)
    conn = Datastar::PubSub::Connection.new("conn-123", channel)

    conn.id.should eq "conn-123"
    conn.output_channel.should eq channel
  end

  it "generates unique id when not provided" do
    channel = Channel(String).new(10)
    conn1 = Datastar::PubSub::Connection.new(channel)
    conn2 = Datastar::PubSub::Connection.new(channel)

    conn1.id.should_not eq conn2.id
    conn1.id.should_not be_empty
  end

  it "can send messages through output channel" do
    channel = Channel(String).new(10)
    conn = Datastar::PubSub::Connection.new("test", channel)

    conn.send("hello")
    channel.receive.should eq "hello"
  end
end
