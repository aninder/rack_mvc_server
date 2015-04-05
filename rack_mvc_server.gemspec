# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rack_mvc_server/version'

Gem::Specification.new do |spec|
  spec.name          = "rack_mvc_server"
  spec.version       = RackMvcServer::VERSION
  spec.authors       = ["aninder"]
  spec.email         = ["aninder@gmail.com"]
  spec.summary       = %q{rack mvc server}
  spec.description   = %q{rack mvc server}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_dependency "mono_logger", "~> 1.1.0"
  spec.add_dependency "rack"
end
