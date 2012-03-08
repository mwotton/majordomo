require 'rzmq_brokers'
require 'ffi-rzmq'
log_transport = "inproc://reactor_log"
APP_CONFIG = { 'broker' => 'tcp://*:5555' }

class RunBroker
  def initialize(master_context, log_transport, broker_endpoint)
    @broker_config = RzmqBrokers::Broker::Configuration.new do
      name 'broker-reactor'
      exception_handler nil
      poll_interval 250
      context master_context
      log_endpoint log_transport

      broker_endpoint broker_endpoint
      broker_bind  true

      broker_klass RzmqBrokers::Majordomo::Broker::Handler
      service_klass RzmqBrokers::Majordomo::Broker::Service
      worker_klass RzmqBrokers::Broker::Worker

      base_msg_klass RzmqBrokers::Majordomo::Messages
    end    
  end
  
  def run
    @broker = RzmqBrokers::Broker::Broker.new(@broker_config) # new thread
  end
end # RunBroker


broker_address = APP_CONFIG['broker'] or raise "need to define the address to listen on"
master_context = ZMQ::Context.new

logger_config = ZM::Configuration.new do
  context master_context
  name 'logger-server'
end


ZM::Reactor.new(logger_config).run do |reactor|
  log_config = ZM::Server::Configuration.new do
    endpoint log_transport
    bind true
    topic ''
    context master_context
    reactor reactor
  end

  log_config.extra = {:file => STDOUT}

  log_server = ZM::LogServer.new(log_config)
end
sleep 1

RunBroker.new(master_context, log_transport, broker_address).run

# run loop
while true
  sleep 1
end
