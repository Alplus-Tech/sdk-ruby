# frozen_string_literal: true

# `rubygems/release-gem` (the release workflow) runs `bundle exec rake release`.
# That task comes from bundler's gem tasks: build, guard_clean, tag, push.
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec
