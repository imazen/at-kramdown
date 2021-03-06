class Repositext
  class Process
    class Export
      # Exports content_at to gap_mark_tagging.
      class GapMarkTagging

        # Initializes a new exporter.
        # @param [String] content_at
        def initialize(content_at)
          @content_at = content_at
        end

        # Exports content_at to gap_mark_tagging.
        # Uses Suspension to remove everything but:
        #  * gap_marks
        #  * paragraph IALs
        #  * headers
        # @return [Outcome] where result is gap_mark_tagging text
        def export
          # NOTE: In order to preserve sub-title text (which may contain gap_marks,
          # we need to retain them and remove the hash marks in post-processing)
          # Remove all tokens but :subtitle_mark from content_at
          gmt = @content_at.dup
          gmt = pre_process(gmt)
          gmt = suspend_unwanted_tokens(gmt)
          gmt = post_process(gmt)
          Outcome.new(true, gmt)
        end

      protected

        def pre_process(txt)
          gmt = txt.dup
          # temporarily replace underscores in IALs, otherwise they'd be removed
          # by Suspension as :emphasis tokens
          gmt.gsub!('_', "(underscore placeholder)")
          gmt
        end

        def suspend_unwanted_tokens(txt)
          Suspension::TokenRemover.new(
            txt,
            Suspension::REPOSITEXT_TOKENS.find_all { |e|
              ![
                :gap_mark,
                :header_atx,
                :ial_block,
                :ial_span,
              ].include?(e.name)
            }
          ).remove
        end

        def post_process(txt)
          gmt = txt.dup
          gmt.gsub!(/(?<!\n)\{[^\}]+\}/, '') # remove inline IALs
          gmt.gsub!('(underscore placeholder)', '_') # convert underscore placeholders to underscores
          gmt
        end

      end
    end
  end
end
