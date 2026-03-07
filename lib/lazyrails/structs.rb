# frozen_string_literal: true

module LazyRails
  Route = Data.define(:verb, :path, :action, :name, :engine) do
    def to_s
      "#{verb.ljust(7)} #{path.ljust(40)} #{action}"
    end
  end

  Migration = Data.define(:status, :version, :name, :file_path, :database) do
    def up? = status == "up"
    def down? = status == "down"

    def to_s
      arrow = up? ? "\u2191" : "\u2193"
      "#{arrow} #{version}  #{name}"
    end
  end

  Column = Data.define(:name, :type, :null, :default, :limit) do
    def to_s
      parts = [name.ljust(20), type.to_s.ljust(12)]
      parts << "NOT NULL" unless null
      parts << "default: #{default.inspect}" unless default.nil?
      parts << "limit: #{limit}" if limit
      parts.join("  ")
    end
  end

  ModelInfo = Data.define(:name, :file_path, :table_name, :columns, :associations, :validations, :error) do
    def initialize(name:, file_path: nil, table_name: nil, columns: [], associations: [], validations: [], error: nil)
      super
    end

    def to_s
      col_count = columns.size
      "#{name} (#{col_count} cols)"
    end
  end

  Association = Data.define(:macro, :name, :class_name) do
    def to_s
      "#{macro} :#{name}"
    end
  end

  Validation = Data.define(:kind, :attributes, :options) do
    def to_s
      attrs = attributes.map { |a| ":#{a}" }.join(", ")
      opts = options.empty? ? "" : ", #{options.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')}"
      "validates #{attrs}, #{kind}: true#{opts}"
    end
  end

  GemEntry = Data.define(:name, :version, :groups) do
    def to_s
      "#{name} (#{version})"
    end
  end

  TestFile = Data.define(:path, :status, :last_output) do
    def initialize(path:, status: :not_run, last_output: nil)
      super
    end

    def to_s
      icon = case status
             when :passed then "\u2713"
             when :failed then "\u2717"
             else " "
             end
      "#{icon} #{path}"
    end
  end

  TestResult = Data.define(:file, :passed, :failed, :errors, :output)

  StatRow = Data.define(:name, :lines, :loc, :classes, :methods) do
    def to_s
      "#{name.ljust(25)} #{lines.to_s.rjust(6)}  #{loc.to_s.rjust(6)}  #{classes.to_s.rjust(4)}  #{methods.to_s.rjust(4)}"
    end
  end

  Note = Data.define(:file, :line, :tag, :message) do
    def to_s
      "[#{tag}] #{file}:#{line} — #{message}"
    end
  end

  CommandEntry = Data.define(:command, :exit_code, :duration_ms, :timestamp, :stdout, :stderr,
                             :annotation, :undo_command) do
    def initialize(annotation: nil, undo_command: nil, **kwargs)
      super
    end

    def success? = exit_code.zero?

    def to_s
      icon = success? ? "\u2713" : "\u2717"
      duration = format("%.1fs", duration_ms / 1000.0)
      "#{icon} #{command.ljust(50)} #{duration}"
    end
  end

  CredentialFile = Data.define(:environment, :path, :exists) do
    def to_s
      exists ? environment : "#{environment} (missing key)"
    end
  end

  MailerPreview = Data.define(:mailer_class, :method_name, :preview_path) do
    def to_s = "  #{method_name}"
    def display_name = "#{mailer_class}##{method_name}"
  end

  LogEntry = Data.define(:verb, :path, :status, :duration_ms, :sql_lines, :raw) do
    def to_s
      "#{verb&.ljust(6)} #{path&.ljust(30)} #{status}"
    end

    def slow? = sql_lines.any? { |s| s[:duration_ms].to_f > 100 }
  end

  RakeTask = Data.define(:name, :description, :source) do
    def to_s
      description.to_s.empty? ? name : "#{name.ljust(35)} #{description}"
    end
  end

  JobEntry = Data.define(:id, :fe_id, :class_name, :queue_name, :status, :priority,
                         :active_job_id, :arguments, :error_class, :error_message,
                         :backtrace, :worker_id, :started_at, :scheduled_at,
                         :finished_at, :failed_at, :concurrency_key, :expires_at,
                         :created_at) do
    def initialize(fe_id: nil, priority: nil, active_job_id: nil, error_class: nil,
                   error_message: nil, backtrace: nil, worker_id: nil, started_at: nil,
                   scheduled_at: nil, finished_at: nil, failed_at: nil,
                   concurrency_key: nil, expires_at: nil, created_at: nil, **kwargs)
      super
    end

    def to_s
      "#{class_name}  #{queue_name}  [#{status}]"
    end
  end

  PendingJobAction = Data.define(:action, :fe_id, :job_id) do
    def initialize(action:, fe_id: nil, job_id: nil)
      super
    end
  end

  # Messages for async data loading
  IntrospectLoadedMsg = Data.define(:data, :error)
  GemsLoadedMsg = Data.define(:gems, :error)
  TestsLoadedMsg = Data.define(:files, :error)
  CommandFinishedMsg = Data.define(:entry, :panel)
  TableRowsLoadedMsg = Data.define(:table, :columns, :rows, :total, :error)
  EvalFinishedMsg = Data.define(:entry)
  CredentialsLoadedMsg = Data.define(:environment, :content, :error)
  MailersLoadedMsg = Data.define(:previews, :error)
  MailerPreviewLoadedMsg = Data.define(:preview, :subject, :to, :from, :body, :error)
  JobsLoadedMsg = Data.define(:available, :jobs, :counts, :error)
  JobActionMsg = Data.define(:action, :job_id, :success, :error)
end
