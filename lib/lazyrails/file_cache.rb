# frozen_string_literal: true

module LazyRails
  class FileCache
    def initialize
      @cache = {}
    end

    def read(path)
      return @cache[path] if @cache.key?(path)

      @cache[path] = (File.read(path) if File.exist?(path))
    end

    def invalidate
      @cache.clear
    end
  end
end
