# frozen_string_literal: true

require "spec_helper"
require "json"
require "digest"

# Top-level (unnamespaced) so `.class.name` renders the bare
# "ContractTestError" the golden fixture expects -- matching the Elixir
# SDK's own top-level `ContractTestError` (see
# sdks/elixir/test/alplus_sdk/contract_test.exs).
class ContractTestError < StandardError; end

RSpec.describe "golden envelope contract (issue #18)" do
  # Canonical input documented in sdks/contract/README.md. Frames are
  # already-built wire hashes, not a real exception's backtrace: this SDK's
  # public `exception_item` always derives frames from
  # `Exception#backtrace`(_locations), which is tied to THIS file's own
  # path/line -- never reproducible across three languages. `cap_frames`
  # and `base_item` are pure, public `module_function`s independent of
  # where the frames came from, so calling them directly with the literal
  # canonical frames exercises the same capping/shape code `exception_item`
  # itself uses, without requiring an unreproducible real stack trace.
  # The golden contract is owned by the AL+ product (Alplus-Tech/alplus) and
  # consumed as an explicit, immutable input (issue #26): ALPLUS_CONTRACT_DIR
  # points at a checkout of `sdks/contract` at the pinned contract tag. There is
  # no monorepo-relative fallback -- an absent variable fails loudly.
  contract_version = "1.0.0"

  let(:contract_dir) do
    dir = ENV["ALPLUS_CONTRACT_DIR"]
    if dir.nil? || dir.empty?
      raise "ALPLUS_CONTRACT_DIR is not set. Point it at a checkout of sdks/contract " \
            "at the contract-v#{contract_version} tag (owned by Alplus-Tech/alplus), then rerun."
    end

    manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
    unless manifest["version"] == contract_version
      raise "contract version mismatch: pinned #{contract_version}, got #{manifest["version"]}"
    end

    manifest["items"].each do |name, expected|
      actual = "sha256:#{Digest::SHA256.hexdigest(File.read(File.join(dir, name)))}"
      unless actual == expected
        raise "contract checksum mismatch for #{name}: expected #{expected}, got #{actual}"
      end
    end

    dir
  end
  let(:non_deterministic_keys) { %i[id timestamp started_at duration_ms] }

  let(:config) do
    Alplus::Configuration.new.tap do |c|
      c.key = "alp_p_contract_test"
      c.environment = "test"
      c.release = "1.0.0"
    end
  end

  let(:canonical_frames) do
    [
      { file: "app/worker.ex", function: "MyApp.Worker.perform/1", lineno: 42, colno: 5, in_app: true },
      { file: "lib/some_lib.ex", function: "SomeLib.call/2", lineno: 10, in_app: false }
    ]
  end

  let(:canonical_breadcrumbs) do
    [
      { category: "nav", message: "clicked checkout", level: "info", ts: "2024-01-01T00:00:00.000Z" },
      { category: "http", message: "POST /api/orders", level: "info", ts: "2024-01-01T00:00:01.000Z" }
    ]
  end

  def golden(contract_dir, name)
    JSON.parse(File.read(File.join(contract_dir, name)))
  end

  def normalize(item, non_deterministic_keys)
    json = JSON.parse(JSON.generate(item))
    json.reject { |key, _| non_deterministic_keys.map(&:to_s).include?(key) }
  end

  it "matches the golden exception item" do
    exception = ContractTestError.new("canonical contract test exception")

    item = Alplus::Envelope.exception_item(
      id: "err_ignored",
      exception: exception,
      config: config,
      level: "error",
      contexts: { extra: { cart_id: "cart_123", items: 3 } },
      tags: { team: "observability", flow: "checkout" },
      breadcrumbs: canonical_breadcrumbs,
      user: { id: "user_42", email: "person@example.com" },
      fingerprint: %w[checkout timeout],
      frames: canonical_frames
    )

    expect(normalize(item, non_deterministic_keys)).to eq(normalize(golden(contract_dir, "exception_item.json"), non_deterministic_keys))
  end

  it "matches the golden message item" do
    item = Alplus::Envelope.message_item(
      id: "err_ignored",
      message: "canonical contract test message",
      config: config,
      level: "warning",
      contexts: { extra: { note: "message-level context" } },
      tags: { team: "observability" },
      breadcrumbs: [{ category: "nav", message: "opened settings", level: "info", ts: "2024-01-01T00:00:00.000Z" }],
      user: { id: "user_42", email: "person@example.com" }
    )

    expect(normalize(item, non_deterministic_keys)).to eq(normalize(golden(contract_dir, "message_item.json"), non_deterministic_keys))
  end

  it "matches the golden session item" do
    session = Alplus::Session.new
    session.mark_crashed

    item = Alplus::Envelope.session_item(session: session, config: config)

    expect(normalize(item, non_deterministic_keys)).to eq(normalize(golden(contract_dir, "session_item.json"), non_deterministic_keys))
  end
end
