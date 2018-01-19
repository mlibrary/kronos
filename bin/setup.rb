require_relative "../kronos"

GoogleCalendarRetriever.new(credsfile: "kronosauth.yml", secretsfile: "client_secret.json")
  .store_credentials_from_code!
