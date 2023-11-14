# frozen_string_literal: true

RSpec.shared_examples "redis_shared_examples" do
  include StubENV
  include TmpdirHelper

  let(:test_redis_url) { "redis://redishost:#{redis_port}" }
  let(:test_cluster_config) { { cluster: [{ host: "redis://redishost", port: redis_port }] } }
  let(:config_file_name) { instance_specific_config_file }
  let(:config_old_format_socket) { "spec/fixtures/config/redis_old_format_socket.yml" }
  let(:config_new_format_socket) { "spec/fixtures/config/redis_new_format_socket.yml" }
  let(:old_socket_path) { "/path/to/old/redis.sock" }
  let(:new_socket_path) { "/path/to/redis.sock" }
  let(:config_old_format_host) { "spec/fixtures/config/redis_old_format_host.yml" }
  let(:config_new_format_host) { "spec/fixtures/config/redis_new_format_host.yml" }
  let(:config_cluster_format_host) { "spec/fixtures/config/redis_cluster_format_host.yml" }
  let(:redis_port) { 6379 }
  let(:redis_database) { 99 }
  let(:sentinel_port) { 26379 }
  let(:config_with_environment_variable_inside) { "spec/fixtures/config/redis_config_with_env.yml" }
  let(:config_env_variable_url) { "TEST_GITLAB_REDIS_URL" }
  let(:rails_root) { mktmpdir }

  before do
    allow(described_class).to receive(:config_file_name).and_return(Rails.root.join(config_file_name).to_s)
    allow(described_class).to receive(:redis_yml_path).and_return('/dev/null')
  end

  describe '.config_file_name' do
    subject { described_class.config_file_name }

    before do
      # Undo top-level stub of config_file_name because we are testing that method now.
      allow(described_class).to receive(:config_file_name).and_call_original

      allow(described_class).to receive(:rails_root).and_return(rails_root)
      FileUtils.mkdir_p(File.join(rails_root, 'config'))
    end

    context 'when there is no config file anywhere' do
      it { expect(subject).to be_nil }
    end
  end

  describe '.store' do
    let(:rails_env) { 'development' }

    subject { described_class.new(rails_env).store }

    shared_examples 'redis store' do
      let(:redis_store) { ::Redis::Store }
      let(:redis_store_to_s) { "Redis Client connected to #{host} against DB #{redis_database}" }

      it 'instantiates Redis::Store' do
        is_expected.to be_a(redis_store)

        expect(subject.to_s).to eq(redis_store_to_s)
      end

      context 'with the namespace' do
        let(:namespace) { 'namespace_name' }
        let(:redis_store_to_s) do
          "Redis Client connected to #{host} against DB #{redis_database} with namespace #{namespace}"
        end

        subject { described_class.new(rails_env).store(namespace: namespace) }

        it "uses specified namespace" do
          expect(subject.to_s).to eq(redis_store_to_s)
        end
      end
    end

    context 'with old format' do
      it_behaves_like 'redis store' do
        let(:config_file_name) { config_old_format_host }
        let(:host) { "localhost:#{redis_port}" }
      end
    end

    context 'with new format' do
      it_behaves_like 'redis store' do
        let(:config_file_name) { config_new_format_host }
        let(:host) { "development-host:#{redis_port}" }
      end
    end
  end

  describe '.params' do
    subject { described_class.new(rails_env).params }

    let(:rails_env) { 'development' }
    let(:config_file_name) { config_old_format_socket }

    it 'withstands mutation' do
      params1 = described_class.params
      params2 = described_class.params
      params1[:foo] = :bar

      expect(params2).not_to have_key(:foo)
    end

    context 'when url contains unix socket reference' do
      context 'with old format' do
        let(:config_file_name) { config_old_format_socket }

        it 'returns path key instead' do
          is_expected.to include(path: old_socket_path)
          is_expected.not_to have_key(:url)
        end
      end

      context 'with new format' do
        let(:config_file_name) { config_new_format_socket }

        it 'returns path key instead' do
          is_expected.to include(path: new_socket_path)
          is_expected.not_to have_key(:url)
        end
      end
    end

    context 'when url is host based' do
      context 'with old format' do
        let(:config_file_name) { config_old_format_host }

        it 'returns hash with host, port, db, and password' do
          is_expected.to include(host: 'localhost', password: 'mypassword', port: redis_port, db: redis_database)
          is_expected.not_to have_key(:url)
        end
      end

      context 'with new format' do
        let(:config_file_name) { config_new_format_host }

        where(:rails_env, :host) do
          [
            %w[development development-host],
            %w[test test-host],
            %w[production production-host]
          ]
        end

        with_them do
          it 'returns hash with host, port, db, and password' do
            is_expected.to include(host: host, password: 'mynewpassword', port: redis_port, db: redis_database)
            is_expected.not_to have_key(:url)
          end
        end
      end

      context 'with redis cluster format' do
        let(:config_file_name) { config_cluster_format_host }

        where(:rails_env, :host) do
          [
            %w[development development-master],
            %w[test test-master],
            %w[production production-master]
          ]
        end

        with_them do
          it 'returns hash with cluster and password' do
            is_expected.to include(
              password: 'myclusterpassword',
              cluster: [
                { host: "#{host}1", port: redis_port },
                { host: "#{host}2", port: redis_port }
              ]
            )
            is_expected.not_to have_key(:url)
          end
        end
      end
    end
  end

  describe '.url' do
    let(:config_file_name) { config_old_format_socket }

    it 'withstands mutation' do
      url1 = described_class.url
      url2 = described_class.url
      url1 << 'foobar' unless url1.frozen?

      expect(url2).not_to end_with('foobar')
    end

    context 'when yml file with env variable' do
      let(:config_file_name) { config_with_environment_variable_inside }

      before do
        stub_env(config_env_variable_url, test_redis_url)
      end

      it 'reads redis url from env variable' do
        expect(described_class.url).to eq test_redis_url
      end
    end
  end

  describe '.version' do
    it 'returns a version' do
      expect(described_class.version).to be_present
    end
  end

  describe '.with' do
    let(:config_file_name) { config_old_format_socket }

    before do
      clear_pool
    end

    after do
      clear_pool
    end

    context 'when running on single-threaded runtime' do
      before do
        allow(Gitlab::Runtime).to receive(:multi_threaded?).and_return(false)
      end

      it 'instantiates a connection pool with size 5' do
        expect(ConnectionPool).to receive(:new).with(size: 5).and_call_original

        described_class.with { |_redis_shared_example| true }
      end
    end

    context 'when running on multi-threaded runtime' do
      before do
        allow(Gitlab::Runtime).to receive(:multi_threaded?).and_return(true)
        allow(Gitlab::Runtime).to receive(:max_threads).and_return(18)
      end

      it 'instantiates a connection pool with a size based on the concurrency of the worker' do
        expect(ConnectionPool).to receive(:new).with(size: 18 + 5).and_call_original

        described_class.with { |_redis_shared_example| true }
      end
    end

    context 'when there is no config at all' do
      before do
        # Undo top-level stub of config_file_name because we are testing that method now.
        allow(described_class).to receive(:config_file_name).and_call_original

        allow(described_class).to receive(:rails_root).and_return(rails_root)
      end

      it 'can run an empty block' do
        expect { described_class.with { nil } }.not_to raise_error
      end
    end
  end

  describe '#db' do
    let(:rails_env) { 'development' }

    subject { described_class.new(rails_env).db }

    context 'with old format' do
      let(:config_file_name) { config_old_format_host }

      it 'returns the correct db' do
        expect(subject).to eq(redis_database)
      end
    end

    context 'with new format' do
      let(:config_file_name) { config_new_format_host }

      it 'returns the correct db' do
        expect(subject).to eq(redis_database)
      end
    end

    context 'with cluster-mode' do
      let(:config_file_name) { config_cluster_format_host }

      it 'returns the correct db' do
        expect(subject).to eq(0)
      end
    end
  end

  describe '#sentinels' do
    subject { described_class.new(rails_env).sentinels }

    let(:rails_env) { 'development' }

    context 'when sentinels are defined' do
      let(:config_file_name) { config_new_format_host }

      where(:rails_env, :hosts) do
        [
          ['development', %w[development-replica1 development-replica2]],
          ['test', %w[test-replica1 test-replica2]],
          ['production', %w[production-replica1 production-replica2]]
        ]
      end

      with_them do
        it 'returns an array of hashes with host and port keys' do
          is_expected.to include(host: hosts[0], port: sentinel_port)
          is_expected.to include(host: hosts[1], port: sentinel_port)
        end
      end
    end

    context 'when sentinels are not defined' do
      let(:config_file_name) { config_old_format_host }

      it 'returns nil' do
        is_expected.to be_nil
      end
    end

    context 'when cluster is defined' do
      let(:config_file_name) { config_cluster_format_host }

      it 'returns nil' do
        is_expected.to be_nil
      end
    end
  end

  describe '#sentinels?' do
    subject { described_class.new(Rails.env).sentinels? }

    context 'when sentinels are defined' do
      let(:config_file_name) { config_new_format_host }

      it 'returns true' do
        is_expected.to be_truthy
      end
    end

    context 'when sentinels are not defined' do
      let(:config_file_name) { config_old_format_host }

      it { expect(subject).to eq(nil) }
    end

    context 'when cluster is defined' do
      let(:config_file_name) { config_cluster_format_host }

      it 'returns false' do
        is_expected.to be_falsey
      end
    end
  end

  describe '#raw_config_hash' do
    it 'returns old-style single url config in a hash' do
      expect(subject).to receive(:fetch_config) { test_redis_url }
      expect(subject.send(:raw_config_hash)).to eq(url: test_redis_url)
    end

    it 'returns cluster config without url key in a hash' do
      expect(subject).to receive(:fetch_config) { test_cluster_config }
      expect(subject.send(:raw_config_hash)).to eq(test_cluster_config)
    end
  end

  describe '#secret_file' do
    context 'when explicitly specified in config file' do
      it 'returns the absolute path of specified file inside Rails root' do
        allow(subject).to receive(:raw_config_hash).and_return({ secret_file: '/etc/gitlab/redis_secret.enc' })
        expect(subject.send(:secret_file)).to eq('/etc/gitlab/redis_secret.enc')
      end
    end

    context 'when not explicitly specified' do
      it 'returns the default path in the encrypted settings shared directory' do
        expect(subject.send(:secret_file)).to eq(Rails.root.join("shared/encrypted_settings/redis.yaml.enc").to_s)
      end
    end
  end

  describe "#parse_client_tls_options" do
    let(:dummy_certificate) { OpenSSL::X509::Certificate.new }
    let(:dummy_key) { OpenSSL::PKey::RSA.new }
    let(:resque_yaml_config_without_tls) { { url: 'redis://localhost:6379' } }
    let(:resque_yaml_config_with_tls) do
      {
        url: 'rediss://localhost:6380',
        ssl_params: {
          cert_file: '/tmp/client.crt',
          key_file: '/tmp/client.key'
        }
      }
    end

    let(:resque_yaml_config_with_only_cert) do
      {
        url: 'rediss://localhost:6380',
        ssl_params: {
          cert_file: '/tmp/client.crt'
        }
      }
    end

    let(:resque_yaml_config_with_only_key) do
      {
        url: 'rediss://localhost:6380',
        ssl_params: {
          key_file: '/tmp/client.key'
        }
      }
    end

    let(:parsed_config_with_tls) do
      {
        url: 'rediss://localhost:6380',
        ssl_params: {
          cert: dummy_certificate,
          key: dummy_key
        }
      }
    end

    let(:parsed_config_with_only_cert) do
      {
        url: 'rediss://localhost:6380',
        ssl_params: {
          cert: dummy_certificate
        }
      }
    end

    let(:parsed_config_with_only_key) do
      {
        url: 'rediss://localhost:6380',
        ssl_params: {
          key: dummy_key
        }
      }
    end

    before do
      allow(::File).to receive(:exist?).and_call_original
      allow(::File).to receive(:read).and_call_original
    end

    context 'when configuration does not have TLS related options' do
      it 'returns the coniguration as-is' do
        expect(subject.send(:parse_client_tls_options,
          resque_yaml_config_without_tls)).to eq(resque_yaml_config_without_tls)
      end
    end

    context 'when specified certificate file does not exist' do
      before do
        allow(::File).to receive(:exist?).with("/tmp/client.crt").and_return(false)
        allow(::File).to receive(:exist?).with("/tmp/client.key").and_return(true)
      end

      it 'raises error about missing certificate file' do
        expect do
          subject.send(:parse_client_tls_options,
            resque_yaml_config_with_tls)
        end.to raise_error(Gitlab::Redis::Wrapper::InvalidPathError,
          "Certificate file /tmp/client.crt specified in in `resque.yml` does not exist.")
      end
    end

    context 'when specified key file does not exist' do
      before do
        allow(::File).to receive(:exist?).with("/tmp/client.crt").and_return(true)
        allow(::File).to receive(:read).with("/tmp/client.crt").and_return("DUMMY_CERTIFICATE")
        allow(OpenSSL::X509::Certificate).to receive(:new).with("DUMMY_CERTIFICATE").and_return(dummy_certificate)
        allow(::File).to receive(:exist?).with("/tmp/client.key").and_return(false)
      end

      it 'raises error about missing key file' do
        expect do
          subject.send(:parse_client_tls_options,
            resque_yaml_config_with_tls)
        end.to raise_error(Gitlab::Redis::Wrapper::InvalidPathError,
          "Key file /tmp/client.key specified in in `resque.yml` does not exist.")
      end
    end

    context 'when only certificate file is specified' do
      before do
        allow(::File).to receive(:exist?).with("/tmp/client.crt").and_return(true)
        allow(::File).to receive(:read).with("/tmp/client.crt").and_return("DUMMY_CERTIFICATE")
        allow(OpenSSL::X509::Certificate).to receive(:new).with("DUMMY_CERTIFICATE").and_return(dummy_certificate)
        allow(::File).to receive(:exist?).with("/tmp/client.key").and_return(false)
      end

      it 'renders resque.yml correctly' do
        expect(subject.send(:parse_client_tls_options,
          resque_yaml_config_with_only_cert)).to eq(parsed_config_with_only_cert)
      end
    end

    context 'when only key file is specified' do
      before do
        allow(::File).to receive(:exist?).with("/tmp/client.crt").and_return(false)
        allow(::File).to receive(:exist?).with("/tmp/client.key").and_return(true)
        allow(::File).to receive(:read).with("/tmp/client.key").and_return("DUMMY_KEY")
        allow(OpenSSL::PKey).to receive(:read).with("DUMMY_KEY").and_return(dummy_key)
      end

      it 'renders resque.yml correctly' do
        expect(subject.send(:parse_client_tls_options,
          resque_yaml_config_with_only_key)).to eq(parsed_config_with_only_key)
      end
    end

    context 'when configuration valid TLS related options' do
      before do
        allow(::File).to receive(:exist?).with("/tmp/client.crt").and_return(true)
        allow(::File).to receive(:exist?).with("/tmp/client.key").and_return(true)
        allow(::File).to receive(:read).with("/tmp/client.crt").and_return("DUMMY_CERTIFICATE")
        allow(::File).to receive(:read).with("/tmp/client.key").and_return("DUMMY_KEY")
        allow(OpenSSL::X509::Certificate).to receive(:new).with("DUMMY_CERTIFICATE").and_return(dummy_certificate)
        allow(OpenSSL::PKey).to receive(:read).with("DUMMY_KEY").and_return(dummy_key)
      end

      it "converts cert_file and key_file appropriately" do
        expect(subject.send(:parse_client_tls_options, resque_yaml_config_with_tls)).to eq(parsed_config_with_tls)
      end
    end
  end

  describe '#fetch_config' do
    before do
      FileUtils.mkdir_p(File.join(rails_root, 'config'))
      # Undo top-level stub of config_file_name because we are testing that method now.
      allow(described_class).to receive(:config_file_name).and_call_original
      allow(described_class).to receive(:rails_root).and_return(rails_root)
    end

    it 'raises an exception when the config file contains invalid yaml' do
      Tempfile.open('bad.yml') do |file|
        file.write('{"not":"yaml"')
        file.flush
        allow(described_class).to receive(:config_file_name) { file.path }

        expect { subject.send(:fetch_config) }.to raise_error(Psych::SyntaxError)
      end
    end

    context 'when redis.yml exists' do
      subject { described_class.new('test').send(:fetch_config) }

      before do
        allow(described_class).to receive(:redis_yml_path).and_call_original
      end

      it 'uses config/redis.yml' do
        File.write(File.join(rails_root, 'config/redis.yml'), {
          'test' => { described_class.store_name.underscore => { 'foobar' => 123 } }
        }.to_json)

        expect(subject).to eq({ 'foobar' => 123 })
      end
    end

    context 'when no config file exsits' do
      subject { described_class.new('test').send(:fetch_config) }

      it 'returns nil' do
        expect(subject).to eq(nil)
      end

      context 'when resque.yml exists' do
        before do
          FileUtils.mkdir_p(File.join(rails_root, 'config'))
          File.write(File.join(rails_root, 'config/resque.yml'), {
            'test' => { 'foobar' => 123 }
          }.to_json)
        end

        it 'returns the config from resque.yml' do
          expect(subject).to eq({ 'foobar' => 123 })
        end
      end
    end
  end

  def clear_pool
    described_class.remove_instance_variable(:@pool)
  rescue NameError
    # raised if @pool was not set; ignore
  end
end
