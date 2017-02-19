module ZMQ
  class Authenticator
    def authenticate(domain, address, identity, mechanism, *credentials)
      case mechanism
      when 'NULL'
        null(domain, address, identity)
      when 'PLAIN'
        plain(domain, address, identity, credentials.first.to_str, credentials.last.to_str)
      when 'CURVE'
        curve(domain, address, identity, credentials.first.to_str)
      else
        raise ArgumentError, "Unknown mechanism #{mechanism.dump}"
      end
    end

    def null(domain, address, identity)
      'anonymous'
    end

    def plain(domain, address, identity, username, password)
      'anonymous'
    end

    def curve(domain, address, identity, public_key)
      'anonymous'
    end
  end

  class Zap
    attr_reader :socket

    def initialize(options = {})
      @authenticator = options.fetch(:authenticator)
      @socket = ZMQ::Router.new("inproc://zeromq.zap.01")
    end

    def handle_zap
      socket_identity, _, version, request_id, domain, address, identity, mechanism, *credentials = @socket.recv
      if version.to_str == '1.0'
        user, metadata = @authenticator.authenticate(domain.to_str, address.to_str, identity.to_str, mechanism.to_str, credentials)
        if user
          send_reply(socket_identity, _, version, request_id, 200, 'OK', user, metadata)
        else
          send_reply(socket_identity, _, version, request_id, 400, 'Invalid credentials', nil)
        end
      else
        send_reply(socket_identity, _, 1.0, request_id, 500, 'Version number not valid', nil)
      end
    rescue => e
      ZMQ.logger.crash(e)
    end

    def send_reply(socket_identity, _, version, request_id, status_code, reason, user, metadata = nil)
      LibZMQ.msg_send(socket_identity, @socket, LibZMQ::SNDMORE)
      LibZMQ.msg_send(_, @socket, LibZMQ::SNDMORE)
      if version.is_a?(ZMQ::Msg)
        LibZMQ.msg_send(version, @socket, LibZMQ::SNDMORE)
      else
        LibZMQ.send(@socket, version, LibZMQ::SNDMORE)
      end
      LibZMQ.msg_send(request_id, @socket, LibZMQ::SNDMORE)
      LibZMQ.send(@socket, status_code, LibZMQ::SNDMORE)
      LibZMQ.send(@socket, reason, LibZMQ::SNDMORE)
      LibZMQ.send(@socket, user, LibZMQ::SNDMORE)
      if metadata.respond_to?(:each)
        meta = ""
        metadata.each do |key, value|
          key, value = String(key), String(value)
          if key.bytesize > 255
            raise ArgumentError, "metadata keys can only be 8 bit long"
          else
            meta << sprintf("%s%s%s%s", [key.bytesize].pack('C'), key, [value.bytesize].pack('N'), value)
          end
        end
        LibZMQ.send(@socket, meta, 0)
      else
        LibZMQ.send(@socket, nil, 0)
      end
    end
  end
end
