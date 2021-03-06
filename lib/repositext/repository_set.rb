class Repositext

  # Represents a collection of git content and code repositories.
  # Assumes that all repositories are siblings in the same folder.
  #
  # Expects current directory to be a repositext content repo root path.
  #
  # Usage example:
  #     repository_set = RepositorySet.new('/repositories/parent/path')
  #     repository_set.git_pull(:all_content_repos)
  class RepositorySet

    attr_reader :repo_set_parent_path

    # @param repo_set_parent_path [String] path to the folder that contains all repos.
    def initialize(repo_set_parent_path)
      @repo_set_parent_path = repo_set_parent_path
    end

    def all_content_repo_names
      [primary_repo_name] + foreign_content_repo_names
    end

    def all_repo_names
      all_content_repo_names + code_repo_names
    end

    # Returns an array of paths to all repos in repo_set_spec
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    def all_repo_paths(repo_set_spec)
      compute_repo_paths(repo_set_spec)
    end

    # Returns an array of all repos in repo_set
    def all_repos(repo_set)
      repo_class = if repo_set.is_a?(Symbol) && repo_set.to_s.include?('_content_')
        Repository::Content
      else
        Repository
      end
      all_repo_paths(repo_set).map{ |e| repo_class.new(e) }
    end

    def code_repo_names
      core_code_repo_names + %w[
        suspension
      ]
    end

    def core_code_repo_names
      %w[
        repositext
      ]
    end

    # Run `delete_all_pdf_exports` in all repositories
    def delete_all_pdf_exports(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } delete all_pdf_exports")
    end

    # Run `export pdf_book` in all repositories
    def export_pdf_book(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } export pdf_book")
    end

    def fix_add_first_par_class(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } fix add_first_par_class")
    end

    def fix_add_initial_data_json_file(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } fix add_initial_data_json_file")
    end

    def fix_normalize_trailing_newlines(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } fix normalize_trailing_newlines")
    end

    def foreign_content_repo_names
      %w[
        french
        german
        italian
        spanish
      ]
    end

    # Extracting the git clone command so that it can be overridden in subclasses.
    # @param repo_name [String]
    def git_clone_command(repo_name)
      "git clone <repo clone url>#{ repo_name }.git"
    end

    # Clones all git repos that don't exist on local filesystem yet.
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    # @example Clone all language repos
    #   # cd into primary repo root folder
    #   # run `bundle console`
    #   repository_set = Repositext::RepositorySet.new('/path/to/repos/parent/folder')
    #   repository_set.git_clone_missing_repos(:all_content_repos)
    def git_clone_missing_repos(repo_set_spec)
      compute_repo_paths(repo_set_spec).each { |repo_path|
        repo_name = repo_path.split('/').last
        if File.exist?(repo_path)
          puts " -   Skipping #{ repo_name }"
          next
        end
        puts " - Cloning #{ repo_name }"
        clone_command = git_clone_command(repo_name)
        cmd = %(cd #{ repo_set_parent_path } && #{ clone_command })
        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          exit_status = wait_thr.value
          if exit_status.success?
            puts "   - Cloned #{ repo_name }"
          else
            msg = %(Could not clone #{ repo_name }:\n\n)
            puts(msg + stderr.read)
          end
        end
      }
    end

    # Makes sure that all content repos are ready for git operations:
    # * They are on master branch
    # * They have no uncommitted changes
    # * They pulled latest from origin
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    # @yield [repo_path] will be called for each repo.
    # @return [Hash] with repos that are not ready. Keys are repo paths, values
    #     are arrays with issue messages if any exist.
    def git_ensure_repos_are_ready(repo_set_spec)
      # TODO: when we use this from st_sync we only want to include repos that have
      # st_sync_active set to true. We already have a method that gives us a list of
      # all synced repos. Maybe we could move this check to Repository... Then we
      # could use it from here, or the other collection.
      repos_with_issues = {}
      compute_repo_paths(repo_set_spec).each { |repo_path|
        if block_given?
          yield(repo_path)
        end
        repo_issues = []
        cmd = %(cd #{ repo_path } && git pull && git status)
        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          exit_status = wait_thr.value
          r = stdout.read
          if !r.index('On branch master')
            repo_issues << "Is not on master branch."
          end
          if !r.index(%(Your branch is up-to-date with 'origin/master'))
            repo_issues << "Is not up-to-date with origin"
          end
          if !(
            r.index(%(nothing to commit, working directory clean)) ||
            r.index(%(nothing added to commit but untracked files present))
          )
            repo_issues << "Has uncommitted changes"
          end
          if !exit_status.success?
            repo_issues << "Error: could not check repo (#{ stderr.read })".color(:red)
          end
        end
        if repo_issues.any?
          repos_with_issues[repo_path] = repo_issues
        end
      }
      repos_with_issues
    end

    # Fetches all branches (including new ones on remote) in all repos and pulls
    # all local tracking branches.
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    def git_fetch_and_pull(repo_set_spec)
      compute_repo_paths(repo_set_spec).each { |repo_path|
        cmd = %(cd #{ repo_path } && git remote update && git pull --all)
        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          exit_status = wait_thr.value
          if exit_status.success?
            puts " - Fetched and pulled #{ repo_path }"
          else
            msg = %(Could not fetch and pull #{ repo_path }:\n\n).color(:red)
            puts(msg + stderr.read)
          end
        end
      }
    end

    # Pulls all repos
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    def git_pull(repo_set_spec)
      compute_repo_paths(repo_set_spec).each { |repo_path|
        cmd = %(cd #{ repo_path } && git pull)
        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          exit_status = wait_thr.value
          if exit_status.success?
            puts " - Pulled #{ repo_path }"
          else
            msg = %(Could not pull #{ repo_path }:\n\n).color(:red)
            puts(msg + stderr.read)
          end
        end
      }
    end

    # Pushes all repos to remote_spec
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    # @param remote_spec [String, optional] defaults to 'origin'
    def git_push(repo_set_spec, remote_spec = 'origin')
      compute_repo_paths(repo_set_spec).each { |repo_path|
        cmd = %(cd #{ repo_path } && git push #{ remote_spec })
        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          exit_status = wait_thr.value
          if exit_status.success?
            puts " - Pushed #{ repo_path }"
          else
            msg = %(Could not push #{ repo_path }:\n\n).color(:red)
            puts(msg + stderr.read)
          end
        end
      }
    end

    # Resets all repos
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    def git_reset(repo_set_spec)
      compute_repo_paths(repo_set_spec).each { |repo_path|
        puts '-' * 80
        puts "Git reset #{ repo_path }"
        FileUtils.cd(repo_path)
        puts `git reset --hard`
      }
      true
    end

    # Prints git_status for all repos
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    def git_status(repo_set_spec)
      compute_repo_paths(repo_set_spec).each { |repo_path|
        puts '-' * 80
        puts "Git status for #{ repo_path }"
        FileUtils.cd(repo_path)
        puts `git status`
      }
      true
    end

    # Initializes any empty content repositories.
    # @param primary_language_repo_path [String]
    def initialize_empty_content_repos(primary_language_repo_path)
      compute_repo_paths(:all_content_repos).each { |repo_path|
        repo_name = repo_path.split('/').last
        if File.exist?(File.join(repo_path, 'data.json'))
          puts " -   Skipping #{ repo_name } (`data.json` file already exists)"
          next
        end
        puts " - Initializing #{ repo_name }"
        # Create directories
        puts "   - Creating directories"
        create_default_content_directory_structure(repo_path)
        # Copy standard files
        puts "   - Copying standard files"
        copy_default_content_repo_files(repo_path, primary_language_repo_path)
        # TODO: Figure out how to run bundle install from Ruby so it works.
        # Bundle install
        # puts "   - Installing RubyGems"
        # cmd = %(cd #{ repo_path } && bundle install)
        # Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        #   exit_status = wait_thr.value
        #   if exit_status.success?
        #     puts "     - Gems installed"
        #   else
        #     msg = %(Could not install Gems:\n\n)
        #     puts(msg + stderr.read)
        #   end
        # end
      }
    end

    def primary_repo_name
      'english'
    end

    # Replaces text in all repositories
    def replace_text(filename, &block)
    end

    # Run `report character_inventory` in all repositories
    def report_character_inventory(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } report character_inventory -g")
    end

    # Run `report content_sources` in all repositories
    def report_content_sources(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } report content_sources")
    end

    # Run `report count_files_with_gap_marks_and_subtitle_marks` in all repositories
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    def report_count_files_with_gap_marks_and_subtitle_marks(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } report count_files_with_gap_marks_and_subtitle_marks")
    end

    def report_files_that_dont_have_st_sync_active(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } report files_that_dont_have_st_sync_active -g")
    end

    def report_files_with_subtitles_that_require_review(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } report files_with_subtitles_that_require_review -g")
    end

    # Run `report quotes_details` in all repositories
    def report_quotes_details(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } report quotes_details")
    end

    # Allows running of any command (e.g., export, fix, report, validate) on
    # a repository set.
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    # @param command_string [String] the command to run on the command line,
    #     e.g., "repositext general fix update_rtfiles_to_settings_hierarchy -g"
    def run_repositext_command(repo_set_spec, command_string)
      puts " - Running command `#{ command_string }`".color(:blue)
      compute_repo_paths(repo_set_spec).each { |repo_path|
        puts "   - in #{ repo_path }".color(:blue)
        cmd = %(cd #{ repo_path } && #{ command_string })
        Open3.popen2e(cmd) do |stdin, stdout_err, wait_thr|
          while line = stdout_err.gets
            puts line
          end

          exit_status = wait_thr.value
          if exit_status.success?
            puts "   - completed"
          else
            puts "Could not run command in #{ repo_path }!".color(:red)
          end
        end
      }
    end

    # Updates all gems in language repos.
    def update_all_rubygems
      puts
      puts "This command assists in updating Rubygems in all content repos."
      puts
      puts "Please follow the onscreen instructions (=>) and hit enter after each completed step."
      puts "No problem if you make a mistake, just re-run the command."
      # Pull code repos (to get Gemfile updates)
      puts
      puts "Pulling updates for code repos"
      compute_repo_paths(:code_repos).each { |repo_path|
        repo_name = repo_path.split('/').last
        puts " - #{ repo_name }"
        cmd = %(cd #{ repo_path } && git pull)
        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          exit_status = wait_thr.value
          if !exit_status.success?
            msg = %(Could not pull #{ repo_name }:\n\n).color(:red)
            puts(msg + stderr.read)
          end
        end
      }
      puts
      # Bundle install code + content repos
      puts "=> run `bundle install` in primary content repo to update 'Gemfile.lock', then press <Enter>."
      $stdout.flush
      $stdin.gets
      puts "Copying 'Gemfile.lock' to all foreign repos"
      primary_gemfile_lock_path = File.join(
        compute_repo_paths(:primary_repo).first,
        'Gemfile.lock'
      )
      compute_repo_paths(:foreign_content_repos).each { |foreign_repo_path|
        foreign_repo_name = foreign_repo_path.split('/').last
        puts " - #{ foreign_repo_name }"
        FileUtils.cp(primary_gemfile_lock_path, foreign_repo_path)
      }
      puts
      puts "=> commit changes to 'Gemfile.lock' in all repos and push them to origin, then press <Enter>."
      $stdout.flush
      $stdin.gets
      # Wrap up message
      puts
      puts "Command completed."
    end

    def validate_content(repo_set_spec, content_type)
      run_repositext_command(repo_set_spec, "rt #{ content_type.name } validate content")
    end

  protected

    # Returns collection of paths to all repos in repo_set_spec
    # @param repo_set_spec [Symbol, Array<String>] A symbol describing a predefined
    #     group of repos, or an Array with specific repo names as strings.
    def compute_repo_paths(repo_set_spec)
      repo_names = case repo_set_spec
      when Array
        repo_set_spec
      when :all_content_repos
        all_content_repo_names
      when :all_repos
        all_repo_names
      when :code_repos
        code_repo_names
      when :core_code_repos
        core_code_repo_names
      when :foreign_content_repos
        foreign_content_repo_names
      when :primary_repo
        [primary_repo_name]
      when :test_content_repos
        all_content_repo_names.first(2)
      else
        raise ArgumentError.new("Invalid repo_set_spec: #{ repo_set_spec.inspect }")
      end
      repo_names.map { |repo_name|
        File.join(repo_set_parent_path, repo_name)
      }
    end

    # @param repo_root_path [String] absolute path to root of repo
    def create_default_content_directory_structure(repo_root_path)
      # root level directories
      (
        %w[data] +
        ContentType.all_names.map{ |e| "ct-#{ e }" }
      ).each do |rel_path|
        FileUtils.mkdir_p(File.join(repo_root_path, rel_path))
      end
      # per content_type directories
      ContentType.all_names.each do |content_type_name|
        %w[
          content
          lucene_table_export
          lucene_table_export/json_export
          lucene_table_export/L232
          lucene_table_export/L232/full
          lucene_table_export/L232/full/lucene_index
          lucene_table_export/L232/short
          lucene_table_export/L232/short/lucene_index
          lucene_table_export/L472
          lucene_table_export/L472/full
          lucene_table_export/L472/full/lucene_index
          lucene_table_export/L472/short
          lucene_table_export/L472/short/lucene_index
          pdf_export
          reports
          staging
        ].each do |rel_path|
          FileUtils.mkdir(
            File.join(repo_root_path, "ct-#{ content_type_name }", rel_path)
          )
        end
      end
    end

    # @param repo_root_path [String] absolute path to root of new repo
    # @param primary_language_repo_path [String] absolute path
    def copy_default_content_repo_files(repo_root_path, primary_language_repo_path)
      # Copy files that are the same between primary and foreign repos
      [
        '.gitignore',
        '.ruby-gemset',
        '.ruby-version',
        'Gemfile',
        'Gemfile.lock',
        'readme.md',
      ].each do |filename|
        FileUtils.cp(
          File.join(primary_language_repo_path, filename),
          repo_root_path
        )
      end

      # Copy repository level data.json file from code template
      repo_dir_name = repo_root_path.split('/').last
      language = Language.find_by_repo_dir_name(repo_dir_name)
      @langcode_2 = language.code_2_chars
      @langcode_3 = language.code_3_chars
      erb_template = ERB.new(File.read(repository_level_data_json_file_template_path))
      dj_output_path = File.join(repo_root_path, 'data.json')
      File.write(dj_output_path, erb_template.result(binding))

      # Copy content_type level Rtfiles from code template
      ContentType.all_names.each do |content_type_name|
        @content_type_name = content_type_name
        erb_template = ERB.new(File.read(rtfile_template_path))
        rtfile_output_path = File.join(repo_root_path, "ct-#{ content_type_name }", 'Rtfile')
        File.write(rtfile_output_path, erb_template.result(binding))
      end
    end

    # Returns the absolute path to the repository level data.json template to
    # use for new language repos.
    def repository_level_data_json_file_template_path
      File.join(repo_set_parent_path, "repositext/templates/repository-level-data.json.erb")
    end

    # Returns the absolute path to the content_type level Rtfile templates to
    # use for new language repos.
    def rtfile_template_path
      File.join(repo_set_parent_path, "repositext/templates/Rtfile.erb")
    end

  end
end
