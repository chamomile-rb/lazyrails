# frozen_string_literal: true

require "rbconfig"

module LazyRails
  module Platform
    def self.open_url(url)
      case RbConfig::CONFIG["host_os"]
      when /darwin/i
        system("open", url)
      when /linux|bsd/i
        system("xdg-open", url)
      when /mswin|mingw|cygwin/i
        system("start", url)
      end
    end
  end
end
