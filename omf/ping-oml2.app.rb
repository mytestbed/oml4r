#
# Copyright 2012-2014 National ICT Australia (NICTA)
#
# This software may be used and distributed solely under the terms of
# the MIT license (License).  You should find a copy of the License in
# COPYING or at http://opensource.org/licenses/MIT. By downloading or
# using this software you accept the terms and the liability disclaimer
# in the License.
#
defApplication('oml:app:ping', 'ping') do |a|

  # a.version(2, 9, 0) # Deprecated in OMF6
  a.description = %{This application runs the system ping, parses its output and
reports the measurements via OML
  }
  a.binary_path = "/usr/local/bin/ping-oml2"

  a.defProperty('dest_addr', 'Address to ping', nil,
		:type => :string)
  a.defProperty('count', 'Number of times to ping', '-c',
		:type => :integer)
  a.defProperty('interval', 'Interval between echo requests', '-i',
		:type => :integer, :unit => "seconds")
  a.defProperty('quiet', 'Don\'t show ping output on the console', '-q',
		:type => :boolean)
  a.defProperty('inet6', 'Use ping6 rather than ping', '-6',
		:type => :boolean)

  a.defMeasurement('ping') do |m|
    m.defMetric('dest_addr',:string)
    m.defMetric('ttl',:uint32)
    m.defMetric('rtt',:double)
    m.defMetric('rtt_unit',:string)
  end

  a.defMeasurement('summary') do |m|
    m.defMetric('ntransmitted',:uint32)
    m.defMetric('nreceived',:uint32)
    m.defMetric('lossratio',:double)
    m.defMetric('runtime',:double)
    m.defMetric('runtime_unit',:string)
  end

  a.defMeasurement('rtt_stats') do |m|
    m.defMetric('min',:double)
    m.defMetric('avg',:double)
    m.defMetric('max',:double)
    m.defMetric('mdev',:double)
    m.defMetric('rtt_unit',:string)
  end
end

# Example use with OMF:
#defProperty('source', "node1-1.grid.orbit-lab.org", "ID of a resource")
#defProperty('sink', "node1-2.grid.orbit-lab.org", "ID of a resource")
#defProperty('sinkaddr', 'node1-2.grid.orbit-lab.org', "Ping destination address")
#
#defGroup('Source', property.source) do |node|
#  node.addApplication("oml:app:ping") do |app|
#    app.setProperty('dest_addr', property.sinkaddr)
#    app.setProperty('count', 5)
#    app.setProperty('interval', 1)
#    app.measure('ping', :samples => 1)
#  end
#end
#
#defGroup('Sink', property.sink) do |node|
#end
#
#onEvent(:ALL_UP_AND_INSTALLED) do |event|
#  info "Starting the ping"
#  group('Source').startApplications
#  wait 6
#  info "Stopping the ping"
#  group('Source').stopApplications
#  Experiment.done
#end

# Local Variables:
# mode:ruby
# End:
# vim: ft=ruby:sw=2
