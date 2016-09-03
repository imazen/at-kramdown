class Repositext
  class Process
    class Compute

      # Computes subtitle operations for an entire repository. Going from
      # git commit `from_git_commit` to git commit `to_git_commit`.
      class SubtitleOperationsForRepository

        # Initializes a new instance from high level objects.
        # @param content_type [Repositext::ContentType]
        # @param from_git_commit [String]
        # @param to_git_commit [String]
        # @param file_list [Array<String>] path to files to include
        def initialize(content_type, from_git_commit, to_git_commit, file_list)
          @content_type = content_type
          @repository = @content_type.repository
          @language = @content_type.language
          @from_git_commit = from_git_commit
          @to_git_commit = to_git_commit
          # Convert to repo relative paths
          @file_list = file_list.map { |e| e.sub!(@repository.base_dir, '') }
        end

        # @return [Repositext::Subtitle::OperationsForRepository]
        def compute
          if @repository.latest_commit_sha_local != @to_git_commit
            raise ArgumentError.new(
              [
                "`to_git_commit` is not the latest commit in repo #{ @repository.name }. We haven't confirmed that this works!",
                "Latest git commit: #{ @repository.latest_commit_sha_local.inspect }",
                "to_git_commit: #{ @to_git_commit.inspect }",
              ]
            )
          end

          # We get the diff only so that we know which files have changed.
          diff = @repository.diff(@from_git_commit, @to_git_commit, context_lines: 0)

          operations_for_all_files = diff.patches.map { |patch|
            file_name = patch.delta.old_file[:path]
            next nil  if !@file_list.include?(file_name)

            # Skip non content_at files
            unless file_name =~ /\/content\/.+\d{4}\.at\z/
              raise "shouldn't get here"
            end

            puts "     - process #{ file_name }"

            absolute_file_path = File.join(@repository.base_dir, file_name)
            content_at_file_to = Repositext::RFile::ContentAt.new(
              File.read(absolute_file_path),
              @language,
              absolute_file_path,
              @content_type
            )

            soff = SubtitleOperationsForFile.new(
              content_at_file_to,
              @repository.base_dir,
              {
                from_git_commit: @from_git_commit,
                to_git_commit: @to_git_commit,
              }
            ).compute

            # Return nil if no subtitle operations exist for this file
            soff.operations.any? ? soff : nil
          }.compact

          ofr = Repositext::Subtitle::OperationsForRepository.new(
            {
              repository: @repository.name,
              from_git_commit: @from_git_commit,
              to_git_commit: @to_git_commit,
            },
            operations_for_all_files
          )

          ofr
        end

      end

    end
  end
end
