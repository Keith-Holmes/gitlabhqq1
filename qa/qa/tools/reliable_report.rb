# frozen_string_literal: true

require "influxdb-client"
require "terminal-table"
require "slack-notifier"
require "colorize"

module QA
  module Tools
    class ReliableReport
      include Support::InfluxdbTools
      include Support::API

      RELIABLE_REPORT_LABEL = "reliable test report"

      ALLOWED_EXCEPTION_PATTERNS = [
        /Couldn't find option named/,
        /Waiting for [\w:]+ to be removed/,
        /503 Server Unavailable/,
        /\w+ did not appear on [\w:]+ as expected/,
        /Internal Server Error/,
        /Ambiguous match/,
        /500 Error - GitLab/,
        /Page did not fully load/,
        /Timed out reading data from server/,
        /Internal API error/,
        /Something went wrong/
      ].freeze

      # Project for report creation: https://gitlab.com/gitlab-org/gitlab
      PROJECT_ID = 278964
      FEATURES_DIR = 'https://gitlab.com/gitlab-org/gitlab/-/blob/master/qa/qa/specs/features/'

      def initialize(range)
        @range = range.to_i
        @slack_channel = "#quality-reports"
      end

      # Run reliable reporter
      #
      # @param [Integer] range amount of days for results range
      # @param [String] report_in_issue_and_slack
      # @return [void]
      def self.run(range: 14, report_in_issue_and_slack: "false")
        reporter = new(range)

        reporter.print_report

        if report_in_issue_and_slack == "true"
          reporter.report_in_issue_and_slack
          reporter.close_previous_reports
        end
      rescue StandardError => e
        reporter&.notify_failure(e)
        raise(e)
      end

      # Print top stable specs
      #
      # @return [void]
      def print_report
        puts "#{summary_table(stable: true)}\n\n"
        puts "Total amount: #{stable_test_runs.sum { |_k, v| v.count }}\n\n"
        print_results(stable_results_tables)
        return puts("No unstable reliable tests present!".colorize(:yellow)) if unstable_reliable_test_runs.empty?

        puts "#{summary_table(stable: false)}\n\n"
        puts "Total amount: #{unstable_reliable_test_runs.sum { |_k, v| v.count }}\n\n"
        print_results(unstable_reliable_results_tables)
      end

      # Create report issue
      #
      # @return [void]
      def report_in_issue_and_slack
        puts "Creating report".colorize(:green)
        issue = api_update(
          :post,
          "projects/#{PROJECT_ID}/issues",
          title: "Reliable e2e test report",
          description: report_issue_body,
          labels: "#{RELIABLE_REPORT_LABEL},Quality,test,type::maintenance,automation:ml"
        )
        @report_iid = issue[:iid]
        web_url = issue[:web_url]
        puts "Created report issue: #{web_url}"

        puts "Sending slack notification".colorize(:green)
        notifier.post(
          icon_emoji: ":tanuki-protect:",
          text: <<~TEXT
            ```#{summary_table(stable: true)}```
            ```#{summary_table(stable: false)}```

            #{web_url}
          TEXT
        )
        puts "Done!"
      end

      # Close previous reliable test reports
      #
      # @return [void]
      def close_previous_reports
        puts "Closing previous reports".colorize(:green)
        issues = api_get("projects/#{PROJECT_ID}/issues?labels=#{RELIABLE_REPORT_LABEL}&state=opened")

        issues
          .reject { |issue| issue[:iid] == report_iid }
          .each do |issue|
          issue_iid = issue[:iid]
          issue_endpoint = "projects/#{PROJECT_ID}/issues/#{issue_iid}"

          puts "Closing previous report '#{issue[:web_url]}'"
          api_update(:put, issue_endpoint, state_event: "close")
          api_update(:post, "#{issue_endpoint}/notes", body: "Closed issue in favor of ##{report_iid}")
        end
      end

      # Notify failure
      #
      # @param [StandardError] error
      # @return [void]
      def notify_failure(error)
        notifier.post(
          text: "Reliable reporter failed to create report. Error: ```#{error}```",
          icon_emoji: ":sadpanda:"
        )
      end

      private

      attr_reader :range, :slack_channel, :report_iid

      # Slack notifier
      #
      # @return [Slack::Notifier]
      def notifier
        @notifier ||= Slack::Notifier.new(
          slack_webhook_url,
          channel: slack_channel,
          username: "Reliable Spec Report"
        )
      end

      # Gitlab access token
      #
      # @return [String]
      def gitlab_access_token
        @gitlab_access_token ||= ENV["GITLAB_ACCESS_TOKEN"] || raise("Missing GITLAB_ACCESS_TOKEN env variable")
      end

      # Gitlab api url
      #
      # @return [String]
      def gitlab_api_url
        @gitlab_api_url ||= ENV["CI_API_V4_URL"] || raise("Missing CI_API_V4_URL env variable")
      end

      # Slack webhook url
      #
      # @return [String]
      def slack_webhook_url
        @slack_webhook_url ||= ENV["SLACK_WEBHOOK"] || raise("Missing SLACK_WEBHOOK env variable")
      end

      # Markdown formatted report issue body
      #
      # @return [String]
      def report_issue_body
        execution_interval = "(#{Date.today - range} - #{Date.today})"

        issue = []
        issue << "[[_TOC_]]"
        issue << "# Candidates for promotion to reliable #{execution_interval}"
        issue << "Total amount: **#{test_count(stable_test_runs)}**"
        issue << summary_table(markdown: true, stable: true).to_s
        issue << results_markdown(:stable)
        return issue.join("\n\n") if unstable_reliable_test_runs.empty?

        issue << "# Reliable specs with failures #{execution_interval}"
        issue << "Total amount: **#{test_count(unstable_reliable_test_runs)}**"
        issue << summary_table(markdown: true, stable: false).to_s
        issue << results_markdown(:unstable)
        issue.join("\n\n")
      end

      # Spec summary table
      #
      # @param [Boolean] markdown
      # @param [Boolean] stable
      # @return [Terminal::Table]
      def summary_table(markdown: false, stable: true)
        test_runs = stable ? stable_test_runs : unstable_reliable_test_runs
        terminal_table(
          rows: test_runs.map do |stage, stage_specs|
            [stage, stage_specs.sum { |_k, group_specs| group_specs.length }]
          end,
          title: "#{stable ? 'Stable' : 'Unstable'} spec summary for past #{range} days".ljust(50),
          headings: %w[STAGE COUNT],
          markdown: markdown
        )
      end

      # Result tables for stable specs
      #
      # @param [Boolean] markdown
      # @return [Hash]
      def stable_results_tables(markdown: false)
        results_tables(:stable, markdown: markdown)
      end

      # Result table for unstable specs
      #
      # @param [Boolean] markdown
      # @return [Hash]
      def unstable_reliable_results_tables(markdown: false)
        results_tables(:unstable, markdown: markdown)
      end

      # Markdown formatted tables
      #
      # @param [Symbol] type result type - :stable, :unstable
      # @return [String]
      def results_markdown(type)
        runs = type == :stable ? stable_test_runs : unstable_reliable_test_runs
        results_tables(type, markdown: true).map do |stage, group_tables|
          markdown = "## #{stage.capitalize} (#{runs[stage].sum { |_k, group_runs| group_runs.count }})\n\n"

          markdown << group_tables.map { |product_group, table| group_results_markdown(product_group, table) }.join
        end.join("\n\n")
      end

      # Markdown formatted group results table
      #
      # @param [String] product_group
      # @param [Terminal::Table] table
      # @return [String]
      def group_results_markdown(product_group, table)
        <<~MARKDOWN.chomp
          <details>
          <summary>Executions table ~"group::#{product_group.tr('_', ' ')}" (#{table.rows.size})</summary>

          #{table}

          </details>
        MARKDOWN
      end

      # Results table
      #
      # @param [Symbol] type result type - :stable, :unstable
      # @param [Boolean] markdown
      # @return [Hash<String, Hash<String, Terminal::Table>>] grouped by stage and product_group
      def results_tables(type, markdown: false)
        (type == :stable ? stable_test_runs : unstable_reliable_test_runs).to_h do |stage, specs|
          headings = ['NAME', 'RUNS', 'FAILURES', 'FAILURE RATE'].freeze
          [stage, specs.transform_values do |group_specs|
            terminal_table(
              title: "Top #{type} specs in '#{stage}::#{specs.key(group_specs)}' group for past #{range} days",
              headings: headings,
              markdown: markdown,
              rows: group_specs.map do |name, result|
                [
                  name_column(name: name, file: result[:file], link: result[:link],
                    exceptions_and_job_urls: result[:exceptions_and_job_urls], markdown: markdown),
                  *table_params(result.values)
                ]
              end
            )
          end]
        end
      end

      # Stable specs
      #
      # @return [Hash]
      def stable_test_runs
        @top_stable ||= begin
          stable_specs = test_runs(reliable: false).each do |stage, stage_specs|
            stage_specs.transform_values! do |group_specs|
              group_specs.reject { |k, v| v[:failure_rate] != 0 }
                         .sort_by { |k, v| -v[:runs] }
                         .to_h
            end
          end
          stable_specs.transform_values { |v| v.reject { |_, v| v.empty? } }.reject { |_, v| v.empty? }
        end
      end

      # Unstable reliable specs
      #
      # @return [Hash]
      def unstable_reliable_test_runs
        @top_unstable_reliable ||= begin
          unstable = test_runs(reliable: true).each do |_stage, stage_specs|
            stage_specs.transform_values! do |group_specs|
              group_specs.reject { |_, v| v[:failure_rate] == 0 }
                         .sort_by { |_, v| -v[:failure_rate] }
                         .to_h
            end
          end
          unstable.transform_values { |v| v.reject { |_, v| v.empty? } }.reject { |_, v| v.empty? }
        end
      end

      def print_results(results)
        results.each do |_stage, stage_results|
          stage_results.each_value { |group_results_table| puts "#{group_results_table}\n\n" }
        end
      end

      def test_count(test_runs)
        test_runs.sum do |_stage, stage_results|
          stage_results.sum { |_product_group, group_results| group_results.count }
        end
      end

      # Terminal table for result formatting
      #
      # @param [Array] rows
      # @param [Array] headings
      # @param [String] title
      # @param [Boolean] markdown
      # @return [Terminal::Table]
      def terminal_table(rows:, headings:, title:, markdown:)
        Terminal::Table.new(
          headings: headings,
          title: markdown ? nil : title,
          rows: rows,
          style: markdown ? { border: :markdown } : { all_separators: true }
        )
      end

      # Spec parameters for table row
      #
      # @param [Array] parameters
      # @return [Array]
      def table_params(parameters)
        [*parameters[2..3], "#{parameters.last}%"]
      end

      # Name column content
      #
      # @param [String] name
      # @param [String] file
      # @param [String] link
      # @param [Hash] exceptions_and_job_urls
      # @param [Boolean] markdown
      # @return [String]
      def name_column(name:, file:, link:, exceptions_and_job_urls:, markdown: false)
        if markdown
          return "**Name**: #{name}<br>**File**: [#{file}](#{link})#{exceptions_markdown(exceptions_and_job_urls)}"
        end

        wrapped_name = name.length > 150 ? "#{name} ".scan(/.{1,150} /).map(&:strip).join("\n") : name
        "Name: '#{wrapped_name}'\nFile: #{file.ljust(160)}"
      end

      # Formatted exceptions with link to job url
      #
      # @param [Hash] exceptions_and_job_urls
      # @return [String]
      def exceptions_markdown(exceptions_and_job_urls)
        return '' if exceptions_and_job_urls.empty?

        "<br>**Exceptions**:#{exceptions_and_job_urls.keys.map do |e|
          "<br>- [`#{e.truncate(250).tr('`', "'")}`](#{exceptions_and_job_urls[e]})"
        end.join('')}"
      end

      # rubocop:disable Metrics/AbcSize
      # Test executions grouped by name
      #
      # @param [Boolean] reliable
      # @return [Hash<String, Hash>]
      def test_runs(reliable:)
        puts("Fetching data on #{reliable ? 'reliable ' : ''}test execution for past #{range} days\n".colorize(:green))

        all_runs = query_api.query(query: query(reliable))
        all_runs.each_with_object(Hash.new { |hsh, key| hsh[key] = {} }) do |table, result|
          records = table.records.sort_by { |record| record.values["_time"] }

          next if within_execution_range(records.first.values["_time"], records.last.values["_time"])

          last_record = records.last.values
          name = last_record["name"]
          file = last_record["file_path"].split("/").last
          link = FEATURES_DIR + last_record["file_path"]
          stage = last_record["stage"] || "unknown"
          product_group = last_record["product_group"] || "unknown"

          runs = records.count

          failed = records.count do |r|
            r.values["status"] == "failed" && !allowed_failure?(r.values["failure_exception"])
          end

          failure_rate = (failed.to_f / runs) * 100

          records_with_exception = records.reject { |r| !r.values["failure_exception"] }

          # Since exception is the key in the below hash, only one instance of an occurrence is kept
          exceptions_and_job_urls = records_with_exception.to_h do |r|
            [r.values["failure_exception"], r.values["job_url"]]
          end

          result[stage][product_group] ||= {}
          result[stage][product_group][name] = {
            file: file,
            link: link,
            runs: runs,
            failed: failed,
            exceptions_and_job_urls: exceptions_and_job_urls,
            failure_rate: failure_rate == 0 ? failure_rate.round(0) : failure_rate.round(2)
          }
        end
      end

      # rubocop:enable Metrics/AbcSize

      # Check if failure is allowed
      #
      # @param [String] failure_exception
      # @return [Boolean]
      def allowed_failure?(failure_exception)
        ALLOWED_EXCEPTION_PATTERNS.any? { |pattern| pattern.match?(failure_exception) }
      end

      # Returns true if first_time is before our range, or if last_time is before report date
      # offset 1 day due to how schedulers are configured and first run can be 1 day later
      #
      # @param [String] first_time
      # @param [String] last_time
      # @return [Boolean]
      def within_execution_range(first_time, last_time)
        (Date.today - Date.parse(first_time)).to_i < (range - 1) || (Date.today - Date.parse(last_time)).to_i > 1
      end

      # Flux query
      #
      # @param [Boolean] reliable
      # @return [String]
      def query(reliable)
        <<~QUERY
          from(bucket: "#{Support::InfluxdbTools::INFLUX_MAIN_TEST_METRICS_BUCKET}")
            |> range(start: -#{range}d)
            |> filter(fn: (r) => r._measurement == "test-stats")
            |> filter(fn: (r) => r.run_type == "staging-full" or
              r.run_type == "staging-sanity" or
              r.run_type == "production-full" or
              r.run_type == "production-sanity" or
              r.run_type == "package-and-qa" or
              r.run_type == "nightly"
            )
            |> filter(fn: (r) => r.job_name != "airgapped" and
              r.job_name != "instance-image-slow-network" and
              r.job_name != "nplus1-instance-image"
            )
            |> filter(fn: (r) => r.status != "pending" and
              r.merge_request == "false" and
              r.quarantined == "false" and
              r.smoke == "false" and
              r.reliable == "#{reliable}"
            )
            |> filter(fn: (r) => r["_field"] == "job_url" or
              r["_field"] == "failure_exception" or
              r["_field"] == "id"
            )
            |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
            |> group(columns: ["name"])
        QUERY
      end

      # Api get request
      #
      # @param [String] path
      # @param [Hash] payload
      # @return [Hash, Array]
      def api_get(path)
        response = get("#{gitlab_api_url}/#{path}", { headers: { "PRIVATE-TOKEN" => gitlab_access_token } })
        parse_body(response)
      end

      # Api update request
      #
      # @param [Symbol] verb :post or :put
      # @param [String] path
      # @param [Hash] payload
      # @return [Hash, Array]
      def api_update(verb, path, **payload)
        response = send(
          verb,
          "#{gitlab_api_url}/#{path}",
          payload,
          { headers: { "PRIVATE-TOKEN" => gitlab_access_token } }
        )
        parse_body(response)
      end
    end
  end
end
