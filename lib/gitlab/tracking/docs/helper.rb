# frozen_string_literal: true

module Gitlab
  module Tracking
    module Docs
      # Helper with functions to be used by HAML templates
      module Helper
        def auto_generated_comment
          <<-MARKDOWN.strip_heredoc
            ---
            stage: Growth
            group: Product Intelligence
            info: To determine the technical writer assigned to the Stage/Group associated with this page, see https://about.gitlab.com/handbook/engineering/ux/technical-writing/#designated-technical-writers
            ---

            <!---
              This documentation is auto generated by a script.

              Please do not edit this file directly, check generate_metrics_dictionary task on lib/tasks/gitlab/usage_data.rake.
            --->

            <!-- vale gitlab.Spelling = NO -->
          MARKDOWN
        end

        def render_description(object)
          return 'Missing description' unless object.description.present?

          object.description
        end

        def render_event_taxonomy(object)
          headers = %w[category action label property value]
          values = %i[category action label property_description value_description]
          values = values.map { |key| backtick(object.attributes[key]) }
          values = values.join(" | ")

          [
            "| #{headers.join(" | ")} |",
            "#{'|---' * headers.size}|",
            "| #{values} |"
          ].join("\n")
        end

        def md_link_to(anchor_text, url)
          "[#{anchor_text}](#{url})"
        end

        def render_owner(object)
          "Owner: #{backtick(object.product_group)}"
        end

        def render_tiers(object)
          "Tiers: #{object.tiers.map(&method(:backtick)).join(', ')}"
        end

        def render_yaml_definition_path(object)
          "YAML definition: #{backtick(object.yaml_path)}"
        end

        def backtick(string)
          "`#{string}`"
        end
      end
    end
  end
end
