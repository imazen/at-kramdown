class Repositext
  class Cli
    module Utils

      # Utils module provides methods commonly used by the rt commands

      # Changes files in place, updating their contents
      # @param: See #process_files below for param description
      def self.change_files_in_place(file_pattern, file_filter, description, options, &block)
        # Use input file path
        output_path_lambda = lambda do |input_filename, output_file_attrs|
          input_filename
        end
        process_files(
          file_pattern, file_filter, description, output_path_lambda, options, &block
        )
      end

      # Converts files from one format to another
      # @param: See #process_files below for param description
      def self.convert_files(file_pattern, file_filter, description, options, &block)
        # Change file extension only.
        output_path_lambda = lambda do |input_filename, output_file_attrs|
          replace_file_extension(input_filename, output_file_attrs[:extension])
        end

        process_files(
          file_pattern, file_filter, description, output_path_lambda, options, &block
        )
      end

      # Exports files to another format and location
      # @param: See #process_files below for param description
      # @param[String] out_dir the output base directory
      def self.export_files(file_pattern, out_dir, file_filter, description, options, &block)
        # Change output file path
        output_path_lambda = lambda do |input_filename, output_file_attrs|
          File.join(
            out_dir,
            File.basename(input_filename, File.extname(input_filename)) + "." + output_file_attrs[:extension]
          )
        end

        process_files(
          file_pattern, file_filter, description, output_path_lambda, options, &block
        )
      end

      # Does a dry-run of the process. Printing out all debug and logging info
      # but not saving any changes to disk.
      # @param: See #process_files below for param description
      # @param[String] out_dir the output base directory
      def self.dry_run_process(file_pattern, out_dir, file_filter, description, options, &block)
        # Always return empty string to skip writing to disk
        output_path_lambda = lambda do |input_filename, output_file_attrs|
          ''
        end

        process_files(
          file_pattern, file_filter, description, output_path_lambda, options, &block
        )
      end

      # Processes files
      # @param[String] file_pattern A Dir.glob file pattern that describes
      #     the file set to be operated on. This is typically provided by either
      #     Rtfile or as command line argument by the user.
      # @param[Trequal] file_filter Each file's name (and path) is compared with
      #     file_filter using ===. The file will be processed if the comparison
      #     evaluates to true. file_filter can be anything that responds to
      #     #===, e.g., a Regexp, a Proc, or a String.
      #     This is provided by the callling command, limiting the files to be
      #     operated on to valid file types.
      #     See here for more info on ===: http://ruby.about.com/od/control/a/The-Case-Equality-Operator.htm
      # @param[String] description A description of the operation, used for logging.
      # @param[Proc] output_path_lambda A proc that computes the output file
      #     path as string. It is given the input file path and output file attrs.
      #     If output_path_lambda returns '' (empty string), no files will be written.
      # @param[Hash] options
      #     :input_is_binary to force File.binread where required
      #     :output_is_binary
      # @param[Proc] block A Proc that performs the desired operation on each file.
      #     Arguments to the proc are each file's name and contents.
      #     Calling block is expected to return an Array of Outcome objects, one
      #     for each file, with the following attrs:
      #       * success:  Boolean
      #       * result:   A hash with :contents and :extension keys
      #       * messages: An array of message strings.
      def self.process_files(file_pattern, file_filter, description, output_path_lambda, options, &block)
        $stderr.puts "#{ description } at #{ file_pattern }."
        $stderr.puts '-' * 80
        start_time = Time.now
        total_count = 0
        success_count = 0
        updated_count = 0
        unchanged_count = 0
        created_count = 0
        errors_count = 0

        Dir.glob(file_pattern).each do |filename|

          if file_filter && !(file_filter === filename) # file_filter has to be LHS of `===`
            $stderr.puts " - Skipping #{ filename }"
            next
          end

          begin
            $stderr.puts " - Processing #{ filename }"
            contents = if options[:input_is_binary]
              File.binread(filename).freeze
            else
              File.read(filename).freeze
            end
            outcomes = block.call(contents, filename)

            outcomes.each do |outcome|
              if outcome.success
                output_file_attrs = outcome.result
                new_path = output_path_lambda.call(filename, output_file_attrs)
                # new_path is either a file path or the empty string (in which
                # case we don't write anything to the file system).
                # NOTE: it's not enough to just check File.exist?(new_path) for
                # empty string in testing as FakeFS returns true. So I also
                # need to check for empty string separately to make tests work.
                existing_contents = if ('' != new_path && File.exist?(new_path))
                  options[:output_is_binary] ? File.binread(new_path) : File.read(new_path)
                else
                  nil
                end
                new_contents = output_file_attrs[:contents]
                message = outcome.messages.join("\n")

                if(nil == existing_contents)
                  write_file_unless_path_is_blank(new_path, new_contents)
                  created_count += 1
                  $stderr.puts "  * Create: #{ new_path } #{ message }"
                elsif(existing_contents != new_contents)
                  write_file_unless_path_is_blank(new_path, new_contents)
                  updated_count += 1
                  $stderr.puts "  * Update: #{ new_path } #{ message }"
                else
                  unchanged_count += 1
                  $stderr.puts "    Leave as is: #{ new_path } #{ message }"
                end
                success_count += 1
              else
                $stderr.puts "  x  Error: #{ message }"
                errors_count += 1
              end
            end
          rescue => e
            $stderr.puts "  x  Error: #{ e.class.name } - #{ e.message } - #{errors_count == 0 ? e.backtrace : ''}"
            errors_count += 1
          end
          total_count += 1
        end

        $stderr.puts '-' * 80
        $stderr.puts "Finished processing #{ success_count } of #{ total_count } files in #{ Time.now - start_time } seconds."
        $stderr.puts "* #{ created_count } files created"  if created_count > 0
        $stderr.puts "* #{ updated_count } files updated"  if updated_count > 0
        $stderr.puts "* #{ unchanged_count } files left unchanged"  if unchanged_count > 0
        $stderr.puts "* #{ errors_count } errors"  if errors_count > 0
      end

      # Replaces filename's extension with new_extension. If filename doesn't have
      # an extension, adds new_extension.
      # @param[String] filename the source filename with old extension
      # @param[String] new_extension the new extension to use, e.g., '.idml'
      # @return[String] filename with new_extension
      def self.replace_file_extension(filename, new_extension)
        filename = filename.gsub(/\.\z/, '') # remove dot at end if filename ends with dot
        existing_ext = File.extname(filename)
        basepath = if '' == existing_ext
          filename
        else
          filename[0...-existing_ext.length]
        end
        new_extension = '.' + new_extension.sub(/\A\./, '')
        basepath + new_extension
      end

      # Writes file_contents to file at file_path. Overwrites existing file.
      # Doesn't write to file if file_path is blank (nil, empty string, or string
      # with only whitespace)
      # @param[String] file_path
      # @param[String] file_contents
      # @return[Integer, Nil] the number of bytes written or false if nothing was written
      def self.write_file_unless_path_is_blank(file_path, file_contents)
        if '' == file_path.to_s.strip
          $stderr.puts %(  - Skip writing "#{ file_contents.truncate_in_the_middle(60) }" to blank file_path)
          false
        else
          dir = File.dirname(file_path)
          unless File.directory?(dir)
            FileUtils.mkdir_p(dir)
          end
          File.write(file_path, file_contents)
        end
      end

      # Computes a base_dir from glob_pattern
      # @param[String] glob_pattern
      # @return[String] the base dir
      def self.base_dir_from_glob_pattern(glob_pattern)
        if glob_pattern !~ /\A\//
          raise ArgumentError.new("Please provide an absolute path.")
        end
        # split into path segments
        # then build up until we hit the first asterisk or the file name
        glob_pattern.split(File::SEPARATOR)
                    .find_all { |e| '' != e }
                    .inject('/') { |m,e|
                      if e =~ /\*|\w\.\w/
                        break(m)
                      else
                        m << e
                        m << File::SEPARATOR
                      end
                      m
                    }
      end
    end
  end
end
