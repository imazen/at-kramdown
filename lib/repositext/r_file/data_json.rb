class Repositext
  class RFile
    # Represents a .data.json file in repositext.
    class DataJson < RFile

      include FollowsStandardFilenameConvention
      include HasCorrespondingContentAtFile
      include HasCorrespondingPrimaryContentAtFile
      include HasCorrespondingPrimaryFile

      # Creates an empty data.json file. Raises an error if the file already
      # exists.
      # @param filename
      def self.create_empty_data_json_file!(filename)
        if File.exist?(filename)
          raise "File `#{ filename }` already exists!"
        end
        File.write(filename, default_file_contents)
      end

      # Returns the default contents for a data.json file
      # @return [String] JSON formatted string
      def self.default_file_contents
        JSON.generate(default_data, json_formatting_options) + "\n"
      end

      # Returns default data as Hash
      def self.default_data
        { 'data' => {}, 'settings' => {} }
      end

      def self.json_formatting_options
        {
          indent: '  ',
          space: '',
          space_before: '',
          object_nl: "\n",
          array_nl: "\n",
          allow_nan: false,
          max_nesting: 100,
        }
      end

      # Returns all key value pairs as hash
      def get_all_attributes
        (JSON.load(contents) || self.class.default_data)
      end

      def json_formatting_options
        self.class.json_formatting_options
      end

      def read_data
        get_all_attributes['data'] || {}
      end

      def read_settings
        get_all_attributes['settings'] || {}
      end

      # Updates key_val_pairs under the 'data' key in self.
      # @param key_val_pairs [Hash] with string keys
      def update_data!(key_val_pairs)
        lock_self_exclusively do
          # merge key_val_pairs under 'data' key
          new_data = get_all_attributes
          new_data['data'] ||= {}
          new_data['data'].merge!(key_val_pairs)
          # write file back to disk
          File.write(
            filename,
            JSON.generate(new_data, json_formatting_options) + "\n"
          )
        end
      end
    end
  end
end
