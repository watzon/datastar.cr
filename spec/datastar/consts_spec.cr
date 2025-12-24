require "../spec_helper"

describe Datastar do
  describe "DATASTAR_VERSION" do
    it "matches expected protocol version" do
      Datastar::DATASTAR_VERSION.should eq "1.0.0-RC.7"
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
      Datastar::FragmentMergeMode::Outer.to_s.downcase.should eq "outer"
      Datastar::FragmentMergeMode::Inner.to_s.downcase.should eq "inner"
      Datastar::FragmentMergeMode::Replace.to_s.downcase.should eq "replace"
      Datastar::FragmentMergeMode::Append.to_s.downcase.should eq "append"
      Datastar::FragmentMergeMode::Prepend.to_s.downcase.should eq "prepend"
      Datastar::FragmentMergeMode::Before.to_s.downcase.should eq "before"
      Datastar::FragmentMergeMode::After.to_s.downcase.should eq "after"
      Datastar::FragmentMergeMode::Remove.to_s.downcase.should eq "remove"
    end
  end
end
