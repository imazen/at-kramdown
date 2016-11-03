class Repositext
  class Validation
    # Validation to after a PDF export.
    class PdfExport < Validation

      # Specifies validations to run related to PDF export.
      def run_list
        validate_files(:exported_pdfs) do |path|
          next  if path.index('.--') # skip files that have title added to filename. Those are from a previous export.

          Validator::PdfExportConsistency.new(
            path, @logger, @reporter, @options
          ).run
        end
      end

    end
  end
end
