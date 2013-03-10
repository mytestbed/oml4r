# Copyright (c) 2009 - 2012 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of the MIT license (License).
# You should find a copy of the License in LICENSE.TXT or at http://opensource.org/licenses/MIT.
# By downloading or using this software you accept the terms and the liability disclaimer in the License.
# ------------------
#
# = test_types.rb
#
# == Description
#
# Testing blobs and long strings. Should really go into a test suite.
#
require 'rubygems'
require 'oml4r'

# Define your own Measurement Points
class TestMP < OML4R::MPBase
  name :test
  #channel :default

  param :text
  param :blob, :type => :blob
end

# Initialise the OML4R module for your application
opts = {:appName => 'test_types',
  :domain => 'foo', :nodeID => 'n1',
  :collect => 'file:-'} 

OML4R::init(ARGV, opts)

# Now collect and inject some measurements
blob = ""
30.times {|i| blob << i}
TestMP.inject(%{tab new line
another two

and that's it}, blob)

# Don't forget to close when you are finished
OML4R::close()

# vim: sw=2
