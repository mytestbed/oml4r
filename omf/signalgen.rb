# Copyright (c) 2014 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of
# the MIT license (License).  You should find a copy of the License in
# COPYING or at http://opensource.org/licenses/MIT. By downloading or
# using this software you accept the terms and the liability disclaimer
# in the License.
#

defApplication('signalgen') do |a|
  a.binary_path = "/usr/local/bin/signalgen"
  a.description = "A simple signal generator reporting values into OML"

  a.defProperty('frequency', 'Signal frequency [Hz]', '-f', :type => :numeric)
  a.defProperty('increment', 'Increment angle between samples [rad]', '-i', :type => :numeric)
  a.defProperty('samples', 'Number of samples to generate', '-n', :type => :numeric)

  a.defMeasurement('sin') do |m|
    m.defMetric('label', :string)
    m.defMetric('angle', :int32)
    m.defMetric('value', :double)
  end

  a.defMeasurement('cos') do |m|
    m.defMetric('label', :string)
    m.defMetric('value', :double)
  end
end

# Example use with OMF v6:
#
# loadOEDL('https://raw.githubusercontent.com/mytestbed/oml4r/master/omf/signalgen.rb')
#
# defProperty('res1', "test1", "ID of a node")
#
# defGroup('Generator', property.res1) do |node|
#   node.addApplication("signalgen") do |app|
#     app.setProperty('samples', 10)
#     app.measure('sin', samples: 1)
#   end
# end
#
# onEvent(:ALL_UP_AND_INSTALLED) do
#   info "Starting a remote signal generator"
#   allGroups.startApplications
#
#   after 30 do
#     allGroups.stopApplications
#     Experiment.done
#   end
# end
# 
# defGraph 'Sine' do |g|
#   g.ms('sin').select {[ oml_ts_client.as(:ts), :value ]}
#   g.caption "Generated Sine Signal"
#   g.type 'line_chart3'
#   g.mapping :x_axis => :ts, :y_axis => :value
#   g.xaxis :legend => 'time [s]'
#   g.yaxis :legend => 'Sine Signal', :ticks => {:format => 's'}
# end

