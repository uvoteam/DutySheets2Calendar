#!/usr/bin/env ruby

require 'date'
require 'yaml'
require 'etc'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'google/apis/sheets_v4'
require 'google/apis/calendar_v3'

class DutyShifts
    ConfigurationFile = './config.yaml'

    def self.help
        scriptname = File.basename __FILE__
        puts <<-HELP
USE: #{scriptname} [options]

Options:
  --sheet name      - Sheet name to use
  --date date       - Start from this date (default: today)
  --clear           - Clear calendar before adding events
  --dry-run         - Do not create events, only print them
        HELP
    end

    def self.run

        config = YAML.load_file ConfigurationFile

        next_arg = nil
        ARGV.each do |arg|
            case arg
            when '--sheet'      then next_arg = :sheet_name
            when '--date'       then next_arg = :start_date
            when '--clear'      then config[:clear_events] = true
            when '--dry-run'    then config[:noop] = true
            when '--help', '-h' then return self.help
            else
                if next_arg
                    config[next_arg] = arg
                    next_arg         = nil
                else
                    raise ArgumentError, "This command takes no arguments"
                end
            end
        end

        DutyShifts::Authorization.auth_info **config[:auth]

        spreadsheet = DutyShifts::Spreadsheet.new sheet_id: config[:sheet_id]
        config[:sheet_name] ||= spreadsheet.list.first
        username = config.fetch :username, Etc.getlogin
        row = spreadsheet
            .data(sheet: config[:sheet_name], range: config[:sheet_range])
            .find { |row| row[0] == username }
        row.shift

        calendar = DutyShifts::Calendar.new name: config.fetch(:calendar_name, 'DutyShifts'), keep_events: !config[:clear_events] unless config[:noop]
        alarm_times = config.fetch(:alarm_times, [])

        start_date = Date.parse config[:start_date] if config[:start_date]
        start_date ||= Date.today
        start_date.upto(start_date.end_of_month) do |date|
            column      = (date.day - 1) * 2
            day_hours   = row[column].to_i
            night_hours = row[column+1].to_i

            if day_hours > 0
                name       = 'Day shift'
                start_hour = 8
                length     = day_hours
            elsif night_hours > 0
                name       = 'Night shift'
                start_hour = 20
                length     = night_hours
            else
                next
            end
            
            starttime = date.to_time hour: start_hour
            if config[:noop]
                puts "#{starttime}: #{name} [#{length}]"
            else
                calendar.add_event(
                    name:        name,
                    starttime:   starttime,
                    endtime:     starttime + length * 60 * 60,
                    alarm_times: alarm_times,
                )
            end
        end
    end

    class Authorization
        OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'

        @@credentials = nil
        @@user_id
        @@secret
        @@store  = './store.yaml'
        @@scopes = [
            'https://www.googleapis.com/auth/spreadsheets.readonly',
            'https://www.googleapis.com/auth/calendar',
        ]

        def self.auth_info (user_id:, secret:, store: nil, scopes: nil)
            @@user_id = user_id
            @@secret  = secret
            @@store   = store unless store.nil?
            @@scopes  = scopes unless scopes.nil?
        end

        def self.credentials
            @@credentials ||= self.get_credentials
        end

        private
        def self.get_credentials
            client_id   = Google::Auth::ClientId.new @@user_id, @@secret 
            token_store = Google::Auth::Stores::FileTokenStore.new file: @@store
            authorizer  = Google::Auth::UserAuthorizer.new client_id, @@scopes, token_store
            credentials = authorizer.get_credentials @@user_id

            if credentials.nil?
                url = authorizer.get_authorization_url base_url: OOB_URI
                puts <<-MESSAGE
                    Please, open this url in your browser and enter the resulting code:

                    #{url}

                MESSAGE
                print "Code: "
                code = gets
                credentials = authorizer.get_and_store_credentials_from_code user_id: @@user_id, code: code, base_url: OOB_URI
            end

            credentials
        end
    end

    class Calendar
        @calendar_name
        @calendar
        @calendar_id = nil

        def initialize (name:, keep_events: false)
            @calendar_name = name
            @calendar = Google::Apis::CalendarV3::CalendarService.new
            @calendar.authorization = DutyShifts::Authorization.credentials

            @calendar_id = @calendar.list_calendar_lists.items
                .select { |calendar_list| calendar_list.summary == @calendar_name }
                .first&.id

            if !keep_events and @calendar_id
                @calendar.delete_calendar @calendar_id
                @calendar_id = nil
            end

            @calendar_id ||= @calendar.insert_calendar(
                Google::Apis::CalendarV3::Calendar.new(
                    summary: @calendar_name,
                    description: "#{@calendar_name} (autogenerated calendar)",
                    time_zone: 'Europe/Kiev',
                )
            ).id
        end

        def add_event (name:, starttime:, endtime:, alarm_times: [], description: nil)
            @calendar.insert_event(@calendar_id,
                Google::Apis::CalendarV3::Event.new(
                    summary: name,
                    description: description.nil? ? name : description,
                    start: {
                        date_time: starttime.rfc3339,
                        time_zone: 'Europe/Kiev',
                    },
                    end: {
                        date_time: endtime.rfc3339,
                        time_zone: 'Europe/Kiev',
                    },
                    reminders: {
                        use_default: false,
                        overrides:   alarm_times.map { |minutes| { reminder_method: 'popup', minutes: minutes } },
                    },
                )
            )
        end
    end

    class Spreadsheet
        @sheet_id
        @spreadsheet

        def initialize (sheet_id:)
            @sheet_id = sheet_id
            @spreadsheet = Google::Apis::SheetsV4::SheetsService.new
            @spreadsheet.authorization = DutyShifts::Authorization.credentials
        end

        def list
            @spreadsheet.get_spreadsheet(@sheet_id)
                .sheets
                .reject { |sheet| sheet.properties.hidden }
                .sort_by { |sheet| sheet.properties.index }
                .map { |sheet| sheet.properties.title }
        end

        def data (sheet:, range:)
            @spreadsheet.get_spreadsheet_values(@sheet_id, "#{sheet}!#{range}").values
        end
    end
end

class Date
    def end_of_month
        Date.new self.year, self.month, -1
    end

    def to_time (hour: 0, minute: 0, second: 0)
        Time.new self.year, self.month, self.day, hour, minute, second
    end
end

class Time
    def rfc3339
        self.strftime '%FT%T'
    end
end

DutyShifts.run

# the end
