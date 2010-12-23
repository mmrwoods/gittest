require 'rubygems'
require 'autotest'

# autotest options
$f = true # never run the entire test/spec suite on startup
$v = false
$h = false
$q = false
$DEBUG = false
$help = false

class Gittest

  VERSION = '0.0.1'

  attr_reader :commit, :test_mappings

  def initialize(commit='HEAD')
    @at = Autotest.new
    @at.hook :initialize
    @test_mappings = @at.instance_eval { @test_mappings }
    @commit = commit
  end

  def reset
    @new_or_modified_files = nil
    @files_to_test = nil
  end

  def new_or_modified_files
    @new_or_modified_files ||= find_new_or_modified_files
  end

  def files_to_test
    @files_to_test ||= find_files_to_test
  end

  def find_new_or_modified_files
    `git diff --name-only #{@commit}`.split("\n").uniq
  end

  def find_files_to_test
    files_to_test = @at.new_hash_of_arrays
    new_or_modified_files.each do |f|
      next if f =~ @at.exceptions # skip exceptions
      result = @test_mappings.find { |file_re, ignored| f =~ file_re }
      unless result.nil?
        [result.last.call(f, $~)].flatten.each {|match| files_to_test[match] if File.exist?(match)}
      end
    end
    return files_to_test
  end

  def run_tests
    cmd = @at.make_test_cmd(files_to_test)
    # copied from Autotest#run_tests and updated to use ansi colours in TURN enabled test output and specs run with the format option set to specdoc
    colors = { :red => 31, :green => 32, :yellow => 33 }
    old_sync = $stdout.sync
    $stdout.sync = true
    results = []
    line = []
    begin
      open("| #{cmd}", "r") do |f|
        until f.eof? do
          c = f.getc or break
          # putc c
          line << c
          if c == ?\n then
            str = if RUBY_VERSION >= "1.9" then
                              line.join
                            else
                              line.pack "c*"
                            end
            results << str
            line.clear
            if str.match(/(PASS|FAIL|ERROR)$/)
              # test output
              case $1
                when 'PASS' ; color = :green
                when 'FAIL' ; color = :red
                when 'ERROR' ; color = :yellow
              end
              print "\e[#{colors[color]}m" + str + "\e[0m"
            elsif str.match(/^\- /)
              # spec output 
              if str.match(/^\- .*(ERROR|FAILED) \- [0-9]+/)
                color = $1 == 'FAILED' ? :red : :yellow 
                print "\e[#{colors[color]}m" + str + "\e[0m"
              else
                print "\e[#{colors[:green]}m" + str + "\e[0m"
              end
            else
              print str
            end
          end
        end
      end
    ensure
      $stdout.sync = old_sync
    end
    @at.hook :ran_command
    @at.handle_results(results.join)
  end

end
