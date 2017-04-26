require 'addressable/uri'

class CASino::ServiceTicket < ActiveRecord::Base
  include CASino::ModelConcern::Ticket

  self.ticket_prefix = 'ST'.freeze

  belongs_to :ticket_granting_ticket
  before_destroy :send_single_sign_out_notification, if: :consumed?
  has_many :proxy_granting_tickets, as: :granter, dependent: :destroy

  def self.cleanup_unconsumed
    self.delete_all(['created_at < ? AND consumed = ?', CASino.config.service_ticket[:lifetime_unconsumed].seconds.ago, false])
  end

  def self.cleanup_consumed
    self.destroy_all(['(ticket_granting_ticket_id IS NULL OR created_at < ?) AND consumed = ?', CASino.config.service_ticket[:lifetime_consumed].seconds.ago, true])
  end

  def self.cleanup_consumed_hard
    self.delete_all(['created_at < ? AND consumed = ?', (CASino.config.service_ticket[:lifetime_consumed] * 2).seconds.ago, true])
  end

  def service=(service)
    normalized_encoded_service = Addressable::URI.parse(service).normalize.to_str
    super(normalized_encoded_service)
  end

  def service_with_ticket_url
    service_uri = Addressable::URI.parse(self.service)
    service_uri.query_values = (service_uri.query_values(Array) || []) << ['ticket', self.ticket]
    service_uri.to_s
  end

  def expired?
    lifetime = if consumed?
      CASino.config.service_ticket[:lifetime_consumed]
    else
      CASino.config.service_ticket[:lifetime_unconsumed]
    end
    (Time.now - (self.created_at || Time.now)) > lifetime
  end

  private
  def send_single_sign_out_notification
    begin
      notifier = SingleSignOutNotifier.new(self)
      notifier.notify
    rescue => e
      # This block was created in case of an UTF-8 error in the Faraday gem
      # arises. We will ignore it and treat as if it was successfuly notified, but will log to try to identify why this happens.
      Rails.logger.error "exception_class=#{e.class} exception_message=[#{e.message}] operation=send_single_sign_out_notification ticket=#{self.ticket} service=#{self.service}"
      Rails.logger.error e.backtrace.join("\n")
    end
    true
  end
end
