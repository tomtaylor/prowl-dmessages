#!/usr/bin/env ruby
begin
  require 'rubygems'
  gem "twitter"
  require 'twitter'
  require "prowl"
rescue LoadError
  puts "This script requires the following gems: twitter, prowl."
  puts "  sudo gem install twitter prowl"
  exit 1
end

current_dir = File.dirname(__FILE__)
config = YAML.load_file(File.join(current_dir, 'prowl-dmessages-config.yml'))
last_seen_file_path = File.join(current_dir, 'prowl-dmessages-last-seen-id')

if (File.exist?(last_seen_file_path))
  File.open(last_seen_file_path, 'r') do |f|
    @last_seen_id = f.read.to_i
  end
end
@last_seen_id ||= 0

# RIP httpauth - use twurl to get the access token/secret
t = config["twitter"]
oauth = Twitter::OAuth.new(t["consumer_token"], t["consumer_secret"])
oauth.authorize_from_access(t["access_token"], t["access_secret"])
base = Twitter::Base.new(oauth)

# IDs are sequential, so we want to iterate up through them, so if it ever fails we can resume where we left off
direct_messages = base.direct_messages(:since_id => @last_seen_id).sort_by { |m| Time.parse(m.created_at) }

prowl = Prowl.new(:apikey => config["prowl"]["api_key"], :application => "Twitter", :event => "d msg")

# unless prowl.valid?
#   puts "API key is invalid, did you copy it correctly?"
#   exit 2
# end

if direct_messages.any?
  most_recent_id = 0

  direct_messages.each do |message|
    text = "From #{message.sender.screen_name}: #{message.text}"
    puts "Sending: #{text}"

    begin
      if prowl.add(:description => text) == 200
        most_recent_id = message.id if message.id > most_recent_id
      else
        raise "Bad response from Prowl"
      end
    rescue Exception => e
      puts "Something failed, breaking for this run: #{e}"
      break
    end
  end

  if @last_seen_id > most_recent_id
    most_recent_id = @last_seen_id
  end

  File.open(last_seen_file_path, 'w') do |f|
    f.puts most_recent_id
  end
end

