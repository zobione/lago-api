# frozen_string_literal: true

module Subscriptions
  class DatesService
    def self.new_instance(subscription, billing_at, current_usage: false)
      klass = case subscription.plan.interval&.to_sym
              when :weekly
                Subscriptions::Dates::WeeklyService
              when :monthly
                Subscriptions::Dates::MonthlyService
              when :yearly
                Subscriptions::Dates::YearlyService
              else
                raise(NotImplementedError)
      end

      klass.new(subscription, billing_at, current_usage)
    end

    def initialize(subscription, billing_at, current_usage)
      @subscription = subscription

      # NOTE: Billing time should usually be the end of the billing period + 1 day
      #       When subscription is terminated, it is the termination day
      @billing_at = billing_at
      @current_usage = current_usage
    end

    def from_datetime
      return @from_datetime if @from_datetime

      @from_datetime = customer_timezone_shift(compute_from_date)

      # NOTE: On first billing period, subscription might start after the computed start of period
      #       ie: if we bill on beginning of period, and user registered on the 15th, the invoice should
      #       start on the 15th (subscription date) and not on the 1st
      @from_datetime = subscription.started_at if @from_datetime < subscription.started_at

      @from_datetime
    end

    def to_datetime
      return @to_datetime if @to_datetime

      @to_datetime = customer_timezone_shift(compute_to_date, end_of_day: true)
      @to_datetime = subscription.terminated_at if subscription.terminated? && @to_datetime > subscription.terminated_at

      @to_datetime
    end

    def charges_from_datetime
      datetime = customer_timezone_shift(compute_charges_from_date)
      datetime = subscription.started_at if datetime < subscription.started_at

      datetime
    end

    def charges_to_datetime
      datetime = customer_timezone_shift(compute_charges_to_date, end_of_day: true)
      datetime = subscription.terminated_at if subscription.terminated? && datetime > subscription.terminated_at

      datetime
    end

    def next_end_of_period(date)
      end_utc = compute_next_end_of_period(date)
      customer_timezone_shift(end_utc, end_of_day: true)
    end

    # NOTE: Retrieve the beginning of the previous period based on the billing date
    def previous_beginning_of_period(current_period: false)
      date = base_date
      date = billing_date if current_period

      beginning_utc = compute_previous_beginning_of_period(date)
      customer_timezone_shift(beginning_utc)
    end

    def single_day_price(optional_from_date: nil)
      duration = compute_duration(from_date: optional_from_date || compute_from_date)
      plan.amount_cents.fdiv(duration.to_i)
    end

    def charges_duration_in_days
      compute_charges_duration(from_date: compute_charges_from_date)
    end

    private

    attr_accessor :subscription, :billing_at, :current_usage

    delegate :plan, :subscription_date, :calendar?, :customer, to: :subscription

    def billing_date
      @billing_date ||= billing_at.in_time_zone(customer.applicable_timezone).to_date
    end

    def base_date
      @base_date ||= current_usage ? billing_date : compute_base_date
    end

    def customer_timezone_shift(date, end_of_day: false)
      result = date.in_time_zone(customer.applicable_timezone)
      result = result.end_of_day if end_of_day
      result.utc
    end

    def terminated_pay_in_arrear?
      # NOTE: In case of termination or upgrade when we are terminating old plan (paying in arrear),
      #       we should take to the beginning of the billing period
      subscription.terminated? && plan.pay_in_arrear? && !subscription.downgraded?
    end

    def terminated?
      subscription.terminated? && !subscription.next_subscription
    end

    # NOTE: Handle leap years and anniversary date > 28
    def build_date(year, month, day)
      if day.zero?
        day = 31
        month -= 1

        if month.zero?
          month = 12
          year -= 1
        end
      end

      days_count_in_month = Time.days_in_month(month, year)
      day = days_count_in_month if days_count_in_month < day

      Date.new(year, month, day)
    end

    def compute_base_date
      raise(NotImplementedError)
    end

    def compute_from_date
      raise(NotImplementedError)
    end

    def compute_to_date
      raise(NotImplementedError)
    end

    def compute_charges_from_date
      raise(NotImplementedError)
    end

    def compute_charges_to_date
      raise(NotImplementedError)
    end

    def compute_next_end_of_period(date)
      raise(NotImplementedError)
    end

    def first_month_in_yearly_period?
      false
    end

    def compute_duration(from_date:)
      raise(NotImplementedError)
    end
  end
end
