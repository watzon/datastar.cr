require "./spec_helper"

describe Datastar do
  it "has a version" do
    Datastar::VERSION.should_not be_nil
  end

  it "has datastar protocol version" do
    Datastar::DATASTAR_VERSION.should_not be_nil
  end
end
