# frozen_string_literal: true

RSpec.describe Alplus::Testing do
  before { Alplus.configure { |c| c.test_mode = true } }

  it "exposes captured items without going through test_transport" do
    Alplus.capture_exception(RuntimeError.new("boom"))
    Alplus.flush

    item = described_class.events.first
    expect(item[:exception][:value]).to eq("boom")
  end

  it "returns an empty list when nothing was captured" do
    expect(described_class.events).to eq([])
    expect(described_class.sessions).to eq([])
  end

  it "records a closed session item" do
    Alplus::Session.with_clean_session do
      Alplus.close_session
    end
    Alplus.flush
    expect(described_class.sessions.first[:id]).to start_with("ses_")
  end

  it "reset! clears recorded envelopes" do
    Alplus.capture_message("keep")
    Alplus.flush
    described_class.reset!
    Alplus.configure { |c| c.test_mode = true }
    expect(described_class.events).to eq([])
  end
end
