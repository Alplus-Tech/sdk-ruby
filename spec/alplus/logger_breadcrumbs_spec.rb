# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"

RSpec.describe Alplus::LoggerBreadcrumbs do
  before do
    Alplus.configure { |c| c.test_mode = true }
    Thread.current[:alplus_scope] = nil
  end

  after { Thread.current[:alplus_scope] = nil }

  def attached_logger
    logger = Logger.new(StringIO.new)
    described_class.attach(logger)
    logger
  end

  it "records logger lines as log-category breadcrumbs with mapped levels" do
    logger = attached_logger
    logger.debug("cache miss for school 42")
    logger.info("importing roll")
    logger.warn("row 41 blank")
    logger.error("row 42 unusable")

    crumbs = Alplus::Scope.current.snapshot[:breadcrumbs].select { |c| c[:category] == "log" }
    expect(crumbs.map { |c| [c[:message], c[:level]] }).to eq([
      ["cache miss for school 42", "debug"],
      ["importing roll", "info"],
      ["row 41 blank", "warning"],
      ["row 42 unusable", "error"]
    ])
    expect(crumbs).to all(include(:ts))
  end

  it "excludes the SDK's own [alplus] diagnostics and non-String messages" do
    logger = attached_logger
    logger.warn("[alplus] queue full; dropping event")
    logger.info({ structured: "hash" })

    crumbs = Alplus::Scope.current.snapshot[:breadcrumbs].select { |c| c[:category] == "log" }
    expect(crumbs).to be_empty
  end

  it "records nothing when logger_breadcrumbs_enabled is false" do
    Alplus.configuration.logger_breadcrumbs_enabled = false
    logger = attached_logger
    logger.info("should not appear")

    crumbs = Alplus::Scope.current.snapshot[:breadcrumbs].select { |c| c[:category] == "log" }
    expect(crumbs).to be_empty
  end

  it "attaches idempotently: one line, one breadcrumb" do
    logger = Logger.new(StringIO.new)
    described_class.attach(logger)
    described_class.attach(logger)
    logger.info("once")

    crumbs = Alplus::Scope.current.snapshot[:breadcrumbs].select { |c| c[:message] == "once" }
    expect(crumbs.length).to eq(1)
  end

  it "logged lines arrive as before-context on a subsequent capture" do
    logger = attached_logger
    logger.info("about to charge order")
    Alplus.capture_exception(RuntimeError.new("charge failed"))

    item = Alplus.test_transport.envelopes.first[:items].first
    log_crumb = item[:breadcrumbs].find { |c| c[:message] == "about to charge order" }
    expect(log_crumb[:category]).to eq("log")
    expect(log_crumb[:data]).to be_nil
  end
end
