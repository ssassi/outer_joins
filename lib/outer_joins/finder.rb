module ActiveRecord
  class Base
    class << self

      VALID_FIND_OPTIONS = [ :conditions, :include, :joins, :outer_joins, :limit, :offset,
                                 :order, :select, :readonly, :group, :having, :from, :lock ]

      def construct_finder_sql(options)
        scope = scope(:find)
        sql  = "SELECT #{options[:select] || (scope && scope[:select]) || default_select(options[:joins] || options[:outer_joins] || (scope && scope[:joins]) || (scope && scope[:outer_joins]))} "
        sql << "FROM #{options[:from]  || (scope && scope[:from]) || quoted_table_name} "

        add_joins!(sql, options[:joins], scope, :joins)
        add_joins!(sql, options[:outer_joins], scope, :outer_joins)

        add_conditions!(sql, options[:conditions], scope)

        add_group!(sql, options[:group], options[:having], scope)
        add_order!(sql, options[:order], scope)
        add_limit!(sql, options, scope)
        add_lock!(sql, options, scope)

        sql
      end

      def add_joins!(sql, joins, scope = :auto, type = :joins)
        scope = scope(:find) if :auto == scope
        merged_joins = scope && scope[type] && joins ? merge_joins(scope[type], joins) : (joins || scope && scope[type])

        merged_joins = safe_to_array(merged_joins)
        if type == :outer_joins && merged_joins && scope && scope[:joins]
          joins_scope = safe_to_array(scope[:joins])
          merged_joins.delete_if {|e|joins_scope.include?(e)}
        end
        case merged_joins
        when Symbol, Hash, Array
          if array_of_strings?(merged_joins)
            sql << merged_joins.join(' ') + " "
          else
            if type == :outer_joins
              join_dependency = ActiveRecord::Associations::ClassMethods::JoinDependency.new(self, merged_joins, nil)
            else
              join_dependency = ActiveRecord::Associations::ClassMethods::InnerJoinDependency.new(self, merged_joins, nil)
            end
            sql << " #{join_dependency.join_associations.collect { |assoc| assoc.association_join }.join} "
          end
        when String
          sql << " #{merged_joins} "
        end
      end

      def with_scope(method_scoping = {}, action = :merge, &block)
        method_scoping = method_scoping.method_scoping if method_scoping.respond_to?(:method_scoping)

        # Dup first and second level of hash (method and params).
        method_scoping = method_scoping.inject({}) do |hash, (method, params)|
          hash[method] = (params == true) ? params : params.dup
          hash
        end

        method_scoping.assert_valid_keys([ :find, :create ])

        if f = method_scoping[:find]
          f.assert_valid_keys(VALID_FIND_OPTIONS)
          set_readonly_option! f
        end

        # Merge scopings
        if [:merge, :reverse_merge].include?(action) && current_scoped_methods
          method_scoping = current_scoped_methods.inject(method_scoping) do |hash, (method, params)|
            case hash[method]
              when Hash
                if method == :find
                  (hash[method].keys + params.keys).uniq.each do |key|
                    merge = hash[method][key] && params[key] # merge if both scopes have the same key
                    if key == :conditions && merge
                      if params[key].is_a?(Hash) && hash[method][key].is_a?(Hash)
                        hash[method][key] = merge_conditions(hash[method][key].deep_merge(params[key]))
                      else
                        hash[method][key] = merge_conditions(params[key], hash[method][key])
                      end
                    elsif key == :include && merge
                      hash[method][key] = merge_includes(hash[method][key], params[key]).uniq
                    elsif key == :joins && merge
                      hash[method][key] = merge_joins(params[key], hash[method][key])
                    elsif key == :outer_joins && merge
                      hash[method][key] = merge_joins(params[key], hash[method][key])
                    else
                      hash[method][key] = hash[method][key] || params[key]
                    end
                  end
                else
                  if action == :reverse_merge
                    hash[method] = hash[method].merge(params)
                  else
                    hash[method] = params.merge(hash[method])
                  end
                end
              else
                hash[method] = params
            end
            hash
          end
        end

        self.scoped_methods << method_scoping
        begin
          yield
        ensure
          self.scoped_methods.pop
        end
      end
      
    end
  end
end
