# frozen_string_literal: true

module LazyRails
  class CommandLog
    MAX_ENTRIES = 100

    attr_reader :entries

    def initialize
      @entries = []
    end

    def add(entry)
      @entries << entry
      @entries.shift if @entries.size > MAX_ENTRIES
      entry
    end

    def last_entry
      @entries.last
    end

    def last_reversible
      @entries.reverse_each do |e|
        return e if reversible?(e)
      end
      nil
    end

    def size
      @entries.size
    end

    def empty?
      @entries.empty?
    end

    def clear
      @entries.clear
    end

    def reversible?(entry)
      return false unless entry.success?

      case entry.command
      when /rails generate / then true
      when /db:migrate\b(?!:)/ then true
      when /db:migrate:up/     then true
      else false
      end
    end

    def reverse_command(entry)
      case entry.command
      when /rails generate (.+)/
        entry.command.sub("generate", "destroy")
      when /db:migrate\b(?!:)/
        "bin/rails db:rollback"
      when /db:migrate:up VERSION=(\d+)/
        version = Regexp.last_match(1)
        "bin/rails db:migrate:down VERSION=#{version}"
      end
    end
  end
end
