# frozen_string_literal: true

module Alplus
  # Orchestrates one configuration's capture pipeline: builds the wire item,
  # wraps it in an envelope, and hands it to the background worker (or, in
  # test mode, sends it synchronously through the in-memory transport).
  #
  # Every public method is fail-safe: a bug anywhere in envelope building or
  # dispatch is caught and logged, never raised into the host app (issue
  # #14 story 8). The event id is always generated and returned first, so a
  # caller can show "reference id err_..." even if the event was dropped.
  class Client
    def initialize(config)
      @config = config
      @transport = config.transport || (config.test_mode ? TestTransport.new : Transport.new(config))
      @worker = Worker.new(config, @transport)
    end

    attr_reader :transport

    def capture_exception(exception, level: "error", context: nil, tags: nil, breadcrumbs: nil, mechanism: "generic")
      id = Id.generate_event_id
      dispatch(id) { Envelope.exception_item(id: id, exception: exception, config: @config, level: level, context: context, tags: tags, breadcrumbs: breadcrumbs, mechanism: mechanism) }
      id
    end

    def capture_message(message, level: "info", context: nil, tags: nil, breadcrumbs: nil, mechanism: "generic")
      id = Id.generate_event_id
      dispatch(id) { Envelope.message_item(id: id, message: message, config: @config, level: level, context: context, tags: tags, breadcrumbs: breadcrumbs, mechanism: mechanism) }
      id
    end

    def flush(timeout: 2)
      @worker.flush(timeout: timeout)
    rescue StandardError
      false
    end

    private

    # `id` is unused directly but kept as a named parameter for readability
    # at call sites and future correlation logging.
    def dispatch(_id)
      return unless @config.valid?
      return unless @config.sampled?

      item = yield
      envelope = Envelope.wrap(config: @config, item: item)

      if @config.test_mode
        @transport.send_envelope(envelope)
      else
        @worker.enqueue(envelope)
      end
    rescue StandardError => e
      @config.logger&.warn("[alplus] capture failed internally; event dropped: #{e.class}: #{e.message}")
    end
  end
end
