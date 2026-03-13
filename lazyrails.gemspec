# frozen_string_literal: true

require_relative "lib/lazyrails/version"

Gem::Specification.new do |spec|
  spec.name = "lazyrails-tui"
  spec.version = LazyRails::VERSION
  spec.authors = ["Jack Killilea"]
  spec.summary = "A lazygit-style terminal UI for the Rails command line"
  spec.description = "LazyRails gives Rails developers a fast, navigable TUI " \
                     "that surfaces everything the Rails CLI offers in a single split-pane interface."
  spec.homepage = "https://github.com/xjackk/lazyrails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/xjackk/lazyrails"
  spec.metadata["changelog_uri"] = "https://github.com/xjackk/lazyrails/blob/master/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "bin/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "bin"
  spec.executables = ["lazyrails"]

  spec.add_dependency "chamomile", "~> 1.0"
end
