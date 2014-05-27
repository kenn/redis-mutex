class Redis
  class Mutex
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
          mutex_arguments = Array(options[:on]) & target_argument_names

          define_method(with_method) do |*args|
            named_arguments =  Hash[target_argument_names.zip(args)]
            arguments  = mutex_arguments.map { |name| named_arguments[name] }
            key = self.class.name << '#' << target.to_s << ":" << arguments.join(':')
            begin
              Redis::Mutex.with_lock(key, options) do
                send(without_method, *args)
              end
            rescue Redis::Mutex::LockError
              send(after_method, *args) if respond_to?(after_method)
            end
          end

          alias_method without_method, target
          alias_method target, with_method
        end
      end
    end
  end
end
