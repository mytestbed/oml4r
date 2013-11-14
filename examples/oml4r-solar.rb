#!/usr/bin/env ruby

require 'rubygems'
require 'oml4r'
require 'nokogiri'
require 'open-uri'

# collects live solar power production data from the front page
# of the SMA 'Sunny Webbox' plant management web interface
# and inserts it into OML

def convert_to_W(p)
  a=p.split(" ")
  case a[1]    
  when "W"
    return a[0].to_f
  when "kW", "kWh"
    return a[0].to_f*1000
  when "MW", "MWh"
    return a[0].to_f*1000000
  when "GW", "GWh"
    # 1.21 gigawatts!!
    return a[0].to_f*1000000000
  end
end

# Define your own Measurement Point
class MyMP < OML4R::MPBase
  name :Power
  param :ts, :type => :string  
  param :Now_W, :type => :double
  param :DailyYield_Wh, :type => :double
  param :TotalYield_Wh, :type => :double  
end

# poll every second by default
interval = 1
host = nil

# Initialise the OML4R module for your application
oml_opts = {:appName => 'webbox',
  :domain => 'webbox-solar-live', :nodeID => 'plant1',
  :collect => 'file:-'}

node = OML4R::init(ARGV, oml_opts) do |op|
  op.banner = "Usage: #{$0} [options] webbox_ip_addr ...\n"
  op.on( '-i', '--interval SEC', "Query interval in seconds [#{interval}]" ) do |i|
    interval = i.to_i
  end
  op.on( '-w', '--webbox HOST', "Hostname or IP address of Sunny Webbox" ) do |w|
    host = w
  end
end

abort "Please specify the hostname or IP address of the Sunny Webbox ('-w')." if host.nil?

# catch CTRL-C
exit_requested = false
Kernel.trap( "INT" ) { exit_requested = true }

# poll Sunny Webbox
while !exit_requested
  doc = Nokogiri::HTML(open("http://#{host}/home.htm"))
  p=convert_to_W(doc.xpath('//td[@id="Power"]').text)
  d=convert_to_W(doc.xpath('//td[@id="DailyYield"]').text)
  t=convert_to_W(doc.xpath('//td[@id="TotalYield"]').text)
  # do not collect data when no power is generated
  next if p==0
  # inject the measurements
  MyMP.inject(Time.now,p,d,t)
  sleep interval
end

OML4R::close()
