# frozen_string_literal: true

module Invoices
  class AddOnService < BaseService
    def initialize(applied_add_on:, datetime:)
      @applied_add_on = applied_add_on
      @datetime = datetime

      super(nil)
    end

    def create
      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          customer: customer,
          issuing_date: issuing_date,
          invoice_type: :add_on,
          status: :pending,

          # NOTE: Apply credits before VAT, will be changed with credit note feature
          legacy: true,
          vat_rate: customer.applicable_vat_rate,
        )

        create_add_on_fee(invoice)

        compute_amounts(invoice)

        invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
        invoice.total_amount_currency = applied_add_on.amount_currency
        invoice.save!

        track_invoice_created(invoice)
        result.invoice = invoice
      end

      SendWebhookJob.perform_later(:add_on, result.invoice) if should_deliver_webhook?
      create_payment(result.invoice)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :datetime, :applied_add_on

    delegate :customer, to: :applied_add_on

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :vat_amount_cents)

      invoice.amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.amount_currency = applied_add_on.amount_currency
      invoice.vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)
      invoice.vat_amount_currency = applied_add_on.amount_currency
    end

    def create_add_on_fee(invoice)
      fee_result = Fees::AddOnService
        .new(invoice: invoice, applied_add_on: applied_add_on).create
      raise(fee_result.throw_error) unless fee_result.success?
    end

    def should_deliver_webhook?
      customer.organization.webhook_url?
    end

    def create_payment(invoice)
      Invoices::Payments::CreateService.new(invoice).call
    end

    def track_invoice_created(invoice)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type,
        },
      )
    end

    # NOTE: accounting date must be in customer timezone
    def issuing_date
      datetime.in_time_zone(customer.applicable_timezone).to_date
    end
  end
end
