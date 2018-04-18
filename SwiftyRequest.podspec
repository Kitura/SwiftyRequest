
Pod::Spec.new do |s|
  s.name        = "SwiftyRequest"
  s.version     = "1.0.0"
  s.summary     = "SwiftyRequest is an HTTP networking library built for Swift."
  s.homepage    = "https://github.com/IBM-Swift/SwiftyRequest"
  s.license     = { :type => "Apache License, Version 2.0" }
  s.author     = "IBM"
  s.module_name  = 'SwiftyRequest'
  s.requires_arc = true
  s.ios.deployment_target = "10.0"
  s.source   = { :git => "https://github.com/IBM-Swift/SwiftyRequest.git", :tag => s.version }
  s.source_files = "Sources/SwiftyRequest/*.swift"
  s.pod_target_xcconfig =  {
        'SWIFT_VERSION' => '4.0.3',
  }
  s.dependency 'CircuitBreaker', '~> 5.0.1'
  s.dependency 'LoggerAPI', '~> 1.7.2'
end