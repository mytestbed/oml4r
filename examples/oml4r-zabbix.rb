#!/usr/bin/env ruby

# example script that reads CPU load measurements from a Zabbix server
# and pushes them into an OML database

# make sure you install these two gems
require "zabbixapi"
require "oml4r"

# # Zabbix node names
# nodes = ["10.129.16.11", "10.129.16.12", "10.129.16.13"]

# Define your own Measurement Point
class CPU_MP < OML4R::MPBase
  name :CPU
  param :ts, :type => :string  
  param :node, :type => :string    
  param :load1, :type => :double
  param :load5, :type => :double
  param :load15, :type => :double 
end


# Initialise the OML4R module for your application
oml_opts = {
  :appName => 'zabbix',
  :domain => 'zabbix-cpu-measurement', 
  :nodeID => 'cloud',
  :collect => 'file:-'
}
zabbix_opts = {
  :url => 'http://cloud.npc.nicta.com.au/zabbix/api_jsonrpc.php',
  :user => 'Admin',
  :password => 'zabbix'
}

interval = 1

nodes = OML4R::init(ARGV, oml_opts) do |op|
  op.banner = "Usage: #{$0} [options] host1 host2 ...\n"

  op.on( '-i', '--interval SEC', "Query interval in seconds [#{interval}]" ) do |i|
    interval = i.to_i
  end
  op.on( '-s', '--service-url URL', "Zabbix service url [#{zabbix_opts[:url]}]" ) do |u|
    zabbix_opts[:url] = p
  end
  op.on( '-p', '--password PW', "Zabbix password [#{zabbix_opts[:password]}]" ) do |p|
    zabbix_opts[:password] = p
  end
  op.on( '-u', '--user USER', "Zabbix user name [#{zabbix_opts[:user]}]" ) do |u|
    zabbix_opts[:user] = u
  end
end
if nodes.empty?
  OML4R.logger.error "Missing host list"
  OML4R::close()
  exit(-1)
end

# connect to Zabbix JSON API
zbx = ZabbixApi.connect(zabbix_opts)

# catch CTRL-C
exit_requested = false
Kernel.trap( "INT" ) { exit_requested = true }

# poll Zabbix API
while !exit_requested
  nodes.each{|n|
    # https://www.zabbix.com/documentation/2.0/manual/appendix/api/item/get
    results = zbx.query(
      :method => "item.get",
      :params => {
        :output => "extend",
        :host => "#{n}",
        # only interested in CPU load
        :search => {
          :name => "Processor load"
        }
      }
    )
    unless results.empty?
      l15 = results[0]["lastvalue"]
      l1 = results[1]["lastvalue"]
      l5 = results[2]["lastvalue"]
      #puts "Injecting values #{l1}, #{l5}, #{l15} for node #{n}"
      # injecting measurements into OML
      CPU_MP.inject(Time.now.to_s, n, l1, l5, l15)
    else
      OML4R.logger.warn "Empty result usually means misspelled host address"
    end
  }
  sleep interval
end

OML4R::close()
puts "Exiting"
