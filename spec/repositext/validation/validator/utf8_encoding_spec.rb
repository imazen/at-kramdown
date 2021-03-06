require_relative '../../../helper'

class Repositext
  class Validation
    class Validator

      describe Utf8Encoding do

        before do
          # Redirect console output for clean test logs
          # NOTE: use STDOUT.puts if you want to print something to the test output
          @stderr = $stderr = StringIO.new
          @stdout = $stdout = StringIO.new
        end

        let(:logger) { LoggerTest.new(nil, nil, nil, nil, nil) }
        let(:reporter) { ReporterTest.new(nil, nil, nil, nil) }

        [
          'utf8-valid.txt'
        ].each do |filename|
          it "passes a valid file: #{ filename }" do
            r_file = get_r_file(
              contents: File.read(
                get_test_data_path_for("/repositext/validation/validator/utf8_encoding/valid/" + filename)
              )
            )
            Utf8Encoding.new(r_file, logger, reporter, {}).run
            reporter.errors.must_equal []
          end
        end

        [
          'iso-8859-5-cyrillic.txt',
          'iso-8859-7-greek.txt',
          'utf8_invalid_byte_sequence-invalid_bytes_1.txt',
          'utf8_invalid_byte_sequence-invalid_bytes_2.txt',
          'utf8_invalid_byte_sequence-invalid_bytes_3.txt',
          'utf8_invalid_byte_sequence-invalid_bytes_4.txt',
          'utf8_invalid_byte_sequence-non_minimal_multi_byte_characters_1.txt',
          'utf8_invalid_byte_sequence-non_minimal_multi_byte_characters_2.txt',
          'utf8_invalid_byte_sequence-utf_16_surrogates_1.txt',
          'utf8_invalid_byte_sequence-utf_16_surrogates_2.txt',
          'windows-1255-hebrew.txt',
          'windows-1256-arabic.txt'
        ].each do |filename|
          it "flags file with invalid encoding #{ filename }" do
            r_file = get_r_file(
              contents: File.read(
                get_test_data_path_for("/repositext/validation/validator/utf8_encoding/invalid/" + filename)
              ),
              filename: filename
            )
            Utf8Encoding.new(r_file, logger, reporter, {}).run
            reporter.errors.size.must_equal 1
            reporter.errors.all? { |e|
              e.location[:filename].index(filename) && 'Invalid encoding' == e.details.first
            }.must_equal true
          end
        end

        [
          'utf8_with_bom.txt',
        ].each do |filename|
          it "flags file with bom #{ filename }" do
            r_file = get_r_file(
              contents: File.read(
                get_test_data_path_for("/repositext/validation/validator/utf8_encoding/invalid/" + filename)
              ),
              filename: filename
            )
            Utf8Encoding.new(r_file, logger, reporter, {}).run
            reporter.errors.size.must_equal 1
            reporter.errors.all? { |e|
              e.location[:filename].index(filename) && 'Unexpected BOM' == e.details.first
            }.must_equal true
          end
        end

      end

    end
  end
end
