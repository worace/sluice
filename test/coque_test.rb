require "test_helper"

TMP = `cd /tmp && pwd -P`.chomp

describe Coque do
  it "tests" do
    assert true
  end

  it "has version" do
    refute_nil ::Coque::VERSION
  end

  it "runs a command" do
    res = Coque["ls"].run
    assert(res.include?("Rakefile"))
    assert(res.pid > 0)
  end

  it "doesn't cache results" do
    res = Coque["ls"].run
    assert_equal(13, res.count)
    assert_equal(0, res.count)
  end

  it "can store as array" do
    res = Coque["ls"].run.to_a
    assert_equal(13, res.count)
    # Can check a second time as result is cached
    assert_equal(13, res.count)
  end

  it "can pipe together commands" do
    res = (Coque["ls"] | Coque["wc", "-l"]).run
    assert_equal(["13"], res.map(&:strip))
  end

  it "can pipe to ruby" do
    assert_equal("hi", Coque["echo", "hi"].run.sort.first)
    res = (Coque["echo", "hi"] | Coque::Rb.new { |l| puts l.upcase }).run
    assert_equal("HI", res.sort.first)
  end

  it "can redirect stdout" do
    out = Tempfile.new
    (Coque["echo", "hi"] > out).run.wait
    assert_equal "hi\n", File.read(out.path)
  end

  it "can redirect a pipeline stdout" do
    out = Tempfile.new
    (Coque["echo", "hi"] | Coque["wc", "-c"] > out).run.wait

    assert_equal "3\n", File.read(out.path).lstrip
  end

  it "redirects with ruby" do
    out = Tempfile.new
    (Coque["echo", "hi"] |
     Coque["wc", "-c"] |
     Coque::Rb.new { |l| puts l.to_i + 1 } > out).run.wait

    assert_equal "4\n", File.read(out.path)
  end

  it "can redirect stdin of command" do
    res = (Coque["head", "-n", "1"] < "/usr/share/dict/words").run.to_a
    assert_equal ["A"], res
  end

  it "can redirect stdin of pipeline" do
    res = ((Coque["head", "-n", "5"] < "/usr/share/dict/words") | Coque["wc", "-l"]).run.to_a
    assert_equal ["5"], res.map(&:lstrip)
  end

  it "can include already-redirected command in pipeline" do
    out = Tempfile.new
    c = Coque["wc", "-c"] > out
    (Coque["echo", "hi"] | c).run.wait
    assert_equal("3\n", File.read(out.path).lstrip)
  end

  it "cannot add command with already-redirected stdin as subsequent step of pipeline" do
    redirected = (Coque["head", "-n", "5"] < "/usr/share/dict/words")
    assert_raises(Coque::RedirectionError) do
      Coque["printf", "1\n2\n3\n4\n5\n"] | redirected
    end

    pipeline = (Coque["printf", "1\n2\n3\n"] | Coque["head", "-n", "2"])
    next_cmd = Coque["wc", "-c"] < "/usr/share/dict/words"
    assert_raises(Coque::RedirectionError) do
      pipeline | next_cmd
    end
  end

  it "cannot pipe stdout-redirected command to subsequent command" do
    redirected = Coque["echo", "hi"] > Tempfile.new
    assert_raises(Coque::RedirectionError) do
      redirected | Coque["wc", "-c"]
    end

    pipeline = (Coque["printf", "1\n2\n3\n"] | Coque["head", "-n", "2"]) > Tempfile.new
    assert_raises(Coque::RedirectionError) do
      pipeline | Coque["wc", "-c"]
    end
  end

  it "stores exit code in result" do
    cmd = Coque["cat", "/sgsadg/asgdasdg/asgsagsg/ag"] >> "/dev/null"
    res = cmd.run.wait
    assert_equal 1, res.exit_code
  end

  it "can redirect stderr" do
    out = Tempfile.new
    cmd = Coque["cat", "/sgsadg/asgdasdg/asgsagsg/ag"] >> out
    cmd.run.wait
    assert_equal "cat: /sgsadg/asgdasdg/asgsagsg/ag: No such file or directory\n", File.read(out.path)
  end

  it "can manipulate context properties" do
    ctx = Coque::Context.new
    assert_equal Hash.new, ctx.env
    refute ctx.disinherits_env?
    assert ctx.dir.is_a?(String)
    assert ctx.disinherit_env.disinherits_env?
  end

  it "can chdir" do
    ctx = Coque::Context.new.chdir("/tmp")
    assert_equal [TMP], ctx["pwd"].run.to_a
  end

  it "can set env" do
    ctx = Coque::Context.new.setenv(pizza: "pie")
    assert_equal ["pie"], ctx["echo", "$pizza"].run.to_a
  end

  it "can unset baseline env" do
    ENV["COQUE_TEST"] = "testing"
    assert_equal ["testing"], Coque["echo", "$COQUE_TEST"].run.to_a
    ctx = Coque::Context.new.disinherit_env
    assert_equal [""], ctx["echo", "$COQUE_TEST"].run.to_a
  end

  it "inits Rb with noop by default" do
    c = Coque::Rb.new
    assert_equal [], c.run.to_a
  end

  it "can set pre/post commands for crb" do
    c = Coque::Rb.new.pre { puts "pizza" }.post { puts "pie"}
    assert_equal ["pizza", "pie"], c.run.to_a
  end

  it "can create Rb command from a context" do
    ctx = Coque::Context.new
    input = ctx["echo", "hi"]
    cmd = input | ctx.rb { |l| puts l.upcase }.pre { puts "pizza"}

    assert_equal ["pizza", "HI"], cmd.run.to_a
  end

  it "applies ENV settings to CRB commands" do
    ctx = Coque::Context.new.setenv(pizza: "pie")
    cmd = ctx.rb.pre { puts ENV["pizza"]}
    assert_equal ["pie"], cmd.run.to_a
  end

  it "disinherits env for Rb" do
    ENV["COQUE_TEST"] = "testing"
    ctx = Coque::Context.new.disinherit_env
    cmd = ctx.rb.pre { puts ENV["COQUE_TEST"]}
    assert_equal [""], cmd.run.to_a
    # Clearing env in subprocess doesn't affect parent
    assert_equal "testing", ENV["COQUE_TEST"]
  end

  it "chdirs for Rb" do
    ctx = Coque::Context.new.chdir("/tmp")
    assert_equal [TMP], ctx.rb.pre { puts Dir.pwd }.run.to_a
  end

  it "can clone partially-applied commands" do
    local = Coque::Context.new
    echo = local["echo"]

    assert_equal ["hi"], echo["hi"].run.to_a
    assert_equal ["ho"], echo["ho"].run.to_a
  end

  it "can subsequently redirect a partially-applied command" do
    local = Coque::Context.new
    echo = local["echo"]

    o1 = Tempfile.new
    o2 = Tempfile.new

    (echo["hi"] > o1).run.wait
    (echo["ho"] > o2).run.wait

    assert_equal "hi\n", File.read(o1)
    assert_equal "ho\n", File.read(o2)
  end

  it "can create context from the top-level namespace" do
    assert Coque.context.is_a?(Coque::Context)

    assert_equal "/tmp", Coque.context(dir: "/tmp").dir
    assert_equal "pie", Coque.context(env: {pizza: "pie"}).env[:pizza]
    assert Coque.context(disinherits_env: true).disinherits_env?
  end

  it "can use top-level helper method to construct pipeline of multiple commands" do
    echo = Coque["echo", "-n", "hi"]
    wc = Coque["wc", "-c"]

    pipe = Coque.pipeline(echo, wc)
    assert_equal ["2"], pipe.run.to_a.map(&:lstrip)
  end

  it "can re-use a command with different out streams" do
    skip
    local = Coque::Context.new
    echo = local["echo", "hi"]

    o1 = Tempfile.new
    o2 = Tempfile.new

    (echo > o1).run.wait
    (echo > o2).run.wait

    assert_equal "hi\n", File.read(o1)
    assert_equal "hi\n", File.read(o2)
  end

  # TODO
  # [X] Can partial-apply command args and add more using []
  # [X] Can apply chdir, env, and disinherit_env to Rb forks
  # [X] Can fork CRB from context
  # [X] Can provide pre/post blocks for Rb
  # [ ] Can use partial-applied command multiple times with different STDOUTs
  # [ ] Can Fix 2> redirection operator (>err? )
  # [ ] Usage examples in readme
  # [X] Coque.pipeline helper method
  # [X] Rename to Coque
  # [X] Coque.context helper method
end