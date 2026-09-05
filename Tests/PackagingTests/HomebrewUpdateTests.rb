# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
WORKFLOW = YAML.load_file(File.join(ROOT, ".github/workflows/release.yml"))
UPDATE = WORKFLOW.fetch("jobs").fetch("release").fetch("steps").find { |step| step["name"] == "Update Homebrew tap" }.fetch("run")

def run(*command, chdir:)
  output, status = Open3.capture2e(*command, chdir: chdir)
  raise "#{command.inspect} failed:\n#{output}" unless status.success?

  output
end

Dir.mktmpdir("xplay-homebrew-test") do |root|
  remote = File.join(root, "remote.git")
  tap = File.join(root, "homebrew-tap")
  run("git", "init", "--bare", "--initial-branch=main", remote, chdir: root)
  run("git", "clone", remote, tap, chdir: root)
  run("git", "config", "user.name", "Test", chdir: tap)
  run("git", "config", "user.email", "test@example.invalid", chdir: tap)
  FileUtils.mkdir_p(File.join(tap, "Casks"))
  FileUtils.mkdir_p(File.join(root, "dist"))
  FileUtils.cp_r(File.join(ROOT, "Scripts"), root)
  cask = File.join(tap, "Casks/xplay.rb")
  candidate = File.join(root, "dist/xplay.rb")
  File.write(cask, "cask \"xplay\" do\n  version \"1.10.0\"\n  sha256 \"current\"\nend\n")
  run("git", "add", ".", chdir: tap)
  run("git", "commit", "-m", "Current release", chdir: tap)
  run("git", "push", "origin", "HEAD:main", chdir: tap)
  original = run("git", "rev-parse", "HEAD", chdir: tap)

  File.write(candidate, "cask \"xplay\" do\n  version \"1.9.0\"\n  sha256 \"old\"\nend\n")
  run({ "GITHUB_REF_NAME" => "v1.9.0" }, "bash", "-euo", "pipefail", "-c", UPDATE, chdir: root)
  raise "Older release downgraded the Homebrew Cask" unless File.read(cask).include?('version "1.10.0"')
  raise "Older release created a commit" unless run("git", "rev-parse", "HEAD", chdir: tap) == original
  puts "Older release leaves current Cask unchanged"

  File.write(candidate, File.read(cask).sub('sha256 "current"', 'sha256 "repaired"'))
  run({ "GITHUB_REF_NAME" => "v1.10.0" }, "bash", "-euo", "pipefail", "-c", UPDATE, chdir: root)
  raise "Same-version rerun did not repair the Cask" unless File.read(cask) == File.read(candidate)
  repaired = run("git", "rev-parse", "HEAD", chdir: tap)
  run({ "GITHUB_REF_NAME" => "v1.10.0" }, "bash", "-euo", "pipefail", "-c", UPDATE, chdir: root)
  raise "Identical rerun created a commit" unless run("git", "rev-parse", "HEAD", chdir: tap) == repaired
  puts "Same-version repair and identical rerun passed"

  File.write(candidate, File.read(candidate).sub('version "1.10.0"', 'version "2.0.0"'))
  run({ "GITHUB_REF_NAME" => "v2.0.0" }, "bash", "-euo", "pipefail", "-c", UPDATE, chdir: root)
  published = run("git", "show", "main:Casks/xplay.rb", chdir: remote)
  raise "Newer release was not pushed" unless published == File.read(candidate)
  puts "Newer release advances the remote Cask"

  # Simulate the tap advancing since the workflow checked it out.
  other = File.join(root, "other")
  run("git", "clone", remote, other, chdir: root)
  run("git", "config", "user.name", "Test", chdir: other)
  run("git", "config", "user.email", "test@example.invalid", chdir: other)
  File.write(File.join(other, "Casks/xplay.rb"), File.read(candidate).sub('version "2.0.0"', 'version "3.0.0"'))
  run("git", "add", ".", chdir: other)
  run("git", "commit", "-m", "Concurrent newer release", chdir: other)
  run("git", "push", "origin", "main", chdir: other)
  File.write(candidate, File.read(candidate).sub('version "2.0.0"', 'version "2.1.0"'))
  run({ "GITHUB_REF_NAME" => "v2.1.0" }, "bash", "-euo", "pipefail", "-c", UPDATE, chdir: root)
  raise "Stale checkout overwrote newer remote release" unless File.read(cask).include?('version "3.0.0"')
  puts "Stale checkout refreshes before comparing versions"

  File.write(candidate, "invalid Cask")
  _, status = Open3.capture2e({ "GITHUB_REF_NAME" => "v4.0.0" }, "bash", "-euo", "pipefail", "-c", UPDATE, chdir: root)
  raise "Malformed Cask was accepted" if status.success?
  raise "Malformed Cask changed current release" unless File.read(cask).include?('version "3.0.0"')
  puts "Malformed metadata fails without replacing the current Cask"
end

concurrency = WORKFLOW.fetch("concurrency")
raise "Release concurrency must serialize all tags" unless concurrency.fetch("group") == "xplay-release"
raise "Release concurrency must preserve active runs" unless concurrency.fetch("cancel-in-progress") == false
raise "Pending releases must queue without replacing each other" unless concurrency["queue"] == "max"
puts "All release tags share a non-cancelling concurrency queue"
