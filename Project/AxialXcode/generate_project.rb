require 'xcodeproj'
require 'fileutils'

directory = __dir__
root = File.expand_path('../..', directory)
project = Xcodeproj::Project.new(File.join(directory, 'Axial.xcodeproj'))
project.root_object.attributes['LastUpgradeCheck'] = '2700'
project.root_object.attributes['TargetAttributes'] = {}
project.build_configurations.each do |configuration|
  configuration.build_settings.merge!(
    'SDKROOT' => 'macosx', 'SUPPORTED_PLATFORMS' => 'macosx',
    'MACOSX_DEPLOYMENT_TARGET' => '13.0', 'ARCHS' => 'arm64 x86_64',
    'ONLY_ACTIVE_ARCH' => 'NO', 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY' => 'libc++', 'CLANG_ENABLE_MODULES' => 'YES',
    'SWIFT_VERSION' => '5.0', 'CODE_SIGNING_ALLOWED' => 'NO'
  )
end

sources = project.main_group.new_group('Sources')
configs = project.main_group.new_group('Configuration')
scripts = project.main_group.new_group('Scripts')
%w[dependencies assets bundle framework].each do |name|
  scripts.new_file("scripts/#{name}.sh")
end

def source(group, path)
  group.new_file("../../#{path}")
end

def target(project, name, type, files, group, settings = {})
  item = project.new_target(type, name, :osx, '13.0')
  files.each do |path|
    item.source_build_phase.add_file_reference(source(group, path))
  end
  item.build_configurations.each do |configuration|
    configuration.build_settings.merge!(settings)
    configuration.build_settings['PRODUCT_NAME'] = name
    configuration.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  end
  item
end

def script(target, name, path)
  phase = target.new_shell_script_build_phase(name)
  phase.shell_script = "\"${PROJECT_DIR}/scripts/#{path}.sh\""
  phase.always_out_of_date = '1'
  phase
end

def link(target, other)
  target.add_dependency(other)
  target.frameworks_build_phase.add_file_reference(other.product_reference)
end

includes = '$(PROJECT_DIR)/../../include $(PROJECT_DIR)/../../third_party/freecad'
dependencies = '$(PROJECT_DIR)/Build/External'
boost = "#{dependencies}/_deps/axial_boost-src"
openssl = "#{dependencies}/tls/arm64/install/include"
common = {
  'HEADER_SEARCH_PATHS' => "$(inherited) #{includes}",
  'CLANG_ENABLE_OBJC_ARC' => 'YES'
}

bootstrap = project.new_aggregate_target('Dependencies', [], :osx, '13.0')
script(bootstrap, 'Build pinned Boost and OpenSSL', 'dependencies')
assets = project.new_aggregate_target('Assets', [], :osx, '13.0')
script(assets, 'Generate icon and model', 'assets')

bridge = target(project, 'axial-bridge', :static_library, ['app/bridge.cpp'], sources, common)
web = target(project, 'axial-web', :static_library, ['src/web.mm'], sources,
  common.merge('HEADER_SEARCH_PATHS' => "$(inherited) #{includes} #{boost} #{openssl}",
               'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) BOOST_ASIO_NO_DEPRECATED'))
web.add_dependency(bootstrap)

service = target(project, 'axial-service', :command_line_tool, ['src/service.mm'], sources,
  common.merge('LIBRARY_SEARCH_PATHS' => "$(inherited) #{dependencies}/tls",
               'OTHER_LDFLAGS' => '$(inherited) -lssl -lcrypto -lc++ -framework AppKit -framework IOKit -framework ApplicationServices -framework Foundation'))
link(service, web)
service.add_dependency(bootstrap)

cli = target(project, 'axialctl', :command_line_tool, ['src/ctl.cpp'], sources, common)
setup = target(project, 'axial-web-setup', :command_line_tool, ['src/web_setup.mm'], sources,
  common.merge('HEADER_SEARCH_PATHS' => "$(inherited) #{includes} #{openssl}",
               'LIBRARY_SEARCH_PATHS' => "$(inherited) #{dependencies}/tls",
               'OTHER_LDFLAGS' => '$(inherited) -lssl -lcrypto -lc++ -framework Foundation -framework Security'))
setup.add_dependency(bootstrap)

framework_targets = %w[Client Navlib].map do |adapter|
  name = "3Dconnexion#{adapter}"
  file = adapter == 'Client' ? 'src/connexion.mm' : 'src/navlib.mm'
  frameworks = adapter == 'Client' ? '-framework Foundation' : '-framework AppKit -framework CoreVideo'
  framework = target(project, name, :framework, [file], sources,
    common.merge('PRODUCT_BUNDLE_IDENTIFIER' => "pro.jest.#{name}",
                 'INFOPLIST_FILE' => "$(PROJECT_DIR)/Configuration/#{name}.plist",
                 'GENERATE_INFOPLIST_FILE' => 'NO', 'FRAMEWORK_VERSION' => 'A',
                 'DYLIB_INSTALL_NAME_BASE' => '/Library/Frameworks',
                 'OTHER_LDFLAGS' => "$(inherited) -lc++ #{frameworks}"))
  script(framework, 'Copy public headers and sign', 'framework')
  framework
end

app_files = Dir.glob(File.join(root, 'app/*.swift')).sort.map do |path|
  "app/#{File.basename(path)}"
end
app = target(project, 'Axial', :application, app_files, sources,
  common.merge('INFOPLIST_FILE' => '$(PROJECT_DIR)/Configuration/Axial.plist',
               'GENERATE_INFOPLIST_FILE' => 'NO',
               'PRODUCT_BUNDLE_IDENTIFIER' => 'pro.jest.Axial',
               'MARKETING_VERSION' => '0.2.3', 'CURRENT_PROJECT_VERSION' => '0.2.3',
               'OTHER_SWIFT_FLAGS' => '$(inherited) -parse-as-library',
               'OTHER_LDFLAGS' => '$(inherited) -lc++'))
link(app, bridge)
[service, cli, setup, assets, *framework_targets].each { |item| app.add_dependency(item) }
script(app, 'Assemble and sign app bundle', 'bundle')

FileUtils.mkdir_p(File.join(directory, 'Configuration'))
version = '0.2.3'
deployment = '13.0'
app_plist = File.read(File.join(root, 'app/Manifests/Axial.plist.in'))
  .gsub('@PROJECT_VERSION@', version)
  .gsub('@CMAKE_OSX_DEPLOYMENT_TARGET@', deployment)
File.write(File.join(directory, 'Configuration/Axial.plist'), app_plist)
%w[Client Navlib].each do |adapter|
  name = "3Dconnexion#{adapter}"
  plist = File.read(File.join(root, 'app/Manifests/Framework.plist.in'))
    .gsub('${MACOSX_FRAMEWORK_NAME}', name)
    .gsub('${MACOSX_FRAMEWORK_IDENTIFIER}', "pro.jest.#{name}")
    .gsub('${MACOSX_FRAMEWORK_BUNDLE_VERSION}', '1.0.0')
    .gsub('${MACOSX_FRAMEWORK_SHORT_VERSION_STRING}', '1.0.0')
  File.write(File.join(directory, "Configuration/#{name}.plist"), plist)
end
%w[Axial 3DconnexionClient 3DconnexionNavlib].each do |name|
  configs.new_file("Configuration/#{name}.plist")
end
project.save
{ 'Axial' => app, 'Dependencies' => bootstrap }.each do |name, item|
  scheme = Xcodeproj::XCScheme.new
  scheme.configure_with_targets(item, nil, launch_target: name == 'Axial')
  scheme.save_as(project.path, name)
end
