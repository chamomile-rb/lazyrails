# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Local paths: use sibling dirs for dev, or subdirs in CI
{ "chamomile" => "chamomile", "chamomile-flourish" => "flourish", "chamomile-petals" => "petals" }.each do |gem_name, dir|
  path = ["../#{dir}", dir].find { |p| File.directory?(p) }
  gem gem_name, path: path if path
end

group :development, :test do
  gem "rspec", "~> 3.12"
  gem "rubocop", "~> 1.0"
end
