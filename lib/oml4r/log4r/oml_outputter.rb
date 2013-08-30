# Copyright (c) 2013 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of the MIT license (License).
# You should find a copy of the License in LICENSE.TXT or at http://opensource.org/licenses/MIT.
# By downloading or using this software you accept the terms and the liability disclaimer in the License.
# ------------------
#
# = oml_outputter.rb
#
# == Description
#
# Log4r outputter which turn logging events into an OML stream
#

require 'log4r/outputter/outputter'
require 'oml4r'
require 'time'

module Log4r

  # Log4r outputter which turn logging events into an OML stream
  #
  class OmlOutputter < Log4r::Outputter

    class LogEventMP < OML4R::MPBase
      name :log #, add_prefix: false

      param :level, :type => :int32
      param :name
      param :tracer
      param :data
    end

    # Initialise an outputter which turns logging messages
    # into an OML stream
    #
    # param name Name of outputter
    # param opts Options for setting up OML
    # opts collect If set to an URL, then initialise OML otherwise assume that someone else is doing it
    # opts domain OML domain to send to (assumes that 'collect' is set) ['log']
    # opts appName OML domain to send to (assumes that 'collect' is set) [fileName-time-pid]
    #
    def initialize(name, opts = {})
      super(name, opts)
      if url = opts['collect']
        h = {}
        opts.each {|k, v| h[k.to_sym] = v}
        opts = h

        opts[:domain] ||= 'log'
        opts[:appName] ||= File.basename(__FILE__, '.*')
        opts[:id] ||= "#{Socket.gethostname}-#{Time.now.iso8601}-#{Process.pid}"
        OML4R.init(nil, opts)
      end
    end

    def closed?
      false
    end

    def close
      # OutputterFactory.create_methods(self)
      # Logger.log_internal {"Outputter '#{@name}' closed Syslog and set to OFF"}
    end

    private

    def canonical_log(le)
      LogEventMP.inject le.level, le.fullname, le.tracer || '', le.data || ''
    end
  end
end


if __FILE__ == $0
  require 'log4r'
  require 'log4r/configurator'
  require 'log4r/yamlconfigurator'
  require 'yaml'

  yf = %{
log4r:

  # define all loggers ...
  loggers:
    - name      : production
      level     : DEBUG
      trace     : 'false'
      outputters:
        - oml
  outputters:
    - name    : oml
      type    : OmlOutputter
      collect : file:-
}

  ycfg = YAML.load yf
  #puts ycfg['log4r'].inspect
  ::Log4r::YamlConfigurator.decode_yaml(ycfg['log4r'])



  log = ::Log4r::Logger['production']
  log.info 'test'
  log.debug 'test2'

  log2 = Log4r::Logger.new 'production::foo'
  log2.debug 'debugging!'

  sleep 2

end