module ManageIQ
  module Messaging
    module Common
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        private

        def logger
          ManageIQ::Messaging.logger
        end

        def raw_publish(client, address, body, headers)
          client.publish(address, encode_body(headers, body), headers)
          logger.info("Address(#{address}), msg(#{body.inspect}), headers(#{headers.inspect})")
        end

        def queue_for_publish(options)
          affinity = options[:affinity] || 'none'
          address = "queue/#{options[:service]}.#{affinity}"

          headers = {:"destination-type" => "ANYCAST"}
          headers[:expires] = options[:expires_on].to_i * 1000 if options[:expires_on]
          headers[:AMQ_SCHEDULED_TIME] = options[:deliver_on].to_i * 1000 if options[:deliver_on]
          headers[:priority] = options[:priority] if options[:priority]

          [address, headers]
        end

        def queue_for_subscribe(options)
          affinity = options[:affinity] || 'none'
          queue_name = "queue/#{options[:service]}.#{affinity}"

          headers = {:"subscription-type" => 'ANYCAST', :ack => 'client'}

          [queue_name, headers]
        end

        def topic_for_publish(options)
          address = "topic/#{options[:service]}"

          headers = {:"destination-type" => "MULTICAST"}
          headers[:expires] = options[:expires_on].to_i * 1000 if options[:expires_on]
          headers[:AMQ_SCHEDULED_TIME] = options[:deliver_on].to_i * 1000 if options[:deliver_on]
          headers[:priority] = options[:priority] if options[:priority]

          [address, headers]
        end

        def topic_for_subscribe(options)
          queue_name = "topic/#{options[:service]}"

          headers = {:"subscription-type" => 'MULTICAST', :ack => 'client'}
          headers[:"durable-subscription-name"] = options[:persist_ref] if options[:persist_ref]

          [queue_name, headers]
        end

        def assert_options(options, keys)
          keys.each do |key|
            raise "options must contains key #{key}" unless options.key?(key)
          end
        end

        def encode_body(headers, body)
          return body if body.kind_of?(String)
          headers[:encoding] = 'yaml'
          body.to_yaml
        end

        def decode_body(headers, raw_body)
          return raw_body unless headers['encoding'] == 'yaml'
          YAML.load(raw_body)
        end

        def send_response(client, service, correlation_ref, result)
          response_options = {
            :service  => "#{service}.response",
            :affinity => correlation_ref
          }
          address, response_headers = queue_for_publish(response_options)
          raw_publish(client, address, result || '', response_headers.merge(:correlation_id => correlation_ref))
        end

        def receive_response(client, service, correlation_ref)
          response_options = {
            :service  => "#{service}.response",
            :affinity => correlation_ref
          }
          queue_name, response_headers = queue_for_subscribe(response_options)
          client.subscribe(queue_name, response_headers) do |msg|
            client.ack(msg)
            yield decode_body(msg.headers, msg.body)
            client.unsubscribe(queue_name)
          end
        end
      end
    end
  end
end
