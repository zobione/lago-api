# frozen_string_literal: true

module Api
  module V1
    class BillableMetricsController < Api::BaseController
      def create
        service = ::BillableMetrics::CreateService.new
        result = service.create(
          **input_params
            .merge(organization_id: current_organization.id)
            .to_h
            .symbolize_keys,
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: 'billable_metric',
            ),
          )
        else
          render_error_response(result)
        end
      end

      def update
        service = ::BillableMetrics::UpdateService.new
        result = service.update_from_api(
          organization: current_organization,
          code: params[:code],
          params: input_params.to_h,
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: 'billable_metric',
            ),
          )
        else
          render_error_response(result)
        end
      end

      def destroy
        service = ::BillableMetrics::DestroyService.new
        result = service.destroy_from_api(
          organization: current_organization,
          code: params[:code],
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: 'billable_metric',
            ),
          )
        else
          render_error_response(result)
        end
      end

      def show
        metric = current_organization.billable_metrics.find_by(
          code: params[:code],
        )

        return not_found_error(resource: 'billable_metric') unless metric

        render(
          json: ::V1::BillableMetricSerializer.new(
            metric,
            root_name: 'billable_metric',
          ),
        )
      end

      def index
        metrics = current_organization.billable_metrics
          .order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            metrics,
            ::V1::BillableMetricSerializer,
            collection_name: 'billable_metrics',
            meta: pagination_metadata(metrics),
          ),
        )
      end

      private

      def input_params
        params.require(:billable_metric).permit(
          :name,
          :code,
          :description,
          :aggregation_type,
          :field_name,
          group: {},
        )
      end
    end
  end
end
