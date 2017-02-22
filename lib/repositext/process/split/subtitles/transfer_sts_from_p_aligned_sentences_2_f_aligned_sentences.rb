class Repositext
  class Process
    class Split
      class Subtitles

        # This name space provides methods for transferring subtitles from
        # primary to foreign aligned sentences.
        module TransferStsFromPAlignedSentences2FAlignedSentences

          # @param asp [Array<Array<String, Nil>>] the aligned sentence pairs.
          #   [["p sentence 1", "f sentence 1"], ["p sentence 1", nil], ...]
          # @return [Outcome] with Array of foreign sentence and confidence as result.
          def transfer_sts_from_p_aligned_sentences_2_f_aligned_sentences(asp)
            asp_w_f_sts = []

            # Remove any gaps in asp
            asp.each { |(p_s, f_s)|
              raise "Both sentences are empty"  if('' == p_s && '' == f_s)
              raise "Unexpected nil sentence"  if p_s.nil? || f_s.nil?

              if '' == p_s
                # Primary sentence gap:
                # * Append foreign sentence to previous foreign sentence.
                # * Reduce confidence.
                prev_f_s = asp_w_f_sts.last
                asp_w_f_sts[-1] = [
                  prev_f_s[0],
                  prev_f_s[1] + ' ' + f_s, # insert a space
                  0.0
                ]
                if debug
                  puts "Removed gap, f_s: #{ f_s.inspect }"
                  puts " - prev asp: #{ asp_w_f_sts[-1].inspect }"
                end
              elsif '' == f_s
                # Foreign sentence gap:
                # * Append primary sentence to previous primary sentence so that
                #   subtitle count validation has correct data.
                # * Append primary subtitles to previous foreign sentence so
                #   that no subtitles are lost in foreign.
                # * Reduce confidence.
                prev_f_s = asp_w_f_sts.last
                asp_w_f_sts[-1] = [
                  prev_f_s[0] + ' ' + p_s,
                  prev_f_s[1] + ('@' * p_s.count('@')),
                  0.0
                ]
                if debug
                  puts "Removed gap, p_s: #{ p_s.inspect }"
                  puts " - prev asp: #{ asp_w_f_sts[-1].inspect }"
                end
              else
                # Complete pair, transfer subtitles to foreign sentence
                f_s_w_st_o = transfer_subtitles_to_foreign_sentence(p_s, f_s)
                f_s_w_st, f_s_conf = f_s_w_st_o.result
                asp_w_f_sts << [p_s, f_s_w_st, f_s_conf]
              end
            }

            # Return foreign_sentence and confidence, drop primary sentence
            f_s_w_sts = asp_w_f_sts.map { |e| e[1] }
            f_s_confs = asp_w_f_sts.map { |e| e[2] }

            validate_same_number_of_sts_in_p_and_f(asp_w_f_sts)

            Outcome.new(true, [f_s_w_sts, f_s_confs])
          end

          # Transfers subtitles from primary sentence to foreign sentence.
          # @param p_s [String] primary sentence with subtitles
          # @param f_S [String] foreign sentence without subtitles
          # @return [Outcome] with the foreign sentence with subtitles inserted
          #   and sentence confidence as result.
          def transfer_subtitles_to_foreign_sentence(p_s, f_s)
            subtitle_count = p_s.count('@')
            if 0 == subtitle_count
              # Return as is
              Outcome.new(true, [f_s, 1.0])
            elsif((1 == subtitle_count) && (p_s =~ /\A@/))
              # Prepend one subtitle
              Outcome.new(true, ['@' << f_s, 1.0])
            else
              transfer_subtitles(p_s, f_s, subtitle_count)
            end
          end

          # Inserts multiple subtitles based on word interpolation.
          # @param p_s [String] primary sentence with subtitles
          # @param f_S [String] foreign sentence without subtitles
          # @param subtitle_count [Integer] number of subtitles in p_s
          # @return [Outcome] with the foreign sentence with subtitles inserted
          #   and confidence as result.
          def transfer_subtitles(p_s, f_s, subtitle_count)

            # Do a simple character based interpolation for subtitle_mark positions
            new_f_s_raw = interpolate_subtitle_positions(p_s, f_s)

            # Snap subtitle_marks to nearby punctuation
            new_f_s_snapped_to_punctuation_o = snap_subtitles_to_punctuation(
              p_s,
              new_f_s_raw
            )

            Outcome.new(
              true,
              new_f_s_snapped_to_punctuation_o.result
            )
          end

          # @param p_s [String] primary sentence with subtitles
          # @param f_S [String] foreign sentence without subtitles
          # @return [String] the new f_s with subtitles inserted.
          def interpolate_subtitle_positions(p_s, f_s)
            primary_chars = p_s.chars
            primary_subtitle_indexes = primary_chars.each_with_index.inject([]) { |m, (char, idx)|
              m << idx  if '@' == char
              m
            }
            foreign_chars = f_s.chars
            word_scale_factor = foreign_chars.length / primary_chars.length.to_f
            foreign_subtitle_indexes = primary_subtitle_indexes.map { |e|
              (e * word_scale_factor).round
            }
            # Insert subtitles at proportional character position, may be inside
            # a word. We reverse the array so that earlier inserts don't affect
            # positions of later ones.
            foreign_subtitle_indexes.reverse.each { |i|
              foreign_chars.insert(i, '@')
            }
            # Re-build foreign sentence with subtitle_marks added
            r = foreign_chars.join
            # Move subtitle marks to beginning of word if they are inside a word
            r.gsub(/(\S+)@/, '@\1')
          end


          # @param p_s [String] primary sentence with subtitles
          # @param new_f_s_raw [String] foreign sentence with interpolated subtitles
          # @return [String] the new f_s with subtitles snapped to punctuation.
          def snap_subtitles_to_punctuation(p_s, new_f_s_raw)
            # Then we check if we can further optimize subtitle_mark positions:
            # If the subtitle mark comes after secondary punctuation in primary,
            # then we check if the same punctuation is nearby the position of
            # the corresponding foreign subtitle_mark.
            p_captions = p_s.split(/(?=@)/)
            f_captions = new_f_s_raw.split(/(?=@)/)
            sentence_confidence = 1.0

            punctuation_regex_list = Regexp.escape(".,;:!?")
            # Set max_snap_distance based on total sentence length. Range for
            # snap distance is from 10 to 40 characters.
            # Sentences range from 50 to 450 characters.
            max_snap_distance = (
              [
                [(p_s.length / 10.0), 10].max,
                40
              ].min
            ).round

            p_captions.each_with_index do |curr_p_c, idx|
              next  if 0 == idx # nothing to do for first caption
              curr_f_c = f_captions[idx]
              next  if curr_f_c.nil?
              prev_f_c = f_captions[idx-1]
              prev_p_c = p_captions[idx-1]

              if(primary_punctuation_md = prev_p_c.match(/([#{ punctuation_regex_list }])\s?\z/))
                # Previous caption ends with punctuation. Try to see if
                # there is punctuation nearby the corresponding foreign
                # subtitle_mark. Note that the foreign punctuation could be
                # different from the primary one.
                primary_punctuation = primary_punctuation_md[1]

                # Detect nearby foreign punctuation
                leading_punctuation, txt_between_punctuation_and_stm = if(
                  before_md = prev_f_c.match(
                    /([#{ punctuation_regex_list }])\s([^#{ punctuation_regex_list }]{1,#{ max_snap_distance }}\s*)\z/
                  )
                )
                  # Previous foreign caption has punctuation shortly before
                  # current subtitle_mark.
                  [before_md[1], before_md[2]]
                else
                  [nil, nil]
                end
                txt_between_stm_and_punctuation, trailing_punctuation = if(
                  after_md = curr_f_c.match(
                    /\A@([^#{ punctuation_regex_list }]{,#{ max_snap_distance }})([#{ punctuation_regex_list }]\s*)/
                  )
                )
                  # Current foreign caption has punctuation shortly after
                  # current subtitle_mark.
                  [after_md[1], after_md[2]]
                else
                  [nil, nil]
                end
                trailing_punctuation_str = (trailing_punctuation || '').strip

                # Determine where to move the subtitle_mark
                matches_count = [txt_between_punctuation_and_stm, txt_between_stm_and_punctuation].compact.length
                snap_to = if 0 == matches_count
                  # No nearby punctuation found either before or after, nothing to do
                  :none
                elsif 1 == matches_count
                  if txt_between_punctuation_and_stm
                    # We only have nearby punctuation before the subtitle_mark
                    :before
                  elsif txt_between_stm_and_punctuation
                    # We only have nearby punctuation after the subtitle_mark
                    :after
                  else
                    raise "Handle this!"
                  end
                elsif 2 == matches_count
                  # We found nearby punctuation both before and after, use the
                  # same punctuation as primary (if different), or the closer one.
                  if leading_punctuation == primary_punctuation && trailing_punctuation_str != primary_punctuation
                    # Only leading punctuation equals primary
                    :before
                  elsif leading_punctuation != primary_punctuation && trailing_punctuation_str != primary_punctuation
                    # Only trailing punctuation equals primary
                    :after
                  elsif txt_between_punctuation_and_stm.length < txt_between_stm_and_punctuation.length
                    # We can't use punctuation type, use the closer one
                    :before
                  else
                    :after
                  end
                else
                  raise "Handle this!"
                end

                # Move subtitle_mark to closest punctuation
                case snap_to
                when :before
                  # Move text from end of prev_f_c to beginning of curr_f_c
                  curr_f_c.sub!(/\A(@?)/, '\1' + txt_between_punctuation_and_stm)
                  prev_f_c.sub!(
                    /#{ Regexp.escape(txt_between_punctuation_and_stm) }\z/,
                    ''
                  )
                  sentence_confidence *= 0.8

                when :after
                  # Move text from beginning of curr_f_c to end of prev_f_c
                  full_txt_to_move = txt_between_stm_and_punctuation + trailing_punctuation
                  prev_f_c << full_txt_to_move
                  curr_f_c.sub!(full_txt_to_move, '')
                  sentence_confidence *= 0.8

                when :none

                else
                  raise "Handle this: #{ snap_to.inspect }"
                end
              end
            end

            Outcome.new(true, [f_captions.join, sentence_confidence])
          end

          # Validates that in each pair primary and foreign have the same
          # number of subtitles.
          # @param asp_w_f_sts [Array<Array>] with first item p_s and second item f_s
          def validate_same_number_of_sts_in_p_and_f(asp_w_f_sts)
            p_st_count = asp_w_f_sts.inject(0) { |m,e| m += e[0].count('@') }
            f_st_count = asp_w_f_sts.inject(0) { |m,e| m += e[1].count('@') }
            if p_st_count != f_st_count
              raise "Mismatch in subtitle counts: primary has #{ p_st_count } and foreign has #{ f_st_count }"
            end
            true
          end


        end
      end
    end
  end
end
