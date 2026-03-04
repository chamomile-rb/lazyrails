# frozen_string_literal: true

module LazyRails
  EvalEntry = Data.define(:expression, :result, :error, :duration_ms) do
    def to_s
      "> #{expression}"
    end

    def success? = error.nil?
  end
end
