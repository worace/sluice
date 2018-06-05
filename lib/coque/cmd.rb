module Coque
  class Cmd
    include Redirectable
    attr_reader :context

    def |(other)
      verify_redirectable(other)
      case other
      when Cmd
        Pipeline.new([self, other])
      when Pipeline
        Pipeline.new([self] + other.commands)
      end
    end

    def clone
      raise "Not Implemented - Override"
    end

    def ensure_default_fds
      if self.stdin.nil?
        inr, inw = IO.pipe
        inw.close
        self.stdin = inr
      end

      if self.stdout.nil?
        outr, outw = IO.pipe
        self.stdout = outw
        # only used for Result if this is the last command in a pipe
        @stdout_read = outr
      end
    end
  end
end
