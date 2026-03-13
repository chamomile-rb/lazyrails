# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Local path: use sibling dir for dev
path = ["../chamomile", "chamomile"].find { |p| File.directory?(p) }
gem "chamomile", path: path if path

group :development, :test do
  gem "rspec", "~> 3.12"
  gem "rubocop", "~> 1.85"
end
