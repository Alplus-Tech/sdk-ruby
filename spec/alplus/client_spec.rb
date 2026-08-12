# frozen_string_literal: true

require "spec_helper"

RSpec.describe Alplus::Client do
  describe "async delivery (non-test-mode)" do
    let(:config) do
      Alplus::Configuration.new.tap do |c|
        c.key = "alp_p_test_key"
        c.endpoint = "https://ingest.example.test"
      end
    end
    let(:client) { described_class.new(config) }

    it "sends the captured exception off the calling thread and flush waits for it" do
      stub = stub_request(:post, "https://ingest.example.test/e/errors").to_return(status: 202)

      id = client.capture_exception(RuntimeError.new("boom"))

      expect(id).to start_with("err_")
      expect(client.flush(timeout: 2)).to be true
      expect(stub).to have_been_requested.times(1)
    end

    it "swallows a transport failure without raising into the caller" do
      stub_request(:post, "https://ingest.example.test/e/errors").to_return(status: 500)

      expect { client.capture_exception(RuntimeError.new("boom")) }.not_to raise_error
      expect(client.flush(timeout: 2)).to be true
    end

    it "never raises or hangs the caller when captures outrun delivery" do
      # Deterministic drop behavior (queue-full → false, warning logged) is
      # covered at the `Worker` unit level in worker_spec.rb, where the
      # background thread is stubbed out so the queue state can't race the
      # assertion. Here we only assert the client-level contract: bursts of
      # captures never raise or block the calling thread.
      stub_request(:post, "https://ingest.example.test/e/errors").to_return(status: 202, body: "")

      expect do
        20.times { client.capture_exception(RuntimeError.new("boom")) }
      end.not_to raise_error

      # Drain before the example ends so the background thread never bleeds
      # a stray request into a later example's WebMock request history.
      client.flush(timeout: 2)
    end
  end

  describe "test mode" do
    let(:config) do
      Alplus::Configuration.new.tap do |c|
        c.key = "alp_p_test_key"
        c.test_mode = true
      end
    end
    let(:client) { described_class.new(config) }

    it "never touches the network" do
      client.capture_exception(RuntimeError.new("boom"))
      expect(a_request(:post, %r{/e/errors})).not_to have_been_made
    end

    it "records the envelope synchronously in the in-memory test transport" do
      client.capture_exception(RuntimeError.new("boom"))
      expect(client.transport.envelopes.length).to eq(1)
      expect(client.transport.envelopes.first[:items].first[:exception][:type]).to eq("RuntimeError")
    end
  end

  describe "the enabled flag" do
    let(:config) do
      Alplus::Configuration.new.tap do |c|
        c.key = "alp_p_test_key"
        c.test_mode = true
        c.enabled = false
      end
    end
    let(:client) { described_class.new(config) }

    it "returns an id but captures nothing when disabled" do
      id = client.capture_exception(RuntimeError.new("boom"))
      expect(id).to start_with("err_")
      expect(client.transport.envelopes).to be_empty
    end
  end

  describe "a missing ingest key" do
    let(:config) { Alplus::Configuration.new.tap { |c| c.key = nil; c.test_mode = true } }
    let(:client) { described_class.new(config) }

    it "returns an id but captures nothing" do
      id = client.capture_exception(RuntimeError.new("boom"))
      expect(id).to start_with("err_")
      expect(client.transport.envelopes).to be_empty
    end
  end
end
