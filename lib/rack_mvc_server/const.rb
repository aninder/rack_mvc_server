# constants for requests and responses.
module RackMvcServer
    module Const
      # default TCP listen host address (0.0.0.0, all interfaces)
      DEFAULT_HOST = "0.0.0.0"

      # default TCP listen port (8080)
      DEFAULT_PORT = 8080

      # common errors
      ERROR_400_RESPONSE = "HTTP/1.1 400 Bad Request\r\n\r\n"
      ERROR_414_RESPONSE = "HTTP/1.1 414 Request-URI Too Long\r\n\r\n"
      ERROR_413_RESPONSE = "HTTP/1.1 413 Request Entity Too Large\r\n\r\n"
      ERROR_500_RESPONSE = "HTTP/1.1 500 Internal Server Error\r\n\r\n"
    end
  end