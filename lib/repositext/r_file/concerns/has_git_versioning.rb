class Repositext
  class RFile
    # Provides behavior around git versioning
    module HasGitVersioning

      extend ActiveSupport::Concern

      # Returns copy of self with contents as of a ref_commit or one of its
      # children.
      # relative_version can be one of:
      #   * :at_ref - Returns contents as of the ref_commit.
      #   * :at_child_or_current
      #     Returns contents at a child commit if it affected self, otherwise
      #     current file contents.
      #   * :at_child_or_nil
      #     Returns contents at a child commit if it affected self, otherwise nil.
      #   * :at_child_or_ref
      #     Returns contents at a child commit if it affected self, otherwise the
      #     contents at reference commit.
      # @param ref_commit [String]
      # @param relative_version [Symbol]
      # @return [RFile, nil]
      def as_of_git_commit(ref_commit, relative_version=:at_ref)
        if !ref_commit.is_a?(String)
          raise ArgumentError.new("Invalid ref_commit: #{ ref_commit.inspect }")
        end
        if '' == ref_commit.to_s
          raise ArgumentError.new("Invalid ref_commit: #{ ref_commit.inspect }")
        end

        # Get any child commits of ref_commit that affected self.
        cmd = [
          "git",
          "--git-dir=#{ repository.repo_path }",
          "log",
          "--format='%H %P'",
          "--",
          repo_relative_path,
          %(| grep -F " #{ ref_commit }"),
          '| cut -f1 -d" "',
        ].join(' ')
        all_child_commit_sha1s, _ = Open3.capture2(cmd)
        child_commit_including_self = (all_child_commit_sha1s.lines.first || '').strip

        # Instantiate copy of self with contents as of the requested relative_version
        new_contents = case relative_version
        when :at_ref
          # Use contents as of ref_commit
          get_contents_as_of_git_commit(ref_commit)
        when :at_child_or_current
          if '' == child_commit_including_self
            # Use current file contents
            is_binary ? File.binread(filename) : File.read(filename)
          else
            # Use file contents at child commit
            get_contents_as_of_git_commit(child_commit_including_self)
          end
        when :at_child_or_nil
          if '' == child_commit_including_self
            # Return nil instead of RFile
            nil
          else
            # Use file contents at child commit
            get_contents_as_of_git_commit(child_commit_including_self)
          end
        when :at_child_or_ref
          # Use contents at a child commit if it affected self, otherwise use contents at ref_commit.
          if '' == child_commit_including_self
            # Use file contents at ref_commit
            get_contents_as_of_git_commit(ref_commit)
          else
            # Use file contents at child commit
            get_contents_as_of_git_commit(child_commit_including_self)
          end
        else
          raise "Handle this: #{ relative_version.inspect }"
        end
        if new_contents.nil?
          # Return nil, not a new instance of self
          nil
        else
          # Return new instance of self with updated contents
          self.class.new(new_contents, language, filename, content_type)
        end
      end

      # Returns the latest git commit that included self. Before_time is optional
      # and defaults to now.
      # @param before_time [Time, optional]
      # @return [Rugged::Commit]
      def latest_git_commit(before_time=nil)
        return nil  if repository.nil?
        repository.latest_commit(filename, before_time)
      end

    protected

      # Gets contents of self after git_commit. Returns nil if self did not yet
      # exist at git_commit.
      # @param git_commit [String]
      # @return [String, Nil]
      def get_contents_as_of_git_commit(git_commit)
        cmd = "git --git-dir=#{ repository.repo_path } --no-pager show #{ git_commit }:#{ repo_relative_path }"
        file_contents, process_status = Open3.capture2(cmd)
        process_status.success? ? file_contents : nil
      end

    end
  end
end
