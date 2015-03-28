# $LOAD_PATH << temp
# File.open("#{temp}/config.ru","r") do |f|
#   lines = f.readlines
#   lines.grep(/^require/).each do |req|
#    require req.gsub(/(.*)\"(.+)\"/,temp+'\2.rb')
#    #    eval req
#   end
#   puts lines.grep(/\s*run/)[0].gsub("run\s","")
# end
module RackMvcServer
  module Utils
    def setup_env(sock_message)
      env = Hash.new
      get = sock_message[0].split("\n").first
      get.match("GET ([^ ]+).*$")
      env['PATH_INFO']=$1
      return env
    end
  end
  module Appload
    def load_app(config)
      raise ArgumentError, "rackup file (#{config}) not readable" if ! File.readable?(config)
      File.open("config.ru", "r") do |f|
        instance_eval  f.read, f.path
      end
    end
    def map(path)
      puts ".....map NOT IMPLEMENTED YET..."
    end
    def run(obj)
      @application = obj.method(:call).to_proc
    end
    def require_relative(str)
      req = "require '"+Dir.pwd+"/"+str+"'"
      eval(req)
    end
  end
  class Master
    require 'socket'
    require 'yaml'
    require 'net/http'
    require 'rack_mvc_server/const'
    require 'rack_mvc_server/worker'
    require 'mono_logger'
    include Utils
    include Appload
    include RackMvcServer::Const

    SIGNALS = [:WINCH, :QUIT, :INT, :TERM, :USR1, :USR2, :HUP, :TTIN, :TTOU, :CHLD]

    def initialize
      setup_logging
      logger.level = MonoLogger::DEBUG
      logger.info "initializing ..."
      $PROGRAM_NAME = "mvc server master"
      @workers = {}
      load_app("config.ru")
      @socket = TCPServer.open(DEFAULT_HOST, DEFAULT_PORT)
      logger.info("Listening on #{DEFAULT_HOST}: #{DEFAULT_PORT}, Super Master pid  #{Process.ppid}")
    end
    def start
      @signal_queue = []
      setup_signals
      #create preforking model
      logger.info("Spawning #{WORKERS} workers")
      loop do
        signal = @signal_queue.shift
        case signal
          when nil
            spawn_workers
            kill_lazy_workers
            remove_dead_workers
            sleep 2
          when :QUIT, :INT
            logger.info "handling #{signal}"
            kill_each_worker :KILL
            remove_dead_workers
            # When a process terminates(program control flow crosses
            # exit() or return from main) , all of its open files are
            # closed automatically by the kernel. Many programs
            # take advantage of this fact and don't explicitly
            # close open files.
            @socket.close
            break
          when :TTIN, :TTOU
            logger.info "add fun by increasing or decreasing num of workers"
          when :CHLD
            logger.info "oh dear worker , wot u die for ?!"
          else
            logger.info "dummy handle #{signal}"
        end
      end
      logger.info "bye bye from master"
      exit 0
    end

    private
    # signals are asynchronous, process has to leave everything and run the
    # signal handler first(like wake up if it's in sleep state n run the handler)
    # if the process is running signal handler and another signal comes , than it stacks off
    # to run the handler of the latest signal;
    # The signals SIGKILL and SIGSTOP cannot be trapped, blocked, or ignored.
    def setup_signals
      SIGNALS.each do |signal|
        trap(signal) {
          logger.info("got signal #{signal}")
          @signal_queue << signal
        }
      end
    end
    def spawn_workers
      worker_number = -1
      until (worker_number += 1) == WORKERS
        @workers.value?(worker_number) && next
        worker = Worker.new(Process.pid, @application, @socket, work_register, worker_number, logger)
        # It's possible to create copies of file descriptors using Socket#dup .
        # other n common way is through Process.fork
        pid = fork { worker.start }
        logger.info "spawned  worker #{worker_number} with pid #{pid}"
        @workers[pid] = worker
      end
    end
    def kill_lazy_workers
      now = Time.now
      @workers.each_pair do |pid, worker|
        unless (now - worker.register.ctime) <= WORKER_MAX_TIME_ON_CLIENT_REQUEST
          logger.error "worker #{worker.number} (PID:#{pid}) "\
                       "took too long to serve client request"
          kill_worker('HUP', pid)
        end
      end
    end
    def remove_dead_workers
      loop do
        # wait non block
        pid, status = Process.wait2(-1, Process::WNOHANG) || break
        worker = @workers.delete(pid)
        begin
          worker.register.close
          worker.register.unlink
        rescue
          logger.warn "prob while cleaning tempfile"
        end
        logger.info "cleaned up dead worker #{worker.number} " \
                  "(PID:#{pid}) " \
                  "status: #{status.exitstatus}"
      end
    rescue Errno::ECHILD
      logger.warn "no workers left ?!"
    end
    def kill_worker(signal, pid)
      Process.kill(signal, pid)
      # ESRCH --> process doesn’t exist.
    rescue Errno::ESRCH
      logger.info "worker #{pid} not exists, did not receive signal"
      worker = @workers.delete(pid) and worker.close rescue nil
    end
    def kill_each_worker(signal)
      @workers.keys.each { |wpid| kill_worker(signal, wpid) }
    end
    def work_register
      register = Tempfile.new('')
      register.sync = true
      register
    end
    def setup_logging
      $stderr.sync = $stdout.sync = true
      logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{$PROGRAM_NAME} (PID: #{Process.pid})] #{severity} -- #{msg}\n"
      end
    end
    def logger
      @logger || DAEMONIZE ?  @logger ||= MonoLogger.new("server.log") : @logger ||= MonoLogger.new(STDOUT)
    end
  end

  pp = fork {
  Master.new.start
  }
  Process.detach pp
end
