
module OML4R
  #
  # Measurement Channel
  #
  class Channel

    def push(msg, is_schema = false)
      @schemas << msg if is_schema
      @queue.push msg
    end

    def initialize(url, domain, node_id, app_name, start_time)
      @domain = domain
      @url = url
      @nodeId = node_id
      @appName = app_name
      @startTime = start_time
      @schemas = []
      @queue = Queue.new

      start_runner
    end

    def close()
      @queue.push nil  # indicate end of work
      @runner.join()
    end

    # Parse the given fully-qualified collection URI, and return a suitably connected objet
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
    def _connect()
      scheme, host, port = @url.split(':')
      @out = case scheme
            when 'tcp'
              port ||= DEF_SERVER_PORT
              out = TCPSocket.new(host, port)
            when 'file'
              # host is really a filename here
              out = (host == '-' ? $stdout : File.open(host, "w+"))
            else
              raise OML4RException.new "OML4R: Unknown scheme '#{scheme}"
            end
      _send_protocol_header()
      @out
    end

    def _send_protocol_header()
      header = []
      header << "protocol: #{@protocol || DEF_PROTOCOL}"
      header << "content: text"
      case @protocol || OML4R::DEF_PROTOCOL
      when 4
        header << "domain: #{@domain}"
        header << "start-time: #{@startTime.tv_sec}"
        header << "sender-id: #{@nodeID}"
        header << "app-name: #{@appName}"
        header << "schema: 0 _experiment_metadata subject:string key:string value:string"
        header << ""
        if @schemas.empty?
          header << "" # force newline. Requires a second empty one at the end of the array
        else
          @schemas.each {|s| header << s}
        end
      else
        raise OML4RException.new "Unsupported protocol #{@protocol}"
      end
      _send header.join("\n")
    end

    def start_runner
      _connect()
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
        OML4R.logger.info "Channel #{@url} closed"
      end
    end

    def _send(msg)
      begin
        @out.puts msg
        @out.flush
      rescue Errno::EPIPE
        # Trying to reconnect
        OML4R.logger.info "Trying to reconnect to '#{@url}'"
        loop do
          sleep 5
          begin
            _connect()
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
end # module
