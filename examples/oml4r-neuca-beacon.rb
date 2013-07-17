#!/usr/bin/env ruby

# Observes network connectivity on ExoGENI slices
# Sends UDP broadcast messages and reports incoming messages via OML
# (including its own) to build a connectivity graph

require 'rubygems'
require 'eventmachine'
require 'oml4r'
require 'parseconfig'

port = 9089
interval = 10
neuca_file = "/tmp/neuca-user-data.txt"

abort "Could not run 'neuca-user-data'" if !`neuca-user-data > #{neuca_file}`
neuca_user_data = ParseConfig.new(neuca_file)['global']

class MyMP < OML4R::MPBase
  name :received
  param :actor_id, :type => :string
  param :slice_id, :type => :string
  param :reservation_id, :type => :string
  param :unit_id, :type => :string
end

oml_opts = {:appName => 'beacon', :domain => neuca_user_data['slice_id'],
  :nodeID => neuca_user_data['unit_id'], :collect => 'file:-'}

node = OML4R::init(ARGV, oml_opts) do |op|
  op.banner = "Usage: #{$0} [options]\n"
  op.on( '-i', '--interval n', "Send UDP broadcast beacon every n seconds [#{interval}]" ) do |i|
    interval = i.to_i
  end
end

module ServerSocket
    def receive_data data
        d=eval(data)
        return if d.class != Hash
        MyMP.inject(d['actor_id'], d['slice_id'], d['reservation_id'], d['unit_id'])
    end
end

EventMachine.run {
    socket = EventMachine.open_datagram_socket "0.0.0.0", port, ServerSocket
    EventMachine.add_periodic_timer(interval) {
      socket.send_datagram(neuca_user_data, "255.255.255.255", port)
    }
}

OML4R::close()
