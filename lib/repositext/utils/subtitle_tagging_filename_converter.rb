class Repositext
  class Utils
    # Converts filenames between repositext and subtitle_tagging conventions.
    class SubtitleTaggingFilenameConverter

      # Maps from 3 to 2 character language codes
      LANGUAGE_CODE_MAP = [
        %w[eng en],
        %w[itl it],
      ].freeze

      # Converts a repositext filename to the corresponding subtitle_tagging_export one
      # like so:
      #
      # /eng47-0412_0002.at => /47-0412_0002.en.rt.txt
      #
      # @param[String] rt_filename the repositext filename
      # @return[String] the corresponding subtitle_tagging_export filename
      def self.convert_from_repositext_to_subtitle_tagging_export(rt_filename)
        lang_code = rt_filename.split('/').last[0,3] # should be 'eng'
        rt_filename.gsub(/\/#{ lang_code }/, '/')
                   .gsub(/\.at\z/, ".#{ convert_language_code(lang_code) }.rt.txt")
      end

      # Converts a repositext filename to the corresponding subtitle_tagging_import one
      # like so:
      #
      # /eng47-0412_0002.at => /47-0412_0002.en.txt
      #
      # NOTE: import filenames are like export ones, except without the `.rt` extension.
      # @param[String] rt_filename the repositext filename
      # @return[String] the corresponding subtitle_tagging filename
      def self.convert_from_repositext_to_subtitle_tagging_import(rt_filename)
        lang_code = rt_filename.split('/').last[0,3] # should be 'eng'
        rt_filename.gsub(/\/#{ lang_code }/, '/')
                   .gsub(/\.at\z/, ".#{ convert_language_code(lang_code) }.txt")
      end

      # Converts a subtitle_tagging filename to the corresponding repositext one
      # like so:
      #
      # /47-0412_0002.en.txt => /eng47-0412_0002.at
      #
      # @param[String] st_filename the subtitle_tagging filename
      # @return[String] the corresponding repositext filename
      def self.convert_from_subtitle_tagging_import_to_repositext(st_filename)
        lang_code = st_filename.match(//) # should be 'en'
        st_filename.gsub(/(\d\d\/)(\d\d)/, ['\1', convert_language_code(lang_code), '\2'].join)
                   .gsub(/\.#{ lang_code }\.txt\z/, '.at')
      end

    private

      # Converts language codes from 3 to 2 character ones.
      # @param[String] lang_code a 2 or 3 character language code
      def self.convert_language_code(lang_code)
        r = case lang_code.length
        when 2
          # return corresponding 3 char code
          mapping = language_code_map.detect { |e| lang_code.downcase == e.last }
          mapping ? mapping.first : nil
        when 3
          # return corresponding 2 char code
          mapping = language_code_map.detect { |e| lang_code.downcase == e.first }
          mapping ? mapping.last : nil
        else
          raise(ArgumentError.new("Invalid lang_code length, must be 2 or 3 chars: #{ lang_code.inspect }"))
        end
        raise(ArgumentErrorlnew("Unknown lang_code: #{ lang_code.inspect }"))  if r.nil?
        r
      end

    end
  end
end
