# frozen_string_literal: true

module LazyRails
  module Views
    module StatusView
      def self.render(panel, project, about_data, width:, focused:)
        lines = []
        lines << "Rails #{project.rails_version || '?'}"
        lines << "Ruby #{project.ruby_version || '?'}"

        env = about_data.is_a?(Hash) && (about_data["Environment"] || about_data[:environment])
        lines << "Env: #{env || 'development'}"

        lines << "App: #{project.app_name}" if project.app_name
        lines << "Branch: #{project.git_branch}" if project.git_branch

        if panel.loading
          lines << ""
          lines << "Loading..."
        elsif panel.error
          lines << ""
          lines << "! #{panel.error}"
        end

        lines.join("\n")
      end

      def self.render_detail(about_data, stats_data, notes_data, width:)
        sections = []

        if about_data.is_a?(Hash) && !about_data.empty?
          sections << "About"
          sections << ("=" * [width - 4, 40].min)
          about_data.each { |k, v| sections << "  #{k}: #{v}" }
          sections << ""
        end

        if stats_data.is_a?(Hash) && stats_data[:rows]&.any?
          sections << "Statistics"
          sections << ("=" * [width - 4, 40].min)
          header = "#{'Name'.ljust(25)} #{'Lines'.rjust(6)}  #{'LOC'.rjust(6)}  #{'Cls'.rjust(4)}  #{'Mth'.rjust(4)}"
          sections << header
          sections << ("-" * header.length)
          stats_data[:rows].each { |row| sections << row.to_s }

          if (s = stats_data[:summary]) && s[:code_loc]
            sections << ""
            sections << "Code LOC: #{s[:code_loc]}  Test LOC: #{s[:test_loc]}"
          end
          sections << ""
        end

        if notes_data.is_a?(Array) && notes_data.any?
          sections << "Notes"
          sections << ("=" * [width - 4, 40].min)
          current_file = nil
          notes_data.each do |note|
            if note.file != current_file
              sections << "" if current_file
              sections << note.file
              current_file = note.file
            end
            sections << "  [#{note.tag}] L#{note.line}: #{note.message}"
          end
        end

        sections.empty? ? "No data loaded yet." : sections.join("\n")
      end
    end
  end
end
