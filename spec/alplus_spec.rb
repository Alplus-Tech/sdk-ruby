# frozen_string_literal: true

require "spec_helper"

RSpec.describe Alplus do
  before { described_class.configure { |c| c.test_mode = true } }

  describe ".configure" do
    it "yields the shared configuration and rebuilds the client on the next access" do
      described_class.configure { |c| c.release = "v2.0.0" }
      expect(described_class.configuration.release).to eq("v2.0.0")
    end
  end

  describe ".capture_exception" do
    it "returns an err_-prefixed id and records the envelope" do
      id = described_class.capture_exception(RuntimeError.new("boom"))
      expect(id).to start_with("err_")
      expect(described_class.test_transport.envelopes.length).to eq(1)
    end

    it "never raises even if the exception argument is not an Exception" do
      expect { described_class.capture_exception("not an exception") }.not_to raise_error
    end
  end

  describe ".capture_message" do
    it "returns an err_-prefixed id and records a message-type item" do
      id = described_class.capture_message("something happened", level: "warning")
      expect(id).to start_with("err_")
      expect(described_class.test_transport.envelopes.first[:items].first[:level]).to eq("warning")
    end
  end

  describe "the ingest key" do
    it "never appears in Configuration#inspect or #to_s" do
      described_class.configure { |c| c.key = "alp_p_super_secret_value" }
      expect(described_class.configuration.inspect).not_to include("alp_p_super_secret_value")
      expect(described_class.configuration.to_s).not_to include("alp_p_super_secret_value")
    end
  end

  describe ".flush" do
    it "returns true and never raises when nothing is queued" do
      expect(described_class.flush(timeout: 1)).to be true
    end
  end
end
