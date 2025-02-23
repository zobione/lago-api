# frozen_string_literal: true

module Api
  module V1
    class WalletTransactionsController < Api::BaseController
      def create
        service = WalletTransactions::CreateService.new
        result = service.create(
          organization_id: current_organization.id,
          wallet_id: input_params[:wallet_id],
          paid_credits: input_params[:paid_credits],
          granted_credits: input_params[:granted_credits],
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.wallet_transactions,
              ::V1::WalletTransactionSerializer,
              collection_name: 'wallet_transactions',
            ),
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        @input_params ||= params.require(:wallet_transaction).permit(
          :wallet_id,
          :paid_credits,
          :granted_credits
        )
      end
    end
  end
end
