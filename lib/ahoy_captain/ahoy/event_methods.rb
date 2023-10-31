module AhoyCaptain
  module Ahoy
    module EventMethods
      extend ActiveSupport::Concern

      included do
        scope :page_view, -> { where("name = '#{AhoyCaptain.config.event[:view_name]}'") }

        ransacker :route do |_parent|
          Arel.sql(AhoyCaptain.config.event[:url_column])
        end

        ransacker :entry_page do |parent|
          Arel.sql("entry_pages.url")
        end

        ransacker :exit_page do |parent|
          Arel.sql("exit_pages.url")
        end

        scope :with_entry_pages, -> {
          with(
            entry_pages: self.select(
              "sub.min_created_at as min_id, 
               sub.id as entry_id, 
               #{Arel.sql("#{AhoyCaptain.config.event.url_column} AS url")}"
            )
            .from(
              self.select(
                "MIN(#{table_name}.created_at) as min_created_at, 
                 FIRST_VALUE(#{table_name}.id) OVER (PARTITION BY #{table_name}.properties ORDER BY #{table_name}.created_at ASC) as id"
              )
              .where(name: AhoyCaptain.config.event[:view_name])
              .group("#{table_name}.properties")
              .as('sub')
            )
          )
          .joins("INNER JOIN entry_pages ON entry_pages.min_id = sub.entry_id")
        }
        
        scope :with_exit_pages, -> {
          with(
            exit_pages: self.select(
              "sub.max_created_at as max_id, 
               sub.id as exit_id, 
               #{Arel.sql("#{AhoyCaptain.config.event.url_column} AS url")}"
            )
            .from(
              self.select(
                "MAX(#{table_name}.created_at) as max_created_at, 
                 LAST_VALUE(#{table_name}.id) OVER (PARTITION BY #{table_name}.properties ORDER BY #{table_name}.created_at ASC) as id"
              )
              .where(name: AhoyCaptain.config.event[:view_name])
              .group("#{table_name}.properties")
              .as('sub')
            )
          )
          .joins("INNER JOIN exit_pages ON exit_pages.max_id = sub.exit_id")
        }        

        scope :with_routes, -> { where(AhoyCaptain.config.event[:url_exists]) }

        scope :with_url, -> {
          select(Arel.sql("#{AhoyCaptain.config.event.url_column} AS url"))
        }

        scope :distinct_url, -> {
          distinct(Arel.sql("#{AhoyCaptain.config.event.url_column}"))
        }

        scope :with_property_values, ->(value) {
          where("JSONB_EXISTS(properties, '#{value}')")
        }

        ransacker :properties, args: [:parent, :ransacker_args] do |parent, args|
          Arel::Nodes::InfixOperation.new('->>', parent.table[:properties], Arel::Nodes.build_quoted(args))
        end

        ransacker :goal,
                  formatter: ->(value) {
                    ::Arel::Nodes::SqlLiteral.new(
                      ::AhoyCaptain.config.goals[value].event_query.call.select(:id).to_sql
                    )
                  } do |parent|
          parent.table[:id]
        end
      end

      class_methods do
        def ransackable_attributes(auth_object = nil)
          super + [ "action", "controller", "id",  "name", "page", "properties", "time", "url", "user_id", "visit_id", "goal"] + self._ransackers.keys
        end

        def ransackable_scopes(auth_object = nil)
          super + [:with_property_values, :property_value_i_cont]
        end

        def ransackable_associations(auth_object = nil)
          super + [:visit]
        end
      end
    end
  end
end

