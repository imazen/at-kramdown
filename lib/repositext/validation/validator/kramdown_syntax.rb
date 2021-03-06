class Repositext
  class Validation
    class Validator
      # Validates a kramdown string's valid syntax.
      class KramdownSyntax < Validator

        # Returns true if content_at_file contains valid kramdown
        # * parse document using repositext-kramdown
        # * walk the element tree
        #     * check each element against kramdown feature whitelist
        #     * concatenate inner texts into Array of Hashes with strings and corresponding location
        #     * detect any potential ambiguities
        #     * check each IAL against class names whitelist
        # * check inner text string for unprocessed kramdown
        # @param content_at_file [RFile::ContentAt] the file to validate
        # @param options [Hash, optional]
        def valid_kramdown_syntax?(content_at_file, options = {})
          inner_texts = []
          errors = []
          warnings = []
          classes_histogram = Hash.new(0)

          validate_character_inventory(content_at_file, errors, warnings)
          validate_source(content_at_file, errors, warnings)
          validate_escaped_character_syntax(content_at_file, errors, warnings)

          validate_parse_tree(content_at_file, inner_texts, classes_histogram, errors, warnings)
          validate_inner_texts(content_at_file, inner_texts, errors, warnings)

          Outcome.new(errors.empty?, nil, [], errors, warnings)
        end

        # @param content_at_file [RFile::ContentAt] the file to validate
        # @param errors [Array] collector for errors
        # @param warnings [Array] collector for warnings
        def validate_source(content_at_file, errors, warnings)
          # Detect disconnected IAL
          str_sc = Kramdown::Utils::StringScanner.new(content_at_file.contents)
          while !str_sc.eos? do
            if (match = str_sc.scan_until(/\n\s*?\n(\{:[^\}]+\})\s*?\n\s*?\n/))
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                ['Disconnected IAL']
              )
            else
              break
            end
          end
          # Detect gap_marks (%) inside of words, asterisks, quotes (straight or
          # typographic), parentheses, or brackets.
          # NOTE: We allow gap_marks to immediately follow words if the mark is
          # followed by `…?…` or `—` (emdash).
          # NOTE: This section is very similar to the next section where we
          # check subtitle_marks.
          # The regex can be overridden via data.json file under the key
          # "validator_invalid_gap_mark_regex".
          invalid_gap_mark_regex = Regexp.new(
            @options['validator_invalid_gap_mark_regex'] ||
            "(?<=[[:alpha:]\\*\"“”'‘’\\(\\[])%(?!(…?…|—))"
          )
          str_sc.reset
          while !str_sc.eos? do
            if (match = str_sc.scan_until(invalid_gap_mark_regex))
              next  if @options['skip_invalid_gap_mark_validation']
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                [':gap_mark (%) at invalid position']
              )
            else
              break
            end
          end
          # Detect subtitle_marks (@) inside of words, asterisks, quotes (straight or
          # typographic), parentheses, or brackets.
          # NOTE: We allow subtitle_marks to immediately follow words if the mark is
          # followed by `…?…` or `—` (emdash).
          # NOTE: This section is very similar to the previous section where we
          # check gap_marks.
          # The regex can be overridden via data.json file under the key
          # "validator_invalid_subtitle_mark_regex".
          invalid_subtitle_mark_regex = Regexp.new(
            @options['validator_invalid_subtitle_mark_regex'] ||
            "(?<=[[:alpha:]\\*\"“”'‘’\\(\\[])@(?!(…?…|—))"
          )
          str_sc.reset
          while !str_sc.eos? do
            if (match = str_sc.scan_until(invalid_subtitle_mark_regex))
              next  if "…*@" == match[-3..-1] # allow subtitle marks after ellipsis and asterisk
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                [':subtitle_mark (@) at invalid position']
              )
            else
              break
            end
          end
          # Detect paragraphs that are not followed by two newlines.
          str_sc.reset
          while !str_sc.eos? do
            if(
              match = str_sc.scan_until(
                /
                  \n\{:[^}]*\} # block IAL
                  (?=( # followed by one of
                    \n[^\n] # single newline
                    | # OR
                    \n{3,} # 3 or more newlines
                  ))
                /x
              )
            )
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                ['Paragraph not followed by exactly 2 newlines']
              )
            else
              break
            end
          end
          # Detect unexpected line breaks
          str_sc.reset
          while !str_sc.eos? do
            if (match = str_sc.scan_until(/[^\n]\n(?!(\n|\{:|\z))/))
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                ['Unexpected line break']
              )
            else
              break
            end
          end
          # Detect multiple adjacent spaces
          str_sc.reset
          while !str_sc.eos? do
            if (match = str_sc.scan_until(/ {2,}/))
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                ['More than one adjacent space character']
              )
            else
              break
            end
          end
          # Detect trailing spaces at the end of lines
          str_sc.reset
          while !str_sc.eos? do
            # We check for regular space, no-break space, narrow no-break space, and zero-width no-break space
            if (match = str_sc.scan_until(/[ \u00A0\u202F\uFEFF](?=\n)/))
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                ['Trailing whitespace character']
              )
            else
              break
            end
          end
          # Detect invalid elipses: '...' or '. . .'
          str_sc.reset
          while !str_sc.eos? do
            if (match = str_sc.scan_until(/\.\.\.|\. \. \./))
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                ['Invalid elipsis']
              )
            else
              break
            end
          end
          # Detect non-empty horizontal rule paras
          str_sc.reset
          while !str_sc.eos? do
            if (match = str_sc.scan_until(/(?<!^)\* \* \*|\* \* \*(?!$)/))
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                ['Invalid horizontal rule']
              )
            else
              break
            end
          end
          # Detect spaces in chinese titles
          # TBD
          # # TODO: Detect adjacent periods (instead of elipses)
          # str_sc.reset
          # while !str_sc.eos? do
          #   if (match = str_sc.scan_until(/\.{2,}/))
          #     errors << Reportable.error(
          #       [
          #         @file_to_validate.filename,
          #         sprintf("line %5s", str_sc.current_line_number)
          #       ],
          #       ['Adjacent periods. Should this be an elipsis instead?']
          #     )
          #   else
          #     break
          #   end
          # end
        end

        # @param content_at_file [RFile::ContentAt] the file to validate
        # @param inner_texts [Array<Hash>] collector for inner texts
        # @param classes_histogram [Hash] collector for histogram of used classes
        # @param errors [Array] collector for errors
        # @param warnings [Array] collector for warnings
        def validate_parse_tree(content_at_file, inner_texts, classes_histogram, errors, warnings)
          kd_root = @options['kramdown_validation_parser_class'].parse(
            content_at_file.contents
          ).first
          validate_element(
            content_at_file,
            kd_root,
            [],
            inner_texts,
            classes_histogram,
            errors,
            warnings
          )
          if 'debug' == @logger.level
            # capture classes histogram
            classes_histogram = classes_histogram.sort_by { |k,v|
              k
            }.map { |(classes, count)|
              sprintf("%-15s %5d", classes.join(', '), count)
            }
            reporter.add_stat(
              Reportable.stat(
                { filename: content_at_file.filename },
                ['Classes Histogram', classes_histogram]
              )
            )
          end
        end

        # @param content_at_file [RFile::ContentAt] the file to validate
        # @param el [Kramdown::Element]
        # @param el_stack [Array<Kramdown::Element] stack of ancestor elements,
        #   immediate parent is last element in array.
        # @param content_at_file [RFile::ContentAt] the file to validate
        # @param inner_texts [Array<Hash>] collector for inner texts
        # @param classes_histogram [Hash] collector for histogram of used classes
        # @param errors [Array] collector for errors
        # @param warnings [Array] collector for warnings
        def validate_element(content_at_file, el, el_stack, inner_texts, classes_histogram, errors, warnings)
          validation_hook_on_element(content_at_file, el, el_stack, errors, warnings)
          # check if element's type is whitelisted
          if !whitelisted_kramdown_features.include?(el.type)
            errors << Reportable.error(
              {
                filename: content_at_file.filename,
                line: el.options[:location],
                context: el.element_summary,
              },
              [
                'Invalid kramdown feature',
                ":#{ el.type }"
              ]
            )
          end
          if (
            ial = el.options[:ial]) &&
            (klasses = ial['class']) &&
            (klasses = klasses.split(' ')
          )
            # check if element has classes and if so whether all classes are
            # whitelisted.
            if klasses.any? { |k|
              !whitelisted_class_names.map{ |e| e[:name] }.include?(k)
            }
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: el.options[:location],
                  context: el.element_summary,
                },
                [
                  'Invalid class name',
                  "'#{ klasses }'",
                ]
              )
            end
            # Build classes inventory
            if 'debug' == @logger.level
              classes_histogram[klasses.sort] += 1
            end
          end
          # collect inner_texts of :text elements
          if :text == el.type && (t = el.value) && ![" ", "\n", nil].include?(t)
            inner_texts << { :text => t, :location => el.options[:location] }
          end
          # then iterate over children
          el.children.each { |child|
            # Append el to el_stack passsed to child elements
            validate_element(
              content_at_file,
              child,
              el_stack << el,
              inner_texts,
              classes_histogram,
              errors, warnings
            )
          }
        end

        # Use this callback to implement custom validations for subclasses.
        # Called once for each element when walking the tree.
        # @param content_at_file [RFile::ContentAt] the file to validate
        # @param el [Kramdown::Element]
        # @param el_stack [Array<Kramdown::Element] stack of ancestor elements,
        #   immediate parent is last element in array.
        # @param errors [Array] collector for errors
        # @param warnings [Array] collector for warnings
        def validation_hook_on_element(content_at_file, el, el_stack, errors, warnings)
          # NOTE: Implement in sub-classes
        end

        # Validates the inner_texts we collected during validate_parse_tree
        # to check if any invalid characters are entered, or any unprocessed
        # kramdown characters remain, indicating kramdown syntax errors.
        # @param content_at_file [RFile::ContentAt] the file to validate
        # @param inner_texts [Array<Hash>] where we check for kramdown leftovers
        # @param errors [Array] collector for errors
        # @param warnings [Array] collector for warnings
        def validate_inner_texts(content_at_file, inner_texts, errors, warnings)
          inner_texts.each do |it|
            # Detect leftover '*' or '_' kramdown syntax characters or equal signs
            match_data = it[:text].to_enum(
              :scan,
              /
                .{0,10} # capture up to 10 preceding characters on same line
                [\*\_\=]  # detect any asterisks, underscores or equal signs
                .{0,10} # capture up to 10 following characters on same line
              /x
            ).map { Regexp.last_match }
            match_data.each do |e|
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: it[:location],
                  context: e.to_s,
                },
                ['Leftover kramdown character or equal sign', e[0]]
              )
            end
          end
        end

        # @param content_at_file [RFile::ContentAt] the file to validate
        # @param errors [Array] collector for errors
        # @param warnings [Array] collector for warnings
        def validate_character_inventory(content_at_file, errors, warnings)
          # Detect invalid characters
          str_sc = Kramdown::Utils::StringScanner.new(content_at_file.contents)
          soft_hyphen_context_window = 10 # how much context to show around soft hyphens
          while !str_sc.eos? do
            if (match = str_sc.scan_until(
              Regexp.union(self.class.invalid_character_detectors)
            ))
              context = if "\u00AD" == match[-1]
                # Print context around soft hyphens, replace soft with hard hyphen
                " inside '#{ match[-soft_hyphen_context_window..-2] }-#{ str_sc.rest[0..soft_hyphen_context_window] }'"
              else
                ''
              end
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                ['Invalid character', sprintf('U+%04X', match[-1].codepoints.first) + context]
              )
            else
              break
            end
          end
          # Build character inventory
          if 'debug' == @logger.level
            chars = Hash.new(0)
            ignored_chars = [0x30..0x39, 0x41..0x5A, 0x61..0x7A]
            source.codepoints.each { |cp|
              chars[cp] += 1  unless ignored_chars.any? { |r| r.include?(cp) }
            }
            chars = chars.sort_by { |k,v|
              k
            }.map { |(code,count)|
              sprintf("U+%04x  #{ code.chr('UTF-8') }  %5d", code, count)
            }
            reporter.add_stat(
              Reportable.stat(
                { filename: content_at_file.filename },
                ['Character Histogram', chars]
              )
            )
          end
        end

        def whitelisted_kramdown_features
          self.class.whitelisted_kramdown_features
        end

        def whitelisted_class_names
          self.class.whitelisted_class_names
        end

        # TODO: add validation that doesn't allow more than one class on any paragraph
        # e.g., "{: .normal_pn .q}" is not valid. This applies ot both PT and AT.

        # @param content_at_file [RFile::ContentAt] the file to validate
        # @param errors [Array] collector for errors
        # @param warnings [Array] collector for warnings
        def validate_escaped_character_syntax(content_at_file, errors, warnings)
          # Unlike kramdown, in repositext the following characters are not
          # escaped: `:`, `[`, `]`, `'`
          str_sc = Kramdown::Utils::StringScanner.new(content_at_file.contents)
          while !str_sc.eos? do
            if (match = str_sc.scan_until(/\\[\:\[\]\`]/))
              errors << Reportable.error(
                {
                  filename: content_at_file.filename,
                  line: str_sc.current_line_number,
                  context: match[-40..-1].inspect,
                },
                ['Character that should not be escaped is escaped:', match[-2..-1].inspect]
              )
            else
              break
            end
          end
        end

      end
    end
  end
end
