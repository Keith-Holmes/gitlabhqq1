# frozen_string_literal: true

require 'spec_helper'

describe Gitlab::Analytics::UniqueVisits, :clean_gitlab_redis_shared_state do
  let(:unique_visits) { Gitlab::Analytics::UniqueVisits.new }
  let(:target1_id) { 'g_analytics_contribution' }
  let(:target2_id) { 'g_analytics_insights' }
  let(:target3_id) { 'g_analytics_issues' }
  let(:visitor1_id) { 'dfb9d2d2-f56c-4c77-8aeb-6cddc4a1f857' }
  let(:visitor2_id) { '1dd9afb2-a3ee-4de1-8ae3-a405579c8584' }

  describe '#track_visit' do
    it 'tracks the unique weekly visits for targets' do
      unique_visits.track_visit(visitor1_id, target1_id, 7.days.ago)
      unique_visits.track_visit(visitor1_id, target1_id, 7.days.ago)
      unique_visits.track_visit(visitor2_id, target1_id, 7.days.ago)

      unique_visits.track_visit(visitor2_id, target2_id, 7.days.ago)
      unique_visits.track_visit(visitor1_id, target2_id, 8.days.ago)
      unique_visits.track_visit(visitor1_id, target2_id, 15.days.ago)

      expect(unique_visits.weekly_unique_visits_for_target(target1_id)).to eq(2)
      expect(unique_visits.weekly_unique_visits_for_target(target2_id)).to eq(1)

      expect(unique_visits.weekly_unique_visits_for_target(target2_id, week_of: 15.days.ago)).to eq(1)

      expect(unique_visits.weekly_unique_visits_for_target(target3_id)).to eq(0)

      expect(unique_visits.weekly_unique_visits_for_any_target).to eq(2)
      expect(unique_visits.weekly_unique_visits_for_any_target(week_of: 15.days.ago)).to eq(1)
      expect(unique_visits.weekly_unique_visits_for_any_target(week_of: 30.days.ago)).to eq(0)
    end

    it 'sets the keys in Redis to expire automatically after 28 days' do
      unique_visits.track_visit(visitor1_id, target1_id)

      Gitlab::Redis::SharedState.with do |redis|
        redis.scan_each(match: "#{target1_id}-*").each do |key|
          expect(redis.ttl(key)).to be_within(5.seconds).of(28.days)
        end
      end
    end

    it 'raises an error if an invalid target id is given' do
      invalid_target_id = "x_invalid"

      expect do
        unique_visits.track_visit(visitor1_id, invalid_target_id)
      end.to raise_error("Invalid target id #{invalid_target_id}")
    end
  end
end
