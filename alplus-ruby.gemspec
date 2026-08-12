# frozen_string_literal: true

require_relative "lib/alplus/version"

Gem::Specification.new do |spec|
  spec.name = "alplus-ruby"
  spec.version = Alplus::VERSION
  spec.authors = ["AL+"]
  spec.email = ["support@alplus.dev"]

  spec.summary = "Error reporting for AL+ Observe (Ruby + Rails)"
  spec.description = "Captures exceptions and messages and reports them to AL+ Observe's POST /e/errors " \
                      "ingest endpoint, with an optional Rails railtie for automatic unhandled-exception capture."
  spec.homepage = "https://alplus.dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/abpaul/alplus"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb"] + %w[README.md LICENSE]
  end.select { |f| File.exist?(f) }
  spec.require_paths = ["lib"]

  # Zero runtime dependencies by design (Net::HTTP + stdlib only), matching
  # the JS SDK's own "ships to third-party production apps" constraint.

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "webmock", "~> 3.24"
  spec.add_development_dependency "rack", "~> 3.0"
  spec.add_development_dependency "rack-test", "~> 2.1"
  # Dev-only, to exercise the railtie against a real middleware stack
  # (spec/alplus/railtie_spec.rb) — never a runtime dependency.
  spec.add_development_dependency "railties", "~> 7.1"
  spec.add_development_dependency "actionpack", "~> 7.1"
end
