require 'rubygems'
require 'rake'
require 'echoe'

Echoe.new('hotmailer', '1.0.1') do |p|
  p.description    = "Generate a unique token with Active Record."
  p.url            = "https://github.com/luongtran/hotmailer"
  p.author         = "Unkown"
  p.email          = "unknown@gmail.com"
  p.ignore_pattern = ["tmp/*", "script/*"]
  p.development_dependencies = []
end

Dir["#{File.dirname(__FILE__)}/tasks/*.rake"].sort.each { |ext| load ext }