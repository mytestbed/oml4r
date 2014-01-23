require 'logging'
require 'oml4r'

module Logging::Appenders

  def self.oml4r *args
    return Logging::Appenders::Oml4r if args.empty?
    Logging::Appenders::Oml4r.new *args
  end

  class Oml4r < Logging::Appender

    class LogMP < OML4R::MPBase
      name :Log
      param :data, :type => :string
      param :file, :type => :string
      param :level, :type => :string
      param :line, :type => :string
      param :logger, :type => :string
      param :method, :type => :string
      param :time, :type => :string
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
    end

    def close *args
      super(false)
      OML4R::close()
    end

    private

    def write(event)
      LogMP.inject(event.data,event.file,event.level,event.line,event.logger,event.method,event.time)
      self
    end

  end # class Oml4r
end # module