# frozen_string_literal: true

require "yaml"
require "fileutils"

module LazyRails
  class UserSettings
    DEFAULT_CONFIG_DIR = File.join(Dir.home, ".config", "lazyrails")

    def initialize(config_dir: DEFAULT_CONFIG_DIR)
      @config_dir = config_dir
      @settings_file = File.join(config_dir, "settings.yml")
      @data = load_settings
    end

    def welcome_seen?
      @data["welcome_seen"] == true
    end

    def mark_welcome_seen!
      @data["welcome_seen"] = true
      save_settings
    end

    private

    def load_settings
      return {} unless File.exist?(@settings_file)

      YAML.safe_load_file(@settings_file) || {}
    rescue StandardError
      {}
    end

    def save_settings
      FileUtils.mkdir_p(@config_dir)
      File.write(@settings_file, YAML.dump(@data))
    rescue StandardError
      # Best-effort — don't crash if we can't write settings
    end
  end
end
