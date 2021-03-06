module Coque
  class Cmd
    include Redirectable
    include Runnable
    attr_reader :context

    def pipe(other)
      case other
      when Cmd
        Pipeline.new([self.clone, other.clone])
      when Pipeline
        Pipeline.new([self.clone] + other.commands)
      end
    end

    def |(other)
      pipe(other)
    end

    def clone
      raise "Not Implemented - Override"
    end

    def get_default_fds
      stdin = if self.stdin
                self.stdin
              else
                inr, inw = IO.pipe
                inw.close
                inr
              end

      stdoutr, stdoutw = if self.stdout
                           [self.stdout, self.stdout]
                         else
                           IO.pipe
                         end

      [stdin, stdoutr, stdoutw]
    end
  end
end
