# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::AddOnService, type: :service do
  subject(:invoice_service) do
    described_class.new(applied_add_on: applied_add_on, datetime: datetime)
  end

  let(:datetime) { Time.zone.now }
  let(:applied_add_on) { create(:applied_add_on) }

  describe 'create' do
    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates an invoice' do
      result = invoice_service.create

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.subscriptions.first).to be_nil
        expect(result.invoice.issuing_date).to eq(datetime.to_date)
        expect(result.invoice.invoice_type).to eq('add_on')
        expect(result.invoice.status).to eq('pending')

        expect(result.invoice.amount_cents).to eq(200)
        expect(result.invoice.amount_currency).to eq('EUR')
        expect(result.invoice.vat_amount_cents).to eq(40)
        expect(result.invoice.vat_amount_currency).to eq('EUR')
        expect(result.invoice.vat_rate).to eq(20)
        expect(result.invoice.total_amount_cents).to eq(240)
        expect(result.invoice.total_amount_currency).to eq('EUR')

        expect(result.invoice).to be_legacy
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        invoice_service.create
      end.to have_enqueued_job(SendWebhookJob)
    end

    it 'calls SegmentTrackJob' do
      invoice = invoice_service.create.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type,
        },
      )
    end

    it 'creates a payment' do
      payment_create_service = instance_double(Invoices::Payments::CreateService)
      allow(Invoices::Payments::CreateService)
        .to receive(:new).and_return(payment_create_service)
      allow(payment_create_service)
        .to receive(:call)

      invoice_service.create

      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    context 'when organization does not have a webhook url' do
      before { applied_add_on.customer.organization.update!(webhook_url: nil) }

      it 'does not enqueues a SendWebhookJob' do
        expect do
          invoice_service.create
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'with customer timezone' do
      before { applied_add_on.customer.update!(timezone: 'America/Los_Angeles') }

      let(:datetime) { DateTime.parse('2022-11-25 01:00:00') }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.create

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
      end
    end
  end
end
