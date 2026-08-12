# frozen_string_literal: true

require "spec_helper"
require "logger"

RSpec.describe Alplus::Worker do
  let(:logger) { instance_spy(Logger) }
  let(:config) do
    Alplus::Configuration.new.tap do |c|
      c.key = "alp_p_test_key"
      c.max_queue_size = 2
      c.logger = logger
    end
  end
  let(:transport) { instance_double(Alplus::Transport, send_envelope: :sent) }
  let(:worker) { described_class.new(config, transport) }

  # The background thread is never started in these examples (stubbed
  # below), so pushed items sit in the queue deterministically instead of
  # racing a real drain thread — the only way to assert "queue full" /
  # "dropped" without a timing-dependent test.
  before { allow(worker).to receive(:ensure_thread_started) }

  describe "#enqueue" do
    it "accepts items up to max_queue_size" do
      expect(worker.enqueue({ id: "1" })).to be true
      expect(worker.enqueue({ id: "2" })).to be true
      expect(worker.queue_size).to eq(2)
    end

    it "returns false and drops the item once the queue is full" do
      worker.enqueue({ id: "1" })
      worker.enqueue({ id: "2" })

      dropped = worker.enqueue({ id: "overflow" })

      expect(dropped).to be false
      expect(worker.queue_size).to eq(2)
    end

    it "logs a warning when it drops an event" do
      worker.enqueue({ id: "1" })
      worker.enqueue({ id: "2" })
      worker.enqueue({ id: "overflow" })

      expect(logger).to have_received(:warn).with(/queue full/)
    end

    it "never raises, even when dropping" do
      worker.enqueue({ id: "1" })
      worker.enqueue({ id: "2" })

      expect { worker.enqueue({ id: "overflow" }) }.not_to raise_error
    end
  end

  describe "#flush" do
    it "waits for a real in-flight send to finish before reporting idle (TOCTOU fix)" do
      gate = Queue.new
      allow(transport).to receive(:send_envelope) do |_envelope|
        gate.pop # blocks until the test explicitly releases it
        :sent
      end

      real_worker = described_class.new(config, transport)
      real_worker.enqueue({ id: "1" }) # starts the real background thread this time

      # The item is popped off the queue almost immediately, making
      # `queue.empty?` true while `send_envelope` is still blocked on the
      # gate — exactly the window the old `@in_flight`-set-after-pop
      # implementation could race. `flush` must still block here.
      flushed_early = nil
      flush_thread = Thread.new { flushed_early = real_worker.flush(timeout: 0.3) }

      sleep 0.05 # let the worker thread pop the item and call send_envelope
      flush_thread.join

      expect(flushed_early).to be false # timed out: still in flight

      gate.push(:go)
      expect(real_worker.flush(timeout: 2)).to be true
    end
  end
end
