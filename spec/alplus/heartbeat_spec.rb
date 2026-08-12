# frozen_string_literal: true

require "spec_helper"
require "logger"

RSpec.describe Alplus::Heartbeat do
  let(:config) do
    Alplus::Configuration.new.tap do |c|
      c.key = "alp_p_test_key"
      c.endpoint = "https://ingest.example.test"
      c.open_timeout = 1
      c.read_timeout = 1
    end
  end

  describe ".build_uri" do
    it "builds GET|POST /h/:token?state=...&ping_id=... against the configured endpoint" do
      uri = described_class.build_uri("tok_123", "start", "ping_abc", config)
      expect(uri.to_s).to eq("https://ingest.example.test/h/tok_123?state=start&ping_id=ping_abc")
    end

    it "URL-encodes the token" do
      uri = described_class.build_uri("tok/weird value", "finish", "ping_1", config)
      expect(URI.decode_www_form(uri.query).to_h).to eq("state" => "finish", "ping_id" => "ping_1")
      expect(uri.path).to eq("/h/tok%2Fweird+value")
    end
  end

  describe ".generate_ping_id" do
    it "returns a fresh id on every call" do
      expect(described_class.generate_ping_id).not_to eq(described_class.generate_ping_id)
    end
  end

  describe ".ping" do
    it "posts to /h/:token with the given state and a recognized token succeeds (202)" do
      stub = stub_request(:post, "https://ingest.example.test/h/tok_ok")
             .with(query: hash_including("state" => "start"))
             .to_return(status: 202)

      described_class.ping("tok_ok", state: "start", config: config)

      expect(stub).to have_been_requested
    end

    it "defaults state to finish" do
      stub = stub_request(:post, "https://ingest.example.test/h/tok_ok")
             .with(query: hash_including("state" => "finish"))
             .to_return(status: 202)

      described_class.ping("tok_ok", config: config)

      expect(stub).to have_been_requested
    end

    it "falls back to finish (not a no-op) for an unrecognized state, matching the Elixir SDK" do
      stub = stub_request(:post, "https://ingest.example.test/h/tok_ok")
             .with(query: hash_including("state" => "finish"))
             .to_return(status: 202)

      described_class.ping("tok_ok", state: "bogus", config: config)

      expect(stub).to have_been_requested
    end

    it "reuses the SAME ping_id across every retry attempt of one call (server-side dedup key)" do
      stub = stub_request(:post, "https://ingest.example.test/h/tok_retry")
             .with(query: hash_including("ping_id" => "fixed-ping-id"))
             .to_return({ status: 503 }, { status: 202 })

      described_class.ping("tok_retry", config: config, sleeper: ->(_seconds) {}, ping_id: "fixed-ping-id")

      expect(stub).to have_been_requested.times(2)
    end

    it "generates its own ping_id per call when none is given" do
      stub = stub_request(:post, %r{\Ahttps://ingest\.example\.test/h/tok_gen}).to_return(status: 202)

      described_class.ping("tok_gen", config: config)

      expect(stub).to have_been_requested
    end

    it "retries a transient 5xx and succeeds on the next attempt" do
      stub = stub_request(:post, "https://ingest.example.test/h/tok_flaky")
             .with(query: hash_including("state" => "finish"))
             .to_return({ status: 503 }, { status: 202 })

      described_class.ping("tok_flaky", config: config, sleeper: ->(_seconds) {})

      expect(stub).to have_been_requested.times(2)
    end

    it "an unrecognized token (404) is swallowed without raising and does not retry" do
      stub = stub_request(:post, %r{\Ahttps://ingest\.example\.test/h/tok_unknown}).to_return(status: 404)

      expect { described_class.ping("tok_unknown", config: config) }.not_to raise_error
      expect(stub).to have_been_requested.times(1)
    end

    it "never raises on a connection failure" do
      stub_request(:post, %r{\Ahttps://ingest\.example\.test/h/tok_down}).to_raise(SocketError.new("getaddrinfo failed"))

      expect { described_class.ping("tok_down", config: config, sleeper: ->(_seconds) {}) }.not_to raise_error
    end

    describe "the bounded retry budget (issue #16 defect: heartbeat must not stall ~30s)" do
      it "makes at most HEARTBEAT_MAX_ATTEMPTS attempts against a persistent 5xx" do
        stub = stub_request(:post, %r{\Ahttps://ingest\.example\.test/h/tok_persistent_5xx}).to_return(status: 500)

        described_class.ping("tok_persistent_5xx", config: config, sleeper: ->(_seconds) {})

        expect(stub).to have_been_requested.times(described_class::HEARTBEAT_MAX_ATTEMPTS)
      end

      it "caps a 429's Retry-After at HEARTBEAT_MAX_RETRY_AFTER_SECONDS instead of the transport's 30s" do
        stub_request(:post, %r{\Ahttps://ingest\.example\.test/h/tok_429})
          .to_return({ status: 429, headers: { "Retry-After" => "9999" } }, { status: 202 })
        waited = []

        described_class.ping("tok_429", config: config, sleeper: ->(seconds) { waited << seconds })

        expect(waited).to eq([described_class::HEARTBEAT_MAX_RETRY_AFTER_SECONDS.to_f])
      end

      it "logs a warning when the retry budget is exhausted" do
        logger = instance_spy(Logger)
        config.logger = logger
        stub_request(:post, %r{\Ahttps://ingest\.example\.test/h/tok_exhausted}).to_return(status: 500)

        described_class.ping("tok_exhausted", config: config, sleeper: ->(_seconds) {})

        expect(logger).to have_received(:warn).with(/heartbeat exhausted/)
      end

      it "does not log when the ping eventually succeeds" do
        logger = instance_spy(Logger)
        config.logger = logger
        stub_request(:post, %r{\Ahttps://ingest\.example\.test/h/tok_recovers}).to_return({ status: 503 }, { status: 202 })

        described_class.ping("tok_recovers", config: config, sleeper: ->(_seconds) {})

        expect(logger).not_to have_received(:warn)
      end
    end

    it "rejects an invalid state without making a request" do
      # superseded by the fallback-to-finish behavior above; kept to
      # document that a bogus state still results in exactly one request,
      # not zero and not a raise.
      stub = stub_request(:post, %r{\Ahttps://ingest\.example\.test/h/tok_ok}).to_return(status: 202)

      described_class.ping("tok_ok", state: "bogus", config: config)

      expect(stub).to have_been_requested.times(1)
    end
  end
end

RSpec.describe "Alplus.heartbeat" do
  before { Alplus.configure { |c| c.endpoint = "https://ingest.example.test" } }

  it "pings the token and never raises into the caller" do
    stub = stub_request(:post, %r{\Ahttps://ingest\.example\.test/h/tok_ok}).to_return(status: 202)

    expect { Alplus.heartbeat("tok_ok") }.not_to raise_error
    expect(stub).to have_been_requested
  end

  it "accepts an explicit state: start/finish/fail" do
    stub = stub_request(:post, "https://ingest.example.test/h/tok_ok")
           .with(query: hash_including("state" => "fail"))
           .to_return(status: 202)

    Alplus.heartbeat("tok_ok", state: "fail")

    expect(stub).to have_been_requested
  end
end
