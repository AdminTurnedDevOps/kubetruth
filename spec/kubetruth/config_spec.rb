require 'rspec'
require 'kubetruth/config'

module Kubetruth
  describe Config do

    let(:config) { described_class.new([]) }

    describe "ProjectSpec" do

      it "has same keys for defaults and struct" do
        expect(described_class::ProjectSpec.new.to_h.keys).to eq(described_class::DEFAULT_SPEC.keys)
      end

      it "converts types" do
        spec = described_class::ProjectSpec.new(
          scope: "root",
          project_selector: "foo",
          resource_templates: ["bar"],
          skip: true
        )
        expect(spec.scope).to be_an_instance_of(String)
        expect(spec.scope).to eq("root")
        expect(spec.project_selector).to be_an_instance_of(Regexp)
        expect(spec.project_selector).to eq(/foo/)
        expect(spec.resource_templates.first).to be_an_instance_of(Template)
        expect(spec.resource_templates.first.source).to eq("bar")
        expect(spec.skip).to equal(true)
      end

    end

    describe "initialization" do

      it "sets mappings" do
        expect(config.instance_variable_get(:@project_mapping_crds)).to eq([])
      end

    end

    describe "load" do

      it "set defaults" do
        expect(config.instance_variable_get(:@config)).to be_nil
        config.load
        expect(config.instance_variable_get(:@config)).to eq(Kubetruth::Config::DEFAULT_SPEC)
      end

      it "is memoized" do
        expect(config.instance_variable_get(:@config)).to be_nil
        config.load
        old = config.instance_variable_get(:@config)
        expect(Kubetruth::Config::ProjectSpec).to receive(:new).never
        config.load
        expect(config.instance_variable_get(:@config)).to equal(old)
      end

      it "raises error for invalid config" do
        config = described_class.new([{scope: "root", foo: "bar"}])
        expect { config.load }.to raise_error(ArgumentError, /unknown keywords: foo/)
        config = described_class.new([{scope: "override", bar: "baz"}])
        expect { config.load }.to raise_error(ArgumentError, /unknown keywords: bar/)
      end

      it "raises error for multiple root scopes" do
        config = described_class.new([{scope: "root", foo: "bar"}, {scope: "root", bar: "baz"}])
        expect { config.load }.to raise_error(ArgumentError, /Multiple root/)
      end

      it "loads data into config" do
        data = [
          {
            scope: "root",
            project_selector: "project_selector",
            key_selector: "key_selector",
            skip: true,
            included_projects: ["included_projects"],
            resource_templates: ["resource_templates"]
          },
          {
            scope: "override",
            project_selector: "project_overrides:project_selector",
            resource_templates: ["project_overrides:resource_templates"]
          }
        ]
        config = described_class.new(data)
        config.load
        expect(config.instance_variable_get(:@config)).to_not eq(Kubetruth::Config::DEFAULT_SPEC)
        expect(config.root_spec).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
        expect(config.root_spec.resource_templates.first).to be_an_instance_of(Kubetruth::Template)
        expect(config.root_spec.resource_templates.first.source).to eq("resource_templates")
        expect(config.root_spec.key_selector).to eq(/key_selector/)
        expect(config.override_specs.size).to eq(1)
        expect(config.override_specs.first).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
        expect(config.override_specs.first.resource_templates.first).to be_an_instance_of(Kubetruth::Template)
        expect(config.override_specs.first.resource_templates.first.source).to eq("project_overrides:resource_templates")
      end

    end

    describe "root_spec" do

      it "loads and returns the root spec" do
        expect(config).to receive(:load).and_call_original
        expect(config.root_spec).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
      end

    end

    describe "override_specs" do

      it "loads and returns the override specs" do
        config = described_class.new([{scope: "override", project_selector: ""}])
        expect(config).to receive(:load).and_call_original
        expect(config.override_specs).to all(be_an_instance_of(Kubetruth::Config::ProjectSpec))
      end

      it "doesn't return nil when none" do
        expect(config).to receive(:load).and_call_original
        expect(config.override_specs).to eq([])
      end

    end

    describe "spec_for_project" do

      it "returns root spec if no matching override" do
        expect(config.spec_for_project("foo")).to equal(config.root_spec)
      end

      it "returns the matching override specs" do
        config = described_class.new([{scope: "override", project_selector: "fo+", resource_templates: ["foocm"]}])
        spec = config.spec_for_project("foo")
        expect(spec).to_not equal(config.root_spec)
        expect(spec.resource_templates.first).to be_an_instance_of(Kubetruth::Template)
        expect(spec.resource_templates.first.source).to eq("foocm")
      end

      it "raises for multiple matching specs" do
        config = described_class.new([
          {scope: "override", project_selector: "bo+", resource_templates: ["not"]},
          {scope: "override", project_selector: "fo+", resource_templates: ["first"]},
          {scope: "override", project_selector: "foo", resource_templates: ["second"]}
        ])
        expect { config.spec_for_project("foo") }.to raise_error(Config::DuplicateSelection, /Multiple configuration specs/)
      end

      it "memoizes specs by project name" do
        config = described_class.new([{scope: "override", project_selector: "fo+", resource_templates: ["foocm"]}])
        expect(config.instance_variable_get(:@spec_mapping)).to eq({})
        spec = config.spec_for_project("foo")
        expect(config.instance_variable_get(:@spec_mapping)).to eq({"foo" => spec})
        expect(config.override_specs).to_not receive(:find_all)
        spec2 = config.spec_for_project("foo")
        expect(spec2).to equal(spec)
      end

    end

  end
end
