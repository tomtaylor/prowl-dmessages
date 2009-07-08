#!/usr/bin/env ruby
begin
  require 'rubygems'
  require 'activesupport'
  require 'twitter'
  require 'httparty'
rescue LoadError, MissingSourceFile
  puts "This script requires the following gems: activesupport, twitter, httparty."
  puts "  sudo gem install activesupport twitter httparty"
  exit 1
end

class Prowl
  include HTTParty
  base_uri 'https://prowl.weks.net/publicapi'
  format :xml
  
  def initialize(api_key)
    @api_key = api_key
  end
  
  def add_notification(options = {})
    self.class.get("/add?application=#{URI.encode(options[:application])}&event=#{URI.encode(options[:event])}&description=#{URI.encode(options[:description])}&apikey=#{@api_key}")
  end
  
  def verify_api_key
    self.class.get("/verify?apikey=#{@api_key}")
  end
end

current_dir = File.dirname(__FILE__)
config = YAML::load(File.read(File.join(current_dir, 'prowl-dmessages-config.yml')))
last_seen_file_path = File.join(current_dir, 'prowl-dmessages-last-seen-id')

if (File.exist?(last_seen_file_path))
  file = File.new(last_seen_file_path, 'r')
  last_seen_id = file.read.to_i
  file.close
else
  last_seen_id = 0
end

httpauth = Twitter::HTTPAuth.new(config["twitter"]["username"], config["twitter"]["password"])
base = Twitter::Base.new(httpauth)

direct_messages = base.direct_messages(:since_id => last_seen_id)

# IDs are sequential, so we want to iterate up through them, so if it ever fails we can resume where we left off
direct_messages = direct_messages.sort_by { |m| Time.parse(m.created_at) }

prowl = Prowl.new(config["prowl"]["api_key"])
response = prowl.verify_api_key
if response && response.code > 200
  puts "API key is invalid, did you copy it correctly?"
  exit 1
end  

if direct_messages.any?
  most_recent_id = 0
  direct_messages.each do |message|
    text = "From #{message.sender.screen_name}: #{message.text}"
    puts "Sending: #{text}"
  
    begin
      response = prowl.add_notification(:application => 'Twitter', :event => 'd msg', :description => text)
      if response.code == 200
        most_recent_id = message.id if message.id > most_recent_id
      else
        raise "Bad response from Prowl: #{response['prowl']['error']}"
      end
    rescue Exception => e
      puts "Something failed, breaking for this run: #{e}"
      break
    end
  end
  file = File.new(last_seen_file_path, 'w')
  file.write(most_recent_id.to_s)
  file.close
end

