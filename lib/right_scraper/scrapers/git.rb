#--
# Copyright: Copyright (c) 2010 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to 
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, 
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++
require File.expand_path(File.join(File.dirname(__FILE__), 'base'))
require 'git'
require 'libarchive_ruby'
require 'tmpdir'

module RightScale

  class NewGitScraper < NewScraperBase
    def initialize(*args)
      super
      @tmpdir = Dir.mktmpdir
      @git = Git.clone(@repository.url, @tmpdir)
      @git.checkout(@repository.tag) if @repository.tag
      @stack = []
      rewind
    end

    def checkout_path
      @tmpdir
    end

    # Remove the temporary git checkout we made.
    def close
      @stack.each {|s| s.close}
      FileUtils.remove_entry_secure @tmpdir
    end

    def rewind
      @stack.each {|s| s.close}
      @stack = [Dir.open(@tmpdir)]
    end

    # Return the position of the scraper.  Here, the position is the
    # path relative from the top of the repository of the cookbook.
    def position
      return strip_tmpdir(@stack.last.path)
    end

    def strip_tmpdir(path)
      res = path[@tmpdir.length+1..-1]
      if res == nil || res == ""
        "."
      else
        res
      end
    end

    # Seek to the given position.
    def seek(position)
      dirs = position.split(File::SEPARATOR)
      rewind
      until dirs.empty?
        name = dirs.shift
        dir = @stack.last
        entry = dir.read
        until entry == nil || entry == name
          entry = dir.read
        end
        raise "Position #{position} no longer exists!" if entry == nil
        @stack << Dir.open(File.join(dir.path, name))
      end
      @stack.last.rewind # to make sure we don't miss a metadata.json here.
    end

    def next
      until @stack.empty?
        dir = @stack.last
        entry = dir.read
        if entry == nil
          dir.close
          @stack.pop
          next
        end

        fullpath = File.join(dir.path, entry)

        next if entry == '.' || entry == '..' || entry == '.git'

        if File.directory?(fullpath)
          @stack << Dir.new(fullpath)
          next
        elsif entry == 'metadata.json'
          cookbook = RightScale::Cookbook.new(@repository, nil, nil, position)

          cookbook.metadata = JSON.parse(open(fullpath) {|f| f.read })

          # make new archive rooted here
          cookbook.archive =
            watch("tar -C #{File.dirname fullpath} -c --exclude .git .")

          return cookbook
        end 
      end
      nil
    end
  end
end