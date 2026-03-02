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

puts JSON.generate(data)
