# frozen_string_literal: true

# This script is executed via: bin/rails runner lib/lazyrails/table_query_runner.rb table_name [query_json]
# It dumps rows from the given table as JSON to stdout.
#
# Note: WHERE and ORDER BY clauses are passed through as raw SQL. This is intentional —
# lazyrails is a dev tool and the user already has full shell/console access.

require "json"

table = ARGV[0]
query_json = ARGV[1]

begin
  conn = ActiveRecord::Base.connection
  quoted_table = conn.quote_table_name(table)

  # Parse optional query params
  params = query_json ? JSON.parse(query_json) : {}
  where_clause = params["where"]
  order_clause = params["order"]
  limit = (params["limit"] || 100).to_i
  offset = (params["offset"] || 0).to_i

  # Build COUNT query
  count_sql = "SELECT COUNT(*) AS cnt FROM #{quoted_table}"
  count_sql += " WHERE #{where_clause}" if where_clause && !where_clause.strip.empty?
  total = conn.select_value(count_sql).to_i

  # Build data query
  sql = "SELECT * FROM #{quoted_table}"
  sql += " WHERE #{where_clause}" if where_clause && !where_clause.strip.empty?
  sql += " ORDER BY #{order_clause}" if order_clause && !order_clause.strip.empty?
  sql += " LIMIT #{limit}"
  sql += " OFFSET #{offset}" if offset.positive?

  result = conn.exec_query(sql)
  puts JSON.generate({ columns: result.columns, rows: result.rows, total: total })
rescue StandardError => e
  puts JSON.generate({ columns: [], rows: [], total: 0, error: e.message })
end
