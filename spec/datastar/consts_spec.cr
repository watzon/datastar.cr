require "../spec_helper"

describe Datastar do
  describe "DATASTAR_VERSION" do
    it "matches expected protocol version" do
      Datastar::DATASTAR_VERSION.should eq "1.0.0-beta.1"
    end
  end

  describe "EventType" do
    it "has correct event type strings" do
      Datastar::EventType::PatchElements.should eq "datastar-patch-elements"
      Datastar::EventType::PatchSignals.should eq "datastar-patch-signals"
      Datastar::EventType::ExecuteScript.should eq "datastar-execute-script"
    end
  end

  describe "FragmentMergeMode" do
    it "has all merge modes" do
      Datastar::FragmentMergeMode::Morph.to_s.downcase.should eq "morph"
      Datastar::FragmentMergeMode::Append.to_s.downcase.should eq "append"
      Datastar::FragmentMergeMode::Prepend.to_s.downcase.should eq "prepend"
    end
  end
end
