module ActiveRecord
  module Calculations
    module ClassMethods

      def construct_calculation_sql(operation, column_name, options) #:nodoc:
        operation = operation.to_s.downcase
        options = options.symbolize_keys

        scope           = scope(:find)
        merged_includes = merge_includes(scope ? scope[:include] : [], options[:include])
        aggregate_alias = column_alias_for(operation, column_name)
        column_name     = "#{connection.quote_table_name(table_name)}.#{column_name}" if column_names.include?(column_name.to_s)

        if operation == 'count'
          if merged_includes.any?
            options[:distinct] = true
            column_name = options[:select] || [connection.quote_table_name(table_name), primary_key] * '.'
          end

          if options[:distinct]
            use_workaround = !connection.supports_count_distinct?
          end
        end

        if options[:distinct] && column_name.to_s !~ /\s*DISTINCT\s+/i
          distinct = 'DISTINCT '
        end
        sql = "SELECT #{operation}(#{distinct}#{column_name}) AS #{aggregate_alias}"

        # A (slower) workaround if we're using a backend, like sqlite, that doesn't support COUNT DISTINCT.
        sql = "SELECT COUNT(*) AS #{aggregate_alias}" if use_workaround

        sql << ", #{options[:group_field]} AS #{options[:group_alias]}" if options[:group]
        if options[:from]
          sql << " FROM #{options[:from]} "
        elsif scope && scope[:from] && !use_workaround
          sql << " FROM #{scope[:from]} "
        else
          sql << " FROM (SELECT #{distinct}#{column_name}" if use_workaround
          sql << " FROM #{connection.quote_table_name(table_name)} "
        end

        joins = ""
        add_joins!(joins, options[:joins], scope, :joins)
        add_joins!(joins, options[:outer_joins], scope, :outer_joins)

        if merged_includes.any?
          join_dependency = ActiveRecord::Associations::ClassMethods::JoinDependency.new(self, merged_includes, joins)
          sql << join_dependency.join_associations.collect{|join| join.association_join }.join
        end

        sql << joins unless joins.blank?

        add_conditions!(sql, options[:conditions], scope)
        add_limited_ids_condition!(sql, options, join_dependency) if join_dependency && !using_limitable_reflections?(join_dependency.reflections) && ((scope && scope[:limit]) || options[:limit])

        if options[:group]
          group_key = connection.adapter_name == 'FrontBase' ?  :group_alias : :group_field
          sql << " GROUP BY #{options[group_key]} "
        end

        if options[:group] && options[:having]
          having = sanitize_sql_for_conditions(options[:having])

          # FrontBase requires identifiers in the HAVING clause and chokes on function calls
          if connection.adapter_name == 'FrontBase'
            having.downcase!
            having.gsub!(/#{operation}\s*\(\s*#{column_name}\s*\)/, aggregate_alias)
          end

          sql << " HAVING #{having} "
        end

        sql << " ORDER BY #{options[:order]} "       if options[:order]
        add_limit!(sql, options, scope)
        sql << ") #{aggregate_alias}_subquery" if use_workaround
        sql
      end
    end
  end
end
