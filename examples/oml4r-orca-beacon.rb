#!/usr/bin/env ruby

# Observes network connectivity on ORCA slices
# Sends UDP broadcast messages and reports incoming messages via OML
# (including its own) to build a connectivity graph

require 'rubygems'
require 'eventmachine'
require 'oml4r'
require 'system/getifaddrs'

port = 9089
interval = 10
ip_addresses = []
NAME = ENV['OML_ID']
oml_opts = {:appName => 'beacon', :collect => 'file:-'}

abort "Please set the OML_ID environment variable" if NAME.nil?

System.get_ifaddrs.each do |ip|
  # don't report IP address of loopback interface
  next if ip[0]==:lo
  ip_addresses << ip[1][:inet_addr]
end

class MyMP < OML4R::MPBase
  name :received
  param :receiver_name, :type => :string
  param :sender_name, :type => :string
  param :ip_addresses, :type => :string
end

OML4R::init(ARGV, oml_opts) do |op|
  op.banner = "Usage: #{$0} [options]\n"
  op.on( '-i', '--interval n', "Send UDP broadcast beacon every n seconds [#{interval}]" ) do |i|
    interval = i.to_i
  end
end

module ServerSocket
    def receive_data data
        d=eval(data)
        return if d.class != Hash
        # don't log my own beacons
        MyMP.inject(NAME, d[:sender_name], d[:ip_addresses]) if NAME != d[:sender_name] 
    end
end

EventMachine.run {
    socket = EventMachine.open_datagram_socket "0.0.0.0", port, ServerSocket
    EventMachine.add_periodic_timer(interval) {
      socket.send_datagram({:sender_name => NAME, :ip_addresses=> ip_addresses.join(' ')}, "255.255.255.255", port)
    }
}

OML4R::close()
