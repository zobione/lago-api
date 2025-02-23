# frozen_string_literal: true

module Mutations
  module Organizations
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'UpdateOrganization'
      description 'Updates an Organization'

      argument :webhook_url, String, required: false
      argument :vat_rate, Float, required: false
      argument :logo, String, required: false
      argument :legal_name, String, required: false
      argument :legal_number, String, required: false
      argument :email, String, required: false
      argument :address_line1, String, required: false
      argument :address_line2, String, required: false
      argument :state, String, required: false
      argument :zipcode, String, required: false
      argument :city, String, required: false
      argument :country, Types::CountryCodeEnum, required: false
      argument :invoice_footer, String, required: false
      argument :invoice_grace_period, Integer, required: false

      type Types::OrganizationType

      def resolve(**args)
        validate_organization!

        result = ::Organizations::UpdateService
          .new(current_organization)
          .update(**args)

        result.success? ? result.organization : result_error(result)
      end
    end
  end
end
