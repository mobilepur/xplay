# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"

class CommandResult
  def initialize(status)
    @status = status
  end

  def success?
    @status.success?
  end
end

class CaskPostflightHarness
  attr_reader :app_path

  def initialize(root)
    @appdir = Pathname(root).join("Applications")
    @app_path = @appdir.join("XPlay.app")
    FileUtils.mkdir_p(@app_path)
  end

  def load(cask_path)
    Object.send(:define_method, :cask) do |_token, &block|
      $cask_postflight_harness.instance_eval(&block)
    end
    $cask_postflight_harness = self
    Kernel.load(cask_path)
  ensure
    Object.send(:remove_method, :cask)
  end

  def execute
    raise "Generated Cask has no postflight_steps block" unless @postflight_steps

    instance_eval(&@postflight_steps)
  end

  def postflight_steps(&block)
    @postflight_steps = block
  end

  def appdir
    @appdir
  end

  def run(executable, args:, must_succeed: true, print_stderr: true, **_options)
    expanded_args = args.map { |arg| arg.gsub("{{appdir}}", @appdir.to_s) }
    _stdout, stderr, status = Open3.capture3(executable, *expanded_args)
    warn stderr if print_stderr && !stderr.empty?
    raise "Command failed: #{executable} #{expanded_args.join(' ')}" if must_succeed && !status.success?

    CommandResult.new(status)
  end

  def method_missing(_name, *_args, **_kwargs)
    nil
  end

  def respond_to_missing?(_name, _include_private = false)
    true
  end
end

def set_quarantine(path)
  _stdout, stderr, status = Open3.capture3(
    "/usr/bin/xattr",
    "-w",
    "com.apple.quarantine",
    "0081;00000000;Homebrew;00000000-0000-0000-0000-000000000000",
    path.to_s,
  )
  raise stderr unless status.success?
end

def quarantined?(path)
  _stdout, _stderr, status = Open3.capture3(
    "/usr/bin/xattr",
    "-p",
    "com.apple.quarantine",
    path.to_s,
  )
  status.success?
end

cask_path, root = ARGV
harness = CaskPostflightHarness.new(root)
harness.load(cask_path)

harness.execute

set_quarantine(harness.app_path)
harness.execute

raise "App quarantine attribute was not removed" if quarantined?(harness.app_path)
