require 'spec_helper'

describe Puppet::Context do
  let(:context) { Puppet::Context.new({ :testing => "value" }) }

  context "with the implicit test_helper.rb pushed context" do
    it "fails to lookup a value that does not exist" do
      expect { context.lookup("a") }.to raise_error(Puppet::Context::UndefinedBindingError)
    end

    it "calls a provided block for a default value when none is found" do
      expect(context.lookup("a") { "default" }).to eq("default")
    end

    it "behaves as if pushed a {} if you push nil" do
      context.push(nil)
      expect(context.lookup(:testing)).to eq("value")
      context.pop
    end

    it "fails if you try to pop off the top of the stack" do
      expect { context.pop }.to raise_error(Puppet::Context::StackUnderflow)
    end

    it "protects the bindings table from casual access" do
      expect { context.push({}).table }.to raise_error(NoMethodError, /protected/)
    end
  end

  describe "with additional context" do
    before :each do
      context.push("a" => 1)
    end

    it "holds values for later lookup" do
      expect(context.lookup("a")).to eq(1)
    end

    it "allows rebinding values in a nested context" do
      inner = nil
      context.override("a" => 2) do
        inner = context.lookup("a")
      end

      expect(inner).to eq(2)
    end

    it "outer bindings are available in an overridden context" do
      inner_a = nil
      inner_b = nil
      context.override("b" => 2) do
        inner_a = context.lookup("a")
        inner_b = context.lookup("b")
      end

      expect(inner_a).to eq(1)
      expect(inner_b).to eq(2)
    end

    it "overridden bindings do not exist outside of the override" do
      context.override("a" => 2) do
      end

      expect(context.lookup("a")).to eq(1)
    end

    it "overridden bindings do not exist outside of the override even when leaving via an error" do
      begin
        context.override("a" => 2) do
          raise "this should still cause the bindings to leave"
        end
      rescue
      end

      expect(context.lookup("a")).to eq(1)
    end
  end
end
