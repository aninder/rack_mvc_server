require 'fileutils'
module RackMvcServer
  class Worker
    include RackMvcServer::Const
    attr_reader :register, :number
    def initialize(master_pid, application, socket, register, number,logger)
      @master_pid = master_pid
      @application = application
      @socket     = socket
      @register   = register
      @number     = number
      @logger     = logger
    end
    def start
      $PROGRAM_NAME = "mvc server worker #{@number}"
      master_handler = trap('INT') {
        @logger.info "received INT exiting...."
        @socket.close
        exit(0)
      }
      while @master_pid == Process.ppid do
        #  select() and poll() tell us whether an I/O operation would not block,
        # rather than whether it would successfully transfer data.
        #
        # if Incoming connection established on socket, then socket desciptor in the
        # reading queue returns
        # reading socket also returns when some input is available
        new_connection = IO.select([@socket], nil, nil, WORKER_MAX_TIME_ON_CLIENT_REQUEST / 2)
        # @logger.info "select returned  #{new_connection}"
        FileUtils.touch @register
        if new_connection
          begin
          #if there's nothing in the queue then accept would block.
          # In this situation accept_nonblock would raise an Errno::EAGAIN rather
          #than blocking.
          client = @socket.accept_nonblock
            env = setup_env(client.recvmsg)
            response = @application.call(env)
            send_response_to_client(client, response)
            @logger.info("sent response for path #{env['PATH_INFO']}")
            client.close
          rescue Errno::EAGAIN
          end
        end
        FileUtils.touch @register
      end
      @logger.info "master has died , so exiting"
      @socket.close rescue nil
    end
    def ==(other_number)
      @number == other_number
    end
    def setup_env(sock_message)
      env = Hash.new
      get = sock_message[0].split("\n").first
      get.match("GET ([^ ]+).*$")
      env['PATH_INFO']=$1
      return env
    end
    def send_response_to_client(connection, response)
      if response.kind_of?Array
        connection.puts "HTTP/1.1 #{response[0]}\n"
        response[1].each do |k,v|
          connection.puts "#{k}: #{v} \n"
        end
        response[2].each do |body|
          connection.puts("\n#{body}")
        end
      else
        connection.puts "HTTP/1.1 #{response.status}\n"
        response.headers.each do |k,v|
          connection.puts "#{k}: #{v} \n"
        end
        response.body.each do |body|
          connection.puts("\n#{body}")
        end
      end
    end
  end
end
