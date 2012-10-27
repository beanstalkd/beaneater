# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Tubes do
  describe "for #find" do
    before do
      @pool  =  stub
      @tubes = Beaneater::Tubes.new(@pool)
    end

    it("should return Tube obj") { assert_kind_of Beaneater::Tube, @tubes.find(:foo) }
    it("should return Tube name") { assert_equal :foo, @tubes.find(:foo).name }
  end #find
end # Beaneater::Tubes