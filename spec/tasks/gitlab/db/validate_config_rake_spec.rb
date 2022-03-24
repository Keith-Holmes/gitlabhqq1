# frozen_string_literal: true

require 'rake_helper'

RSpec.describe 'gitlab:db:validate_config', :silence_stdout do
  before :all do
    Rake.application.rake_require 'active_record/railties/databases'
    Rake.application.rake_require 'tasks/seed_fu'
    Rake.application.rake_require 'tasks/gitlab/db/validate_config'

    # empty task as env is already loaded
    Rake::Task.define_task :environment
  end

  context "when validating config" do
    let(:main_database_config) do
      Rails.application.config.load_database_yaml
        .dig('test', 'main')
        .slice('adapter', 'encoding', 'database', 'username', 'password', 'host')
        .symbolize_keys
    end

    let(:additional_database_config) do
      # Use built-in postgres database
      main_database_config.merge(database: 'postgres')
    end

    around do |example|
      with_reestablished_active_record_base(reconnect: true) do
        with_db_configs(test: test_config) do
          example.run
        end
      end
    end

    shared_examples 'validates successfully' do
      it 'by default' do
        expect { run_rake_task('gitlab:db:validate_config') }.not_to output(/Database config validation failure/).to_stderr
        expect { run_rake_task('gitlab:db:validate_config') }.not_to raise_error
      end

      it 'for production' do
        allow(Gitlab).to receive(:dev_or_test_env?).and_return(false)

        expect { run_rake_task('gitlab:db:validate_config') }.not_to output(/Database config validation failure/).to_stderr
        expect { run_rake_task('gitlab:db:validate_config') }.not_to raise_error
      end

      it 'if GITLAB_VALIDATE_DATABASE_CONFIG is set' do
        stub_env('GITLAB_VALIDATE_DATABASE_CONFIG', '1')
        allow(Gitlab).to receive(:dev_or_test_env?).and_return(false)

        expect { run_rake_task('gitlab:db:validate_config') }.not_to output(/Database config validation failure/).to_stderr
        expect { run_rake_task('gitlab:db:validate_config') }.not_to raise_error
      end
    end

    shared_examples 'raises an error' do |match|
      it 'by default' do
        expect { run_rake_task('gitlab:db:validate_config') }.to raise_error(match)
      end

      it 'to stderr instead of exception for production' do
        allow(Gitlab).to receive(:dev_or_test_env?).and_return(false)

        expect { run_rake_task('gitlab:db:validate_config') }.to output(match).to_stderr
      end

      it 'if GITLAB_VALIDATE_DATABASE_CONFIG is set' do
        stub_env('GITLAB_VALIDATE_DATABASE_CONFIG', '1')
        allow(Gitlab).to receive(:dev_or_test_env?).and_return(false)

        expect { run_rake_task('gitlab:db:validate_config') }.to raise_error(match)
      end
    end

    context 'when only main: is specified' do
      let(:test_config) do
        {
          main: main_database_config
        }
      end

      it_behaves_like 'validates successfully'
    end

    context 'when main: uses database_tasks=false' do
      let(:test_config) do
        {
          main: main_database_config.merge(database_tasks: false)
        }
      end

      it_behaves_like 'raises an error', /The 'main' is required to use 'database_tasks: true'/
    end

    context 'when many configurations share the same database' do
      context 'when no database_tasks is specified, assumes true' do
        let(:test_config) do
          {
            main: main_database_config,
            ci: main_database_config
          }
        end

        it_behaves_like 'raises an error', /Many configurations \(main, ci\) share the same database/
      end

      context 'when database_tasks is specified' do
        let(:test_config) do
          {
            main: main_database_config.merge(database_tasks: true),
            ci: main_database_config.merge(database_tasks: true)
          }
        end

        it_behaves_like 'raises an error', /Many configurations \(main, ci\) share the same database/
      end

      context "when there's no main: but something different, as currently we only can share with main:" do
        let(:test_config) do
          {
            archive: main_database_config,
            ci: main_database_config.merge(database_tasks: false)
          }
        end

        it_behaves_like 'raises an error', /The 'ci' is expecting to share configuration with 'main', but no such is to be found/
      end
    end

    context 'when ci: uses different database' do
      context 'and does not specify database_tasks which indicates using dedicated database' do
        let(:test_config) do
          {
            main: main_database_config,
            ci: additional_database_config
          }
        end

        it_behaves_like 'validates successfully'
      end

      context 'and does specify database_tasks=false which indicates sharing with main:' do
        let(:test_config) do
          {
            main: main_database_config,
            ci: additional_database_config.merge(database_tasks: false)
          }
        end

        it_behaves_like 'raises an error', /The 'ci' since it is using 'database_tasks: false' should share database with 'main:'/
      end
    end
  end

  %w[db:migrate db:schema:load db:schema:dump].each do |task|
    context "when running #{task}" do
      it "does run gitlab:db:validate_config before" do
        expect(Rake::Task['gitlab:db:validate_config']).to receive(:execute).and_return(true)
        expect(Rake::Task[task]).to receive(:execute).and_return(true)

        Rake::Task['gitlab:db:validate_config'].reenable
        run_rake_task(task)
      end
    end
  end

  def with_db_configs(test: test_config)
    current_configurations = ActiveRecord::Base.configurations # rubocop:disable Database/MultipleDatabases
    ActiveRecord::Base.configurations = { test: test_config }
    yield
  ensure
    ActiveRecord::Base.configurations = current_configurations
  end
end
