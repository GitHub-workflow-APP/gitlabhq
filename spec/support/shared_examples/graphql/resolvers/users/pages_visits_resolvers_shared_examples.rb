# frozen_string_literal: true

RSpec.shared_examples 'namespace visits resolver' do
  include GraphqlHelpers

  describe '#resolve' do
    context 'when user is not logged in' do
      let_it_be(:current_user) { nil }

      it 'returns nil' do
        expect(resolve_items).to eq(nil)
      end
    end

    context 'when user is logged in' do
      let_it_be(:current_user) { create(:user) }

      context 'when the frecent_namespaces_suggestions feature flag is disabled' do
        before do
          stub_feature_flags(frecent_namespaces_suggestions: false)
        end

        it 'raises a "Resource not available" exception' do
          expect(resolve_items).to be_a(::Gitlab::Graphql::Errors::ResourceNotAvailable)
        end
      end

      it 'returns frecent groups' do
        expect(resolve_items).to be_an_instance_of(Array)
      end
    end
  end

  private

  def resolve_items
    sync(resolve(described_class, ctx: { current_user: current_user }))
  end
end
