source "https://rubygems.org"

# Release automation. Run lanes with `bundle exec fastlane <platform> <lane>`.
gem "fastlane"

# CocoaPods must be in the bundle: ruby/setup-ruby activates this Ruby, which
# hides the runner's system-Ruby CocoaPods, so `flutter build ipa` -> pod install
# would otherwise fail with "CocoaPods not installed or not in valid state."
gem "cocoapods", ">= 1.16"
