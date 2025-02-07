# frozen_string_literal: true

module Gitlab
  module Ci
    module Pipeline
      module Chain
        class PopulateMetadata < Chain::Base
          include Chain::Helpers

          def perform!
            set_pipeline_name
            set_auto_cancel

            return if pipeline.pipeline_metadata.nil? || pipeline.pipeline_metadata.valid?

            message = pipeline.pipeline_metadata.errors.full_messages.join(', ')
            error("Failed to build pipeline metadata! #{message}")
          end

          def break?
            pipeline.pipeline_metadata&.errors&.any?
          end

          private

          def set_pipeline_name
            return if @command.yaml_processor_result.workflow_name.blank?

            name = @command.yaml_processor_result.workflow_name
            name = ExpandVariables.expand(name, -> { global_context.variables.sort_and_expand_all })

            return if name.blank?

            assign_to_metadata(name: name.strip)
          end

          def set_auto_cancel
            auto_cancel = @command.yaml_processor_result.workflow_auto_cancel
            auto_cancel_on_new_commit = auto_cancel&.dig(:on_new_commit)

            return if auto_cancel_on_new_commit.blank?

            assign_to_metadata(auto_cancel_on_new_commit: auto_cancel_on_new_commit)
          end

          def global_context
            Gitlab::Ci::Build::Context::Global.new(
              pipeline, yaml_variables: @command.pipeline_seed.root_variables)
          end

          def assign_to_metadata(attributes)
            metadata = pipeline.pipeline_metadata || pipeline.build_pipeline_metadata(project: pipeline.project)
            metadata.assign_attributes(attributes)
          end
        end
      end
    end
  end
end
