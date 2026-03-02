# frozen_string_literal: true

module LazyRails
  module Views
    module DatabaseView
      def self.render_item(migration, selected:, width:)
        arrow = migration.up? ? "\u2191" : "\u2193"
        color = migration.up? ? "#04b575" : "#ff6347"
        text = "#{arrow} #{migration.version}  #{truncate(migration.name, width - 22)}"

        if selected
          Flourish::Style.new.reverse.render(text)
        else
          icon = Flourish::Style.new.foreground(color).render(arrow)
          "#{icon} #{migration.version}  #{truncate(migration.name, width - 22)}"
        end
      end

      def self.render_detail(migration, project_dir, width:)
        lines = []
        lines << "Migration: #{migration.name}"
        lines << "Version:   #{migration.version}"
        lines << "Status:    #{migration.up? ? "UP" : "DOWN"}"
        lines << "Database:  #{migration.database}"
        lines << ""

        if migration.file_path
          full_path = File.expand_path(migration.file_path, project_dir)
          if File.exist?(full_path)
            lines << "File: #{migration.file_path}"
            lines << "=" * [width - 4, 40].min
            lines << ""
            lines << File.read(full_path)
          else
            lines << "File not found: #{migration.file_path}"
          end
        end

        lines.join("\n")
      end

      def self.pending_count(migrations)
        migrations.count(&:down?)
      end

      def self.truncate(str, max)
        return str if max < 1
        return str if str.length <= max

        str[0..max - 2] + "\u2026"
      end

      private_class_method :truncate
    end
  end
end
