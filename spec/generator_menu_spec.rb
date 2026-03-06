# frozen_string_literal: true

RSpec.describe "Generator menu" do
  describe "GENERATOR_TYPES constant" do
    it "contains 8 generator types" do
      expect(LazyRails::App::GENERATOR_TYPES.size).to eq(8)
    end

    it "has required keys for each entry" do
      LazyRails::App::GENERATOR_TYPES.each do |gt|
        expect(gt).to have_key(:type)
        expect(gt).to have_key(:label)
        expect(gt).to have_key(:placeholder)
        expect(gt[:type]).to be_a(String)
        expect(gt[:label]).to be_a(String)
        expect(gt[:placeholder]).to be_a(String)
      end
    end

    it "includes model, migration, controller, scaffold, job, mailer, channel, stimulus" do
      types = LazyRails::App::GENERATOR_TYPES.map { |gt| gt[:type] }
      expect(types).to contain_exactly(
        "model", "migration", "controller", "scaffold",
        "job", "mailer", "channel", "stimulus"
      )
    end
  end

  describe "MenuOverlay integration" do
    let(:menu) { LazyRails::MenuOverlay.new }

    it "can display generator items" do
      items = LazyRails::App::GENERATOR_TYPES.map do |gt|
        LazyRails::MenuOverlay::MenuItem.new(
          label: gt[:label], key: nil, action: :"generate_#{gt[:type]}"
        )
      end
      menu.show(title: "Generate", items: items)

      expect(menu).to be_visible
      expect(menu.title).to eq("Generate")
    end

    it "returns generate action when item is selected" do
      items = [
        LazyRails::MenuOverlay::MenuItem.new(label: "Model", key: nil, action: :generate_model),
        LazyRails::MenuOverlay::MenuItem.new(label: "Controller", key: nil, action: :generate_controller)
      ]
      menu.show(title: "Generate", items: items)

      menu.handle_key("j") # move to controller
      result = menu.handle_key(:enter)
      expect(result).to eq(:generate_controller)
      expect(menu).not_to be_visible
    end

    it "renders the menu overlay" do
      items = [
        LazyRails::MenuOverlay::MenuItem.new(label: "Model", key: nil, action: :generate_model)
      ]
      menu.show(title: "Generate", items: items)

      output = menu.render(width: 80, height: 24)
      expect(output).to include("Model")
    end
  end

  describe "generator action name pattern" do
    it "matches expected pattern for all types" do
      LazyRails::App::GENERATOR_TYPES.each do |gt|
        action = :"generate_#{gt[:type]}"
        match = action.to_s.match(/\Agenerate_(.+)\z/)
        expect(match).not_to be_nil
        expect(match[1]).to eq(gt[:type])
      end
    end
  end
end
