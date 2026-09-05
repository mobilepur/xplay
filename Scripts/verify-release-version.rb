# frozen_string_literal: true

require "yaml"

unless [1, 3].include?(ARGV.length)
  abort "Usage: ruby #{$PROGRAM_NAME} PROJECT_YML [APP_VERSION BUILD_NUMBER]"
end

settings = YAML.load_file(ARGV.fetch(0)).fetch("targets").fetch("XPlay").fetch("settings").fetch("base")
version = settings.fetch("MARKETING_VERSION").to_s
build = settings.fetch("CURRENT_PROJECT_VERSION").to_s
abort "Invalid MARKETING_VERSION: #{version}" unless version.match?(/\A[0-9]+\.[0-9]+\.[0-9]+\z/)
abort "Invalid CURRENT_PROJECT_VERSION: #{build}" unless build.match?(/\A[1-9][0-9]*\z/)

if ARGV.length == 3
  abort "Package version #{ARGV[1]} does not match project version #{version}" unless ARGV[1] == version
  abort "Package build #{ARGV[2]} does not match project build #{build}" unless ARGV[2] == build
else
  puts "#{version} #{build}"
end
