module ActiveRecord
  module Associations
    module ClassMethods
      def construct_finder_sql_with_included_associations(options, join_dependency)
        scope = scope(:find)
        sql = "SELECT #{column_aliases(join_dependency)} FROM #{(scope && scope[:from]) || options[:from] || quoted_table_name} "
        sql << join_dependency.join_associations.collect{|join| join.association_join }.join

        #add_joins!(sql, options[:joins], scope, :joins)
        #add_joins!(sql, options[:outer_joins], scope, :outer_joins)

        add_conditions!(sql, options[:conditions], scope)
        add_limited_ids_condition!(sql, options, join_dependency) if !using_limitable_reflections?(join_dependency.reflections) && ((scope && scope[:limit]) || options[:limit])

        add_group!(sql, options[:group], options[:having], scope)
        add_order!(sql, options[:order], scope)
        add_limit!(sql, options, scope) if using_limitable_reflections?(join_dependency.reflections)
        add_lock!(sql, options, scope)

        return sanitize_sql(sql)
      end

      def joined_tables(options)
        scope = scope(:find)
        joins = options[:joins]
        merged_joins = scope && scope[:joins] && joins ? merge_joins(scope[:joins], joins) : (joins || scope && scope[:joins])

        outer_joins = options[:outer_joins]
        merged_outer_joins = scope && scope[:outer_joins] && outer_joins ? merge_joins(scope[:outer_joins], outer_joins) : (outer_joins || scope && scope[:outer_joins])
        merged_outer_joins = safe_to_array(merged_outer_joins)
        merged_joins = safe_to_array(merged_joins)
        merged_outer_joins.delete_if {|e|merged_joins.include?(e)}

        [table_name] + case merged_joins
        when Symbol, Hash, Array
          if array_of_strings?(merged_joins) && array_of_strings?(merged_outer_joins)
            tables_in_string((merged_joins + merged_outer_joins).join(' '))
          else
            join_dependency = ActiveRecord::Associations::ClassMethods::InnerJoinDependency.new(self, merged_joins, nil)
            outer_join_dependency = ActiveRecord::Associations::ClassMethods::JoinDependency.new(self, merged_outer_joins, nil)

            join_dependency.join_associations.collect {|join_association| [join_association.aliased_join_table_name, join_association.aliased_table_name]}.flatten.compact +
            outer_join_dependency.join_associations.collect {|join_association| [join_association.aliased_join_table_name, join_association.aliased_table_name]}.flatten.compact
          end
        else
          tables_in_string(merged_joins + merged_outer_joins)
        end
      end

      def find_with_associations(options = {})
        catch :invalid_query do
          join_dependency = JoinDependency.new(self, merge_includes(scope(:find, :include), options[:include]), safe_to_array(options[:joins]) + safe_to_array(options[:outer_joins]))
          rows = select_all_rows(options, join_dependency)
          return join_dependency.instantiate(rows)
        end
        []
      end

    end
  end
end