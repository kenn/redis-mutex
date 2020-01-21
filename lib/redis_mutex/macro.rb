class RedisMutex
  module Macro
    def self.included(base)
      base.extend ClassMethods
      base.class_eval do
        class << self
          attr_accessor :auto_mutex_methods
        end
        @auto_mutex_methods = {}
      end
    end

    module ClassMethods
      def auto_mutex(target, options={})
        self.auto_mutex_methods[target] = options
      end

      def method_added(target)
        return if target.to_s =~ /^auto_mutex_methods/
        return unless self.auto_mutex_methods[target]
        without_method  = "#{target}_without_auto_mutex"
        with_method     = "#{target}_with_auto_mutex"
        after_method    = "#{target}_after_failure"
        return if method_defined?(without_method)
        options = self.auto_mutex_methods[target]

        if options[:after_failure].is_a?(Proc)
          define_method(after_method, &options[:after_failure])
        end
        target_argument_names = instance_method(target.to_sym).parameters.map(&:last)
        on_arguments = Array(options[:on])
        mutex_arguments = on_arguments & target_argument_names
        unknown_arguments = on_arguments - target_argument_names
        if unknown_arguments.any?
          raise ArgumentError, "You are trying to lock on unknown arguments: #{unknown_arguments.join(', ')}"
        end

        define_method(with_method) do |*args|
          named_arguments =  Hash[target_argument_names.zip(args)]
          arguments  = mutex_arguments.map { |name| named_arguments.fetch(name) }
          key = format(
            "%<class>s#%<target>s:%<arguments>s",
            class: self.class.name,
            target: target,
            arguments: arguments.join(":")
          )
          begin
            RedisMutex.with_lock(key, options) do
              send(without_method, *args)
            end
          rescue RedisMutex::LockError
            send(after_method, *args) if respond_to?(after_method)
          end
        end

        alias_method without_method, target
        alias_method target, with_method
      end
    end
  end
end
