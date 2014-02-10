#!/usr/bin/env ruby

require 'spec_helper'
require 'puppet/file_bucket/dipper'
require 'puppet_spec/compiler'

describe Puppet::Type.type(:cron).provider(:crontab), '(integration)', :unless => Puppet.features.microsoft_windows? do
  include PuppetSpec::Files

  before :each do
    Puppet::Type.type(:cron).stubs(:defaultprovider).returns described_class
    Puppet::FileBucket::Dipper.any_instance.stubs(:backup) # Don't backup to filebucket

    # I don't want to execute anything
    described_class.stubs(:filetype).returns Puppet::Util::FileType::FileTypeFlat
    described_class.stubs(:default_target).returns crontab_user1

    # I don't want to stub Time.now to get a static header because I don't know
    # where Time.now is used elsewhere, so just go with a very simple header
    described_class.stubs(:header).returns "# HEADER: some simple\n# HEADER: header\n"
    FileUtils.cp(my_fixture('crontab_user1'), crontab_user1)
    FileUtils.cp(my_fixture('crontab_user2'), crontab_user2)
  end

  after :each do
    described_class.clear
  end

  let :crontab_user1 do
    tmpfile('cron_integration_specs')
  end

  let :crontab_user2 do
    tmpfile('cron_integration_specs')
  end

  include PuppetSpec::Compiler
  def compile_and_run(node = Puppet::Node.new('the node'))
    catalog = compile_to_catalog(yield, node)
    catalog.host_config = false
    catalog.resources.each do |resource|
      resource.expects(:err).never
    end
    catalog.apply
  end

  def expect_output(fixture_name)
    File.read(crontab_user1).should == File.read(my_fixture(fixture_name))
  end

  describe "when managing a cron entry" do

    it "should be able to purge unmanaged entries" do
      compile_and_run do <<-MANIFEST
        cron { 'only managed entry':
          ensure      => present,
          command     => '/bin/true',
          target      => crontab_user1,
          user        => crontab_user1
        }
        resources { 'cron': purge => 'true' }
        MANIFEST
      end
      #expect_output('purged')
    end

    describe "with ensure absent" do
      it "should do nothing if entry already absent" do
        compile_and_run do <<-MANIFEST
          cron { 'no_such_entry':
            ensure => absent,
            target => crontab_user1,
            user   => crontab_user1
          }
          MANIFEST
        end
        expect_output('crontab_user1')
      end

      it "should remove the resource from crontab if present" do
        compile_and_run do <<-MANIFEST
          cron { 'My daily failure':
            ensure => absent,
            target => crontab_user1,
            user   => crontab_user1
          }
          MANIFEST
        end
        expect_output('remove_named_resource')
      end

      it "should remove a matching cronentry if present" do
        compile_and_run do <<-MANIFEST
          cron { 'no_such_named_resource_in_crontab':
            ensure   => absent,
            minute   => [ '17-19', '22' ],
            hour     => [ '0-23/2' ],
            weekday  => 'Tue',
            command  => '/bin/unnamed_regular_command',
            target   => crontab_user1,
            user     => crontab_user1
          }
          MANIFEST
        end
        expect_output('remove_unnamed_resource')
      end
    end

    describe "with ensure present" do
      it "should do nothing if entry already present" do
        compile_and_run do <<-MANIFEST
          cron { 'My daily failure':
            special => 'daily',
            command => '/bin/false',
            target  => crontab_user1,
            user    => crontab_user1
          }
          MANIFEST
        end
        expect_output('crontab_user1')
      end

      it "should do nothing if a matching entry already present" do
        compile_and_run do <<-MANIFEST
          cron { 'no_such_named_resource_in_crontab':
            ensure   => present,
            minute   => [ '17-19', '22' ],
            hour     => [ '0-23/2' ],
            command  => '/bin/unnamed_regular_command',
            target   => crontab_user1,
            user     => crontab_user1
          }
          MANIFEST
        end
        expect_output('crontab_user1')
      end

      it "should add a new normal entry if currently absent" do
        compile_and_run do <<-MANIFEST
          cron { 'new entry':
            ensure      => present,
            minute      => '12',
            weekday     => 'Tue',
            command     => '/bin/new',
            environment => [
              'MAILTO=""',
              'SHELL=/bin/bash'
            ],
            target      => crontab_user1,
            user        => crontab_user1
          }
          MANIFEST
        end
        expect_output('create_normal_entry')
      end

      it "should add a new special entry if currently absent" do
        compile_and_run do <<-MANIFEST
          cron { 'new special entry':
            ensure      => present,
            special     => 'reboot',
            command     => 'echo "Booted" 1>&2',
            environment => 'MAILTO=bob@company.com',
            target      => crontab_user1,
            user        => crontab_user1
          }
          MANIFEST
        end
        expect_output('create_special_entry')
      end

      it "should change existing entry if out of sync" do
        compile_and_run do <<-MANIFEST
          cron { 'Monthly job':
            ensure      => present,
            special     => 'monthly',
#           minute => ['22'],
            command     => '/usr/bin/monthly',
            environment => [],
            target      => crontab_user1,
            user        => crontab_user1
          }
          MANIFEST
        end
        expect_output('modify_entry')
      end

      it "should change a special schedule to numeric if requested" do
        compile_and_run do <<-MANIFEST
          cron { 'My daily failure':
            special     => 'absent',
            command     => '/bin/false',
            target      => crontab_user1,
            user        => crontab_user1
          }
          MANIFEST
        end
        expect_output('unspecialized')
      end

      it "should not try to move an entry from one file to another" do
        # force the parsedfile provider to also parse user1's crontab
        compile_and_run do <<-MANIFEST
          cron { 'foo':
            ensure => absent,
            target => crontab_user1,
            user   => crontab_user1
          }
          cron { 'My daily failure':
            special      => 'daily',
            command      => "/bin/false",
            target       => crontab_user2,
            user         => crontab_user2
          }
          MANIFEST
        end
        File.read(crontab_user1).should == File.read(my_fixture('moved_cronjob_input1'))
        File.read(crontab_user2).should == File.read(my_fixture('moved_cronjob_input2'))
      end
    end
  end

end
