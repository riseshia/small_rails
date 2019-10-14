module ActiveRecord
  module Associations
    class HasAndBelongsToManyAssociation < AssociationCollection #:nodoc:
      def initialize(owner, association_name, association_class_name, association_class_primary_key_name, join_table, options)
        super(owner, association_name, association_class_name, association_class_primary_key_name, options)

        @association_foreign_key = options[:association_foreign_key] || Inflector.underscore(Inflector.demodulize(association_class_name.downcase)) + "_id"
        association_table_name = options[:table_name] || @association_class.table_name(association_class_name)
        @join_table = join_table
        @order = options[:order] || "t.#{@owner.class.primary_key}"

        interpolate_sql_options!(options, :finder_sql, :delete_sql)
        @finder_sql = options[:finder_sql] ||
              "SELECT t.*, j.* FROM #{association_table_name} t, #{@join_table} j " +
              "WHERE t.#{@owner.class.primary_key} = j.#{@association_foreign_key} AND " +
              "j.#{association_class_primary_key_name} = '#{@owner.id}' " +
              (options[:conditions] ? " AND " + options[:conditions] : "") + " " +
              "ORDER BY #{@order}"
      end

      # Removes all records from this association.  Returns +self+ so method calls may be chained.
      def clear
        return self if size == 0 # forces load_collection if hasn't happened already

        if sql = @options[:delete_sql]
          each { |record| @owner.connection.execute(sql) }
        elsif @options[:conditions]
          sql =
            "DELETE FROM #{@join_table} WHERE #{@association_class_primary_key_name} = '#{@owner.id}' " +
            "AND #{@association_foreign_key} IN (#{collect { |record| record.id }.join(", ")})"
          @owner.connection.execute(sql)
        else
          sql = "DELETE FROM #{@join_table} WHERE #{@association_class_primary_key_name} = '#{@owner.id}'"
          @owner.connection.execute(sql)
        end

        @collection = []
        self
      end

      def find(association_id = nil, &block)
        if block_given? || @options[:finder_sql]
          load_collection
          @collection.find(&block)
        else
          if loaded?
            find_all { |record| record.id == association_id.to_i }.first
          else
            find_all_records(@finder_sql.sub(/ORDER BY/, "AND j.#{@association_foreign_key} = '#{association_id}' ORDER BY")).first
          end
        end
      end

      def push_with_attributes(record, join_attributes = {})
        raise_on_type_mismatch(record)
        insert_record_with_join_attributes(record, join_attributes)
        join_attributes.each { |key, value| record.send(:write_attribute, key, value) }
        @collection << record if loaded?
        self
      end

      alias :concat_with_attributes :push_with_attributes

      def size
        @options[:uniq] ? count_records : super
      end

      protected
        def find_all_records(sql = @finder_sql)
          records = @association_class.find_by_sql(sql)
          @options[:uniq] ? uniq(records) : records
        end

        def count_records
          load_collection
          @collection.size
        end

        def insert_record(record)
          if @options[:insert_sql]
            @owner.connection.execute(interpolate_sql(@options[:insert_sql], record))
          else
            sql = "INSERT INTO #{@join_table} (#{@association_class_primary_key_name}, #{@association_foreign_key}) VALUES ('#{@owner.id}','#{record.id}')"
            @owner.connection.execute(sql)
          end
        end

        def insert_record_with_join_attributes(record, join_attributes)
          attributes = { @association_class_primary_key_name => @owner.id, @association_foreign_key => record.id }.update(join_attributes)
          sql =
            "INSERT INTO #{@join_table} (#{@owner.send(:quoted_column_names, attributes).join(', ')}) " +
            "VALUES (#{attributes.values.collect { |value| @owner.send(:quote, value) }.join(', ')})"
          @owner.connection.execute(sql)
        end

        def delete_records(records)
          if sql = @options[:delete_sql]
            records.each { |record| @owner.connection.execute(sql) }
          else
            ids = quoted_record_ids(records)
            sql = "DELETE FROM #{@join_table} WHERE #{@association_class_primary_key_name} = '#{@owner.id}' AND #{@association_foreign_key} IN (#{ids})"
            @owner.connection.execute(sql)
          end
        end
      end
  end
end
