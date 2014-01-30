
require 'oml4r/channel'

module OML4R
  #
  # Keeps context for a specific measurement domain.
  # Usually there is only one.
  #
  class DomainContext

    #
    # param opts
    # opts [String]  :domain
    # opts [String]  :nodeID
    # opts [String]  :appName
    # opts [Integer] :omlCollectUri
    #
    def initialize(opts)
      @domain = MissingArgumentException.assert(:domain, opts)
      @appName = MissingArgumentException.assert(:appName, opts)
      @noop = opts[:noop] || false

      unless @nodeID = opts[:nodeID] || default_node_id
        raise MissingArgumentException.new 'OML4R: Missing values for parameter :nodeID (--oml-id)'
      end

      @mp_ctxts = {}
      @channels = []
      @start_time = Time.at(Time.now.tv_sec) # ensure usec == 0
      @meta_seq_no = 0

      collectUri = MissingArgumentException.assert(:omlCollectUri, opts)
      if collectUri == 'FILE'
        #collectURI = DEFAULT_FILE_NA<ME
      end
      add_channel(collectUri)
    end

    def close
      @noop = true
      @channels.each {|c| c.close}
      @channels = []
    end

    MPCtxt = Struct.new(:m_def, :schema_id, :seq_no, :meta_seq_no)

    def inject(args, m_def)
      return if @noop
      ctxt = get_context(m_def)

      # Check that the list of values passed as argument matches the
      # definition of this Measurement Point
      pdefs = m_def.p_defs
      if args.size != pdefs.size
        raise ArgumentMismatchException.new "OML4R: Size mismatch between the measurement (#{args.size}) and the MP definition (#{pdefs.size})!"
      end

      # Now prepare the measurement...
      a = [time_stamp, ctxt.schema_id]
      a << (ctxt.seq_no += 1)
      args.each_with_index do |arg, i|
        case pdefs[i].type
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

      send(a)
    end

    def inject_metadata(key, value, fname, mdef, isExpMeta)
      return if @noop
      ctxt = get_context(mdef)

      # construct the subject reference
      subject = "."
      unless isExpMeta
        subject +=  "#{@appName}_#{mdef.name.name}"
        unless fname.nil?
          subject += ".#{fname}"
        end
      end

      a = [time_stamp, 0, @meta_seq_no += 1, subject, key, value]
      send(a)
    end

    def add_channel(collectUri)
      @channels << Channel.new(collectUri, @domain, @nodeID, @appName, @start_time)
    end

    private

    def send(pa, is_schema = false)
      msg = pa.join("\t")
      #puts "SEND>>> #{msg}"
      @channels.each do |channel|
        #puts "CH>>> #{channel}"
        channel.push msg, is_schema
      end
    end

    def get_context(m_def)
      # TODO: Make this thread safe
      ctxt = @mp_ctxts[m_def]
      unless ctxt
        ctxt = @mp_ctxts[m_def] = MPCtxt.new(m_def, @mp_ctxts.length + 1, 0, 0)

        # 1 generator_sin label:string phase:double value:double
        qName = "#{@appName}_#{m_def.name.name}"
        colDescr = m_def.p_defs.map {|pd| "#{pd.name}:#{pd.type}" }
        schemaDescr = [ctxt.schema_id, qName, colDescr.join(' ')].join(' ')
        a = [time_stamp, 0, @meta_seq_no += 1, '.', 'schema', schemaDescr]
        send(a, true)
      end
      return ctxt
    end


    # Parse an underspecified URI into a fully-qualified one
    # URIs are resolved as follows; the default is [tcp:]host[:port].
    #  hostname   -> tcp:hostname:3003
    #  hostname:3004  -> tcp:hostname:3004
    #  tcp:hostname -> tcp:hostname:3003
    #  tcp:hostname:3004  -> tcp:hostname:3004
    #  file:/P/A/T/H  -> file:/P/A/T/H
    #
    # @param uri [String] a potentially under-qualified collection URI
    #
    # @return [String] afully-qualified collection URI equivalent to uri
    #
    # @raise [OML4RException] in case of a parsing error
    #
    def qualify_uri(uri)
      curi = uri.split(':')

      # Defaults
      scheme = 'tcp'
      port = DEF_SERVER_PORT

      case curi.length
      when 1
        host = curi[0]
      when 2
        case curi[0]
        when 'tcp'
          scheme, host = curi
        when 'file'
          scheme, host = curi
          port = nil
        else
          host, port = curi
        end
      when 3
        scheme, host, port = curi
      else
        raise OML4RException.new "OML4R: Unable to parse URI '#{url}"
      end
      "#{scheme}:#{host}#{":#{port}" if port}"
    end

    def default_node_id
      begin
        # Create a default nodeID by concatinating the local hostname with the process ID
        hostname = nil
        begin
          hostname = Socket.gethostname
        rescue Exception
          begin
            hostname = (`hostname`).chop
          rescue Exception; end
        end
        if hostname
          return "#{hostname}-#{Process.pid}"
        end
      end
      return nil
    end

    def time_stamp
      ts = Time.now - @start_time
      '%.6f' % ts
    end
  end # class
end # module
