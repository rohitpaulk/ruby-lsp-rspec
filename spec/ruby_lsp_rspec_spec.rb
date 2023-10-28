# typed: false
# frozen_string_literal: true

RSpec.describe RubyLsp::RSpec do
  let(:uri) { URI("file:///fake_spec.rb") }
  let(:store) { RubyLsp::Store.new }
  let(:message_queue) { Thread::Queue.new }

  after do
    message_queue.close
  end

  it "recognizes basic rspec test cases" do
    store.set(uri: uri, source: <<~RUBY, version: 1)
      RSpec.describe Foo do
        context "when something" do
          it "does something" do
          end
        end
      end
    RUBY

    response = RubyLsp::Executor.new(store, message_queue).execute(
      {
        method: "textDocument/codeLens",
        params: {
          textDocument: { uri: uri },
          position: { line: 0, character: 0 },
        },
      },
    )

    expect(response.error).to(be_nil)

    response = response.response
    expect(response.count).to eq(9)

    expect(response[0].data).to eq({ type: "test", kind: :group })
    expect(response[1].data).to eq({ type: "test_in_terminal", kind: :group })
    expect(response[2].data).to eq({ type: "debug", kind: :group })

    0.upto(2) do |i|
      expect(response[i].command.arguments).to eq([
        "/fake_spec.rb",
        "Foo",
        "bundle exec rspec /fake_spec.rb:1",
        { start_line: 0, start_column: 0, end_line: 5, end_column: 3 },
      ])
    end

    expect(response[3].data).to eq({ type: "test", kind: :group })
    expect(response[4].data).to eq({ type: "test_in_terminal", kind: :group })
    expect(response[5].data).to eq({ type: "debug", kind: :group })

    3.upto(5) do |i|
      expect(response[i].command.arguments).to eq([
        "/fake_spec.rb",
        "when something",
        "bundle exec rspec /fake_spec.rb:2",
        { start_line: 1, start_column: 2, end_line: 4, end_column: 5 },
      ])
    end

    expect(response[6].data).to eq({ type: "test", kind: :example })
    expect(response[7].data).to eq({ type: "test_in_terminal", kind: :example })
    expect(response[8].data).to eq({ type: "debug", kind: :example })

    6.upto(8) do |i|
      expect(response[i].command.arguments).to eq([
        "/fake_spec.rb",
        "does something",
        "bundle exec rspec /fake_spec.rb:3",
        { start_line: 2, start_column: 4, end_line: 3, end_column: 7 },
      ])
    end
  end

  it "recognizes different it declaration" do
    store.set(uri: uri, source: <<~RUBY, version: 1)
      RSpec.describe Foo do
        it { do_something }
        it var do
          do_something
        end
      end
    RUBY

    response = RubyLsp::Executor.new(store, message_queue).execute(
      {
        method: "textDocument/codeLens",
        params: {
          textDocument: { uri: uri },
          position: { line: 0, character: 0 },
        },
      },
    )

    expect(response.error).to(be_nil)

    response = response.response
    expect(response.count).to eq(9)

    expect(response[3].command.arguments[1]).to eq("<unnamed>")
    expect(response[6].command.arguments[1]).to eq("<var>")
  end

  it "recognizes different describe declaration" do
    store.set(uri: uri, source: <<~RUBY, version: 1)
      RSpec.describe(Foo::Bar) do
      end

      RSpec.describe Foo::Bar do
      end

      describe(Foo) do
      end

      describe Foo do
      end

      describe "Foo" do
      end

      describe var do
      end
    RUBY

    response = RubyLsp::Executor.new(store, message_queue).execute(
      {
        method: "textDocument/codeLens",
        params: {
          textDocument: { uri: uri },
          position: { line: 0, character: 0 },
        },
      },
    )

    expect(response.error).to(be_nil)

    response = response.response
    expect(response.count).to eq(18)

    expect(response[11].command.arguments[1]).to eq("Foo")
    expect(response[13].command.arguments[1]).to eq("Foo")
    expect(response[15].command.arguments[1]).to eq("<var>")
  end

  context "when the file is not a test file" do
    let(:uri) { URI("file:///not_spec_file.rb") }

    it "ignores file" do
      store.set(uri: uri, source: <<~RUBY, version: 1)
        class FooBar
          context "when something" do
          end
        end
      RUBY

      response = RubyLsp::Executor.new(store, message_queue).execute(
        {
          method: "textDocument/codeLens",
          params: {
            textDocument: { uri: uri },
            position: { line: 0, character: 0 },
          },
        },
      )

      expect(response.error).to(be_nil)
      expect(response.response.count).to eq(0)
    end
  end

  context "when there's a binstub" do
    let(:binstub_path) { File.expand_path("../bin/rspec", __dir__) }

    before do
      File.write(binstub_path, <<~RUBY)
        #!/usr/bin/env ruby
        puts "binstub is called"
      RUBY
    end

    after do
      FileUtils.rm(binstub_path) if File.exist?(binstub_path)
    end

    it "uses the binstub" do
      store.set(uri: uri, source: <<~RUBY, version: 1)
        RSpec.describe(Foo::Bar) do
        end
      RUBY

      response = RubyLsp::Executor.new(store, message_queue).execute(
        {
          method: "textDocument/codeLens",
          params: {
            textDocument: { uri: uri },
            position: { line: 0, character: 0 },
          },
        },
      )

      expect(response.error).to(be_nil)

      response = response.response
      expect(response.count).to eq(3)
      expect(response[0].command.arguments[2]).to eq("bundle exec bin/rspec /fake_spec.rb:1")
    end
  end
end
