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

require 'set'
require 'socket'
require 'monitor'
require 'thread'
require 'optparse'
require 'securerandom'

module OML4R; end

require 'oml4r/version'
#require 'oml4r/channel'
require "oml4r/mbase"
require "oml4r/domain_context"


#
# This is the OML4R module, which should be required by ruby applications
# that want to collect measurements via OML
#
module OML4R

  DEF_SERVER_PORT = 3003
  DEF_PROTOCOL = 4

  # Overwrite the default logger
  #
  # @param logger Needs to respond to 'debug', 'info', ...
  #
  def self.logger=(logger)
    @@logger = logger
  end

  class OML4RException < Exception; end
  class MissingArgumentException < OML4RException
    def self.assert(opt_name, opts)
      unless val = opts[opt_name]
        self.new("Missing option '#{opt_name}' in '#{opts}'")
      end
      val
    end
  end
  class ArgumentMismatchException < OML4RException; end

  @@contexts = {}

  def self.domain_context(name)
    @@contexts[name.to_sym]
  end

  def self.create_domain_context(name, opts)
    @@contexts[name.to_sym] = DomainContext.new(opts)
    MPBase.__useOML__
  end

  #
  # The Init method of OML4R
  # Ruby applications should call this method to initialise the OML4R module
  # This method will parse the command line argument of the calling application
  # to extract the OML specific parameters, it will also do the parsing for the
  # remaining application-specific parameters.
  # It will then connect to the OML server (if requested on the command line), and
  # send the initial instruction to setup the database and the tables for each MPs.
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
  def self.init(argv, opts = {}, &block)
    OML4R.logger.info "OML4R Client #{VERSION} [OMSPv#{opts[:protocol] || DEF_PROTOCOL}; Ruby #{RUBY_VERSION}] #{COPYRIGHT}"
    if d = (ENV['OML_EXP_ID'] || opts[:expID])
      # NOTE: It is still too early to complain about that. We need to be sure
      # of the nomenclature before making user-visible changes.
      OML4R.logger.warn "opts[:expID] and ENV['OML_EXP_ID'] are getting deprecated; please use opts[:domain] or ENV['OML_DOMAIN']  instead"
      opts[:domain] ||= d
    end
    opts[:domain] = ENV['OML_DOMAIN'] || opts[:domain]
    opts[:nodeID]  = ENV['OML_NAME'] || opts[:nodeID]  ||  opts[:id] || ENV['OML_ID']
    opts[:appName] ||= opts[:app]
    opts[:protocol] ||= DEF_PROTOCOL

    if  ENV['OML_URL'] || opts[:omlURL] || opts[:url]
      raise MissingArgumentException.new 'neither OML_URL, :omlURL nor :url are valid. Do you mean OML_COLLECT or :omlCollect?'
    end
    if ENV['OML_SERVER'] || opts[:omlServer]
        OML4R.logger.warn "opts[:omlServer] and ENV['OML_SERVER'] are getting deprecated; please use opts[:collect] or ENV['OML_COLLECT'] instead"
    end
    opts[:omlCollectUri] = ENV['OML_COLLECT'] || ENV['OML_SERVER'] || opts[:collect] || opts[:omlServer]
    noop = opts[:noop] || false
    omlConfigFile = opts[:omlConfigFile]
    rest = []

    if argv
      # Create a new Parser for the command line
      op = OptionParser.new
      # Include the definition of application's specific arguments
      yield(op) if block
      # Include the definition of OML specific arguments
      op.on("--oml-id id", "Name to identify this app instance [#{opts[:nodeID] || 'undefined'}]") { |name| opts[:nodeID] = name }
      op.on("--oml-domain domain", "Name of experimental domain [#{opts[:domain] || 'undefined'}] *EXPERIMENTAL*") { |name| opts[:domain] = name }
      op.on("--oml-collect uri", "URI of server to send measurements to") { |u|  opts[:omlCollectUri] = u }
      op.on("--oml-protocol p", "Protocol number [#{OML4R::DEF_PROTOCOL}]") { |l| opts[:protocol] = l.to_i }
      op.on("--oml-log-level l", "Log level used (info: 0 .. debug: 1)") { |l| OML4R.logger.level = 1 - l.to_i }
      op.on("--oml-noop", "Do not collect measurements") { noop = opts[:noop] = true }
      op.on("--oml-config file", "File holding OML configuration parameters") { |f| omlConfigFile = f }
      op.on("--oml-exp-id domain", "Obsolescent equivalent to --oml-domain domain") { |name|
        opts[:domain] = name
        OML4R.logger.warn "Option --oml-exp-id is getting deprecated; please use '--oml-domain #{domain}' instead"
      }
      op.on("--oml-file localPath", "Obsolescent equivalent to --oml-collect file:localPath") { |name|
        opts[:omlCollectUri] = "file:#{name}"
        OML4R.logger.warn "Option --oml-file is getting deprecated; please use '--oml-collect #{opts[:omlCollectUri]}' instead"
      }
      op.on("--oml-server uri", "Obsolescent equivalent to --oml-collect uri") {|u|
        opts[:omlCollectUri] = "#{u}"
        OML4R.logger.warn "Option --oml-server is getting deprecated; please use '--oml-collect #{opts[:omlCollectUri]}' instead"
      }
      op.on_tail("--oml-help", "Show this message") { $stderr.puts op; exit }

      # Now parse the command line
      rest = op.parse(argv) || []
      if opts[:afterParse]
        # give the app a chance to fix missing parameters
        opts[:afterParse].call(opts)
      end
      #OML4R.logger.debug "ARGV: #{argv.inspect}"
    end
    return rest if noop

    # Parameters in OML config file takes precedence
    unless omlConfigFile.nil?
      f = File.open(omlConfigFile, 'r')
      f.each_line do |l|
        d = l[/.*experiment=["']([^"']*)/,1]
        opts[:domain] = d if d
        d = l[/.*domain=["']([^"']*)/,1]
        opts[:domain] = d if d
        i = l[/.*id=["']([^"']*)/,1]
        opts[:nodeID] = i if i
        u = l[/.*url=["']([^"']*)/,1]
        opts[:omlCollectUri] = u if u
      end
      f.close
    end

    # Return if user hasn't set anything (similar to noop)
    return rest unless opts[:domain] || opts[:nodeID] || opts[:omlCollectUri]

    create_domain_context(:default, opts)
    rest
  end

  #
  # Close the OML collection. This will block until all outstanding data have been sent out.
  #
  def self.close()
    MPBase.__useOML__(false)
    @@contexts.values.each {|ctxt| ctxt.close}
    @@contexts = {}
  end

  # Generate a random GUID
  #
  # @return [BigNum] An integer GUID.
  def self.generate_guid()
    SecureRandom.random_number(2**64)
  end


  # def self.create_channel(name, url)
    # OML4R.logger.warn "No longer supported. Create channels on DomainContext instead."
    # #Channel.create(name, url)
  # end

  # Hard-code "schema0" measurement point
  #
  class ExperimentMetadata < MPBase
    name :_experiment_metadata, :add_prefix => false
    param :subject, :type => :string
    param :key, :type => :string
    param :value, :type => :string
  end

  require 'logger'
  class Logger < ::Logger
    def format_message(severity, time, progname, message)
      "%s\t%s\n" % [severity, message]
    end
  end

  @@logger = nil
  def self.logger
    unless @@logger
      @@logger = Logger.new(STDERR)
      @@logger.level = ::Logger::INFO
    end
    @@logger
  end

end # module OML4R

# vim: sw=2
