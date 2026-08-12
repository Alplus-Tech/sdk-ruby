# frozen_string_literal: true

require "spec_helper"

RSpec.describe Alplus::Transport do
  let(:config) do
    Alplus::Configuration.new.tap do |c|
      c.key = "alp_p_test_key"
      c.endpoint = "https://ingest.example.test"
      c.open_timeout = 1
      c.read_timeout = 1
    end
  end
  let(:transport) { described_class.new(config) }
  let(:envelope) { { header: { key: config.key }, items: [{ id: "err_1" }] } }

  it "posts to POST /e/errors with a Bearer Authorization header and JSON content-type" do
    stub = stub_request(:post, "https://ingest.example.test/e/errors")
           .with(
             headers: { "Content-Type" => "application/json", "Authorization" => "Bearer alp_p_test_key" },
             body: JSON.generate(envelope)
           )
           .to_return(status: 202, body: "")

    expect(transport.send_envelope(envelope)).to eq(:sent)
    expect(stub).to have_been_requested
  end

  it "never raises on a 5xx response and reports :rejected (a non-network failure)" do
    stub_request(:post, "https://ingest.example.test/e/errors").to_return(status: 500)

    expect { transport.send_envelope(envelope) }.not_to raise_error
    expect(transport.send_envelope(envelope)).to eq(:rejected)
  end

  it "never raises and returns :error on a connection timeout" do
    stub_request(:post, "https://ingest.example.test/e/errors").to_timeout

    expect { transport.send_envelope(envelope) }.not_to raise_error
    expect(transport.send_envelope(envelope)).to eq(:error)
  end

  it "never raises and returns :error when the host is unreachable" do
    stub_request(:post, "https://ingest.example.test/e/errors").to_raise(SocketError.new("getaddrinfo failed"))

    expect { transport.send_envelope(envelope) }.not_to raise_error
    expect(transport.send_envelope(envelope)).to eq(:error)
  end

  it "never sends an envelope over the configured MAX_ENVELOPE_BYTES cap" do
    huge_envelope = { items: [{ id: "err_1", message: "x" * 2_000_000 }] }
    expect(transport.send_envelope(huge_envelope)).to eq(:oversized)
    expect(a_request(:post, "https://ingest.example.test/e/errors")).not_to have_been_made
  end
end
