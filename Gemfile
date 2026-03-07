# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Local paths: use sibling dirs for dev, or subdirs in CI
%w[chamomile flourish petals].each do |dep|
  path = ["../#{dep}", dep].find { |p| File.directory?(p) }
  gem dep, path: path if path
end

group :development, :test do
  gem "rspec", "~> 3.12"
  gem "rubocop", "~> 1.0"
end
