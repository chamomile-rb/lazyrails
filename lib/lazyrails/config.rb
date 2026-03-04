# frozen_string_literal: true

require "yaml"

module LazyRails
  class Config
    CustomCommand = Data.define(:name, :key, :command, :confirmation) do
      def to_s = name
      def confirmation_tier = confirmation&.to_sym || :green
    end

    attr_reader :custom_commands

    def self.load(project_dir)
      path = File.join(project_dir, ".lazyrails.yml")
      return new([]) unless File.exist?(path)

      data = YAML.safe_load_file(path, symbolize_names: true) || {}
      commands = (data[:custom_commands] || []).map do |c|
        CustomCommand.new(
          name: c[:name].to_s,
          key: c[:key].to_s,
          command: c[:command].to_s,
          confirmation: c[:confirmation]
        )
      end
      new(commands)
    rescue
      new([])
    end

    def initialize(commands)
      @custom_commands = commands
    end

    def empty? = @custom_commands.empty?
  end
end
