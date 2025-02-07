# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Deleting a container registry protection rule', :aggregate_failures, feature_category: :container_registry do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :repository) }
  let_it_be_with_refind(:container_protection_rule) do
    create(:container_registry_protection_rule, project: project)
  end

  let_it_be(:current_user) { create(:user, maintainer_projects: [project]) }

  let(:mutation) { graphql_mutation(:delete_container_registry_protection_rule, input) }
  let(:mutation_response) { graphql_mutation_response(:delete_container_registry_protection_rule) }
  let(:input) { { id: container_protection_rule.to_global_id } }

  subject(:post_graphql_mutation_delete_container_registry_protection_rule) do
    post_graphql_mutation(mutation, current_user: current_user)
  end

  shared_examples 'an erroneous reponse' do
    it { post_graphql_mutation_delete_container_registry_protection_rule.tap { expect(mutation_response).to be_blank } }

    it do
      expect { post_graphql_mutation_delete_container_registry_protection_rule }
        .not_to change { ::ContainerRegistry::Protection::Rule.count }
    end
  end

  it_behaves_like 'a working GraphQL mutation'

  it 'responds with deleted container registry protection rule' do
    expect { post_graphql_mutation_delete_container_registry_protection_rule }
      .to change { ::ContainerRegistry::Protection::Rule.count }.from(1).to(0)

    expect_graphql_errors_to_be_empty

    expect(mutation_response).to include(
      'errors' => be_blank,
      'containerRegistryProtectionRule' => {
        'id' => container_protection_rule.to_global_id.to_s,
        'containerPathPattern' => container_protection_rule.container_path_pattern,
        'deleteProtectedUpToAccessLevel' => container_protection_rule.delete_protected_up_to_access_level.upcase,
        'pushProtectedUpToAccessLevel' => container_protection_rule.push_protected_up_to_access_level.upcase
      }
    )
  end

  context 'with existing container registry protection rule belonging to other project' do
    let_it_be(:container_protection_rule) do
      create(:container_registry_protection_rule, container_path_pattern: 'protection_rule_other_project')
    end

    it_behaves_like 'an erroneous reponse'

    it { is_expected.tap { expect_graphql_errors_to_include(/you don't have permission to perform this action/) } }
  end

  context 'with deleted container registry protection rule' do
    let!(:container_protection_rule) do
      create(:container_registry_protection_rule, project: project,
        container_path_pattern: 'protection_rule_deleted').destroy!
    end

    it_behaves_like 'an erroneous reponse'

    it { is_expected.tap { expect_graphql_errors_to_include(/you don't have permission to perform this action/) } }
  end

  context 'when current_user does not have permission' do
    let_it_be(:developer) { create(:user).tap { |u| project.add_developer(u) } }
    let_it_be(:reporter) { create(:user).tap { |u| project.add_reporter(u) } }
    let_it_be(:guest) { create(:user).tap { |u| project.add_guest(u) } }
    let_it_be(:anonymous) { create(:user) }

    where(:current_user) do
      [ref(:developer), ref(:reporter), ref(:guest), ref(:anonymous)]
    end

    with_them do
      it_behaves_like 'an erroneous reponse'

      it { is_expected.tap { expect_graphql_errors_to_include(/you don't have permission to perform this action/) } }
    end
  end

  context "when feature flag ':container_registry_protected_containers' disabled" do
    before do
      stub_feature_flags(container_registry_protected_containers: false)
    end

    it_behaves_like 'an erroneous reponse'

    it do
      post_graphql_mutation_delete_container_registry_protection_rule

      expect_graphql_errors_to_include(/'container_registry_protected_containers' feature flag is disabled/)
    end
  end
end
