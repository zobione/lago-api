# frozen_string_literal: true

module Invoices
  class CalculateFeesService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(invoice:, timestamp:)
      @invoice = invoice
      @timestamp = timestamp
      @customer = invoice.subscriptions&.first&.customer
      @currency = invoice.subscriptions&.first&.plan&.amount_currency

      super
    end

    def call
      ActiveRecord::Base.transaction do
        invoice.subscriptions.each do |subscription|
          boundaries = calculate_boundaries(subscription)

          create_subscription_fee(subscription, boundaries) if should_create_subscription_fee?(subscription)
          create_charges_fees(subscription, boundaries) if should_create_charge_fees?(subscription)
        end

        compute_amounts
        create_credit_note_credit if should_create_credit_note_credit?
        create_coupon_credit if should_create_coupon_credit?
        create_applied_prepaid_credit if should_create_applied_prepaid_credit?

        invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
        invoice.status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        invoice.save!

        result.invoice = invoice
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :timestamp, :customer, :currency

    def issuing_date
      Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone).to_date
    end

    def date_service(subscription)
      Subscriptions::DatesService.new_instance(
        subscription,
        Time.zone.at(timestamp),
        current_usage: subscription.terminated? && subscription.upgraded?,
      )
    end

    def compute_amounts
      fee_amounts = invoice.fees.select(:amount_cents, :vat_amount_cents)

      invoice.amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)
    end

    def create_subscription_fee(subscription, boundaries)
      fee_result = Fees::SubscriptionService.new(
        invoice: invoice,
        subscription: subscription,
        boundaries: boundaries,
      ).create

      fee_result.throw_error unless fee_result.success?
    end

    def create_charges_fees(subscription, boundaries)
      subscription.plan.charges.each do |charge|
        fee_result = Fees::ChargeService.new(
          invoice: invoice,
          charge: charge,
          subscription: subscription,
          boundaries: boundaries,
        ).create

        fee_result.throw_error unless fee_result.success?
      end
    end

    def should_create_subscription_fee?(subscription)
      # NOTE: When plan is pay in advance we generate an invoice upon subscription creation
      # We want to prevent creating subscription fee if subscription creation already happened on billing day
      return false if subscription.plan.pay_in_advance? && subscription.fee_exists?(issuing_date)
      return false unless should_create_yearly_subscription_fee?(subscription)

      # NOTE: When a subscription is terminated we still need to charge the subscription
      #       fee if the plan is in pay in arrear, otherwise this fee will never
      #       be created.
      subscription.active? || (subscription.terminated? && subscription.plan.pay_in_arrear?)
    end

    def should_create_yearly_subscription_fee?(subscription)
      return true unless subscription.plan.yearly?

      # NOTE: we do not want to create a subscription fee for plans with bill_charges_monthly activated
      # But we want to keep the subscription charge when it has to proceed
      # Cases when we want to charge a subscription:
      # - Plan is pay in advance, we're at the beginning of the period or subscription has never been billed
      # - Plan is pay in arrear and we're at the beginning of the period
      date_service(subscription).first_month_in_yearly_period? ||
        subscription.plan.pay_in_advance && !subscription.already_billed?
    end

    def should_create_charge_fees?(subscription)
      # We should take a look at charges if subscription is created in the past and if it is not upgrade
      if subscription.plan.pay_in_advance? && subscription.started_in_past? && subscription.previous_subscription.nil?
        return true
      end

      # NOTE: Charges should not be billed in advance when we are just upgrading to a new
      #       pay_in_advance subscription
      return false if subscription.plan.pay_in_advance? && subscription.invoices.where.not(id: invoice.id).count.zero?

      true
    end

    def applied_coupons
      return @applied_coupons if @applied_coupons

      @applied_coupons = customer.applied_coupons.active.order(created_at: :asc)
    end

    def credit_notes
      @credit_notes ||= customer.credit_notes.available.order(created_at: :asc)
    end

    def wallet
      return @wallet if @wallet

      @wallet = customer.wallets.active.first
    end

    def should_create_credit_note_credit?
      credit_notes.any?
    end

    def should_create_coupon_credit?
      return false if applied_coupons.blank?
      return false unless invoice.amount_cents&.positive?

      true
    end

    def should_create_applied_prepaid_credit?
      return false unless wallet&.active?
      return false unless invoice.amount_cents&.positive?

      wallet.balance.positive?
    end

    def create_credit_note_credit
      credit_result = Credits::CreditNoteService.new(
        invoice: invoice,
        credit_notes: credit_notes,
      ).call
      credit_result.throw_error unless credit_result.success?

      refresh_amounts(credit_amount_cents: credit_result.credits.sum(&:amount_cents))
    end

    def create_coupon_credit
      applied_coupons.each do |applied_coupon|
        break unless invoice.amount_cents&.positive?

        next if applied_coupon.coupon.fixed_amount? && applied_coupon.amount_currency != currency

        credit_result = Credits::AppliedCouponService.new(
          invoice: invoice,
          applied_coupon: applied_coupon,
        ).create
        credit_result.throw_error unless credit_result.success?

        refresh_amounts(credit_amount_cents: credit_result.credit.amount_cents)
      end
    end

    def create_applied_prepaid_credit
      prepaid_credit_result = Credits::AppliedPrepaidCreditService.new(invoice: invoice, wallet: wallet).create
      prepaid_credit_result.throw_error unless prepaid_credit_result.success?

      refresh_amounts(credit_amount_cents: prepaid_credit_result.prepaid_credit_amount_cents)
    end

    # NOTE: Since credit impact the invoice amount, we need to recompute the amount and
    #       the VAT amount
    def refresh_amounts(credit_amount_cents:)
      invoice.amount_cents = invoice.amount_cents - credit_amount_cents
      invoice.vat_amount_cents = (invoice.amount_cents * customer.applicable_vat_rate).fdiv(100).ceil
    end

    def calculate_boundaries(subscription)
      date_service = date_service(subscription)

      {
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        timestamp: timestamp,
      }
    end
  end
end
