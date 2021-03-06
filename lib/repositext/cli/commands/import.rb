class Repositext
  class Cli
    # This namespace contains methods related to the `import` command.
    module Import

    private

      # Import from IDML and Folio sources and merge into /content
      def import_all(options)
        import_folio_xml_specific_steps(options)
        import_idml_specific_steps(options)
        import_shared_steps(options)
      end

      # Import from DOCX.
      #
      # A file will only be imported if any of the following conditions are met:
      #
      # * no corresponding content AT file exists OR
      # * If it exists, it doesn't contain any subtitles.
      #
      # TODO: When importing malayalam DOCX and we encounter an invalid br character
      # the entire import should be cancelled. However it does the copy step
      # from import_docx -> content
      # TODO: cancel the copy step and any other subsequent actions
      def import_docx(options)
        options['report_file'] ||= config.compute_glob_pattern(
          :docx_import_dir, :validation_report_file, ''
        )
        options['append_to_validation_report'] = false
        reset_validation_report(options, 'import_docx')
        validate_docx_pre_import(options)
        convert_docx_to_at(options)
        fix_normalize_trailing_newlines(options)
        fix_adjust_gap_mark_positions(options)
        # fix_normalize_editors_notes(
        #   options.merge({ 'base-dir' => :idml_import_dir, 'file-extension' => :at_extension })
        # )
        options['append_to_validation_report'] = true
        # fix_convert_abbreviations_to_lower_case(options) # run after merge_record_marks...
        # fix_normalize_subtitle_mark_before_gap_mark_positions(
        #   options.merge({ 'base-dir' => :staging_dir, 'file-extension' => :at_extension })
        # )
        fix_normalize_trailing_newlines(options)
        copy_docx_import_to_content(options)
        # Run post_import validation after docx.at file has been copied into
        # content. This is so that the validation console prints out the content
        # AT file path which is where corrections have to be made.
        # We want to be able to open content AT file with single click in editor.
        validate_docx_post_import(options)
        # Make sure that any newly created content AT files also have a
        # data.json file.
        # Deactivate st_sync for this new file by default
        fix_add_initial_data_json_file(
          options.merge(
            'initial_only_data_json_settings' => { 'st_sync_active' => false }
          )
        )
        fix_insert_record_mark_into_all_at_files(options)
        options['report_file'] ||= config.compute_glob_pattern(
          :content_dir, :validation_report_file, ''
        )
        options['append_to_validation_report'] = false
        reset_validation_report(options, 'import_docx')
        validate_content(options.merge('run_options' => []))
      end

      # Import FOLIO XML and merge into /content
      def import_folio_xml(options)
        import_folio_xml_specific_steps(options)
        import_shared_steps(options)
        compare_folio(options)
      end

      def import_gap_mark_tagging(options)
        # NOTE: Normally we don't modify import files, however when getting
        # gap_mark_tagging import files, e.g., from Chinese, the gap_marks
        # aren't always in the correct position relative to parens, brackets, etc.
        # Until we can enforce correct gap_mark positions (e.g., via web UI),
        # we will make an exception and run the fix_adjust_gap_mark_positions
        # script on the import file to avoid GapMarkTaggingImportConsistency::TextMismatchError
        input_base_dir = config.compute_base_dir(options['base-dir'] || :gap_mark_tagging_import_dir)
        input_file_extension = config.compute_file_extension(options['file-extension'] || :txt_extension)
        fix_adjust_gap_mark_positions(
          options.merge('base-dir' => input_base_dir, 'file-extension' => input_file_extension)
        )
        options['report_file'] ||= config.compute_glob_pattern(
          input_base_dir, :validation_report_file, ''
        )
        options['append_to_validation_report'] = false
        reset_validation_report(options, 'validate_gap_mark_tagging_import')
        validate_gap_mark_tagging_import(options.merge('run_options' => %w[pre_import]))
        merge_gap_mark_tagging_import_into_content_at(options)
        fix_normalize_subtitle_mark_before_gap_mark_positions(
          options.merge('base-dir' => :content_dir, 'file-extension' => :at_extension)
        )
        fix_normalize_trailing_newlines(options)
        options['append_to_validation_report'] = true
        if 'chn' == config.setting(:language_code_3_chars)
          # Don't check for gap_marks in invalid positions for chinese since
          # the validations rules don't apply to Chinese docs.
          options['skip_invalid_gap_mark_validation'] = true
        end
        validate_gap_mark_tagging_import(options.merge('run_options' => %w[post_import]))
      end

      def import_html(options)
        options['report_file'] ||= config.compute_glob_pattern(
          :html_import_dir, :validation_report_file, ''
        )
        options['append_to_validation_report'] = false
        reset_validation_report(options, 'validate_html_import')
        validate_html_import(options.merge('run_options' => %w[pre_import]))
        convert_html_to_at(options)
        fix_normalize_trailing_newlines(options)
        # any fixes
        copy_html_import_to_content(options)
        options['append_to_validation_report'] = true
        validate_html_import(options.merge('run_options' => %w[post_import]))
      end

      # Import IDML and merge into /content
      def import_idml(options)
        import_idml_specific_steps(options)
        import_shared_steps(options)
        compare_idml(options)
      end

      def import_subtitle(options)
        options['report_file'] ||= config.compute_glob_pattern(
          :subtitle_import_dir, :validation_report_file, ''
        )
        options['append_to_validation_report'] = false
        reset_validation_report(options, 'validate_subtitle_import')
        validate_subtitle_import(options.merge('run_options' => %w[pre_import]))
        merge_subtitle_marks_from_subtitle_import_into_content_at(options)
        fix_normalize_subtitle_mark_before_gap_mark_positions(
          options.merge({ 'base-dir' => :content_dir, 'file-extension' => :at_extension })
        )
        fix_normalize_trailing_newlines(options)

        if config.setting(:is_primary_repo)
          # NOTE: We update st_sync related data on a per file basis in
          #       `merge_subtitle_marks_from_subtitle_shared_into_content_at`
          # Flag st_sync as required on primary repo.
          repository.update_repo_level_data('st_sync_required' => true)
        end

        options['append_to_validation_report'] = true
        # NOTE: We have to run the subtitle import consistency validation before we
        # transfer subtitle operations to foreign files. Otherwise the validation
        # would fail because of st ops changes.
        validate_subtitle_import(options.merge('run_options' => %w[post_import_1]))

        if !config.setting(:is_primary_repo)
          # We're in a foreign repo, we transfer any subtitle operations that
          # have accumulated since the subtitle export.
          # NOTE 2: When calling this after a subtitle import, we have to re-apply
          # all st_ops that occurred since the subtitle export.
          sync_subtitles_for_foreign_files(
            options.merge('re-apply-st-ops-since-st-export' => true)
          )
        end

        # NOTE: We run the content validation (including SubtitleMarkCountsMatch)
        # after subtitle operations have been transferred to foreign files.
        # Otherwise subtitle counts would not match with foreign files.
        validate_subtitle_import(options.merge('run_options' => %w[post_import_2]))
        # At last we run a full content validation to make sure that no content
        # got lost and everything else is ok. NOTE: We're running some validations
        # multiple times post subtitle import. We're ok with this, want to err
        # on the side of caution.
        validate_content(options.merge('run_options' => []))
      end

      def import_subtitle_tagging(options)
        options['report_file'] ||= config.compute_glob_pattern(
          :subtitle_tagging_import_dir, :validation_report_file, ''
        )
        options['append_to_validation_report'] = false
        reset_validation_report(options, 'validate_subtitle_tagging_import')
        validate_subtitle_tagging_import(options.merge('run_options' => %w[pre_import]))
        merge_subtitle_marks_from_subtitle_tagging_import_into_content_at(options)
        fix_normalize_subtitle_mark_before_gap_mark_positions(
          options.merge({ 'base-dir' => :content_dir, 'file-extension' => :at_extension })
        )
        fix_normalize_trailing_newlines(options)
        if config.setting(:is_primary_repo)
          # Handle subtitle_marker CSV files only when we're working in the primary repo.
          copy_subtitle_marker_csv_files_to_content(
            options.merge({ 'base-dir' => :subtitle_tagging_import_dir, 'file-extension' => :txt_extension })
          )
          sync_subtitle_mark_character_positions(options)
        end
        options['append_to_validation_report'] = true
        validate_subtitle_tagging_import(options.merge('run_options' => %w[post_import]))
      end

      def import_test(options)
        # dummy method for testing
        puts 'import_test'
      end

    private

      # -----------------------------------------------------
      # Helper methods for DRY process specs
      # -----------------------------------------------------

      def import_folio_xml_specific_steps(options)
        options['report_file'] ||= config.compute_glob_pattern(
          :folio_import_dir, :validation_report_file, ''
        )
        options['append_to_validation_report'] = false
        reset_validation_report(options, 'import_folio_xml_specific_steps')
        validate_folio_xml_import(options.merge('run_options' => %w[pre_import]))
        convert_folio_xml_to_at(options)
        merge_titles_from_folio_roundtrip_compare_into_folio_import(options)
        fix_normalize_trailing_newlines(options)
        fix_remove_underscores_inside_folio_paragraph_numbers(options)
        fix_normalize_editors_notes(
          options.merge({ 'base-dir' => :folio_import_dir, 'file-extension' => :at_extension })
        ) # has to be invoked before fix_convert_folio_typographical_chars
        fix_convert_folio_typographical_chars(options)
        options['append_to_validation_report'] = true
        validate_folio_xml_import(options.merge('run_options' => %w[post_import]))
      end

      def import_idml_specific_steps(options)
        options['report_file'] ||= config.compute_glob_pattern(
          :idml_import_dir, :validation_report_file, ''
        )
        options['append_to_validation_report'] = false
        reset_validation_report(options, 'import_idml_specific_steps')
        validate_idml_import(options.merge('run_options' => %w[pre_import]))
        convert_idml_to_at(options)
        fix_normalize_trailing_newlines(options)
        fix_adjust_gap_mark_positions(options)
        fix_normalize_editors_notes(
          options.merge({ 'base-dir' => :idml_import_dir, 'file-extension' => :at_extension })
        )
        # set up filename transform for inserting record_marks
        fix_insert_record_mark_into_all_at_files(
          options.merge({
            'base-dir' => :idml_import_dir,
            'file-extension' => :at_extension,
          })
        )
        options['append_to_validation_report'] = true
        validate_idml_import(options.merge('run_options' => %w[post_import]))
      end

      # Specifies all shared steps that need to run after each Folio/IDML import
      def import_shared_steps(options)
        case config.setting(:folio_import_strategy)
        when 'merge_record_ids_into_idml'
          merge_record_marks_from_folio_xml_at_into_idml_at(options)
          # validate that all kramdown elements are nested inside record_mark
          validation_run_options = %w[kramdown_syntax_at-all_elements_are_inside_record_mark]
        when 'only_use_if_idml_not_present'
          merge_use_idml_or_folio(options)
          # skip validation that all kramdown elements are nested inside record_mark
          validation_run_options = []
        else
          raise "Invalid folio_import_strategy: #{ config.setting(:folio_import_strategy).inspect }"
        end
        fix_adjust_merged_record_mark_positions(options)
        fix_convert_abbreviations_to_lower_case(options) # run after merge_record_marks...
        fix_normalize_subtitle_mark_before_gap_mark_positions(
          options.merge({ 'base-dir' => :staging_dir, 'file-extension' => :at_extension })
        )
        fix_normalize_trailing_newlines(options)
        move_staging_to_content(options)
        # Make sure that any newly created content AT files also have a
        # data.json file.
        # Deactivate st_sync for this new file by default
        fix_add_initial_data_json_file(
          options.merge(
            'initial_only_data_json_settings' => { 'st_sync_active' => false }
          )
        )
        options['report_file'] ||= config.compute_glob_pattern(
          :content_dir, :validation_report_file, ''
        )
        options['append_to_validation_report'] = false
        reset_validation_report(options, 'import_shared_steps')
        validate_content(options.merge('run_options' => validation_run_options))
      end

    end
  end
end
