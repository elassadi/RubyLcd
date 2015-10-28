#!/usr/bin/ruby

APP_ROOT = '/heatcontroll'
load "#{APP_ROOT}/classes/logger.rb"
load "#{APP_ROOT}/driver/lcd1602_driver.rb"

module RubyLcd
  class Request
    require 'json'
    require 'thread'
    @@last_requests = []

    def initialize(message)
      return if message.nil?
      @object = begin
        JSON.parse(message, symbolize_names: true)
      rescue
        nil
      end
      add_request @object unless @object.nil?
    end

    def add_request(object)
      @@last_requests.pop if @@last_requests.size >= 10
      @@last_requests << object unless object[:flash]
    end

    def get_extra_text(row)
      i = 0
      row = (row == BOTTOM_ROW) ? TOP_ROW : BOTTOM_ROW
      @@last_requests.reverse_each do |request|
        i += 1
        next if i == 1 # skip first request
        return request[:text] if request[:single_line] == row
      end
      nil
    end

    def run
      return if @object.nil?
      Server.gracefull_stop_others
      if @object[:single_line]
        @object[:extra_text] ||= get_extra_text(@object[:single_line])
      end
      return RubyLcd.send(@object[:command]) if @object[:command]
      RubyLcd.print(@object)
      if @object[:flash]
        RubyLcd.print(@@last_requests.last) unless @@last_requests.nil?
      end
    end
  end

  class Server
    require 'socket'
    require 'thread'

    STATUS_INTERUPT = 1
    def threads
      @threads || []
    end

    def self.gracefull_stop_others
      @threads.each do |t|
        if (t.object_id != Thread.current.object_id)
          t['STOP'] = Time.now.to_s
          log ("STOP SIGNAL SET for Thread #{t.object_id} we must wait ")
          # wait until thred exit
          t.value
          log ('Finisched Waiting  ')
         end
      end unless @threads.nil?
      @threads = [Thread.current]
    end

    def self.get_ip
      a = Socket.ip_address_list.detect(&:ipv4_private?)
      return a.ip_address unless a.nil?
      nil
    end

    def self.start
      log('Lcd Server gestartet')
      RubyLcd.print({ text: 'LCD Display ist   Bereit' })
      ip = nil
      2.times do |i|
        ip = get_ip
        if ip
          RubyLcd.print({ text: "IP:             #{ip}" })
          log("Netzwerk IP:#{ip}")
        else
          RubyLcd.print({ text: "Warte auf       Netzwerk#{'.' * (i + 1)}" })
        end
        sleep(2)
        break if ip
      end
      RubyLcd.print({ text: 'Kein  Netzwerk' }) unless ip
      @threads = []
      Thread.abort_on_exception = true
      server = TCPServer.new('localhost', 2000) # Server bind to port 2000
      loop do
        @threads << Thread.start(server.accept) do |client|
          message = client.gets
          # puts "server got message #{message} "
          unless message.nil?
            r = Request.new(message)
            r.run unless r.nil?
            # client.puts "responce"
          end
          client.close
        end
      end.join
    end
  end
end

Signal.trap('INT') do|_signo|
  # RubyLcd.driver.init
end
Signal.trap('KILL') do|_signo|
  RubyLcd.clear
  exit(0)
end

Signal.trap('TERM') do|_signo|
  RubyLcd.clear
  exit(0)
end
RubyLcd::Server.start
