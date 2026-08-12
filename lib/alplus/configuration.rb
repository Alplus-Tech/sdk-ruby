# frozen_string_literal: true

module Alplus
  # Holds ingest key, endpoint, environment/release tags, and safety knobs.
  # The key is read from `ALPLUS_KEY` by default and is never logged —
  # `#inspect`/`#to_s` omit it deliberately (issue #14 story 11).
  class Configuration
    DEFAULT_ENDPOINT = "https://ingest.alplus.dev"

    attr_accessor :key, :endpoint, :environment, :release, :sample_rate,
                  :enabled, :test_mode, :app_dirs, :max_queue_size,
                  :open_timeout, :read_timeout, :logger, :transport

    def initialize
      @key = ENV["ALPLUS_KEY"]
      @endpoint = ENV["ALPLUS_ENDPOINT"] || DEFAULT_ENDPOINT
      @environment = ENV["ALPLUS_ENVIRONMENT"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "production"
      @release = ENV["ALPLUS_RELEASE"]
      @sample_rate = 1.0
      @enabled = true
      @test_mode = false
      @app_dirs = []
      @max_queue_size = 100
      @open_timeout = 2
      @read_timeout = 5
      @logger = nil
      @transport = nil
    end

    def valid?
      !enabled.nil? && enabled && !key.to_s.strip.empty?
    end

    def sampled?
      sample_rate >= 1.0 || rand < sample_rate
    end

    # Never expose the key. A future maintainer adding a field here must not
    # add it to this list without checking it isn't a secret.
    def inspect
      "#<Alplus::Configuration endpoint=#{endpoint.inspect} environment=#{environment.inspect} " \
        "release=#{release.inspect} enabled=#{enabled.inspect} test_mode=#{test_mode.inspect}>"
    end
    alias to_s inspect
  end
end
