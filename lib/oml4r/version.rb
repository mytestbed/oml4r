# Copyright (c) 2009 - 2014 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of the MIT license (License).
# You should find a copy of the License in LICENSE.TXT or at http://opensource.org/licenses/MIT.
# By downloading or using this software you accept the terms and the liability disclaimer in the License.
# ------------------

module OML4R

  # NOTE: The version number is now derived automatically from Git tags. This
  # file needs not be modified.
  # To create a new release, use git tag -asm "DESC" v2.m.r (make sure the
  # feature set corresponds to that of liboml2-2.m).
  def self.version_of(name)
    git_tag  = `git describe --tags 2> /dev/null`.chomp
    git_root = `git rev-parse --show-toplevel 2> /dev/null`.chomp
    gem_v = Gem.loaded_specs[name].version.to_s rescue '0.0.0'

    # Not in a development environment or git not present
    if git_root != File.absolute_path("#{File.dirname(__FILE__)}/../../") || git_tag.empty?
      gem_v
    else
      git_tag.gsub(/-/, '.').gsub(/^v/, '')
    end
  end

  VERSION = version_of('oml4r')
  VERSION_STRING = "OML4R Client V#{VERSION}"
  COPYRIGHT = "Copyright 2009-2014, NICTA"
end

# vim: ft=ruby:sw=2
