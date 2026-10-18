# frozen_string_literal: true

RSpec.describe PostDeploy::Testing do
  before { PostDeploy.configure { |c| c.test_mode = true } }

  it "exposes captured items without going through test_transport" do
    PostDeploy.capture_exception(RuntimeError.new("boom"))
    PostDeploy.flush

    item = described_class.events.first
    expect(item[:exception][:value]).to eq("boom")
  end

  it "returns an empty list when nothing was captured" do
    expect(described_class.events).to eq([])
  end

  it "reset! clears recorded envelopes" do
    PostDeploy.capture_message("keep")
    PostDeploy.flush
    described_class.reset!
    PostDeploy.configure { |c| c.test_mode = true }
    expect(described_class.events).to eq([])
  end
end
