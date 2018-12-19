require 'active_support/time'
require 'active_record'
require 'bigdecimal'
require 'delorean/ruby'
require 'delorean/ruby/whitelists/default'

module Delorean

  ::Delorean::Ruby.whitelist = ::Delorean::Ruby::Whitelists::Default.new

  module BaseModule
    # _e is used by Marty promise_jobs to pass promise-related
    # information
    class NodeCall < Struct.new(:_e, :engine, :node, :params)
      def cloned_params
        # FIXME: evaluate() modifies params! => need to clone it.
        # This is pretty awful.  NOTE: can't sanitize params as Marty
        # patches NodeCall and modifies params to send _parent_id.
        # This whole thing needs to be redone.
        @cp ||= Hash[params]
      end

      def evaluate(attr)
        engine.evaluate(node, attr, cloned_params)
      end

      def /(args)
        begin
          case args
          when Array
            engine.eval_to_hash(node, args, cloned_params)
          when String
            self.evaluate(args)
          else
            raise "non-array/string arg to /"
          end
        rescue => exc
          Delorean::Engine.grok_runtime_exception(exc)
        end
      end

      # FIXME: % should also support string as args
      def %(args)
        raise "non-array arg to %" unless args.is_a?(Array)

        engine.eval_to_hash(node, args, cloned_params)
      end

      # add new arguments, results in a new NodeCall
      def +(args)
        raise "bad arg to %" unless args.is_a?(Hash)

        NodeCall.new(_e, engine, node, params.merge(args))
      end
    end

    class BaseClass
      def self._get_attr(obj, attr, _e)
        # REALLY FIXME: this really needs to be another "when" in the
        # case statement below. However, Gemini appears to create Hash
        # objects when running Delorean modules in delayed jobs that
        # return true when we called obj.instance_of?(Hash) and do not
        # work with the "case/when" matcher!!!  For now, this is a
        # hacky workaround.  This is likely some sort of Ruby bug.
        if obj.instance_of?(Hash)
          # FIXME: this implementation doesn't handle something like
          # {}.length.  i.e. length is a whitelisted function, but not
          # an attr. This implementation returns nil instead of 0.
          return obj[attr] if obj.member?(attr)
          return attr.is_a?(String) ? obj[attr.to_sym] : nil
        end

        # NOTE: should keep this function consistent with _index
        case obj
        when nil
          # FIXME: even Javascript which is superpermissive raises an
          # exception on null getattr.
          return nil
        when NodeCall
          return obj.evaluate(attr)
        when OpenStruct
          return obj[attr.to_sym]
        when Class
          return obj.send((attr + POST).to_sym, _e) if obj < BaseClass
        end

        begin
          return _instance_call(obj, attr, [], _e)
        rescue => exc
          raise InvalidGetAttribute,
          "attr lookup failed: '#{attr}' on <#{obj.class}> #{obj} - #{exc}"
        end
      end

      ######################################################################

      def self._index(obj, args, _e)
        # NOTE: should keep this function consistent with _get_attr
        case obj
        when nil
          # FIXME: even Javascript which is superpermissive raises an
          # exception on null getattr.
          return nil
        when Hash, NodeCall, Class, OpenStruct
          raise InvalidIndex unless args.length == 1
          _get_attr(obj, args[0], _e)
        when Array, String, MatchData
          raise InvalidIndex unless args.length <= 2 &&
                                    args[0].is_a?(Integer) &&
                                    (args[1].nil? || args[1].is_a?(Integer))
          obj[*args]
        else
          raise InvalidIndex
        end
      end

      ######################################################################

      def self._sanitize_hash(_e)
        _e.each_with_object({}) do
          |(k,v), h|
          h[k] = v if k.is_a?(Integer) || k =~ /\A[a-z][A-Za-z0-9_]*\z/
        end
      end

      ######################################################################

      def self._err(*args)
        str = args.map(&:to_s).join(", ")
        raise str
      end

      def self._node_call(node, _e, params)
        context = _e[:_engine]

        # a node call is being called with amended args
        return node + params if node.is_a?(NodeCall)

        engine = node.is_a?(Class) &&
          context.module_name != node.module_name ?
        context.get_import_engine(node.module_name) : context

        NodeCall.new(_e, engine, node || self, params)
      end

      ######################################################################

      def self._instance_call(obj, method, args, _e)
        begin
          msg = method.to_sym
        rescue NoMethodError
          raise "bad method #{method}"
        end

        # FIXME: this is pretty hacky -- should probably merge
        # whitelist and SIG mechanisms.
        if obj.is_a?(Class)
          _e[:_engine].parse_check_call_fn(method, args.count, obj)
          return obj.send(msg, *args)
        end

        cls = obj.class

        matcher = ::Delorean::Ruby.whitelist.matcher(method_name: msg)

        raise "no such method #{method}" unless matcher

        return _instance_call(obj, matcher.match_to, args, _e) if matcher.match_to?

        matcher.match!(klass: obj.class, args: args)

        obj.send(msg, *args)
      end

      ######################################################################
    end
  end
end
