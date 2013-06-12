# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe "Beaneater::Errors" do
  it 'should raise proper exception for invalid status NOT_FOUND' do
    @klazz = Beaneater::UnexpectedResponse.from_status("NOT_FOUND", "job-stats -1")
    assert_kind_of(Beaneater::NotFoundError, @klazz)
    assert_equal 'job-stats -1', @klazz.cmd
    assert_equal 'NOT_FOUND', @klazz.status
  end

  it 'should raise proper exception for invalid status BAD_FORMAT' do
    @klazz = Beaneater::UnexpectedResponse.from_status("BAD_FORMAT", "FAKE")
    assert_kind_of(Beaneater::BadFormatError, @klazz)
    assert_equal 'FAKE', @klazz.cmd
    assert_equal 'BAD_FORMAT', @klazz.status
  end

  it 'should raise proper exception for invalid status DEADLINE_SOON' do
    @klazz = Beaneater::UnexpectedResponse.from_status("DEADLINE_SOON", "reserve 0")
    assert_kind_of(Beaneater::DeadlineSoonError, @klazz)
    assert_equal 'reserve 0', @klazz.cmd
    assert_equal 'DEADLINE_SOON', @klazz.status
  end

  it 'should raise proper exception for invalid status EXPECTED_CRLF' do
    @klazz = Beaneater::UnexpectedResponse.from_status("EXPECTED_CRLF", "reserve 0")
    assert_kind_of(Beaneater::ExpectedCrlfError, @klazz)
    assert_equal 'reserve 0', @klazz.cmd
    assert_equal 'EXPECTED_CRLF', @klazz.status
  end


  describe "UnexpectedException" do
    let(:cause) { Exception.new("Dummy Exception") }
    let(:subject) { Beaneater::UnexpectedException.new(cause) }

    it "saves the exception that caused UnexpectedException" do
      assert_same subject.cause, cause
    end

    it "builds a relevant message using the cause Exception" do
      assert_equal "Unexpected exception: Dummy Exception", subject.message
    end

    it "changes the backtrace to include the cause's backtrace" do
      cause.set_backtrace(["1", "2", "3"])
      subject.set_backtrace(["4", "5", "6"])

      assert_equal ["1", "2", "3", "4", "5", "6"], subject.backtrace
    end
  end
end
