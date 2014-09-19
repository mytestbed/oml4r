

module OML4R
  #
  # Measurement Point Class
  # Ruby applications using this module should sub-class this MPBase class
  # to define their own Measurement Point (see the example at the end of
  # this file)
  #
  class MPBase

    # Some Class variables
    @@useOML = false

    Def = Struct.new(:name, :p_defs, :domain_name, :domain_context)
    PDef = Struct.new(:name, :type, :opts)
    NDef = Struct.new(:name, :opts)
    @@defs = {}

    # Set a name for this MP
    #
    # param opts Options
    # opts add_prefix Add app name as prefix to table. Default: true
    #
    def self.name(name, opts = {})
      opts[:add_prefix] ||= true
      __def__().name = NDef.new(name, opts)
    end

    # Set the domain name these measurements should be collected under.
    # Only the last declaration is kept and it defaults to ':default'
    #
    def self.domain(domain = :default)
      __defs__().domain_name = domain
    end


    # Set a metric for this MP
    # - name = name of the metric to set
    # - opts = a Hash with the options for this metric
    #          Only supported option is :type = { :string | :int32 | :uint32 | :int64 | :uint64 | :double | :bool | :guid |
    #          [ DEPRECATED :long | :integer ] }
    def self.param(name, opts = {})
      type = opts[:type] || :string
      if type == :long || type == :integer
        # XXX: :name in :name... See #1527 bullet point 3
        OML4R.logger.warn "Type #{type} for #{__def__().name[:name]}.#{o[:name]} is deprecated, use :int32 instead"
        type = :int32
      end

      pd = PDef.new(name, type, opts)
      __def__().p_defs << pd
      nil
    end

    # Inject a metadata measurement from this Measurement Point ot the OML Server.
    # - key = a string used to identify the key
    # - value = the string value
    # - fname = when not nil a string used to qualify the subject name
    def self.inject_metadata(key, value, fname = nil)
      return unless @@useOML

      mdef = __def__()
      unless (ctxt = mdef.domain_context)
        ctxt = mdef.domain_context = OML4R::domain_context(mdef.domain_name || :default)
      end
      ctxt.inject_metadata(key, value, fname, mdef, self == OML4R::ExperimentMetadata)
      nil
    end

    # Inject a measurement from this Measurement Point to the OML Server
    # However, if useOML flag is false, then only prints the measurement on stdout
    # - args = a list of arguments (comma separated) which correspond to the
    #          different values of the metrics for the measurement to inject
    #
    def self.inject(*args)
      return unless @@useOML

      mdef = __def__()
      unless (ctxt = mdef.domain_context)
        ctxt = mdef.domain_context = OML4R::domain_context(mdef.domain_name || :default)
      end
      ctxt.inject(args, mdef)
    end

    # # Execute a block for each defined MP
    # def self.each_mp(&block)
      # @@defs.each(&block)
    # end

    # Set the useOML flag. If set to false, make 'inject' a NOOP
    def self.__useOML__(flag = true)
      @@useOML = flag
    end

    # Returns the definition of this MP
    def self.__def__()
      defs = @@defs[self] ||= Def.new(nil, [])
    end

  end # class MPBase
end # module
