#!/usr/bin/env ruby

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

# Use the oml4r.rb from ../lib
$:.unshift "#{File.dirname(__FILE__)}/../lib"

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
  argv = OML4R::init(ARGV, opts)
rescue OML4R::MissingArgumentException => mex
  OML4R.logger.error "oml4r-simple-example: #{mex}"
  exit
end

freq = 2.0 # Hz
inc = 15 # rad

# Now collect and inject some measurements
SinMP.inject_metadata "unit", "radian", "angle"
SinMP.inject_metadata "freq_Hz", "#{freq}"
SinMP.inject_metadata "inc_rad", "#{inc}"
CosMP.inject_metadata "freq_Hz", "#{freq}"
CosMP.inject_metadata "inc_rad", "#{inc}"
(argv[0] || 500).to_i.times do |i|
  sleep 1./freq
  angle = inc * i
  SinMP.inject("label_#{angle}", angle, Math.sin(angle))
  CosMP.inject("label_#{angle}", Math.cos(angle))
end

# Don't forget to close when you are finished
OML4R::close()

# vim: sw=2
