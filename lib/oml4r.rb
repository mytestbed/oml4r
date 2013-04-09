# Copyright (c) 2009 - 2012 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of the MIT license (License).
# You should find a copy of the License in LICENSE.TXT or at http://opensource.org/licenses/MIT.
# By downloading or using this software you accept the terms and the liability disclaimer in the License.
# ------------------
#
# = oml4r.rb
#
# == Description
#
# This is a simple client library for OML which does not use liboml2 and its
# filters, but connects directly to the server using the +text+ protocol.
# User can use this library to create ruby applications which can send
# measurement to the OML collection server.
#
require 'socket'
require 'monitor'
require 'thread'
require 'optparse'

require 'oml4r/version'

#
# This is the OML4R module, which should be required by ruby applications
# that want to collect measurements via OML
#
module OML4R

  DEF_SERVER_PORT = 3003
  DEF_PROTOCOL = 3

  # Overwrite the default logger
  #
  # @param logger Needs to respond to 'debug', 'info', ...
  #
  def self.logger=(logger)
    @@logger = logger
  end
  
  class OML4RExeption < Exception; end
  class MissingArgumentException < OML4RExeption; end
  class ArgumentMismatchException < OML4RExeption; end
  #
  # Measurement Point Class
  # Ruby applications using this module should sub-class this MPBase class
  # to define their own Measurement Point (see the example at the end of
  # this file)
  #
  class MPBase

    # Some Class variables
    @@defs = {}
    @@channels = {}
    @@frozen = false
    @@useOML = false
    @@start_time = nil

    # Execute a block for each defined MP
    def self.each_mp(&block)
      @@defs.each(&block)
    end

    # Set the useOML flag. If set to false, make 'inject' a NOOP
    def self.__useOML__()
      @@useOML = true
    end

    # Returns the definition of this MP
    def self.__def__()
      unless (defs = @@defs[self])
        defs = @@defs[self] = {}
        defs[:p_def] = []
        defs[:seq_no] = 0
      end
      defs
    end

    # Set a name for this MP
    def self.name(name)
      __def__()[:name] = name
    end

    # Set the channel these measurements should be sent out on.
    # Multiple declarations are allowed, and ':default' identifies
    # the channel defined by the command line arguments or environment variables.
    #
    def self.channel(channel, domain = :default)
      (@@channels[self] ||= []) << [channel, domain]
    end

    # Set a metric for this MP
    # - name = name of the metric to set
    # - opts = a Hash with the options for this metric
    #          Only supported option is :type = { :string | :int32 | :double }
    def self.param(name, opts = {})
      o = opts.dup
      o[:name] = name
      o[:type] ||= :string
      case o[:type] 
      when :long
        OML4R.logger.warn ":long is deprecated use, :int32 instead"
        o[:type] = :int32
      when :boolean
        o[:type] = :int32  # TODO: Hopefully we can remove this soon
      end
      __def__()[:p_def] << o
      nil
    end

    # Inject a measurement from this Measurement Point to the OML Server
    # However, if useOML flag is false, then only prints the measurement on stdout
    # - args = a list of arguments (comma separated) which correspond to the
    #          different values of the metrics for the measurement to inject
    def self.inject(*args)
      return unless @@useOML

      # Check that the list of values passed as argument matches the
      # definition of this Measurement Point
      defs = __def__()
      pdef = defs[:p_def]
      types = defs[:types]
      if args.size != pdef.size
        raise ArgumentMismatchException.new "OML4R: Size mismatch between the measurement (#{args.size}) and the MP definition (#{pdef.size})!"
      end

      # Now prepare the measurement...
      t = Time.now - @@start_time
      a = []
      a << (defs[:seq_no] += 1)
      args.each_with_index do |arg, i|
        case types[i]
        when :string
          # Escape tabs and newlines
          arg = arg.to_s.gsub("\n", "\\n").gsub("\t", "\\t")
        when :boolean
          # boolean
          arg = arg ? 1 : 0
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

    def self.start_time()
      @@start_time
    end

    # Freeze the definition of further MPs
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
        cna = @@channels[klass] || []
        OML4R.logger.debug "'#{cna.inspect}', '#{klass}'"
        ca = cna.collect do |cname, domain|
          # return it in an array as we need to add the channel specific index
          [Channel[cname.to_sym, domain.to_sym]]
        end
        OML4R.logger.debug "Using channels '#{ca.inspect}"
        @@channels[klass] = ca.empty? ? [[Channel[]]] : ca
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
    def self.__print_meta__(name_prefix = nil)
      return unless @@frozen
      defs = __def__()

      # Do some sanity checks...
      unless (mp_name = defs[:name])
        raise MissingArgumentException.new "Missing 'name' declaration for '#{self}'"
      end
      unless (name_prefix.nil?)
        mp_name = "#{name_prefix}_#{mp_name}"
      end

      @@channels[self].each do |ca|
        OML4R.logger.debug "Setting up channel '#{ca.inspect}"
        index = ca[0].send_schema(mp_name, defs[:p_def])
        ca << index
      end
    end
  end # class MPBase



  #
  # The Init method of OML4R
  # Ruby applications should call this method to initialise the OML4R module
  # This method will parse the command line argument of the calling application
  # to extract the OML specific parameters, it will also do the parsing for the
  # remaining application-specific parameters.
  # It will then connect to the OML server (if requested on the command line), and
  # send the initial instruction to setup the database and the tables for each MPs.
  #
  # - argv = the Array of command line arguments from the calling Ruby application
  # - & block = a block which defines the additional application-specific arguments
  #
  def self.init(argv, opts = {}, &block)
    OML4R#{VERSION_STRING} [#{COPYRIGHT}")

    if d = (ENV['OML_EXP_ID'] || opts[:expID])
      # XXX: It is still too early to complain about that. We need to be sure
      # of the nomenclature before making user-visible changes.
      OML4R.logger.warn "opts[:expID] and ENV['OML_EXP_ID'] are getting deprecated; please use opts[:domain] or ENV['OML_DOMAIN']  instead"
      opts[:domain] ||= d
    end
    domain ||= ENV['OML_DOMAIN'] || opts[:domain]

    # XXX: Same as above; here, though, :id might actually be the way to go; or
    # perhaps instId?
    #if opts[:id]
    #  raise 'OML4R: :id is not a valid option. Do you mean :nodeID?'
    #end
    nodeID = ENV['OML_NAME'] || opts[:nodeID]  ||  opts[:id] || ENV['OML_ID']
    #
    # XXX: Same again; also, this is the responsibility of the developer, not the user
    #if opts[:app]
    #  raise 'OML4R: :app is not a valid option. Do you mean :appName?'
    #end
    appName = opts[:appName] || opts[:app]
    protocol = opts[:protocol] = DEF_PROTOCOL

    if  ENV['OML_URL'] || opts[:omlURL] || opts[:url]
      raise MissingArgumentException.new 'neither OML_URL, :omlURL nor :url are valid. Do you mean OML_COLLECT or :omlCollect?'
    end
    if ENV['OML_SERVER'] || opts[:omlServer]
        OML4R.logger.warn "opts[:omlServer] and ENV['OML_SERVER'] are getting deprecated; please use opts[:collect] or ENV['OML_COLLECT'] instead"
    end
    omlCollectUri = ENV['OML_COLLECT'] || ENV['OML_SERVER'] || opts[:collect] || opts[:omlServer]
    noop = opts[:noop] || false


    # Create a new Parser for the command line
    op = OptionParser.new
    # Include the definition of application's specific arguments
    yield(op) if block
    # Include the definition of OML specific arguments
    op.on("--oml-id id", "Name to identify this app instance [#{nodeID || 'undefined'}]") { |name| nodeID = name }
    op.on("--oml-domain domain", "Name of experimental domain [#{domain || 'undefined'}] *EXPERIMENTAL*") { |name| domain = name }
    op.on("--oml-collect uri", "URI of server to send measurements to") { |u|  omlCollectUri = u }
    op.on("--oml-protocol p", "Protocol number [#{OML4R::DEF_PROTOCOL}]") { |l| protocol = l.to_i }
    op.on("--oml-log-level l", "Log level used (info: 1 .. debug: 0)") { |l| OML4R.logger.level = l.to_i }
    op.on("--oml-noop", "Do not collect measurements") { noop = true }
    op.on("--oml-exp-id domain", "Obsolescent equivalent to --oml-domain domain") { |name|
      domain = name
      OML4R.logger.warn "Option --oml-exp-id is getting deprecated; please use '--oml-domain #{domain}' instead"
    }
    op.on("--oml-file localPath", "Obsolescent equivalent to --oml-collect file:localPath") { |name|
      omlCollectUri = "file:#{name}"
      OML4R.logger.warn "Option --oml-file is getting deprecated; please use '--oml-collect #{omlCollectUri}' instead"
    }
    op.on("--oml-server uri", "Obsolescent equivalent to --oml-collect uri") {|u|
      omlCollectUri = u
      OML4R.logger.warn "Option --oml-server is getting deprecated; please use '--oml-collect #{omlCollectUri}' instead"
    }
    op.on_tail("--oml-help", "Show this message") { $stderr.puts op; exit }
    # XXX: This should be set by the application writer, not the command line
    #op.on("--oml-appid APPID", "Application ID for OML [#{appName || 'undefined'}] *EXPERIMENTAL*") { |name| appID = name }

    # Now parse the command line
    OML4R.logger.debug "ARGV:>>> #{argv.inspect}"
    rest = op.parse(argv)
    return if noop

    unless nodeID
      begin
        # Create a default nodeID by concatinating the local hostname with the process ID
        hostname = nil
        begin 
          hostname = Socket.gethostbyname(Socket.gethostname)[0]
        rescue Exception 
          begin
            hostname = `hostname`
          rescue Exception; end           
        end
        if hostname
          nodeID = "#{hostname}-#{Process.pid}"
        end
      end
      unless nodeID
        raise MissingArgumentException.new 'OML4R: Missing values for parameter :nodeID (--oml-id)'        
      end
    end
    
    unless domain && appName
      raise MissingArgumentException.new 'OML4R: Missing values for parameters :domain (--oml-domain), :nodeID (--oml-id), or :appName (in code)!'
    end

    # Set a default collection URI if nothing has been specified
    omlCollectUri ||= "file:#{appName}_#{nodeID}_#{domain}_#{Time.now.strftime("%Y-%m-%dt%H.%M.%S%z")}"

    create_channel(:default, omlCollectUri) if omlCollectUri

    # Handle the defined Measurement Points
    startTime = Time.now
    Channel.init_all(domain, nodeID, appName, startTime, protocol)
    OML4R.logger.info "Collection URI is #{omlCollectUri}"
    rest || []
  end
  
  def self.create_channel(name, url)
    Channel.create(name, url)
  end

  #
  # Close the OML collection. This will block until all outstanding data have been sent out.
  #
  def self.close()
    Channel.close_all
  end



  #
  # Measurement Point Class
  # Ruby applications using this module should sub-class this MPBase class
  # to define their own Measurement Point (see the example at the end of
  # this file)
  #
  class Channel
    @@channels = {}
    @@default_domain = nil
    
    

    def self.create(name, url, domain = :default)
      key = "#{name}:#{domain}"
      if channel = @@channels[key]
        if url != channel.url
          raise OML4RException.new "OML4R: Channel '#{name}' already defined with different url"
        end
        return channel
      end
      return self._create(key, domain, url)
    end

    def self._create(key, domain, url)
      out = _connect(url)
      @@channels[key] = self.new(url, domain, out)
    end

    def self._connect(url)
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
      out
    end

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

      MPBase.__freeze__(appName, startTime)

      # send channel header
      @@channels.values.each { |c| c.init(nodeID, appName, startTime, protocol) }

      # send schema definitions
      MPBase.each_mp do |klass, defs|
        klass.__print_meta__(appName)
      end

      MPBase.__useOML__()
    end

    def self.close_all()
      @@channels.values.each { |c| c.close }
      @@channels = {}
      MPBase.__unfreeze__()
    end

    attr_reader :url

    def send_schema(mp_name, pdefs) # defs[:p_def]
      # Build the schema and send it
      @index += 1
      #line = ['schema:', @index, mp_name]
      line = [@index, mp_name]
      pdefs.each do |d|
        line << "#{d[:name]}:#{d[:type]}"
      end
      msg = line.join(' ')
      @schemas << msg
      @index
    end

    def send(msg)
      @queue.push msg
    end

    def init(nodeID, appName, startTime, protocol)
      @nodeID, @appName, @startTime, @protocol = nodeID, appName, startTime, protocol
    end

    def close()
      @queue.push nil  # indicate end of work
      @runner.join()
    end

    protected
    def initialize(url, domain, out_channel)
      @domain = domain
      @url = url
      @out = out_channel
      @index = 0
      @schemas = []
      @header_sent = false
      @queue = Queue.new
      start_runner
    end


    def _send_protocol_header(stream)
      header = []
      header << "protocol: #{@protocol}"
      header << "content: text"
      d = (@domain == :default) ? @@default_domain : @domain
      raise MissingArgumentException.new "Missing domain name" unless d
      case @protocol || OML4R::DEF_PROTOCOL
      when 3
        header << "experiment-id: #{d}"
        header << "start_time: #{@startTime.tv_sec}"
        header << "sender-id: #{@nodeID}"
        header << "app-name: #{@appName}"
        @schemas.each do |s|
          header << "schema: #{s}"
        end
        header << ""        
      when 4
        i = 0
        header << ""        
        header << "0\t0\t#{i += 1}\t.\texperiment-id\t#{d}"
        header << "0\t0\t#{i += 1}\t.\tstart_time\t#{@startTime.tv_sec}"
        header << "0\t0\t#{i += 1}\t.\tsender-id\t#{@nodeID}"
        header << "0\t0\t#{i += 1}\t.\tapp-name\t#{@appName}"
        @schemas.each do |s|
          header << "0\t0\t#{i += 1}\t.\tschema\t#{s}"
        end
        
      else
        raise OML4RException.new "Unsupported protocol #{@protocol}"
      end
      stream.puts header
    end

    def start_runner
      header_sent = false
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
            @out = self.class._connect(@url)
            @header_sent = false
            OML4R.logger.info "Reconnected to '#{@url}'"
            return _send(msg)
          rescue Errno::ECONNREFUSED => ex
            OML4R.logger.warn "Exception while reconnect '#{@url}' (#{ex.class})"
          end
          #Errno::ECONNREFUSED
        end
      end
    end

  end # Channel
  
  require 'logger'
  
  class Logger < ::Logger
    def format_message(severity, time, progname, message)
      "%5s oml4r: %s\n" % [severity, message]
    end
  end
  
  @@logger = Logger.new(STDERR)
  @@logger.level = ::Logger::INFO
  
  def self.logger
    @@logger
  end
  
  
end # module OML4R

# vim: sw=2
