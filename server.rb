load  'dummy_driver.rb'

module RubyLcd
  class Request    
    require 'json'
    require 'thread'
    @@last_requests = []
    
    def initialize message
      return if message.nil?
      @object = begin
        JSON.parse(message,{:symbolize_names => true})
      rescue
        nil
      end
      add_request @object if !@object.nil?
    end
    
    def add_request(object)
      @@last_requests.pop if @@last_requests.size >=10        
      @@last_requests << object unless object[:flash]
    end
    
    def get_extra_text(row)
      i = 0
      row = (row == BOTTOM_ROW) ? TOP_ROW : BOTTOM_ROW
      @@last_requests.reverse_each do |request|
        i +=1 
        next if i==1 # skip first request
        if request[:single_line] == row
          return request[:text]
        end
      end
      nil
    end
    
    def run
      require 'pry'      
      Server.kill_others()
      if @object[:single_line]
        @object[:extra_text] ||= get_extra_text(@object[:single_line]) 
      end
      
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

    def self.kill_others
      @threads.each do |t|
          Thread.kill t if (t.object_id != Thread.current.object_id)           
      end if !@threads.nil?
      @threads = [Thread.current]
    end

    def self.start
      @threads = []
      Thread::abort_on_exception = true  
      server = TCPServer.new("localhost", 2000)  # Server bind to port 2000
      loop {
        @threads << Thread.start(server.accept) do |client|
            puts "server startet"
            message = client.gets
            if !message.nil?
              r = Request.new(message)
              r.run
              #client.puts "responce"
            end
            client.close
        end
      }.join
    end
  end
end
RubyLcd::Server.start
