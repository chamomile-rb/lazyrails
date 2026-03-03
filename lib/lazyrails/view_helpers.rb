# frozen_string_literal: true

module LazyRails
  module ViewHelpers
    def self.truncate(str, max)
      return str if max < 1 || str.length <= max

      str[0..max - 2] + "\u2026"
    end

    def self.classify_name(name)
      name.to_s.split("_").map(&:capitalize).join
    end
  end
end
