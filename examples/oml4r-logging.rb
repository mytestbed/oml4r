#!/usr/bin/env ruby
 
require 'oml4r/logging/oml4r_appender'
 
appender = Logging.appenders.oml4r('oml4r',
  :appName => 'log-tester',
  :domain => 'foo',
  :collect => 'file:-')
 
log = Logging.logger[self]
log.add_appenders 'oml4r'
 
log.info 'Info Message'
log.debug 'Debug Message'
log.info ({:a => 1, :b => 2, :c => 3})

appender.close
