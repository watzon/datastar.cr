require "../spec_helper"

describe Datastar::Configuration do
  describe "#initialize" do
    it "has sensible defaults" do
      config = Datastar::Configuration.new
      config.heartbeat.should eq 3.seconds
      config.on_error.should be_nil
    end
  end

  describe "#heartbeat" do
    it "can be set to a time span" do
      config = Datastar::Configuration.new
      config.heartbeat = 5.seconds
      config.heartbeat.should eq 5.seconds
    end

    it "can be disabled with false" do
      config = Datastar::Configuration.new
      config.heartbeat = false
      config.heartbeat.should eq false
    end
  end
end

describe Datastar do
  describe ".configure" do
    it "yields the global configuration" do
      Datastar.configure do |config|
        config.should be_a Datastar::Configuration
      end
    end
  end

  describe ".config" do
    it "returns the global configuration" do
      Datastar.config.should be_a Datastar::Configuration
    end
  end
end
