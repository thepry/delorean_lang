require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

class Dummy2 < ActiveRecord::Base
  def self.call_me_maybe(*a)
    a.inject(0, :+)
  end

  CALL_ME_MAYBE_SIG = [0, Float::INFINITY]
end

describe "Delorean" do

  let(:engine) {
    Delorean::Engine.new
  }

  it "evaluate simple expressions" do
    c = engine.parse defn("A:",
                          "  a = 123",
                          "  x = -(a * 2)",
                          "  b = -(a + 1)",
                          "  c = -a + 1",
                          )
    r = engine.evaluate(c, "A", "x")
    r.should == -246

    r = engine.evaluate(c, "A", "b")
    r.should == -124

  end

  it "proper unary expression evaluation" do
    c = engine.parse defn("A:",
                          "  a = 123",
                          "  c = -a + 1",
                          )

    r = engine.evaluate(c, "A", "c")
    r.should == -122
  end

  it "should be able to evaluate multiple node attrs" do
    pending
  end

  it "should give error when accessing undefined attr" do
    c = engine.parse defn("A:",
                          "  a = 1",
                          "  c = a.to_s",
                          )

    lambda {
      r = engine.evaluate(c, "A", "c")
    }.should raise_error(Delorean::InvalidGetAttribute)
  end

  it "should handle default param values" do
    c = engine.parse defn("A:",
                          "  a =? 123",
                          "  c = a / 123.0",
                          )

    r = engine.evaluate(c, "A", "c")
    r.should == 1
  end

  it "should give error when param is undefined for eval" do
    c = engine.parse defn("A:",
                          "  a = ?",
                          "  c = a / 123.0",
                          )

    lambda {
      r = engine.evaluate(c, "A", "c")
    }.should raise_error(Delorean::UndefinedParamError)
  end

  it "should handle simple param computation" do
    c = engine.parse defn("A:",
                          "  a = ?",
                          "  c = a / 123.0",
                          )

    r = engine.evaluate(c, "A", "c", {"a" => 123})
    r.should == 1
  end

  it "should give error on unknown node" do
    c = engine.parse defn("A:",
                          "  a = 1",
                          )

    lambda {
      r = engine.evaluate(c, "B", "a")
    }.should raise_error(Delorean::UndefinedNodeError)
  end

  it "should handle divide by zero" do
    # FIXME: this should check that we can report the proper line
    # number and exception for zero division.
    pending
    c = engine.parse defn("A:",
                          "  a = 1/0",
                          )

    lambda {
      r = engine.evaluate(c, "A", "a")
    }.should raise_error(ZeroDivisionError)
  end

  it "should cache attr results and reuse them" do
    # can probably test this using the call to a Dummy class method???
    pending
  end

  it "should handle operator precedence properly" do
    pending
  end

  it "should be able to access specific node attrs " do
    c = engine.parse defn("A:",
                          "  b = 123",
                          "  c = ?",
                          "B: A",
                          "  b = 111",
                          "  c = A.b * 123",
                          "C:",
                          "  c = A.c + B.c",
                          )

    r = engine.evaluate(c, "B", "c")
    r.should == 123*123
    r = engine.evaluate(c, "C", "c", {"c" => 5})
    r.should == 123*123 + 5
  end

  it "should be able to call class methods on ActiveRecord classes" do
    c = engine.parse defn("A:",
                          "  b = Dummy2.call_me_maybe(1, 2, 3, 4)",
                          )
    r = engine.evaluate(c, "A", "b")
    r.should == 10
  end

end
