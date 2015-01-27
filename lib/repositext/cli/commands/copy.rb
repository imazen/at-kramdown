class Repositext
  class Cli
    module Copy

    private

      # Copies HTML imported AT files to content. Also renames files like so:
      # eng59-0125_0547.html.at => eng59-0125_0547.at
      # @param options [Hash]
      def copy_html_import_to_content(options)
        input_base_dir = config.compute_base_dir(options['base-dir'] || :html_import_dir)
        input_file_selector = config.compute_file_selector(options['file-selector'] || :all_files)
        input_file_extension = config.compute_file_extension(options['file-extension'] || :at_extension)
        output_base_dir = options['output'] || config.base_dir(:content_dir)

        Repositext::Cli::Utils.copy_files(
          input_base_dir,
          input_file_selector,
          input_file_extension,
          output_base_dir,
          options['file_filter'],
          "Copying HTML imported AT files to content",
          options.merge(
            :output_path_lambda => lambda { |input_filename|
              input_filename.gsub(input_base_dir, output_base_dir)
                            .gsub(/\.html\.at\z/, '.at')
            }
          )
        )
      end

      # Copies subtitle_marker csv files to content for subtitle import. Also renames files like so:
      # 59-0125_0547.markers.txt => eng59-0125_0547.subtitle_markers.csv
      # @param options [Hash]
      # @option options [String] 'base-dir': (required) one of 'subtitle_tagging_import_dir' or 'subtitle_import_dir'
      # @option options [String] 'file-pattern': defaults to 'txt_files', can be custom pattern
      def copy_subtitle_marker_csv_files_to_content(options)
        input_base_dir = config.compute_base_dir(options['base-dir'])
        input_file_selector = config.compute_file_selector(options['file-selector'] || :all_files)
        input_file_extension = config.compute_file_extension(options['file-extension'] || :txt_extension)
        output_base_dir = options['output'] || config.base_dir(:content_dir)

        Repositext::Cli::Utils.copy_files(
          input_base_dir,
          input_file_selector,
          input_file_extension,
          output_base_dir,
          options['file_filter'] || /\.markers\.txt\z/,
          "Copying subtitle marker CSV files from subtitle_tagging_import_dir to content_dir",
          options.merge(
            :output_path_lambda => lambda { |input_filename|
              input_filename.gsub(input_base_dir, output_base_dir)
                            .gsub(
                              /\/([^\/\.]+)\.markers\.txt/,
                              '/' + config.setting(:language_code_3_chars) + '\1.subtitle_markers.csv'
                            )
            }
          )
        )
      end

      # Copies subtitle_marker csv files from content to subtitle export.
      # Also renames files like so:
      # eng59-0125_0547.subtitle_markers.csv => 59-0125_0547.markers.txt
      def copy_subtitle_marker_csv_files_to_subtitle_export(options)
        input_base_dir = config.compute_base_dir(options['base-dir'] || :content_dir)
        input_file_selector = config.compute_file_selector(options['file-selector'] || :all_files)
        input_file_extension = config.compute_file_extension(options['file-extension'] || :csv_extension)
        # grab source marker_csv file from primary repo
        primary_repo_input_base_dir = input_base_dir.sub(
          config.base_dir(:rtfile_dir), config.primary_repo_base_dir
        )
        output_base_dir = options['output'] || config.base_dir(:subtitle_export_dir)
        Repositext::Cli::Utils.copy_files(
          primary_repo_input_base_dir,
          input_file_selector,
          input_file_extension,
          output_base_dir,
          options['file_filter'] || /\.subtitle_markers\.csv\z/,
          "Copying subtitle marker CSV files from content_dir to subtitle_export_dir",
          options.merge(
            :output_path_lambda => lambda { |input_filename|
              input_filename.gsub(primary_repo_input_base_dir, output_base_dir)
                            .gsub(
                              /\/[[:alpha:]]{3}([^\/\.]+)\.subtitle_markers\.csv/,
                              '/\1.markers.txt'
                            )
            }
          )
        )
      end

    end
  end
end
