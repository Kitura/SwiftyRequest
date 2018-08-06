podspec="Pod::Spec.new do |s|\ns.name        = \"$projectName\"\ns.version     = \"$TRAVIS_TAG\"\ns.summary     = \"$TRAVIS_DESCRIPTION\"\ns.homepage    = \"https://github.com/IBM-Swift/$projectName\"\ns.license     = { :type => \"Apache License, Version 2.0\" }\ns.author     = \"IBM\"\ns.module_name  = '$projectName'\ns.requires_arc = true\ns.ios.deployment_target = \"10.0\"\ns.source   = { :git => \"https://github.com/IBM-Swift/$projectName.git\", :tag => s.version }\ns.source_files = \"Sources/$projectName/*.swift\"\ns.pod_target_xcconfig =  {\n'SWIFT_VERSION' => '4.0.3',\n}"

# Check that a Package.swift file exists, extract dependencies, and use within the podspec file
if [ -e "Package.swift" ]; then
echo "Package.swift file found, may contain dependencies."
# Get and append name of dependencies from the Package.swift file
dependencies=$(grep -Eo "IBM-Swift/(.+?).git" Package.swift | sed -E "s|IBM-Swift/||g" | sed -E "s|.git||g")
while read -r line; do
podspec="$podspec\ns.dependency '$line'"
done <<< "$dependencies"
podspec="$podspec\nend"
else
podspec="$podspec\nend"
fi
podFile="pods.podspec"
touch "$podFile"
echo "$podspec" >> "$podFile"
