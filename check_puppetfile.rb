#!/usr/bin/env ruby
# Author: NWOPS, LLC <automation@nwops.io>
# Purpose: Vaiidate the git urls and branches, refs, or tags in the Puppetfile
# Date: 1/14/19
# outputs 1 if Puppetfile is invalid, 0 otherwise
# Usage: ./check_puppetfile.rb [path_to_puppetfile]
# Example Output
#
# NAME     | URL                                           | REF                            | STATUS
# ---------|-----------------------------------------------|--------------------------------|-------
# splunk   | https://github.com/cudgel/splunk.git          | prod                           | 👍
# r10k     | https://github.com/acidprime/r10k             | v3.1.1                         | 👍
# gms      | https://github.com/npwalker/abrader-gms       | gitlab_disable_ssl_verify_s... | 👍
# rbac     | https://github.com/puppetlabs/pltraining-rbac | 2f60e1789a721ce83f8df061e13... | 👍
# acl      | https://github.com/dobbymoodge/puppet-acl.git | master                         | 👍
# deploy   | https://github.com/cudgel/deploy.git          | master                         | 👍
# dotfiles | https://github.com/cudgel/puppet-dotfiles.git | master                         | 👍
# gitlab   | https://github.com/vshn/puppet-gitlab         | 00397b86dfb3487d9df768cbd36... | 👍
#
# 👍👍 Puppetfile looks good.👍👍
begin
  require 'tempfile'
  require 'table_print'
rescue LoadError
  puts "You may need to install the table_print gem"
  puts "gem install table_print"
  require 'bundler/inline'
  gemfile do
    source 'https://rubygems.org'
    gem 'table_print', require: true
  end
end

class String
  # colorization
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end
end

# @return [Array] - returns a array of hashes that contain modules with a git source
def git_modules(puppetfile)
  modules.find_all do |mod|
    mod[:args].keys.include?(:git)
  end
end

# @param puppetfile [String] - the absolute path to the puppetfile
# @return [Array] - returns an array of module hashes that represent the puppetfile
# @example
# [{:namespace=>"puppetlabs", :name=>"stdlib", :args=>[]},
# {:namespace=>"petems", :name=>"swap_file", :args=>["'4.0.0'"]}]
def modules(puppetfile = File.expand_path('./Puppetfile'))
  @modules ||= begin
    return [] unless File.exist?(puppetfile)
    all_lines = File.read(puppetfile).lines
    # remove comments from all the lines
    lines_without_comments = all_lines.reject {|line| line.match(/#.*\n/) }.join("\n").gsub(/\n/,'')
    lines_without_comments.split('mod').map do |line|
      next nil if line =~ /^forge/
      parse_module_args(line)
    end.compact.uniq
  end
end

# @param data [String] - the string to parse the puppetfile args out of
# @return [Array] -  an array of arguments in hash form
# @example
# {:namespace=>"puppetlabs", :name=>"stdlib", :args=>[]}
# {:namespace=>"petems", :name=>"swap_file", :args=>["'4.0.0'"]}
def parse_module_args(data)
  args = data.split(',').map(&:strip)
  # we can't guarantee that there will be a namespace when git is used
  # remove quotes and dash and slash
  namespace, name = args.shift.gsub(/'|"/, '').split(/-|\//)
  name ||= namespace
  namespace = nil if namespace == name
  {
      namespace: namespace,
      name: name,
      args: process_args(args)
  }
end

# @return [Array] - returns an array of hashes with the args in key value pairs
# @param [Array] - the arguments processed from each entry in the puppetfile
# @example
# [{:args=>[], :name=>"razor", :namespace=>"puppetlabs"},
#  {:args=>[{:version=>"0.0.3"}], :name=>"ntp", :namespace=>"puppetlabs"},
#  {:args=>[], :name=>"inifile", :namespace=>"puppetlabs"},
#  {:args=>
#    [{:git=>"https://github.com/nwops/reportslack.git"}, {:ref=>"1.0.20"}],
#   :name=>"reportslack",
#   :namespace=>"nwops"},
#  {:args=>{:git=>"git://github.com/puppetlabs/puppetlabs-apt.git"},
#   :name=>"apt",
#   :namespace=>nil}
# ]
def process_args(args)
  results = {}
  args.each do |arg|
    a = arg.gsub(/'|"/, '').split(/\A\:|\:\s|\=\>/).map(&:strip).reject(&:empty?)
    if a.count < 2
      results[:version] = a.first
    else
      results[a.first.to_sym] = a.last
    end
  end
  results
end

# @return [Boolean] - return true if the ref is valid
# @param url [String] - the git string either https or ssh url
# @param ref [String] - the ref object, branch name, tag name, or commit sha, defaults to HEAD
def valid_ref?(url, ref = 'HEAD')
  raise ArgumentError unless ref
  `git ls-remote --symref #{url} |grep #{ref}`
  $?.success?
end

# @return [Boolean] - return true if the commit sha is valid
# @param url [String] - the git string either https or ssh url
# @param ref [String] - the sha id
def valid_commit?(url, sha)
  return false if sha.nil? || sha.empty?
  puts "Warning: consider pinning #{url} to tag if possible.".yellow
  Dir.mktmpdir do |dir|
    `git clone --no-tags #{url} #{dir} 2>&1 > /dev/null`
    Dir.chdir(dir) do
      `git show #{sha} 2>&1 > /dev/null`
      $?.success?
    end
  end

end

puppetfile = ARGV.first || File.expand_path('./Puppetfile')

unless File.exist?(puppetfile)
  puts "puppetfile does not exist"
  puts "💩"
  exit 1
end

all_modules = git_modules(puppetfile).map do |mod|
  ref = mod[:args][:ref] || mod[:args][:tag] || mod[:args][:branch]
  valid_ref = valid_ref?(mod[:args][:git], ref ) || valid_commit?(mod[:args][:git], mod[:args][:ref])
  {
      name: mod[:name],
      url: mod[:args][:git],
      ref: ref,
      valid_ref?: valid_ref,
      status: valid_ref ? "👍" : "😨"
  }
end

exit_code = 0
bad_mods = all_modules.find_all {|mod| !mod[:valid_ref?]}.count > 0

if bad_mods
  exit_code = 1
  message = "😨😨 " + "Not all modules in the Puppetfile are valid.".red + " 😨😨"
else
  message = "👍👍 " + "Puppetfile looks good.".green +  "👍👍"
end



sorted = all_modules.sort_by {|a| a[:valid_ref?] ? 1 : 0 }
tp sorted, :name, {url: {:width => 50}}, :ref, :status
puts ""
puts message
exit exit_code
