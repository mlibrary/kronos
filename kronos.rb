require 'google/apis/calendar_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'yaml'
require 'json'
require 'date'
require 'mail'
require 'ostruct'
require 'erb'

class AlertTriggers
  def initialize(configfile:)
    @config = YAML.load_file(configfile)
  end

  def active_triggers
    all_triggers.select{|trigger| trigger.enabled?}
  end

  def inactive_triggers
    all_triggers.reject{|trigger| trigger.enabled?}
  end

  def all_triggers
    config.map do |name, trigger_hash|
      Trigger.new(trigger_hash.merge(name: name))
    end
  end

  def trigger(name)
    Trigger.new(config[name])
  end

  def details_for_trigger(trigger)
    config[trigger]
  end

  private
  attr_accessor :config
end

class Trigger < OpenStruct
  def enabled?
    enabled
  end

  def to_s
    name
  end

  def matches?(event)
    matches_filter?(event) && occurs_on_end_date?(event)
  end

  def host
    smtp.split(":").first
  end

  def port
    if smtp.index(":").nil?
        25 
    else 
        smtp.split(":").last
    end
  end

  def end_date
    future_date(DateTime.now, lookahead)
  end

  def send_email!
    h = host
    p = port
    Mail.defaults do
      delivery_method:smtp, address: h, port: p
    end

    vars = {event_date: "#{end_date.strftime("%Y-%m-%d")}"}

    mail = Mail.new(
      from: from,
      to: to,
      subject: subject,
      body: body % vars,
    )
    mail.header['X-Custom-Header'] = 'Sent by Kronos'

    mail.deliver
  end

  private

  def future_date(start_date, interval)
    m = interval.to_s.match(/((\d+)m)? ?((\d+)w)? ?((\d+)d)? ?((\d+)h)?/i)
    hour = start_date.hour + m[8].to_i
    hrem = hour / 24
    hour = hour % 24
    days = m[4].to_i * 7 + m[6].to_i + hrem
    months = m[2].to_i
    later = DateTime.new(
      start_date.year,
      start_date.month,
      start_date.day,
      hour,
      start_date.minute,
      start_date.second
    )
    later = later >> months
    later = later + days
    return later
  end

  def matches_filter?(event)
    /#{regex}/i.match(event.summary.to_s)
  end

  def occurs_on_end_date?(event)
    event.start.date == end_date.strftime("%Y-%m-%d")
  end
end


class GoogleCalendarRetriever

  def initialize(credsfile:, secretsfile:)
    abort "Unable to access the secrets file. Aborting..." unless File.exist?(secretsfile)
    @credsfile = credsfile
    @secretsfile = secretsfile
  end

  def store_credentials_from_code!
    uri = 'urn:ietf:wg:oauth:2.0:oob'
    url = authorizer.get_authorization_url(base_url: uri)
    puts url
    code = gets
    authorizer.get_and_store_credentials_from_code(user_id: 'default', code: code, base_url:uri)
  end

  def read_from_calendar(calendar_id, end_time)
    service.list_events(
      calendar_id,
      single_events: true,
      order_by: 'startTime',
      time_min: DateTime.now.iso8601,
      time_max: end_time.iso8601
    )
  end

  private

  attr_reader :secretsfile, :credsfile

  def service
    return @service if @service
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.client_options.application_name = "Kronos"
    @service.authorization = credentials
    @service
  end

  def authorizer
    return @authorizer if @authorizer
    client_id = Google::Auth::ClientId.from_file(secretsfile)
    token_store = Google::Auth::Stores::FileTokenStore.new(file: credsfile)
    scope = Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY
    @authorizer = Google::Auth::UserAuthorizer.new(client_id,scope,token_store)
  end

  def credentials
    @credentials ||= authorizer.get_credentials('default').tap do |creds|
      abort "Couldn't get credentials" unless creds
    end
  end
end

