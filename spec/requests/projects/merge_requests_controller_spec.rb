# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::MergeRequestsController, feature_category: :source_code_management do
  let_it_be(:merge_request) { create(:merge_request) }
  let_it_be(:project) { merge_request.project }
  let_it_be(:user) { merge_request.author }

  describe 'GET #show' do
    let_it_be(:group) { create(:group) }
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, :public, group: group) }

    let(:merge_request) { create :merge_request, source_project: project, author: user }

    context 'when the author of the merge request is banned', feature_category: :insider_threat do
      let_it_be(:user) { create(:user, :banned) }

      subject { response }

      before do
        get project_merge_request_path(project, merge_request)
      end

      it { is_expected.to have_gitlab_http_status(:not_found) }
    end
  end

  describe 'GET #index' do
    let_it_be(:public_project) { create(:project, :public) }

    it_behaves_like 'rate limited endpoint', rate_limit_key: :search_rate_limit do
      let_it_be(:current_user) { user }

      before do
        sign_in current_user
      end

      def request
        get project_merge_requests_path(public_project), params: { scope: 'all', search: 'test' }
      end
    end

    it_behaves_like 'rate limited endpoint', rate_limit_key: :search_rate_limit_unauthenticated do
      def request
        get project_merge_requests_path(public_project), params: { scope: 'all', search: 'test' }
      end
    end
  end

  describe 'GET #discussions' do
    let_it_be(:discussion) { create(:discussion_note_on_merge_request, noteable: merge_request, project: project) }
    let_it_be(:discussion_reply) do
      create(:discussion_note_on_merge_request, noteable: merge_request, project: project, in_reply_to: discussion)
    end

    let_it_be(:state_event) { create(:resource_state_event, merge_request: merge_request) }
    let_it_be(:discussion_2) { create(:discussion_note_on_merge_request, noteable: merge_request, project: project) }
    let_it_be(:discussion_3) { create(:diff_note_on_merge_request, noteable: merge_request, project: project) }

    before do
      login_as(user)
    end

    context 'pagination' do
      def get_discussions(**params)
        get discussions_project_merge_request_path(project, merge_request, params: params.merge(format: :json))
      end

      it 'returns paginated notes and cursor based on per_page param' do
        get_discussions(per_page: 2)

        discussions = Gitlab::Json.parse(response.body)
        notes = discussions.flat_map { |d| d['notes'] }

        expect(discussions.count).to eq(2)
        expect(notes).to match(
          [
            a_hash_including('id' => discussion.id.to_s),
            a_hash_including('id' => discussion_reply.id.to_s),
            a_hash_including('type' => 'StateNote')
          ])

        cursor = response.header['X-Next-Page-Cursor']
        expect(cursor).to be_present

        get_discussions(per_page: 1, cursor: cursor)

        discussions = Gitlab::Json.parse(response.body)
        notes = discussions.flat_map { |d| d['notes'] }

        expect(discussions.count).to eq(1)
        expect(notes).to match([a_hash_including('id' => discussion_2.id.to_s)])
      end
    end
  end

  context 'token authentication' do
    context 'when public project' do
      let_it_be(:public_project) { create(:project, :public) }

      it_behaves_like 'authenticates sessionless user for the request spec', 'index atom', public_resource: true do
        let(:url) { project_merge_requests_url(public_project, format: :atom) }
      end
    end

    context 'when private project' do
      let_it_be(:private_project) { create(:project, :private) }

      it_behaves_like 'authenticates sessionless user for the request spec', 'index atom',
        public_resource: false,
        ignore_metrics: true do
        let(:url) { project_merge_requests_url(private_project, format: :atom) }

        before do
          private_project.add_maintainer(user)
        end
      end
    end
  end

  describe 'GET #pipelines.json' do
    before do
      login_as(user)
    end

    it 'avoids N+1 queries', :use_sql_query_cache do
      create_pipeline

      # warm up
      get pipelines_project_merge_request_path(project, merge_request, format: :json)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        get pipelines_project_merge_request_path(project, merge_request, format: :json)
      end

      expect(response).to have_gitlab_http_status(:ok)
      expect(Gitlab::Json.parse(response.body)['count']['all']).to eq(1)

      create_pipeline

      expect do
        get pipelines_project_merge_request_path(project, merge_request, format: :json)
      end.to issue_same_number_of_queries_as(control)

      expect(response).to have_gitlab_http_status(:ok)
      expect(Gitlab::Json.parse(response.body)['count']['all']).to eq(2)
    end

    context 'when there are pipelines with failed builds' do
      before do
        pipeline = create_pipeline

        create(:ci_build, :failed, pipeline: pipeline)
        create(:ci_build, :failed, pipeline: pipeline)
      end

      it 'returns the failed build count but not the failed builds' do
        get pipelines_project_merge_request_path(project, merge_request, format: :json)

        expect(response).to have_gitlab_http_status(:ok)
        expect(Gitlab::Json.parse(response.body)['pipelines'].size).to eq(1)
        expect(Gitlab::Json.parse(response.body)['pipelines'][0]['failed_builds_count']).to eq(2)
        expect(Gitlab::Json.parse(response.body)['pipelines'][0]).not_to have_key('failed_builds')
      end

      it 'avoids N+1 queries', :use_sql_query_cache do
        # warm up
        get pipelines_project_merge_request_path(project, merge_request, format: :json)

        control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          get pipelines_project_merge_request_path(project, merge_request, format: :json)
        end

        expect(response).to have_gitlab_http_status(:ok)
        expect(Gitlab::Json.parse(response.body)['count']['all']).to eq(1)

        pipeline_2 = create_pipeline
        create(:ci_build, :failed, pipeline: pipeline_2)
        create(:ci_build, :failed, pipeline: pipeline_2)

        expect do
          get pipelines_project_merge_request_path(project, merge_request, format: :json)
        end.to issue_same_number_of_queries_as(control)

        expect(response).to have_gitlab_http_status(:ok)
        expect(Gitlab::Json.parse(response.body)['count']['all']).to eq(2)
      end
    end

    private

    def create_pipeline
      create(
        :ci_pipeline, :with_job, :success,
        project: merge_request.source_project,
        ref: merge_request.source_branch,
        sha: merge_request.diff_head_sha
      )
    end
  end
end
