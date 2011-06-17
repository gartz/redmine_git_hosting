require_dependency 'projects_controller'
module GitHosting
	module Patches
		module ProjectsControllerPatch
			
			def git_repo_init
				
				users = @project.member_principals.map(&:user).compact.uniq
				if users.length == 0
					membership = Member.new(
						:principal=>User.current,
						:project_id=>@project.id,
						:role_ids=>[3]
						)
					membership.save
				end
				if Setting.plugin_redmine_git_hosting['allProjectsUseGit'] == "true"
					repo = Repository::Git.new
					repo_name= @project.parent ? File.join(@project.parent.identifier,@project.identifier) : @project.identifier
					repo.url = repo.root_url = File.join(Setting.plugin_redmine_git_hosting['gitRepositoryBasePath'], "#{repo_name}.git")
					@project.repository = repo
				end

			end
			

			def self.included(base)
				base.class_eval do
					unloadable
				end
				base.send(:after_filter, :git_repo_init, :only=>:create)
			end
		end
	end
end
ProjectsController.send(:include, GitHosting::Patches::ProjectsControllerPatch) unless ProjectsController.include?(GitHosting::Patches::ProjectsControllerPatch)