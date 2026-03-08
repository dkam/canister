require "test_helper"

class MediaManagerTest < ActiveSupport::TestCase
  setup do
    @manager = MediaManager.instance
    @manager.send(:idle)
    @manager.instance_variable_set(:@logs, [])
  end

  test "is a singleton" do
    assert_equal MediaManager.instance, MediaManager.instance
    assert_raises(NoMethodError) { MediaManager.new }
  end

  test "starts in idle state" do
    assert_equal :idle, @manager.status
    assert_equal "Waiting...", @manager.message
    assert_equal 0, @manager.current
    assert_equal 0, @manager.total
  end

  test "progress returns 0 when total is 0" do
    assert_equal 0, @manager.progress
  end

  test "progress calculates percentage" do
    @manager.current = 5
    @manager.total = 10
    assert_equal 50.0, @manager.progress
  end

  test "info adds log entry" do
    @manager.info("test message")
    assert_equal({type: :info, message: "test message"}, @manager.logs.first)
  end

  test "warn adds log entry" do
    @manager.warn("warning message")
    assert_equal({type: :warn, message: "warning message"}, @manager.logs.first)
  end

  test "error adds log entry" do
    @manager.error("error message")
    assert_equal({type: :error, message: "error message"}, @manager.logs.first)
  end

  test "debug adds log entry" do
    @manager.debug("debug message")
    assert_equal({type: :debug, message: "debug message"}, @manager.logs.first)
  end

  test "logs are prepended (newest first)" do
    @manager.info("first")
    @manager.info("second")
    assert_equal "second", @manager.logs.first[:message]
    assert_equal "first", @manager.logs.last[:message]
  end

  test "import does nothing when not idle" do
    @manager.instance_variable_set(:@status, :scan)
    @manager.import(job_id: "test")
    assert_equal :scan, @manager.status
  end

  test "export does nothing when not idle" do
    @manager.instance_variable_set(:@status, :scan)
    @manager.export(job_id: "test")
    assert_equal :scan, @manager.status
  end

  test "clean does nothing when not idle" do
    @manager.instance_variable_set(:@status, :scan)
    @manager.clean(job_id: "test")
    assert_equal :scan, @manager.status
  end

  test "scan does nothing when not idle" do
    @manager.instance_variable_set(:@status, :import)
    @manager.scan(job_id: "test")
    assert_equal :import, @manager.status
  end

test "scrape does nothing when not idle" do
    @manager.instance_variable_set(:@status, :import)
    @manager.scrape(job_id: "test", scraper: Object.new)
    assert_equal :import, @manager.status
  end
end
