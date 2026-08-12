# frozen_string_literal: true

module Alplus
  # Maps a Ruby backtrace to the wire `frames[]` shape
  # (`{file, function, lineno, in_app}`) with in-app vs library detection.
  #
  # Prefers `Exception#backtrace_locations` (structured, available since
  # Ruby 2.0) over parsing `#backtrace` strings; falls back to string
  # parsing only for backtraces that don't expose locations (e.g. a
  # synthetic backtrace assigned by hand).
  module Stack
    # Path fragments that mark a frame as library code regardless of
    # `app_dirs`: installed gems, the Ruby stdlib, and common version
    # manager layouts. Checked before `app_dirs`, so a gem vendored inside
    # the app directory is still treated as library code.
    LIBRARY_MARKERS = [
      "/gems/",
      "/lib/ruby/",
      "/vendor/bundle/",
      "/.rbenv/",
      "/.rvm/",
      "/.asdf/",
      "<internal:"
    ].freeze

    LINE_PATTERN = /\A(.+):(\d+):in [`'"](.+)['"]\z/.freeze

    module_function

    def frames_for(exception, app_dirs: [])
      locations = exception.respond_to?(:backtrace_locations) ? exception.backtrace_locations : nil
      if locations
        locations.map { |loc| build_frame(loc.path, loc.lineno, loc.label, app_dirs) }
      else
        Array(exception.backtrace).filter_map { |line| frame_from_line(line, app_dirs) }
      end
    end

    def build_frame(path, lineno, label, app_dirs)
      { file: path, lineno: lineno, function: label, in_app: in_app?(path, app_dirs) }.compact
    end

    def frame_from_line(line, app_dirs)
      match = LINE_PATTERN.match(line)
      return nil unless match

      build_frame(match[1], match[2].to_i, match[3], app_dirs)
    end

    def in_app?(path, app_dirs)
      return false if path.nil?
      return false if LIBRARY_MARKERS.any? { |marker| path.include?(marker) }
      return true if app_dirs.empty?

      app_dirs.any? { |dir| path.start_with?(dir.to_s) }
    end
  end
end
