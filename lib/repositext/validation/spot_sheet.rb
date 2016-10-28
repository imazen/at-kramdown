class Repositext
  class Validation
    # Validation to run before accepting spot corrections.
    class SpotSheet < Validation

      # Specifies validations to run
      def run_list
        validate_files(:accepted_corrections_files) do |path|
          Validator::SpotSheet.new(
            path, @logger, @reporter, @options
          ).run
        end
      end

    end
  end
end
