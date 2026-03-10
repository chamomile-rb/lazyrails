# frozen_string_literal: true

RSpec.describe LazyRails::GeneratorWizard do
  subject(:wizard) { described_class.new }

  def type_string(str)
    str.chars.each { |c| wizard.handle_key(c) }
  end

  def add_field(name, type_index = 0)
    type_string(name)
    wizard.handle_key(:enter)
    type_index.times { wizard.handle_key("j") }
    wizard.handle_key(:enter)
  end

  describe "#show / #hide" do
    it "starts hidden" do
      expect(wizard).not_to be_visible
    end

    it "becomes visible when shown" do
      wizard.show(gen_type: "model", gen_label: "Model")
      expect(wizard).to be_visible
      expect(wizard.step).to eq(:name)
    end

    it "hides on escape from name step" do
      wizard.show(gen_type: "model", gen_label: "Model")
      result = wizard.handle_key(:escape)
      expect(result).to eq({ action: :cancel })
      expect(wizard).not_to be_visible
    end

    it "resets all state when reshown" do
      wizard.show(gen_type: "model", gen_label: "Model")
      type_string("User")
      wizard.handle_key(:enter)
      add_field("name")

      wizard.show(gen_type: "controller", gen_label: "Controller")
      expect(wizard.step).to eq(:name)
      expect(wizard.gen_type).to eq("controller")
    end
  end

  describe "name step" do
    before { wizard.show(gen_type: "model", gen_label: "Model") }

    it "requires a non-empty name" do
      wizard.handle_key(:enter)
      expect(wizard.step).to eq(:name)
    end

    it "rejects whitespace-only names" do
      type_string("   ")
      wizard.handle_key(:enter)
      expect(wizard.step).to eq(:name)
    end

    it "supports backspace" do
      type_string("Userx")
      wizard.handle_key(:backspace)
      wizard.handle_key(:enter)
      add_field("name")
      wizard.handle_key(:enter)
      result = wizard.handle_key(:enter)
      expect(result[:command]).to include("User")
      expect(result[:command]).not_to include("Userx")
    end

    it "ignores non-string keys" do
      wizard.handle_key(:down)
      wizard.handle_key(:up)
      wizard.handle_key(:tab)
      expect(wizard.step).to eq(:name) # nothing broke
    end
  end

  describe "model wizard" do
    before { wizard.show(gen_type: "model", gen_label: "Model") }

    it "builds correct command with fields" do
      type_string("User")
      wizard.handle_key(:enter)

      add_field("name")       # string (index 0)
      add_field("email")      # string (index 0)

      wizard.handle_key(:enter)
      expect(wizard.step).to eq(:review)

      result = wizard.handle_key(:enter)
      expect(result[:action]).to eq(:run)
      expect(result[:command]).to eq(%w[bin/rails generate model User name:string email:string])
    end

    it "allows picking non-default column types" do
      type_string("User")
      wizard.handle_key(:enter)

      add_field("age", 1)      # integer
      add_field("bio", 2)      # text
      add_field("active", 3)   # boolean

      wizard.handle_key(:enter)
      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate model User age:integer bio:text active:boolean])
    end

    it "allows references type" do
      type_string("Comment")
      wizard.handle_key(:enter)

      add_field("post", 10)    # references (last in list)

      wizard.handle_key(:enter)
      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate model Comment post:references])
    end

    it "requires at least one field for model" do
      type_string("User")
      wizard.handle_key(:enter)
      wizard.handle_key(:enter)
      expect(wizard.step).to eq(:fields)
    end

    it "deletes last field with backspace on empty input" do
      type_string("User")
      wizard.handle_key(:enter)

      add_field("name")
      add_field("extra")

      wizard.handle_key(:backspace) # delete "extra" field
      wizard.handle_key(:enter)     # finish with just "name"
      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate model User name:string])
    end

    it "allows typing d in field names" do
      type_string("User")
      wizard.handle_key(:enter)

      add_field("description") # field name contains 'd'

      wizard.handle_key(:enter)
      result = wizard.handle_key(:enter)
      expect(result[:command]).to include("description:string")
    end

    it "navigates back from fields to name" do
      type_string("User")
      wizard.handle_key(:enter)
      wizard.handle_key(:escape)
      expect(wizard.step).to eq(:name)
    end

    it "clears field input on escape when input is non-empty" do
      type_string("User")
      wizard.handle_key(:enter)
      type_string("partial")
      wizard.handle_key(:escape) # clears input, stays on fields
      expect(wizard.step).to eq(:fields)
      wizard.handle_key(:escape) # now empty, goes back
      expect(wizard.step).to eq(:name)
    end

    it "goes back from type picker to field name on escape" do
      type_string("User")
      wizard.handle_key(:enter)
      type_string("name")
      wizard.handle_key(:enter) # go to type picker
      wizard.handle_key(:escape) # back to field name editing
      expect(wizard.step).to eq(:fields)
    end

    it "goes back from type picker to field name on backspace" do
      type_string("User")
      wizard.handle_key(:enter)
      type_string("name")
      wizard.handle_key(:enter) # go to type picker
      wizard.handle_key(:backspace) # back to field name editing
      expect(wizard.step).to eq(:fields)
    end

    it "navigates back from review to fields" do
      type_string("User")
      wizard.handle_key(:enter)
      add_field("name")
      wizard.handle_key(:enter) # review
      wizard.handle_key(:escape) # back to fields
      expect(wizard.step).to eq(:fields)
    end

    it "type cursor wraps around" do
      type_string("User")
      wizard.handle_key(:enter)
      type_string("name")
      wizard.handle_key(:enter) # type picker
      wizard.handle_key("k")    # wrap to bottom (references)
      wizard.handle_key(:enter)

      wizard.handle_key(:enter)
      result = wizard.handle_key(:enter)
      expect(result[:command]).to include("name:references")
    end
  end

  describe "controller wizard" do
    before { wizard.show(gen_type: "controller", gen_label: "Controller") }

    it "builds command with selected actions" do
      type_string("Articles")
      wizard.handle_key(:enter)

      wizard.handle_key(" ")    # toggle index
      wizard.handle_key("j")
      wizard.handle_key(" ")    # toggle show
      wizard.handle_key(:enter)

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate controller Articles index show])
    end

    it "supports toggle all with 'a'" do
      type_string("Foo")
      wizard.handle_key(:enter)
      wizard.handle_key("a")
      wizard.handle_key(:enter)

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate controller Foo index show new create edit update destroy])
    end

    it "allows no actions selected" do
      type_string("Static")
      wizard.handle_key(:enter)
      wizard.handle_key(:enter) # no actions, go to review

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate controller Static])
    end

    it "toggle all off when all are on" do
      type_string("Foo")
      wizard.handle_key(:enter)
      wizard.handle_key("a")    # all on
      wizard.handle_key("a")    # all off
      wizard.handle_key(:enter)

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate controller Foo])
    end

    it "navigates back from actions to name" do
      type_string("Foo")
      wizard.handle_key(:enter)
      wizard.handle_key(:escape)
      expect(wizard.step).to eq(:name)
    end
  end

  describe "migration wizard" do
    before { wizard.show(gen_type: "migration", gen_label: "Migration") }

    it "allows migration with no fields" do
      type_string("AddIndexToUsers")
      wizard.handle_key(:enter)
      wizard.handle_key(:enter) # empty = review (migration allows no fields)
      expect(wizard.step).to eq(:review)

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate migration AddIndexToUsers])
    end

    it "allows migration with fields" do
      type_string("AddStatusToOrders")
      wizard.handle_key(:enter)

      add_field("status", 1)   # integer

      wizard.handle_key(:enter)
      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate migration AddStatusToOrders status:integer])
    end
  end

  describe "job wizard" do
    it "goes straight from name to review" do
      wizard.show(gen_type: "job", gen_label: "Job")
      type_string("ProcessPayment")
      wizard.handle_key(:enter)
      expect(wizard.step).to eq(:review)

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate job ProcessPayment])
    end
  end

  describe "channel wizard" do
    it "goes straight from name to review" do
      wizard.show(gen_type: "channel", gen_label: "Channel")
      type_string("Chat")
      wizard.handle_key(:enter)
      expect(wizard.step).to eq(:review)

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate channel Chat])
    end
  end

  describe "stimulus wizard" do
    it "goes straight from name to review" do
      wizard.show(gen_type: "stimulus", gen_label: "Stimulus")
      type_string("toggle")
      wizard.handle_key(:enter)
      expect(wizard.step).to eq(:review)

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate stimulus toggle])
    end
  end

  describe "mailer wizard" do
    before { wizard.show(gen_type: "mailer", gen_label: "Mailer") }

    it "builds command with methods" do
      type_string("UserMailer")
      wizard.handle_key(:enter)

      type_string("welcome")
      wizard.handle_key(:enter)
      type_string("reset_password")
      wizard.handle_key(:enter)
      wizard.handle_key(:enter) # empty -> review

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate mailer UserMailer welcome reset_password])
    end

    it "requires at least one method" do
      type_string("UserMailer")
      wizard.handle_key(:enter)
      wizard.handle_key(:enter)
      expect(wizard.step).to eq(:methods)
    end

    it "deletes last method with backspace on empty input" do
      type_string("UserMailer")
      wizard.handle_key(:enter)

      type_string("welcome")
      wizard.handle_key(:enter)
      type_string("extra")
      wizard.handle_key(:enter)

      wizard.handle_key(:backspace) # delete "extra"
      wizard.handle_key(:enter)     # finish with just "welcome"
      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate mailer UserMailer welcome])
    end

    it "allows typing d in method names" do
      type_string("UserMailer")
      wizard.handle_key(:enter)

      type_string("deliver_receipt")
      wizard.handle_key(:enter)
      wizard.handle_key(:enter)

      result = wizard.handle_key(:enter)
      expect(result[:command]).to include("deliver_receipt")
    end

    it "clears method input on escape when non-empty" do
      type_string("UserMailer")
      wizard.handle_key(:enter)
      type_string("partial")
      wizard.handle_key(:escape)
      expect(wizard.step).to eq(:methods)
      wizard.handle_key(:escape)
      expect(wizard.step).to eq(:name)
    end
  end

  describe "scaffold wizard" do
    it "follows same flow as model" do
      wizard.show(gen_type: "scaffold", gen_label: "Scaffold")
      type_string("Post")
      wizard.handle_key(:enter)

      add_field("title")       # string
      add_field("body", 2)     # text

      wizard.handle_key(:enter)

      result = wizard.handle_key(:enter)
      expect(result[:command]).to eq(%w[bin/rails generate scaffold Post title:string body:text])
    end
  end

  describe "#render" do
    it "renders name step with step indicator" do
      wizard.show(gen_type: "model", gen_label: "Model")
      output = wizard.render(width: 80, height: 24)
      expect(output).to include("Model")
      expect(output).to include("1/3")
    end

    it "renders fields step" do
      wizard.show(gen_type: "model", gen_label: "Model")
      type_string("User")
      wizard.handle_key(:enter)
      output = wizard.render(width: 80, height: 24)
      expect(output).to include("Field name")
      expect(output).to include("2/3")
    end

    it "renders type picker" do
      wizard.show(gen_type: "model", gen_label: "Model")
      type_string("User")
      wizard.handle_key(:enter)
      type_string("name")
      wizard.handle_key(:enter)
      output = wizard.render(width: 80, height: 24)
      expect(output).to include("string")
      expect(output).to include("integer")
    end

    it "renders actions step" do
      wizard.show(gen_type: "controller", gen_label: "Controller")
      type_string("Foo")
      wizard.handle_key(:enter)
      output = wizard.render(width: 80, height: 24)
      expect(output).to include("index")
      expect(output).to include("show")
    end

    it "renders review step" do
      wizard.show(gen_type: "job", gen_label: "Job")
      type_string("Test")
      wizard.handle_key(:enter)
      output = wizard.render(width: 80, height: 24)
      expect(output).to include("Ready to generate")
      expect(output).to include("bin/rails generate job Test")
    end

    it "returns empty string when hidden" do
      expect(wizard.render(width: 80, height: 24)).to eq("")
    end
  end
end
