#!/usr/bin/env ruby

require 'aws'
require 'optparse'

class Launcher

  INSTANCE_TYPES = %w[
    t1.micro
    m1.small
    m1.medium
    m1.large
    m1.xlarge
    c1.medium
    c1.xlarge
    m2.xlarge
    m2.2xlarge
    m2.4xlarge
    cc1.4xlarge
    cc2.8xlarge
    cg1.4xlarge]

  # Hash of Ubuntu 12.04 AMIs by availability zone.
  # Array is in order 64-bit ebs, 64-bit instance, 32-bit ebs, 32-bit instance
  UBUNTU_AMIS = {
    :"ap-northeast-1" =>
      %w[ami-c641f2c7
         ami-ac41f2ad
         ami-c441f2c5
         ami-4041f241],

    :"ap-southeast-1" =>
      %w[ami-acf6b0fe
         ami-a6f6b0f4
         ami-aaf6b0f8
         ami-b8f6b0ea],

    :"eu-west-1" =>
      %w[ami-ab9491df
         ami-b39491c7
         ami-a99491dd
         ami-d19491a5],

    :"sa-east-1" =>
      %w[ami-5c03dd41
         ami-2a03dd37
         ami-2203dd3f
         ami-2e03dd33],

    :"us-east-1" =>
      %w[ami-82fa58eb
         ami-eafa5883
         ami-8cfa58e5
         ami-4efa5827],

    :"us-west-1" =>
      %w[ami-5965401c
         ami-bfe5bffa
         ami-5d654018
         ami-a7e5bfe2],

    :"us-west-2" =>
      %w[ami-4438b474
         ami-5238b462
         ami-4038b470
         ami-6038b450],
  }

  def initialize(options)
    @options = options
    @ec2 = AWS::EC2.new(:access_key_id => ENV["AWS_ACCESS_KEY_ID"],
                        :secret_access_key => ENV["AWS_SECRET_ACCESS_KEY"])
  end

  def interactive!
    # Choose region to select zone from
    puts "Which region do you want to deploy in?"
    regions = @ec2.regions.map(&:name)
    regions.each_with_index do |r, i|
      puts "[#{i + 1}] #{r}"
    end
    print "[1-#{regions.size}]? "
    region = @ec2.regions[regions[gets.strip.to_i - 1]]

    azs = region.availability_zones.map(&:name)
    puts "Which availability zone in #{region.name}?"
    azs.each_with_index do |z, i|
      puts "[#{i + 1}] #{z}"
    end
    puts ""
    print "[1-#{azs.size}]? "
    @options[:zone] = azs[gets.strip.to_i - 1]

    puts "Which security group should the instance belong to?"
    groups = region.security_groups.map(&:name)
    groups.each_with_index do |g, i|
      puts "[#{i + 1}] #{g}"
    end
    puts ""
    print "[1-#{groups.size}]? "
    @options[:group] = groups[gets.strip.to_i - 1]

    puts "Which instance type would you like to deploy?"
    INSTANCE_TYPES.each_with_index do |t, i|
      puts "[#{i + 1}] #{t}"
    end
    puts ""
    print "[1-#{INSTANCE_TYPES.size}]? "
    @options[:instance_type] = INSTANCE_TYPES[gets.strip.to_i - 1]

    puts "Which architecture would you like?"
    puts "[1] 64-bit"
    puts "[2] 32-bit"
    print "[1-2]? "
    @options[:arch] = gets.strip.to_i - 1

    puts "Which root storage would you like?"
    puts "[1] ebs"
    puts "[2] instance"
    print "[1-2]? "
    @options[:arch] = gets.strip.to_i - 1

    # Choose region to select zone from
    puts "Which security key will you use?"
    puts "[0] Upload new key"
    keys = region.key_pairs.map(&:name)
    keys.each_with_index do |k, i|
      puts "[#{i + 1}] #{k}"
    end
    print "[0-#{keys.size}]? "
    kid = gets.strip.to_i
    if kid == 0
      print "Key name (#{`hostname`.strip})? "
      keyname = gets.strip
      keyname = `hostname`.strip if keyname.empty?
      print "Key location (~/.ssh/id_rsa.pub)? "
      keyloc = gets.strip
      keyloc = "~/.ssh/id_rsa.pub" if keyloc.empty?
      kp = region.key_pairs.import(keyname, File.read(File.expand_path(keyloc)))
      @options[:key_name] = kp.name
    else
      @options[:key_name] = keys[kid - 1]
    end
  end

  def launch!
    if @options[:interactive]
      interactive!
    end
    region = @ec2.regions[@options[:zone][0..-2]]
    ami = UBUNTU_AMIS[region.name.to_sym][@options[:arch] * 2 + @options[:store]]
    instance = region.instances.create(
                          :image_id => ami,
                          :availability_zone => @options[:zone],
                          :security_groups => @options[:group],
                          :instance_type => @options[:instance_type],
                          :key_name => @options[:key_name])
    sleep 1 while instance.status == :pending
    if block_given?
      yield(instance)
    else
      puts instance.dns_name
    end
  end

end

options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} hostname [options]"

  options[:interactive] = false
  opts.on("-i", "--interactive", "Ask for options interactively") do
    options[:interactive] = true
  end

  options[:zone] = "us-east-1a"
  opts.on("-z", "--zone AVAILABILITY_ZONE", "Availability zone to use") do |zone|
    options[:zone] = zone
  end

  opts.on("-k", "--key KEY_NAME", "Security key name") do |key|
    options[:key_name] = key
  end

  options[:group] = "default"
  opts.on("-g", "--group SECURITY_GROUP", "Security group to launch in") do |group|
    options[:group] = group
  end

  options[:instance_type] = "t1.micro"
  opts.on("-t", "--type INSTANCE_TYPE", "Instance type (t1.micro, m1.small...)") do |type|
    options[:instance_type] = type
  end

  options[:arch] = 0
  opts.on("-a", "--arch [64|32]", "Architecture") do |arch|
    if arch == "32"
      options[:arch] = 1
    elsif arch == "64"
      options[:arch] = 0
    else
      $stderr.puts "Invalid architecture: #{arch}"
      exit(1)
    end
  end

  options[:store] = 0
  opts.on("-s", "--store [ebs|instance]", "Root storage type") do |store|
    if store == "instance"
      options[:store] = 1
    elsif arch == "ebs"
      options[:store] = 0
    else
      $stderr.puts "Invalid store: #{store}"
      exit(1)
    end
  end
end

optparse.parse!

Launcher.new(options).launch!

