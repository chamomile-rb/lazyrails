# frozen_string_literal: true

module LazyRails
  module Views
    module RoutesView
      VERB_COLORS = {
        "GET" => "#04b575",
        "POST" => "#5b9bd5",
        "PUT" => "#e5c07b",
        "PATCH" => "#e5c07b",
        "DELETE" => "#ff6347"
      }.freeze

      def self.render_item(route, selected:, width:)
        verb = route.verb.ljust(7)
        path = ViewHelpers.truncate(route.path, [width - 12, 1].max)

        if selected
          ViewHelpers.selected_style.render("#{verb} #{path}".ljust(width))
        else
          styled_verb = Chamomile::Style.new.foreground(VERB_COLORS[route.verb] || "#999999").render(verb)
          "#{styled_verb} #{path}"
        end
      end

      def self.render_detail(route, project_dir, width:, file_cache: nil)
        lines = []
        lines << "#{route.verb} #{route.path}"
        lines << ("=" * [width - 4, 40].min)
        lines << ""
        lines << "Action:     #{route.action}"
        lines << "Name:       #{route.name}" if route.name && !route.name.empty?
        lines << "Engine:     Yes" if route.engine

        if route.action.include?("#")
          controller, action_name = route.action.split("#", 2)
          controller_file = "app/controllers/#{controller.gsub('::', '/')}_controller.rb"
          full_path = File.join(project_dir, controller_file)

          lines << ""
          lines << "Controller: #{controller_file}"
          content = file_cache ? file_cache.read(full_path) : safe_read(full_path)
          if content
            lines << "Status:     File exists"
            lines << if content.include?("def #{action_name}")
                       "Method:     def #{action_name} \u2713"
                     else
                       "Method:     def #{action_name} \u2717 (not found in file)"
                     end
          else
            lines << "Status:     File not found"
          end
        end

        if route.name && !route.name.empty?
          lines << ""
          lines << "Helpers:"
          lines << "  #{route.name}_path"
          lines << "  #{route.name}_url"
        end

        lines.join("\n")
      end

      def self.safe_read(path)
        File.exist?(path) ? File.read(path) : nil
      end
      private_class_method :safe_read
    end
  end
end
