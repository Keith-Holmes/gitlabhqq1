module Gitlab
  class ProjectTemplate
    attr_reader :title, :name

    def initialize(name, title)
      @name, @title = name, title
    end

    def logo_path
      "project_templates/#{name}.png"
    end

    def file
      archive_path.open
    end

    def archive_path
      Rails.root.join("vendor/project_templates/#{name}.tar.gz")
    end

    def clone_url
      "https://gitlab.com/gitlab-org/project-templates/#{name}.git"
    end

    def ==(other)
      name == other.name && title == other.title
    end

    TemplatesTable = [
      ProjectTemplate.new('rails', 'Ruby on Rails')
    ].freeze

    class << self
      def all
        TemplatesTable
      end

      def find(name)
        all.find { |template| template.name == name.to_s }
      end

      def archive_directory
        Rails.root.join("vendor_directory/project_templates")
      end
    end
  end
end
