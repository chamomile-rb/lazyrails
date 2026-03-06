# frozen_string_literal: true

module LazyRails
  module Views
    module ServerView
      STATE_ICONS = {
        stopped: "\u25CB",  # ○
        starting: "\u25CE", # ◎
        running: "\u25CF",  # ●
        error: "\u2716"     # ✖
      }.freeze

      def self.render(server_manager, width:, focused:)
        state = server_manager.state
        icon = STATE_ICONS[state]
        port = server_manager.port
        mode = server_manager.uses_bin_dev? ? "bin/dev" : "rails server"

        lines = []
        case state
        when :running
          lines << "#{icon} Running :#{port} (#{mode})"
          lines << "PID: #{server_manager.pid}" if server_manager.pid
          lines << "S stop \u2502 r restart"
        when :starting
          lines << "#{icon} Starting :#{port}..."
        when :stopped
          lines << "#{icon} Stopped"
          lines << "s start \u2502 p change port"
        when :error
          lines << "#{icon} Error"
          lines << "s retry \u2502 p change port"
        end

        lines.join("\n")
      end

      def self.render_detail(server_manager, width:)
        content = server_manager.log_content
        content.empty? ? "No server output yet.\n\nPress 's' to start the server." : content
      end
    end
  end
end
