# encoding UTF-8
class Repositext
  class Process
    class Sync

      # Synchronizes subtitles from English to foreign repos.
      #
      class Subtitles

        class ReposNotReadyError < StandardError; end
        class InvalidInputDataError < StandardError; end

        include EnsureAllContentReposAreReady
        include ExtractOrLoadPrimarySubtitleOperations
        include FinalizeSyncOperation
        include TransferAccumulatedStOpsToForeignFile
        include TransferSubtitleOperationsToForeignRepos
        include UpdatePrimarySubtitleMarkerCsvFiles

        # Initialize a new subtitle sync process
        # @param options [Hash] with stringified keys
        # @option options [Config] 'config'
        # @option options [Array<String>] 'file_list' can be used at command
        #                                 line via file-selector to limit which
        #                                 files should be synced.
        # @option options [String, Nil] 'from-commit', optional, defaults to previous `to-commit`
        # @option options [Repository] 'repository' the primary repo
        # @option options [IO] stids_inventory_file
        # @option options [String, Nil] 'to-commit', optional, defaults to most recent local git commit
        def initialize(options)
          @config = options['config']
          @file_list = options['file_list']
          @from_git_commit = options['from-commit']
          @repository = options['repository']
          @stids_inventory_file = options['stids_inventory_file']
          @to_git_commit = options['to-commit']
        end

        def sync
          @from_git_commit, @to_git_commit = compute_bounding_git_commits(
            @from_git_commit,
            @to_git_commit,
            @config,
            @repository
          )
          if @from_git_commit == @to_git_commit
            raise "Subtitles are up-to-date, nothing to sync!".color(:red)
          end

          # ensure_all_content_repos_are_ready
          st_ops_for_repo, created_new_st_ops_file = extract_or_load_primary_subtitle_operations
          if created_new_st_ops_file
            # We update CSV marker files only if a new st_ops file was created.
            # If we reuse an existing one, then CSV marker files have been updated
            # already and we don't want to do it again.
            update_primary_subtitle_marker_csv_files(@repository, st_ops_for_repo)
          end
          transfer_subtitle_operations_to_foreign_repos!(st_ops_for_repo)
          finalize_sync_operation(
            @repository,
            @to_git_commit,
            st_ops_for_repo.affected_content_at_files
          )
        end

      private

        # Computes `from` and `to` git commits
        # @param from_g_c_override [String, nil]
        # @param to_g_c_override [String, nil]
        # @param config [Config]
        # @param repo [Repository]
        # @return [Array<String>] the `from` and `to` git commit sha1 strings
        def compute_bounding_git_commits(from_g_c_override, to_g_c_override, config, repo)
          from_git_commit = compute_from_commit(from_g_c_override, config, repo)
          to_git_commit = compute_to_commit(to_g_c_override, repo)
          [from_git_commit, to_git_commit]
        end

        # Computes the `from` commit
        # @param commit_sha1_override [String, Nil]
        # @param config [Repositext::Cli::Config]
        # @param repository [Repository]
        def compute_from_commit(commit_sha1_override, config, repository)
          # Use override if given
          if '' != (o = commit_sha1_override.to_s)
            return o
          end
          # Load from repository's data.json file
          from_setting = repository.read_repo_level_data['st_sync_commit']
          raise "Missing st_sync_commit datum".color(:red)  if from_setting.nil?
          # Load `from` and `to` commits from latest st-ops file as array
          from_latest_st_ops_file = Subtitle::OperationsFile.compute_latest_from_and_to_commits(
            config.base_dir(:subtitle_operations_dir)
          )
          # Verify that setting and file name are consistent, either `from` or `to`
          # commit. If setting is consistent with `from` commit, then the st-ops
          # file already exists and we'll re-use it. If setting is consistent
          # with `to` commit, then st-ops file doesn't exist yet and we'll
          # create it.
          if from_latest_st_ops_file.any? && !from_latest_st_ops_file.include?(from_setting.first(6))
            raise([
              "Inconsistent from_git_commit: Setting is #{ from_setting.inspect }",
              "and latest st-ops file has `from` and `to` commits #{ from_latest_st_ops_file.inspect }"
            ].join(' ').color(:red))
          end
          # Return consistent value from setting
          from_setting
        end

        # Computes the `to` commit
        # @param commit_sha1_override [String, Nil]
        # @param repository [Repositext::Repository]
        def compute_to_commit(commit_sha1_override, repository)
          # Use override if given
          if '' != (o = commit_sha1_override.to_s)
            return o
          end
          # Use latest commit from repository
          repository.latest_commit_sha_local
        end

      end
    end
  end
end
