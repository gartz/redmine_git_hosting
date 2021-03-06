require 'digest/md5'
require_dependency 'redmine/scm/adapters/git_adapter'

module GitHosting
	module Hooks
		module GitAdapterHooks

			def self.check_hooks_installed
				create_hooks_digests

				post_receive_hook_path = File.join(gitolite_hooks_dir, 'post-receive')
				post_receive_exists = %x[#{GitHosting.git_user_runner} test -r '#{post_receive_hook_path}' && echo 'yes' || echo 'no']
				if post_receive_exists.match(/no/)
					logger.info "\"post-receive\" not handled by gitolite, installing it..."
					if python_available == true
						logger.info "python is available, installing faster version of hook"
						install_hook("post-receive.redmine_gitolite.py")
					else
						install_hook("post-receive.redmine_gitolite")
					end
					logger.info "\"post-receive.redmine_gitolite\ installed"
					logger.info "Running \"gl-setup\" on the gitolite install..."
					%x[#{GitHosting.git_user_runner} gl-setup]
					logger.info "Finished installing hooks in the gitolite install..."
					return true
				else
					git_user = Setting.plugin_redmine_git_hosting['gitUser']
					web_user = GitHosting.web_user
					if git_user == web_user
						digest = Digest::MD5.file(File.expand_path(post_receive_hook_path))
					else
						contents = %x[#{GitHosting.git_user_runner} 'cat #{post_receive_hook_path}']
						digest = Digest::MD5.hexdigest(contents)
					end

					logger.debug "Installed hook digest: #{digest}"
					if @@hook_digests.include? digest
						logger.info "Our hook is already installed"
						return true
					else
						error_msg = "\"post-receive\" is alreay present but it's not ours!"
						logger.warn error_msg
						return error_msg
					end
				end
			end

			def self.install_hook(hook_name)
				hook_source_path = File.join(package_hooks_dir, hook_name)
				hook_dest_path = File.join(gitolite_hooks_dir, hook_name.split('.')[0])
				logger.info "Installing \"#{hook_name}\" from #{hook_source_path} to #{hook_dest_path}"
				git_user = Setting.plugin_redmine_git_hosting['gitUser']
				web_user = GitHosting.web_user
				if git_user == web_user
					%x[#{GitHosting.git_user_runner} 'cp #{hook_source_path} #{hook_dest_path}']
					%x[#{GitHosting.git_user_runner} 'chown #{git_user}:#{git_user} #{hook_dest_path}']
					%x[#{GitHosting.git_user_runner} 'chmod 700 #{hook_dest_path}']
				else
					%x[#{GitHosting.git_user_runner} 'sudo -nu #{web_user} cat #{hook_source_path} | cat - >  #{hook_dest_path}']
					%x[#{GitHosting.git_user_runner} 'chown #{git_user}:#{git_user} #{hook_dest_path}']
					%x[#{GitHosting.git_user_runner} 'chmod 700 #{hook_dest_path}']
				end
			end

			def self.setup_hooks_for_project(project)
				logger.info "Setting up hooks for project #{project.identifier}"
				debug_hook = Setting.plugin_redmine_git_hosting['gitDebugPostUpdateHook']
				curl_ignore_security = Setting.plugin_redmine_git_hosting['gitPostUpdateHookCurlIgnore']
				repo_path = File.join(Setting.plugin_redmine_git_hosting['gitRepositoryBasePath'], GitHosting.repository_name(project))
				%x[#{GitHosting.git_exec} --git-dir='#{repo_path}.git' config hooks.redmine_gitolite.key #{Setting['sys_api_key']}]
				%x[#{GitHosting.git_exec} --git-dir='#{repo_path}.git' config hooks.redmine_gitolite.server #{Setting['host_name']}]
				%x[#{GitHosting.git_exec} --git-dir='#{repo_path}.git' config hooks.redmine_gitolite.projectid #{project.identifier}]
				%x[#{GitHosting.git_exec} --git-dir='#{repo_path}.git' config --bool hooks.redmine_gitolite.debug #{debug_hook}]
				%x[#{GitHosting.git_exec} --git-dir='#{repo_path}.git' config --bool hooks.redmine_gitolite.curlignoresecurity #{curl_ignore_security}]
			end

			def self.setup_hooks(projects=nil)
				# TODO: Need to find out how to call this when this plugin's settings are saved
				check_hooks_installed()
				if projects.nil?
					projects = Project.visible.find(:all).select{|p| p.repository.is_a?(Repository::Git)}
				end
				projects.each do |project|
					setup_hooks_for_project(project)
				end
			end

			private

			def self.logger
				return GitHosting::logger
			end

			@@package_hooks_dir = nil

			def self.gitolite_hooks_dir
				return '~/.gitolite/hooks/common'
			end

			def self.package_hooks_dir
				if @@package_hooks_dir.nil?
					@@package_hooks_dir = File.join(File.dirname(File.dirname(File.dirname(File.dirname(__FILE__)))), 'contrib', 'hooks')
				end
				return @@package_hooks_dir
			end

			@python_available = nil
			def self.python_available
				if @python_available.nil?
					python_test = %x[#{GitHosting.git_user_runner} "which python 2>/dev/null && echo 'yes_we_have_python' || echo 'no'"].chomp.strip
					logger.info "Python test result #{python_test}"
					@python_available = python_test.match(/yes_we_have_python/)? true : false
				end
				@python_available
			end

			@@hook_digests = []
			def self.create_hooks_digests
				if @@hook_digests.empty?
					logger.info "Creating MD5 digests for our hooks"
					["post-receive.redmine_gitolite", "post-receive.redmine_gitolite.py"].each do |hook_name|
						digest = Digest::MD5.file(File.join(package_hooks_dir, hook_name))
						logger.info "Digest for #{hook_name}: #{digest}"
						@@hook_digests.push(digest)
					end
				end
			end

		end
	end
end
