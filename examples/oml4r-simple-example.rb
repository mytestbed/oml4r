# Copyright (c) 2009 - 2012 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of the MIT license (License).
# You should find a copy of the License in LICENSE.TXT or at http://opensource.org/licenses/MIT.
# By downloading or using this software you accept the terms and the liability disclaimer in the License.
# ------------------
#
# = oml4r-simple-example.rb
#
# == Description
#
# A very simple straightforward example of OML4R.
#
require 'rubygems'
require 'oml4r'

# Define your own Measurement Points
class SinMP < OML4R::MPBase
  name :sin
  #channel :default

  param :label
  param :angle, :type => :int32
  param :value, :type => :double
end

class CosMP < OML4R::MPBase
  name :cos
  # channel :ch1
  # channel :default

  param :label
  param :value, :type => :double
end

# Initialise the OML4R module for your application
opts = {:appName => 'oml4rSimpleExample',
  :domain => 'foo',
  :collect => 'file:-'} # Server could also be tcp:host:port
#  
#OML4R::create_channel(:ch1, 'file:/tmp/foo.log')    

begin
  OML4R::init(ARGV, opts)
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
