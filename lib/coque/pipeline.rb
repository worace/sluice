module Coque
  class Pipeline
    include Redirectable

    attr_reader :commands
    def initialize(commands = [])
      @commands = commands
    end

    def to_s
      "<Pipeline #{commands.join(" | ")} >"
    end

    def |(other)
      verify_redirectable(other)
      case other
      when Pipeline
        Pipeline.new(commands + other.commands)
      when Cmd
        Pipeline.new(commands + [other])
      when RbCmd
        Pipeline.new(commands + [other])
      end
    end

    def stitch
      # Set head in
      if commands.first.stdin.nil?
        start_r, start_w = IO.pipe
        start_w.close
        commands.first.stdin = start_r
      end

      # Connect intermediate in/outs
      commands.each_cons(2) do |left, right|
        read, write = IO.pipe
        left.stdout = write
        right.stdin = read
      end

      # Set tail out
      if self.stdout
        commands.last.stdout = stdout
        stdout
      elsif commands.last.stdout
        commands.last.stdout
      else
        next_r, next_w = IO.pipe
        commands.last.stdout = next_w
        next_r
      end
    end

    def run
      stdout = stitch
      results = commands.map(&:run)
      Result.new(results.last.pid, stdout)
    end
  end
end