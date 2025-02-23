module Types
  module Events
    class Object < Types::BaseObject
      graphql_name 'Event'

      field :id, ID, null: false
      field :code, String, null: false

      field :external_customer_id, String, null: false
      field :external_subscription_id, String, null: false
      field :transaction_id, String, null: true

      field :timestamp, GraphQL::Types::ISO8601DateTime, null: true
      field :timestamp_in_customer_timezone, GraphQL::Types::ISO8601DateTime, null: true

      field :received_at, GraphQL::Types::ISO8601DateTime, null: false
      field :received_at_in_customer_timezone, GraphQL::Types::ISO8601DateTime, null: false

      field :api_client, String, null: true
      field :ip_address, String, null: true

      field :payload, GraphQL::Types::JSON, null: false
      field :billable_metric_name, String, null: true

      field :match_billable_metric, Boolean, null: false
      field :match_custom_field, Boolean, null: false

      def received_at
        object.created_at
      end

      def external_customer_id
        object.customer.external_id
      end

      def external_subscription_id
        object.subscription.external_id
      end

      def payload
        {
          event: {
            transaction_id: object.transaction_id,
            external_customer_id: object.customer.external_id,
            external_subscription_id: object.subscription.external_id,
            code: object.code,
            timestamp: object.timestamp.to_i,
            properties: object.properties || {},
          },
        }
      end

      def match_billable_metric
        object.billable_metric_name.present?
      end

      def match_custom_field
        return true if object.billable_metric_field_name.blank?

        object.properties.key?(object.billable_metric_field_name)
      end

      delegate :timestamp_in_customer_timezone, to: :object

      def received_at_in_customer_timezone
        object.created_at_in_customer_timezone
      end
    end
  end
end
