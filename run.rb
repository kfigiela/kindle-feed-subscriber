#!/usr/bin/env ruby
require "bundler/setup"
require 'open-uri'
require 'digest/sha1'

Bundler.require(:default)

def display_img_title(html)
  html.gsub /<img[^>]*title="([^"]*)"[^>]*>/, '\0\1'
end


url = (ENV['FEED'] or "http://xkcd.com/atom.xml")
$stderr.puts "Fetching feed #{url}"
# feed ||= "http://what-if.xkcd.com/feed.atom"
cache = "dump/#{Digest::SHA1.hexdigest(url)}"
feed = begin
    feed = Marshal.load(File.open(cache).read)
    feed = Feedzirra::Feed.update(feed)
    feed
  rescue Exception => e
    p e
    Feedzirra::Feed.fetch_and_parse url
end

regexp = /(?<=src=")([^"]*?)(?=")/
feed.entries.each do |entry|
  entry.summary.gsub! regexp do |m|
    m.sub! %r{^//}, "http://"
    name = "cache/"+(Digest::SHA1.hexdigest m)+File.extname(m)
    unless File.exist?(name) 
      $stderr.puts "Fetching #{m}"
      File.open(name, "wb") do |f|
        f.write open(m).read
      end
    else
      $stderr.puts "Already have #{m}"
    end
    name
  end 
end

if feed.new_entries.count > 0 or true
  $stderr.puts "Rendering HTML"
  File.open("out.html", "wb") do |f|
    f.write Haml::Engine.new(File.read("template.html.haml")).render(binding)
  end
  Kernel.system("kindlegen out.html -c2 -gif -o kindle.mobi")

  feed.new_entries = []
  File.open(cache, "wb") do |f|
    f.write Marshal.dump(feed)
  end


  $stderr.puts "Sending email"
  Pony.mail({
      :to => ENV['SMTP_TO'],
      :from => ENV['SMTP_FROM'],
      :via => :smtp,
      :attachments => {"kindle.mobi" => File.read("kindle.mobi")},
      :via_options => {
        :address              => (ENV['SMTP_SERVER'] or 'smtp.gmail.com'),
        :port                 => (ENV['SMTP_POSRT'] or '587'),
        :enable_starttls_auto => true,
        :user_name            => (ENV['SMTP_USER'] or ENV['SMTP_FROM']),
        :password             => ENV['SMTP_PASSWORD'],
        :authentication       => :plain, # :plain, :login, :cram_md5, no auth by default
        :domain               => "localhost.localdomain" # the HELO domain provided by the client to the server
      }
    })
  
else
  puts "Nothing new"
end
