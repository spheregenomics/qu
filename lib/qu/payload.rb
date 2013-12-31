require 'ostruct'
require 'forwardable'

module Qu
  class Payload < OpenStruct
    extend Forwardable
    include Logger

    def_delegators :"Qu.instrumenter", :instrument

    undef_method(:id) if method_defined?(:id)

    def initialize(options = {})
      super
      self.args ||= []
    end

    def klass
      @klass ||= constantize(super)
    end

    def job
      @job ||= klass.load(self)
    end

    def queue
      @queue ||= (klass.instance_variable_get(:@queue) || 'default').to_s
    end

    def perform
      job.run_hook(:perform) do
        instrument("perform.#{InstrumentationNamespace}") do |ipayload|
          ipayload[:payload] = self
          job.perform
        end
      end

      job.run_hook(:complete) do
        Qu.complete(self)
      end
    rescue Qu::Worker::Abort
      job.run_hook(:abort) do
        Qu.abort(self)
      end
      raise
    rescue => exception
      job.run_hook(:failure, exception) do
        instrument("failure.#{InstrumentationNamespace}") do |ipayload|
          ipayload[:payload] = self
          ipayload[:exception] = exception
          Qu.failure.create(self, exception)
        end
      end
    end

    # Internal: Pushes payload to backend.
    def push
      self.pushed_at = Time.now.utc

      job.run_hook(:push) do
        Qu.push(self)
      end
    end

    def attributes
      {
        :id => id,
        :klass => klass.to_s,
        :args => args,
      }
    end

    def attributes_for_push
      attributes
    end

    def to_s
      "#{id}:#{klass}:#{args.inspect}"
    end

    private

    def constantize(class_name)
      return unless class_name
      return class_name if class_name.is_a?(Class)
      constant = Object
      class_name.split('::').each do |name|
        constant = constant.const_get(name) || constant.const_missing(name)
      end
      constant
    end
  end
end
