# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Tubes do
  describe "for #find" do
    before do
      @conn =  stub
      @tubes = Beaneater::Tubes.new(@conn)
    end

    it("should return Tube obj") { assert_kind_of Beaneater::Tube, @tubes.find(:foo) }
  end #find
end # Beaneater::Tubes