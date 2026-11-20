# Embeds the optional native proofing backends as signed dynamic frameworks.
#
# Each package's tool/build.py --ios --install-ios <this directory>/Frameworks
# writes <name>.xcframework here (git-ignored build output). CocoaPods' embed
# phase copies the slice for the current SDK into Runner.app/Frameworks and
# signs it with the app's identity; Dart opens
# `<name>.framework/<name>`. A missing framework only makes that backend
# report itself unavailable, exactly like an unbuilt desktop library.
Pod::Spec.new do |s|
  s.name = 'QudsProofingNative'
  s.version = '1.0.0'
  s.summary = 'Optional native proofing backends (Hunspell, Arabic morphology, CLD3, Harper, spaCy).'
  s.homepage = 'https://github.com/CrispStrobe/quds_office_suite'
  s.license = { :type => 'MIT AND MPL-1.1 (see app licence assets)' }
  s.author = 'Quds Office'
  s.source = { :path => '.' }
  s.platform = :ios, '13.0'
  frameworks = Dir.glob(File.join(__dir__, 'Frameworks', '*.xcframework')).sort.map do |path|
    path.delete_prefix("#{__dir__}/")
  end
  s.vendored_frameworks = frameworks unless frameworks.empty?
  # Keep the pod non-empty for CocoaPods when no backend has been built.
  s.source_files = 'Sources/*.{h,m}'
end
