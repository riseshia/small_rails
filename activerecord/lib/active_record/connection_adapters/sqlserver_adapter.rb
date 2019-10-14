require 'active_record/connection_adapters/abstract_adapter'

# sqlserver_adapter.rb -- ActiveRecord adapter for Microsoft SQL Server
#
# Author: Joey Gibson <joey@joeygibson.com>
# Date:   10/14/2004
#
# REQUIREMENTS:
#
# This adapter will ONLY work on Windows systems, since it relies on Win32OLE, which,
# to my knowledge, is only available on Window.
#
# It relies on the ADO support in the DBI module. If you are using the
# one-click installer of Ruby, then you already have DBI installed, but
# the ADO module is *NOT* installed. You will need to get the latest
# source distribution of Ruby-DBI from http://ruby-dbi.sourceforge.net/
# unzip it, and copy the file src/lib/dbd_ado/ADO.rb to
# X:/Ruby/lib/ruby/site_ruby/1.8/DBD/ADO/ADO.rb (you will need to create
# the ADO directory). Once you've installed that file, you are ready to go.
#
# This module uses the ADO-style DSNs for connection. For example:
# "DBI:ADO:Provider=SQLOLEDB;Data Source=(local);Initial Catalog=test;User Id=sa;Password=password;"
# with User Id replaced with your proper login, and Password with your
# password.
#
# I have tested this code on a WindowsXP Pro SP1 system,
# ruby 1.8.2 (2004-07-29) [i386-mswin32], SQL Server 2000.
#
module ActiveRecord
  class Base
    def self.sqlserver_connection(config)
      require_library_or_gem 'dbi' unless self.class.const_defined?(:DBI)
      class_eval { include ActiveRecord::SQLServerBaseExtensions }

      symbolize_strings_in_hash(config)

      if config.has_key? :dsn
        dsn = config[:dsn]
      else
        raise ArgumentError, "No DSN specified"
      end

      conn = DBI.connect(dsn)
      conn["AutoCommit"] = true

      ConnectionAdapters::SQLServerAdapter.new(conn, logger)
    end
  end

  module SQLServerBaseExtensions #:nodoc:
    def self.append_features(base)
      super
      base.extend(ClassMethods)
    end

    module ClassMethods
      def find_first(conditions = nil, orderings = nil)
        sql  = "SELECT TOP 1 * FROM #{table_name} "
        add_conditions!(sql, conditions)
        sql << "ORDER BY #{orderings} " unless orderings.nil?

        record = connection.select_one(sql, "#{name} Load First")
        instantiate(record) unless record.nil?
      end

      def find_all(conditions = nil, orderings = nil, limit = nil, joins = nil)
        sql  = "SELECT "
        sql << "TOP #{limit} " unless limit.nil?
        sql << " * FROM #{table_name} " 
        sql << "#{joins} " if joins
        add_conditions!(sql, conditions)
        sql << "ORDER BY #{orderings} " unless orderings.nil?

        find_by_sql(sql)
      end
    end

    def attributes_with_quotes
      columns_hash = self.class.columns_hash

      attrs = @attributes.dup

      attrs = attrs.reject do |name, value|
        columns_hash[name].identity
      end

      attrs.inject({}) do |attrs_quoted, pair|
        attrs_quoted[pair.first] = quote(pair.last, columns_hash[pair.first])
        attrs_quoted
      end
    end
  end

  module ConnectionAdapters
    class ColumnWithIdentity < Column
      attr_reader :identity

      def initialize(name, default, sql_type = nil, is_identity = false)
        super(name, default, sql_type)

        @identity = is_identity
      end
    end

    class SQLServerAdapter < AbstractAdapter # :nodoc:
      def quote_column_name(name)
        " [#{name}] "
      end

      def select_all(sql, name = nil)
        select(sql, name)
      end

      def select_one(sql, name = nil)
        result = select(sql, name)
        result.nil? ? nil : result.first
      end

      def columns(table_name, name = nil)
        sql = <<EOL
SELECT s.name AS TableName, c.id AS ColId, c.name AS ColName, t.name AS ColType, c.length AS Length,
c.AutoVal AS IsIdentity,
c.cdefault AS DefaultId, com.text AS DefaultValue
FROM syscolumns AS c
JOIN systypes AS t ON (c.xtype = t.xtype AND c.usertype = t.usertype)
JOIN sysobjects AS s ON (c.id = s.id)
LEFT OUTER JOIN syscomments AS com ON (c.cdefault = com.id)
WHERE s.name = '#{table_name}'
EOL

        columns = []

        log(sql, name, @connection) do |conn|
          conn.select_all(sql) do |row|
            default_value = row[:DefaultValue]

            if default_value =~ /null/i
              default_value = nil
            else
              default_value =~ /\(([^)]+)\)/
              default_value = $1
            end

            col = ColumnWithIdentity.new(row[:ColName], default_value, "#{row[:ColType]}(#{row[:Length]})", row[:IsIdentity] != nil)

            columns << col
          end
        end

        columns
      end

      def insert(sql, name = nil, pk = nil, id_value = nil)
        begin
          table_name = get_table_name(sql)

          col = get_identity_column(table_name)

          ii_enabled = false

          if col != nil
            if query_contains_identity_column(sql, col)
              begin
                execute enable_identity_insert(table_name, true)
                ii_enabled = true
              rescue Exception => e
                # Coulnd't turn on IDENTITY_INSERT
              end
            end
          end

          log(sql, name, @connection) do |conn|
            conn.execute(sql)

            select_one("SELECT @@IDENTITY AS Ident")["Ident"]
          end
        ensure
          if ii_enabled
            begin
              execute enable_identity_insert(table_name, false)

            rescue Exception => e
              # Couldn't turn off IDENTITY_INSERT
            end
          end
        end
      end

      def execute(sql, name = nil)
        if sql =~ /^INSERT/i
          insert(sql, name)
        else
          log(sql, name, @connection) do |conn|
            conn.execute(sql)
          end
        end
      end

      alias_method :update, :execute
      alias_method :delete, :execute

      def begin_db_transaction
        begin
          @connection["AutoCommit"] = false
        rescue Exception => e
          @connection["AutoCommit"] = true
        end
      end

      def commit_db_transaction
        begin
          @connection.commit
        ensure
          @connection["AutoCommit"] = true
        end
      end

      def rollback_db_transaction
        begin
          @connection.rollback
        ensure
          @connection["AutoCommit"] = true
        end
      end

      def recreate_database(name)
        drop_database(name)
        create_database(name)
      end

      def drop_database(name)
        execute "DROP DATABASE #{name}"
      end

      def create_database(name)
        execute "CREATE DATABASE #{name}"
      end

      private
      def select(sql, name = nil)
        rows = []

        log(sql, name, @connection) do |conn|
          conn.select_all(sql) do |row|
            record = {}

            row.column_names.each do |col|
              record[col] = row[col]
            end

            rows << record
          end
        end

        rows
      end

      def enable_identity_insert(table_name, enable = true)
        if has_identity_column(table_name)
          "SET IDENTITY_INSERT #{table_name} #{enable ? 'ON' : 'OFF'}"
        end
      end

      def get_table_name(sql)
        if sql =~ /into\s*([^\s]+)\s*/i or
            sql =~ /update\s*([^\s]+)\s*/i
          $1
        else
          nil
        end
      end

      def has_identity_column(table_name)
        return get_identity_column(table_name) != nil
      end

      def get_identity_column(table_name)
        if not @table_columns
          @table_columns = {}
        end

        if @table_columns[table_name] == nil
          @table_columns[table_name] = columns(table_name)
        end

        @table_columns[table_name].each do |col|
          return col.name if col.identity
        end

        return nil
      end

      def query_contains_identity_column(sql, col)
        return sql =~ /[\(\.\,]\s*#{col}/
      end
    end
  end
end
