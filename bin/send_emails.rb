require_relative "../kronos"

triggers = AlertTriggers.new(configfile: "config.yml")
calendars = GoogleCalendarRetriever.new(credsfile: "kronosauth.yml", secretsfile: "client_secret.json")

triggers.active_triggers.each do |trigger|
  events = calendars.read_from_calendar(trigger.sourcecalendarid, trigger.end_date)
  puts "#{events.items.count} events found in the time period defined (#{trigger.lookahead}) for #{trigger}"

  events.items
    .select{|event| event.status == "confirmed"}
    .select{|event| trigger.matches?(event)}
    .each do |event|
      trigger.send_email!
    end
end

