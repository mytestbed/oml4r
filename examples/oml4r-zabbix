#!/usr/bin/env ruby

# example script that reads CPU load measurements from a Zabbix server
# and pushes them into an OML database

# make sure you install these two gems
require "zabbixapi"
require "oml4r"

# Zabbix node names
nodes = ["10.129.16.11", "10.129.16.12", "10.129.16.13"]

# Define your own Measurement Point
class MyMP < OML4R::MPBase
  name :CPU
  param :ts, :type => :string  
  param :node, :type => :string    
  param :load1, :type => :double
  param :load5, :type => :double
  param :load15, :type => :double 
end

# connect to Zabbix JSON API
zbx = ZabbixApi.connect(
  :url => 'http://cloud.npc.nicta.com.au/zabbix/api_jsonrpc.php',
  :user => 'Admin',
  :password => 'zabbix'
)

# Initialise the OML4R module for your application
opts = {:appName => 'zabbix',
  :expID => 'zabbix-cpu-measurement', :nodeID => 'cloud',
  :omlServer => 'tcp:norbit.npc.nicta.com.au:3003'}
OML4R::init(nil, opts)

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
    l15=results[0]["lastvalue"]
    l1=results[1]["lastvalue"]
    l5=results[2]["lastvalue"]
    puts "Injecting values #{l1}, #{l5}, #{l15} for node #{n}"
    # injecting measurements into OML
    MyMP.inject(Time.now,n,l1,l5,l15)
  }
  sleep 1
end

OML4R::close()
puts "Exiting"
