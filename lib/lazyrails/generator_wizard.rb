# frozen_string_literal: true

module LazyRails
  class GeneratorWizard
    COLUMN_TYPES = %w[
      string integer text boolean float decimal
      datetime date time binary references
    ].freeze

    CONTROLLER_ACTIONS = %w[index show new create edit update destroy].freeze

    attr_reader :gen_type, :step

    def initialize
      @visible = false
      @gen_type = nil
      @gen_label = nil
      @step = :name
      @name = ""
      @fields = []        # [{name: "email", type: "string"}, ...]
      @methods = []       # ["welcome", "reset_password"]
      @method_input = +""
      @field_name_input = +""
      @type_cursor = 0
      @field_cursor = 0
      @action_toggles = {} # {"index" => true, "show" => false, ...}
      @action_cursor = 0
      @editing_field_name = true # true = typing field name, false = picking type
      @error = nil
    end

    def visible? = @visible

    def show(gen_type:, gen_label:)
      @visible = true
      @gen_type = gen_type
      @gen_label = gen_label
      @step = :name
      @name = +""
      @fields = []
      @methods = []
      @method_input = +""
      @field_name_input = +""
      @type_cursor = 0
      @field_cursor = 0
      @action_toggles = CONTROLLER_ACTIONS.to_h { |a| [a, false] }
      @action_cursor = 0
      @editing_field_name = true
      @error = nil
    end

    def hide
      @visible = false
    end

    # Returns nil normally, or a Hash with :action when done
    # { action: :run, command: ["bin/rails", "generate", ...] }
    # { action: :cancel }
    def handle_key(key)
      @error = nil

      case @step
      when :name    then handle_name_key(key)
      when :fields  then handle_fields_key(key)
      when :actions then handle_actions_key(key)
      when :methods then handle_methods_key(key)
      when :review  then handle_review_key(key)
      end
    end

    def render(width:, height:)
      return "" unless @visible

      content = case @step
                when :name    then render_name_step
                when :fields  then render_fields_step
                when :actions then render_actions_step
                when :methods then render_methods_step
                when :review  then render_review_step
                end

      menu_width = [width * 0.6, 50].max.to_i
      menu_width = [menu_width, width - 4].min

      step_label = step_indicator
      footer = render_footer

      box = Chamomile::Style.new
                            .width(menu_width)
                            .border(Chamomile::Border::ROUNDED)
                            .border_foreground("#b48ead")
                            .padding(0, 1)
                            .render("#{content}\n\n#{footer}")

      box_lines = box.lines
      if box_lines.any?
        title_text = " Generate #{@gen_label} #{step_label} "
        title_styled = Chamomile::Style.new.foreground("#b48ead").bold.render(title_text)
        box_lines[0] = ViewHelpers.inject_title(box_lines[0], title_styled, title_text.length)
      end

      box_lines.join
    end

    private

    # ─── Step indicators ───────────────────────────────

    def step_indicator
      steps = step_names
      idx = steps.index(@step) || 0
      "(#{idx + 1}/#{steps.size})"
    end

    def step_names
      case @gen_type
      when "model", "scaffold"    then %i[name fields review]
      when "migration"            then %i[name fields review]
      when "controller"           then %i[name actions review]
      when "mailer"               then %i[name methods review]
      when "job", "channel", "stimulus" then %i[name review]
      else %i[name review]
      end
    end

    def next_step
      steps = step_names
      idx = steps.index(@step) || 0
      steps[idx + 1] || :review
    end

    # ─── Name step ─────────────────────────────────────

    def handle_name_key(key)
      case key
      when :escape
        hide
        { action: :cancel }
      when :enter
        if @name.strip.empty?
          @error = "Name cannot be empty"
        else
          @step = next_step
        end
        nil
      when :backspace
        @name.chop!
        nil
      else
        @name << key.to_s if key.is_a?(String) && key.length == 1
        nil
      end
    end

    def render_name_step
      lines = []
      lines << "Enter the #{@gen_label.downcase} name:"
      lines << ""

      prompt = "> #{@name}\u2588"
      lines << Chamomile::Style.new.bold.render(prompt)

      lines << ""
      lines << Chamomile::Style.new.foreground("#666666").render(name_hint)

      if @error
        lines << ""
        lines << Chamomile::Style.new.foreground("#ff6347").render(@error)
      end

      lines.join("\n")
    end

    def name_hint
      case @gen_type
      when "model"      then "e.g. User, BlogPost, Admin::Setting"
      when "scaffold"   then "e.g. Article, Product, Admin::User"
      when "migration"  then "e.g. AddStatusToOrders, CreateProducts"
      when "controller" then "e.g. Articles, Users, Admin::Dashboard"
      when "job"        then "e.g. ProcessPayment, SendNewsletter"
      when "mailer"     then "e.g. UserMailer, OrderNotification"
      when "channel"    then "e.g. Chat, Notifications"
      when "stimulus"   then "e.g. toggle, dropdown, search"
      else "Enter a name"
      end
    end

    # ─── Fields step (model/scaffold/migration) ────────

    def handle_fields_key(key)
      if @editing_field_name
        handle_field_name_key(key)
      else
        handle_field_type_key(key)
      end
    end

    def handle_field_name_key(key)
      case key
      when :escape
        if @field_name_input.empty?
          @step = :name
        else
          @field_name_input = +""
        end
      when :enter, :tab
        if @field_name_input.strip.empty?
          # No field name entered — move to review (fields optional for migrations)
          if @fields.any? || @gen_type == "migration"
            @step = :review
          else
            @error = "Add at least one field, or press Esc to go back"
          end
        else
          @editing_field_name = false
          @type_cursor = 0
        end
      when :backspace
        if @field_name_input.empty? && @fields.any?
          @fields.pop
        else
          @field_name_input.chop!
        end
      else
        @field_name_input << key.to_s if key.is_a?(String) && key.length == 1
      end
      nil
    end

    def handle_field_type_key(key)
      case key
      when :escape, :backspace
        @editing_field_name = true
      when "j", :down
        @type_cursor = (@type_cursor + 1) % COLUMN_TYPES.size
      when "k", :up
        @type_cursor = (@type_cursor - 1) % COLUMN_TYPES.size
      when :enter
        @fields << { name: @field_name_input.strip, type: COLUMN_TYPES[@type_cursor] }
        @field_name_input = +""
        @editing_field_name = true
      end
      nil
    end

    def render_fields_step
      lines = []
      lines << "Add fields to #{@name}:"
      lines << ""

      # Show existing fields
      if @fields.any?
        @fields.each_with_index do |f, _i|
          marker = Chamomile::Style.new.foreground("#a3be8c").render("\u2713")
          lines << "  #{marker} #{f[:name]}:#{f[:type]}"
        end
        lines << ""
      end

      if @editing_field_name
        lines << "Field name: #{@field_name_input}\u2588"
        lines << ""
        hint = if @fields.empty?
                 "Type a field name, then press Enter to pick its type"
               else
                 "Type a field name, Enter to pick type, Enter with empty to finish"
               end
        lines << Chamomile::Style.new.foreground("#666666").render(hint)
        lines << Chamomile::Style.new.foreground("#666666").render("Backspace with empty input to remove last field") if @fields.any?
      else
        lines << "Pick type for '#{@field_name_input}':"
        lines << ""
        COLUMN_TYPES.each_with_index do |t, i|
          lines << if i == @type_cursor
                     ViewHelpers.selected_style.render("  #{t}  ")
                   else
                     "  #{t}"
                   end
        end
      end

      if @error
        lines << ""
        lines << Chamomile::Style.new.foreground("#ff6347").render(@error)
      end

      lines.join("\n")
    end

    # ─── Actions step (controller) ─────────────────────

    def handle_actions_key(key)
      case key
      when :escape
        @step = :name
      when :enter
        @step = :review
      when "j", :down
        @action_cursor = (@action_cursor + 1) % CONTROLLER_ACTIONS.size
      when "k", :up
        @action_cursor = (@action_cursor - 1) % CONTROLLER_ACTIONS.size
      when " "
        action = CONTROLLER_ACTIONS[@action_cursor]
        @action_toggles[action] = !@action_toggles[action]
      when "a"
        # Toggle all
        all_on = CONTROLLER_ACTIONS.all? { |a| @action_toggles[a] }
        CONTROLLER_ACTIONS.each { |a| @action_toggles[a] = !all_on }
      end
      nil
    end

    def render_actions_step
      lines = []
      lines << "Select actions for #{@name}Controller:"
      lines << ""

      CONTROLLER_ACTIONS.each_with_index do |action, i|
        checked = @action_toggles[action]
        marker = checked ? Chamomile::Style.new.foreground("#a3be8c").render("[x]") : "[ ]"
        text = "#{marker} #{action}"
        lines << if i == @action_cursor
                   ViewHelpers.selected_style.render("  #{Chamomile::ANSI.strip(text)}  ")
                 else
                   "  #{text}"
                 end
      end

      lines << ""
      lines << Chamomile::Style.new.foreground("#666666").render("Space toggle | a toggle all | Enter continue")

      lines.join("\n")
    end

    # ─── Methods step (mailer) ─────────────────────────

    def handle_methods_key(key)
      case key
      when :escape
        if @method_input.empty?
          @step = :name
        else
          @method_input = +""
        end
      when :enter
        if @method_input.strip.empty?
          if @methods.any?
            @step = :review
          else
            @error = "Add at least one method, or press Esc to go back"
          end
        else
          @methods << @method_input.strip
          @method_input = +""
        end
      when :backspace
        if @method_input.empty? && @methods.any?
          @methods.pop
        else
          @method_input.chop!
        end
      else
        @method_input << key.to_s if key.is_a?(String) && key.length == 1
      end
      nil
    end

    def render_methods_step
      lines = []
      lines << "Add methods to #{@name}:"
      lines << ""

      if @methods.any?
        @methods.each do |m|
          marker = Chamomile::Style.new.foreground("#a3be8c").render("\u2713")
          lines << "  #{marker} #{m}"
        end
        lines << ""
      end

      lines << "Method name: #{@method_input}\u2588"
      lines << ""
      hint = @methods.empty? ? "Type a method name and press Enter" : "Enter another method, or Enter with empty to finish"
      lines << Chamomile::Style.new.foreground("#666666").render(hint)
      lines << Chamomile::Style.new.foreground("#666666").render("Backspace with empty input to remove last method") if @methods.any?

      if @error
        lines << ""
        lines << Chamomile::Style.new.foreground("#ff6347").render(@error)
      end

      lines.join("\n")
    end

    # ─── Review step ───────────────────────────────────

    def handle_review_key(key)
      case key
      when :escape
        # Go back to previous step
        steps = step_names
        idx = steps.index(:review) || 0
        @step = idx.positive? ? steps[idx - 1] : :name
        @editing_field_name = true if @step == :fields
        nil
      when :enter
        hide
        { action: :run, command: build_command }
      end
    end

    def render_review_step
      cmd = build_command
      cmd_str = cmd.join(" ")

      lines = []
      lines << Chamomile::Style.new.foreground("#a3be8c").bold.render("Ready to generate!")
      lines << ""

      lines << "Command:"
      lines << Chamomile::Style.new.bold.render("  $ #{cmd_str}")
      lines << ""

      # Summary
      case @gen_type
      when "model", "scaffold"
        lines << "Name: #{@name}"
        if @fields.any?
          lines << "Fields:"
          @fields.each { |f| lines << "  - #{f[:name]} (#{f[:type]})" }
        end
      when "migration"
        lines << "Migration: #{@name}"
        if @fields.any?
          lines << "Columns:"
          @fields.each { |f| lines << "  - #{f[:name]} (#{f[:type]})" }
        end
      when "controller"
        lines << "Controller: #{@name}"
        selected = CONTROLLER_ACTIONS.select { |a| @action_toggles[a] }
        lines << "Actions: #{selected.join(', ')}" if selected.any?
      when "mailer"
        lines << "Mailer: #{@name}"
        lines << "Methods: #{@methods.join(', ')}" if @methods.any?
      else
        lines << "Name: #{@name}"
      end

      lines.join("\n")
    end

    def build_command
      cmd = %W[bin/rails generate #{@gen_type} #{@name.strip}]

      case @gen_type
      when "model", "scaffold", "migration"
        @fields.each { |f| cmd << "#{f[:name]}:#{f[:type]}" }
      when "controller"
        CONTROLLER_ACTIONS.each { |a| cmd << a if @action_toggles[a] }
      when "mailer"
        @methods.each { |m| cmd << m }
      end

      cmd
    end

    # ─── Footer ────────────────────────────────────────

    def render_footer
      case @step
      when :name
        "Enter continue | Esc cancel"
      when :fields
        if @editing_field_name
          "Enter pick type | Esc back"
        else
          "j/k navigate | Enter select | Esc back"
        end
      when :actions
        "Space toggle | a all | Enter continue | Esc back"
      when :methods
        "Enter add/continue | Esc back"
      when :review
        "Enter run | Esc go back"
      end
    end
  end
end
