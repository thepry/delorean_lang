module Delorean
  # FIXME: separate runtime/parse exceptions

  class ParseError < StandardError
    attr_reader :line, :module_name

    def initialize(message, module_name, line)
      super(message)
      @line = line
      @module_name = module_name
    end
  end

  class UndefinedError < ParseError
  end

  class RedefinedError < ParseError
  end

  class UndefinedFunctionError < ParseError
  end

  class UndefinedNodeError < ParseError
  end

  class RecursionError < ParseError
  end

  class BadCallError < ParseError
  end

  class InvalidGetAttribute < StandardError
  end

  class UndefinedParamError < StandardError
  end

  class ModuleNotFoundError < StandardError
  end

end
