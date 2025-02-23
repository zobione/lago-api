# frozen_string_literal: true

class BillAddOnJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError

  def perform(applied_add_on, timestamp)
    result = Invoices::AddOnService.new(
      applied_add_on: applied_add_on,
      datetime: Time.zone.at(timestamp),
    ).create

    raise(result.throw_error) unless result.success?
  end
end
