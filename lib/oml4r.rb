# Copyright (c) 2009 - 2013 National ICT Australia Limited (NICTA).
#
# This software may be used and distributed solely under the terms of
# the MIT license (License).  You should find a copy of the License in
# LICENSE.TXT or at http://opensource.org/licenses/MIT.  By
# downloading or using this software you accept the terms and the
# liability disclaimer in the License.
#
# = oml4r.rb
#
# == Description
#
# This is a simple client library for OML which does not use liboml2
# and its filters, but connects directly to the server using the
# +text+ protocol.  User can use this library to create ruby
# applications which can send measurement to the OML collection
# server.
#

require 'logger'
require 'monitor'
require 'optparse'
require 'securerandom'
require 'set'
require 'singleton'
require 'socket'
require 'thread'

require 'oml4r/version'


# This is the OML4R module, which should be required by ruby
# applications that want to collect measurements via OML
#
module OML4R

  DEF_SERVER_PORT = 3003
  DEF_PROTOCOL = 4

  class OML4RException < Exception; end
  class MissingArgumentException < OML4RException; end
  class ArgumentMismatchException < OML4RException; end


  # The OML4R logger.
  #
  class Logger < ::Logger
    def format_message(severity, time, progname, message)
      "%s\t%s\n" % [severity, message]
    end
  end

  # Initialize the OML4R.logger.
  #
  @@logger = Logger.new(STDERR)
  @@logger.level = ::Logger::INFO

  # Return the default logger.
  #
  # @return 
  #
  def OML4R.logger
    @@logger
  end

  # Overwrite the default logger.
  #
  # @param logger Needs to respond to 'debug', 'info', ...
  #
  def OML4R.logger=(logger)
    @@logger = logger
  end


  # OML Client.
  #
  class OMLClient

    include Singleton

    attr_reader :start_time

    # Configure the OMLClient.
    #
    def configure(argv, opts)
      if :instantiated == @state
        # FIXME: remember opts{:appname} (insist it is provided!)
        # get the config file and command line flags
        path, args = parse_args(argv, opts)
        cfg = path ? parse_config_file(path, [:experiment, :domain, :id, :url]) : {}
        # configure this OMLClient
        id = get_config_value(:id, [], cfg, :oml_id, [] , args, default_node_id)
        domain = get_config_value(:domain, [:experiment], cfg, :oml_domain, [:oml_exp_id], args, nil)
        collect_uri = get_config_value(:url, [], cfg, :oml_collect, [:oml_server, :oml_file], args, default_uri(opts[:appName], id, domain))
        # create the default channel
        @defaultChan = create_channel(:default, collect_uri)
        OML4R.logger.info "Default collection URI is #{collect_uri]}"
        @state = :configured
      elsif :configured == @state
        raise OML4RException.new "OML4R: already configured"
      end
    end

    # Start this OML Client.
    #
    def start
      if :instantiated == @state
        raise OML4RException.new "OML4R: "
      elsif :configured == @state
        # FIXME: connect all defined channels
        @startTime = Time.now
        @state = :running
      elsif :running == @state
        raise OML4RException.new "OML4R: "
      end
    end

    # Stop this OML Client.
    #
    def stop
      if :instantiated == @state
        raise OML4RException.new "OML4R: "
      elsif :configured == @state
        # FIXME: stop all channels (???) (may not be running)
        # FIXME: do I need to tell MPs? Yes, so we move back into defining state
        # FIXME: forget configuration
        @start_time = 0
        @state = :instantiated
      elsif
        raise OML4RException.new "OML4R: "       
      end
    end

    # Create a named channel. If the client is not configured then the
    # channel will be connected when configure is called. Otherwise it
    # is connected immediately. 
    #
    def create_channel(name, uri)   
      if :instantiated == @state
        ch = Channel[name]
        ch.uri = uri
        @@channels << @state
      elsif :configured == @state
        ch = Channel[name]
        ch.uri = uri
        ch.connect
        @@channels << @state
      end
    end

    # Tests whether this OMLClient is running.
    #
    def isRunning?
      return (:running == @state)
    end

    private    

    # Initialize this OMLClient.
    #
    def initialize
      @state = :instantiated
      @appName = nil
      @protocol = nil
      @startTime = 0
      @defaultChan = nil
      OML4R.logger.info "OML4R Client #{VERSION} [OMSPv#{opts[:protocol] || DEF_PROTOCOL}; Ruby #{RUBY_VERSION}] #{COPYRIGHT}"
    end

    # Parse the command line.
    #
    # param argv [String]
    #
    def parse_args(argv, opts)
      omlConfigFile = nil
      opts = {}
      noop = false
      if argv
        # Create a new Parser for the command line
        op = OptionParser.new

        # include the definition of application's specific arguments
# FIXME:
#        yield(op) if block

        # include the definition of OML specific arguments
        op.on("--oml-id id", "Name to identify this app instance [#{opts[:nodeID] || 'undefined'}]") { |name| opts[:oml_id] = name }
        op.on("--oml-domain domain", "Name of experimental domain [#{opts[:domain] || 'undefined'}] *EXPERIMENTAL*") { |name| opts[:oml_domain] = name }
        op.on("--oml-collect uri", "URI of server to send measurements to") { |u|  opts[:oml_collect] = u }
        op.on("--oml-protocol p", "Protocol number [#{OML4R::DEF_PROTOCOL}]") { |l| opts[:protocol] = l.to_i }
        op.on("--oml-log-level l", "Log level used (info: 0 .. debug: 1)") { |l| OML4R.logger.level = 1 - l.to_i }
        op.on("--oml-noop", "Do not collect measurements") { noop = true }
        op.on("--oml-config file", "File holding OML configuration parameters") { |f| omlConfigFile = f }

        # deprecated options
        op.on("--oml-exp-id domain", "Obsolescent equivalent to --oml-domain domain") { |name| opts[:oml_exp_id] = name }
        op.on("--oml-file localPath", "Obsolete equivalent to --oml-collect file:localPath") { |name| opts[:oml_file] = "file:#{name}" }
        op.on("--oml-server uri", "Obsolescent equivalent to --oml-collect uri") {|u| opts[:oml_server] = "#{u}" }
        op.on_tail("--oml-help", "Show this message") { $stderr.puts op; exit }

        # parse the command line
        rest = op.parse(argv)
        if opts[:afterParse]
          # give the app a chance to fix missing parameters
          opts[:afterParse].call(opts)
        end
        OML4R.logger.debug "ARGV: #{argv.inspect}"
      end
      (omlConfigFile, opts, noop)
    end
      
    # Parse the OML config file.
    #
    # param path [String] = the config file's path
    # param keys [Array of symbols] = list of symbols to extract
    # return [Map] = a map from config symbols to values
    # 
    def parse_config_file(path, keys)
      results = {}
      unless path.nil? 
        f = File.open(path, 'r')
        f.each_line do |l|
          keys.each do |k|
            s = k.to_s
            m = l[/.*#{s}=["']([^"']*)/, 1]
            opts[k] = m if m
          end
        end
        f.close
      end
      results.freeze
    end

    # Get a config value. OML searches the config file, command
    # line and the process environment to find a match. If none is
    # found a MissingArgumentException is raised.
    #
    # param
    def get_config_value(cfg, depr_cfgs, cfgs, arg, depr_args, args, default_val)
      # config file
      val = cfgs[cfg]
      return val unless val.nil?
      depr_cfgs.each {|depr_cfg|
        val = cfgs[depr_cfg] and OML4R.logger.warn "Configuration '#{depr_cfg.to_s}' is deprecated; please use '#{cfg.to_s}' instead"
        return val unless val.nil?
      }
      # command line
      val = args[arg]
      return val unless val.nil?
      depr_args.each {|depr_arg|
        val = args[depr_arg] and  OML4R.logger.warn "Option '--#{depr_arg.to_s}' is deprecated; please use '--#{arg.to_s}' instead"
        return val unless val.nil?
      }
      # process environment
      env_name = arg.to_s.upcase
      val = ENV[env_name]
      return val unless val.nil?
      # assume the default
      val = default_val
      return val unless val.nil?
      raise MissingArgumentException.new "OML4R: Missing values for parameter #{arg_name} ('--#{arg_name}')"
    end

    # Get the client's hostname.
    #
    def get_hostname
      begin
        hostname = Socket.gethostname
      rescue Exception
        begin
          hostname = (`hostname`).chop
        rescue Exception
          hostname = nil
        end
      end
      hostname
    end

    # Returns the default nodeID. This is formed by concatinating the
    # client's hostname and the process ID.
    #
    def default_node_id
      hostname = get_hostname
      hostname ? "#{hostname}-#{Process.pid}" : nil
    end

    # Set a default collection URI if nothing has been specified
    #
    def default_uri(app_name, node_id, domain)
      "file:#{app_name}_#{node_id}_#{domain}_#{Time.now.strftime("%Y-%m-%dt%H.%M.%S%z")}"
    end

  end # OMLClient


  # Measurement Point
  #
  class MeasurementPoint

    @@mps = {}

    TYPES = [:string, :long, :int32, :uint32, :int64, :uint64, :double, :bool, :guid].to_set

    STATES = [:defining, :complete ]

    # Retrieve MeasurementPoint instance for a given class.
    # @param klass The class for which we want a MeasurementPoint 
    # @return [MeasurementPoint] A non-nil MeasurementPoint reference.
    #
    def MeasurementPoint.[](klass)
      unless mp = @@mps[klass]
        mp = MeasurementPoint.new
        mp.schema_no = @@mps.size
        @@mps[klass] = mp
      end
      mp
    end

    # Initialize a MeasurementPoint instance
    #
    def initialize
      @name = nil
      @state = :defining
      @schema_no = 0
      @schema = []
      @schema_defs = {}
      @sequence_no = 0
      @channel = {}
      @channel_names = []
    end

    # set the name for this MeasurementPoint
    #
    def name=(name)
      if :defining == @state
        @name = name
      else 
        raise OML4RException.new "OML4R: cannot set name"
      end
    end

    # set the schema number for this MeasurementPoint
    #
    def schema_no=(schema_no)
      if :defining == @state
        @schema_no = schema_no
      else 
        raise OML4RException.new "OML4R: cannot set schema_no"
      end
    end

    # add a parameter to this MeasurementPoint
    #
    def add_param(param)
      if :defining == @state
        # FIXME check type is member of TYPES
        @schema_defs << param
      else 
        raise OML4RException.new "OML4R: cannot add parameter"
      end
    end

    # add a channel to this MeasurementPoint
    #
    def add_channel(chan)
      if :defining == @state
        @channels << chan
      else 
        raise OML4RException.new "OML4R: cannot add channel"
      end
    end

    # state-changing calls

    def connect()
      
      # is name defined
      # are there any channels? are they defined?
      # is there a schema?

      if :defining == @state
        # do actions
        @state = :connecting
      else
      end

    end

    def inject_metadata(start_time, schema, key, value, fname = nil)
      # retrieve infos
      defs = @@defs[self]
      mp_name_def = defs[:name]
      mp_name = mp_name_def[:name]
      pdefs = defs[:p_def]
      defs[:types] = pdefs.map {|h| h[:type]}

      # construct the subject reference
      subject = "."
      if self != OML4R::ExperimentMetadata
        subject +=  "#{@@appName}_#{mp_name}"
        unless fname.nil?
          subject += ".#{fname}"
        end
      end

      # prepare the message header
      a = []
      a << Time.now - @@start_time
      a << "0"
      a << (defs[:meta_no] += 1)
      a << subject
      a << key
      a << value
      msg = a.join("\t")

      # Setup channels for the ExperimentMetadata MP
      chans = @@channels[self] || []
      if chans.empty?
        @@channels[self] = [[Channel[], 0]]
      end

      # now inject the schema
      # @@channels[self].each do |ca|
      #   channel = ca[0]
      #   index = ca[1]
      #   channel.send msg
      # end
    end

    def inject(*args)
      defs = __def__()

      # FIXME: compare the schema types against the argument types
      # validate(args, schema)

      # Do we need to send the schema?
      if :defining == @state
        # Identify MP details
        mp_name_def = defs[:name]
        mp_name = mp_name_def[:name]
        pdefs = defs[:p_def]
        defs[:types] = pdefs.map {|h| h[:type]}
        # Setup channel and schema
        channel = Channel[]
        schema_info = channel.build_schema(mp_name, mp_name_def[:opts][:add_prefix], pdefs)
        @@channels[self] = [[channel, schema_info[0]]]
        # Inject it!
        ExperimentMetadata.inject_metadata("schema", schema_info[1])
        @state = :complete
      end

      # Check that the list of values passed as argument matches the
      # definition of this Measurement Point
      pdef = defs[:p_def]
      types = defs[:types]
      if args.size != pdef.size
        raise ArgumentMismatchException.new "OML4R: Size mismatch between the measurement (#{args.size}) and the MP definition (#{pdef.size})!"
      end

      # prepare the measurement...
      t = Time.now - @@start_time
      a = []
      a << (defs[:seq_no] += 1)
      args.each_with_index do |arg, i|
        case types[i]
        when :double
          arg = "NaN" if arg.nil?
        when :string
          # Escape tabs and newlines
          arg = arg.to_s.gsub("\\", "\\\\").gsub("\r", "\\r").gsub("\n", "\\n").gsub("\t", "\\t")
        when :bool
          # Convert boolean value to appropriate literal
          arg = arg ? "True" : "False"
        when :blob
          arg = [arg].pack("m")
        end
        a << arg
      end
      # ...and inject it!
      msg = a.join("\t")
      @@channels[self].each do |ca|
        channel = ca[0]
        index = ca[1]
        channel.send "#{t}\t#{index}\t#{msg}"
      end
      args
    end

    # Freeze the definition of this MeasurementPoint
    #
    def self.__freeze__(appName, start_time)
      return if @@frozen
      @@frozen = true
      # create type array for easier processing in inject
      @@defs.each do |name, descr|
        descr[:types] = descr[:p_def].map {|h| h[:type]}
      end
      
      # replace channel names with channel object
      self.each_mp do |klass, defs|
        names = @@channelNames[klass] || []
        OML4R.logger.debug "'#{names.inspect}', '#{klass}'"
        chans = names.collect do |cname, domain|
          # return it in an array as we need to add the channel specific index
          [Channel[cname.to_sym, domain.to_sym]]
        end
        OML4R.logger.debug "Using channels '#{chans.inspect}"
        @@channels[klass] = chans.empty? ? [[Channel[], 0]] : chans
      end
      @@start_time = start_time
    end

    def self.__unfreeze__()
      self.each_mp do |klass, defs|
        defs[:seq_no] = 0
      end
      @@channels = {}
      @@start_time = nil
      @@frozen = false
    end
    
    # Build the table schema for this MP and send it to the OML collection server
    # - name_prefix = the name for this MP to use as a prefix for its table
    def self.__puts_meta__(name_prefix = nil)
      return unless @@frozen
      defs = __def__()

      # Do some sanity checks...
      unless True
        raise MissingArgumentException.new "Missing 'name' declaration for '#{self}'"
      end

      # Build the schema
      mp_name = mp_name_def[:name]
      @@channels[self].each do |ca|
        OML4R.logger.debug "Setting up channel '#{ca.inspect}"
        schema_info = ca[0].build_schema(mp_name, mp_name_def[:opts][:add_prefix], defs[:p_def])
        ca << schema_info[0]
      end
    end

    def build_schema(mp_name, add_prefix, pdefs)
      # @index += 1
      # line = [@index, (!@@appName.nil? && add_prefix)? "#{@@appName}_#{mp_name}" : mp_name]
      # pdefs.each do |d|
      #   line << "#{d[:name]}:#{d[:type]}"
      # end
      # msg = line.join(' ')
      # @schemas << msg
      # [@index, msg]
    end

    def to_s()
      # write the class definition again
      "FIXME: to_s conversion for MP"
    end

    # execute a block for each defined MP (is this necessary?)
    def each_mp(&block)
      @@defs.each(&block)    
    end

  end # MeasurementPoint


  # Measurement Channel
  #
  class Channel

    @@channels = {}

    # the renamed create method
    def self.[](name = :default, domain = :default)
      key = "#{name}:#{domain}"
      unless (@@channels.key?(key))
        # If domain != :default and we have one for :default, create a new one
        if (domain != :default)
          if (dc = @@channels["#{name}:default"])
            return self._create(key, domain, dc.url)
          end
        end
        raise OML4RException.new "OML4R: Unknown channel '#{name}'"
      end
      @@channels[key]
    end

    def self.init_all(domain, nodeID, appName, startTime, protocol)
      @@default_domain = domain
      @@nodeID = nodeID
      @@appName = appName
      @@startTime = startTime
      @@protocol = protocol

      MPBase.__freeze__(appName, startTime)

      # send channel header
      @@channels.values.each { |c| c.init(nodeID, appName, startTime, protocol) }

      # send schema definitions
      MPBase.each_mp do |klass, defs|
        klass.__puts_meta__(appName)
      end

      MPBase.__useOML__()
    end

    def self.close_all()
      @@channels.values.each { |c| c.close }
      @@channels = {}
      MPBase.__unfreeze__()
    end

    attr_reader :url

    def url=(url)

      qualify_uri(uri)

      return if @url == url
      if @out
        raise "Can't change channel's URL when it is already connected"
      end
      @url = url
    end

    def send(msg)
      @queue.push msg
    end

    def send_schema_update(msg)
      @header_sent = true
      @queue.push msg
    end

    def init(nodeID, appName, startTime, protocol)
      @nodeID, @appName, @startTime, @protocol = nodeID, appName, startTime, protocol
      @out = _connect(@url)
    end

    def close()
      @queue.push nil  # indicate end of work
      @runner.join()
    end

    private

    # Parse the given fully-qualified collection URI, and return a suitably connected object
    #
    # Supported URIs are
    #  tcp:host:port
    #  file:/P/A/T/H
    #
    # @param fquri [String] a fully qualified collection URI
    # @return [IO] an object suitably connected to the required URL
    #
    # @raise [OML4RException] in case of an unknown scheme
    #
    def self._connect(fquri)
      scheme, host, port = fquri.split(':')
      out = case scheme
            when 'tcp'
              out = TCPSocket.new(host, port)
            when 'file'
              # host is really a filename here
              out = (host == '-' ? $stdout : File.open(host, "w+"))
            else
              raise OML4RException.new "OML4R: Unknown scheme '#{scheme}"
            end
      out
    end

    def initialize(url, domain)
      @domain = domain
      @url = url
      @index = -1
      @schemas = []
      @header_sent = false
      @queue = Queue.new
      start_runner
    end


    # Parse an underspecified URI into a fully-qualified one
    # URIs are resolved as follows; the default is [tcp:]host[:port].
    #  hostname		-> tcp:hostname:3003
    #  hostname:3004	-> tcp:hostname:3004
    #  tcp:hostname	-> tcp:hostname:3003
    #  tcp:hostname:3004	-> tcp:hostname:3004
    #  file:/P/A/T/H	-> file:/P/A/T/H
    #
    # @param uri [String] a potentially under-qualified collection URI
    #
    # @return [String] a fully-qualified collection URI equivalent to uri
    #
    # @raise [OML4RException] in case of a parsing error
    #
    def qualify_uri(uri)
      curi = uri.split(':')

      # Defaults
      scheme = 'tcp'
      port = DEF_SERVER_PORT

      if curi.length == 1
        host = curi[0]

      elsif curi.length == 2
        if curi[0] == 'tcp'
          scheme, host = curi

        elsif  curi[0] == 'file'
          scheme, host = curi
          port = nil

        else
          host, port = curi
        end

      elsif curi.length >= 3
        if curi.length > 3
          OML4R.logger.warn "Parsing URI '#{uri}' as a triplet, ignoring later components"
        end
        scheme, host, port = curi
        
      else
        raise OML4RException.new "OML4R: Unable to parse URI '#{url}"
      end
      "#{scheme}:#{host}#{":#{port}" if port}"
    end


    def _connect(url)
      if url.start_with? 'file:'
        proto, fname = url.split(':')
        out = (fname == '-' ? $stdout : File.open(fname, "w+"))
      elsif url.start_with? 'tcp:'
        #tcp:norbit.npc.nicta.com.au:3003
        proto, host, port = url.split(':')
        port ||= DEF_SERVER_PORT
        out = TCPSocket.new(host, port)
      else
        raise OML4RException.new "OML4R: Unknown transport in server url '#{url}'"
      end
      @out = out
    end


    def _send_protocol_header(stream)
      header = []
      header << "protocol: #{@protocol}"
      header << "content: text"
      d = (@domain == :default) ? @@default_domain : @domain
      raise MissingArgumentException.new "Missing domain name" unless d

      case @protocol || OML4R::DEF_PROTOCOL
      when 4
        header << "domain: #{d}"
        header << "start-time: #{@startTime.tv_sec}"
        header << "sender-id: #{@nodeID}"
        header << "app-name: #{@appName}"
        @schemas.each do |s|
          header << "schema: #{s}"
        end
        header << ""
      else
        raise OML4RException.new "Unsupported protocol version #{@protocol}"
      end
      stream.print header
    end

    def start_runner
      @runner = Thread.new do
        active = true
        begin
          while (active)
            msg = @queue.pop
            active = !msg.nil?
            if !@queue.empty?
              ma = [msg]
              while !@queue.empty?
                msg = @queue.pop
                if (active = !msg.nil?)
                  ma << msg
                end
              end
              msg = ma.join("\n")
            end
            #$stderr.puts ">>>>>>#{@domain}: <#{msg}>"
            unless msg.nil?
              _send msg
            end
          end
          @out.close unless @out == $stdout
          @out = nil
        rescue Exception => ex
          OML4R.logger.warn "Exception while sending message to channel '#{@url}' (#{ex})"
        end
        OML4R.logger.info "Channel #{url} closed"
      end
    end

    def _send(msg)
      begin
        unless @header_sent
          _send_protocol_header(@out)
          @header_sent = true
        end
        @out.puts msg
        @out.flush

      rescue Errno::EPIPE
        # Trying to reconnect
        OML4R.logger.info "Trying to reconnect to '#{@url}'"
        loop do
          sleep 5
          begin
            @out = _connect(@url)
            @header_sent = false
            OML4R.logger.info "Reconnected to '#{@url}'"
            return _send(msg)
          rescue Errno::ECONNREFUSED => ex
            OML4R.logger.warn "Exception while reconnect '#{@url}' (#{ex.class})"
          end
        end
      end
    end

  end # Channel

  # Public API
  #

  # Superclass for Measurement Point definitions. Ruby applications
  # using this module should sub-class this MPBase class to define
  # their own Measurement Point (see the example at the end of this
  # file which is used to define the ExperimentMetadata).
  #
  class MPBase

    # Define the name for this measurement point.
    #
    # param name String naming this MP
    # param opts A map specifying MP options 
    #   opts:add_prefix Add app name as prefix to table name (default=true)
    #
    def MPBase.name(name, opts = {})

      # ensure name is non-nil
      # ensure opts is non-nil

      # everyone is prefixed unless they opt out
      if opts[:add_prefix].nil?
        opts[:add_prefix] = true
      end

      # set the MP name
      mp = MeasurementPoint[self]
      mp.name = name, opts

    end

    # Define a channel these measurements should be sent out on.
    # Multiple declarations are allowed, and ':default' identifies
    # the channel defined by the command line arguments or environment variables.
    #
    def MPBase.channel(name, domain = :default)

      # FIXME: check args
      # FIXME: mapping from names to default channel

      # add channel to the MeasurementPoint
      mp = MeasurementPoint[self]
      mp.add_channel(name, domain)

    end

    # This'd be nice if there was a read-only accessor!?
    # @@scalar_types = [:string, :int32, :uint32, :int64, :uint64, :double, :bool, :guid].to_set
    # @@vector_types = [:vector_int32, :vector_uint32, :vector_int64, :vector_uint64, :vector_double, :vector_bool].to_set    

    # Add a metric for this MP
    # - name = name of the metric to set
    # - opts = a Hash with the options (at present the only supported option is :type) for this metric
    #
    def MPBase.param(name, opts = {})

      # FIXME: ensure name is non-nil
      # ensure opts is non-nil

      mp = MeasurementPoint[self]
      p = opts.dup
      p[:name] = name
      p[:type] ||= :string

      # handle deprecated types
      if :long == p[:type]
        OML4R.logger.warn ":long is deprecated use, :int32 instead"
        p[:type] = :int32
      end

      mp.add_param(p)

    end

    # Inject a metadata measurement from this Measurement Point to the OML Server. 
    #
    # - key = a string used to identify the key
    # - value = the string value
    # - fname = when not nil a string used to qualify the subject name
    #
    def MPBase.inject_metadata(key, value, fname = nil)
      unless OMLClient.instance.isConfigured?
        # raise an exception
      end
      mp = MeasurementPoint[self]
      mp.inject_metadata(key, value, fname)
    end

    # Inject a measurement from this Measurement Point to the OML Server.
    #
    # We don't know the schema is complete until the first measurement
    # is injected and so we do the schema update at that point.
    # If there is a problem connecting to a channel then we put the measurement to stdout
    #
    # - args = a list of arguments (comma separated) which correspond to the
    #          different values of the metrics for the measurement to inject
    def MPBase.inject(*args)
      unless OMLClient.instance.isConfigured?
        # raise an exception
      end
      mp = MeasurementPoint[self]
      mp.inject(args)
    end

  end # class MPBase


  # The Init method of OML4R.
  #
  # Ruby applications should call this method to initialise the OML4R
  # module This method will parse the command line argument of the
  # calling application to extract the OML specific parameters, it
  # will also do the parsing for the remaining application-specific
  # parameters.
  #
  # Any connections to the OML Server that have been fully specified
  # prior to this function being called will be made and the initial
  # schema exchanged. Both MP and Channel definitions can occur after
  # Init() is called and so we lazily instantiate those channels
  # during the first inject() call (at which time both the MP and
  # channel definitions must, perforce, be complete).
  #
  # param argv = the Array of command line arguments from the calling Ruby application
  # param opts
  # opts [String]  :domain
  # opts [String]  :nodeID
  # opts [String]  :appName
  # opts [Integer] :protocol
  # opts [Proc] :afterParse
  # param block = a block which defines the additional application-specific arguments
  #
  def OML4R.init(argv, opts = {}, &block)
    OMLClient.instance.configure(argv, opts, block)
    OMLClient.instance.start
  end

  # Close the OML connection. This will block until all outstanding data have been sent out.
  #
  def OML4R.close()
    OMLClient.instance.stop
    OMLClient.instance.cleanup
  end

  # Generate a random GUID
  #
  # @return [BigNum] An integer GUID.
  #
  def OML4R.generate_guid()
    SecureRandom.random_number(2**64)
  end

  # Create a channel and associate with the specified id.
  # uri [String] a potentially under-qualified collection URI
  # Returns [Channel] a
  #
  def OML4R.create_channel(name, uri)
    OMLClient.instance.create_channel(name, uri)
  end

  # Define the MeasurementPoint for "schema 0". We use this MP for
  # recording metadata and for sendnig schema updates to the OML
  # Server.
  #
  class ExperimentMetadata < MPBase
    name :_experiment_metadata, :add_prefix => false
    param :subject, :type => :string
    param :key, :type => :string
    param :value, :type => :string    
  end


end # module OML4R

# vim: sw=2
