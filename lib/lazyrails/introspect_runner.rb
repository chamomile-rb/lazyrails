# frozen_string_literal: true

# This script is executed via: bin/rails runner lib/lazyrails/introspect_runner.rb
# It dumps all introspectable data as one JSON blob to stdout.

require "json"

data = {}

begin
  data[:routes] = Rails.application.routes.routes.filter_map do |route|
    w = ActionDispatch::Routing::RouteWrapper.new(route)
    next if w.internal?
    { verb: w.verb, path: w.path, action: w.endpoint, name: w.name, engine: w.engine? }
  end
rescue => e
  data[:routes_error] = e.message
  data[:routes] = []
end

begin
  conn = ActiveRecord::Base.connection
  table_names = conn.tables.sort

  data[:tables] = table_names.to_h do |table|
    cols = conn.columns(table).map do |c|
      { name: c.name, type: c.type, null: c.null, default: c.default, limit: c.limit }
    end
    [table, cols]
  end

  data[:connection] = {
    adapter: conn.adapter_name,
    database: conn.current_database,
    tables_count: table_names.size
  }
rescue ActiveRecord::NoDatabaseError => e
  data[:tables] = {}
  data[:connection] = {}
  data[:migrations_error] = "no_database"
rescue => e
  data[:tables] = {}
  data[:connection] = {}
  data[:tables_error] = e.message
end

begin
  # Rails 7.2+ changed the SchemaMigration API
  applied = if ActiveRecord::SchemaMigration.respond_to?(:all_versions)
    ActiveRecord::SchemaMigration.all_versions
  elsif ActiveRecord::Base.connection.respond_to?(:schema_migration)
    ActiveRecord::Base.connection.schema_migration.versions
  else
    ActiveRecord::SchemaMigration.new(ActiveRecord::Base.connection_pool).versions
  end

  # Rails 7.2+ migration context API
  migration_paths = if ActiveRecord::Migrator.respond_to?(:migrations_paths)
    ActiveRecord::Migrator.migrations_paths
  elsif ActiveRecord::Base.connection.respond_to?(:migration_context)
    ActiveRecord::Base.connection.migration_context.migrations_paths
  else
    ["db/migrate"]
  end

  context = ActiveRecord::MigrationContext.new(migration_paths)
  data[:migrations] = context.migrations.map do |m|
    {
      status: applied.include?(m.version.to_s) ? "up" : "down",
      version: m.version,
      name: m.name,
      filename: m.filename
    }
  end
rescue => e
  data[:migrations_error] = e.message
  data[:migrations] = []
end

begin
  Rails.application.eager_load!
  data[:models] = ActiveRecord::Base.descendants.filter_map do |model|
    next if model.abstract_class?

    begin
      next unless model.table_exists?
    rescue
      next
    end

    assocs = model.reflect_on_all_associations.map do |a|
      { macro: a.macro, name: a.name, class_name: a.class_name }
    end

    valids = model.validators.map do |v|
      { kind: v.kind, attributes: v.attributes, options: v.options.except(:if, :unless) }
    end

    { name: model.name, table: model.table_name, associations: assocs, validations: valids }
  rescue => e
    { name: model.name, error: e.message }
  end
rescue => e
  data[:models_error] = e.message
  data[:models] = []
end

# ─── About / Stats / Notes ─────────────────────────────
# Gathered here to avoid 3 extra Rails boot cycles.

begin
  about = {}
  about["Ruby version"] = "#{RUBY_VERSION} (#{RUBY_PLATFORM})"
  about["Rails version"] = Rails::VERSION::STRING
  about["Environment"] = Rails.env
  about["Database adapter"] = ActiveRecord::Base.connection_db_config.adapter rescue nil
  about["Database"] = ActiveRecord::Base.connection_db_config.database rescue nil
  data[:about] = about
rescue => e
  data[:about_error] = e.message
  data[:about] = {}
end

begin
  # Replicate `rails stats` output by reading the CodeStatistics
  # We output the raw text so the existing parser can handle it
  stats_directories = []

  {
    "Controllers" => "app/controllers",
    "Helpers" => "app/helpers",
    "Jobs" => "app/jobs",
    "Models" => "app/models",
    "Mailers" => "app/mailers",
    "Channels" => "app/channels",
    "Views" => "app/views",
    "JavaScripts" => "app/javascript",
    "Libraries" => "lib"
  }.each do |name, dir|
    full = Rails.root.join(dir)
    stats_directories << [name, full.to_s] if full.directory?
  end

  {
    "Controller tests" => "test/controllers",
    "Helper tests" => "test/helpers",
    "Model tests" => "test/models",
    "Mailer tests" => "test/mailers",
    "Job tests" => "test/jobs",
    "Integration tests" => "test/integration",
    "System tests" => "test/system"
  }.each do |name, dir|
    full = Rails.root.join(dir)
    stats_directories << [name, full.to_s, true] if full.directory?
  end

  if Rails.root.join("spec").directory?
    stats_directories << ["RSpec specs", Rails.root.join("spec").to_s, true]
  end

  if stats_directories.any?
    cs = CodeStatistics.new(*stats_directories)
    stats_output = StringIO.new
    begin
      $stdout = stats_output
      cs.to_s
    ensure
      $stdout = STDOUT
    end
    data[:stats_raw] = stats_output.string
  else
    data[:stats_raw] = ""
  end
rescue => e
  data[:stats_error] = e.message
  data[:stats_raw] = ""
end

begin
  annotations = Rails::SourceAnnotationExtractor.enumerate("OPTIMIZE|FIXME|TODO", tag: true)
  notes = []
  annotations.each do |file, entries|
    entries.each do |entry|
      notes << { file: file, line: entry.line, tag: entry.tag, message: entry.text }
    end
  end
  data[:notes] = notes
rescue => e
  data[:notes_error] = e.message
  data[:notes] = []
end

begin
  Rails.application.load_tasks
  data[:rake_tasks] = Rake.application.tasks.map do |t|
    {
      name: t.name,
      description: t.comment,
      source: t.locations&.first
    }
  end
rescue => e
  data[:rake_tasks] = []
  data[:rake_tasks_error] = e.message
end

puts JSON.generate(data)
