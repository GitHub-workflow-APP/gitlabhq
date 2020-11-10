# frozen_string_literal: true
require 'spec_helper'

RSpec.describe 'getting container repositories in a project' do
  using RSpec::Parameterized::TableSyntax
  include GraphqlHelpers

  let_it_be_with_reload(:project) { create(:project, :private) }
  let_it_be(:container_repository) { create(:container_repository, project: project) }
  let_it_be(:container_repositories_delete_scheduled) { create_list(:container_repository, 2, :status_delete_scheduled, project: project) }
  let_it_be(:container_repositories_delete_failed) { create_list(:container_repository, 2, :status_delete_failed, project: project) }
  let_it_be(:container_repositories) { [container_repository, container_repositories_delete_scheduled, container_repositories_delete_failed].flatten }
  let_it_be(:container_expiration_policy) { project.container_expiration_policy }

  let(:fields) do
    <<~GQL
      edges {
        node {
          #{all_graphql_fields_for('container_repositories'.classify)}
        }
      }
    GQL
  end

  let(:query) do
    graphql_query_for(
      'project',
      { 'fullPath' => project.full_path },
      query_graphql_field('container_repositories', {}, fields)
    )
  end

  let(:user) { project.owner }
  let(:variables) { {} }
  let(:container_repositories_response) { graphql_data.dig('project', 'containerRepositories', 'edges') }

  before do
    stub_container_registry_config(enabled: true)
    container_repositories.each do |repository|
      stub_container_registry_tags(repository: repository.path, tags: %w(tag1 tag2 tag3), with_manifest: false)
    end
  end

  subject { post_graphql(query, current_user: user, variables: variables) }

  it_behaves_like 'a working graphql query' do
    before do
      subject
    end
  end

  context 'with different permissions' do
    let_it_be(:user) { create(:user) }

    where(:project_visibility, :role, :access_granted, :can_delete) do
      :private | :maintainer | true  | true
      :private | :developer  | true  | true
      :private | :reporter   | true  | false
      :private | :guest      | false | false
      :private | :anonymous  | false | false
      :public  | :maintainer | true  | true
      :public  | :developer  | true  | true
      :public  | :reporter   | true  | false
      :public  | :guest      | true  | false
      :public  | :anonymous  | true  | false
    end

    with_them do
      before do
        project.update!(visibility_level: Gitlab::VisibilityLevel.const_get(project_visibility.to_s.upcase, false))
        project.add_user(user, role) unless role == :anonymous
      end

      it 'return the proper response' do
        subject

        if access_granted
          expect(container_repositories_response.size).to eq(container_repositories.size)
          container_repositories_response.each do |repository_response|
            expect(repository_response.dig('node', 'canDelete')).to eq(can_delete)
          end
        else
          expect(container_repositories_response).to eq(nil)
        end
      end
    end
  end

  context 'limiting the number of repositories' do
    let(:limit) { 1 }
    let(:variables) do
      { path: project.full_path, n: limit }
    end

    let(:query) do
      <<~GQL
        query($path: ID!, $n: Int) {
          project(fullPath: $path) {
            containerRepositories(first: $n) { #{fields} }
          }
        }
      GQL
    end

    it 'only returns N repositories' do
      subject

      expect(container_repositories_response.size).to eq(limit)
    end
  end

  context 'filter by name' do
    let_it_be(:container_repository) { create(:container_repository, name: 'fooBar', project: project) }

    let(:name) { 'ooba' }
    let(:query) do
      <<~GQL
        query($path: ID!, $name: String) {
          project(fullPath: $path) {
            containerRepositories(name: $name) { #{fields} }
          }
        }
      GQL
    end

    let(:variables) do
      { path: project.full_path, name: name }
    end

    before do
      stub_container_registry_tags(repository: container_repository.path, tags: %w(tag4 tag5 tag6), with_manifest: false)
    end

    it 'returns the searched container repository' do
      subject

      expect(container_repositories_response.size).to eq(1)
      expect(container_repositories_response.first.dig('node', 'id')).to eq(container_repository.to_global_id.to_s)
    end
  end
end
