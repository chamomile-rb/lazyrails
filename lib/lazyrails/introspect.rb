# frozen_string_literal: true

module LazyRails
  class Introspect
    IntrospectData = Data.define(:routes, :tables, :migrations, :models, :connection, :about, :stats, :notes,
                                 :rake_tasks, :error)

    RUNNER_SCRIPT = File.expand_path("introspect_runner.rb", __dir__)

    def self.load(json_string)
      data = JSON.parse(json_string, symbolize_names: true)

      routes = (data[:routes] || []).map do |r|
        Route.new(
          verb: r[:verb].to_s,
          path: r[:path].to_s,
          action: r[:action].to_s,
          name: r[:name].to_s,
          engine: !r[:engine].nil?
        )
      end

      # symbolize_names turns JSON keys into symbols, so tables hash has symbol keys.
      # Convert to string keys for consistent lookup by table_name (which is a string).
      tables = (data[:tables] || {}).transform_keys(&:to_s).transform_values do |cols|
        cols.map do |c|
          Column.new(
            name: c[:name].to_s,
            type: c[:type]&.to_sym,
            null: c[:null] != false,
            default: c[:default],
            limit: c[:limit]
          )
        end
      end

      migrations = (data[:migrations] || []).map do |m|
        Migration.new(
          status: m[:status].to_s,
          version: m[:version].to_s,
          name: m[:name].to_s,
          file_path: m[:filename],
          database: m[:database]&.to_s || "primary"
        )
      end

      models = (data[:models] || []).map do |m|
        if m[:error]
          ModelInfo.new(name: m[:name].to_s, error: m[:error].to_s)
        else
          assocs = (m[:associations] || []).map do |a|
            Association.new(
              macro: a[:macro]&.to_sym || :unknown,
              name: a[:name]&.to_sym || :unknown,
              class_name: a[:class_name].to_s
            )
          end

          valids = (m[:validations] || []).map do |v|
            Validation.new(
              kind: v[:kind]&.to_sym || :unknown,
              attributes: (v[:attributes] || []).map(&:to_sym),
              options: v[:options].is_a?(Hash) ? v[:options] : {}
            )
          end

          table_name = m[:table].to_s
          columns = tables[table_name] || []

          ModelInfo.new(
            name: m[:name].to_s,
            table_name: table_name,
            columns: columns,
            associations: assocs,
            validations: valids
          )
        end
      end

      conn = data[:connection] || {}
      connection = {
        adapter: conn[:adapter],
        database: conn[:database],
        tables_count: conn[:tables_count]
      }

      # Parse about data (already a simple hash from the runner)
      about = (data[:about] || {}).transform_keys(&:to_s)

      # Parse stats from raw output using existing parser
      stats_raw = data[:stats_raw].to_s
      stats = stats_raw.empty? ? { rows: [], summary: {} } : Parsers::RailsStats.parse(stats_raw)

      # Parse notes (already structured from the runner)
      notes = (data[:notes] || []).map do |n|
        Note.new(
          file: n[:file].to_s,
          line: n[:line].to_i,
          tag: n[:tag].to_s,
          message: n[:message].to_s
        )
      end

      rake_tasks = (data[:rake_tasks] || []).map do |t|
        RakeTask.new(
          name: t[:name].to_s,
          description: t[:description].to_s,
          source: t[:source].to_s
        )
      end

      IntrospectData.new(
        routes: routes,
        tables: tables,
        migrations: migrations,
        models: models,
        connection: connection,
        about: about,
        stats: stats,
        notes: notes,
        rake_tasks: rake_tasks,
        error: data[:error]
      )
    rescue JSON::ParserError, TypeError, NoMethodError => e
      IntrospectData.new(routes: [], tables: {}, migrations: [], models: [], connection: {},
                         about: {}, stats: { rows: [], summary: {} }, notes: [], rake_tasks: [], error: e.message)
    end
  end
end
