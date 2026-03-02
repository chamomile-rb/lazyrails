# frozen_string_literal: true

module LazyRails
  # Custom messages for async operations
  TestFinishedMsg = Data.define(:path, :status, :output)

  class App
    include Chamomile::Model
    include Chamomile::Commands

    PANEL_DEFS = [
      { type: :status,   title: "Status" },
      { type: :server,   title: "Server" },
      { type: :routes,   title: "Routes" },
      { type: :database, title: "Database" },
      { type: :models,   title: "Models" },
      { type: :tests,    title: "Tests" },
      { type: :gems,     title: "Gems" }
    ].freeze

    FOCUSED_COLOR = "#7d56f4"
    UNFOCUSED_COLOR = "#444444"
    LEFT_WIDTH_RATIO = 0.30
    UI_TICK_SECONDS = 1.0

    def initialize(project)
      @project = project
      @panels = PANEL_DEFS.map { |d| Panel.new(type: d[:type], title: d[:title]) }
      @focused_panel = 0
      @width = 80
      @height = 24
      @command_log = CommandLog.new
      @server = ServerManager.new(project)
      @detail_viewport = Petals::Viewport.new(width: 40, height: 20)
      @filter_input = Petals::TextInput.new(prompt: "/", placeholder: "filter...")

      # Data stores
      @introspect_data = nil
      @about_data = {}
      @stats_data = {}
      @notes_data = []

      # UI state
      @show_help = false
      @show_command_log = false
      @command_log_cursor = 0
      @command_log_detail = nil
      @flash = nil
      @flash_expiry = nil
      @confirmation = nil
      @filter_mode = false
      @filter_purpose = nil
      @route_grouped = false
      @last_server_state = :stopped

      # Detail content cache
      @detail_content = ""
    end

    # ─── Chamomile lifecycle ──────────────────────────────

    def start
      batch(
        load_introspect_cmd,
        load_about_cmd,
        load_gems_cmd,
        load_tests_cmd,
        ui_tick
      )
    end

    def update(msg)
      # Handle confirmation mode first
      return handle_confirmation(msg) if @confirmation

      # Handle filter mode
      return handle_filter(msg) if @filter_mode

      case msg
      when Chamomile::WindowSizeMsg
        handle_resize(msg)
      when Chamomile::KeyMsg
        return handle_key(msg)
      when Chamomile::TickMsg
        return handle_tick
      when Chamomile::InterruptMsg
        @server.stop
        return quit
      when IntrospectLoadedMsg
        return handle_introspect_loaded(msg)
      when AboutLoadedMsg
        handle_about_loaded(msg)
      when GemsLoadedMsg
        handle_gems_loaded(msg)
      when TestsLoadedMsg
        handle_tests_loaded(msg)
      when CommandFinishedMsg
        return handle_command_finished(msg)
      when TestFinishedMsg
        handle_test_finished(msg)
      end

      nil
    end

    def view
      return render_help if @show_help
      return render_command_log_overlay if @show_command_log

      left_width = (@width * LEFT_WIDTH_RATIO).to_i
      right_width = @width - left_width - 1

      left_content = render_left_panels(left_width)
      right_content = render_right_pane(right_width)

      layout = Flourish.join_horizontal(Flourish::TOP, left_content, " ", right_content)

      if @confirmation
        layout = "#{layout}\n#{render_confirmation}"
      elsif @filter_mode
        layout = "#{layout}\n#{render_filter_bar}"
      else
        layout = "#{layout}\n#{render_status_bar}"
      end

      layout
    end

    private

    # ─── UI tick (handles flash expiry + server polling) ──

    def ui_tick
      tick(UI_TICK_SECONDS)
    end

    def handle_tick
      # Clear expired flash messages
      if @flash && @flash_expiry && Time.now > @flash_expiry
        @flash = nil
        @flash_expiry = nil
      end

      # Detect server state changes
      current_state = @server.state
      if current_state != @last_server_state
        case current_state
        when :running
          set_flash("Server running on port #{@server.port}")
        when :stopped
          set_flash("Server stopped.") if @last_server_state == :running
        when :error
          set_flash("Server error — check detail pane")
        end
        @last_server_state = current_state
      end

      # Refresh server detail content if server panel is focused
      update_detail_content if current_panel.type == :server

      ui_tick
    end

    # ─── Key handling ────────────────────────────────────

    def handle_key(msg)
      # Help overlay intercepts all keys
      if @show_help
        @show_help = false if msg.key == "?" || msg.key == :escape
        return msg.key == "q" ? ((@server.stop; quit)) : nil
      end

      # Command log overlay intercepts all keys
      return handle_command_log_key(msg) if @show_command_log

      # Handle Shift+Tab (Chamomile sends :tab with [:shift] modifier)
      if msg.key == :tab && msg.shift?
        @focused_panel = (@focused_panel - 1) % @panels.size
        update_detail_content
        return nil
      end

      case msg.key
      when "q"
        @server.stop
        return quit
      when "?"
        @show_help = true
      when "L"
        @show_command_log = true
        @command_log_cursor = 0
        @command_log_detail = nil
      when :tab
        @focused_panel = (@focused_panel + 1) % @panels.size
        update_detail_content
      when "1".."7"
        idx = msg.key.to_i - 1
        if idx < @panels.size
          @focused_panel = idx
          update_detail_content
        end
      when "j", :down
        current_panel.move_cursor(1, panel_visible_height)
        update_detail_content
      when "k", :up
        current_panel.move_cursor(-1, panel_visible_height)
        update_detail_content
      when :enter
        return handle_enter
      when "/"
        start_filter
      when "R"
        return handle_refresh
      when "z"
        return handle_undo
      else
        return handle_panel_key(msg)
      end

      nil
    end

    def handle_command_log_key(msg)
      case msg.key
      when "L", :escape
        @show_command_log = false
        @command_log_detail = nil
      when "j", :down
        max = @command_log.size - 1
        @command_log_cursor = [@command_log_cursor + 1, [max, 0].max].min
        @command_log_detail = nil
      when "k", :up
        @command_log_cursor = [@command_log_cursor - 1, 0].max
        @command_log_detail = nil
      when :enter
        entry = @command_log.entries[@command_log_cursor]
        @command_log_detail = entry
      when "q"
        @server.stop
        return quit
      end
      nil
    end

    def handle_panel_key(msg)
      case current_panel.type
      when :server  then handle_server_key(msg)
      when :database then handle_database_key(msg)
      when :tests   then handle_tests_key(msg)
      when :gems    then return handle_gems_key(msg)
      when :routes  then handle_routes_key(msg)
      when :models  then handle_models_key(msg)
      end
    end

    def handle_server_key(msg)
      case msg.key
      when "s"
        @server.start
        set_flash("Starting server on port #{@server.port}...")
      when "S"
        @server.stop
        set_flash("Server stopped.")
      when "r"
        @server.restart
        set_flash("Restarting server...")
      when "p"
        start_input_for(:change_port)
      end
      nil
    end

    def handle_database_key(msg)
      case msg.key
      when "m"
        return run_rails_cmd("bin/rails db:migrate", :database)
      when "M"
        start_confirmation("bin/rails db:rollback", tier: :yellow)
      when "c"
        start_input_for(:migration_name)
      when "d"
        migration = current_panel.selected_item
        if migration
          start_confirmation("bin/rails db:migrate:down VERSION=#{migration.version}", tier: :yellow)
        end
      when "u"
        migration = current_panel.selected_item
        return run_rails_cmd("bin/rails db:migrate:up VERSION=#{migration.version}", :database) if migration
      end
      nil
    end

    def handle_tests_key(msg)
      case msg.key
      when "a" then return run_rails_cmd(test_all_command, :tests)
      when "f" then return run_rails_cmd(test_failed_command, :tests)
      end
      nil
    end

    def handle_gems_key(msg)
      case msg.key
      when "u"
        gem_entry = current_panel.selected_item
        return run_rails_cmd("bundle update #{gem_entry.name}", :gems) if gem_entry
      when "U"
        start_confirmation("bundle update", tier: :yellow)
      when "o"
        gem_entry = current_panel.selected_item
        return open_gem_homepage(gem_entry) if gem_entry
      end
      nil
    end

    def handle_routes_key(msg)
      case msg.key
      when "g"
        toggle_route_grouping
      end
      nil
    end

    def handle_models_key(msg)
      case msg.key
      when "g"
        start_input_for(:generate_model)
      end
      nil
    end

    def handle_enter
      panel = current_panel
      item = panel.selected_item
      return nil unless item

      case panel.type
      when :tests
        return run_test_file_cmd(item)
      end

      update_detail_content
      nil
    end

    # ─── Filter / input mode ─────────────────────────────

    def start_filter
      return unless %i[routes models tests gems].include?(current_panel.type)

      @filter_mode = true
      @filter_purpose = :filter
      @filter_input = Petals::TextInput.new(prompt: "/", placeholder: "filter...")
      @filter_input.focus
    end

    def start_input_for(purpose)
      @filter_mode = true
      @filter_purpose = purpose
      case purpose
      when :migration_name
        @filter_input = Petals::TextInput.new(prompt: "Migration name: ", placeholder: "CreateUsers")
      when :generate_model
        @filter_input = Petals::TextInput.new(prompt: "Model name: ", placeholder: "User name:string email:string")
      when :change_port
        @filter_input = Petals::TextInput.new(prompt: "Port: ", placeholder: "3000")
      end
      @filter_input.focus
    end

    def handle_filter(msg)
      return nil unless msg.is_a?(Chamomile::KeyMsg)

      case msg.key
      when :escape
        @filter_mode = false
        @filter_purpose = nil
        current_panel.filter_text = ""
        current_panel.reset_cursor
      when :enter
        @filter_mode = false
        value = @filter_input.value
        result = handle_input_submit(value)
        @filter_purpose = nil
        return result
      else
        @filter_input.update(msg)
        # Live-update filter text for the filter purpose
        if @filter_purpose == :filter
          current_panel.filter_text = @filter_input.value
          current_panel.reset_cursor
        end
      end

      nil
    end

    def handle_input_submit(value)
      case @filter_purpose
      when :filter
        current_panel.filter_text = value
        current_panel.reset_cursor
        nil
      when :migration_name
        return run_rails_cmd("bin/rails generate migration #{value}", :database) unless value.empty?
      when :generate_model
        return run_rails_cmd("bin/rails generate model #{value}", :models) unless value.empty?
      when :change_port
        port = value.to_i
        if port > 0 && port < 65_536
          @server.port = port
          set_flash("Port changed to #{port}")
        else
          set_flash("Invalid port: #{value}")
        end
        nil
      end
    end

    # ─── Confirmation mode ───────────────────────────────

    def start_confirmation(command, tier: nil, required_text: nil)
      panel_name = current_panel.title.downcase
      required_text ||= panel_name if tier == :red
      @confirmation = Confirmation.new(command: command, tier: tier, required_text: required_text)
    end

    def handle_confirmation(msg)
      return nil unless msg.is_a?(Chamomile::KeyMsg)

      @confirmation.handle_key(msg.key)

      if @confirmation.confirmed?
        command = @confirmation.command
        panel_type = current_panel.type
        @confirmation = nil
        return run_rails_cmd(command, panel_type)
      elsif @confirmation.cancelled?
        @confirmation = nil
        set_flash("Cancelled.")
      end

      nil
    end

    # ─── Data loading commands ───────────────────────────
    # All return Chamomile commands (lambdas) that run in
    # the framework's thread pool and return messages.

    def load_introspect_cmd
      project_dir = @project.dir
      cmd(-> {
        begin
          script = Introspect::RUNNER_SCRIPT
          result = CommandRunner.run("bin/rails runner #{script}", dir: project_dir)

          if result.success?
            data = Introspect.load(result.stdout)
            IntrospectLoadedMsg.new(data: data, error: nil)
          else
            IntrospectLoadedMsg.new(data: nil, error: result.stderr)
          end
        rescue => e
          IntrospectLoadedMsg.new(data: nil, error: e.message)
        end
      })
    end

    def load_about_cmd
      project_dir = @project.dir
      cmd(-> {
        begin
          about_result = CommandRunner.run("bin/rails about", dir: project_dir)
          stats_result = CommandRunner.run("bin/rails stats", dir: project_dir)
          notes_result = CommandRunner.run("bin/rails notes", dir: project_dir)

          about = about_result.success? ? Parsers::RailsAbout.parse(about_result.stdout) : {}
          stats = stats_result.success? ? Parsers::RailsStats.parse(stats_result.stdout) : {}
          notes = notes_result.success? ? Parsers::RailsNotes.parse(notes_result.stdout) : []

          error = about_result.success? ? nil : about_result.stderr
          AboutLoadedMsg.new(about: about, stats: stats, notes: notes, error: error)
        rescue => e
          AboutLoadedMsg.new(about: {}, stats: {}, notes: [], error: e.message)
        end
      })
    end

    def load_gems_cmd
      project_dir = @project.dir
      cmd(-> {
        begin
          lockfile = File.join(project_dir, "Gemfile.lock")
          gems = Parsers::GemfileLock.parse(lockfile)
          GemsLoadedMsg.new(gems: gems, error: nil)
        rescue => e
          GemsLoadedMsg.new(gems: [], error: e.message)
        end
      })
    end

    def load_tests_cmd
      project_dir = @project.dir
      cmd(-> {
        begin
          files = []
          test_dir = File.join(project_dir, "test")
          spec_dir = File.join(project_dir, "spec")

          if File.directory?(spec_dir)
            Dir.glob("#{spec_dir}/**/*_spec.rb").sort.each do |f|
              files << TestFile.new(path: f.sub("#{project_dir}/", ""))
            end
          end

          if File.directory?(test_dir)
            Dir.glob("#{test_dir}/**/*_test.rb").sort.each do |f|
              files << TestFile.new(path: f.sub("#{project_dir}/", ""))
            end
          end

          TestsLoadedMsg.new(files: files, error: nil)
        rescue => e
          TestsLoadedMsg.new(files: [], error: e.message)
        end
      })
    end

    # Run a command via Chamomile's thread pool, returning a CommandFinishedMsg
    def run_rails_cmd(command, panel_type)
      set_flash("Running: #{command}...")
      project_dir = @project.dir
      cmd(-> {
        result = CommandRunner.run(command, dir: project_dir)
        CommandFinishedMsg.new(entry: result, panel: panel_type)
      })
    end

    # Run a test file via Chamomile's thread pool
    def run_test_file_cmd(test_file)
      set_flash("Running: #{test_file.path}...")
      project_dir = @project.dir
      path = test_file.path
      test_cmd = path.start_with?("spec/") ? "bundle exec rspec #{path}" : "bin/rails test #{path}"

      cmd(-> {
        result = CommandRunner.run(test_cmd, dir: project_dir)
        status = result.success? ? :passed : :failed
        TestFinishedMsg.new(path: path, status: status, output: result.stdout + result.stderr)
      })
    end

    # Open gem homepage via Chamomile's thread pool
    def open_gem_homepage(gem_entry)
      project_dir = @project.dir
      name = gem_entry.name
      cmd(-> {
        begin
          result = CommandRunner.run("bundle info #{name}", dir: project_dir)
          if result.success? && (match = result.stdout.match(/Homepage:\s*(\S+)/))
            system("open", match[1])
          end
        rescue
          # Best-effort — ignore failures
        end
        nil
      })
    end

    # ─── Message handlers ────────────────────────────────

    def handle_introspect_loaded(msg)
      if msg.error
        load_fallback_data
        [:routes, :database, :models].each { |t| find_panel(t).error = msg.error }
      else
        @introspect_data = msg.data

        routes_panel = find_panel(:routes)
        routes_panel.items = msg.data.routes
        routes_panel.loading = false

        db_panel = find_panel(:database)
        db_panel.items = msg.data.migrations
        db_panel.loading = false
        pending = Views::DatabaseView.pending_count(msg.data.migrations)
        db_panel.title = pending > 0 ? "Database (#{pending} pending)" : "Database"

        models_panel = find_panel(:models)
        models_panel.items = msg.data.models
        models_panel.loading = false
      end

      [:routes, :database, :models].each { |t| find_panel(t).loading = false }
      update_detail_content
      nil
    end

    def handle_about_loaded(msg)
      @about_data = msg.about || {}
      @stats_data = msg.stats || {}
      @notes_data = msg.notes || []

      status_panel = find_panel(:status)
      status_panel.loading = false
      status_panel.error = msg.error
      update_detail_content
    end

    def handle_gems_loaded(msg)
      gems_panel = find_panel(:gems)
      gems_panel.items = msg.gems
      gems_panel.loading = false
      gems_panel.error = msg.error
      update_detail_content
    end

    def handle_tests_loaded(msg)
      tests_panel = find_panel(:tests)
      tests_panel.items = msg.files
      tests_panel.loading = false
      tests_panel.error = msg.error
      update_detail_content
    end

    def handle_command_finished(msg)
      @command_log.add(msg.entry)
      set_flash("#{msg.entry.success? ? "\u2713" : "\u2717"} #{msg.entry.command} (#{msg.entry.duration_ms}ms)")

      # Reload panel data after command
      case msg.panel
      when :database, :models
        return load_introspect_cmd
      when :gems
        return load_gems_cmd
      when :tests
        return load_tests_cmd
      end

      nil
    end

    def handle_test_finished(msg)
      tests_panel = find_panel(:tests)
      idx = tests_panel.items.index { |f| f.path == msg.path }
      if idx
        tests_panel.items[idx] = TestFile.new(
          path: msg.path,
          status: msg.status,
          last_output: msg.output
        )
      end
      set_flash("#{msg.status == :passed ? "\u2713" : "\u2717"} #{msg.path}")
      update_detail_content
    end

    def handle_resize(msg)
      @width = msg.width
      @height = msg.height
      right_width = @width - (@width * LEFT_WIDTH_RATIO).to_i - 1
      @detail_viewport.set_width(right_width - 4)
      @detail_viewport.set_height(@height - 4)
    end

    def handle_refresh
      panel = current_panel
      panel.loading = true
      case panel.type
      when :routes, :database, :models
        return load_introspect_cmd
      when :status
        return load_about_cmd
      when :gems
        return load_gems_cmd
      when :tests
        return load_tests_cmd
      end
      nil
    end

    def handle_undo
      entry = @command_log.last_reversible
      unless entry
        set_flash("Nothing to undo.")
        return nil
      end

      reverse = @command_log.reverse_command(entry)
      unless reverse
        set_flash("Cannot undo.")
        return nil
      end

      start_confirmation(reverse, tier: :yellow)
      nil
    end

    # ─── Rendering ───────────────────────────────────────

    def render_left_panels(width)
      panel_heights = distribute_panel_heights(@height - 2)
      sections = []

      @panels.each_with_index do |panel, i|
        focused = i == @focused_panel
        h = panel_heights[i]
        content = render_panel_content(panel, width: width - 4, height: h - 2, focused: focused)

        border_color = focused ? FOCUSED_COLOR : UNFOCUSED_COLOR
        box = Flourish::Style.new
          .width(width)
          .height(h)
          .border(Flourish::Border::ROUNDED)
          .border_foreground(border_color)
          .render(content)

        box_lines = box.lines
        if box_lines.any?
          title = " #{panel.title} "
          title_styled = Flourish::Style.new.foreground(border_color).bold.render(title)
          box_lines[0] = inject_title(box_lines[0], title_styled, title.length)
        end

        sections << box_lines.join
      end

      Flourish.join_vertical(Flourish::LEFT, *sections)
    end

    def render_panel_content(panel, width:, height:, focused:)
      return "Loading..." if panel.loading

      if panel.error && panel.items.empty?
        return Views::ErrorView.render(panel.error.to_s, width: width)
      end

      case panel.type
      when :status
        Views::StatusView.render(panel, @project, @about_data, width: width, focused: focused)
      when :server
        Views::ServerView.render(@server, width: width, focused: focused)
      else
        render_list_panel(panel, width: width, height: height, focused: focused)
      end
    end

    def render_list_panel(panel, width:, height:, focused:)
      items = panel.filtered_items
      return "No items." if items.empty?

      visible = items[panel.scroll_offset, [height, 1].max] || []
      visible.each_with_index.map do |item, i|
        selected = focused && (i + panel.scroll_offset) == panel.cursor
        case panel.type
        when :routes   then Views::RoutesView.render_item(item, selected: selected, width: width)
        when :database then Views::DatabaseView.render_item(item, selected: selected, width: width)
        when :models   then Views::ModelsView.render_item(item, selected: selected, width: width)
        when :tests    then Views::TestsView.render_item(item, selected: selected, width: width)
        when :gems     then Views::GemsView.render_item(item, selected: selected, width: width)
        else
          selected ? Flourish::Style.new.reverse.render(item.to_s) : item.to_s
        end
      end.join("\n")
    end

    def render_right_pane(width)
      update_detail_content
      @detail_viewport.set_width(width - 4)
      @detail_viewport.set_height(@height - 4)
      @detail_viewport.set_content(@detail_content)

      content = @detail_viewport.view
      border_color = UNFOCUSED_COLOR

      box = Flourish::Style.new
        .width(width)
        .height(@height - 2)
        .border(Flourish::Border::ROUNDED)
        .border_foreground(border_color)
        .render(content)

      box_lines = box.lines
      if box_lines.any?
        title = " Detail "
        title_styled = Flourish::Style.new.foreground(border_color).bold.render(title)
        box_lines[0] = inject_title(box_lines[0], title_styled, title.length)
      end

      box_lines.join
    end

    def update_detail_content
      panel = current_panel
      item = panel.selected_item

      @detail_content = case panel.type
      when :status
        Views::StatusView.render_detail(@about_data, @stats_data, @notes_data, width: detail_width)
      when :server
        Views::ServerView.render_detail(@server, width: detail_width)
      when :routes
        item ? Views::RoutesView.render_detail(item, @project.dir, width: detail_width) : "Select a route."
      when :database
        item ? Views::DatabaseView.render_detail(item, @project.dir, width: detail_width) : "Select a migration."
      when :models
        item ? Views::ModelsView.render_detail(item, width: detail_width) : "Select a model."
      when :tests
        item ? Views::TestsView.render_detail(item, width: detail_width) : "Select a test file."
      when :gems
        item ? Views::GemsView.render_detail(item, width: detail_width) : "Select a gem."
      else
        ""
      end
    end

    def render_status_bar
      left = if @flash
        "  #{@flash}"
      else
        " Tab navigate \u2502 j/k scroll \u2502 Enter select \u2502 L log \u2502 ? help \u2502 q quit"
      end

      Flourish::Style.new
        .foreground("#666666")
        .width(@width)
        .render(left.slice(0, @width))
    end

    def render_filter_bar
      Flourish::Style.new.width(@width).render(@filter_input.view)
    end

    def render_confirmation
      return "" unless @confirmation

      text = @confirmation.prompt_text
      return "" unless text

      color = @confirmation.red? ? "#ff6347" : "#e5c07b"
      Flourish::Style.new.foreground(color).width(@width).render(text)
    end

    def render_help
      Views::HelpView.render(width: @width, height: @height)
    end

    def render_command_log_overlay
      if @command_log.empty?
        return "No commands executed yet.\n\nPress L or Esc to close."
      end

      header = Flourish::Style.new.bold.render("Command Log")
      list = Views::CommandLogView.render(@command_log, width: @width - 4, selected: @command_log_cursor)

      parts = [header, "", list]

      if @command_log_detail
        parts << ""
        parts << Flourish::Style.new.bold.render("Detail")
        parts << Views::CommandLogView.render_detail(@command_log_detail, width: @width - 4)
      end

      parts << ""
      parts << "j/k navigate | Enter detail | L or Esc close | q quit"
      parts.join("\n")
    end

    # ─── Helpers ─────────────────────────────────────────

    def current_panel
      @panels[@focused_panel]
    end

    def find_panel(type)
      @panels.find { |p| p.type == type }
    end

    def panel_visible_height
      heights = distribute_panel_heights(@height - 2)
      h = heights[@focused_panel] || 5
      [h - 2, 1].max
    end

    def detail_width
      [@width - (@width * LEFT_WIDTH_RATIO).to_i - 5, 10].max
    end

    def distribute_panel_heights(total)
      n = @panels.size
      min_unfocused = 3

      unfocused_total = (n - 1) * min_unfocused
      focused_height = total - unfocused_total

      # Fall back to equal distribution if terminal is too small
      if focused_height < min_unfocused
        base = total / n
        remainder = total % n
        return @panels.each_with_index.map { |_, i| i < remainder ? base + 1 : base }
      end

      @panels.each_with_index.map { |_, i| i == @focused_panel ? focused_height : min_unfocused }
    end

    def set_flash(message, duration: 3)
      @flash = message
      @flash_expiry = Time.now + duration
    end

    def load_fallback_data
      schema_path = File.join(@project.dir, "db/schema.rb")
      if File.exist?(schema_path)
        tables = Parsers::Schema.parse(File.read(schema_path))
        models_panel = find_panel(:models)
        models_panel.items = tables.map do |table_name, cols|
          ModelInfo.new(name: classify_name(table_name), table_name: table_name, columns: cols)
        end
      end
    end

    # Simple classify without ActiveSupport
    def classify_name(table_name)
      table_name.to_s.split("_").map(&:capitalize).join
    end

    def test_all_command
      if File.directory?(File.join(@project.dir, "spec"))
        "bundle exec rspec"
      else
        "bin/rails test"
      end
    end

    def test_failed_command
      if File.directory?(File.join(@project.dir, "spec"))
        "bundle exec rspec --only-failures"
      else
        "bin/rails test --fail-fast"
      end
    end

    def toggle_route_grouping
      panel = find_panel(:routes)
      return unless @introspect_data

      if @route_grouped
        panel.items = @introspect_data.routes
        @route_grouped = false
      else
        grouped = @introspect_data.routes.sort_by do |r|
          r.action.split("#").first rescue "zzz"
        end
        panel.items = grouped
        @route_grouped = true
      end
      panel.reset_cursor
    end

    def inject_title(top_line, styled_title, title_visible_len)
      stripped = Flourish::ANSI.strip(top_line)
      return top_line if stripped.length <= title_visible_len + 2

      # Extract the leading ANSI escape sequences (border styling)
      ansi_prefix = top_line[/\A((?:\e\[[0-9;]*m)*)/] || ""
      reset = "\e[0m"

      corner = stripped[0]
      rest = stripped[(1 + title_visible_len)..]

      # Preserve border styling: corner in border color, title with its own styling, rest in border color
      "#{ansi_prefix}#{corner}#{reset}#{styled_title}#{ansi_prefix}#{rest}#{reset}"
    end
  end
end
