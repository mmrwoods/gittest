require 'rubygems'
require 'autotest'
require 'rbconfig'

class Gittest

  VERSION = '0.1.2'

  attr_reader :commit, :test_mappings

  # Create a new Gittest instance. Raises LoadError if current working directory not within a git repository. Changes current working directory to root of git repository.
  def initialize(commit='HEAD')
    # Force fast start option for autotest. Although not used directly here, hooks might 
    # do things like preparing test databases unless the fast start option is enabled.
    Autotest.respond_to?(:options) ? Autotest.options[:no_full_after_start] = true : $f = true
    raise LoadError, "Not in a git repository" unless silence_stream(STDERR) { system("git rev-parse") } # note: git rev-parse will exit 0 if it's in a repo
    cd_to_repository_root # note: I'm assuming that the repository root is the project root, and any .autotest file will be in the project root
    @at = Autotest.new
    @at.hook :initialize
    @test_mappings = @at.instance_eval { @test_mappings }
    @commit = commit
  end

  # Reset the known files and both new_or_modified_files and files_to_test values
  def reset
    @new_or_modified_files = nil
    @files_to_test = nil
  end

  # Returns the new or modified files, initially found by calling find_new_or_modified_files
  def new_or_modified_files
    @new_or_modified_files ||= find_new_or_modified_files
  end

  # Returns the files to test, initially found by calling find_files_to_test
  def files_to_test
    @files_to_test ||= find_files_to_test
  end

  # Finds new or modified files by executing git diff and parsing output
  def find_new_or_modified_files
    `git diff --name-only #{@commit}`.split("\n").uniq
  end

  # Finds files to test by checking if the autotest test mappings match any of the new or modified files
  def find_files_to_test
    @at.find_files # populate the known files, otherwise procs defined as part of test mappings may fail to find any matching files when called
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

  # Runs tests and ask autotest to handle the results. Also calls autotest :run_command and :ran_command hooks appropriately.
  def run_tests
    @at.hook :run_command
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

  private

  # Changes the working directory to the root path for the repository (assumes current working directory is within a repository)
  def cd_to_repository_root #:nodoc:
    loop do
      begin
        Dir.entries('.git')
        break
      rescue SystemCallError
        Dir.chdir('..')
        next
      end
    end
  end

  # Silences a stream for the duration of the block - copied directly from Rails Kernel extensions
  def silence_stream(stream) #:nodoc:
    old_stream = stream.dup
    stream.reopen(RbConfig::CONFIG['host_os'] =~ /mswin|mingw/ ? 'NUL:' : '/dev/null')
    stream.sync = true
    yield
  ensure
    stream.reopen(old_stream)
  end

end
