require 'logging'
require 'oml4r'
require 'time'

module Logging::Appenders

  def self.oml4r *args
    return Logging::Appenders::Oml4r if args.empty?
    Logging::Appenders::Oml4r.new(*args)
  end

  class Oml4r < Logging::Appender

    class LogMP < OML4R::MPBase
      name :log
      param :time, :type => :string
      param :level, :type => :int32
      param :logger, :type => :string
      param :data, :type => :string
      param :file, :type => :string
      param :line, :type => :int32
      param :method, :type => :string
    end

    # pass a name and the usual OML options here to configure oml4r
    def initialize *args
      opts = Hash === args.last ? args.pop : {}
      name = args.empty? ? 'oml4r' : args.shift
      super(name, opts)
      begin
        OML4R::init(nil, opts)
      rescue OML4R::MissingArgumentException => mex
        $stderr.puts mex
        exit
      end
      @inject_failed = false
    end

    def close *args
      super(false)
      OML4R::close()
    end

    private

    def write(event)
      begin
        LogMP.inject(event.time.iso8601, event.level.to_i, event.logger,
                      event.data, event.file, event.line.to_i, event.method)
      rescue => ex
        # Complain only once
        unless @inject_failed
          $stderr.puts "ERROR: While sending logging message via OML4r - #{mex}"
          @inject_failed = true
        end
      end
      self
    end

  end # class Oml4r
end # module
