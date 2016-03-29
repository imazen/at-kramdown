class Repositext
  class Validation
    class Validator

      # Validates consistency of spot corrections:
      #
      # * sanitizes corrections text whitespace
      #
      # Validates that:
      #
      # * Correction numbers are consecutive.
      # * `reads` and `submitted` fragments are not identical.
      # * `reads` fragments are unambiguous in given file and paragraph.
      # * `reads` is consistent with content AT (ignoring subtitle and gap_marks).
      class SpotSheet < Validator

        class InvalidCorrectionsFile < StandardError; end
        class InvalidCorrection < StandardError; end
        class InvalidCorrectionAndContentAt < StandardError; end

        # Runs all validations for self
        def run
          outcome = spot_sheet_valid?(@file_to_validate)
          log_and_report_validation_step(outcome.errors, outcome.warnings)
        end

      protected

        # @param accepted_corrections_file_name [String] absolute path to the corrections file
        # @return [Outcome]
        def spot_sheet_valid?(accepted_corrections_file_name)
          repository = @options['repository']
          language = repository.language
          accepted_corrections_file = Repositext::RFile::Text.new(
            File.read(accepted_corrections_file_name),
            language,
            accepted_corrections_file_name,
            repository
          )
          corrections = Process::Extract::SubmittedSpotCorrections.extract(
            accepted_corrections_file.contents
          )
          content_at = accepted_corrections_file.corresponding_content_at_contents

          errors = []
          warnings = []

          validate_corrections_file(
            accepted_corrections_file.contents, errors, warnings
          )
          validate_corrections(
            corrections, errors, warnings
          )
          validate_corrections_and_content_at(
            corrections, content_at, errors, warnings
          )

          Outcome.new(errors.empty?, nil, [], errors, warnings)
        end

        # Validates the corrections file in its entirety
        # @param corrections_file_contents [String]
        # @param [Array] errors collector for errors
        # @param [Array] warnings collector for warnings
        def validate_corrections_file(corrections_file_contents, errors, warnings)
          # Validate that no invalid characters are in correction file
          # NOTE: straight double quotes are allowed inside kramdown IALs, so we
          # convert them to a placeholder string ('<sdq>') for validation purposes.
          txt = corrections_file_contents.gsub(/(?<=\{)[^\{\}]*(?=\})/) { |inside_ial|
            inside_ial.gsub(/"/, '<sdq>')
          }

          invalid_chars = []
          [
            [/–/, 'EN DASH'],
            [/"/, 'Straight double quote'],
            [/'/, 'Straight single quote'],
            [/\r/, 'Carriage return'],
          ].each do |(regex, description)|
            s = StringScanner.new(txt)
            while !s.eos? do
              inv_char = s.scan_until(/.{,5}#{ regex }/) # match up to 5 chars before invalid char for reporting context
              if inv_char
                previous_text = txt[0..(s.pos - 1)]
                line_num = previous_text.count("\n") + 1
                context = s.matched[(-[10, s.matched.length].min)..-1] + s.rest[0,10]
                invalid_chars << " - #{ description } on line #{ line_num }: #{ context.inspect }"
              else
                s.terminate
              end
            end
          end
          if invalid_chars.any?
            loc = [@file_to_validate]
            desc = ['Contains invalid characters:'] + invalid_chars
            if 'merge' == @options['validate_or_merge']
              # This is part of `merge` command, raise an exception if we find error
              raise(InvalidCorrectionsFile.new((loc + desc).join("\n")))
            else
              errors << Reportable.error(loc, desc)
            end
          end
        end

        # Validates just the corrections for internal consistency.
        # @param corrections [Array<Hash>]
        # @param [Array] errors collector for errors
        # @param [Array] warnings collector for warnings
        def validate_corrections(corrections, errors, warnings)
          # Validate that each correction has the required attrs
          required_attrs_groups = [
            if 'merge' == @options['validate_or_merge']
              # This is part of merge
              [:becomes, :no_change]
            else
              # This is just a validation
              [:submitted]
            end,
            [:reads],
            [:correction_number],
            [:first_line],
            [:paragraph_number],
          ].compact
          corrections.each { |corr|
            if(mag =required_attrs_groups.detect { |attrs_group|
              # Are there any groups that have none of their attrs present in correction?
              attrs_group.none? { |attr| corr[attr] }
            })
              loc = [@file_to_validate, "Correction ##{ corr[:correction_number] }"]
              desc = ['Missing attributes', "One of `#{ mag.to_s }` is missing:", corr.inspect]
              if 'merge' == @options['validate_or_merge']
                # This is part of `merge` command, raise an exception if we find error
                raise(InvalidCorrection.new((loc + desc).join("\n")))
              else
                errors << Reportable.error(loc, desc)
              end
            end
          }

          # Validate that before and after are not identical
          corrections.each { |corr|
            if !corr[:no_change] && corr[:reads] == (corr[:becomes] || corr[:submitted])
              loc = [@file_to_validate, "Correction ##{ corr[:correction_number] }"]
              desc = [
                'Identical `Reads` and (`Becomes` or `Submitted`):',
                "`Reads`: `#{ corr[:reads].to_s }`, (`Becomes` or `Submitted`): `#{ (corr[:becomes] || corr[:submitted]).to_s }`",
              ]
              if 'merge' == @options['validate_or_merge']
                # This is part of `merge` command, raise an exception if we find error
                raise(InvalidCorrection.new((loc + desc).join("\n")))
              else
                errors << Reportable.error(loc, desc)
              end
            end
          }

          # Validate that we get consecutive correction_numbers
          correction_numbers = corrections.map { |e| e[:correction_number].to_i }.sort
          correction_numbers.each_cons(2) { |x,y|
            if y != x + 1
              loc = [@file_to_validate, "Correction ##{ y }"]
              desc = [
                'Non consecutive correction numbers:',
                "#{ x } was followed by #{ y }",
              ]
              if 'merge' == @options['validate_or_merge']
                # This is part of `merge` command, raise an exception if we find error
                raise(InvalidCorrection.new((loc + desc).join("\n")))
              else
                errors << Reportable.error(loc, desc)
              end
            end
          }
        end

        # Validates corrections as they relate to content at
        # @param corrections [Array<Hash>]
        # @param content_at [String]
        # @param [Array] errors collector for errors
        # @param [Array] warnings collector for warnings
        def validate_corrections_and_content_at(corrections, content_at, errors, warnings)
          corrections.each do |corr|
            content_at_relevant_paragraphs = Process::Extract::SpotCorrectionRelevantParagraphs.extract(
              corr,
              content_at
            )

            # Number of `Reads` occurrences
            num_reads_occurrences = content_at_relevant_paragraphs[:relevant_paragraphs].scan(
              corr[:reads]
            ).length
            # Validate that `reads` fragments are unambiguous in given file and paragraph.
            case num_reads_occurrences
            when 1
              # Found unambiguously, no errors to report.
              # This validates that `Reads` is specified unambiguously and matches
              # content at.
            when 0
              # Found none, report error
              loc = [@file_to_validate, "Correction ##{ corr[:correction_number] }"]
              desc = [
                'Corresponding content AT not found:',
                "`Reads`: #{ corr[:reads] }",
              ]
              if 'merge' == @options['validate_or_merge']
                # This is part of `merge` command, raise an exception if we find error
                raise(InvalidCorrectionAndContentAt.new((loc + desc).join("\n")))
              else
                errors << Reportable.error(loc, desc)
              end
            else
              # Found more than one, report error
              loc = [@file_to_validate, "Correction ##{ corr[:correction_number] }"]
              desc = [
                'Multiple instances of `Reads` found:',
                "Found #{ num_reads_occurrences } instances of `#{ corr[:reads] }`",
              ]
              if 'merge' == @options['validate_or_merge']
                # This is part of `merge` command, raise an exception if we find error
                raise(InvalidCorrectionAndContentAt.new((loc + desc).join("\n")))
              else
                errors << Reportable.error(loc, desc)
              end
            end

          end
        end

      end
    end
  end
end
