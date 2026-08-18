# frozen_string_literal: true

module Alplus
  # In-memory recorder for host tests. Start with `config.test_mode = true`.
  #
  #   Alplus.configure { |c| c.test_mode = true }
  #   Alplus.capture_exception(error)
  #   Alplus.flush
  #   item = Alplus::Testing.events.first
  module Testing
    def self.events
      Array(transport&.envelopes).flat_map { |envelope| envelope[:items] || [] }
    end

    def self.sessions
      Array(transport&.session_envelopes).flat_map { |envelope| envelope[:items] || [] }
    end

    def self.reset!
      Alplus.reset!
    end

    def self.transport
      Alplus.initialized_client&.transport
    end
    private_class_method :transport
  end
end
