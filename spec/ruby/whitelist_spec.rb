require_relative '../spec_helper'
require 'delorean/ruby/whitelists/empty'

describe "Delorean Ruby whitelisting" do
  it 'allows to override whitelist with an empty one' do
    ::Delorean::Ruby.whitelist = whitelist
    expect(whitelist.matchers).to be_empty

    ::Delorean::Ruby.whitelist = ::Delorean::Ruby::Whitelists::Default.new
    expect(::Delorean::Ruby.whitelist.matchers).to_not be_empty
  end

  let(:whitelist) { ::Delorean::Ruby::Whitelists::Empty.new }

  describe "methods" do
    before do
      whitelist.add_method :testmethod do |method|
        method.called_on Dummy
      end

      whitelist.add_method :testmethod_with_args do |method|
        method.called_on Dummy, with: [Numeric, [String, nil], [String, nil]]
      end
    end

    let(:matcher) { whitelist.matcher(method_name: :testmethod) }
    let(:matcher_with_args) { whitelist.matcher(method_name: :testmethod_with_args) }

    it 'matches method' do
      matcher = whitelist.matcher(method_name: :testmethod)
      expect(matcher).to_not be_nil
      expect { matcher.match!(klass: Dummy, args: []) }.to_not raise_error
    end

    it 'allows missing nillable arguments' do
      expect { matcher_with_args.match!(klass: Dummy, args: [1]) }.to_not raise_error
    end

    it 'raises error if method not allowed for a class' do
      expect { matcher.match!(klass: Date, args: []) }.to raise_error('no such method testmethod for Date')
    end

    it 'raises error if arguments list is too long' do
      expect { matcher.match!(klass: Dummy, args: [1]) }.to raise_error('too many args to testmethod')
    end

    it 'raises error if arguments list is too short' do
      expect { matcher_with_args.match!(klass: Dummy, args: []) }.to raise_error('bad arg 0, method testmethod_with_args: /NilClass [Numeric]')
    end

    it 'raises error if argument type is wrong' do
      expect { matcher_with_args.match!(klass: Dummy, args: [1, 2]) }.to raise_error('bad arg 1, method testmethod_with_args: 2/Fixnum [String, nil]')
    end

    it 'allows match one method to another' do
      whitelist.add_method :testmethod_matched, match_to: :testmethod_with_args
      matcher = whitelist.matcher(method_name: :testmethod_matched)
      expect(matcher.match_to?).to be true
    end
  end
end
