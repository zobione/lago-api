# frozen_string_literal: true

module Types
  module InvoiceSubscription
    class Object < Types::BaseObject
      graphql_name 'InvoiceSubscription'

      field :invoice, Types::Invoices::Object, null: false
      field :subscription, Types::Subscriptions::Object, null: false

      field :charge_amount_cents, Integer, null: false
      field :subscription_amount_cents, Integer, null: false
      field :total_amount_cents, Integer, null: false

      field :fees, [Types::Fees::Object], null: true
      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: true
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: true

      # NOTE: LEGACY FIELDS
      field :from_date, GraphQL::Types::ISO8601Date, null: true
      field :to_date, GraphQL::Types::ISO8601Date, null: true

      def from_date
        object.from_datetime&.to_date
      end

      def to_date
        object.to_datetime&.to_date
      end
    end
  end
end
