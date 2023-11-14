# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Catalog::Resources::Component, type: :model, feature_category: :pipeline_composition do
  let(:component) { build(:ci_catalog_resource_component) }

  it { is_expected.to belong_to(:catalog_resource).class_name('Ci::Catalog::Resource') }
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:version).class_name('Ci::Catalog::Resources::Version') }

  it_behaves_like 'a BulkInsertSafe model', described_class do
    let_it_be(:project) { create(:project, :readme, description: 'project description') }
    let_it_be(:catalog_resource) { create(:ci_catalog_resource, project: project) }
    let_it_be(:version) { create(:ci_catalog_resource_version, project: project) }

    let(:valid_items_for_bulk_insertion) do
      build_list(:ci_catalog_resource_component, 10) do |component|
        component.catalog_resource = catalog_resource
        component.version = version
        component.project = project
        component.created_at = Time.zone.now
      end
    end

    let(:invalid_items_for_bulk_insertion) { [] }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:catalog_resource) }
    it { is_expected.to validate_presence_of(:project) }
    it { is_expected.to validate_presence_of(:version) }
    it { is_expected.to validate_presence_of(:name) }

    context 'when attributes are valid' do
      it 'returns no errors' do
        component.inputs = {
          website: nil,
          environment: {
            default: 'test'
          },
          tags: {
            type: 'array'
          }
        }
        expect(component).to be_valid
      end
    end

    context 'when data is invalid' do
      it 'returns errors' do
        component.inputs = { boo: [] }

        aggregate_failures do
          expect(component).to be_invalid
          expect(component.errors.full_messages).to contain_exactly(
            'Inputs must be a valid json schema'
          )
        end
      end
    end
  end
end
