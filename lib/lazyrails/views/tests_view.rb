# frozen_string_literal: true

module LazyRails
  module Views
    module TestsView
      def self.render_item(test_file, selected:, width:)
        text = test_file.to_s

        if selected
          Flourish::Style.new.reverse.render(text)
        else
          color = case test_file.status
                  when :passed then "#04b575"
                  when :failed then "#ff6347"
                  else "#999999"
                  end
          Flourish::Style.new.foreground(color).render(text)
        end
      end

      def self.render_detail(test_file, width:)
        if test_file.last_output
          test_file.last_output
        else
          "Press Enter to run this test.\n\nFile: #{test_file.path}"
        end
      end
    end
  end
end
