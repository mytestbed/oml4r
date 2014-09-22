# Copyright 2014 National ICT Australia (NICTA)
#
# This software may be used and distributed solely under the terms of
# the MIT license (License).  You should find a copy of the License in
# COPYING or at http://opensource.org/licenses/MIT. By downloading or
# using this software you accept the terms and the liability disclaimer
# in the License.
#
defApplication('oml:app:ntpq', 'ntpq') do |a|

  a.version(2, 10, 4)
  a.shortDescription = "Wrapper around ntpq -p -n"
  a.description = %{This application runs the system ntpq, parses its output and
reports the measurements via OML
  }
  a.path = "/usr/local/bin/ntpq-oml2"

  # XXX: -n and -p are implied, and -i is irrelevant for automated use
  a.defProperty('force-v4', 'Force DNS resolution of following host names on the command line to the IPv4 namespace',
		-4, :type => :boolean)
  a.defProperty('force-v6', 'Force DNS resolution of following host names on the command line to the IPv6 namespace',
		-6, :type => :boolean)
  a.defProperty('count', 'Interactive format command and added to the list of commands to be executed on the specified host',
		'-c', :type => :string)
  # These options are specific to the instrumentation
  a.defProperty('loop-interval', 'Interval between runs (seconds)',
		'-l', :type => :integer, :unit => 'seconds')
  a.defProperty('quiet', 'Don\'t show ntpq output on the console',
		'-q', :type => :boolean)

  a.defMeasurement('ntpq') do |m|
    m.defMetric('rtype',:string)
    m.defMetric('remote',:string)
    m.defMetric('refid',:string)
    m.defMetric('stratum',:uint32)
    m.defMetric('type',:string)
    m.defMetric('when',:uint32)
    m.defMetric('poll',:uint32)
    m.defMetric('reach',:uint32)
    m.defMetric('delay',:double)
    m.defMetric('offset',:double)
    m.defMetric('jitter',:double)
  end

end

# Example use with OMF:
#defProperty('node', "node1-1.grid.orbit-lab.org", "ID of a resource")
#
#defGroup('Source', property.node) do |node|
#  node.addApplication("oml:app:ntpq") do |app|
#    app.setProperty('loop-interval', 10)
#    app.setProperty('quiet', true)
#    app.measure('ntpq', :samples => 1)
#  end
#end
#
#onEvent(:ALL_UP_AND_INSTALLED) do |event|
#  info "Starting ntpq"
#  group('Source').startApplications
#  wait 6
#  info "Stopping ntpq"
#  group('Source').stopApplications
#  Experiment.done
#end

# Local Variables:
# mode:ruby
# End:
# vim: ft=ruby:sw=2
