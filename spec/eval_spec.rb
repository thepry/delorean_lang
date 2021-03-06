require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
describe "Delorean" do

  let(:sset) {
    TestContainer.new({
                        "AAA" =>
                        defn("X:",
                             "    a =? 123",
                             "    b = a*2",
                             )
                      })
  }

  let(:engine) {
    Delorean::Engine.new "XXX", sset
  }

  it "evaluate simple expressions" do
    engine.parse defn("A:",
                      "    a = 123",
                      "    x = -(a * 2)",
                      "    b = -(a + 1)",
                      "    c = -a + 1",
                      "    d = a ** 3 - 10*0.2",
                      )

    engine.evaluate("A", ["a"]).should == [123]

    r = engine.evaluate("A", ["x", "b"])
    r.should == [-246, -124]

    expect(engine.evaluate("A", "d")).to eq 1860865.0
  end

  it "proper unary expression evaluation" do
    engine.parse defn("A:",
                      "    a = 123",
                      "    c = -a + 1",
                      )

    r = engine.evaluate("A", "c")
    r.should == -122
  end

  it "proper string interpolation" do
    engine.parse defn("A:",
                      '    a = "\n123\n"',
                      )

    r = engine.evaluate("A", "a")
    r.should == "\n123\n"
  end

  it "should handle getattr in expressions" do
    engine.parse defn("A:",
                      "    a = {'x':123, 'y':456, 'z':789}",
                      "    b = A.a.x * A.a.y - A.a.z",
                      )
    engine.evaluate("A", ["b"]).should == [123*456-789]
  end

  it "should handle numeric getattr" do
    engine.parse defn("A:",
                      "    a = {1:123, 0:456, 'z':789, 2: {'a':444}}",
                      "    b = A.a.1 * A.a.0 - A.a.z - A.a.2.a",
                      )
    engine.evaluate("A", ["b"]).should == [123*456-789-444]
  end

  it "should be able to evaluate multiple node attrs" do
    engine.parse defn("A:",
                      "    a =? 123",
                      "    b = a % 11",
                      "    c = a / 4.0",
                      )

    h = {"a" => 16}
    r = engine.evaluate("A", ["c", "b"], h)
    r.should == [4, 5]
  end

  it "should give error when accessing undefined attr" do
    engine.parse defn("A:",
                      "    a = 1",
                      "    c = a.to_ss",
                      )

    lambda {
      r = engine.evaluate("A", "c")
    }.should raise_error(Delorean::InvalidGetAttribute)
  end

  it "should be able to call 0-ary functions without ()" do
    engine.parse defn("A:",
                      "    a = 1",
                      "    d = a.to_s",
                      )

    engine.evaluate("A", "d").should == "1"
  end

  it "should handle default param values" do
    engine.parse defn("A:",
                      "    a =? 123",
                      "    c = a / 123.0",
                      )

    r = engine.evaluate("A", "c")
    r.should == 1
  end

  it "order of attr evaluation should not matter" do
    engine.parse defn("A:",
                      "    a =? 1",
                      "B:",
                      "    a =? 2",
                      "    c = A.a",
                      )
    engine.evaluate("B", %w{c a}).should == [1, 2]
    engine.evaluate("B", %w{a c}).should == [2, 1]
  end

  it "params should behave properly with inheritance" do
    engine.parse defn("A:",
                      "    a =? 1",
                      "B: A",
                      "    a =? 2",
                      "C: B",
                      "    a =? 3",
                      "    b = B.a",
                      "    c = A.a",
                      )
    engine.evaluate("C", %w{a b c}).should == [3, 2, 1]
    engine.evaluate("C", %w{a b c}, {"a" => 4}).should == [4, 4, 4]
    engine.evaluate("C", %w{c b a}).should == [1, 2, 3]
  end

  it "should give error when param is undefined for eval" do
    engine.parse defn("A:",
                      "    a =?",
                      "    c = a / 123.0",
                      )

    lambda {
      r = engine.evaluate("A", "c")
    }.should raise_error(Delorean::UndefinedParamError)
  end

  it "should handle simple param computation" do
    engine.parse defn("A:",
                      "    a =?",
                      "    c = a / 123.0",
                      )

    r = engine.evaluate("A", "c", {"a" => 123})
    r.should == 1
  end

  it "should give error on unknown node" do
    engine.parse defn("A:",
                      "    a = 1",
                      )

    lambda {
      r = engine.evaluate("B", "a")
    }.should raise_error(Delorean::UndefinedNodeError)
  end

  it "should handle runtime errors and report module/line number" do
    engine.parse defn("A:",
                      "    a = 1/0",
                      "    b = 10 * a",
                      )

    begin
      engine.evaluate("A", "b")
    rescue => exc
      res = Delorean::Engine.grok_runtime_exception(exc)
    end

    res.should == {
      "error" => "divided by 0",
      "backtrace" => [["XXX", 2, "/"], ["XXX", 2, "a"], ["XXX", 3, "b"]],
    }
  end

  it "should handle runtime errors 2" do
    engine.parse defn("A:",
                      "    b = Dummy.call_me_maybe('a', 'b')",
                      )

    begin
      engine.evaluate("A", "b")
    rescue => exc
      res = Delorean::Engine.grok_runtime_exception(exc)
    end

    res["backtrace"].should == [["XXX", 2, "b"]]
  end

  it "should handle optional args to external fns" do
    engine.parse defn("A:",
                      "    b = Dummy.one_or_two(['a', 'b'])",
                      "    c = Dummy.one_or_two([1,2,3], ['a', 'b'])",
                      )

    engine.evaluate("A", "b").should == [['a', 'b'], nil]
    engine.evaluate("A", "c").should == [[1,2,3], ['a', 'b']]
  end

  it "should handle operator precedence properly" do
    engine.parse defn("A:",
                      "    b = 3+2*4-1",
                      "    c = b*3+5",
                      "    d = b*2-c*2",
                      "    e = if (d < -10) then -123-1 else -456+1",
                      )

    r = engine.evaluate("A", "d")
    r.should == -50

    r = engine.evaluate("A", "e")
    r.should == -124
  end

  it "should handle if/else" do
    text = defn("A:",
                "    d =? -10",
                '    e = if d < -10 then "gungam"+"style" else "korea"'
                )

    engine.parse text
    r = engine.evaluate("A", "e", {"d" => -100})
    r.should == "gungamstyle"

    r = engine.evaluate("A", "e")
    r.should == "korea"
  end

  it "should be able to access specific node attrs " do
    engine.parse defn("A:",
                      "    b = 123",
                      "    c =?",
                      "B: A",
                      "    b = 111",
                      "    c = A.b * 123",
                      "C:",
                      "    c = A.c + B.c",
                      )

    r = engine.evaluate("B", "c")
    r.should == 123*123
    r = engine.evaluate("C", "c", {"c" => 5})
    r.should == 123*123 + 5
  end

  it "should be able to access nodes and node attrs dynamically " do
    engine.parse defn("A:",
                      "    b = 123",
                      "B:",
                      "    b = A",
                      "    c = b.b * 456",
                      )

    r = engine.evaluate("B", "c")
    r.should == 123*456
  end

  it "should be able to call class methods on ActiveRecord classes" do
    engine.parse defn("A:",
                      "    b = Dummy.call_me_maybe(1, 2, 3, 4)",
                      "    c = Dummy.call_me_maybe()",
                      "    d = Dummy.call_me_maybe(5) + b + c",
                      )
    r = engine.evaluate("A", ["b", "c", "d"])
    r.should == [10, 0, 15]
  end

  it "should be able to access ActiveRecord whitelisted fns using .x syntax" do
    engine.parse defn("A:",
                      '    b = Dummy.i_just_met_you("CRJ", 1.234).name2',
                      )
    r = engine.evaluate("A", "b")
    r.should == "CRJ-1.234"
  end

  it "should be able to get attr on Hash objects using a.b syntax" do
    engine.parse defn("A:",
                      '    b = Dummy.i_threw_a_hash_in_the_well()',
                      "    c = b.a",
                      "    d = b.b",
                      "    e = b.this_is_crazy",
                      )
    engine.evaluate("A", %w{c d e}).should == [456, 789, nil]
  end

  it "get attr on nil should return nil" do
    engine.parse defn("A:",
                      '    b = nil',
                      '    c = b.gaga',
                      '    d = b.gaga || 55',
                      )
    r = engine.evaluate("A", ["b", "c", "d"])
    r.should == [nil, nil, 55]
  end

  it "should be able to get attr on node" do
    engine.parse defn("A:",
                      "    a = 123",
                      "    b = A",
                      "    c = b.a * 2",
                      )
    engine.evaluate("A", %w{a c}).should == [123, 123*2]
  end

  getattr_code = <<eoc
A:
    x = 1
B:
    x = 2
C:
    x = 3
D:
    xs = [A, B, C]
E:
    xx = [n.x for n in D.xs]
eoc

  it "should be able to get attr on node 2" do
    engine.parse getattr_code
    engine.evaluate("E", "xx").should == [1,2,3]
  end

  it "should be able to call class methods on AR classes in modules" do
    engine.parse defn("A:",
                      "    b = M::LittleDummy.heres_my_number(867, 5309)",
                      )
    r = engine.evaluate("A", "b")
    r.should == 867 + 5309
  end

  it "should be able to use AR classes as values and call their methods" do
    engine.parse defn("A:",
                      "    a = M::LittleDummy",
                      "    b = a.heres_my_number(867, 5309)",
                      )
    r = engine.evaluate("A", "b")
    r.should == 867 + 5309
  end

  it "should ignore undeclared params sent to eval which match attr names" do
    engine.parse defn("A:",
                      "    d = 12",
                      )
    r = engine.evaluate("A", "d", {"d" => 5, "e" => 6})
    r.should == 12
  end

  it "should handle different param defaults on nodes" do
    engine.parse defn("A:",
                      "    p =? 1",
                      "    c = p * 123",
                      "B: A",
                      "    p =? 2",
                      "C: A",
                      "    p =? 3",
                      )

    r = engine.evaluate("C", "c", {"p" => 5})
    r.should == 5*123

    r = engine.evaluate("B", "c", {"p" => 10})
    r.should == 10*123

    r = engine.evaluate("A", "c")
    r.should == 1*123

    r = engine.evaluate("B", "c")
    r.should == 2*123

    r = engine.evaluate("C", "c")
    r.should == 3*123
  end

  it "should allow overriding of attrs as params" do
    engine.parse defn("A:",
                      "    a = 2",
                      "    b = a*3",
                      "B: A",
                      "    a =?",
                      )

    r = engine.evaluate("A", "b", {"a" => 10})
    r.should == 2*3

    r = engine.evaluate("B", "b", {"a" => 10})
    r.should == 10*3

    lambda {
      r = engine.evaluate("B", "b")
    }.should raise_error(Delorean::UndefinedParamError)

  end

  sample_script = <<eof
A:
    a = 2
    p =?
    c = a * 2
    pc = p + c

C: A
    p =? 3

B: A
    p =? 5
eof

  it "should allow overriding of attrs as params" do
    engine.parse sample_script

    r = engine.evaluate("C", "c")
    r.should == 4

    r = engine.evaluate("B", "pc")
    r.should == 4 + 5

    r = engine.evaluate("C", "pc")
    r.should == 4 + 3

    lambda {
      r = engine.evaluate("A", "pc")
    }.should raise_error(Delorean::UndefinedParamError)
  end

  it "engines of same name should be independent" do
    engin2 = Delorean::Engine.new(engine.module_name)

    engine.parse defn("A:",
                      "    a = 123",
                      "    b = a*3",
                      "B: A",
                      "    c = b*2",
                      )

    engin2.parse defn("A:",
                      "    a = 222.0",
                      "    b = a/5",
                      "B: A",
                      "    c = b*3",
                      "C:",
                      "    d = 111",
                      )

    engine.evaluate("A", ["a", "b"]).should == [123, 123*3]
    engin2.evaluate("A", ["a", "b"]).should == [222.0, 222.0/5]

    engine.evaluate("B", ["a", "b", "c"]).should == [123, 123*3, 123*3*2]
    engin2.evaluate("B", ["a", "b", "c"]).should ==
      [222.0, 222.0/5, 222.0/5*3]

    engin2.evaluate("C", "d").should == 111
    lambda {
      engine.evaluate("C", "d")
    }.should raise_error(Delorean::UndefinedNodeError)
  end

  it "should handle invalid expression evaluation" do
    # Should handle errors on expression such as -[] or -"xxx" or ("x"
    # + []) better. Currently, it raises NoMethodError.
    skip 'handle errors on expressions such as -[] or -"xxx"'
  end

  it "should eval lists" do
    engine.parse defn("A:",
                      "    b = []",
                      "    c = [1,2,3]",
                      "    d = [b, c, b, c, 1, 2, '123', 1.1, -1.23]",
                      "    e = [1, 1+1, 1+1+1, 1*2*4]",
                      )

    engine.evaluate("A", %w{b c d e}).should ==
      [[],
       [1, 2, 3],
       [[], [1, 2, 3], [], [1, 2, 3], 1, 2, "123", 1.1, -1.23],
       [1, 2, 3, 8],
      ]
  end

  it "should eval list expressions" do
    engine.parse defn("A:",
                      "    b = []+[]",
                      "    c = [1,2,3]+b",
                      "    d = c*2",
                      )

    engine.evaluate("A", %w{b c d}).should ==
      [[],
       [1, 2, 3],
       [1, 2, 3]*2,
      ]
  end

  it "should eval sets and set comprehension" do
    engine.parse defn("A:",
                      "    a = {-}",
                      "    b = {i*5 for i in {1,2,3}}",
                      "    c = {1,2,3} | {4,5}",
                      )
    engine.evaluate("A", ["a", "b", "c"]).should ==
      [Set[], Set[5,10,15], Set[1,2,3,4,5]]
  end

  it "should eval list comprehension" do
    engine.parse defn("A:",
                      "    b = [i*5 for i in [1,2,3]]",
                      "    c = [a-b for a, b in [[1,2],[4,3]]]"
                      )
    engine.evaluate("A", "b").should == [5, 10, 15]
    engine.evaluate("A", "c").should == [-1, 1]
  end

  it "should eval nested list comprehension" do
    engine.parse defn("A:",
                      "    b = [[a+c for c in [4,5]] for a in [1,2,3]]",
                      )
    engine.evaluate("A", "b").should == [[5, 6], [6, 7], [7, 8]]

  end

  it "should eval list comprehension variable override" do
    engine.parse defn("A:",
                      "    b = [b/2.0 for b in [1,2,3]]",
                      )
    engine.evaluate("A", "b").should == [0.5, 1.0, 1.5]
  end

  it "should eval list comprehension variable override (2)" do
    engine.parse defn("A:",
                      "    a = 1",
                      "    b = [a+1 for a in [1,2,3]]",
                      )
    engine.evaluate("A", "b").should == [2, 3, 4]
  end

  it "should eval conditional list comprehension" do
    engine.parse defn("A:",
                      "    b = [i*5 for i in [1,2,3,4,5] if i%2 == 1]",
                      "    c = [i/10.0 for i in [1,2,3,4,5] if i>4]",
                      )
    engine.evaluate("A", "b").should == [5, 15, 25]
    engine.evaluate("A", "c").should == [0.5]
  end

  it "should handle list comprehension unpacking" do
    engine.parse defn("A:",
                      "    b = [a-b for a, b in [[1,2],[20,10]]]",
                      )
    engine.evaluate("A", "b").should == [-1, 10]
  end

  it "should handle list comprehension with conditions using loop var" do
    skip "need to fix"
    engine.parse defn("A:",
                      "    b = [n for n in {'pt' : 1} if n[1]+1]",
                      )
    engine.evaluate("A", "b").should == [['pt', 1]]
  end

  it "should eval hashes" do
    engine.parse defn("A:",
                      "    b = {}",
                      "    c = {'a':1, 'b': 2,'c':3}",
                      "    d = {123*2: -123, 'b_b': 1+1}",
                      "    e = {'x': 1, 'y': 1+1, 'z': 1+1+1, 'zz': 1*2*4}",
                      "    f = {'a': nil, 'b': [1, nil, 2]}",
                      "    g = {b:b, [b]:[1,23], []:345}",
                      )

    engine.evaluate("A", %w{b c d e f g}).should ==
      [{},
       {"a"=>1, "b"=>2, "c"=>3},
       {123*2=>-123, "b_b"=>2},
       {"x"=>1, "y"=>2, "z"=>3, "zz"=>8},
       {"a"=>nil, "b"=>[1, nil, 2]},
       {{}=>{}, [{}]=>[1, 23], []=>345},
      ]
  end

  it "handles literal hashes with conditionals" do
    engine.parse defn("A:",
                      "    a = {'a':1 if 123, 'b':'x' if nil}",
                      "    b = {'a':a if a, 2: a if true, 'c':nil if 2*2}",
                      "    c = 1>2",
                      "    d = {1: {1: 2 if b}, 3: 3 if c, 2: {2: 3 if a}}",
                      )

    engine.evaluate("A", %w{a b d}).should == [
      {"a"=>1},
      {"a"=>{"a"=>1}, 2=>{"a"=>1}, "c"=>nil},
      {1=>{1=>2}, 2=>{2=>3}},
    ]
  end

  it "should eval hash comprehension" do
    engine.parse defn("A:",
                      "    b = {i*5 :i for i in [1,2,3]}",
                      "    c = [kv for kv in {1:11, 2:22}]",
                      )
    engine.evaluate("A", "b").should == {5=>1, 10=>2, 15=>3}
    engine.evaluate("A", "c").should == [[1, 11], [2, 22]]
  end

  it "for-in-hash should iterate over key/value pairs" do
    engine.parse defn("A:",
                      "    b = {1: 11, 2: 22}",
                      "    c = [kv[0]-kv[1] for kv in b]",
                      "    d = {kv[0] : kv[1] for kv in b}",
                      "    e = [kv for kv in b if kv[1]]",
                      "    f = [k-v for k, v in b if k>1]",
                      )
    engine.evaluate("A", "c").should == [-10, -20]
    engine.evaluate("A", "d").should == {1=>11, 2=>22}
    engine.evaluate("A", "f").should == [-20]

    # FIXME: this is a known bug in Delorean caused by the strange way
    # that select iterates over hashes and provides args to the block.
    # engine.evaluate("A", "e").should == [[1,11], [2,22]]
  end

  it "should eval nested hash comprehension" do
    engine.parse defn("A:",
                      "    b = { a:{a+c:a-c for c in [4,5]} for a in [1,2,3]}",
                      )
    engine.evaluate("A", "b").should ==
      {1=>{5=>-3, 6=>-4}, 2=>{6=>-2, 7=>-3}, 3=>{7=>-1, 8=>-2}}
  end

  it "should eval conditional hash comprehension" do
    engine.parse defn("A:",
                      "    b = {i*5:i+5 for i in [1,2,3,4,5] if i%2 == 1}",
                      "    c = {i/10.0:i*10 for i in [1,2,3,4,5] if i>4}",
                      )
    engine.evaluate("A", "b").should == {5=>6, 15=>8, 25=>10}
    engine.evaluate("A", "c").should == {0.5=>50}
  end

  it "should eval node calls as intermediate results" do
    engine.parse defn("A:",
                      "    a =?",
                      "    e = A(a=13)",
                      "    d = e.a * 2",
                      "    f = e.d / e.a",
                      )

    engine.evaluate("A", ["d", "f"]).should == [26, 2]
  end

  it "allows node calls from attrs" do
    engine.parse defn("A:",
                      "    a =?",
                      "    c =?",
                      "    b = a**2",
                      "    e = A(a=13)",
                      "    d = e(a=4, **{'c': 5})",
                      "    f = d.b + d.c + e().a",
                      )

    engine.evaluate("A", ["f"]).should == [16+5+13]
  end

  it "should eval multi-var hash comprehension" do
    engine.parse defn("A:",
                      "    b = {k*5 : v+1 for k, v in {1:2, 7:-30}}",
                      "    c = [k-v for k, v in {1:2, 7:-30}]",
                      )
    engine.evaluate("A", "b").should == {5=>3, 35=>-29}
    engine.evaluate("A", "c").should == [-1, 37]
  end

  it "should be able to amend node calls" do
    engine.parse defn("A:",
                      "    a =?",
                      "    aa = a*2",
                      "    c = A(a=12)",
                      "    d = c+{'a':3}",
                      "    f = c+{'a':4}",
                      "    g = d.aa + f.aa",
                      "    h = c(a=5).aa",
                      "    j = d(a=6).aa",
                      )

    engine.evaluate("A", ["g", "h", "j"]).should ==
      [3*2 + 4*2, 5*2, 6*2]
  end

  it "should be able to amend node calls 2" do
    engine.parse defn("A:",
                      "    a =?",
                      "    d = A(a=3)",
                      "    e = [d.a, d(a=4).a]",
                      )

    engine.evaluate("A", ["e"]).should == [[3,4]]
  end

  it "should eval module calls 1" do
    engine.parse defn("A:",
                      "    a = 123",
                      "    n = A",
                      "    d = n().a",
                      )

    engine.evaluate("A", %w{d}).should == [123]
  end

  it "should eval module calls 2" do
    engine.parse defn("A:",
                      "    a = 123",
                      "    b = 456 + a",
                      "    n = 'A'",
                      "    c = nil(x = 123, y = 456) % ['a', 'b']",
                      "    d = n(x = 123, y = 456) % ['a', 'b']",
                      "    e = nil() % ['b']",
                      )

    engine.evaluate("A", %w{n c d e}).should ==
      ["A", {"a"=>123, "b"=>579}, {"a"=>123, "b"=>579}, {"b"=>579}]
  end

  it "should eval module calls 3" do
    engine.parse defn("A:",
                      "    a = 123",
                      "B:",
                      "    n = 'A'",
                      "    d = n().a",
                      )

    engine.evaluate("B", %w{d}).should == [123]
  end

  it "should be possible to implement recursive calls" do
    engine.parse defn("A:",
                      "    n =?",
                      "    fact = if n <= 1 then 1 else n * A(n=n-1).fact",
                      )

    engine.evaluate("A", "fact", "n" => 10).should == 3628800
  end

  it "should eval module calls by node name" do
    engine.parse defn("A:",
                      "    a = 123",
                      "    b = A().a",
                      )
    engine.evaluate("A", "b").should == 123
  end

  it "should eval multiline expressions" do
    engine.parse defn("A:",
                      "    a = 1",
                      "    b = [a+1",
                      "        for a in [1,2,3]",
                      "        ]",
                      )
    engine.evaluate("A", "b").should == [2, 3, 4]
  end

  it "should eval multiline expressions (2)" do
    engine.parse defn("A:",
                      "    a = 123",
                      "    b = 456 + ",
                      "        a",
                      "    n = 'A'",
                      "    c = nil(x = 123,",
                      "          y = 456) % ['a', 'b']",
                      "    d = n(",
                      "           x = 123, y = 456) % ['a', 'b']",
                      "    e = nil(",
                      "         ) % ['b']",
                      )

    engine.evaluate("A", %w{n c d e}).should ==
      ["A", {"a"=>123, "b"=>579}, {"a"=>123, "b"=>579}, {"b"=>579}]
  end

  it "should eval in expressions" do
    engine.parse defn("A:",
                      "    a = [1,2,3,33,44]",
                      "    s = {22,33,44}",
                      "    b = (1 in a) && (2 in {22,44})",
                      "    c = (2 in a) && (22 in s)",
                      "    d = [i*2 for i in s if i in a]",
                      )

    engine.evaluate("A", %w{b c d}).should ==
      [false, true, [66, 88]]
  end

  it "should eval imports" do
    engine.parse defn("import AAA",
                      "A:",
                      "    b = 456",
                      "B: AAA::X",
                      "    a = 111",
                      "    c = AAA::X(a=456).b",
                      )
    engine.evaluate("B", ["a", "b", "c"], {}).should ==
      [111, 222, 456*2]
  end

  it "should eval imports (2)" do
    sset.merge({
                 "BBB"    =>
                 defn("import AAA",
                      "B: AAA::X",
                      "    a = 111",
                      "    c = AAA::X(a=-1).b",
                      "    d = a * 2",
                      ),
                 "CCC" =>
                 defn("import BBB",
                      "import AAA",
                      "B: BBB::B",
                      "    e = d * 3",
                      "C: AAA::X",
                      "    d = b * 3",
                      ),
               })

    e2 = sset.get_engine("BBB")

    e2.evaluate("B", ["a", "b", "c", "d"]).should ==
      [111, 222, -2, 222]

    engine.parse defn("import BBB",
                      "B: BBB::B",
                      "    e = d + 3",
                      )

    engine.evaluate("B", ["a", "b", "c", "d", "e"]).should ==
      [111, 222, -2, 222, 225]

    e4 = sset.get_engine("CCC")

    e4.evaluate("B", ["a", "b", "c", "d", "e"]).should ==
      [111, 222, -2, 222, 666]

    e4.evaluate("C", ["a", "b", "d"]).should == [123, 123*2, 123*3*2]
  end

  it "should eval imports (3)" do
    sset.merge({
                 "BBB" => getattr_code,
                 "CCC" =>
                 defn("import BBB",
                      "X:",
                      "    xx = [n.x for n in BBB::D().xs]",
                      "    yy = [n.x for n in BBB::D.xs]",
                      ),
               })

    e4 = sset.get_engine("CCC")
    e4.evaluate("X", "xx").should == [1,2,3]
    e4.evaluate("X", "yy").should == [1,2,3]
  end

  it "can eval indexing" do
    engine.parse defn("A:",
                      "    a = [1,2,3]",
                      "    b = a[1]",
                      "    c = a[-1]",
                      "    d = {'a' : 123, 'b': 456}",
                      "    e = d['b']",
                      "    f = a[1,2]",
                      )
    r = engine.evaluate("A", ["b", "c", "e", "f"])
    r.should == [2, 3, 456, [2,3]]
  end

  it "can eval indexing 2" do
    engine.parse defn("A:",
                      "    a = 1",
                      "    b = {'x' : 123, 'y': 456}",
                      "    c = A() % ['a', 'b']",
                      "    d = c['b'].x * c['a'] - c['b'].y",
                      )
    r = engine.evaluate("A", ["a", "b", "c", "d"])
    r.should ==
      [1, {"x"=>123, "y"=>456}, {"a"=>1, "b"=>{"x"=>123, "y"=>456}}, -333]
  end

  it "can handle exceptions with / syntax" do
    engine.parse defn("A:",
                      "    a = 1",
                      "    b = {'x' : 123, 'y': 456}",
                      "    e = ERR('hello')",
                      "    c = A() / ['a', 'b']",
                      "    d = A() / ['a', 'e']",
                      "    f = A() / 'a'",
                      )
    r = engine.evaluate("A", ["a", "b", "c"])
    r.should ==
      [1, {"x"=>123, "y"=>456}, {"a"=>1, "b"=>{"x"=>123, "y"=>456}}]

    r = engine.evaluate("A", ["a", "d"])
    r.should ==
      [1, {"error"=>"hello", "backtrace"=>[["XXX", 4, "e"], ["XXX", 6, "d"]]}]

    r = engine.evaluate("A", ["f"])
    r.should == [1]
  end

  it "should properly eval overridden attrs" do
    engine.parse defn("A:",
                      "    a = 5",
                      "    b = a",
                      "B: A",
                      "    a = 2",
                      "    x = A.b - B.b",
                      "    k = [A.b, B.b]",
                      "    l = [x.b for x in [A, B]]",
                      "    m = [x().b for x in [A, B]]",
                      )

    engine.evaluate("A", "b").should == 5
    engine.evaluate("B", "b").should == 2
    engine.evaluate("B", "x").should == 3
    engine.evaluate("B", "k").should == [5, 2]
    engine.evaluate("B", "l").should == [5, 2]
    engine.evaluate("B", "m").should == [5, 2]
  end

  it "implements simple version of self (_)" do
    engine.parse defn("B:",
                      "    a =?",
                      "    b =?",
                      "    x = a - b",
                      "A:",
                      "    a =?",
                      "    b =?",
                      "    x = _.a * _.b",
                      "    y = a && _",
                      "    z = (B() + _).x",
                      "    w = B(**_).x",
                      "    v = {**_, 'a': 123}",
                      )

    engine.evaluate("A", "x", {"a"=>3, "b"=>5}).should == 15
    h = {"a"=>1, "b"=>2, "c"=>3}
    engine.evaluate("A", "y", {"a"=>1, "b"=>2, "c"=>3}).should == h
    engine.evaluate("A", "z", {"a"=>1, "b"=>2, "c"=>3}).should == -1
    engine.evaluate("A", "w", {"a"=>4, "b"=>5, "c"=>3}).should == -1
    engine.evaluate("A", "v", {"a"=>4, "b"=>5, "c"=>3}).should == {
      "a"=>123, "b"=>5, "c"=>3}
  end

  it "implements positional args in node calls" do
    engine.parse defn("B:",
                      "    a =?",
                      "    b =?",
                      "    x = (_.0 - _.1) * (a - b)",
                      "    y = [_.0, _.1, _.2]",
                      "A:",
                      "    a = _.0 - _.1",
                      "    z = B(10, 20, a=3, b=7).x",
                      "    y = B('x', 'y').y",
                      )
    engine.evaluate("A", ["a", "z", "y"], {0 => 123, 1 => 456}).should ==
      [123-456, 40, ["x", "y", nil]]
  end

  it "can call 0-arity functions in list comprehension" do
    engine.parse defn("A:",
                      '    b = [x.name for x in Dummy.all_of_me]',
                      )
    r = engine.evaluate("A", "b")
    expect(r).to eq ["hello"]
  end

  it "node calls are not memoized/cached" do
    engine.parse defn("A:",
                      "    x = Dummy.side_effect",
                      "B: A",
                      "    x = (A() + _).x + (A() + _).x"
                     )
    r = engine.evaluate("B", "x")
    expect(r).to eq 3
  end

  it "node calls with double splats" do
    engine.parse defn("A:",
                      "    a =?",
                      "    b =?",
                      "    c = a+b",
                      "    h = {'a': 123}",
                      "    k = {'b': 456}",
                      "    x = A(**h, **k).c"
                     )
    r = engine.evaluate("A", "x")
    expect(r).to eq 579
  end

  it "hash literal with double splats" do
    engine.parse defn("A:",
                      "    a =?",
                      "    b =?",
                      "    h = {'a': 123, **a}",
                      "    k = {'b': 456, **h, **a, **b}",
                      "    l = {**k}",
                      "    m = {**k, 1:1, 2:2, 3:33}",
                      "    n = {**k if false, 1:1, 2:2, 3:33}",
                     )
    r = engine.evaluate("A", ["h", "k", "l", "m", "n"],
                        {"a" => {3=>3, 4=>4}, "b" => {5=>5, "a" => "aa"}})
    expect(r).to eq [
                   {"a"=>123, 3=>3, 4=>4},
                   {"b"=>456, "a"=>"aa", 3=>3, 4=>4, 5=>5},
                   {"b"=>456, "a"=>"aa", 3=>3, 4=>4, 5=>5},
                   {"b"=>456, "a"=>"aa", 3=>33, 4=>4, 5=>5, 1=>1, 2=>2},
                   {1=>1, 2=>2, 3=>33},
                 ]
  end

  it "understands openstructs" do
    engine.parse defn("A:",
                      "    os = Dummy.returns_openstruct",
                      "    abc = os.abc",
                      "    not_found = os.not_found"
                     )
    r = engine.evaluate("A", ["os", "abc", "not_found"])
    expect(r[0].abc).to eq("def")
    expect(r[1]).to eq("def")
    expect(r[2]).to be_nil
  end

  it "can use nodes as continuations" do

    # FIME: This is actually a trivial exmaple. Ideally we should be
    # able to pass arguments to the nodes when evaluating ys.  If the
    # arguments do not change the computation of "x" then "x" should
    # not be recomputed.  This would need some flow analysis though.

    engine.parse defn("A:",
                      "    a =?",
                      "    x = Dummy.side_effect",
                      "    y = x*a",
                      "B:",
                      "    ns = [A(a=a) for a in [1, 1, 1]]",
                      "    xs = [n.x for n in ns]",
                      "    ys = [n.y for n in ns]",
                      "    res = [xs, ys]",
                     )
    r = engine.evaluate("B", "res")
    expect(r[1]).to eq r[0]
  end

  it "can use nodes as continuations -- simple" do
    engine.parse defn("A:",
                      "    x = Dummy.side_effect",
                      "    y = x",
                      "B:",
                      "    ns = A()",
                      "    res = [ns.x, ns.y]",
                      "    res2 = ns % ['x', 'y']",
                     )
    r = engine.evaluate("B", "res")
    expect(r[1]).to eq r[0]

    # this one works as expected
    r2 = engine.evaluate("B", "res2")
    expect(r2.values.uniq.length).to eq 1
  end
end
