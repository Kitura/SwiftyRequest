
Pod::Spec.new do |s|
  s.name        = "SwiftyRequest"
  s.version     = "2.2.1"
  s.summary     = "SwiftyRequest is an HTTP networking library built for Swift."
  s.homepage    = "https://github.com/IBM-Swift/SwiftyRequest"
  s.license     = { :type => "Apache License, Version 2.0" }
  s.author     = "IBM"
  s.module_name  = 'SwiftyRequest'
  s.ios.deployment_target = "10.0"
  s.osx.deployment_target = "10.11"
  s.source   = { :git => "https://github.com/IBM-Swift/SwiftyRequest.git", :tag => s.version }
  s.source_files = "Sources/**/*.swift"
  s.dependency 'LoggerAPI', '~> 1.7'
  s.dependency 'IBMSwiftCircuitBreaker', '~> 5.0'
end
