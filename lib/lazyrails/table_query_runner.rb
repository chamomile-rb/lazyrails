# frozen_string_literal: true

# This script is executed via: bin/rails runner lib/lazyrails/table_query_runner.rb table_name
# It dumps rows from the given table as JSON to stdout.

require "json"

table = ARGV[0]

begin
  conn = ActiveRecord::Base.connection
  result = conn.exec_query("SELECT * FROM #{conn.quote_table_name(table)} LIMIT 100")
  puts JSON.generate({ columns: result.columns, rows: result.rows })
rescue => e
  puts JSON.generate({ columns: [], rows: [], error: e.message })
end
