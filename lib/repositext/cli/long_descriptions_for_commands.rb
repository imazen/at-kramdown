class Repositext
  class Cli
    # This namespace provides the long descriptions for Thor commandline commands.
    module LongDescriptionsForCommands

      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods

        def long_description_for_compare
          %(
            Compares files for consistency.

            Available SPECs:

            [TBD]
          )
        end

        def long_description_for_convert
          %(
            Converts files from one format to another, using Repositext Parsers and
            Converters. Has sensible defaults for input file patterns.
            Stores output files in same directory as input files.

            Available SPECs:

            folio_xml_to_at - Converts Folio XML files in import_folio to AT
            kramdown files, storing the output files in the same directory as
            the input files.

            idml_to_at - Converts IDML files in import_idml to AT kramdown files,
            storing the output files in the same directory as the input files.

            Examples:

            * bundle exec rt convert idml_to_at
          )
        end

        def long_description_for_copy
          %(
            Copies files from one location to another.

            Available SPECs:

            Examples:

            * bundle exec rt copy subtitle_marker_csv_files_to_content
          )
        end

        def long_description_for_data
          %(
            Manipulates the contents of data.json files.

            Available SPECs:

            Examples:

            * bundle exec rt data set_st_sync_active_to_false
          )
        end

        def long_description_for_delete
          %(
            Deletes files

            Available SPECs:

            Examples:

            * bundle exec rt delete all_pdf_exports
          )
        end

        def long_description_for_distribute
          %(
            Distributes files to final destination.

            Available SPECs:

            Examples:

            * bundle exec rt distribute add_title_to_filename
          )
        end

        def long_description_for_fix
          %(
            Modifies files in place. Updates contents of existing files.

            Available SPECs:

            adjust_merged_record_mark_positions - move :record_marks to the right
            spot after merging them into IDML AT.

            folio_typographical_chars - changes double dashes, triple periods
            and double quotes to the correct typographical symbols.
          )
        end

        def long_description_for_git_repo
          %(
            Performs operations on git repositories.
          )
        end

        def long_description_for_init
          %(
            Generates a default Rtfile in the current working directory if it doesn't
            exist already. Can be forced to overwrite an existing Rtfile.

            This command ignores the '--input' option.
          )
        end

        def long_description_for_merge
          %(
            Merges the contents of two files and writes the result to an output
            file, typically using a suspension-based operation.
            Each of the two input files contributes a different kind of data.
            This is the equivalent of a SQL left outer join where we merge the
            first and second file (if the second file exists), or we just use
            the first file if the second file doesn't exist.

            Available SPECs:

            record_marks_from_folio_xml_at_into_idml_at - merges :record_marks
            from FOLIO XML imported AT into IDML imported AT.
          )
        end

        def long_description_for_move
          %(
            Moves files from one location to another.

            Available SPECs:

            staging_to_content - moves AT files from /staging to /content
          )
        end

        def long_description_for_release
          %(
            Releases a product.
          )
        end

        def long_description_for_report
          %(
            Generates a report for the repository.

            Available SPECs:

            folio_import_warnings - summarizes Folio import warnings
          )
        end

        def long_description_for_split
          %(
            Splits files in /content.

            Available SPECs:

            subtitles - splits subtitles
          )
        end

        def long_description_for_sync
          %(
            Syncs data between different file types in /content.
            Applies a suspension-based operation between files of different types.

            Available SPECs:

            [TBD]
          )
        end

        def long_description_for_validate
          %(
            Validates files. Uses Profiles to determine which validations to run.
            The validate command usually requires the --base-dir, --file-selector,
            and --file-extension options since it has no defaults.

            Available SPECs:

            utf8_encoding

            Example:

            bundle exec repositext validate utf8_encoding --base-dir=/dir1/dir2/folio_import_dir --file-pattern=at_files
          )
        end

        def long_description_for_export
          %(
            Exports files from /content, performing all steps required to generate
            files of the desired output file type.

            Available SPECs:

            [TBD]

            Options:

            --additional-footer-text="Some extra text" - adds text to the footer of an exported PDF
          )
        end

        def long_description_for_import
          %(
            Imports files from a source, performs all steps required to merge changes
            into /content

            Available SPECs:

            all - Imports from all sources (FOLIO XML, IDML) and merges updates
            into /content.

            folio_xml - Imports from FOLIO XML and merges updates into /content.

            idml - Imports from IDML and merges updates into /content.
          )
        end

      end
    end
  end
end
