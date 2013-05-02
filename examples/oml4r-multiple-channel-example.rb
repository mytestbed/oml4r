# Copyright (c) 2013 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of the MIT license (License).
# You should find a copy of the License in LICENSE.TXT or at http://opensource.org/licenses/MIT.
# By downloading or using this software you accept the terms and the liability disclaimer in the License.
# ------------------
#
# = oml4r-multiple-channel-example.rb
#
# == Description
#
# An extension of the 'oml4r-simple.example.rb' example demonstrating the use of
# multiple destinations for different measurements.
#
# == Usage
#
# The following write the COS measurements to STDOUT (file:-) and the SIN 
# measurements to /tmp/ch2.oml (which can be overwrriten with the --oml-ch2 option)
#
# % cd $OML_HOME
# % ruby -I lib examples/oml4r-multiple-channel-example.rb --oml-ch1 file:-
#
# Use --oml-help to get all available options
#
# % cd $OML_HOME
# % ruby -I lib examples/oml4r-multiple-channel-example.rb --oml-help
# 
require 'rubygems'
require 'oml4r'

# Define your own Measurement Points
class SinMP < OML4R::MPBase
  name :sin
  channel :ch1

  param :label
  param :angle, :type => :int32
  param :value, :type => :double
end

class CosMP < OML4R::MPBase
  name :cos
  channel :ch2

  param :label
  param :value, :type => :double
end

# Initialise the OML4R module for your application
opts = {
  :appName => 'oml4rSimpleExample',
  :domain => 'foo',
  :create_default_channel => false  # we don't need the default channel
} 
#  
ch1 = OML4R::create_channel(:ch1, 'file:/tmp/ch1.oml')    
ch2 = OML4R::create_channel(:ch2, 'file:/tmp/ch2.oml')    

begin
  OML4R::init(ARGV, opts) do |op|
    op.on("--oml-ch1 URL", "Set destination for Channel 1 [#{ch1.url}]") { |url| ch1.url = url }
    op.on("--oml-ch2 URL", "Set destination for Channel 2 [#{ch2.url}]") { |url| ch2.url = url }
  end
rescue OML4R::MissingArgumentException => mex
  $stderr.puts mex
  exit
end

# Now collect and inject some measurements
500.times do |i|
  sleep 0.5
  angle = 15 * i
  SinMP.inject("label_#{angle}", angle, Math.sin(angle))
  CosMP.inject("label_#{angle}", Math.cos(angle))    
end

# Don't forget to close when you are finished
OML4R::close()

# vim: sw=2
