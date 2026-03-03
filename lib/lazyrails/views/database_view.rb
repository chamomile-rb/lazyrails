# frozen_string_literal: true

module LazyRails
  module Views
    module DatabaseView
      def self.render_item(migration, selected:, width:)
        arrow = migration.up? ? "\u2191" : "\u2193"
        color = migration.up? ? "#04b575" : "#ff6347"
        text = "#{arrow} #{migration.version}  #{ViewHelpers.truncate(migration.name, width - 22)}"

        if selected
          Flourish::Style.new.reverse.render(text)
        else
          icon = Flourish::Style.new.foreground(color).render(arrow)
          "#{icon} #{migration.version}  #{ViewHelpers.truncate(migration.name, width - 22)}"
        end
      end

      def self.render_detail(migration, project_dir, width:, file_cache: nil)
        lines = []
        lines << "Migration: #{migration.name}"
        lines << "Version:   #{migration.version}"
        lines << "Status:    #{migration.up? ? "UP" : "DOWN"}"
        lines << "Database:  #{migration.database}"
        lines << ""

        if migration.file_path
          full_path = File.expand_path(migration.file_path, project_dir)
          content = file_cache ? file_cache.read(full_path) : safe_read(full_path)
          if content
            lines << "File: #{migration.file_path}"
            lines << "=" * [width - 4, 40].min
            lines << ""
            lines << content
          else
            lines << "File not found: #{migration.file_path}"
          end
        end

        lines.join("\n")
      end

      def self.safe_read(path)
        File.exist?(path) ? File.read(path) : nil
      end
      private_class_method :safe_read

      def self.pending_count(migrations)
        migrations.count(&:down?)
      end

    end
  end
end
