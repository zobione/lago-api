# frozen_string_literal: true

module V1
  module Legacy
    class CustomerUsageSerializer < ModelSerializer
      def serialize
        {
          # TODO: remove || after all cache key expirations
          from_date: model.from_date || model.from_datetime&.to_date,
          to_date: model.to_date || model.to_datetime&.to_date,
        }
      end
    end
  end
end
