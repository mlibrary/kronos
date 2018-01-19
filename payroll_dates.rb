require 'google/apis/calendar_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'yaml'
require 'json'
require 'date'
require 'mail'

class AlertTriggers
    def initialize(configfile:)
        if File.exist?(configfile)
            @config = YAML.load_file(configfile)
        end
    end

    def active_triggers
        (config.select { |key,value| value["enabled"]==true }).keys
    end 

    def inactive_triggers
        (config.select { |key,value| value["enabled"]==false }).keys
    end 

    def all_triggers
        config.keys
    end 

    def details_for_trigger(trigger)
        config[trigger]
    end 

    private        
    attr_accessor :config
end

def future_date(dt, interval) 
    m = interval.to_s.match(/((\d+)m)? ?((\d+)w)? ?((\d+)d)? ?((\d+)h)?/i)
    hour = dt.hour + m[8].to_i
    hrem = hour / 24
    hour = hour % 24    
    days = m[4].to_i * 7 + m[6].to_i + hrem
    months = m[2].to_i
    later = DateTime.new(dt.year, dt.month, dt.day, hour, dt.minute, dt.second)
    later = later >> months
    later = later + days
    return later
end 

class GoogleCalendarRetriever
    def initialize(credsfile:, secretsfile:) 
        if File.exist?(secretsfile) 
            client_id = Google::Auth::ClientId.from_file(secretsfile)
            token_store = Google::Auth::Stores::FileTokenStore.new(file: credsfile)
            scope = Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY
            authorizer = Google::Auth::UserAuthorizer.new(client_id,scope,token_store)
            @credentials = authorizer.get_credentials('default')
            if @credentials.nil?
                puts "Couldn't get credentials..."
                uri = 'urn:ietf:wg:oauth:2.0:oob'
                url = authorizer.get_authorization_url(base_url: uri)
                puts url
                code = gets
                @credentials = authorizer.get_and_store_credentials_from_code(user_id: 'default', code: code, base_url:uri)
            end
            @googleservice = Google::Apis::CalendarV3::CalendarService.new
            @googleservice.client_options.application_name = "Kronos"
            @googleservice.authorization = @credentials
        else 
            puts "Unable to access the secrets file. Aborting..."
            abort
        end
    end 

    def read_from_calendar(calendar_id, look_ahead_time) 
        endTime = future_date(DateTime.now, look_ahead_time)
        @googleservice.list_events(calendar_id, 
                                    single_events: true, 
                                    order_by: 'startTime',
                                    time_min:DateTime.now.iso8601,
                                    time_max:endTime.iso8601)
    end 

    private
    attr_accessor :credentials, :googleservice
end


def send_email(s_host,s_from,s_to,s_subject,s_body) 
    i = s_host.index(":")
    Mail.defaults do 
        if i.nil?
            delivery_method:smtp, address:"#{s_host}", port: 25
        else
            delivery_method:smtp, address:"#{s_host[0..i-1]}", port: "#{s_host[i+1..-1]}".to_i
        end
    end
    mail = Mail.new do 
        from    "#{s_from}"
        to      "#{s_to}"
        subject "#{s_subject}"
        body    "#{s_body}"
    end 
    mail.header['X-Custom-Header'] = 'Sent by Kronos'
    return mail.deliver
end

t = AlertTriggers.new(configfile:"config.yml")
g = GoogleCalendarRetriever.new(credsfile:"kronosauth.yml", secretsfile:"client_secret.json")

t.active_triggers.each do |trigger|
    trigger_details = t.details_for_trigger(trigger)
    events = g.read_from_calendar(trigger_details["sourcecalendarid"], trigger_details["lookahead"])
    puts "#{events.items.count} events found in the time period defined (#{trigger_details["lookahead"]}) for #{trigger}"
    events.items.each do |event|
        next unless event.status == "confirmed"
            puts "\t#{event.start.date} - #{event.summary} - #{event.status}"
        if event.summary.to_s.match(/#{trigger_details["regex"]}/i) && event.start.date == future_date(DateTime.now,trigger_details["lookahead"]).strftime("%Y-%m-%d")
            puts "\t\tSending email"
            send_email(trigger_details["smtp"],trigger_details["from"],trigger_details["to"],trigger_details["subject"],trigger_details["body"])
        end
    end
end
