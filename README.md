# Kronos

This script sends email notifications based on events in a Google calendar.
You can add multiple reminders in the config.yml file.

## Process

1. reads information from a config.yml file
2. connect to the google calendar of our choice
3. use a regular expression to find appropriate entries in the calendar
4. send an email that is formatted appropriately.  


Installation

* clone the project from github
* install bundler
* cd to the folder you cloned the project
* bundle install


Run

`bundle exec ruby bin/send_emails.rb`



