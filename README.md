OML4R: Native OML Implementation in Ruby			{#oml4rdoc}
========================================

This is a simple client library for OML which does not use liboml2 and its
filters, but connects directly to the server using the text protocol [oml-text].
User can use this library to create ruby applications which can send
measurement to the OML collection server. A simple example on how to use
this library is attached at the end of this file. Another example can be
found in the file oml4r-example.rb

Installation
------------

OML4R is available from RubyGems [oml4r-rubygem].

    $ gem install oml4r


Usage
-----

### Definition of a Measurement Point

    class MyMP < OML4R::MPBase
      name :mymp
    
      param :mystring
      param :myint, :type => :int32
      param :mydouble, :type => :double
    end

### Initialisation, Injection and Tear-down

    OML4R::init(ARGV, 
    	:appName => 'oml4rSimpleExample',
    	:domain => 'foo', 
    	:nodeID => 'n1',
    )
    MyMP.inject("hello", 13, 37.1)
    OML4R::close()
    
### Multiple Channels

It is sometimes desirable to send different measurement points to different collectors. OML4R supports
this with the 'channel' abstraction.

    class A_MP < OML4R::MPBase
      name :a
      channel :default
    
      param :a_val, :type => :int32
    end

    class B_MP < OML4R::MPBase
      name :b
      channel :archive
      channel :default
    
      param :b_val, :type => :int32
    end
    
    OML4R::init(ARGV, 
      :appName => 'doubleAgent',
      :domain => 'foo' 
    )
    OML4R::create_channel(:archive, 'file:/tmp/archive.log')    

Setting the command line flag '--oml-collect' will define a ':default' channel. Any additional channels
need to be declared with 'OML4R::create_channel' which takes two arguments, the name of the channel
and the destination for the measurement stream. The above example defines an 'archive' channel
which is being collected in the local '/tmp/archive.log' file.

Please note that by declaring a specific channel, every MP needs at least one channel declaration.

### Real example

See examples files oml4r-simple-example.rb and oml4r-wlanconfig.rb.

[oml-text]: http://oml.mytestbed.net/projects/oml/wiki/Description_of_Text_protocol
[oml4r-rubygem]: https://rubygems.org/gems/oml4r/
