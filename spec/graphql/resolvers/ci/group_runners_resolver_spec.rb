# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ci::GroupRunnersResolver do
  include GraphqlHelpers

  describe '#resolve' do
    subject { resolve(described_class, obj: obj, ctx: { current_user: user }, args: args) }

    include_context 'runners resolver setup'

    let(:obj) { group }
    let(:args) { {} }

    # First, we can do a couple of basic real tests to verify common cases. That ensures that the code works.
    context 'when user cannot see runners' do
      it 'returns no runners' do
        expect(subject.items.to_a).to eq([])
      end
    end

    context 'with user as group owner' do
      before do
        group.add_owner(user)
      end

      it 'returns all the runners' do
        expect(subject.items.to_a).to contain_exactly(inactive_project_runner, offline_project_runner, group_runner, subgroup_runner)
      end

      context 'with membership direct' do
        let(:args) { { membership: :direct } }

        it 'returns only direct runners' do
          expect(subject.items.to_a).to contain_exactly(group_runner)
        end
      end
    end

    # Then, we can check specific edge cases for this resolver
    context 'with obj set to nil' do
      let(:obj) { nil }

      it 'raises an error' do
        expect { subject }.to raise_error('Expected group missing')
      end
    end

    context 'with obj not set to group' do
      let(:obj) { build(:project) }

      it 'raises an error' do
        expect { subject }.to raise_error('Expected group missing')
      end
    end

    # Here we have a mocked part. We assume that all possible edge cases are covered in RunnersFinder spec. So we don't need to test them twice.
    # Only thing we can do is to verify that args from the resolver is correctly transformed to params of the Finder and we return the Finder's result back.
    describe 'Allowed query arguments' do
      let(:finder) { instance_double(::Ci::RunnersFinder) }
      let(:args) do
        {
          status: 'active',
          type: :group_type,
          tag_list: ['active_runner'],
          search: 'abc',
          sort: :contacted_asc,
          membership: :descendants
        }
      end

      let(:expected_params) do
        {
          status_status: 'active',
          type_type: :group_type,
          tag_name: ['active_runner'],
          preload: { tag_name: nil },
          search: 'abc',
          sort: 'contacted_asc',
          membership: :descendants,
          group: group
        }
      end

      it 'calls RunnersFinder with expected arguments' do
        allow(::Ci::RunnersFinder).to receive(:new).with(current_user: user, params: expected_params).once.and_return(finder)
        allow(finder).to receive(:execute).once.and_return([:execute_return_value])

        expect(subject.items.to_a).to eq([:execute_return_value])
      end
    end
  end
end
